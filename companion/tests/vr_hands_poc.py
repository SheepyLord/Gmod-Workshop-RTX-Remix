"""Run task H's short scripted hands fixture through the production, locked VR session driver."""
import argparse
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc


def timeline(legacy=False):
    steps = []

    def step(t, curls=None, distance=0.5, wall=False):
        side = 0.06 if distance < 0.4 else 0.14
        x = math.sqrt(distance * distance - side * side)
        value = {"time": t, "hmd": {"pos": [0, 0, 1.6], "ang": [0, 0, 0]},
                 "left": {"pos": [x, side, 1.6], "ang": [-35, 0, 0]},
                 "right": {"pos": [1.1 if wall else x, -side, 1.6], "ang": [-35, 0, 0]}}
        if not legacy:
            value["actions"] = {hand + "_skeleton": {"curls": curls or [0] * 5, "splay": [0.4] * 4}
                                for hand in ("left", "right")}
        steps.append(value)

    step(0)
    step(4)
    for finger in range(5):
        curls = [int(i == finger) for i in range(5)]
        step(5 + finger * 5, curls)
        step(9 + finger * 5, curls)
    step(30, [1] * 5)
    step(34, [1] * 5)
    for t, distance in ((35, 0.2), (40, 0.3), (45, 0.5)):
        step(t, distance=distance)
        step(t + 4, distance=distance)
    step(50, wall=True)
    step(69, wall=True)
    step(70)
    step(90)
    return {"version": 1, "steps": steps}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--simulate", action="store_true")
    parser.add_argument("--legacy-input", action="store_true",
                        help="V1 native only: supply scripted curls in the Lua fixture instead of its unsupported skeleton timeline")
    parser.add_argument("--seconds", type=int, default=85)
    args = parser.parse_args(argv)
    driver.check_screenshot_dependencies()
    evidence = driver.inside_out(args.evidence, driver.main_checkout())
    # The driver itself needs an empty evidence folder; input belongs beside it, under out.
    timeline_path = evidence.with_name(evidence.name + "-timeline.json")
    driver.write_json(timeline_path, timeline(args.legacy_input))
    original_script, original_command = driver.lua_script, driver.command

    def script(path, settings):
        settings["hands_legacy"] = args.legacy_input
        original_script(path, settings)
        text = path.read_text(encoding="utf-8")
        fixture = Path(__file__).with_name("vr_hands_poc.lua").read_text(encoding="utf-8")
        text = text.replace("-- Real-package V1 acceptance probe,", fixture + "\n-- Real-package V1 acceptance probe,", 1)
        text = text.replace("local function finish(success)\n", "local function finish(success)\n    handsTestStop()\n", 1)
        text = text.replace('    if captures[label] then return end\n',
                            '    if captures[label] or handsCaptureFrame == FrameNumber() then return end\n'
                            '    handsCaptureFrame = FrameNumber()\n', 1)
        text = text.replace('    captures[label] = true\n',
                            '    captures[label] = true\n    emit("hands", handsTestRecord(label))\n', 1)
        # H has a different timeline: remove V1's turn captures (42s would overwrite our near capture).
        for label in ("yaw-plus20", "yaw-minus20", "lean-left"):
            text = text.replace('capture("' + label + '")', 'do end')
        # Retain the neutral and HUD receipts, with independent single-finger/near/wall proof.
        marker = '        if t >= 3 then capture("neutral") end'
        text = text.replace(marker, marker + '''
        local handState = native.TestState()
        local handTime = handState and handState.time or 0
        for _, item in ipairs({{7,"thumb"},{12,"index"},{17,"middle"},{22,"ring"},{27,"pinky"},
            {32,"fist"},{37,"near-020"},{42,"near-030"},{47,"near-050"},
            {53,"wall"},{59,"ghost-disabled"},{65,"dominant-left"},{74,"model-changed"}}) do
            if handTime >= item[1] and not captures[item[2]] then capture(item[2]) break end
        end''', 1)
        path.write_text(text, encoding="utf-8")

    def command(arguments, *positional, **keywords):
        arguments = list(arguments)
        if len(arguments) > 3 and arguments[0] == "tools/poc_session.py" and "run" in arguments:
            server = '''concommand.Add("nlvr_h_fixture",function(p,c,a)
if p~=Entity(1) then return end local x,y,z,yaw=tonumber(a[1]),tonumber(a[2]),tonumber(a[3]),tonumber(a[4])
if not yaw then return end p:SetPos(Vector(x,y,z-64)) p:SetEyeAngles(Angle(0,yaw,0)) end)
concommand.Add("nlvr_h_model",function(p)
if not IsValid(p) and game.SinglePlayer() then p=Entity(1) end
if p==Entity(1) then p:SetModel("models/player/combine_soldier.mdl") print("NL_HAND_PLAYER_MODEL "..p:GetModel()) end end)'''
            for line in poc.client_lua_lines("hands_server", server):
                arguments += ["--console", line.replace("lua_run_cl", "lua_run", 1)]
        return original_command(arguments, *positional, **keywords)

    class HandLock(driver.ExclusiveLock):
        def __init__(self, path, task, timeout=3600):
            super().__init__(path, "VR-V2-H hands", timeout=timeout)

    driver.ExclusiveLock, driver.lua_script, driver.command = HandLock, script, command
    options = ["--package", str(args.package), "--evidence", str(evidence), "--seconds", str(args.seconds)]
    if args.simulate:
        options.append("--simulate")
    options += ["--timeline", str(timeline_path)]
    result = driver.main(options)
    summary_file = evidence / "summary.json"
    if summary_file.is_file():
        summary = json.loads(summary_file.read_text(encoding="utf-8"))
        records = summary.get("records", [])
        issues = []
        witnessed = {record["label"]: record for record in records if record.get("kind") == "hands"}
        required = ["neutral", "thumb", "index", "middle", "ring", "pinky", "fist", "near-020", "near-030",
                    "near-050", "wall", "ghost-disabled", "dominant-left", "model-changed"]
        for label in required:
            record = witnessed.get(label)
            if not record:
                issues.append(label + ": missing hands receipt")
                continue
            for side in ("left", "right"):
                hand = (record.get("debug") or {}).get(side, {})
                if not hand.get("model") or hand.get("finger_bones") != 15 or not hand.get("draws"):
                    issues.append(label + ": " + side + " model/fingers not drawn")
            if len(record.get("models", [])) != 2:
                issues.append(label + ": expected two live hand models")
        wall = (witnessed.get("wall", {}).get("debug") or {}).get("right", {})
        if not wall.get("blocked") or not wall.get("ghost") or wall.get("distance", 0) <= 0:
            issues.append("wall: no stopped hand and visible ghost")
        if (witnessed.get("ghost-disabled", {}).get("debug") or {}).get("right", {}).get("ghost"):
            issues.append("ghost-disabled: ghost still visible")
        for i, label in enumerate(("thumb", "index", "middle", "ring", "pinky")):
            for side in ("left", "right"):
                curls = (witnessed.get(label, {}).get("debug") or {}).get(side, {}).get("curls", [])
                if len(curls) != 5 or any(abs(curl - int(j == i)) > 0.05 for j, curl in enumerate(curls)):
                    issues.append(label + ": " + side + " individual curl not applied")
        thumb_models = witnessed.get("thumb", {}).get("models", [])
        for i, side in enumerate(("L", "R")):
            bone = thumb_models[i].get("bones", {}).get(side + "Finger0", {}) if len(thumb_models) > i else {}
            applied = bone.get("applied", [])
            expected = 40 if side == "L" else -40
            if len(applied) != 3 or abs((applied[0] - expected + 180) % 360 - 180) > 2:
                issues.append("thumb: " + side + " opposition not applied to the actual bone")
        for label, expected in (("near-020", 0.2), ("near-030", 0.3), ("near-050", 0.5)):
            for side in ("left", "right"):
                metres = witnessed.get(label, {}).get("hands", {}).get(side, {}).get("metres", -1)
                if abs(metres - expected) > 0.005:
                    issues.append(label + ": " + side + " wrist not at measured depth")
        if witnessed.get("dominant-left", {}).get("dominant") != "left":
            issues.append("dominant-left: input mapping did not mirror")
        if ((witnessed.get("model-changed", {}).get("debug") or {}).get("left", {}).get("model") ==
                (witnessed.get("neutral", {}).get("debug") or {}).get("left", {}).get("model")):
            issues.append("model-changed: player model change did not replace the hands")
        cleanup = [record for record in records if record.get("kind") == "hands-cleanup"]
        if not cleanup or cleanup[-1].get("models_live") != 0:
            issues.append("cleanup: hand models remain or receipt missing")
        driver.write_json(evidence / "hands-acceptance.json", {"success": not issues, "issues": issues,
                          "labels": sorted(witnessed), "legacy_input": args.legacy_input})
        if issues:
            print("Hands acceptance failed: " + "; ".join(issues), file=sys.stderr)
            return 1
    return result


if __name__ == "__main__":
    raise SystemExit(main())
