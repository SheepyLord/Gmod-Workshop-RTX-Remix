"""S's scaffold and engine weapon stand-ins, executed without a game or OpenVR."""
from pathlib import Path
import subprocess
import unittest
from test_mmd_alpha import LUAJIT, ROOT

FRAMEWORK = ("protocol", "client_network", "server_network", "overlays", "settings", "page", "stubs", "head_roll", "aim_movement")
STANDINS = ("weapon", "clips", "ammo_types", "next_fire", "world_model", "hold_type", "scripted", "inventory", "active",
            "ammo_count", "give_ammo", "remove_ammo", "set_ammo", "give", "strip", "select", "buttons", "wheel", "command_select",
            "bullets", "register", "attachments", "bones", "model_lifecycle")


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRScaffoldTests(unittest.TestCase):
    def run_case(self, scenario, framework=False):
        harness = "vr_harness.lua" if framework else "vr_v4_harness.lua"
        scenario = "f_v4_" + scenario if framework else scenario
        run = subprocess.run([LUAJIT, str(Path(__file__).with_name(harness)), str(ROOT), scenario],
                             cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("PASS " + scenario, run.stdout)


for _name in FRAMEWORK:
    setattr(VRScaffoldTests, "test_" + _name, lambda self, name=_name: self.run_case(name, True))
for _name in STANDINS:
    setattr(VRScaffoldTests, "test_standin_" + _name, lambda self, name=_name: self.run_case(name))

if __name__ == "__main__":
    unittest.main()
