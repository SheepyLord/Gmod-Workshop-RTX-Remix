"""T's native tools measurements on the production simulated/Index session driver."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import re
import base64

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc


def tool_records(console):
    ordered, chunks = [], {}
    for line_number, line in enumerate(console.splitlines()):
        if line.startswith("NLVR_T "):
            ordered.append((line_number, json.loads(line[7:])))
        elif line.startswith("NLVR_T_CHUNK "):
            match = re.fullmatch(r"NLVR_T_CHUNK (client|server) (\d+) (\d+)/(\d+) ([A-Za-z0-9+/=]+)", line)
            if not match:
                raise ValueError("malformed T chunk")
            realm, serial, part, total, encoded = match.groups()
            part, total = int(part), int(total)
            if not 1 <= part <= total <= 1024:
                raise ValueError("invalid T chunk count")
            entry = chunks.setdefault((realm, serial), {"line": line_number, "total": total, "parts": {}})
            if entry["total"] != total or part in entry["parts"]:
                raise ValueError("duplicate/inconsistent T chunk")
            entry["parts"][part] = encoded
    for entry in chunks.values():
        if len(entry["parts"]) != entry["total"]:
            raise ValueError("incomplete T chunk")
        encoded = "".join(entry["parts"][i] for i in range(1, entry["total"] + 1))
        ordered.append((entry["line"], json.loads(base64.b64decode(encoded, validate=True))))
    return [row for _, row in sorted(ordered, key=lambda item: item[0])]


def timeline(seconds, case):
    steps = []

    def at(t, ang=(0, 0, 0), trigger=False, stick=0, a=False, b=False, pos=(0.3, -0.25, 1.2), head=None, stick_x=0, sprint=False):
        pitch = (35 if 22 <= t < 24.3 else 0) if head is None else head
        steps.append({"time": t, "hmd": {"pos": [0, 0, 1.6], "ang": [pitch, 0, 0]},
                      "left": {"pos": [0.0, 0.6, 1.2], "ang": [0, 0, 0]},
                      "right": {"pos": list(pos), "ang": list(ang)},
                      "actions": {"right_trigger": trigger, "right_stick": [stick_x, stick], "right_a": a, "right_b": b, "left_stick_click": sprint}})
    if case == "linear_trial":
        at(0); at(2); at(2.05,trigger=True); at(4,trigger=True)
        at(4.25,ang=(0,90,0),trigger=True); at(27,ang=(0,90,0),trigger=True); at(27.05,ang=(0,90,0)); at(seconds+15)
        return {"version":1,"steps":steps}
    if case in ("engine", "drop_api"):
        at(0, head=0)
        at(2, head=0)
        at(2.05, trigger=True, head=0)
        at(18.5, trigger=True, head=0)
        at(18.55, head=0)
        at(seconds + 15, head=0)
        return {"version": 1, "steps": steps}
    at(0)
    at(2)
    at(2.05, trigger=True)
    at(4, trigger=True)
    at(4.25, ang=(0, 90, 0), trigger=True)
    at(6.5, ang=(0, 90, 0), trigger=True)
    at(6.75, ang=(90, 0, 0), trigger=True)
    at(9, ang=(90, 0, 0), trigger=True)
    at(9.25, ang=(0, 0, 90), trigger=True)
    at(11.5, ang=(0, 0, 90), trigger=True)
    at(11.75, trigger=True)
    at(13, trigger=True)
    at(13.05, trigger=True, stick=1)
    at(15, trigger=True, stick=1)
    at(15.05, trigger=True)
    at(16, trigger=True)
    at(16.05, trigger=True, stick=-1)
    at(18, trigger=True, stick=-1)
    at(18.05, trigger=True)
    at(19, trigger=True)
    at(19.05, trigger=True, a=True)
    at(19.25, trigger=True, a=True)
    at(19.3)
    at(20.1, b=True)
    at(20.25, b=True)
    at(20.3)
    at(22)
    at(22.05, b=True)
    at(22.5, b=True)
    at(23, b=True, pos=(0.3, -0.25, 1.36))
    at(23.8, b=True, pos=(0.3, -0.25, 1.36))
    at(23.85, pos=(0.3, -0.25, 1.36))
    at(24.3)
    at(24.8, b=True)
    at(24.95, b=True)
    at(25)
    if case in ("features", "review"):
        at(26, head=0)
        at(40, head=0)
        at(40.7, head=35)
        at(50.5, head=35)
        at(51, head=0)
        at(51.5, head=0)
        at(52, head=35)
        at(54.3, head=35)
        at(55, head=0)
    if case == "review":
        for step in steps:
            if 22.5 <= step["time"] <= 25:
                step["actions"]["right_trigger"] = True
        at(25.2, trigger=True); at(25.25); at(25.5, trigger=True); at(25.7, trigger=True); at(25.8)
        at(60); at(62, trigger=True); at(63, trigger=True)
        at(63.25, ang=(0,37,0), trigger=True, sprint=True)
        at(65, ang=(0,37,0), trigger=True, sprint=True)
        at(65.05, ang=(0,37,0), trigger=True); at(67, ang=(0,37,0), trigger=True); at(68)
        for begin, upward, horizontal in ((70,1,0),(80,-1,0),(90,0.8,0.8)):
            at(begin); at(begin+2,trigger=True); at(begin+3,trigger=True,stick=upward,stick_x=horizontal)
            at(begin+4.9,trigger=True,stick=upward,stick_x=horizontal)
            if begin == 70:
                at(begin+5,trigger=True,stick=upward,a=True); at(begin+5.15,trigger=True,stick=upward,a=True)
                at(begin+5.2,trigger=True,stick=upward); at(begin+6.5,trigger=True,stick=upward)
                at(begin+6.6,trigger=True); at(begin+7)
            else:
                at(begin+5,stick=upward,stick_x=horizontal); at(begin+7,stick=upward,stick_x=horizontal); at(begin+7.1)
        for begin in (100,110,120,130):
            at(begin); at(begin+2,trigger=True); at(begin+8,trigger=True); at(begin+8.1)
        at(140); at(142,b=True,head=35); at(144,b=True,head=35); at(144.05,head=35); at(146,head=35)
        at(147); at(148.5,trigger=True); at(150); at(152); at(154,trigger=True); at(seconds+3,trigger=True)
        steps.sort(key=lambda step:step["time"])
    at(max(seconds + 15, 28))
    return {"version": 1, "steps": steps}


def main(argv=None):
    import vr_v4_fixture as fixture
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--tools-case", choices=("native", "engine", "motion", "features", "review", "drop_api", "linear_trial"), default="features")
    parser.add_argument("--seconds", type=int)
    parser.add_argument("--left-hand",action="store_true")
    task, rest = parser.parse_known_args(sys.argv[1:] if argv is None else argv)
    minimum = 160 if task.tools_case == "review" else 60 if task.tools_case == "features" else 30
    seconds = minimum if task.seconds is None else task.seconds
    if not minimum <= seconds < 180:
        parser.error(f"{task.tools_case} requires {minimum}..179 active seconds")
    rest += ["--seconds", str(seconds)]
    source_files = (Path(__file__), *Path(__file__).parent.glob("vr_tools_*client.lua"), *Path(__file__).parent.glob("vr_tools_*server.lua"))
    source_bytes = {file: file.read_bytes() for file in source_files}
    def source_text(name):
        return source_bytes[Path(__file__).with_name(name)].decode("utf-8")
    original_script, original_command, original_lock = driver.lua_script, driver.command, driver.ExclusiveLock

    class ToolsLock(original_lock):
        def __init__(self, path, name, timeout=7200):
            super().__init__(path, "VR-V4-T tools", max(timeout, 7200))

    def script(path, config):
        config["tools_case"] = "features" if task.tools_case == "review" else task.tools_case
        config["tools_review"] = task.tools_case == "review"
        config["tools_api"] = task.tools_case == "drop_api"
        config["tools_linear"] = task.tools_case == "linear_trial"
        fixture.configure(config,"tools",task.left_hand,fixture.input_data(timeline(config["seconds"],task.tools_case),task.left_hand))
        original_script(path, config)
        source = path.read_text(encoding="utf-8")
        start = source.index('if not CONFIG.look then\n    hook.Add("CreateMove",ID,')
        end = source.index('\nif CONFIG.flat then', start)
        # Keep the declared flat heading before Start; leave active W/K commands intact.
        block = source[start:end]
        hook_start = 'hook.Add("CreateMove",ID,function(command)\n'
        assert block.count(hook_start) == 1
        block = block.replace(hook_start, hook_start + '        if NativeLoaderVR.state == "running" then return end\n')
        source = source[:start] + block + source[end:]
        saved_start = 'for _, name in ipairs({"nativeloader_weather",'
        assert source.count(saved_start) == 1
        source = source.replace(saved_start, 'for _, name in ipairs({"m_yaw", "nativeloader_weather",')
        weather = 'RunConsoleCommand("nativeloader_weather_seconds", "0")'
        assert source.count(weather) == 1
        source = source.replace(weather, 'RunConsoleCommand("m_yaw", "0")\n' + weather)
        # The wrist-only probe writes the currently selected clip/reserve. Tool and Hands
        # selection must be measured without that unrelated inventory perturbation.
        for command in ('RunConsoleCommand("nlvr_q_hud")', 'RunConsoleCommand("nlvr_q_hud", "restore")'):
            assert source.count(command) == 1, "shared HUD inventory fixture changed"
            source = source.replace(command, '-- T: this fixture owns its test inventory')

        extra = source_text("vr_tools_review_client.lua") if task.tools_case in ("review", "drop_api", "linear_trial") else ""
        source += "\ndo\nlocal T_ORIGINAL_MOUSE_YAW = saved.m_yaw\n" + source_text("vr_tools_poc_client.lua") + "\n" + extra + "\nend\n"
        path.write_text(fixture.prepare(source,"tools",task.left_hand), encoding="utf-8")

    def command(args, evidence, label, **kwargs):
        if label == "game":
            field = poc.game_processes(driver.FIELD)
            if field:
                main_root = driver.main_checkout()
                helper = main_root / "out/vr/v2/quit_field_game.py"
                with (evidence / "field-quit.log").open("w", encoding="utf-8") as log:
                    quit_result = subprocess.run([sys.executable, str(helper)], cwd=main_root, stdout=log, stderr=subprocess.STDOUT)
                driver.write_json(evidence / "field-quit.json", {"pids": field, "helper": str(helper), "exit": quit_result.returncode})
                if quit_result.returncode or poc.game_processes(driver.FIELD):
                    raise RuntimeError("Authorised field console quit did not complete")
            setup = 'local T_TOOLS_MODE = "' + task.tools_case + '"\n' + source_text("vr_tools_poc_server.lua")
            if task.tools_case in ("review", "drop_api", "linear_trial"):
                setup += "\ndo\n" + source_text("vr_tools_review_server.lua") + "\nend\n"
            args=fixture.stage(args,evidence,setup,"tools",task.left_hand)
            shutil.copy2(evidence/"server-fixture.lua",evidence/"tools-server-fixture.lua")
            arguments = evidence / "tools-game-arguments.json"
            driver.write_json(arguments, [str(v) for v in args[1:]])
            args = [Path(__file__).resolve(), "--poc-arguments", arguments]
        return original_command(args, evidence, label, **kwargs)

    driver.lua_script, driver.command, driver.ExclusiveLock = script, command, ToolsLock
    driver.timeline = lambda seconds: fixture.input_data(timeline(seconds, task.tools_case),task.left_hand)
    result = driver.main([*rest, "--camera", "0,0,512,0,0,0"])
    folder = Path(rest[rest.index("--evidence") + 1])
    console = folder / "poc/game/console.log"
    if console.is_file():
        records = tool_records(console.read_text(encoding="utf-8", errors="replace"))
        driver.write_json(folder / "tools-records.json", records)
        for file, data in source_bytes.items():
            (folder / (file.name + ".snapshot")).write_bytes(data)
        driver.write_json(folder / "tools-provenance.json", {"case": task.tools_case, "driver_exit": result,
            "sources": {file.name: hashlib.sha256(data).hexdigest() for file, data in source_bytes.items()}})
        print(f"Tools records: {len(records)}", flush=True)
    return result


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--poc-arguments":
        raise SystemExit(poc.main(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))))
    raise SystemExit(main())
