"""The character motion importer's camera under LuaJIT: hiding yourself during camera motion (ADR 0250).
See test_motion_camera.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
CAMERA = REPO / 'packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_camera.lua'
STOOL = REPO / 'packages/character-motion-importer/mmd_vmd_npc/lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua'
CORE = REPO / 'packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sh_core.lua'


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MotionCameraTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('motion_camera_harness.lua')), scenario,
                                 str(CAMERA)], cwd=REPO, capture_output=True, encoding='utf-8', errors='replace',
                                timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_hidden_while_the_camera_plays_and_back_after_a_stop_or_toggle(self):
        # Your body, weapon, worn models and the RTX fixes' copies hidden only while a camera frame draws, the
        # flashlight dark; back the frame the server stops the camera or the toggle leaves it; a shutdown
        # mid-frame leaves nothing hidden.
        self.run_lua('play')

    def test_unticked_mid_motion_shows_you(self):
        self.run_lua('untick')

    def test_a_preview_of_yourself_keeps_you(self):
        # The debug window's camera preview orbits you when nothing is selected: you are its subject.
        self.run_lua('subject')

    def test_a_camera_that_fails_shows_you(self):
        self.run_lua('ends')

    def test_a_frame_without_postrender_leaves_nothing_hidden(self):
        self.run_lua('skipped')

    def test_what_is_hidden_and_what_is_not(self):
        # Parts someone else hid stay hidden, a death ragdoll is hidden, the dancer never, later copies too.
        self.run_lua('parts')


class MotionCameraPanelTests(unittest.TestCase):
    def test_the_option_is_in_the_camera_section_with_its_texts(self):
        stool = STOOL.read_text(encoding='utf-8')
        camera = stool[stool.index('-- Camera tab'):stool.index('-- RTX-Remix lighting tab')]
        self.assertIn('L("mmd_vmd_npc.camera.hide_player"), "mmd_vmd_npc_cam_hide_player", '
                      'L("mmd_vmd_npc.camera.hide_player_help")', camera)
        core = CORE.read_text(encoding='utf-8')
        block = core[core.index('-- The user\'s request of 2026-11-21'):]
        block = block[:block.index('\nend\n')]
        for language in ('en', 'zh', '["zh-tw"]', 'ja', 'ko', 'fr', 'ru', 'ar', 'es'):
            self.assertIn(f'\n        {language} = {{', block, language)
        self.assertEqual(block.count('["mmd_vmd_npc.camera.hide_player"]'), 9)
        self.assertEqual(block.count('["mmd_vmd_npc.camera.hide_player_help"]'), 9)
        self.assertIn('other players still see you', block)


if __name__ == '__main__':
    unittest.main()
