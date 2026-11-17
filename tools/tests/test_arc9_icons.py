"""Load speed-up round 3 (ADR 0240): ARC9's attachment icons decoded when first drawn, not while a map loads. Runs the
load accelerator's nlloadaccel/arc9_icons.lua under LuaJIT (arc9_icons_harness.lua), once per scenario."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class Arc9IconTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('arc9_icons_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, encoding='utf-8', timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_the_client_decodes_an_icon_at_its_first_draw_or_read(self):
        self.run_case('client')

    def test_through_the_render_guards_material_wrapper(self):
        self.run_case('guard')

    def test_the_server_decodes_none(self):
        self.run_case('server')

    def test_arc9s_generated_entities_keep_gmods_material(self):
        self.run_case('generate')

    def test_the_switch_leaves_material_alone(self):
        self.run_case('off')


class Arc9IconSourceTests(unittest.TestCase):
    """The add-on's autorun includes the file in both realms (sent to clients), before the module is required."""

    def test_included_by_the_autorun_in_both_realms(self):
        autorun = (REPO / 'fs_accel' / 'addon' / 'lua' / 'autorun' / '!!!!!nlloadaccel.lua').read_text(encoding='utf-8')
        self.assertIn('AddCSLuaFile("nlloadaccel/arc9_icons.lua")', autorun)
        self.assertIn('include("nlloadaccel/arc9_icons.lua")', autorun)
        self.assertLess(autorun.index('include("nlloadaccel/arc9_icons.lua")'), autorun.index('require, "nlfsaccel"'))


if __name__ == '__main__':
    unittest.main()
