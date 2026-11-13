"""Run VR-E's test-only stand-in in the real PoC, export evidence, and roll back."""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
MAIN = Path(subprocess.check_output(
    ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=ROOT, text=True).strip()).parent
POC = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod_PoC")
FIELD = POC.with_name("GarrysMod")
LOCK = MAIN / "out/r10/poc.lock"
BLOB = re.compile(r"(?m)^NLVR_E_BLOB ([\w.-]+) (\d+)/(\d+) ([A-Za-z0-9+/=]+)\s*$")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def lua_string(text):
    equals = "===="
    while "]" + equals + "]" in text:
        equals += "="
    return "[" + equals + "[" + text + "]" + equals + "]"


def build_probe(path):
    sources = {
        "page": ROOT / "companion/nativeloader/lua/autorun/client/nativeloader_vr.lua",
        "addon": ROOT / "vr/addon/lua/nlvr/client.lua",
        "standin": Path(__file__).with_name("vr_standin.lua"),
    }
    sources.update({p.relative_to(ROOT / "vr/addon/lua").as_posix(): p
                    for p in sorted((ROOT / "vr/addon/lua/nlvr").rglob("*.lua"))})
    text = "local TEST_SOURCES = {\n" + "\n".join(
        f"[{lua_string(name)}] = {lua_string(source.read_text(encoding='utf-8'))}," for name, source in sources.items()) + "\n}\n"
    text += Path(__file__).with_suffix(".lua").read_text(encoding="utf-8")
    path.write_text(text, encoding="utf-8")
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources.values()}


def blobs(console, folder):
    found = {}
    for name, index, total, payload in BLOB.findall(console):
        item = found.setdefault(name, {"total": int(total), "chunks": {}})
        assert item["total"] == int(total), name
        item["chunks"][int(index)] = payload
    for name, item in found.items():
        assert len(item["chunks"]) == item["total"], (name, "incomplete console payload")
        payload = "".join(item["chunks"][i] for i in range(1, item["total"] + 1))
        (folder / name).write_bytes(base64.b64decode(payload, validate=True))
    return found


def run(command, log, environment):
    with log.open("wb") as output:
        subprocess.run(command, cwd=ROOT, env=environment, stdout=output, stderr=subprocess.STDOUT, check=True)


