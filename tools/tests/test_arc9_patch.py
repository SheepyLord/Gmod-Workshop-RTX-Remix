"""R24 (ADR 0135): the RTX fixes' ARC9 patch under LuaJIT (arc9_patch_harness.lua), one scenario per test."""
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
class ARC9PatchTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('arc9_patch_harness.lua')), str(SOURCE), scenario],
                              capture_output=True, text=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_a_view_models_stickers_and_screens_draw_with_their_materials(self):
        self.run_case('view')

    def test_no_parts_of_a_world_model_arc9_does_not_draw(self):
        self.run_case('world-model-skipped')

    def test_no_view_model_parts_when_arc9_draws_none(self):
        self.run_case('view-model-skipped')

    def test_a_preset_icon_draws_the_presets_models(self):
        self.run_case('preset')

    def test_parts_arc9_draws_elsewhere_are_left_to_it(self):
        self.run_case('left-to-arc9')

    def test_arc9s_error_goes_on_with_the_parts_restored(self):
        self.run_case('error')

    def test_the_setting_turns_it_off(self):
        self.run_case('off')

    def test_the_gun_screen_provider_whichever_loads_first(self):
        self.run_case('screens-first')
        self.run_case('screens-after')


if __name__ == '__main__':
    unittest.main()
