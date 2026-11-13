"""Task P's fixture/timeline extension of the shared, lock-owning VR session driver."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc


def timeline(seconds, phases=None):
    steps = []

    def step(time, x=.3, z=1.2, grip=False, left=False, lx=.3, yaw=0, lz=1.2, span=.3):
        steps.append({"time": time, "hmd": {"pos": [0, 0, 1.6], "ang": [0, 0, 0]},
                      "left": {"pos": [lx, span, lz], "ang": [0, 0, 0]},
                      "right": {"pos": [x, -span, z], "ang": [0, yaw, 0]},
                      "actions": {"right_grip": grip, "left_grip": left}})

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
        if not phases or any(n < 0 or n > 13 for n in phases):
            raise ValueError("interaction phases must be 0..13")
        del sys.argv[slot:slot+2]

    def script(path, settings):
        settings["interact_phases"] = phases
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