def validate(folder, record):
    console = (folder / "console.log").read_text(encoding="utf-8")
    exported = blobs(console, folder)
    assert "result.json" in exported and "wrist.png" in exported, "missing stand-in result/canvas"
    result = json.loads((folder / "result.json").read_text(encoding="utf-8"))
    assert result["success"], result.get("failure", "stand-in checks failed")
    assert record["normal_quit"] and record["exit"] == 0 and record["settings_back"] == "restored"
    expected_blocks = len(re.findall(r"(?m)^\[ERROR\] RunConsoleCommand: Command is blocked! \(fps_max\)", console))
    # A listen host echoes the same client Lua error through the server's error forwarding too.
    expected_echoes = 2 if result["mode"] == "listen-host" else 1
    assert expected_blocks == expected_echoes and record["lua_errors"] == expected_blocks, "unexpected Lua error"
    assert len(record["lua_shots"]) == 7 and record["lua_shots_done"], "incomplete camera/cleanup screenshots"
    from PIL import Image
    with Image.open(io.BytesIO((folder / "wrist.png").read_bytes())) as image:
        image.load()
        assert image.size == (769, 257)
        assert len(image.convert("RGB").getcolors(769 * 257)) > 10, "canvas contains no raster text"
    summary = {"mode": result["mode"], "success": True, "cameras": len(result["cameras"]),
               "camera_error": result["max_camera_error"], "render_error": result["max_render_error"],
               "getpos_delta": result["max_getpos_delta"], "pose_age": result["max_pose_age"],
               "duplicate_pushes": result["duplicate_pushes"], "foreign_calls": result["foreign_calls"],
               "render_checks": result["render_checks"], "repeated_checks": result["repeated_checks"],
               "engine_probes": result["engine_probes"], "snapshots": [s["label"] for s in result["snapshots"]],
               "viewmodel_frames": result["viewmodel_frames"], "hand_frames": result["hand_frames"],
               "viewmodel_while_running": result["viewmodel_while_running"], "hands_while_running": result["hands_while_running"],
               "hud_while_running": result["hud_while_running"],
               "hud_frames": result["hud_frames"], "wrist": result["wrist"], "lua_errors": record["lua_errors"],
               "expected_blocked_command_diagnostics": expected_blocks, "unexpected_lua_errors": record["lua_errors"]-expected_blocks}
    first = result["camera_samples"][0]["getpos"]
    summary["movement_distance"] = max(math.dist([sample["getpos"][key] for key in ("x", "y", "z")],
                                                 [first[key] for key in ("x", "y", "z")]) for sample in result["camera_samples"])
    write_json(folder / "summary.json", summary)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=MAIN / "out/vr/e/review")
    parser.add_argument("--tag", default="r1")
    parser.add_argument("--players", choices=("both", "1", "2"), default="both")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--evaluate-only", action="store_true", help="validate saved runs/rollback without launching a game")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,24}", args.tag):
        parser.error("--tag must be a short filename-safe label")
    evidence = args.evidence.resolve()
    if not evidence.is_relative_to((MAIN / "out").resolve()):
        parser.error("--evidence must stay under this repository's out directory")
    evidence.mkdir(parents=True, exist_ok=True)
    players = (1, 2) if args.players == "both" else (int(args.players),)
    if args.evaluate_only:
        records = json.loads((evidence / "poc/session.json").read_text(encoding="utf-8"))
        summaries = []
        for number in players:
            name = f"{args.tag}-standin-" + ("sp" if number == 1 else "host")
            record = next(r for r in reversed(records) if r.get("name") == name)
            summaries.append(validate(evidence / "poc" / name, record))
            print("PASS", name)
        assert json.loads((evidence / (args.tag + "-snapshot") / "rollback.json").read_text(encoding="utf-8"))["clean"]
        write_json(evidence / (args.tag + "-summary.json"), summaries)
        print("PASS saved rollback")
        return 0
    scratch = ROOT / "out/vr/e/review"
    scratch.mkdir(parents=True, exist_ok=True)
    probe = scratch / (args.tag + "-probe.lua")
    sources = build_probe(probe)
    write_json(evidence / (args.tag + "-sources.json"), {"files": sources, "probe_sha256": hashlib.sha256(probe.read_bytes()).hexdigest()})
    if args.build_only:
        print(probe)
        return 0
    environment = os.environ.copy()
    (ROOT / "out/tmp").mkdir(parents=True, exist_ok=True)
    environment["TEMP"] = environment["TMP"] = str(ROOT / "out/tmp")
    owner = json.dumps({"task": "VR-V1-E review", "pid": os.getpid(), "started": dt.datetime.now(dt.timezone.utc).isoformat()})
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    waiting = 0
    while True:
        try:
            with LOCK.open("x", encoding="utf-8") as lock:
                lock.write(owner)
            break
        except FileExistsError:
            if waiting % 5 == 0:
                print("Waiting for PoC lock:", LOCK.read_text(encoding="utf-8")[:220], flush=True)
            waiting += 1
            time.sleep(3)
    print("Acquired PoC lock for", args.tag, flush=True)
    snapshot = evidence / (args.tag + "-snapshot")
    acquired_snapshot = False
    summaries = []
    try:
        sys.path.insert(0, str(ROOT / "tools"))
        import poc_session
        live = [(pid, poc_session.process_path(pid)) for pid, _, name in poc_session.process_entries()
                if name.lower() == "gmod.exe"]
        write_json(evidence / (args.tag + "-processes-before.json"), live)
        assert not any(path and Path(path).resolve() == (POC / "bin/win64/gmod.exe").resolve() for _, path in live), "PoC still running"
        run([sys.executable, "tools/field_snapshot.py", "--snapshot", str(snapshot), "snapshot", "--root", str(POC),
             "--manifests-from", str(FIELD)], evidence / (args.tag + "-snapshot.log"), environment)
        acquired_snapshot = True
        for number in players:
            name = f"{args.tag}-standin-" + ("sp" if number == 1 else "host")
            setup = ('lua_run local p=Entity(1) p:SetHealth(87) p:SetArmor(31) '
                     'local w=p:Give("weapon_pistol") if IsValid(w) then w:SetClip1(12) '
                     'p:SetAmmo(36,"Pistol") p:SelectWeapon("weapon_pistol") end')
            command = [sys.executable, "tools/poc_session.py", "--evidence", str(evidence / "poc"), "run", "--name", name,
                       "--players", str(number), "--addons", "--width", "1920", "--height", "1080", "--extra=-insecure",
                       "--extra=+fps_max", "--extra=60.000", "--console", "cl_drawhud 1", "--console", "r_drawviewmodel 1",
                       "--console", "rtx_pseudoplayer 1", "--console", "rtx_pseudoweapon 1", "--console", setup,
                       "--lua", str(probe), "--lua-shots", "120", "--settle", "3", "--screenshots", "0"]
            print("Running", name, flush=True)
            run(command, evidence / (name + "-driver.log"), environment)
            records = json.loads((evidence / "poc/session.json").read_text(encoding="utf-8"))
            record = next(r for r in reversed(records) if r.get("name") == name)
            summary = validate(evidence / "poc" / name, record)
            assert summary["mode"] == ("single-player" if number == 1 else "listen-host")
            summaries.append(summary)
            print("Passed", name, "cameras", summary["cameras"], "error", summary["camera_error"], flush=True)
    finally:
        try:
            if acquired_snapshot:
                run([sys.executable, "tools/field_snapshot.py", "--snapshot", str(snapshot), "rollback", "--config", "Release"],
                    evidence / (args.tag + "-rollback.log"), environment)
                rollback = json.loads((snapshot / "rollback.json").read_text(encoding="utf-8"))
                assert rollback["clean"], "PoC rollback not clean"
                print("Rollback clean", flush=True)
        finally:
            if LOCK.read_text(encoding="utf-8") == owner:
                LOCK.unlink()
                print("Released PoC lock", flush=True)
    write_json(evidence / (args.tag + "-summary.json"), summaries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
