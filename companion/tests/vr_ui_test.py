"""Task M's production Lua modules against the framework's math and bounded VGUI stand-ins."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from test_mmd_alpha import LUAJIT, ROOT

SCENARIOS = ("pixels", "click_drag", "claims", "dominant_capture", "scroll_close", "cursor_error", "window_cursor", "keyboard",
             "keyboard_unavailable", "keyboard_edit", "keyboard_layout", "window_dispatch", "fallback_typing", "fallback_window_text", "keyboard_reentrant", "keyboard_nontext", "keyboard_switch", "keyboard_toolbar_wait", "keyboard_numeric", "panels", "wrist", "module_debug", "deferred_button", "window", "window_menu", "context_widget", "baseline_flags", "invalid_head", "resolution_error", "page")


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRUITests(unittest.TestCase):
    def run_case(self, name):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_ui_harness.lua")), str(ROOT), name],
                                cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + name, result.stdout)


for _name in SCENARIOS:
    setattr(VRUITests, "test_" + _name, lambda self, name=_name: self.run_case(name))


for _name in ("review_restore_throw", "review_wrist_exit"):
    setattr(VRUITests, "test_" + _name, lambda self, name=_name: self.run_case(name))

setattr(VRUITests,"test_verify_window_refusal",lambda self:self.run_case("verify_window_refusal"))
setattr(VRUITests,"test_verify_background_drag_cursor",lambda self:self.run_case("verify_background_drag_cursor"))
setattr(VRUITests,"test_verify_background_drag_events",lambda self:self.run_case("verify_background_drag_events"))

class VRUIPreflightTests(unittest.TestCase):
    def test_no_pillow_refuses_before_evidence_or_locks(self):
        scratch = ROOT / "out/tmp"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch, prefix="vr-ui-preflight-") as td:
            evidence = Path(td) / "never-created"
            result = subprocess.run([sys.executable, "-E", "-S", str(Path(__file__).with_name("vr_ui_poc.py")),
                "--package", str(Path(td) / "not-required.gma"), "--evidence", str(evidence)],
                cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("Pillow", result.stderr)
            self.assertFalse(evidence.exists())

if __name__ == "__main__":
    unittest.main()
