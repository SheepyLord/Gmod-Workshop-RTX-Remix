"""Task M's adaptive UI fixture on the production snapshot/lock/rollback VR driver."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
import time
import threading

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc
PYTHON_SOURCE = Path(__file__).read_bytes()


def capture_problems(folder, records):
    """V1's checker is wrist-only (one megapixel); M also has larger, transparent panel canvases."""
    from PIL import Image
    problems = []
    for record in records:
        if record.get("kind") != "capture" or not record.get("ok"):
            continue
        capture = folder / record["label"]
        for name in ("centre.png", "centre_depth.png", "left.png", "right.png", "mirror.png", "timings.json"):
            if not (capture / name).is_file():
                problems.append(f"{record['label']}: missing {name}")
        wrist = False
        for path in capture.glob("overlay_*.png"):
            with Image.open(path) as image:
                if not (0 < image.width <= 4095 and 0 < image.height <= 4095) or image.mode != "RGBA":
                    problems.append(f"{path}: invalid overlay dimensions/format")
                if image.size == (769, 257):
                    wrist = True
                    if driver.overlay_bright_pixels(path) < 16:
                        problems.append(f"{path}: wrist has no glyphs")
        if not wrist:
            problems.append(f"{record['label']}: missing wrist canvas")
    return problems


