"""K reload acceptance through the production driver, with transactional PoC rollback."""
from pathlib import Path
import json
import math
import re
import struct
import zlib
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc

CLASSES = ("weapon_pistol", "weapon_357", "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_rpg")


class ReloadLock(driver.ExclusiveLock):
    """Keep the shared atomic ownership rules while noticing short queue vacancies."""
    def __init__(self, path, task, timeout=7200):
        super().__init__(path, "VR-V4-K reload", timeout)

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        deadline, announced = time.monotonic() + self.timeout, False
        while True:
            try:
                with self.path.open("x", encoding="utf-8") as stream:
                    stream.write(self.owner)
                return self
            except FileExistsError:
                if not announced:
                    print("Waiting for lock", self.path, flush=True)
                    announced = True
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"lock remains owned by another session: {self.path}")
                time.sleep(.25)


def validate_records(folder, records, requested, calibrate, console):
    """Keep managed module errors and actual capture files in the acceptance path."""
    module_errors = [line for line in console.splitlines()
                     if re.search(r"\[nlvr\] (?:module |cleanup |stop |server core:)", line)]
    checks = {"no_managed_errors": not module_errors,
              "all_setups": set(requested) <= {r["class"] for r in records if r["kind"] == "setup"}}
    if calibrate:
        checks["all_calibrated"] = set(requested) & set(CLASSES) <= {
            r["class"] for r in records if r["kind"] == "calibration"}
    assets = [r for r in records if r["kind"] == "ammo-model" and r.get("class") in requested]
    if assets:
        checks["stock_ammo_exists"] = all(r.get("exists") and r.get("valid") for r in assets)
    captures, problems = [], []
    for r in records:
        if r["kind"] != "capture":
            continue
        label = r["label"]
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,120}", label):
            problems.append("invalid capture label")
            continue
        path = folder / "captures" / label
        missing = [n for n in ("centre.png", "centre_depth.png", "left.png", "right.png", "mirror.png", "timings.json")
                   if not (path / n).is_file()]
        handle = str(r.get("ammo_handle", ""))
        if r["class"] in CLASSES:
            if not re.fullmatch(r"\d{1,20}", handle):
                missing.append("known ammo handle")
            else:
                target = path / ("overlay_" + handle + ".png")
                try:
                    size = struct.unpack_from(">II", target.read_bytes(), 16)
                    if size != (387, 129) or driver.overlay_bright_pixels(target) < 16:
                        missing.append("nonblank 387x129 ammo source")
                except (OSError, ValueError, struct.error, zlib.error) as error:
                    missing.append("ammo source: " + str(error))
        if missing:
            problems.append(label + ": " + ", ".join(missing))
        captures.append({"label": label, "ammo_handle": handle, "missing": missing})
    checks["captures_exist"] = bool(captures) and not problems
    for cls in set(requested) & set(CLASSES):
        counters = [r for r in records if r["kind"] == "counter" and r.get("class") == cls]
        checks["counter_" + cls] = any(r.get("visible") and r.get("native", {}).get("texture_width") == 387
            and r["native"].get("texture_height") == 129 and r["native"].get("texture_error") == 0
            and r["native"].get("transform_error") == 0 for r in counters)
    restored = [r for r in records if r["kind"] == "settings-restored"]
    checks["fixture_settings_restored"] = bool(restored) and not restored[-1]["differences"]
    return {"checks": checks, "module_errors": module_errors, "capture_problems": problems,
            "captures": captures, "success": all(checks.values())}


