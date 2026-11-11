"""Run the disposable S4 PoC experiment under both shared locks, with rollback."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[3]
MAIN = REPO.parents[2]
GAME = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod_PoC")
FIELD = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod")
OUT = MAIN / "out/vr/d/s4"


def run(args, name):
    result = subprocess.run([sys.executable, *map(str,args)], cwd=REPO,
                            capture_output=True, text=True, encoding="utf-8", errors="replace")
    (OUT / name).write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"{name}: exit {result.returncode}")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def session(name,force_queued=False):
    args=[REPO/"tools/poc_session.py","--evidence",OUT/"poc","run","--name",name,
          "--addons","--extra=-insecure","--lua",Path(__file__).with_name("probe.lua"),
          "--lua",Path(__file__).with_name("module_smoke.lua"),
          "--lua-shots","90","--settle","2","--screenshots","0","--timeout","300"]
    if force_queued:
        args.extend(["--console","mat_queue_mode 2"])
    run(args,"run-"+name+".log")
    log=(OUT/"poc"/name/"console.log").read_text(encoding="utf-8")
    for marker in ["NL_S4_ACCEPTED","NL_S4_RENDER_LAYOUT","NL_D_MODULE_DONE",
                   r"NL_D_MODULE_RESULT\s+failed\s+missing export: rtxvr_GetApiVersion",
                   r"NL_D_MODULE_FINAL\s+off",r"NL_D_MODULE_OFF_FRAME\s+true",
                   r"NL_D_MODULE_STOPPED_FRAME\s+true"]:
        if not re.search(marker,log):
            raise RuntimeError("missing expected probe marker: "+marker)
    record=json.loads((OUT/"poc/session.json").read_text(encoding="utf-8"))[-1]
    if not record.get("normal_quit") or record.get("settings_back")!="restored":
        raise RuntimeError("session did not quit normally with archived settings restored")
    match=re.search(r"(?m)^NL_S4_MODE\s+(-?\d+)",log)
    if not match:
        raise RuntimeError("probe did not print actual mat_queue_mode")
    return int(match.group(1))


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    if (OUT/"snapshot").exists():
        raise RuntimeError("existing S4 snapshot needs review before another session")
    scratch=REPO/"out/tmp"
    scratch.mkdir(parents=True,exist_ok=True)
    os.environ["TEMP"]=os.environ["TMP"]=str(scratch)
    locks = [MAIN / "out/r10/poc.lock", MAIN / "out/vr/vr.lock"]
    owner = "VR-V1-D-S4 " + datetime.datetime.now(datetime.timezone.utc).isoformat()
    handles = []
    deadline = time.monotonic() + 1800
    while not handles:
        try:
            for path in locks:
                path.parent.mkdir(parents=True, exist_ok=True)
                handle = path.open("x",encoding="utf-8")
                handle.write(owner+"\n");handle.flush()
                handles.append((path,handle))
        except FileExistsError:
            for path,handle in reversed(handles):
                handle.close();path.unlink()
            handles.clear()
            if time.monotonic() >= deadline:
                raise RuntimeError("timed out waiting for shared locks")
            print("S4 waiting for PoC/VR locks",flush=True)
            time.sleep(5)
    snapshot = OUT / "snapshot"
    before = {}
    try:
        # Inventory is captured before anything touches the PoC. A live game refuses the test.
        inventory = subprocess.run(["powershell","-NoProfile","-Command",
            "Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(gmod|python|vrserver|vrcompositor|vrmonitor).*' } | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Depth 3"],
            capture_output=True,text=True,encoding="utf-8",errors="replace")
        (OUT / "processes-before.json").write_text(inventory.stdout,encoding="utf-8")
        processes = json.loads(inventory.stdout)
        if any(p["Name"].lower()=="gmod.exe" for p in processes):
            raise RuntimeError("a game is running; S4 did not touch it")
        watched = [GAME/"user.conf",GAME/"bin/win64/materialsystem.dll",GAME/"garrysmod/cfg/config.cfg"]
        before = {str(p):digest(p) for p in watched}
        (OUT/"hashes-before.json").write_text(json.dumps(before,indent=2),encoding="utf-8")
        run([REPO/"tools/field_snapshot.py","--snapshot",snapshot,"snapshot","--root",GAME,
             "--manifests-from",FIELD],"snapshot.log")
        modules = [REPO / "out/vr/d/s4/build/gmcl_nlvrs4_win64.dll",
                   REPO / "out/build/win64-release/vr/native/gmcl_nlvr_win64.dll"]
        hashes={}
        for dll in modules:
            target=GAME / "garrysmod/lua/bin" / dll.name
            if target.exists():
                raise RuntimeError("module path already exists; refusing to replace: "+str(target))
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(dll,target)
            hashes[dll.name]=digest(dll)
        (OUT/"module-sha256.json").write_text(json.dumps(hashes,indent=2),encoding="ascii")
        if session("queue-default")!=2:
            session("queue-mode2",True)
    finally:
        if snapshot.is_dir() and (snapshot/"snapshot.json").is_file():
            try:
                run([REPO/"tools/field_snapshot.py","--snapshot",snapshot,"rollback"],"rollback.log")
                rollback=json.loads((snapshot/"rollback.json").read_text(encoding="utf-8"))
                shutil.copy2(snapshot/"rollback.json",OUT/"rollback.json")
                if not rollback.get("clean"):
                    raise RuntimeError("snapshot rollback was not clean; retain snapshot")
                after={p:digest(Path(p)) for p in before}
                (OUT/"hashes-after.json").write_text(json.dumps(after,indent=2),encoding="utf-8")
                if before!=after:
                    raise RuntimeError("watched hashes differ after rollback")
                # Authorized evidence cleanup, only after the rollback and hash comparison.
                checked=snapshot.resolve()
                if checked.parent != OUT.resolve():
                    raise RuntimeError("snapshot cleanup escaped S4 evidence")
                shutil.rmtree(checked)
            finally:
                for path,handle in reversed(handles):
                    handle.close();path.unlink()
        else:
            for path,handle in reversed(handles):
                handle.close();path.unlink()
    print("S4 session complete; rollback verified",flush=True)


if __name__=="__main__":
    main()
