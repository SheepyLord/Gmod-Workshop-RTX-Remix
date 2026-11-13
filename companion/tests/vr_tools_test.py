"""T's LuaJIT tools/wheel contracts, including an independent NLVR.Weapon stand-in."""
from pathlib import Path
import subprocess
import json
import tempfile
import base64
import struct
import unittest
from test_mmd_alpha import LUAJIT, ROOT
import vr_tools_check as evidence
import vr_tools_poc as probe


class VRToolsEvidenceTests(unittest.TestCase):
    def beam_capture(self, occluded, shift=0):
        from PIL import Image, ImageDraw
        import vr_tools_capture
        folder = self.sample_folder([])
        capture = folder / "captures/tools-roll"
        capture.mkdir(parents=True)
        (capture / "timings.json").write_text('{"pose":1}', encoding="utf-8")
        image = Image.new("RGB", (200, 200))
        ImageDraw.Draw(image).line((110, 100 + shift, 130, 100 + shift), fill="white", width=3)
        image.save(capture / "centre.png")
        Image.new("L", (200, 200)).save(capture / "centre_depth.png")
        depth = [-1.0 if occluded and x > 130 else -100.0 for y in range(200) for x in range(200)]
        (capture / "centre_depth.f32").write_bytes(struct.pack("<40000f", *depth))
        eye = {"tanLeft": -1, "tanRight": 1, "tanTop": -1, "tanBottom": 1,
               "eyeToHead": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]}
        rows = [{"name": "capture", "label": "tools-roll", "ok": True,
                 "camera": {"origin": [0, 0, 0], "angles": [0, 0, 0]}, "info": {"eyes": [eye, eye]}},
                {"name": "beam-draw", "frame": 1, "start": [2, -1, 0], "model_muzzle": [2, -1, 0], "endpoint": [10, 0, 0]}]
        return vr_tools_capture.measure(folder, rows, {})[0]

    def test_beam_capture_accounts_for_measured_model_occlusion(self):
        result = self.beam_capture(True)
        self.assertLessEqual(result["first_luminous_gap_pixels"], 1)
        self.assertAlmostEqual(result["occluded_pixels"], 20)
        self.assertEqual(result["visible_start_pixel"], [130, 100])

    def test_beam_capture_rejects_unexplained_visible_gap(self):
        result = self.beam_capture(False)
        self.assertGreater(result["first_luminous_gap_pixels"], 12)

    def test_beam_image_detects_offset_despite_identical_draw_attachment(self):
        result = self.beam_capture(True, shift=3)
        self.assertGreater(result.get("image_line_muzzle_error_pixels", result.get("draw_vs_model_pixels", 0)), 2)
        from vr_tools_capture import accepted
        self.assertFalse(accepted(result))

    def test_native_limits_reject_wrong_damping_factor(self):
        from vr_tools_review_check import evaluate
        row = {"name": "review-shadow-parameters", "angular": 5000, "server_angular": 5000,
               "damping": 10000, "server_damping": 10000, "arrive": 0.05, "server_arrive": 0.05,
               "factor": 0.35, "server_factor": 0.7}
        checks, _ = evaluate([row] * 5)
        self.assertFalse(checks["actual_server_rotation_limits"])

    def test_probe_records_reassemble_chunked_realms(self):
        text = ""
        expected = []
        for realm in ("client", "server"):
            row = {"name": "capture", "realm": realm, "detail": "x" * 9000}
            expected.append(row)
            encoded = base64.b64encode(json.dumps(row).encode()).decode()
            parts = [encoded[i:i+2800] for i in range(0, len(encoded), 2800)]
            text += "\n".join(f"NLVR_T_CHUNK {realm} 1 {i+1}/{len(parts)} {p}" for i,p in enumerate(parts)) + "\n"
        self.assertEqual(probe.tool_records(text), expected)

    def test_probe_records_reject_truncated_chunk(self):
        with self.assertRaises(ValueError):
            probe.tool_records("NLVR_T_CHUNK client 1 1/2 e30=\n")
    def sample_folder(self, rows):
        scratch = ROOT / "out/tmp"
        scratch.mkdir(parents=True, exist_ok=True)
        directory = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(directory.cleanup)
        p = Path(directory.name)
        (p / "poc/game").mkdir(parents=True)
        for name, value in {"tools-records.json": rows, "summary.json": {"success": True, "simulated": True},
                            "tools-provenance.json": {"driver_exit": 0}, "restoration.json": {"clean": True, "originals": {"owned": True}}}.items():
            (p / name).write_text(json.dumps(value), encoding="utf-8")
        (p / "poc/game/console.log").write_text("", encoding="utf-8")
        return p

    def test_debug_beam_identity_without_capture_is_rejected(self):
        rows = [{"name": "sample", "realm": "client", "time": t, "weapon": "weapon_physgun", "frame": 1,
                 "muzzle": [0, 0, 0], "debug": {"beam": {"origin": [0, 0, 0], "frame": 1}}} for t in (5.6, 5.7, 5.8)]
        result = evidence.evaluate(self.sample_folder(rows), native_only=True)
        self.assertFalse(result["checks"]["beam_at_muzzle"])

    def test_debug_distance_change_with_stationary_actual_prop_is_rejected(self):
        rows = [{"name": "sample", "realm": "server", "time": t, "pos": [100, 0, 0], "ang": [0, 0, 0],
                 "muzzle": {"pos": [0, 0, 0]}, "scale": 40, "debug": {"held": {"entity": 1, "distance": distance}}}
                for t, distance in ((12.5, 2), (15.5, 7))]
        rows.append({"name": "pickup-orientation", "time": 2, "body": [0, 0, 0], "hand": [0, 0, 0], "contact": [0, 0, 0]})
        result = evidence.evaluate(self.sample_folder(rows), native_only=True)
        self.assertFalse(result["checks"]["push"])
    def test_independent_rotation_witnesses(self):
        self.assertAlmostEqual(evidence.angle_error("{0 0 0}", "{0 0 90}"), 90)
        self.assertAlmostEqual(evidence.angle_error("{90 0 0}", "{0 90 0}"), 120)
        self.assertAlmostEqual(evidence.angle_error("{0 179 0}", "{0 -179 0}"), 2)

    def test_vector_decoding_preserves_sign_and_exponent(self):
        self.assertEqual(evidence.vector("[-12.5 1e-3 -0]"), [-12.5, 0.001, 0])

    def test_vector_decoder_rejects_incomplete_and_nonfinite(self):
        for value in ("[nan 0 0]", "[1e999 0 0]", [1, 2], [1, 2, float("nan")]):
            with self.subTest(value=value), self.assertRaises(ValueError):
                evidence.vector(value)

    def test_timeline_contains_native_axes_and_actions(self):
        data = probe.timeline(60, "features")
        self.assertEqual(sorted(s["time"] for s in data["steps"]), [s["time"] for s in data["steps"]])
        orientations = {tuple(s["right"]["ang"]) for s in data["steps"]}
        self.assertTrue({(90, 0, 0), (0, 90, 0), (0, 0, 90)} <= orientations)
        self.assertTrue(any(s["actions"]["right_stick"] == [0, 1] for s in data["steps"]))
        self.assertTrue(any(s["actions"]["right_stick"] == [0, -1] for s in data["steps"]))

    def test_missing_target_cannot_certify_remover_or_colour(self):
        rows = [{"name": "menu-selected", "wanted": "remover", "actual": "remover"},
                {"name": "remover-result", "remaining": 0}, {"name": "colour-result", "entity": 3,
                 "colour": {"r": 32, "g": 140, "b": 220, "a": 255}},
                {"name": "secondary-result", "r": 32, "g": 140, "b": 220}]
        self.assertFalse(any(evidence.tool_actions(rows, []).values()))

    def test_fixture_cleanup_cannot_certify_remover(self):
        rows = [{"name": "menu-selected", "wanted": "remover", "actual": "remover"},
                {"name": "target", "entity": 3, "purpose": "remover", "tool": "remover", "class": "gmod_tool"},
                {"name": "target-removed", "entity": 3, "purpose": "remover", "tool": "remover", "class": "gmod_tool",
                 "fixture_cleanup": True, "time": 33.5}, {"name": "remover-result", "remaining": 0}]
        self.assertTrue(evidence.tool_actions(rows, [])["menu_remover"])
        self.assertFalse(evidence.tool_actions(rows, [])["remover"])
        rows[2]["fixture_cleanup"] = False
        self.assertTrue(evidence.tool_actions(rows, [])["remover"])

    def test_simulated_overlay_cannot_certify_index_source(self):
        state = {"visible": True, "texture_error": 0, "transform_error": 0, "texture_width": 643, "texture_height": 133, "simulated": True}
        self.assertTrue(evidence.overlay_source(state, (643, 133), True))
        self.assertFalse(evidence.overlay_source(state, (643, 133), False))
        state["simulated"] = False
        self.assertTrue(evidence.overlay_source(state, (643, 133), False))

    def test_rotation_goal_comes_from_measured_pickup_and_hand_delta(self):
        goal = evidence.followed_rotation((0, 0, 30), (0, 20, 0), (0, 110, 0))
        self.assertAlmostEqual(evidence.matrix_error(goal, evidence.rotation((0, 90, 30))), 0, places=5)
        body, hand = (12, -34, 56), (-23, 87, 65)
        self.assertAlmostEqual(evidence.matrix_error(evidence.followed_rotation(body, hand, hand), evidence.rotation(body)), 0, places=5)

    def test_pickup_anchor_prefers_native_hook_over_earlier_sample(self):
        server = [{"name": "sample", "time": 1, "exists": True, "ang": [0, 0, 0], "hand": {"valid": True, "ang": [0, 0, 0]}},
                  {"name": "sample", "time": 2, "held": True, "class": "weapon_physgun"}]
        self.assertEqual(evidence.pickup_orientation([], server)["source"], "last-pre-pickup-sample")
        event = {"name": "pickup-orientation", "time": 1.9, "body": [0, 0, 30], "hand": [0, 20, 0]}
        anchor = evidence.pickup_orientation([event], server)
        self.assertEqual(anchor["source"], "native-pickup-hook")
        self.assertEqual(anchor["body"], [0, 0, 30])


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRToolsTests(unittest.TestCase):
    def run_case(self, case):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_tools_harness.lua")), str(ROOT), case],
                                capture_output=True, encoding="utf-8", timeout=30, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + case, result.stdout)


