"""W's scripted fixture on the production simulated/Index driver and shared locks."""
from pathlib import Path
import json
import base64
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc

CLASSES = ("weapon_crowbar", "weapon_stunstick", "weapon_pistol", "weapon_357", "weapon_smg1", "weapon_ar2",
           "weapon_shotgun", "weapon_crossbow", "weapon_rpg", "weapon_frag", "weapon_bugbait", "weapon_physgun",
           "gmod_tool", "gmod_camera", "weapon_medkit", "weapon_fists")
PHASES = list(CLASSES) + ["pistol-5", "357-5", "smg1-5", "ar2-5", "shotgun-5", "pistol-20", "357-20", "smg1-20",
                         "ar2-20", "shotgun-20", "bolt", "rocket", "smg-grenade", "ar2-orb", "fore-smg", "fore-shotgun",
                         "wall", "melee-slow", "melee-fast", "melee-stun", "frag-throw", "bugbait-throw", "hands", "death", "respawn", "left",
                         "bolt-eye", "bullet-passes", "melee-walk", "melee-lunge"]
SLOT = 4


def timeline(seconds, phases):
    steps = []
    main_pose=(.5,-.2,1.4)
    head_yaw=0
    head_pos=(0,0,1.6)

    def step(t, right=None, left=(.45, .35, 1.25), grip=False, trigger=False, secondary=False, yaw=0, head=None):
        steps.append({"time": t, "hmd": {"pos": list(head or head_pos), "ang": [0, head_yaw, 0]},
                      "right": {"pos": list(right or main_pose), "ang": [0, yaw, 0]}, "left": {"pos": list(left), "ang": [0, yaw, 0]},
                      "actions": {"right_trigger": trigger, "right_a": secondary, "left_grip": grip}})

    for slot, phase in enumerate(phases):
        head_yaw=0 if phase in CLASSES else 45
        main_pose=(.5,-.2,1.4) if phase in CLASSES else (.5,.1,1.4)
        t = slot * SLOT
        head_pos=(0,0,1.6)
        step(t)
        step(t+.8)
        if phase in PHASES[16:30] or phase=="bolt-eye":
            step(t+1.1, trigger=phase not in ("smg-grenade", "ar2-orb"), secondary=phase in ("smg-grenade", "ar2-orb"))
            step(t+2.1)
        elif phase.startswith("fore-"):
            fore = .23 if phase == "fore-smg" else .36
            step(t+.9, trigger=True)
            step(t+1.0, left=(.5+fore, .1, 1.375), grip=True,trigger=True)
            step(t+1.5, left=(.5+fore, .1, 1.375), grip=False,trigger=True)
            step(t+1.7, left=(.5+fore, .1, 1.375), grip=True,trigger=True)
            step(t+2.0, left=(.5+fore, .16, 1.375), grip=False,trigger=True)
            step(t+2.2, left=(.5+fore, .16, 1.375), grip=True,trigger=True)
            step(t+2.35, left=(.5+fore, .16, 1.375), grip=True)
            step(t+2.8, left=(.5+fore, .16, 1.375), grip=False)
        elif phase == "melee-lunge":
            step(t+1, right=(.5,.1,1.4))
            head_pos=(.5,0,1.6)
            step(t+1.2, right=(1.5,.1,1.4), left=(.95,.35,1.25))
            step(t+3, right=(1.5,.1,1.4), left=(.95,.35,1.25))
        elif phase in ("melee-fast", "melee-slow", "melee-stun", "melee-walk"):
            step(t+1, right=(.5,.1,1.4))
            step(t+2.8 if phase == "melee-slow" else t+1.15, right=(1.0,.1,1.4))
            step(t+3, right=(1.0,.1,1.4))
        elif phase.endswith("-throw"):
            step(t+1.0, trigger=True)
            step(t+2.0, trigger=True)
            step(t+2.2, right=(.9,.1,1.4), trigger=False)
            step(t+2.5, right=(1.5,.1,1.4))
        elif phase == "hands":
            step(t+1.1)
            steps[-1]["actions"]["right_grip"] = True
            step(t+2.5)
            steps[-1]["actions"]["right_grip"] = True
        elif phase == "wall":
            step(t+1.0, right=(1.1,.1,1.4))
            step(t+1.2, right=(1.1,.1,1.4), trigger=True)
            step(t+2.8, right=(1.1,.1,1.4))
        step(t+3.7,right=(.9,-.3,1.0) if phase=="melee-lunge" else (.4,-.3,1.0) if phase.startswith("melee-") else None)
    # Standard HUD witnesses run after the weapon phases. Preserve physical head
    # travel and return both hands to their ordinary positions in front of it.
    neutral_right=(.5+head_pos[0],.1+head_pos[1],1.4)
    neutral_left=(.45+head_pos[0],.35+head_pos[1],1.25)
    step(len(phases)*SLOT+.1,right=neutral_right,left=neutral_left)
    step(max(len(phases)*SLOT+2, seconds+5),right=neutral_right,left=neutral_left)
    return {"version": 1, "steps": steps}


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    import vr_v4_fixture as fixture
    left="--left-hand" in argv
    if left:argv.remove("--left-hand")
    phases = PHASES
    camera_debug = "--camera-debug" in argv
    if camera_debug:
        argv.remove("--camera-debug")
    if "--weapons-phases" in argv:
        index = argv.index("--weapons-phases")
        phases = argv[index+1].split(",")
        del argv[index:index+2]
        if not phases or any(p not in PHASES for p in phases):
            raise ValueError("unknown W phase")
    original_script, original_command, original_lock = driver.lua_script, driver.command, driver.ExclusiveLock

    class TaskLock(original_lock):
        def __init__(self, path, task, timeout=7200):
            super().__init__(path, "VR-V4-W weapons", timeout)

    def script(path, settings):
        settings["weapons_phases"] = phases
        settings["weapons_camera_debug"] = camera_debug
        fixture.configure(settings,"weapons",left,fixture.input_data(timeline(settings["seconds"],phases),left))
        original_script(path, settings)
        text = path.read_text(encoding="utf-8")
        # S's proven settling check: preserve all live-selector assertions after a fresh flat frame.

        for label in ("yaw-plus20", "yaw-minus20", "lean-left"):
            text = text.replace('capture("'+label+'")', 'do end')
        # Our fixture controls inventory and poses. Avoid rewriting the currently selected gun's ammo mid-test.
        text = text.replace('RunConsoleCommand("nlvr_q_hud")', 'do end')
        text = text.replace('RunConsoleCommand("nlvr_q_hud", "restore")', 'do end')
        text += "\n" + Path(__file__).with_name("vr_weapons_poc_client.lua").read_text(encoding="utf-8")
        path.write_text(fixture.prepare(text,"weapons",left), encoding="utf-8")

    def command(args, evidence, label, **kwargs):
        if label == "game":
            field = poc.game_processes(driver.FIELD)
            if field:
                main_root = driver.main_checkout()
                helper = main_root / "out/vr/v2/quit_field_game.py"
                with (evidence / "field-quit.log").open("w", encoding="utf-8") as output:
                    code = subprocess.call([sys.executable, str(helper)], cwd=main_root, stdout=output, stderr=subprocess.STDOUT)
                driver.write_json(evidence / "field-quit.json", {"pids": field, "helper": str(helper), "exit": code,
                    "authority": "User permits this normal field-game console quit when a GPU/SteamVR test needs it."})
                if code or poc.game_processes(driver.FIELD):
                    raise RuntimeError("authorised field quit did not finish")
            code = Path(__file__).with_suffix(".lua").read_text(encoding="utf-8")
            args=fixture.stage(args,evidence,code,"weapons",left)
            arguments = evidence / "game-arguments.json"
            driver.write_json(arguments, [str(v) for v in args[1:]])
            args = [Path(__file__).resolve(), "--poc-arguments", arguments]
        return original_command(args, evidence, label, **kwargs)

    driver.ExclusiveLock, driver.lua_script, driver.command = TaskLock, script, command
    driver.timeline = lambda seconds: fixture.input_data(timeline(seconds, phases),left)
    result = driver.main(argv)
    evidence = Path(argv[argv.index("--evidence") + 1])
    console = evidence / "poc/game/console.log"
    if console.exists():
        records, chunks = [], {}
        for line in console.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("NLVR_W "):
                records.append(json.loads(line[7:]))
            elif line.startswith("NLVR_W_CHUNK "):
                key, part, data = line[13:].split(" ", 2)
                index, count = map(int, part.split("/"))
                bucket = chunks.setdefault(key, {})
                bucket[index] = data
                if len(bucket) == count:
                    records.append(json.loads(base64.b64decode("".join(bucket[n] for n in range(1, count+1)))))
                    del chunks[key]
        if chunks:
            raise RuntimeError("incomplete W console record chunks")
        driver.write_json(evidence / "weapons.json", records)
        from vr_weapons_analyse import analyse
        checks = analyse(evidence)
        driver.write_json(evidence / "weapons-checks.json", checks)
        if not checks["success"]:
            print("W feature checks failed: " + "; ".join(checks["issues"]), file=sys.stderr)
            return 1
    return result


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--poc-arguments":
        raise SystemExit(poc.main(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))))
    raise SystemExit(main())
