"""ADR 0259: a Model Hotloader character's carriers share their built animations (the Character Motion Importer's
sv_skeletons.lua) under LuaJIT. See test_motion_skeletons.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / 'packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MotionSkeletonTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('motion_skeleton_harness.lua')), scenario, str(ADDON)],
                                cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_a_resized_character_finds_its_builds(self):
        # The user's report of 2026-11-22: the motions of an imported character had to be built again.
        self.run_lua('resize')

    def test_a_reimport_finds_its_builds_and_another_skeleton_does_not(self):
        self.run_lua('reimport')

    def test_the_next_session_finds_the_builds_without_the_old_rig(self):
        self.run_lua('persist')

    def test_earlier_builds_and_mappings_are_adopted_once(self):
        self.run_lua('migrate')

    def test_a_lookup_completes_the_adoption_first(self):
        self.run_lua('migrate_on_demand')

    def test_expression_mappings_follow_the_character(self):
        self.run_lua('mappings')

    def test_the_skeleton_file_loads(self):
        result = subprocess.run([LUAJIT, '-e', f"assert(loadfile([[{ADDON / 'sv_skeletons.lua'}]]))"],
                                cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
