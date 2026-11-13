"""Run task L's scripted movement acceptance on top of the unchanged VR session driver."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as vr  # noqa: E402


def canvas_pixels(path):
    """The runtime's filter-zero RGBA8 format; UI canvases have a separate bounded extent."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not PNG")
    offset, header, payload = 8, None, bytearray()
    while offset + 12 <= len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        part = data[offset + 8:offset + 8 + size]
        if offset + size + 12 > len(data):
            raise ValueError("truncated PNG")
        kind = data[offset + 4:offset + 8]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", part)
        if kind == b"IDAT":
            payload.extend(part)
        offset += size + 12
    if not header or header[2:] != (8, 6, 0, 0, 0):
        raise ValueError("expected RGBA8")
    w, h = header[:2]
    if not 1 <= w * h <= 2_000_000:
        raise ValueError("canvas too large")
    stride = w * 4 + 1
    decoder = zlib.decompressobj()
    raw = decoder.decompress(payload, stride * h + 1)
    if len(raw) != stride * h or not decoder.eof or any(raw[y * stride] for y in range(h)):
        raise ValueError("invalid filter-zero pixels")
    result = {"width": w, "height": h, "white": 0, "green": 0, "red": 0, "max_alpha": 0}
    for y in range(h):
        for x in range(w):
            pos = y * stride + 1 + x * 4
            r, g, b, a = raw[pos:pos + 4]
            result["white"] += int(min(r, g, b) > 150 and a >= 128)
            result["green"] += int(g > r * 1.5 and g > 100 and a >= 100)
            result["red"] += int(r > g * 1.5 and r > 100 and a >= 100)
            result["max_alpha"] = max(result["max_alpha"], a)
    pos = (h // 2) * stride + 1 + (w // 2) * 4
    result["centre_rgba"] = list(raw[pos:pos + 4])
    return result


def capture_problems(root, records):
    # V1's stock checker treats every overlay as a wrist glyph canvas. L also owns an
    # intentionally black vignette/fade. Validate the wrist and every other canvas by role.
    problems, metrics = [], {}
    for record in records:
        if record.get("kind") != "capture" or not record.get("ok"):
            continue
        label, folder = record["label"], root / record["label"]
        for name in ("centre.png", "centre_depth.png", "left.png", "right.png", "mirror.png", "timings.json"):
            if not (folder / name).is_file():
                problems.append(label + ": missing " + name)
        canvases, wrist = {}, False
        for image in folder.glob("overlay_*.png"):
            try:
                value = canvas_pixels(image)
                canvases[image.name] = value
                if (value["width"], value["height"]) == (769, 257):
                    wrist = True
                    if value["white"] < 16:
                        problems.append(label + ": blank wrist")
            except (ValueError, zlib.error, struct.error) as error:
                problems.append(label + ": invalid " + image.name + ": " + str(error))
        if not wrist:
            problems.append(label + ": missing wrist")
        metrics[label] = canvases
    (root.parent / "L-capture-metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    return problems


def timeline(kind):
    if kind == "allmotion":
        steps = timeline("followup")["steps"]
        for s in timeline("locomotion")["steps"]:
            if s["time"] <= 0:
                continue
            s["time"] = round(s["time"] + 105, 4)
            for hand in ("hmd", "left", "right"):
                s[hand]["pos"][0] += 2
                s[hand]["pos"][1] += 4
            steps.append(s)
        return {"version": 1, "steps": steps}
    if kind == "locomotion":
        steps = []
        for i in range(251):
            t = i / 10
            actions = {}
            if 5 <= t < 7 or 9 <= t < 10 or 12 <= t < 14:
                actions["left_stick"] = [0, 1]
            if 9 <= t < 10:
                actions["left_stick_click"] = True
            if 12 <= t < 14:
                actions["left_trigger_value"] = 1
            steps.append({"time": t, "hmd": {"pos": [0, 0, 1.6], "ang": [0, 0, 0]},
                          "left": {"pos": [0.25, 0.25, 1.2], "ang": [0, 0, 0]},
                          "right": {"pos": [0.25, -0.25, 1.2], "ang": [0, 0, 0]}, "actions": actions})
        return {"version": 1, "steps": steps}
    if kind == "followup":
        steps = [s for s in timeline("combined")["steps"] if s["time"] <= 85.9]
        keys = {4, 5, 7, 9, 11, 13, 16, 17.98, 18, 19.98, 20, 22, 23}
        for s in timeline("latency")["steps"]:
            if s["time"] in keys or 13 < s["time"] < 16:
                s["time"] = round(s["time"] + 82, 4)
                for hand in ("hmd", "left", "right"):
                    s[hand]["pos"][0] += 2
                steps.append(s)
        return {"version": 1, "steps": steps}
    if kind == "latency":
        import math
        steps = []
        for i in range(1251):
            t = i / 50
            y = 0.5 * max(0, min(2, t - 5)) + 1.5 * max(0, min(2, t - 9))
            if 13 <= t <= 16:
                y += 0.05 * math.sin(4 * math.pi * (t - 13))
            roll = 25 if 18 <= t < 20 else 0
            steps.append({"time": t, "hmd": {"pos": [0, y, 1.6], "ang": [0, 0, roll]},
                          "left": {"pos": [0.25, y + 0.25, 1.2], "ang": [0, 0, 0]},
                          "right": {"pos": [0.25, y - 0.25, 1.2], "ang": [0, 0, 0]}, "actions": {}})
        return {"version": 1, "steps": steps}
    steps = []
    for frame in range(0, 901):
        t = frame / 10
        x, z, pitch, hand_yaw = 0, 1.6, 0, 0
        actions = {}
        if kind in ("movement", "combined"):
            x = max(0, min(1, t - 5))
            hand_yaw = 90 if 8 <= t < 17 else 0
            if 8 <= t < 10 or 12 <= t < 14 or 15 <= t < 16:
                actions["left_stick"] = [0, 1]
            if 15 <= t < 16:
                actions["left_stick_click"] = True
            if 17 <= t < 17.25:
                actions["left_a"] = True
            if 19 <= t < 19.6 or 21 <= t < 22:
                actions["right_stick"] = [1, 0]
            if 24 <= t < 25:
                z = 1.6 - (t - 24) * 0.6
            elif 25 <= t < 26:
                z = 1
            elif 26 <= t < 27:
                z = 1.2
            elif 27 <= t < 28:
                z = 1.3
            if 32 <= t < 32.7:
                z = 1  # physical crouch while the virtual toggle remains on
            if 31 <= t < 31.3 or 33 <= t < 33.3:
                actions["right_stick"] = [0, -1]
            if 39 <= t < 41 or 42 <= t < 43:
                actions["left_stick"] = [0, 1]
                actions["left_trigger_value"] = 0.25 if t < 41 else 0.75
                pitch = -30
            x += max(0, min(1, t - 45))
            if 52 <= t < 54:
                actions["right_stick"] = [0, 1]  # combined Index walking/turning/teleport acceptance
            if kind == "combined" and t >= 50:
                actions = {}
                local_time = t - 47
                if 5 <= local_time < 7 or 11 <= local_time < 13 or 18 <= local_time < 20 or 25 <= local_time < 27 or 34 <= local_time < 36:
                    actions["right_stick"] = [0, 1]
                pitch = -15 if 17 <= local_time < 21 else 0
        else:
            if 5 <= t < 7 or 11 <= t < 13 or 18 <= t < 20 or 25 <= t < 27 or 34 <= t < 36:
                actions["right_stick"] = [0, 1]
            pitch = -15 if 17 <= t < 21 else 0
        steps.append({"time": round(t, 4), "hmd": {"pos": [x, 0, z], "ang": [0, 0, 0]},
                      "left": {"pos": [x + 0.25, 0.25, z - 0.4], "ang": [pitch, hand_yaw, 0]},
                      "right": {"pos": [x + 0.25, -0.25, z - 0.4], "ang": [pitch, 0, 0]},
                      "actions": actions})
    return {"version": 1, "steps": steps}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("movement", "teleport", "combined", "latency", "followup", "locomotion", "allmotion"), required=True)
    args, rest = parser.parse_known_args()
    output = Path(rest[rest.index("--evidence") + 1]).resolve()
    # The session driver alone creates the evidence folder after acquiring the locks.
    timeline_path = ROOT / "out/vr/v2l" / (args.case + "-timeline.json")
    timeline_path.parent.mkdir(parents=True, exist_ok=True)
    timeline_path.write_text(json.dumps(timeline(args.case)), encoding="utf-8")
    original_script, original_command = vr.lua_script, vr.command
    original_lock = vr.ExclusiveLock

    class MovementLock(original_lock):
        def __init__(self, path, task, timeout=600):
            super().__init__(path, "VR-V2-L", max(timeout, 3600))

    def script(path, settings):
        original_script(path, settings)
        text = path.read_text(encoding="utf-8")
        start = text.index('if not CONFIG.look then\n    hook.Add("CreateMove",ID,')
        end = text.index('\nif CONFIG.flat then', start)
        text = text[:start] + text[end:]  # let the production movement command reach Source
        # Native off can precede the first flat GPU frame. The live selector is a
        # render result; compare it after flat rendering, not in that transition callback.
        probe = "vr_move_motion_probe.lua" if args.case == "locomotion" else "vr_move_latency_probe.lua" if args.case == "latency" else "vr_move_probe.lua"
        extra = Path(__file__).with_name(probe).read_text(encoding="utf-8")
        case = "combined" if args.case in ("followup", "allmotion") else args.case
        if args.case in ("followup", "allmotion"):
            extra += '\nlocal L_LATENCY_FROM, L_LATENCY_OFFSET = 84.5, 82\n' + Path(__file__).with_name("vr_move_latency_probe.lua").read_text(encoding="utf-8")
        if args.case == "allmotion":
            extra += '\nlocal M_FROM, M_OFFSET, M_HAS_BASE_PROBE = 106, 105, true\n' + Path(__file__).with_name("vr_move_motion_probe.lua").read_text(encoding="utf-8")
        path.write_text(text + '\nlocal L_CASE = "' + case + '"\n' + extra, encoding="utf-8")

    def command(command_args, evidence, name, allowed=(0,)):
        if name == "game":
            setup = Path(__file__).with_name("vr_move_server_probe.lua").read_text(encoding="utf-8")
            if args.case in ("locomotion", "allmotion"):
                setup += "\n" + Path(__file__).with_name("vr_move_motion_server.lua").read_text(encoding="utf-8")
            import poc_session as poc
            index = command_args.index("--lua")
            additions = []
            for line in poc.client_lua_lines("l_server_fixture", setup):
                additions.extend(["--console", line.replace("lua_run_cl", "lua_run", 1)])
            command_args[index:index] = additions
        return original_command(command_args, evidence, name, allowed)

    vr.lua_script, vr.command, vr.capture_problems, vr.ExclusiveLock = script, command, capture_problems, MovementLock
    return vr.main([*rest, "--timeline", str(timeline_path), "--camera", "823,-657,-79,0,0,0"])


if __name__ == "__main__":
    raise SystemExit(main())