def timeline(seconds, classes, calibration=None, button=False, counter_motion=False, holster=False):
    steps = []

    def step(t, off=(.2, .3, 1.2), angle=(0, 0, 0), main=(.4, -.25, 1.2), main_angle=(0, 0, 0), head_angle=(0, 0, 0), **actions):
        steps.append({"time": t, "hmd": {"pos": [0, 0, 1.6], "ang": list(head_angle)},
                      "left": {"pos": list(off), "ang": list(angle)},
                      "right": {"pos": list(main), "ang": list(main_angle)}, "actions": actions})

    if calibration is None:
        step(0)
    else:
        ports = {r["class"]: r for r in calibration if r["kind"] == "calibration"}
        for slot, cls in enumerate(classes):
            base = slot * (15 if holster else 20)
            step(base)
            if holster:
                port = ports[cls]
                pos, ang = port["port_tracking"], port["port_angle"]
                step(base + 1, right_trigger=True)
                step(base + 1.15)
                eject = 2 if cls == "weapon_smg1" else 8.2
                step(base + eject, right_a=True)
                step(base + eject + .15)
                step(base + 9, off=(-.22,.3,1.6), left_grip=True)
                step(base + 9.5, off=(-.22,.3,1.6), left_grip=True)
                step(base + 10, off=pos, angle=ang, left_grip=True)
                step(base + 11, off=pos, angle=ang, left_grip=True)
                step(base + 11.5)
                step(base + 13, right_trigger=True)
                step(base + 13.15)
                continue
            if button:
                step(base + 1, right_trigger=True)
                step(base + 1.15)
                step(base + 3, right_b=True)
                step(base + 3.15)
                step(base + 8)
                continue
            port = ports[cls]
            pos, ang = port["port_tracking"], port["port_angle"]
            def look_at(point):
                x, y, z = point[0], point[1], point[2] - 1.6
                return (math.degrees(math.atan2(-z, math.hypot(x, y))), math.degrees(math.atan2(y, x)), 0)
            shown_ammo = (.35, .25, 1.3)
            look_well = look_at(pos)
            pitch, yaw = map(math.radians, ang[:2])
            forward = (math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch))
            approach = [p + .075 * d for p, d in zip(pos, forward)]
            if cls == "weapon_rpg":
                # A fresh RPG has no trusted chamber indicator. Arm it through
                # the production shoulder/insert path before the first shot.
                step(base + .2, off=(-.22,.3,1.6), left_grip=True)
                step(base + .6, off=(-.22,.3,1.6), left_grip=True)
                step(base + .9, off=pos, angle=ang, left_grip=True)
                step(base + 1.3, off=pos, angle=ang, left_grip=True)
                step(base + 1.4)
                step(base + 1.5, right_trigger=True)
                step(base + 1.65)
            else:
                step(base + 1, right_trigger=True)
                step(base + 1.15)
            if cls in CLASSES[:4]:
                step(base + 2, right_a=True)
                step(base + 2.15)
            step(base + 3)
            step(base + 3.4, right_trigger=True)
            step(base + 3.55)
            step(base + 6.2, right_trigger=True)
            step(base + 6.35)
            step(base + 7.5)
            step(base + 8, off=(-.22, .3, 1.6), left_grip=True)
            step(base + 8.4, off=(-.22, .3, 1.6), left_grip=True)
            step(base + 8.6, off=shown_ammo, head_angle=look_at(shown_ammo), left_grip=True)
            step(base + 9, off=shown_ammo, head_angle=look_at(shown_ammo), left_grip=True)
            step(base + 9.5, off=approach, angle=ang, head_angle=look_well, left_grip=True)
            step(base + 10.3, off=approach, angle=ang, head_angle=look_well, left_grip=True)
            step(base + 10.5, off=pos, angle=ang, head_angle=look_well, left_grip=True)
            step(base + 11, off=pos, angle=ang, head_angle=look_well)
            if cls == "weapon_shotgun":
                for extra in (0, 1):
                    t = base + 11.5 + extra * 2
                    step(t, off=(-.22, .3, 1.6), left_grip=True)
                    step(t + .5, off=(-.22, .3, 1.6), left_grip=True)
                    step(t + 1, off=pos, angle=ang, left_grip=True)
                    step(t + 1.5, off=pos, angle=ang)
            step(base + 16, head_angle=look_well, right_trigger=True)
            step(base + 16.15, head_angle=look_well)
            step(base + 18, head_angle=look_well)
    if counter_motion:
        base = 0 if calibration is None else len(classes) * 20
        step(base + 4)
        step(base + 7, main=(.58, -.18, 1.3), main_angle=(0, 30, 0))
        step(base + 10, main=(.58, -.18, 1.3), main_angle=(0, 30, 0))
        step(base + 13)
    step(seconds + 5)
    return {"version": 1, "steps": steps}


