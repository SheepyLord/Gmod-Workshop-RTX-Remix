"""Measure task L's retained real/simulated session records; fail missing or incorrect features."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import re


def vector(value):
    if isinstance(value, dict):
        return [float(value[k]) for k in ("x", "y", "z")]
    if isinstance(value, str):
        return [float(n) for n in re.findall(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", value)]
    return list(map(float, value))


def delta(a, b):
    return [x - y for x, y in zip(vector(a), vector(b))]


def length(v):
    return math.sqrt(sum(n * n for n in v))


def check(folder, timing_scale=1):
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    rows = summary["records"]
    marks = {r["label"]: r for r in rows if r.get("kind") == "L-movement"}
    result = {"success": bool(summary["success"]), "metrics": {}, "checks": {}, "missing": []}
    metrics, checks = result["metrics"], result["checks"]
    if not marks:
        result.update(success=False, missing=["L-movement records"])
        return result
    kind = next(iter(marks.values()))["case"]
    result["case"] = kind

    def record(name):
        if name not in marks:
            result["missing"].append(name)
            return {}
        return marks[name]

    def travel(name, first, last, expected, tolerance):
        a, b = record(first), record(last)
        if "position" not in a or "position" not in b:
            checks[name] = False
            return
        displacement = delta(b["position"], a["position"])
        metrics[name] = {"vector": displacement, "distance": length(displacement), "expected": expected}
        checks[name] = abs(length(displacement) - expected) <= tolerance

    if kind in ("movement", "combined"):
        travel("one_metre", "room-before", "room-after", 40, 1)
        travel("hand_walk", "hand-before", "hand-after", 400*timing_scale, 45)
        travel("head_walk", "head-before", "head-after", 400*timing_scale, 45)
        travel("sprint", "sprint-before", "sprint-after", 400*timing_scale, 45)
        for name, axis in (("hand_walk", 1), ("head_walk", 0)):
            value = metrics.get(name, {}).get("vector", [0, 0, 0])
            checks[name + "_direction"] = value[axis] > 350*timing_scale and abs(value[1 - axis]) < 10
        head_errors, all_head_errors = [], {}
        room_marks = {"room-before", "room-after", "wall-before", "wall-after", "wall-open-before", "wall-open-after"}
        for r in marks.values():
            m = r.get("move", {})
            if m.get("head") and m.get("position"):
                displacement = delta(m["head"], m["position"])
                error = length(displacement[:2])
                all_head_errors[r["label"]] = error
                if r["label"] in room_marks:
                    head_errors.append(error)
        metrics["camera_hull_separation_by_milestone"] = all_head_errors
        metrics["head_hull_horizontal_error_max"] = max(head_errors, default=math.inf)
        checks["head_under_hull"] = metrics["head_hull_horizontal_error_max"] <= 0.4
        try:
            snap = record("snap")["move"]["space"]["yaw"]
            smooth = record("smooth-after")["move"]["space"]["yaw"]
            mouse = record("mouse-after")["move"]["space"]["yaw"]
            metrics.update(snap_degrees=snap, smooth_degrees=smooth - snap, mouse_degrees=mouse - smooth)
            checks["snap"] = abs(snap + 30) < 0.1
            checks["smooth_turn"] = abs(smooth - snap + 120*timing_scale) < 5
            checks["mouse_turn"] = abs(mouse - smooth + 2.2) < 0.1
            errors = [r["move"]["turn"]["error"] for r in marks.values() if r.get("move", {}).get("turn")]
            metrics["turn_head_error_max"] = max(errors, default=math.inf)
            checks["turn_pivot"] = metrics["turn_head_error_max"] <= 0.4
            checks["physical_crouch"] = record("physical-down")["move"]["physical_crouch"] is True
            checks["crouch_hysteresis"] = record("physical-hold")["move"]["physical_crouch"] is True and record("physical-up")["move"]["physical_crouch"] is False
            down, up, seated = record("toggle-down")["move"], record("toggle-up")["move"], record("seated")["move"]
            metrics["toggle_eye_height"] = down["head"][2] - down["position"][2]
            metrics["standing_eye_height"] = up["head"][2] - up["position"][2]
            metrics["seated_eye_height"] = seated["head"][2] - seated["position"][2]
            checks["crouch_toggle"] = down["crouch_toggle"] is True and up["crouch_toggle"] is False and abs(metrics["toggle_eye_height"] - 28) < 1
            both = record("toggle-physical")["move"]
            metrics["combined_crouch_eye_height"] = both["head"][2] - both["position"][2]
            checks["combined_crouch"] = both["physical_crouch"] is True and both["crouch_toggle"] is True and abs(metrics["combined_crouch_eye_height"] - 28) < 1
            checks["seated_height"] = abs(metrics["seated_eye_height"] - metrics["standing_eye_height"] - 18) < 1
            calibration = record("calibrated")["move"]["calibration"]
            metrics["calibration"] = calibration
            checks["calibration"] = abs(calibration["height"] - 1.6) < 0.001 and abs(calibration["scale"] - 40) < 0.001
            jump = vector(record("jump")["position"])[2] - vector(record("sprint-after")["position"])[2]
            metrics["jump_height"] = jump
            checks["jump"] = jump > 15
            for name, speed in (("flight-quarter", 100), ("flight-threequarters", 300)):
                measured = length(vector(record(name)["velocity"]))
                metrics[name] = measured
                checks[name] = abs(measured - speed) < 3
            wall = delta(record("wall-after")["position"], record("wall-before")["position"])
            after = delta(record("wall-open-after")["position"], record("wall-open-before")["position"])
            metrics.update(wall_displacement=length(wall), after_wall_removed=length(after))
            checks["wall_stops"] = 1 < length(wall) < 35
            checks["no_wall_backlog"] = length(after) < 1
        except (KeyError, TypeError, IndexError):
            checks["complete_movement_records"] = False
    if kind in ("teleport", "combined"):
        try:
            for name in ("blink", "shift", "ledge", "blink-zero"):
                r = record(name + "-after")
                tele = r["move"]["teleport"]
                error = length(delta(r["position"], tele["target"]))
                metrics[name] = {"error": error, "reason": tele["reason"], "target": tele["target"]}
                checks[name] = tele["success"] is True and error < 1
            checks["mantle"] = metrics["ledge"]["reason"] == "mantle"
            checks["invalid_target_red"] = record("refused")["move"].get("target") is None
            refused = [r for r in rows if r.get("kind") == "L-server" and r.get("label") == "sample"]
            last = refused[-1]["movement"]["last"]
            checks["server_refuses"] = last["success"] is False and last["id"] == 60000
            metrics["server_refusal"] = last["reason"]
            frames = [r for r in rows if r.get("kind") == "L-server-move" and r.get("movement", {}).get("teleport", {}).get("mode") == 2]
            checks["shift_intermediate"] = len(frames) >= 2
            metrics["shift_intermediate_records"] = len(frames)
        except (KeyError, TypeError, IndexError):
            checks["complete_teleport_records"] = False
    restoration = json.loads((folder / "restoration.json").read_text(encoding="utf-8"))
    canvases = json.loads((folder / "L-capture-metrics.json").read_text(encoding="utf-8"))

    def canvas(label, size):
        return next((c for c in canvases.get(label, {}).values() if (c["width"], c["height"]) == size), None)

    if kind in ("movement", "combined"):
        c = canvas("L-vignette", (1031, 1033))
        checks["vignette_picture"] = bool(c and c["max_alpha"] > 0 and c["centre_rgba"][3] == 0)
        metrics["vignette_pixels"] = c
    if kind in ("teleport", "combined"):
        green, red = canvas("L-arc-green", (261, 263)), canvas("L-arc-red", (261, 263))
        fade = canvas("L-blink-fade", (1031, 1033))
        checks["green_target_picture"] = bool(green and green["green"] >= 100)
        checks["red_target_picture"] = bool(red and red["red"] >= 100)
        checks["full_fade_picture"] = bool(fade and fade["centre_rgba"] == [0, 0, 0, 255])
        metrics.update(green_target_pixels=green, red_target_pixels=red, fade_pixels=fade)
    checks["rollback_clean"] = restoration["clean"]
    checks["settings_restored"] = not next((r.get("variable_differences") for r in reversed(rows) if r.get("kind") == "done"), {"missing": True})
    result["success"] &= bool(checks) and all(checks.values()) and not result["missing"]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    result = check(args.folder)
    (args.folder / "movement-acceptance.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