def feature_receipt(summary, folder, expect_scaler=False):
    records = [r for r in summary["records"] if r.get("kind") == "ui"]
    by_name = {r["name"]: r for r in records}
    checks = {"wrist_spawn_click": by_name.get("spawn-open", {}).get("open") is True,
              "prop_icon": bool(by_name.get("spawn-result", {}).get("new_entities")),
              "hand_property_menu": by_name.get("property-menu", {}).get("remove_option") is True,
              "property_removed_entity": by_name.get("property-result", {}).get("removed") is True,
              "closed_panels": by_name.get("closed", {}).get("debug", {}).get("panels") == []}
    off = by_name.get("off", {})
    checks["vgui_restored"] = off.get("owned_roots") == 0 and not off.get("vgui_differences")
    checks["cursor_restored"] = off.get("cursor_before") == off.get("cursor_after") and "cursor_before" in off
    if expect_scaler:
        checks["gui_scaler_loaded"] = by_name.get("attached", {}).get("gui_scale") is not None
    keyboard = by_name.get("keyboard-result", {})
    checks["keyboard_text"] = keyboard.get("text") == "barrel"
    slider = by_name.get("slider-result", {}).get("changes", {})
    if not isinstance(slider, dict):
        slider = {}  # Empty Lua tables can encode as []; missing changes fail instead of crashing the checker.
    checks["drag"] = any(float(a) != float(b) for a, b in slider.values())
    scroll_a = by_name.get("scroll-start", {}).get("scroll", 0)
    scroll_b = by_name.get("scroll-result", {}).get("scroll", 0)
    checks["scroll"] = scroll_b > scroll_a
    flat = by_name.get("flat-state", {})
    source = flat.get("debug", {}).get("window_source")
    open_items = []
    if source == "ready":
        checks["resume"] = flat.get("visible") is True and by_name.get("resume-result", {}).get("resumed") is True
    elif source == "unavailable":
        checks["flat_fallback"] = True
        open_items.append("The packaged runtime lacks the window source; Resume needs R's runtime.")
    else:
        checks["flat_fallback"] = False
    images = []
    geometry_ok = True
    for record in records:
        if record.get("name", "").startswith("capture-"):
            label = "ui-" + record["name"][len("capture-"):]
            for panel in record.get("debug", {}).get("panels", []):
                if panel["key"] != "flat" or source != "ready":
                    geometry_ok &= record.get("geometry", {}).get(panel["key"]) == [panel["width"], panel["height"]]
                path = folder / "captures" / label / ("overlay_" + str(panel["handle"]) + ".png")
                images.append({"panel": panel["key"], "path": str(path), "exists": path.is_file()})
    checks["fixed_canvas_geometry"] = geometry_ok
    errors = [line for line in (folder / "poc/game/console.log").read_text(encoding="utf-8").splitlines()
              if "Create overlays in a module context" in line or line.startswith("[nlvr] UI") or "[nlvr] module ui:" in line]
    return {"checks": checks, "open": open_items, "images": images, "ui_errors": errors,
            "success": all(checks.values()) and not errors and all(i["exists"] for i in images),
            "full_acceptance": all(checks.values()) and not errors and not open_items}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--simulate", action="store_true")
    parser.add_argument("--seconds", type=int, default=70)
    parser.add_argument("--window", default=None)
    parser.add_argument("--gui-scaler", type=Path, help="cached GMA or verified extracted GUI Scaler folder; never downloaded")
    parser.add_argument("--flat-probe", action="store_true", help="25-second diagnostic of the real window's mouse dispatch")
    parser.add_argument("--probe-setters", action="store_true", help="with --flat-probe, compare cursor setters and client cursor focus")
    parser.add_argument("--settings-probe", action="store_true", help="15-second fixed-font settings layout capture")
    parser.add_argument("--window-probe", action="store_true", help="posted-window Resume diagnostic (at least 15 seconds)")
    parser.add_argument("--window-press-at", type=int, default=5, help="window probe trigger time (foreground control may need longer)")
    parser.add_argument("--followup", action="store_true", help="native Resume, fallback search and console acceptance (50 seconds)")
    args = parser.parse_args(argv)
    run_token = f"{os.getpid()}-{time.time_ns()}"
    # The native timeline supplies real head/off-hand poses and, after N, a keyboard event.
    # The client fixture computes a scripted main-hand angle from actual widget geometry;
    # it replaces only the main hand/actions at the native-to-Lua boundary, never the ray/hit code.
    original_timeline, original_script, original_command = driver.timeline, driver.lua_script, driver.command
    fixture_source = {}

    def timeline(seconds):
        poses = {"hmd": {"pos": [0, 0, 1.6], "ang": [0, 0, 0]},
                 "left": {"pos": [0.25, 0.3, 1.2], "ang": [0, 0, -90]},
                 "right": {"pos": [0.05, -0.25, 1.2], "ang": [0, 0, 0]}}
        return {"version": 1, "steps": [{"time": t, **poses} for t in (0, seconds + 20)],
                "events": [] if args.flat_probe or args.window_probe or args.followup else [{"time": 18, "type": "keyboard_done", "text": "barrel"}]}

    def script(path, config):
        config["ui_probe_setters"] = args.probe_setters
        config["ui_settings_probe"] = args.settings_probe
        config["ui_window_press_at"] = args.window_press_at
        config["ui_force_keyboard_fallback"] = args.followup and args.simulate
        config["ui_run_token"] = run_token
        original_script(path, config)
        fixture = Path(__file__).with_name("vr_ui_flat_probe.lua") if args.flat_probe else Path(__file__).with_suffix(".lua")
        if args.window_probe: fixture = Path(__file__).with_name("vr_ui_window_probe.lua")
        if args.followup: fixture = Path(__file__).with_name("vr_ui_followup.lua")
        fixture_source["path"] = str(fixture)
        fixture_source["bytes"] = fixture.read_bytes()
        fixture = fixture_source["bytes"].decode("utf-8")
        with path.open("a", encoding="utf-8") as out:
            out.write("\ndo\n" + fixture + "\nend\n")

    def command(command_args, evidence, name, allowed=(0,)):
        if name == "game":
            if args.gui_scaler:
                source = args.gui_scaler.resolve(strict=True)
                unpacked = evidence / "gui-scaler-source"
                validation = None
                if source.is_dir():
                    driver.inside_out(source, driver.main_checkout())
                    validation = json.loads(source.with_suffix(".provenance.json").read_text(encoding="utf-8"))
                    actual = {p.relative_to(source).as_posix(): driver.sha256(p) for p in source.rglob("*") if p.is_file()}
                    expected = {p["name"]: p["sha256"] for p in validation["files"]}
                    if actual != expected or any(not p["crc_ok"] for p in validation["files"]):
                        raise ValueError("extracted GUI fixture differs from its verified archive payload")
                    unpacked = source
                else:
                    with (evidence / "gui-scaler-extract.log").open("w", encoding="utf-8") as log:
                        subprocess.run([sys.executable, str(ROOT / "tools/gmapack/gmapack.py"), "extract", "--file",
                                        str(source), "--out", str(unpacked)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
                if any(p.suffix.lower() in (".dll", ".exe") for p in unpacked.rglob("*")):
                    raise ValueError("GUI Scaler fixture must contain no native binary")
                destination = (driver.POC / "garrysmod/addons/nlvr_ui_scaler_fixture").resolve()
                if not destination.is_relative_to(driver.POC.resolve()) or destination.exists():
                    raise ValueError("GUI fixture destination is not a fresh owned PoC add-on")
                shutil.copytree(unpacked, destination)
                driver.write_json(evidence / "gui-scaler-fixture.json", {"source": str(source),
                    "sha256": driver.sha256(source) if source.is_file() else None, "validation": validation,
                    "destination": str(destination), "restoration": "the standard driver's snapshotted addons root"})
            command_args = list(command_args)
            setup = ('lua_run local e=ents.Create("prop_physics") e:SetModel("models/props_c17/oildrum001.mdl") '
                     'e:SetPos(Vector(679,-657,-60)) e:Spawn() e:GetPhysicsObject():EnableMotion(false) '
                     'e:SetNWBool("nlvr_ui_target",true)')
            command_args += ["--console", setup]
        if name != "game" or not args.followup:
            return original_command(command_args, evidence, name, allowed)
        # UI preparation only: these commands are blocked from client Lua. The normal PoC
        # launcher's owned-window console route opens/closes the console; it never types/runs
        # the acceptance command. Only WindowInput + the laser keyboard do that.
        stopped, preparations = threading.Event(), []
        def prepare_console():
            done = set()
            lock_path = driver.main_checkout() / "out/r10/poc.lock"
            def own_lock():
                lock = json.loads(lock_path.read_text(encoding="utf-8"))
                if lock.get("pid") != os.getpid() or lock.get("task") != "VR-V2-M":
                    raise RuntimeError("console preparation lost M's PoC lock")
            try:
                while not stopped.wait(0.1):
                    console = driver.POC / "garrysmod/console.log"
                    if not console.exists(): continue
                    text = console.read_text(encoding="utf-8", errors="replace")
                    for operation in ("hideconsole", "showconsole"):
                        if operation in done or ("NLVR_UI_PREPARE " + run_token + " " + operation) not in text: continue
                        own_lock()
                        candidates = [(pid, poc.console_window(pid)) for pid in poc.game_processes(driver.POC)]
                        candidates = [(pid, window) for pid, window in candidates if window]
                        if len(candidates) != 1: raise RuntimeError("console preparation needs one owned PoC window")
                        pid, window = candidates[0]
                        def check(target):
                            own_lock()
                            if poc.console_window(pid) != target or os.path.normcase(poc.process_path(pid) or "") != os.path.normcase(str(driver.POC / "bin/win64/gmod.exe")):
                                raise RuntimeError("console preparation target changed")
                        ok = poc.console(window, operation, attempts=1, check=check)
                        preparations.append({"operation": operation, "pid": pid, "ok": ok})
                        done.add(operation)
                        driver.write_json(evidence / "console-preparations.json", preparations)
                    if len(done) == 2: return
            except Exception as error:
                preparations.append({"error": str(error)})
                driver.write_json(evidence / "console-preparations.json", preparations)
        thread = threading.Thread(target=prepare_console, name="M-console-preparation", daemon=True)
        thread.start()
        try: return original_command(command_args, evidence, name, allowed)
        finally:
            stopped.set()
            thread.join(15)
            if thread.is_alive(): raise RuntimeError("console preparation did not stop before rollback")

    class UILock(driver.ExclusiveLock):
        def __init__(self, path, task, timeout=7200):
            super().__init__(path, "VR-V2-M", timeout)

        def __enter__(self):
            self.path.parent.mkdir(parents=True, exist_ok=True)
            began, announced = time.monotonic(), False
            while True:
                try:
                    with self.path.open("x", encoding="utf-8") as stream:
                        stream.write(self.owner)
                    print(f"Acquired {self.path.name} after {time.monotonic() - began:.1f} seconds", flush=True)
                    return self
                except FileExistsError:
                    if not announced:
                        print("Waiting for lock", self.path, flush=True)
                        announced = True
                    if time.monotonic() - began >= self.timeout:
                        raise TimeoutError(f"lock remains owned by another session: {self.path}")
                    time.sleep(1.5 + random.random() * 1.5)

    driver.timeline, driver.lua_script, driver.command, driver.ExclusiveLock = timeline, script, command, UILock
    driver.capture_problems = capture_problems
    options = ["--package", str(args.package), "--evidence", str(args.evidence), "--seconds", str(args.seconds)]
    if args.simulate:
        options += ["--simulate"]
    if args.window:
        options += ["--window", args.window]
    result = driver.main(options)
    if result == 2 or not (args.evidence / "summary.json").is_file():
        return result or 1
    summary = json.loads((args.evidence / "summary.json").read_text(encoding="utf-8"))
    ui = [r for r in summary["records"] if r.get("kind") == "ui"]
    driver.write_json(args.evidence / "ui-records.json", ui)
    if args.followup:
        by_name = {r["name"]: r for r in ui}
        after = by_name.get("followup-search-result", {}).get("after", {})
        text = (args.evidence / "poc/game/console.log").read_text(encoding="utf-8")
        checks = {"search_text": after.get("text") == "barrel", "search_query": after.get("current") == "barrel",
                  "search_results": isinstance(after.get("results"), (int, float)) and after["results"] > 0,
                  "resume": by_name.get("followup-resume-result", {}).get("resumed") is True,
                  "console_echo": any(line.strip() == "nlvrmconsoleok" for line in text.splitlines()),
                  "released": by_name.get("followup-closed", {}).get("info", {}).get("held") == 0,
                  "keyboard_tried": any(r.get("name") == "followup-steam-keyboard" for r in ui)}
        checks["console_open"] = by_name.get("followup-console-open", {}).get("visible") is True
        off = by_name.get("followup-off", {})
        checks["overlays_destroyed"] = off.get("overlay_objects") == 0 and off.get("keyboard_overlay") is False
        captures = [r for r in ui if r.get("name") == "followup-capture"]
        images = []
        for record in captures:
            for panel in record.get("debug", {}).get("panels", []):
                image = args.evidence / "captures" / ("followup-" + record["label"]) / ("overlay_" + str(panel["handle"]) + ".png")
                images.append({"label": record["label"], "panel": panel["key"], "path": str(image), "exists": image.is_file()})
        checks["pictures"] = len(captures) >= 7 and all(r.get("ok") for r in captures) and bool(images) and all(i["exists"] for i in images)
        for label in ("keyboard-search", "keyboard-console"):
            checks[label] = any(r.get("label") == label and r.get("debug", {}).get("keyboard") == "fallback" for r in captures)
            states = [r.get("overlays", {}).get("keyboard", {}) for r in captures if r.get("label") == label]
            checks[label + "-platform"] = any(s.get("visible") is True and s.get("texture_width") == 1039 and s.get("texture_height") == 391
                and s.get("texture_error") == 0 and s.get("simulated") is args.simulate for s in states)
        receipt = {"checks": checks, "images": images, "success": all(checks.values())}
    elif args.window_probe:
        attempts = [r for r in ui if r.get("name") == "window-result"]
        receipt = {"attempts": attempts, "success": bool(attempts) and all(r.get("resumed") is True for r in attempts)}
    elif args.settings_probe:
        receipt = {"success": any(r.get("name") == "capture-settings-layout" and r.get("capture_ok") for r in ui)}
    elif args.flat_probe:
        attempts = [r for r in ui if r.get("name") == "flat-probe-result"]
        receipt = {"attempts": attempts, "success": any(r.get("resumed") for r in attempts)}
    else:
        receipt = feature_receipt(summary, args.evidence, expect_scaler=bool(args.gui_scaler))
    driver.write_json(args.evidence / "ui-acceptance.json", receipt)
    (args.evidence / "ui-driver.py.snapshot").write_bytes(PYTHON_SOURCE)
    (args.evidence / "ui-fixture.lua.snapshot").write_bytes(fixture_source["bytes"])
    driver.write_json(args.evidence / "ui-driver-sources.json", {"python_sha256": hashlib.sha256(PYTHON_SOURCE).hexdigest(),
        "lua_path": fixture_source["path"], "lua_sha256": hashlib.sha256(fixture_source["bytes"]).hexdigest()})
    return result or (0 if receipt["success"] else 1)


if __name__ == "__main__":
    raise SystemExit(main())
