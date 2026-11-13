"""K physical reload, input and counter contracts under LuaJIT, without OpenVR."""
from pathlib import Path
import os
import subprocess
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib
from test_mmd_alpha import LUAJIT, ROOT

SCENARIOS = ("hold", "release_external", "secondary_cooldown_survives_hold", "disable", "timeout", "pistol_gate", "pistol_post_update", "eject", "insert", "shotgun",
             "crossbow", "rpg", "reject_far", "reject_angle", "reject_weapon", "reject_token", "reject_reserve",
             "reject_reserve_changed", "reject_stale", "reject_occluded", "reject_grip", "drop", "death", "zone",
             "port_transform", "arithmetic", "tap_b", "tap_b_between_commands", "tap_b_preview", "pending_b_context", "hold_b", "physical_b", "swep_b", "tap_a", "hold_a",
             "counter", "no_ammo", "claims", "reject_occupied", "reject_magazine", "reject_carry_expired",
             "reject_full", "vehicle", "left_server", "counter_left", "counter_late_weapon_switch", "models_cleanup", "carry_occupies_hand",
             "drops_expire", "empty_client", "foregrip_secondary", "rpg_empty", "scaled_point", "aim_frame_port", "eject_ack_once", "release_drop_once", "coalesced_carry", "haptic_ack_once", "dependency_failure_server", "dependency_failure_client", "proxy_trace_filter", "death_client", "physics_mesh_fallback", "carry_first_resolver")

SCENARIOS += ('review_holster', 'review_external_fill', 'review_prop_zone', 'review_climb_zone', 'review_server_inactive', 'review_ack_timeout', 'review_vehicle_button', 'review_packet_ranges', 'review_retain_hand', 'review_retain_setting', 'review_retain_vehicle', 'review_retain_gap', 'review_rpg_unloaded', 'review_real_heartbeat', 'review_real_rate', 'review_rate_refusal', 'review_switch_carry', 'review_drop_release', 'review_removed_prune', 'review_deploy_button', 'review_counter_failure', 'review_idle_cost', 'review_client_debug_reuse', 'review_arithmetic_mutant', 'review_hold_oracle', 'review_hold_engine_window', 'review_retry_eject', 'review_server_vehicle_ack', 'review_server_stop_ack', 'review_new_entity', 'review_counter_paint_failure', 'review_other_claim', 'review_low_reserve_transfer', 'review_rpg_suspend_cycle', 'review_deploy_server_fallback', 'review_deploy_server_disagreement', 'review_client_past_absolute_attack_time')

SCENARIOS += ('verify_hitch_eject', 'verify_eject_ack_edge', 'verify_b_hitch_intent', 'verify_carry_hitch', 'verify_server_carry_hitch', 'verify_glove_lock', 'verify_glove_pull', 'verify_map_hold', 'verify_map_loaded_hold', 'verify_counter_buffer', 'verify_heartbeat_coalescing', 'verify_retry_coalesced_state', 'verify_carry_stale_sync_hitch')
SCENARIOS += ('q4r_dispatch_peer',)


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRReloadTests(unittest.TestCase):
    def run_case(self, case):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_reload_harness.lua")), str(ROOT), case] + ([os.environ["NLVR_RELOAD_BASELINE"]] if "NLVR_RELOAD_BASELINE" in os.environ else []),
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + case, result.stdout)


for _case in SCENARIOS:
    setattr(VRReloadTests, "test_" + _case, lambda self, case=_case: self.run_case(case))


