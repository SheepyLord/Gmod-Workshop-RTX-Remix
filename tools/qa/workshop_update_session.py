"""Run WU's two unattended PoC launches, retain their evidence and restore the install."""
import argparse
import json
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

QA = Path(__file__).resolve().parent
TOOLS = QA.parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "gmapack"))
sys.path.insert(0, str(REPO / "skills/workshop-content-pack/scripts"))
import gmapack
import mmdhl_pack
import poc_session as poc
import vr_session as vs

ARTIFACTS = Path("out/wsup")
RTX = ARTIFACTS / "rtx/gmod-rtx-remix-0.0.0-dev.20261128114114_daa2c523.gma"
PROBE = Path("tools/qa/workshop_update_probe.lua")
GYM = {"v1": "7c6d7e466389899bbdd2c9d614e1dacbf8a1a62bfa1b2af0083742553aeda89c",
       "v2": "a95c9a34a5eec099b19769e8968b64fa2947e738d34fdb17711dd2ee170bde50"}
HELENA = "81b3caae0303d15a610ef213bd4c64366c9b9e2f6dda1eae2e5d5fa49a74c80b"
CONTROL = {"v1": "663b8b295a042f8e8f448a8d4f4734d1d74b5f062d1368d0340cd38ca1bbae5a",
           "v2": "2747fec1c9ae250309ab6c9a01100d0a10bf874173f9be4d893a0b1c4dd83c59"}
VERSION = {"v1": "1.0.0", "v2": "1.1.0"}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def fixture(phase):
    return ARTIFACTS / "fixtures" / phase / "wu-fixture.gma"


def fixture_id(phase):
    pattern = r"native/root/garrysmod/addons/mmdhl_wu_fixture/data_static/mmdhl/packages/([0-9a-f]{32})\.json"
    with gmapack.read_gma(str(REPO / fixture(phase))) as archive:
        entry, = [item for item in archive.files if re.fullmatch(pattern, item["name"])]
        archive.fh.seek(entry["offset"])
        pack = json.loads(archive.fh.read(entry["size"]))
        packets = {item["name"]: item for item in archive.files}
        base = entry["name"].rsplit("/packages/", 1)[0] + "/files/"
        codec = mmdhl_pack.Codec()
        for meta in pack["files"].values():
            packet = packets[base + meta["sha256"] + ".dat"]
            require(packet["size"] == meta["packed"], f"{phase} packed length mismatch")
            archive.fh.seek(packet["offset"])
            mmdhl_pack.unpack(codec, archive.fh.read(packet["size"]), meta["size"], meta["sha256"])
    require(pack["id"] == Path(entry["name"]).stem and {i["asset"] for i in pack["items"]} == {GYM[phase], HELENA},
            f"{phase} is not the expected Gym/Helena fixture")
    manifest = pack["files"][f"assets/{HELENA}/manifest.json"]
    require(manifest["sha256"] == CONTROL[phase] and manifest["size"] == 63247, f"wrong {phase} Helena control")
    return pack["id"]


def commands(evidence, phase, selector=None):
    base = ["tools/poc_session.py", "--evidence", str(evidence / "poc")]
    config = ["install", "--replace-config"] if phase == "v1" else ["config"]
    config += ["--allow-local", str(RTX), "--allow-local", str(fixture(phase)), "--subscribed-content", "off", "--remix", "on"]
    run = ["run", "--name", phase, "--map", "gm_flatgrass", "--players", "1", "--addons", "--extra=-insecure",
           "--extra=+gamemode", "--extra=sandbox"]
    if phase == "v2":
        run.extend(["--extra=+cl_playermodel", "--extra=" + selector])
    run.extend(["--console", "engine_no_focus_sleep 0", "--console", "gmod_npcweapon none", "--console", "hideconsole",
                "--hide-hud", "--lua", str(PROBE), "--lua-shots", "780", "--screenshots", "0", "--settle", "0",
                "--width", "1600", "--height", "900", "--timeout", "900"])
    return base + config, base + run


def results(text, token, phase):
    rows = []
    done = False
    for line in text.splitlines():
        if line == "NL_SHOT_DONE":
            require(not done and rows and rows[-1]["event"] == "result", "misplaced NL_SHOT_DONE")
            done = True
        elif line.startswith("NL_WU "):
            require(not done, "probe output after NL_SHOT_DONE")
            require(len(line.encode("utf-8")) < 500, "oversized NL_WU result")
            row = json.loads(line[6:])
            require(row["run"] == token and row["phase"] == phase, "stale probe output")
            rows.append(row)
    require(done, "missing NL_SHOT_DONE")
    return rows


