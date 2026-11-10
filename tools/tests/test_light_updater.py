"""Run the RTX fixes' packaged light updater under light_updater_harness.lua (R28, ADR 0144): which helpers a
frame draws. No game."""
import os
import shutil
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LUA = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
HARNESS = REPO / 'tools/tests/light_updater_harness.lua'
UPDATER = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_light_updater.lua'


@unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT is not installed')
class LightUpdaterTests(unittest.TestCase):
    def run_case(self, *scenario: str) -> None:
        result = subprocess.run([LUA, str(HARNESS), str(UPDATER), *scenario], cwd=REPO, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + ' '.join(scenario), result.stdout)

    def test_steady_point_lights_are_drawn_in_view_near_the_eye_and_on_their_turn(self):
        self.run_case('bounded')

    def test_lights_near_a_lamp_or_a_lua_dynamic_light_never_stop(self):
        # The second review's finding: the runtime hands a light that stops to a new point light nearby.
        self.run_case('dynamic')
        self.run_case('dynamic', 'entity')

    def test_a_helper_that_may_set_a_texture_light_is_drawn_every_frame(self):
        # The review's finding: a texture light is a spot light for the runtime, dropped the frame it is not set.
        self.run_case('texture_light')
        self.run_case('texture_light', 'walls')

    def test_a_light_counts_only_from_a_leaf_that_can_see_its_cluster(self):
        # The engine's first test for a model's lights is the PVS of the model's leaf.
        for variant in ('strong', 'pvs', 'solid'):
            with self.subTest(variant=variant):
                self.run_case('texture_light', variant)

    def test_a_light_set_by_its_own_every_frame_helper_keeps_no_other_helper_drawn(self):
        self.run_case('spot_and_switched')
        self.run_case('spot_and_switched', 'walls')
        self.run_case('spot_and_switched', 'dim')

    def test_a_light_its_own_helper_does_not_set_keeps_its_neighbours_helpers_drawn(self):
        self.run_case('light_set_by_a_neighbour')
        self.run_case('light_set_by_a_neighbour', 'bright')

    def test_a_helper_that_sees_the_sky_along_the_sun_is_drawn_every_frame(self):
        self.run_case('sky')

    def test_runtime_options_in_rtx_conf_switch_the_list_off_or_shorten_the_turns(self):
        self.run_case('options')
        self.run_case('options', 'frames')

    def test_without_usable_world_lights_every_helper_is_drawn_every_frame(self):
        for variant in ((), ('mismatch',), ('layout',)):
            with self.subTest(variant=variant):
                self.run_case('no_world_lights', *variant)

    def test_a_new_lamp_rebuilds_the_list_and_keeps_what_was_worked_out(self):
        self.run_case('rebuild')


if __name__ == '__main__':
    unittest.main()