class VRReloadReceiptTests(unittest.TestCase):
    def test_unclassified_attack_before_reload_chapter_cannot_crash_or_pass(self):
        import json
        from vr_reload_analyse import analyse
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        rows=[{'kind':'setup','class':'weapon_pistol'}, {'kind':'attack-button','time':4}]
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4-unclassified-') as tmp:
            folder=Path(tmp)
            for name,data in (('reload.json',rows),('summary.json',{'success':True}),('reload-receipt.json',{'success':True}),('sources.json',{'config':{}})):
                (folder/name).write_text(json.dumps(data),encoding='utf-8')
            with patch('vr_reload_analyse.counter_metrics',return_value={'success':True}):
                result=analyse(folder)
            self.assertFalse(result['success'])
            self.assertFalse(result['checks']['weapon_pistol']['empty_fire_attempt'])

    def test_stale_ready_ack_cannot_delay_B_ten_seconds(self):
        import json
        from vr_reload_analyse import analyse
        scratch=ROOT / "out/tmp";scratch.mkdir(parents=True,exist_ok=True)
        rows=[{"kind":"setup","class":"weapon_rpg","phase":0,"reserve":60},
              {"kind":"sample","class":"weapon_rpg","time":2.7,"clip":-1,"reserve":59,"player_next_attack":.8},
              {"kind":"sample","class":"weapon_rpg","time":6.5,"clip":-1,"reserve":59,"player_next_attack":-3},
              {"kind":"reload-button","class":"weapon_rpg","time":13.2,"tick":123,"player_next_attack":-9.7},
              {"kind":"deploy-lock","class":"weapon_rpg","time":2.5,"remaining":1},
              {"kind":"button-input","class":"weapon_rpg","time":3.15,"released":True,"tapped":True},
              {"kind":"button-command","class":"weapon_rpg","time":3,"client_game_time":3,"next_attack":3.5}]
        with tempfile.TemporaryDirectory(dir=scratch,prefix="B-latency-") as directory:
            folder=Path(directory)
            for name,data in (("reload.json",rows),("summary.json",{"success":True}),("reload-receipt.json",{"success":True}),("sources.json",{"config":{"reload_deploy":True}})):
                (folder/name).write_text(json.dumps(data),encoding="utf-8")
            with patch("vr_reload_analyse.counter_metrics",return_value={"success":True}):
                self.assertFalse(analyse(folder,button=True)["success"],"unbounded late RPG B passed")

    def test_reload_own_attack_lock_is_not_prerequisite_readiness(self):
        from vr_reload_analyse import button_delivery
        cls="weapon_ar2"
        rows=[{"kind":"setup","class":cls,"phase":0},
              {"kind":"sample","class":cls,"time":3,"player_next_attack":.55},
              {"kind":"deploy-lock","class":cls,"time":2.5,"remaining":1},
              {"kind":"button-input","class":cls,"time":3.15,"released":True,"tapped":True},
              {"kind":"button-command","class":cls,"time":3.6195,"client_game_time":108.24,"next_attack":104.8,"reload":True},
              {"kind":"button-command","class":cls,"time":3.6418,"client_game_time":108.26,"next_attack":109.82,"reload":False},
              {"kind":"reload-button","class":cls,"time":3.6423,"player_next_attack":-.095,"tick":123}]
        result=button_delivery(rows,cls,True)
        self.assertTrue(result["on_time"])
        self.assertAlmostEqual(result["latency"],.0923)

    def test_native_RPG_delivery_is_bounded_by_actual_readiness(self):
        from vr_reload_analyse import button_delivery
        records=[{"kind":"setup","class":"weapon_rpg","phase":0},
                 {"kind":"button-input","class":"weapon_rpg","time":3.15,"released":True,"tapped":True},
                 {"kind":"button-command","class":"weapon_rpg","time":3,"client_game_time":3,"next_attack":5.17},
                 {"kind":"sample","class":"weapon_rpg","time":3,"player_next_attack":.5},
                 {"kind":"deploy-lock","class":"weapon_rpg","time":2.5,"remaining":1},
                 {"kind":"reload-button","class":"weapon_rpg","time":5.298,"tick":100,"player_next_attack":-.133}]
        result=button_delivery(records,"weapon_rpg",True)
        self.assertTrue(result["on_time"]);self.assertAlmostEqual(result["latency"],.128)
        records[-1]["time"]=5.6
        self.assertFalse(button_delivery(records,"weapon_rpg",True)["on_time"])
        records[-1]["time"]=13.2
        self.assertFalse(button_delivery(records,"weapon_rpg",True)["on_time"])

    def test_late_duplicate_cannot_hide_outside_readiness_bound(self):
        from vr_reload_analyse import button_delivery
        records=[{"kind":"reload-button","class":"weapon_rpg","time":t,"tick":i,"player_next_attack":-.1} for i,t in enumerate((3.2,5.3))]
        self.assertFalse(button_delivery(records,"weapon_rpg")["one_tick"])
        self.assertFalse(button_delivery(records,"weapon_rpg")["on_time"])

    def test_port_chain_documented(self):
        text=(ROOT / "vr/addon/lua/nlvr/modules/sv_reload.lua.md").read_text(encoding="utf-8")
        for term in ("pitch", "45", "foregrip", "0.65", "SafeMuzzle"):
            self.assertIn(term,text)

    @unittest.skipUnless(LUAJIT,"LuaJIT is not installed")
    def test_protocol_and_lifecycle_mutants_are_detected(self):
        scratch=ROOT / "out/tmp";scratch.mkdir(parents=True,exist_ok=True)
        source=ROOT / "vr/addon/lua/nlvr/modules"
        original=(source / "sv_reload.lua").read_text(encoding="utf-8")
        mutants=[("heartbeat","verify_heartbeat_coalescing",original.replace("state.lease=((state.lease or 0)+1)%65536", "state.lease=0")),
                 ("prune","review_removed_prune",original.replace("state.guns[w]=nil", "state.dirty=true").replace("state.guns[w],owners[w]=nil,nil", "owners[w]=nil")),
                 ("future_timer","review_holster",original.replace('field(w,"m_flHolsterTime",0)', 'field(w,"m_flHolsterTime",3600)')),
                 ("timer_writes","review_idle_cost",original.replace('if not s.holsterAt or gameNow-s.holsterAt>=.5 then', 'if true then'))]
        for label,case,mutant in mutants:
            with self.subTest(label=label),tempfile.TemporaryDirectory(dir=scratch,prefix="K-mutant-") as directory:
                self.assertNotEqual(mutant,original)
                folder=Path(directory)
                for name in ("cl_reload.lua","sh_reload.lua"):(folder/name).write_bytes((source/name).read_bytes())
                (folder/"sv_reload.lua").write_text(mutant,encoding="utf-8")
                result=subprocess.run([LUAJIT,str(Path(__file__).with_name("vr_reload_harness.lua")),str(ROOT),case,str(folder)],capture_output=True,text=True,timeout=30)
                self.assertNotEqual(result.returncode,0,label+" mutant was not detected")

    def test_field_quit_without_console_never_uses_force(self):
        import json
        from vr_reload_poc import quit_field_normally
        scratch=ROOT / "out/tmp"
        scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix="field-quit-") as directory:
            with patch("vr_reload_poc.poc.game_processes",return_value=[123]),patch("vr_reload_poc.poc.console_window",return_value=None),patch("vr_reload_poc.subprocess.run") as launch:
                with self.assertRaises(RuntimeError):quit_field_normally(Path(directory))
                launch.assert_not_called()
            self.assertFalse(json.loads((Path(directory)/"field-quit.json").read_text())["forced"])

    def test_field_quit_normal_completion(self):
        from vr_reload_poc import quit_field_normally
        scratch=ROOT / "out/tmp"
        scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix="field-quit-") as directory:
            with patch("vr_reload_poc.poc.game_processes",side_effect=[[123],[],[]]),patch("vr_reload_poc.poc.console_window",return_value=456),patch("vr_reload_poc.poc.console",return_value=True) as send:
                quit_field_normally(Path(directory));send.assert_called_once_with(456,"quit")

    def test_holster_analysis_rejects_no_fire(self):
        import json
        from vr_reload_holster_analyse import analyse
        scratch=ROOT / "out/tmp"
        scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix="holster-analysis-") as directory:
            folder=Path(directory);rows=[]
            for cls,size in (("weapon_smg1",45),("weapon_pistol",18)):
                for t,active,clip,reserve in ((2.5,cls,0,60),(3.1,"nlvr_hands",0,60),(7.4,"nlvr_hands",0,60),(8,cls,0,60),(12,cls,size,60-size),(13.8,cls,size,60-size)):
                    row={"kind":"holster-watch","class":cls,"time":t,"active":active,"clip":clip,"reserve":reserve,"holster":-.1,"reload":{"last_insertion":"inserted"}}
                    rows.append(row)
                    if t==13.8:rows.append(dict(row,kind="sample"))
            for name,data in (("reload.json",rows),("summary.json",{"success":True}),("reload-receipt.json",{"success":True}),("restoration.json",{"clean":True})):
                (folder/name).write_text(json.dumps(data),encoding="utf-8")
            self.assertFalse(analyse(folder)["success"],"a loaded but unfired gun must not prove cycling")

    def test_trust_boundary_is_explicit(self):
        text=(ROOT / "vr/addon/lua/nlvr/modules/sv_reload.lua.md").read_text(encoding="utf-8")
        self.assertIn("client-synced",text)
        self.assertIn("message 64",text)
        self.assertIn("not independent tracking attestation",text)
        self.assertNotIn("No client pose",text)

    def test_lock_wait_preserves_foreign_owner_until_release(self):
        from vr_reload_poc import ReloadLock, driver
        scratch = ROOT / "out/tmp"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch, prefix="vr-reload-lock-") as directory:
            path = Path(directory) / "poc.lock"
            foreign = driver.ExclusiveLock(path, "fixture owner")
            with foreign:
                original = path.read_bytes()
                def release(delay):
                    self.assertEqual(delay, .25)
                    self.assertEqual(path.read_bytes(), original)
                    foreign.__exit__()
                with patch("vr_reload_poc.time.sleep", side_effect=release):
                    with ReloadLock(path, "unused", timeout=1) as own:
                        self.assertEqual(path.read_text(encoding="utf-8"), own.owner)
                self.assertFalse(path.exists())

    def fixture(self, folder, width=387):
        from vr_reload_poc import validate_records
        capture = folder / "captures" / "weapon_pistol-held"
        capture.mkdir(parents=True)
        for name in ("centre.png", "centre_depth.png", "left.png", "right.png", "mirror.png", "timings.json"):
            (capture / name).touch()
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, 129, 8, 6, 0, 0, 0))
        data += chunk(b"IDAT", zlib.compress((b"\0" + bytes((255, 255, 255, 255)) * width) * 129)) + chunk(b"IEND", b"")
        (capture / "overlay_42.png").write_bytes(data)
        records = [{"kind": "setup", "class": "weapon_pistol"}, {"kind": "calibration", "class": "weapon_pistol"},
                   {"kind": "capture", "class": "weapon_pistol", "label": capture.name, "ammo_handle": "42"},
                   {"kind": "settings-restored", "differences": {}},
                   {"kind": "counter", "class": "weapon_pistol", "visible": True,
                    "native": {"texture_width": 387, "texture_height": 129, "texture_error": 0, "transform_error": 0}}]
        return validate_records, records, capture

    def run_receipt(self, mutation=None, width=387, console=""):
        scratch = ROOT / "out/tmp"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch, prefix="vr-reload-receipt-") as directory:
            folder = Path(directory)
            validate, records, capture = self.fixture(folder, width)
            if mutation:
                mutation(records, capture)
            return validate(folder, records, ["weapon_pistol"], True, console)

    def test_complete_receipt(self):
        self.assertTrue(self.run_receipt()["success"])

    def test_managed_module_failure_is_fatal(self):
        receipt = self.run_receipt(console="[nlvr] module reload: deliberate failure")
        self.assertFalse(receipt["success"])
        self.assertEqual(len(receipt["module_errors"]), 1)

    def test_requested_capture_must_exist(self):
        receipt = self.run_receipt(lambda records, capture: (capture / "left.png").unlink())
        self.assertFalse(receipt["success"])
        self.assertIn("left.png", receipt["capture_problems"][0])

    def test_ammo_extent_is_exact(self):
        self.assertFalse(self.run_receipt(width=389)["success"])

    def counter_rows(self):
        return [{"kind": "counter", "class": "weapon_smg1", "values": [3, 60, 4], "paints": 1,
                 "main_pos": [x, -.25, 1.2], "main_ang": [0, 0, 0], "pos": [0, .1, .05],
                 "native": {"openvr_matrix34": [1, 0, 0, .15, 0, 1, 0, 1.25, 0, 0, 1, -x]}}
                for x in (.4, .4, .6, .6)]

    def test_moving_counter_uses_the_device_transform(self):
        from vr_reload_analyse import counter_metrics
        result = counter_metrics(self.counter_rows(), True)
        self.assertTrue(result["success"])
        self.assertAlmostEqual(result["hand_motion_metres"], .2)
        self.assertLess(result["max_matrix_error_metres"], 1e-10)

    def test_wrong_device_transform_fails(self):
        from vr_reload_analyse import counter_metrics
        rows = self.counter_rows()
        rows[-1]["native"]["openvr_matrix34"][3] += .03
        self.assertFalse(counter_metrics(rows, True)["success"])

    def test_unchanged_counter_must_not_repaint(self):
        from vr_reload_analyse import counter_metrics
        rows = self.counter_rows()
        rows[-1]["paints"] = 2
        self.assertFalse(counter_metrics(rows, True)["success"])

if __name__ == "__main__":
    unittest.main()