def validate(rows, phase, receipt, folder, baseline=None):
    def events(name):
        return [row for row in rows if row["event"] == name]

    require(rows and rows[-1]["event"] == "result" and rows[-1].get("ok") is True and not events("mismatch"),
            f"{phase} probe failed or never finished: {rows[-1:]}")
    require(receipt.get("normal_quit") and receipt.get("exit") == 0 and not receipt.get("failed")
            and receipt.get("activation", {}).get("outcome") == "active" and receipt.get("lua_shots_done")
            and receipt.get("lua") and all(item["started"] for item in receipt["lua"]), f"{phase} session incomplete")
    if receipt.get("settings_source"):
        require(receipt.get("settings_back") == "restored", "Steam Cloud settings restoration did not complete")
    versions = json.loads((folder / "status.json").read_bytes())["packages"]
    require(any(p["id"] == "wu-fixture" and p["source"] == "local" and p["version"] == VERSION[phase] for p in versions),
            f"{phase} fixture did not deploy")
    views = [phase] if phase == "v1" else ["v2", "restored"]
    shots = receipt["lua_shots"]
    require([shot["label"] for shot in shots] == [f"wu_{view}_head" for view in views], "missing or out-of-order screenshots")
    for index, shot in enumerate(shots, 1):
        image = folder / f'shot-{index:02d}-{shot["label"]}.png'
        require(image.name == shot["file"] and image.is_file(), f"missing screenshot {image.name}")
        with image.open("rb") as png:
            require(png.read(8) == b"\x89PNG\r\n\x1a\n", f"invalid screenshot {image.name}")
    heads = events("head")
    require([h["view"] for h in heads] == views, "missing head measurement")
    for h in heads:
        version = "v1" if h["view"] == "restored" else phase
        reference = 2.756 if version == "v1" else 2.607
        require(h["asset"] == h["rig_asset"] == GYM[version] and h["role"] == "citizen"
                and h["sequence"].lower() == "reference" and abs(h["scale"] - 1.15) <= .001
                and abs(h["distance"] - reference) <= .03, f'wrong {h["view"]} rendered head')
    entries = events("entry")
    expected = {("Faelynn (Gym Uniform)", GYM[phase]), ("Helena (Dorm)", HELENA)}
    require({(e["name"], e["asset"]) for e in entries} == expected and len(entries) == 2 * len(views), "wrong library entries")
    require(len(events("library")) == len(views) and all(s["gym_rows"] == 1 and s["entries"] == 2
            and not s["busy"] and (phase == "v1" or s["replacement"] == GYM["v2"]) for s in events("library")),
            "incomplete library replacement")
    control, = events("helena")
    require(control["sha256"] == control["recorded"] == CONTROL[phase] and control["bytes"] == 63247, "stale equal-size manifest")
    player, = events("player")
    require(player["asset"] == GYM[phase] and player["selector"] == "mmd_" + player["body_key"][:16], "wrong player selector")
    rendered = {e["part"]: e for e in events("rendered")}
    for part, role, key in (("body", "player", "body_key"), ("hands", "arms", "arms_key")):
        r = rendered[part]
        require(r["role"] == role and r["asset"] == GYM[phase] and r["key"] == player[key]
                and r["model"] == r["actual_model"], f"wrong {part} carrier")
    when = "choices" if phase == "v1" else "before_spawn"
    published = {r["role"]: r for r in events("published") if r["when"] == when and r.get("role") in ("citizen", "player", "arms")}
    require(all(r["asset"] == r["indexAsset"] == GYM[phase] for r in events("published")
                if r.get("role") in ("citizen", "player", "arms")), "obsolete published rig")
    npc, = events("npc_entry")
    require(published["citizen"]["key"] == npc["key"] == heads[0]["key"] and
            published["player"]["key"] == player["body_key"] and published["player"]["arms"] ==
            published["arms"]["key"] == player["arms_key"], "published NPC/player/hands differ from the live carriers")
    recent = {r["asset"]: r["used"] for r in events("recent") if r["when"] == when}
    require(recent.get(GYM[phase], 0) > 0, "Gym absent from recent history")
    if phase == "v2":
        loaded, = events("load")
        require(baseline and player["previous_selector"] == baseline["selector"] != player["selector"]
                and GYM["v1"] not in recent and recent[GYM[phase]] >= baseline["used"], "v1 choice or history did not migrate")
        require(rows.index(player) < rows.index(heads[0]) < rows.index(loaded) < rows.index(heads[1]),
                "v2 observed the states out of order")
        require(any(r["when"] == "after_spawn" and r["asset"] == GYM[phase] for r in events("recent")),
                "missing post-spawn recent history")
        require(all(loaded[k] == baseline["save"][k] for k in ("path", "bytes", "sha256")) and
                heads[1]["key"] == baseline["citizen"], "restore did not use the v1 save and carrier")


def stage():
    addon = poc.DEFAULT_ROOT / "garrysmod/addons/nl_wu_qa"
    (addon / "lua/autorun").mkdir(parents=True)
    (addon / "lua/nl_wu").mkdir()
    (addon / "addon.json").write_text('{"title":"WU local check","type":"tool","tags":["fun"]}', encoding="ascii")
    shutil.copyfile(QA / "workshop_update_pose.lua", addon / "lua/autorun/nl_wu_pose.lua")
    shutil.copyfile(REPO / PROBE, addon / "lua/nl_wu/probe.lua")


