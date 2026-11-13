"""Check actual T gameplay measurements separately from native renderer acceptance."""
from pathlib import Path
import argparse
import json
import math
import re
import sys


def vector(value):
    if isinstance(value, str):
        result = [float(x) for x in re.findall(r"[-+]?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?", value)]
    elif isinstance(value, dict):
        result = [value[k] for k in ("x", "y", "z")]
    else:
        result = list(value)
    if len(result) != 3 or not all(math.isfinite(n) for n in result):
        raise ValueError("expected three finite Source vector/angle components")
    return result


def basis(value):
    p, y, r = (math.radians(n) for n in vector(value))
    sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return ((cp * cy, cp * sy, -sp), (-sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp),
            (cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp))


def angle_error(a, b):
    trace = sum(sum(x * y for x, y in zip(row_a, row_b)) for row_a, row_b in zip(basis(a), basis(b)))
    return math.degrees(math.acos(max(-1, min(1, (trace - 1) / 2))))


def rotation(value):
    forward, right, up = basis(value)
    return tuple(zip(forward, tuple(-x for x in right), up))


def transpose(matrix):
    return tuple(zip(*matrix))


def multiply(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def matrix_error(a, b):
    trace = sum(a[i][j] * b[i][j] for i in range(3) for j in range(3))
    return math.degrees(math.acos(max(-1, min(1, (trace - 1) / 2))))


def followed_rotation(body_at_pickup, hand_at_pickup, hand_now):
    return multiply(multiply(rotation(hand_now), transpose(rotation(hand_at_pickup))), rotation(body_at_pickup))


def pickup_orientation(records, server):
    exact = next((r for r in records if r["name"] == "pickup-orientation"), None)
    if exact:
        return {"time": exact["time"], "body": exact["body"], "hand": exact["hand"], "contact": exact.get("contact"), "entity": exact.get("entity"), "source": "native-pickup-hook"}
    # Earlier retained runs have complete pre-pickup samples of the gravity-free target.
    first = next((r for r in server if r.get("held") and r.get("class") == "weapon_physgun"), None)
    before = [r for r in server if first and r.get("time", -1) < first["time"] and r.get("exists") and
              not r.get("held") and r.get("ang") and r.get("hand", {}).get("valid")]
    if before:
        return {"time": before[-1]["time"], "body": before[-1]["ang"], "hand": before[-1]["hand"]["ang"], "source": "last-pre-pickup-sample"}


def tools(debug):
    if isinstance(debug, list):
        return next((x for x in debug if isinstance(x, dict) and x.get("entity")), {})
    if isinstance(debug, dict):
        return next((x for x in debug.values() if isinstance(x, dict) and x.get("entity")), {})
    return {}


def measured_distance(row, anchor):
    if not anchor or anchor.get("contact") is None or not row.get("muzzle") or not row.get("pos"):
        return None
    contact, position, muzzle = vector(anchor["contact"]), vector(row.get("body_pos", row["pos"])), vector(row["muzzle"]["pos"])
    orient = rotation(row["ang"])
    world = [position[i] + sum(orient[i][j] * contact[j] for j in range(3)) for i in range(3)]
    scale = row.get("scale")
    return math.dist(world, muzzle) / scale if isinstance(scale, (int, float)) and scale > 0 else None


def measured_ray_error(row, anchor):
    if not anchor or anchor.get("contact") is None or not row.get("muzzle"):
        return None
    position, contact = vector(row.get("body_pos", row["pos"])), vector(anchor["contact"])
    body, gun = rotation(row["ang"]), rotation(row["muzzle"]["ang"])
    point = [position[i] + sum(body[i][j] * contact[j] for j in range(3)) for i in range(3)]
    delta = [point[i] - vector(row["muzzle"]["pos"])[i] for i in range(3)]
    direction = [gun[i][0] for i in range(3)]
    along = sum(delta[i] * direction[i] for i in range(3))
    return math.sqrt(sum((delta[i] - along * direction[i])**2 for i in range(3))) / row["scale"]


def tool_actions(records, server):
    """Require the intended native tool and a real target, never fixture cleanup alone."""
    chosen = [r for r in records if r["name"] == "menu-selected"]
    targets = [r for r in records if r["name"] == "target" and r.get("class") == "gmod_tool"]
    checks = {}
    for mode in ("remover", "colour"):
        checks["menu_" + mode] = any(r.get("wanted") == r.get("actual") == mode for r in chosen) and any(
            r.get("purpose") == r.get("tool") == mode for r in targets)
    removers = {r["entity"] for r in targets if r.get("purpose") == r.get("tool") == "remover"}
    checks["remover"] = checks["menu_remover"] and any(
        r["name"] == "target-removed" and r.get("entity") in removers and r.get("purpose") == r.get("tool") == "remover" and
        r.get("class") == "gmod_tool" and r.get("fixture_cleanup") is False and 33 <= r.get("time", -1) <= 34.6
        for r in records) and any(r["name"] == "remover-result" and r.get("remaining") == 0 for r in records)
    colours = {r["entity"] for r in targets if r.get("purpose") == r.get("tool") == "colour"}
    expected, white = {"r": 32, "g": 140, "b": 220, "a": 255}, {"r": 255, "g": 255, "b": 255, "a": 255}
    def colour_window(low, high, value):
        return any(low <= r.get("time", -1) <= high and r.get("target_entity") in colours and
                   r.get("class") == "gmod_tool" and r.get("tool") == r.get("target_purpose") == "colour" and
                   r.get("colour") == value for r in server)
    checks["colour"] = checks["menu_colour"] and colour_window(41, 43, white) and colour_window(43.4, 44.8, expected) and any(
        r["name"] == "colour-result" and r.get("entity") in colours and r.get("colour") == expected for r in records)
    checks["tool_secondary"] = checks["colour"] and any(
        r["name"] == "secondary-result" and [r.get(k) for k in ("r", "g", "b")] == [32, 140, 220] for r in records)
    checks["tool_reload"] = checks["colour"] and colour_window(47.3, 48.8, white) and any(
        r["name"] == "reload-result" and r.get("colour") == white for r in records)
    return checks


def overlay_source(state, size, simulated):
    return (state.get("visible") is True and state.get("texture_error") == 0 and state.get("transform_error") == 0 and
            state.get("simulated") is simulated and (state.get("texture_width"), state.get("texture_height")) == size)


def evaluate(folder, native_only=False):
    records = json.loads((folder / "tools-records.json").read_text(encoding="utf-8"))
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    provenance = json.loads((folder / "tools-provenance.json").read_text(encoding="utf-8"))
    restoration = json.loads((folder / "restoration.json").read_text(encoding="utf-8"))
    console = (folder / "poc/game/console.log").read_text(encoding="utf-8", errors="replace")
    clocks = {}
    for row in records:
        if row["name"] == "command-clock" and row.get("number") and row.get("time") is not None:
            clocks.setdefault(row["number"], row["time"])
    # Phase windows use the client's actual networked-command label, not CurTime
    # elapsed on a different clock through capture stalls. Raw records stay untouched.
    records = [dict(row, server_time=row.get("time"), time=clocks[row["command_number"]])
               if row.get("realm") == "server" and row.get("command_number") in clocks else row for row in records]
    module_errors = [line for line in console.splitlines() if re.search(r"\[nlvr\] (?:module|cleanup|stop)\s", line) or "[nlvr] UI cleanup:" in line or "[nlvr] tools rotation:" in line]
    expected_faults = []
    if provenance.get("case") == "review":
        expected_faults = [line for line in module_errors if "[nlvr] tools rotation:" in line and
                           ("intentional T review controller fault" in line or "could not create physgun angle controller" in line)]
        module_errors = [line for line in module_errors if line not in expected_faults]
    server = [r for r in records if r.get("realm") == "server" and r["name"] == "sample"]
    client = [r for r in records if r.get("realm") == "client" and r["name"] == "sample"]
    checks = {"renderer": summary.get("success") is True,
              "driver": provenance.get("driver_exit") == 0,
              "restoration": restoration.get("clean") is True and all(restoration.get("originals", {}).values()),
              "module_errors": not module_errors,
              "native_pickup": any(r.get("held") for r in server),
              "server_stopped": any(r["name"] == "stopped" and r.get("realm") == "server" for r in records),
              "client_stopped": any(r["name"] == "stopped" and r.get("global_absent") for r in records)}
    checks["tool_settings_restored"] = any(r["name"] == "tool-settings-restored" and r.get("before") == r.get("after") and r.get("before") for r in records)
    observed = {r.get("event") for r in records if r["name"] == "hook" and r.get("count", 0) > 0}
    for event in ("PhysgunPickup", "OnPhysgunPickup", "PhysgunDrop", "OnPhysgunFreeze", "OnPhysgunReload"):
        checks["native_hook_" + event] = event in observed
    anchor = pickup_orientation(records, server)
    measurements = {"pickup_orientation": anchor}
    checks["pickup_orientation"] = anchor is not None
    for axis, low, high, declared in (("yaw", 5.6, 6.3, (0, 90, 0)), ("pitch", 8.2, 8.8, (90, 0, 0)), ("roll", 10.7, 11.3, (0, 0, 90))):
        window = [r for r in server if anchor and low <= r.get("time", -1) <= high and r.get("held") and r.get("hand", {}).get("valid")]
        errors, angles, hand_errors = [], [], []
        for row in window:
            errors.append(matrix_error(rotation(row["ang"]), followed_rotation(anchor["body"], anchor["hand"], row["hand"]["ang"])))
            hand_delta = multiply(rotation(row["hand"]["ang"]), transpose(rotation(anchor["hand"])))
            hand_errors.append(matrix_error(hand_delta, rotation(declared)))
            angles.append(row["ang"])
        jitter = max((angle_error(a, angles[0]) for a in angles), default=None)
        maximum = max(errors, default=None)
        spin = max((math.sqrt(sum(n * n for n in vector(r["angular"]))) for r in window if r.get("angular")), default=None)
        velocity = max((math.sqrt(sum(n * n for n in vector(r["velocity"]))) for r in window if r.get("velocity")), default=None)
        ray_errors = [error for r in window if (error := measured_ray_error(r, anchor)) is not None]
        measurements[axis] = {"samples": len(window), "max_error_degrees": maximum, "settled_range_degrees": jitter,
                              "max_spin_degrees_per_second": spin, "max_speed_units_per_second": velocity,
                              "max_declared_hand_delta_error_degrees": max(hand_errors, default=None),
                              "max_contact_ray_error_metres": max(ray_errors, default=None)}
        checks[axis + "_on_gun_ray"] = len(ray_errors) >= 3 and max(ray_errors) <= 0.05
        checks[axis + "_declared_hand_rotation"] = len(window) >= 3 and max(hand_errors) <= 1
        checks[axis + "_within_5_degrees"] = len(window) >= 3 and maximum <= 5
        checks[axis + "_settled"] = len(window) >= 3 and jitter <= 0.5 and spin is not None and spin <= 1
    def distances(low, high):
        return [d for r in server if low <= r.get("time", -1) <= high and (d := measured_distance(r, anchor)) is not None]
    for label, a, b in (("push", (12.3, 12.8), (15.3, 15.8)), ("pull", (15.3, 15.8), (18.3, 18.8))):
        before, after = distances(*a), distances(*b)
        delta = sum(after) / len(after) - sum(before) / len(before) if before and after else None
        measurements[label] = {"before_metres": before, "after_metres": after, "delta_metres": delta}
        checks[label] = delta is not None and (delta > 0.15 if label == "push" else delta < -0.15)
    frozen = [r for r in server if 19.3 <= r.get("time", -1) < 20 and r.get("exists")]
    unfrozen = [r for r in server if 20.6 <= r.get("time", -1) < 21.3 and r.get("exists")]
    checks["freeze"] = bool(frozen) and all(not r.get("motion") for r in frozen)
    checks["unfreeze"] = bool(unfrozen) and all(r.get("motion") for r in unfrozen)
    checks["hands_selection"] = any(24 <= r.get("time", -1) <= 24.7 and r.get("class") == "nlvr_hands" for r in server)
    taps = [r for r in records if r["name"] == "tap"]
    tap_rows = [r for r in client if 24.7 <= r.get("time", -1) <= 25.6]
    before_tap = [r for r in client if 24.3 <= r.get("time", -1) < 24.7]
    paints_before = before_tap[-1].get("debug", {}).get("wheel", {}).get("paints") if before_tap else None
    checks["tap_no_wheel"] = bool(taps) and bool(tap_rows) and paints_before is not None and all(
        not r.get("debug", {}).get("wheel", {}).get("open") and r.get("debug", {}).get("wheel", {}).get("paints") == paints_before
        for r in [*tap_rows, *taps])
    from vr_tools_capture import measure, accepted
    beam = measure(folder, records, summary)
    checks["beam_at_muzzle"] = len(beam) >= 2 and all(accepted(r) for r in beam)
    measurements["beam"] = beam
    if not native_only:
        checks.update(tool_actions(records, server))
        checks["weapon_selection"] = any(r["name"] == "wheel-weapon-result" and r.get("class") == "weapon_crowbar" for r in records)
        checks["tool_overlay"] = any(r.get("debug", {}).get("tool", {}).get("mode") == "colour" for r in client)
    if provenance.get("case") == "review":
        from vr_tools_review_check import evaluate as review_evaluate
        review_checks, review_measurements = review_evaluate(records)
        checks.update(review_checks)
        checks["exact_injected_faults"] = (sum("intentional T review controller fault" in r for r in expected_faults) == 1 and
                                           sum("could not create physgun angle controller" in r for r in expected_faults) == 1)
        measurements["review"] = review_measurements
    labels = ["tools-yaw", "tools-pitch", "tools-roll", "tools-wheel"] + ([] if native_only else ["tools-info", "tools-wheel-weapon", "tools-removed", "tools-coloured"])
    images = {}
    for label in labels:
        directory = folder / "captures" / label
        images[label] = {name: (directory / name).is_file() for name in ("left.png", "right.png", "centre.png", "mirror.png", "timings.json")}
        checks["capture_" + label] = all(images[label].values())
    for label, role, size in (("tools-wheel", "wheel", (1035, 1037)), *([] if native_only else [("tools-info", "tool", (643, 133))])):
        captures = [r for r in records if r["name"] == "capture" and r.get("label") == label]
        overlay = captures[0].get("overlays", {}).get(role, {}) if captures else {}
        state = overlay.get("state", {})
        checks[role + "_sdk_source"] = overlay_source(state, size, summary.get("simulated") is True)
        path = folder / "captures" / label / ("overlay_" + str(overlay.get("handle")) + ".png")
        checks[role + "_image"] = path.is_file()
        images[label][role] = {"path": str(path), "sdk": state}
    return {"checks": checks, "measurements": measurements, "images": images, "module_errors": module_errors, "success": all(checks.values())}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--native-only", action="store_true")
    args = parser.parse_args(argv)
    result = evaluate(args.folder, args.native_only)
    (args.folder / "tools-acceptance.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
