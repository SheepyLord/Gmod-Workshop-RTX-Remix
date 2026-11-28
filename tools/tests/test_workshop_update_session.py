"""Offline WU game probe, screenshot protocol, evidence checks and Sandbox save isolation."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

if sys.platform != "win32":
    raise unittest.SkipTest("the PoC driver uses the Windows session tool")

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS / "qa"))
import workshop_update_session as wu
import workshop_update_fixtures as fixtures

LUAJIT = shutil.which("luajit") or str(Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/LuaJIT/bin/luajit.exe")
HARNESS = Path(__file__).with_name("workshop_update_probe_harness.lua")


def probe_logs(scenario):
    process = subprocess.run([LUAJIT, str(HARNESS), str(wu.QA), scenario], capture_output=True,
                             text=True, encoding="utf-8", timeout=15)
    if process.returncode:
        raise AssertionError(process.stderr + process.stdout[-1000:])
    return dict(zip(("v1", "v2"), process.stdout.split("HARNESS v1\n")[1].split("HARNESS v2\n"), strict=True))


def simulated_receipt(phase, text, folder):
    folder.mkdir(parents=True)
    (folder / "status.json").write_text(json.dumps({"packages": [
        {"id": "wu-fixture", "source": "local", "version": wu.VERSION[phase]}]}))
    shots = []
    for i, label in enumerate(re.findall(r"^NL_SHOT (\S+)$", text, re.M), 1):
        name = f"shot-{i:02d}-{label}.png"
        (folder / name).write_bytes(b"\x89PNG\r\n\x1a\n")
        shots.append({"file": name, "label": label})
    return {"normal_quit": True, "exit": 0, "activation": {"outcome": "active"},
            "lua_shots_done": True, "lua_shots": shots, "lua": [{"started": True}]}


class WorkshopUpdateSessionTests(unittest.TestCase):
    def setUp(self):
        tmp = wu.REPO / "out/tmp"
        tmp.mkdir(parents=True, exist_ok=True)
        temp = tempfile.TemporaryDirectory(dir=tmp)
        self.addCleanup(temp.cleanup)
        self.scratch = Path(temp.name)

    def test_control_packet_declares_its_actual_raw_size_in_both_exports(self):
        codec = wu.mmdhl_pack.Codec()
        raw = b'{"bones":1}'
        digest = hashlib.sha256(raw).hexdigest()
        for version, whitespace in (("v1", b" "), ("v2", b"\t")):
            addon = self.scratch / version
            base = addon / "data_static/mmdhl"
            path = "assets/" + wu.HELENA + "/manifest.json"
            (base / "packages").mkdir(parents=True)
            (base / "files").mkdir()
            src = wu.mmdhl_pack.pack(codec, raw, digest)
            (base / "files" / (digest + ".dat")).write_bytes(src)
            manifest = base / "packages/build.json"
            manifest.write_text(json.dumps({"items": [{"key": "helena-dorm", "asset": wu.HELENA}],
                "files": {path: {"sha256": digest, "size": len(raw), "packed": len(src)}}}))
            fixtures.change_control_manifest(addon, whitespace)
            meta = json.loads(manifest.read_bytes())["files"][path]
            packet = (base / "files" / (meta["sha256"] + ".dat")).read_bytes()
            self.assertEqual(len(packet), meta["packed"])
            self.assertEqual(wu.mmdhl_pack.unpack(codec, packet, meta["size"], meta["sha256"]), raw + whitespace)

    def test_session_arguments_and_every_injected_console_line(self):
        selector = "mmd_" + "a" * 16
        for phase in wu.VERSION:
            config, launch = wu.commands(self.scratch, phase, selector)
            self.assertIn(str(wu.fixture(phase)), config)
            self.assertIn(str(wu.RTX), config)
            self.assertIn("--lua-shots", launch)
            self.assertNotIn("--lua-manual", launch)
            self.assertNotIn("--load-save", launch)
            self.assertEqual("--extra=" + selector in launch, phase == "v2")
            code = wu.poc.file_lua(1, (wu.REPO / wu.PROBE).read_text(encoding="utf-8"))
            lines = wu.poc.client_lua_lines("lua1", code)
            lines.extend(launch[i+1] for i, arg in enumerate(launch) if arg == "--console")
            self.assertTrue(all(len(line.encode("utf-8")) < 500 for line in lines))

    def test_existing_saves_return_after_verified_preservation(self):
        root, evidence = self.scratch / "poc", self.scratch / "run"
        saves = root / "garrysmod/saves"
        saves.mkdir(parents=True)
        (saves / "original.gms").write_bytes(b"original")
        wu.vs.preserve(root, evidence, include_saves=True)
        self.assertFalse(saves.exists())
        saves.mkdir()
        (saves / "wu.gms").write_bytes(b"test")
        (evidence / "snapshot").mkdir()
        (evidence / "snapshot/rollback.json").write_text('{"clean":true}')
        with mock.patch.object(wu.poc, "game_processes", return_value=[]), mock.patch.object(wu.vs, "command"):
            result = wu.vs.restore(root, evidence)
        self.assertTrue(result["originals"]["garrysmod/saves"])
        self.assertEqual([p.name for p in saves.iterdir()], ["original.gms"])
        self.assertEqual((saves / "original.gms").read_bytes(), b"original")
        self.assertEqual((evidence / "generated/garrysmod/saves/wu.gms").read_bytes(), b"test")

    @unittest.skipUnless(Path(LUAJIT).is_file(), "LuaJIT is not installed")
    def test_actual_probes_and_verdicts(self):
        for scenario in ("good", "reset_realm", "wrong_head", "old_player", "duplicate", "stale_pose", "no_paste"):
            with self.subTest(scenario=scenario):
                baseline = None
                for phase, text in probe_logs(scenario).items():
                    self.assertEqual(text.splitlines()[-1], "NL_SHOT_DONE")
                    rows = wu.results(text, "mock000000000001", phase)
                    folder = self.scratch / scenario / phase
                    receipt = simulated_receipt(phase, text, folder)
                    if phase == "v1" or scenario in ("good", "reset_realm"):
                        wu.validate(rows, phase, receipt, folder, baseline)
                    else:
                        with self.assertRaises(ValueError):
                            wu.validate(rows, phase, receipt, folder, baseline)
                    if phase == "v1":
                        by_event = {r["event"]: r for r in rows}
                        baseline = {"selector": by_event["player"]["selector"], "citizen": by_event["head"]["key"],
                                    "used": by_event["recent"]["used"], "save": by_event["save"]}
                    elif scenario == "good":
                        control = next(r for r in rows if r["event"] == "helena")
                        control["bytes"] -= 1
                        with self.assertRaisesRegex(ValueError, "equal-size"):
                            wu.validate(rows, phase, receipt, folder, baseline)

    @unittest.skipUnless(Path(LUAJIT).is_file(), "LuaJIT is not installed")
    def test_driver_handoff_and_rollback_on_pass_and_fail(self):
        fake_rtx = self.scratch / "rtx.gma"
        fake_rtx.touch()
        for scenario in ("good", "wrong_head"):
            root = self.scratch / scenario / "poc"
            evidence = self.scratch / scenario / "evidence"
            saves = root / "garrysmod/saves"
            saves.mkdir(parents=True)
            (saves / "user.gms").write_bytes(b"own saved world")
            calls = []
            logs = probe_logs(scenario)

            def command(args, dest, name, allowed=(0,)):
                self.assertEqual(dest, evidence)
                calls.append(name)
                if name == "snapshot":
                    self.assertEqual(args[args.index("--root") + 1], root)
                if name == "rollback":
                    wu.vs.write_json(dest / "snapshot/rollback.json", {"clean": True})
                if not name.endswith("-run"):
                    return
                phase = name[:2]
                data = root / "garrysmod/data/nl_wu"
                ctx = json.loads((data / "run.json").read_bytes())
                self.assertEqual(ctx["phase"], phase)
                text = logs[phase].replace("mock000000000001", ctx["token"])
                folder = dest / "poc" / phase
                receipt = simulated_receipt(phase, text, folder)
                (folder / "console.log").write_text(text, encoding="utf-8")
                wu.vs.write_json(dest / "poc/session.json", [receipt])
                if phase == "v1":
                    events = {r["event"]: r for r in wu.results(text, ctx["token"], phase)}
                    saves.mkdir()
                    (saves / "gm_flatgrass mock.gms").write_bytes(b"Sandbox")
                    body = events["player"]
                    wu.vs.write_json(data / "baseline.json", {"token": ctx["token"], "selector": body["selector"],
                        "citizen": events["head"]["key"], "player": body["body_key"], "arms": body["arms_key"],
                        "used": events["recent"]["used"], "save": events["save"]})
                else:
                    saved = json.loads((dest / "baseline.json").read_bytes())
                    self.assertIn("--extra=" + saved["selector"], args)
                    self.assertEqual((dest / "v1.gms").read_bytes(), b"Sandbox")

            with mock.patch.object(wu, "RTX", fake_rtx), mock.patch.object(wu, "fixture_id", side_effect=lambda v: v), \
                    mock.patch.object(wu.vs, "main_checkout", return_value=self.scratch), \
                    mock.patch.object(wu.vs, "command", side_effect=command), \
                    mock.patch.object(wu.poc, "DEFAULT_ROOT", root), mock.patch.object(wu.poc, "game_processes", return_value=[]), \
                    contextlib.redirect_stdout(io.StringIO()):
                if scenario == "good":
                    self.assertEqual(wu.main(["--evidence", str(evidence)]), 0)
                else:
                    with self.assertRaisesRegex(ValueError, "probe failed"):
                        wu.main(["--evidence", str(evidence)])
                self.assertEqual(wu.main(["--evidence", str(evidence), "--restore"]), 0)
            self.assertEqual(calls, ["snapshot", "v1-config", "v1-run", "v2-config", "v2-run", "rollback"])
            self.assertEqual([p.name for p in saves.iterdir()], ["user.gms"])
            self.assertEqual((saves / "user.gms").read_bytes(), b"own saved world")


if __name__ == "__main__":
    unittest.main()
