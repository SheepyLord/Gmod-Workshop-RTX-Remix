"""Task H's real hands module against independent skeleton, trace and matrix stand-ins."""
from pathlib import Path
import subprocess
import unittest
from test_mmd_alpha import LUAJIT, ROOT
from vr_frames_test import recorded_fixture

SCENARIOS = (
    "bones", "aliases", "missing_bones", "angles", "splay", "smoothing", "grip", "sanitization",
    "wall", "finger_envelope", "clear", "shoulder", "solid", "lifecycle", "models", "fallback", "world_draw",
    "matrices", "dominant", "invalid_tracking", "fault_cleanup", "skeleton_cache", "anatomy_reset", "render_rate_sampling",
)


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRHandsTests(unittest.TestCase):
    def run_scenario(self, scenario):
        with recorded_fixture() as fixture:
            result = subprocess.run(
                [LUAJIT, str(Path(__file__).with_name("vr_hands_harness.lua")), str(ROOT), scenario, str(fixture)],
                cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + scenario, result.stdout)


for _scenario in SCENARIOS:
    setattr(VRHandsTests, "test_" + _scenario,
            lambda self, scenario=_scenario: self.run_scenario(scenario))

setattr(VRHandsTests,"test_verify_pending_ghost",lambda self:self.run_scenario("verify_pending_ghost"))
setattr(VRHandsTests,"test_q4r_dispatch_peer",lambda self:self.run_scenario("q4r_dispatch_peer"))

if __name__ == "__main__":
    unittest.main()
