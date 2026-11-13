"""Task L's real Lua modules against F's maths/wire stand-ins and a geometric collision world."""
from pathlib import Path
import subprocess
import unittest
from test_mmd_alpha import LUAJIT, ROOT

SCENARIOS = (
    "arc", "landing", "landing_refusals", "follow", "steps", "crouch", "calibration", "vignette",
    "turn_rules", "turn_pivot", "room_client", "room_server", "room_validation", "room_wall",
    "smooth_hand", "smooth_head", "smooth_left", "buttons", "noclip", "q5_noclip_underwater", "q5_ladder_overlay_pipeline", "q4s_medium_head_rule", "snap", "smooth_turn", "mouse",
    "claims", "blink", "shift", "server_refuse", "moving_obstacle", "lifecycle", "tracking_loss", "overlays",
    "mantle", "climbing_resume", "flight_server", "crouch_view", "seated", "calibration_restart",
    "eye_ceiling", "climbing_cancels_teleport", "teleport_doorway", "room_float_wire", "paused_teleport", "blink_ack_fade",
    "render_prediction", "prediction_authority", "framework_view_feet", "command_roll",
    "motion_interpolation", "motion_with_room", "debug_reuse", "physical_hands_body_filter", "coalesced_motion", "render_time_motor", "motor_cadence_kept_across_reset", "motor_buffer_change_without_hold", "motor_buffer_alternating_gaps_hold",
)


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRMoveTests(unittest.TestCase):
    def run_scenario(self, scenario):
        run = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_move_harness.lua")), str(ROOT), scenario],
                             cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("PASS " + scenario, run.stdout)


for _scenario in SCENARIOS:
    setattr(VRMoveTests, "test_" + _scenario, lambda self, name=_scenario: self.run_scenario(name))

for _scenario in ("review_room_pause", "review_follow_stale", "review_paused_room_client"):
    setattr(VRMoveTests, "test_" + _scenario, lambda self, name=_scenario: self.run_scenario(name))

setattr(VRMoveTests, "test_review_render_hands_current_motor", lambda self: self.run_scenario("review_render_hands_current_motor"))

if __name__ == "__main__":
    unittest.main()
