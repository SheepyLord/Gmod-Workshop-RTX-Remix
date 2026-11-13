"""V1's real page/add-on against an API-v1 nlvr stand-in, without OpenVR or a game."""
from pathlib import Path
import subprocess
import sys
import unittest
from test_mmd_alpha import LUAJIT, ROOT

SCENARIOS = (
    "idle", "options_no_format_write", "probe", "missing_module", "require_error", "version", "runtime", "remote", "host", "vrmod", "gvrmod",
    "inactive_vrmod", "api_vrmod", "start_exit", "start_cancel", "failure", "failure_running", "start_error", "missing_addon",
    "guard_refused", "overlay_error", "quit", "off", "shutdown", "shutdown_starting", "hot_reload",
    "frame_error", "paint_error", "tracking", "no_tracking", "scale_latched", "hud", "notifications", "proxies", "wrist", "gpu", "metrics", "uncapped",
    "authoritative_view", "predicted_origin", "frame_once", "calcview_before_prerender",
    "review_nil_camera", "review_return_failures", "review_paused_poll", "review_native_stopping", "review_page_nil", "review_overlay_nil", "review_recenter",
    "sdk_ready", "async_stop", "cap_warning", "native_return_error", "missing_steamvr",
    "review2_busy_camera", "review2_overlay_ack", "review2_overlay_info_error",
    "f_space", "f_poses", "f_input", "f_settings", "f_movers_aim", "f_movers_noclip", "f_movers_ladder_water", "f_movers_armed_medium_parity", "f_ladder_sectors", "f_noclip_water_basis", "f_ladder_tool_buttons", "f_server_ladder_yaw_intent", "f_module_failure", "f_module_order", "f_competing_addon_lifecycle",
    "f_overlays", "f_overlay_refusals", "f_protocol", "f_protocol_rejections", "f_server_sync", "f_server_movers",
    "f_server_send", "f_stub", "f_client_sync", "f_server_ladder_water_basis",
    "f_overlay_attached", "f_stale_history", "f_failed_mover", "f_module_packets",
    "f_network_cleanup_error", "f_createmove_frame_error",
)


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRTests(unittest.TestCase):
    def test_immediate_peer_removal_mutant_cannot_pass_lifecycle(self):
        import json
        code='local root='+json.dumps(ROOT.as_posix())+'\n'+'''
local original=loadfile
loadfile=function(path)
 if path==root.."/companion/tests/vr_hook_addon.lua" then
  local f=assert(io.open(path,"rb")) local source=f:read("*a") f:close()
  source=source:gsub("return self[\\r\\n]+end","self.Remove() return self\\nend")
  return loadstring(source)
 end
 return original(path)
end
assert(original(root.."/companion/tests/vr_harness.lua"))(root,"f_competing_addon_lifecycle","ulib")
'''
        run=subprocess.run([LUAJIT,'-e',code],capture_output=True,text=True)
        self.assertNotEqual(run.returncode,0)
        self.assertIn('not exercised',run.stdout+run.stderr)

    def test_production_render_guard_accepts_wrist_canvas(self):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_guard_harness.lua")), str(ROOT)],
                                cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("native allocation=1; guard refusals=0", result.stdout)

    def run_scenario(self, scenario, library="stock"):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_harness.lua")), str(ROOT), scenario,library],
                                capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + scenario, result.stdout)


for _scenario in SCENARIOS:
    setattr(VRTests, "test_" + _scenario, lambda self, scenario=_scenario: self.run_scenario(scenario))


class VRULibTests(VRTests):
    def run_scenario(self,scenario):
        return VRTests.run_scenario(self,scenario,"ulib")


setattr(VRTests, "test_f_world_velocity", lambda self: self.run_scenario("f_world_velocity"))
setattr(VRTests, "test_f_review_overlay_repaint", lambda self: self.run_scenario("f_review_overlay_repaint"))
for _name in ("f_view_ulib","f_view_ulib_copy","f_view_unknown","f_view_reentry","f_view_ulib_lifecycle","f_view_stock_lifecycle","f_view_removed_stock","f_view_removed_ulib","f_view_ulib_detached_dispatch","f_view_ulib_no_shortcircuit"):
    setattr(VRTests,"test_"+_name,lambda self,name=_name:self.run_scenario(name))
for _name in ("f_review_overlay_budget", "f_review_refresh_cache"):
    setattr(VRTests, "test_" + _name, lambda self, name=_name: self.run_scenario(name))

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
