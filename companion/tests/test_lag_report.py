"""Run the companion's lag report against a stand-in hook table under LuaJIT (R28, ADR 0143)."""
from pathlib import Path
import subprocess
import unittest
from test_mmd_alpha import LUAJIT, ROOT


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class LagReportTests(unittest.TestCase):
    def test_hooks_are_timed_put_back_and_named_with_their_add_on(self):
        # client and server: GMod's hook table; ulib: a function per priority; copy: a hook library the report
        # does not know; failure: the report cannot be written.
        for scenario in ("client", "server", "ulib", "copy", "failure"):
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(Path(__file__).with_name("lag_report_harness.lua")),
                                         str(ROOT / "companion/nativeloader/lua/autorun/nativeloader_lag_report.lua"),
                                         scenario], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS " + scenario, result.stdout)


if __name__ == "__main__":
    unittest.main()
