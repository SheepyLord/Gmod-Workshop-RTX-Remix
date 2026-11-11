"""V1's real page/add-on against an API-v1 nlvr stand-in, without OpenVR or a game."""
from pathlib import Path
import subprocess
import sys
import unittest
from test_mmd_alpha import LUAJIT, ROOT

SCENARIOS = (
    "idle", "probe", "missing_module", "require_error", "version", "runtime", "remote", "host", "vrmod", "gvrmod",
    "inactive_vrmod", "api_vrmod", "start_exit", "start_cancel", "failure", "failure_running", "start_error", "missing_addon",
    "guard_refused", "overlay_error", "quit", "off", "shutdown", "shutdown_starting", "hot_reload",
    "frame_error", "paint_error", "tracking", "no_tracking", "scale_latched", "hud", "notifications", "proxies", "wrist", "gpu", "metrics", "uncapped",
    "authoritative_view", "predicted_origin", "frame_once", "calcview_before_prerender",
    "review_nil_camera", "review_return_failures", "review_paused_poll", "review_native_stopping", "review_page_nil", "review_overlay_nil", "review_recenter",
    "sdk_ready", "async_stop", "cap_warning", "native_return_error", "missing_steamvr",
    "review2_busy_camera", "review2_overlay_ack", "review2_overlay_info_error",
)


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRTests(unittest.TestCase):
    def test_production_render_guard_accepts_wrist_canvas(self):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_guard_harness.lua")), str(ROOT)],
                                cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("native allocation=1; guard refusals=0", result.stdout)

    def run_scenario(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_harness.lua")), str(ROOT), scenario],
                                capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + scenario, result.stdout)


for _scenario in SCENARIOS:
    setattr(VRTests, "test_" + _scenario, lambda self, scenario=_scenario: self.run_scenario(scenario))


class VRCatalogTests(unittest.TestCase):
    def test_vr_catalog_bytes_have_no_lost_non_ascii_letters(self):
        sys.path.insert(0, str(ROOT / "tools"))
        import companion_i18n as catalog
        texts = {s for s, refs in catalog.extract() if any("nativeloader_vr.lua" in ref for ref in refs)} | {"VR"}
        for code in catalog.LANGUAGES:
            path = Path(catalog.I18N) / (code + ".po")
            path.read_bytes().decode("utf-8")  # strict decoding, independent of console codepage
            table = {entry["msgid"]: entry["msgstr"] for entry in catalog.read_po(path)}
            for source in texts:
                with self.subTest(language=code, source=source):
                    value = table[source]
                    self.assertNotIn("\ufffd", value)
                    if "?" not in source:
                        self.assertNotIn("?", value, "a console codepage may have replaced a letter")


if __name__ == "__main__":
    unittest.main()
