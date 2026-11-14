"""Task P's fixture/timeline extension of the shared, lock-owning VR session driver."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc


LAST_PHASE = 17  # V8 adds 14 (wrist turn), 15 (two-hand plank), 16 (freeze and free), 17 (a ragdoll bone frozen)


def timeline(seconds, phases=None):
    steps = []

    def step(time, x=.3, z=1.2, grip=False, left=False, lx=.3, yaw=0, lz=1.2, span=.3, trigger=False, pitch=0, lpitch=0):
        steps.append({"time": time, "hmd": {"pos": [0, 0, 1.6], "ang": [0, 0, 0]},
                      "left": {"pos": [lx, span, lz], "ang": [lpitch, 0, 0]},
                      "right": {"pos": [x, -span, z], "ang": [pitch, yaw, 0]},
                      "actions": {"right_grip": grip, "left_grip": left, "right_trigger": trigger}})

    phases = list(range(14)) if phases is None else phases
    for slot, phase in enumerate(phases):
        t = slot * 8
        span=.6 if phase==5 else .3
        step(t,span=span)
        step(t + 2,span=span)
        if phase == 0 or phase == 2:
            step(t+3, x=.3)
            step(t+4, x=1)
            step(t+6, x=1)
        elif phase == 1:
            step(t+2.1, grip=True)
            step(t+4, grip=True)
            step(t+4.45, x=1.65, grip=False, yaw=30)
            step(t+4.5, x=1.8, yaw=33.3333)
            step(t+6, x=1.8, yaw=33.3333)
        elif phase == 3:
            step(t+2.1, grip=True, left=True)
            step(t+3, grip=True, left=True)
            step(t+4, x=.6, lx=0, grip=True, left=True)
            step(t+6, x=.6, lx=0, grip=True, left=True)
            step(t+6.2, x=.6, lx=0)
        elif phase == 4 or phase == 5:
            step(t+2.1, grip=True, left=phase==5,span=span)
            step(t+3, grip=True, left=phase==5,span=span)
            step(t+4, x=.8, z=1.4, grip=True, left=phase==5,span=span)
            step(t+6, x=.8, z=1.4, grip=True, left=phase==5,span=span)
            step(t+6.2, x=.8, z=1.4,span=span)
        elif phase in (6, 12):
            step(t+2.1, grip=True,left=True)
            step(t+3, grip=True,left=True)
            step(t+5, z=.9,lz=.9, grip=True,left=True)
            step(t+6, z=.9,lz=.9, grip=True,left=True)
            step(t+6.2, z=.9,lz=.9)
        elif phase == 7:
            step(t+3, grip=True)
            step(t+3.3)
            step(t+4.4, grip=True)
            step(t+4.7)
            step(t+5.6, grip=True)
            step(t+6)
        elif phase == 8:
            step(t+3, x=.3)
            step(t+3.15, x=1.1)
            step(t+5, x=1.1)
        elif phase == 9:
            step(t+2.1, x=.5, grip=True)
            step(t+2.5, x=.5, grip=True)
            step(t+2.65, x=.2, grip=True)
            step(t+6, x=.2, grip=True)
        elif phase == 10:
            step(t+2.1, x=.3, z=.5)
            step(t+3, x=.3, z=.5, grip=True)
            step(t+3.15, x=1.1, z=.5, grip=True)
            step(t+5, x=1.1, z=.5)
            step(t+5.5, x=1.1, z=.5, grip=True)
            step(t+6.8, x=1.1, z=.5, grip=True)
        elif phase == 11:
            step(t+3, grip=True)
            step(t+4)
        elif phase == 13:
            step(t+2.1, grip=True)
            step(t+4, grip=True)
            step(t+4.15, x=.9, grip=True)
            step(t+6, x=.9, grip=True)
            step(t+6.2, x=.9)
        elif phase == 14:
            # V8: hold a light cube, turn the wrist a quarter turn in half a second, then move it while held.
            step(t+2.1, grip=True)
            step(t+3, grip=True)
            step(t+3.5, grip=True, yaw=90)
            step(t+4.5, grip=True, yaw=90)
            step(t+5.5, x=.6, z=1.35, grip=True, yaw=90)
            step(t+6.5, x=.6, z=1.35, grip=True, yaw=90)
            step(t+6.7, x=.6, z=1.35, yaw=90)
        elif phase == 15:
            # V8: both hands take one plank, raise it, tilt it (the right hand rises) and turn both wrists 25
            # degrees about the line between the hands (a pitch of each controller: the hands are side by side), which
            # rolls the plank about its length. A roll about each controller's own forward crosses that line: no roll.
            step(t+2.1, grip=True, left=True)
            step(t+3, grip=True, left=True)
            step(t+4, z=1.4, lz=1.4, grip=True, left=True)
            step(t+4.6, z=1.55, lz=1.4, grip=True, left=True)
            # Held level until 5.2 s, the analysis's level reference (poses interpolate between steps), then the turn.
            step(t+5.2, z=1.55, lz=1.4, grip=True, left=True)
            step(t+5.8, z=1.55, lz=1.4, grip=True, left=True, pitch=25, lpitch=25)
            step(t+6.4, z=1.55, lz=1.4, grip=True, left=True, pitch=25, lpitch=25)
            step(t+6.6, z=1.55, lz=1.4, pitch=25, lpitch=25)
        elif phase == 16:
            # V8: hold, freeze with the trigger, let go, grip again and free it with the trigger, then carry it.
            step(t+2.1, grip=True)
            step(t+3, grip=True)
            step(t+3.05, grip=True, trigger=True)
            step(t+3.3, grip=True)
            step(t+3.5)
            step(t+4.5, grip=True)
            step(t+5, grip=True)
            step(t+5.05, grip=True, trigger=True)
            step(t+5.3, grip=True)
            step(t+6.2, x=.55, grip=True)
            step(t+6.6, x=.55, grip=True)
            step(t+6.8, x=.55)
        elif phase == 17:
            # V8: hold one ragdoll bone and freeze it: only that bone stops.
            step(t+2.1, grip=True)
            step(t+3, grip=True)
            step(t+3.05, grip=True, trigger=True)
            step(t+3.3, grip=True)
            step(t+3.5)
        step(t+7.5)
    step(max(len(phases)*8+2, seconds + 5))
    return {"version": 1, "steps": steps}


def main():
    original_script, original_command = driver.lua_script, driver.command
    original_lock = driver.ExclusiveLock

    class TaskLock(original_lock):
        def __init__(self, path, task, timeout=3600):
            super().__init__(path, "VR-V3-P physical interaction", timeout)

    driver.ExclusiveLock = TaskLock
    phases = None
    if "--interact-phases" in sys.argv:
        slot = sys.argv.index("--interact-phases")
        phases = [int(n) for n in sys.argv[slot+1].split(",")]
        if not phases or any(n < 0 or n > LAST_PHASE for n in phases):
            raise ValueError("interaction phases must be 0..%d" % LAST_PHASE)
        del sys.argv[slot:slot+2]

    fg_check = "--fg-check" in sys.argv
    if fg_check:
        sys.argv.remove("--fg-check")

    def script(path, settings):
        settings["interact_phases"] = phases
        # V8: Frame generation off for 4 s after the phases, then the saved value again (the client part restores it).
        settings["fg_check"] = fg_check
        settings["fg_check_at"] = len(phases if phases is not None else range(14)) * 8 + 2
        original_script(path, settings)
        with path.open("a", encoding="utf-8") as stream:
            stream.write("\n" + Path(__file__).with_name("vr_interact_poc_client.lua").read_text(encoding="utf-8"))

    def command(args, evidence, label, **kwargs):
        if label == "game":
            field = poc.game_processes(driver.FIELD)
            if field:
                main_root=driver.main_checkout()
                helper=main_root/"out/vr/v2/quit_field_game.py"
                with (evidence/"field-quit.log").open("w",encoding="utf-8") as stream:
                    quit_result=subprocess.run([sys.executable,str(helper)],cwd=main_root,stdout=stream,stderr=subprocess.STDOUT)
                driver.write_json(evidence/"field-quit.json",{"pids":field,"helper":str(helper),"exit":quit_result.returncode,
                    "authority":"User authorised ending the field game for GPU/SteamVR tests by this normal-console-quit helper."})
                if quit_result.returncode or poc.game_processes(driver.FIELD):
                    raise RuntimeError("Authorised field-game quit did not complete; see field-quit.log")
            code = Path(__file__).with_suffix(".lua").read_text(encoding="utf-8")
            extra = []
            for line in poc.client_lua_lines("vr_interact", code):
                extra += ["--console", line.replace("lua_run_cl", "lua_run", 1)]
            arguments = evidence / "game-arguments.json"
            driver.write_json(arguments, [str(v) for v in args[1:] + extra])
            args = [Path(__file__).resolve(), "--poc-arguments", arguments]
        return original_command(args, evidence, label, **kwargs)

    driver.timeline, driver.lua_script, driver.command = lambda seconds: timeline(seconds, phases), script, command
    code = driver.main()
    evidence = Path(sys.argv[sys.argv.index("--evidence") + 1])
    console = evidence / "poc/game/console.log"
    if console.exists():
        records = []
        for line in console.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("NLVR_P "):
                records.append(json.loads(line[7:]))
        driver.write_json(evidence / "interaction.json", records)
        print(f"Physical interaction records: {len(records)}", flush=True)
    return code


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--poc-arguments":
        raise SystemExit(poc.main(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))))
    raise SystemExit(main())
