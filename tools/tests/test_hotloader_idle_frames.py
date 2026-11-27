"""ADR 0273: the Model Hotloader's per-frame work with no character model, and with a few. Runs
hotloader_idle_frames_harness.lua under LuaJIT. See test_hotloader_idle_frames.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class IdleFramesTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('hotloader_idle_frames_harness.lua')), scenario,
                                 str(LUA)], cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)
        return result.stdout

    def test_a_map_without_character_models_costs_no_scans(self):
        self.run_lua('idle')

    def test_the_counts_of_a_frame(self):
        out = self.run_lua('measure')
        self.assertIn('idle: 2.00 asset reads, 0.00 legacy searches', out)
        self.assertIn('3 characters: 5.00 asset reads, 0.00 legacy searches', out)

    def test_a_new_character_model_is_listed_at_once(self):
        self.run_lua('spawn')

    def test_a_model_announced_for_an_entity_in_view(self):
        self.run_lua('change')

    def test_an_unannounced_model_is_found_in_turn(self):
        self.run_lua('missed')

    def test_an_entity_back_in_view(self):
        self.run_lua('transmit')

    def test_a_removed_character_model_leaves_the_list(self):
        self.run_lua('removed')

    def test_the_list_keeps_its_order(self):
        self.run_lua('order')

    def test_a_noted_preview_is_listed(self):
        self.run_lua('preview')

    def test_a_full_update(self):
        self.run_lua('full_update')

    def test_legacy_entities_are_looked_for_only_while_one_exists(self):
        self.run_lua('legacy')

    def test_the_natives_rest_only_when_nothing_needs_them(self):
        self.run_lua('native_idle')

    def test_the_server_searches_for_server_side_worlds_only_once_one_exists(self):
        self.run_lua('server_pose')

    def test_an_unannounced_server_side_world_is_found(self):
        self.run_lua('server_pose_unannounced')


if __name__ == '__main__':
    unittest.main()