for _case in ("relative_axes", "relative_compound", "angle_wrap", "stick_rate", "stick_deadzone", "stick_bounded",
              "inventory", "layout", "picking", "deadzone", "pages", "tool_info", "tool_stages", "tool_fallback",
              "tool_repaint", "tool_switch", "tool_hide", "wheel_hold", "wheel_tap", "wheel_select", "wheel_cancel",
              "wheel_death", "wheel_many", "wheel_claims", "wheel_inventory_change", "wheel_mirror", "held_distance", "q5_ladder_distance",
              "held_unchanged", "held_tracking_lost", "held_entity_removed", "stick_owner", "beam", "cleanup", "server_pickup", "server_drop", "server_stale", "server_stop",
              "wheel_trigger_release", "wheel_reacquire", "wheel_weapon_claim", "layout_readable", "dependency_absent", "tool_model_anchor",
              "wheel_left_selection", "tool_left", "server_left", "beam_hidden", "stick_frame_rate", "wheel_prediction_retry", "wheel_selection_expiry", "rotation_params", "rotation_lifecycle", "rotation_failure", "server_repickup", "rotation_after_stop",
              "tool_button_passthrough", "wheel_reload_a_claim", "wheel_pending_b_claim", "wheel_lost_b_claim",
              "stick_drop_latch", "stick_tracking_latch", "stick_mirror_latch", "wheel_cancel_trigger_claim", "wheel_mirror_trigger_claim",
              "rotation_server_limits", "rotation_origin_velocity", "server_failed_creation_drop", "drop_trigger_rearm",
              "beam_addon_hooks", "beam_material_cached", "debug_reused", "tool_info_cached", "tool_native_calls_cached", "wheel_inventory_cached",
              "wheel_refused_once", "wheel_custom_icon", "tool_use_modifier", "rotation_native_snap", "server_drop_rearm", "beam_cached_dispatch", "rotation_no_linear_force", "server_creation_before_native_attach", "beam_rendered_attachment",
              "beam_ulib_empty", "beam_ulib_existing", "beam_unknown_library", "rotation_damping_factor", "tool_native_calls_moving", "presentation_tolerance", "wheel_hands_base_icon", "rotation_damped_residual", "rotation_feedback_bound"):
    setattr(VRToolsTests, "test_" + _case, lambda self, case=_case: self.run_case(case))


if __name__ == "__main__":
    unittest.main()