def run(evidence, ids, token):
    scratch = poc.DEFAULT_ROOT / "garrysmod/data/nl_wu"
    baseline = None
    for phase in ("v1", "v2"):
        vs.write_json(scratch / "run.json", {"phase": phase, "package": ids[phase], "token": token})
        config, launch = commands(evidence, phase, baseline and baseline["selector"])
        vs.command(config, evidence, phase + "-config")
        vs.command(launch, evidence, phase + "-run", allowed=(0, 1))
        receipt = json.loads((evidence / "poc/session.json").read_bytes())[-1]
        folder = evidence / "poc" / phase
        rows = results((folder / "console.log").read_text(encoding="utf-8"), token, phase)
        vs.write_json(evidence / (phase + "-results.json"), rows)
        validate(rows, phase, receipt, folder, baseline)
        if phase == "v1":
            baseline = json.loads((scratch / "baseline.json").read_bytes())
            p, = (r for r in rows if r["event"] == "player")
            h, = (r for r in rows if r["event"] == "head")
            save, = (r for r in rows if r["event"] == "save")
            require(baseline["token"] == token and baseline["selector"] == p["selector"]
                    and re.fullmatch(r"mmd_[0-9a-f]{16}", p["selector"]) and baseline["citizen"] == h["key"]
                    and (baseline["player"], baseline["arms"]) == (p["body_key"], p["arms_key"])
                    and any(r["event"] == "recent" and r["asset"] == GYM["v1"] and r["used"] == baseline["used"] for r in rows),
                    "v1 handoff does not match observed selection")
            require(re.fullmatch(r'saves/[^/\\;%"\x00-\x1f]+\.gms', save["path"]) and
                    all(save[k] == baseline["save"][k] for k in ("path", "sha256", "bytes")), "wrong save receipt")
            saved = poc.DEFAULT_ROOT / "garrysmod" / save["path"]
            require(saved.resolve().parent == (poc.DEFAULT_ROOT / "garrysmod/saves").resolve()
                    and vs.sha256(saved) == save["sha256"], "v1 save file does not match its receipt")
            shutil.copyfile(saved, evidence / "v1.gms")
            vs.write_json(evidence / "baseline.json", baseline)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--evidence", type=Path, required=True, help="fresh run directory under out, or the directory to restore")
    actions = ap.add_mutually_exclusive_group()
    actions.add_argument("--plan", action="store_true", help="check the local inputs and print the command sequence offline")
    actions.add_argument("--restore", action="store_true", help="restore an interrupted WU run after its PoC exits")
    args = ap.parse_args(argv)
    main_root = vs.main_checkout()
    root = poc.DEFAULT_ROOT
    evidence = vs.inside_out(args.evidence, main_root)
    if not args.restore:
        require((REPO / RTX).is_file(), f"missing WU RTX archive {RTX}")
        ids = {phase: fixture_id(phase) for phase in VERSION}
        if args.plan:
            for phase in VERSION:
                config, launch = commands(args.evidence, phase, "$selector")
                print(subprocess.list2cmdline(["python", *map(str, config)]))
                if phase == "v2":
                    baseline_path = str(args.evidence / "baseline.json").replace("'", "''")
                    print(f"$selector = (Get-Content -Raw -LiteralPath '{baseline_path}' | ConvertFrom-Json).selector")
                print(subprocess.list2cmdline(["python", *map(str, launch)]))
            print("The runner snapshots before install and restores after v2, including on failure.")
            return 0
    with vs.ExclusiveLock(main_root / "out/r10/poc.lock", "WU two-launch character update", timeout=6 * 3600):
        require(not poc.game_processes(root), "a game is running in the PoC")
        if args.restore:
            plan = json.loads((evidence / "wu-plan.json").read_bytes())
            require(plan["root"] == str(root) and plan["task"] == "WU", "not a WU snapshot for this PoC")
            done = evidence / "restoration.json"
            if not done.exists() or not json.loads(done.read_bytes()).get("clean"):
                vs.restore(root, evidence)
            return 0
        require(not evidence.exists() or not any(evidence.iterdir()), "use a fresh evidence directory")
        vs.require_clean_transaction(main_root)
        evidence.mkdir(parents=True, exist_ok=True)
        token = uuid.uuid4().hex[:16]
        vs.write_json(evidence / "wu-plan.json", {"task": "WU", "root": str(root), "packages": ids, "token": token})
        vs.command(["tools/field_snapshot.py", "--snapshot", evidence / "snapshot", "snapshot", "--root", root,
                    "--manifests-from", poc.FIELD_ROOT], evidence, "snapshot")
        try:
            vs.preserve(root, evidence, include_saves=True)
            stage()
            run(evidence, ids, token)
        finally:
            if (evidence / "originals.json").exists():
                vs.restore(root, evidence)
        vs.cleanup(evidence)
    print("PASS WU. Both launches, the saved actor and PoC restoration verified.", evidence)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