def quit_field_normally(evidence):
    """Only console quit; never delegate to a helper with an unknown force fallback."""
    field=poc.game_processes(driver.FIELD)
    if not field:
        return
    sent=[]
    for pid in field:
        hwnd=poc.console_window(pid)
        if hwnd and poc.console(hwnd,"quit"):
            sent.append(pid)
    deadline=time.monotonic()+30
    if sent:
        while poc.game_processes(driver.FIELD) and time.monotonic()<deadline:
            time.sleep(.5)
    remaining=poc.game_processes(driver.FIELD)
    driver.write_json(evidence/"field-quit.json",{"pids":field,"sent":sent,"remaining":remaining,
        "exit":int(bool(remaining)),"forced":False,"method":"normal console quit only"})
    if remaining:
        raise RuntimeError("field game has no completed normal quit; no forced termination attempted")


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    import vr_v4_fixture as fixture
    left="--left-hand" in args
    if left:args.remove("--left-hand")
    deploy = "--deploy-lock" in args
    if deploy:
        args.remove("--deploy-lock")
    holster = "--holster" in args
    if holster:
        args.remove("--holster")
    calibrate = "--calibrate" in args
    if calibrate:
        args.remove("--calibrate")
    classes = list(CLASSES)
    if "--classes" in args:
        i = args.index("--classes")
        classes = args[i + 1].split(",")
        del args[i:i + 2]
    calibration = None
    if "--calibration" in args:
        i = args.index("--calibration")
        calibration = fixture.canonical_calibration(json.loads(Path(args[i + 1]).read_text(encoding="utf-8")),left)
        del args[i:i + 2]
    button = "--button" in args
    if button:
        args.remove("--button")
    empty = "--empty" in args
    if empty:
        args.remove("--empty")
    counter_motion = "--counter-motion" in args
    if counter_motion:
        args.remove("--counter-motion")
    if not calibrate and calibration is None:
        raise ValueError("feature runs require --calibration <reload.json>")
    if not classes or any(c not in (*CLASSES, "nlvr_k_swep", "gmod_tool", "weapon_physgun") for c in classes):
        raise ValueError("unknown reload test class")
    seconds = int(args[args.index("--seconds") + 1]) if "--seconds" in args else 150
    if not 15 <= seconds < 180:
        raise ValueError("keep feature sessions below three minutes")
    motion_start = 0 if calibrate else len(classes) * 20
    if counter_motion and seconds < motion_start + 15:
        raise ValueError("counter motion needs fifteen seconds after the weapon phases")
    if "--seconds" not in args:
        args += ["--seconds", str(seconds)]
    original_script, original_command = driver.lua_script, driver.command

    def script(path, config):
        config.update(reload_classes=classes, reload_calibrate=calibrate, reload_button=button, reload_empty=empty,
                      reload_counter_motion=counter_motion, reload_motion_start=motion_start, reload_holster=holster, reload_deploy=deploy)
        fixture.configure(config,"reload",left,fixture.input_data(timeline(config["seconds"],classes,None if calibrate else calibration,button,counter_motion,holster),left))
        original_script(path, config)
        source = path.read_text(encoding="utf-8")

        # The shared wrist-HUD fixture edits the active clip at 48 s. K must measure
        # only native fire and production insertion, so omit that test perturbation.
        for command_text in ('RunConsoleCommand("nlvr_q_hud")', 'RunConsoleCommand("nlvr_q_hud", "restore")'):
            assert source.count(command_text) == 1
            source = source.replace(command_text, '-- K: the reload fixture owns its test inventory')
        source += "\ndo\n" + Path(__file__).with_name("vr_reload_holster_client.lua" if holster else "vr_reload_poc_client.lua").read_text(encoding="utf-8") + "\nend\n"
        path.write_text(fixture.prepare(source,"reload",left), encoding="utf-8")

    def command(arguments, evidence, name, **kwargs):
        if name == "game":
            quit_field_normally(evidence)
            extra = []
            code = "local K_DEPLOY=" + ("true" if deploy else "false") + "\n" + "local K_HOLSTER=" + ("true" if holster else "false") + "\n" + "local K_EMPTY=" + ("true" if empty else "false") + "\n" + Path(__file__).with_name("vr_reload_poc_server.lua").read_text(encoding="utf-8")
            arguments=fixture.stage(arguments,evidence,code,"reload",left)
            path = evidence / "game-arguments.json"
            driver.write_json(path, [str(a) for a in arguments[1:]])
            arguments = [Path(__file__).resolve(), "--poc-arguments", path]
        return original_command(arguments, evidence, name, **kwargs)

    driver.ExclusiveLock, driver.lua_script, driver.command = ReloadLock, script, command
    driver.timeline = lambda seconds: fixture.input_data(timeline(seconds, classes, None if calibrate else calibration, button, counter_motion, holster),left)
    result = driver.main(args)
    evidence = Path(args[args.index("--evidence") + 1])
    console = evidence / "poc/game/console.log"
    if console.is_file():
        records = []
        console_text = console.read_text(encoding="utf-8", errors="replace")
        for line in console_text.splitlines():
            if line.startswith("NLVR_K "):
                records.append(json.loads(line[7:]))
        driver.write_json(evidence / "reload.json", records)
        receipt = validate_records(evidence, records, classes, calibrate, console_text)
        if counter_motion:
            from vr_reload_analyse import counter_metrics
            receipt["counter_motion"] = counter_metrics(records, True)
            receipt["success"] &= receipt["counter_motion"]["success"]
        receipt["renderer_exit"] = result
        receipt["success"] &= not result
        driver.write_json(evidence / "reload-receipt.json", receipt)
        if not receipt["success"]:
            result = 1
        print(f"Reload records: {len(records)}", flush=True)
    return result


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--poc-arguments":
        raise SystemExit(poc.main(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))))
    raise SystemExit(main())
