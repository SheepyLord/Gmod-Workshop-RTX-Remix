"""The distance gain the RTX flashlight and the dance light share, and the character motion importer's dance light
(ADR 0208, ADR 0209), under LuaJIT; and the dance light's menu against its catalog. No game. See test_lights.py.md."""
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TESTS = Path(__file__).resolve().parent
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
FIXES_GAIN = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_light_gain.lua'
MOTION = REPO / 'packages/character-motion-importer/mmd_vmd_npc/lua'
MOTION_GAIN = MOTION / 'mmd_vmd_npc/cl_light_gain.lua'
DANCE_LIGHT = MOTION / 'mmd_vmd_npc/cl_flashlight.lua'
STOOL = MOTION / 'weapons/gmod_tool/stools/mmd_vmd_npc.lua'
CORE = MOTION / 'mmd_vmd_npc/sh_core.lua'
AUTORUN = MOTION / 'autorun/mmd_vmd_npc.lua'


def run_lua(*args):
    return subprocess.run([LUAJIT, *map(str, args)], cwd=REPO, capture_output=True, encoding='utf-8',
                          errors='replace', timeout=120)


class SharedGainTests(unittest.TestCase):
    def test_both_parts_ship_the_same_file(self):
        # Neither part depends on the other: each has its copy, and the copies may not drift.
        self.assertEqual(FIXES_GAIN.read_bytes(), MOTION_GAIN.read_bytes())

    def test_the_motion_importer_sends_its_copy_to_clients(self):
        self.assertIn('AddCSLuaFile("mmd_vmd_npc/cl_light_gain.lua")', AUTORUN.read_text(encoding='utf-8'))

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_gain_maths(self):
        result = run_lua(TESTS / 'light_gain_harness.lua', FIXES_GAIN, MOTION_GAIN)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS light gain', result.stdout)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class DanceLightTests(unittest.TestCase):
    def run_scenario(self, scenario):
        result = run_lua(TESTS / 'dance_light_harness.lua', MOTION / 'mmd_vmd_npc', scenario)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS dance light ' + scenario, result.stdout)

    def test_with_the_defaults_the_light_is_as_it_was(self):
        self.run_scenario('defaults')

    def test_uniform_lighting_keeps_the_dancer_equally_lit(self):
        self.run_scenario('uniform')

    def test_the_light_is_for_the_framed_or_nearest_dancer_else_what_it_points_at(self):
        self.run_scenario('subject')

    def test_aim_at_the_character(self):
        self.run_scenario('aim')

    def test_colour_temperature(self):
        self.run_scenario('temperature')

    def test_rim_light(self):
        self.run_scenario('rim')

    def test_presets(self):
        self.run_scenario('presets')

    def test_the_vanilla_projected_texture(self):
        self.run_scenario('vanilla_uniform')


class DanceLightMenuTests(unittest.TestCase):
    def english(self):
        core = CORE.read_text(encoding='utf-8')
        start = core.index('MMDVMDNPC.I18N.en = {')
        return core[start:core.index('\n}', start)]

    def test_every_lighting_label_and_preset_is_in_the_english_catalog(self):
        # A key missing from the catalog shows as its raw name in the tool's Lighting tab.
        stool = STOOL.read_text(encoding='utf-8')
        keys = set(re.findall(r'L\("(mmd_vmd_npc\.lighting\.[a-z_]+)"\)', stool))
        keys |= set(re.findall(r'label = "(mmd_vmd_npc\.lighting\.[a-z_]+)"', DANCE_LIGHT.read_text(encoding='utf-8')))
        english = self.english()
        self.assertGreaterEqual(len(keys), 40)
        for key in sorted(keys):
            self.assertIn(f'["{key}"] = "', english, key)

    def test_every_dance_light_setting_has_a_control(self):
        settings = set(re.findall(r'CreateClientConVar\("(mmd_vmd_npc_flashlight_[a-z_]+)"',
                                  DANCE_LIGHT.read_text(encoding='utf-8')))
        stool = STOOL.read_text(encoding='utf-8')
        self.assertGreaterEqual(len(settings), 24)
        for name in sorted(settings):
            self.assertIn(f'"{name}"', stool, name)


if __name__ == '__main__':
    unittest.main()
