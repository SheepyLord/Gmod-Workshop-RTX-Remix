"""R25: the RTX fixes' ARC9 patch's path-traced scopes and its screen-space draws under LuaJIT (arc9_scope_harness.lua)."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/addons/cl_arc9.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class ARC9ScopeTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('arc9_scope_harness.lua')), str(SOURCE), scenario],
                              capture_output=True, text=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_the_lens_is_path_traced_through_the_scopes_camera(self):
        self.run_case('lens')

    def test_a_lens_nobody_looks_through_is_black(self):
        self.run_case('not-looking')

    def test_the_setting_leaves_arc9s_own_scopes(self):
        self.run_case('off')

    def test_without_the_runtime_setting_arc9s_own_scopes(self):
        self.run_case('no-runtime')

    def test_arc9s_own_picture_after_the_screen_is_read(self):
        self.run_case('own-picture')

    def test_a_cheap_sight_shows_the_view_one_to_one(self):
        self.run_case('cheap')

    def test_no_sight_blur(self):
        self.run_case('blur')

    def test_no_screen_draws_before_the_view_model(self):
        self.run_case('screen-draws')

    def test_no_screen_reads_before_the_view_model(self):
        self.run_case('screen-reads')

    def test_the_translucent_pass_reads_no_screen(self):
        self.run_case('translucent-pass')

    def test_the_screen_is_read_after_the_view_models(self):
        self.run_case('after-view-model')

    def test_holosights_and_flares_after_the_view_models(self):
        self.run_case('deferred')

    def test_the_view_models_attachments_mark_the_guns_front(self):
        self.run_case('vm-attachments')

    def test_parts_arc9_has_not_placed_do_not_move_the_camera(self):
        self.run_case('far-part')

    def test_a_scope_in_the_weapons_own_view_model(self):
        self.run_case('own-lens')

    def test_always_draw_is_read_when_arc9_has_made_it(self):
        self.run_case('always-draw')

    def test_an_additive_reticle(self):
        self.run_case('additive')

    def test_a_failing_camera_draw_leaves_nothing_pushed(self):
        self.run_case('camera-error')

    def test_the_hash_can_be_overridden(self):
        self.run_case('hash-override')

    def test_every_function_is_intercepted(self):
        self.run_case('apply')


if __name__ == '__main__':
    unittest.main()
