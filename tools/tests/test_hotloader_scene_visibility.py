"""ADR 0245: the Model Hotloader's hair and clothing leave out what nobody sees. Runs
hotloader_scene_visibility_harness.lua under LuaJIT. See test_hotloader_scene_visibility.py.md."""
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
class SceneVisibilityTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('hotloader_scene_visibility_harness.lua')), scenario,
                                 str(LUA)], cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_entities_nobody_can_see_are_left_out(self):
        self.run_lua('hidden')

    def test_an_entity_drawn_again_collides_again(self):
        self.run_lua('visible_again')

    def test_models_drawing_no_mesh_are_left_out(self):
        # Enhanced Death Animations' animator: a prop_dynamic whose model's only bodygroup is blank.
        self.run_lua('models')

    def test_bone_followers_are_as_visible_as_their_model(self):
        self.run_lua('followers')

    def test_characters_follow_what_the_add_on_draws(self):
        self.run_lua('characters')

    def test_stand_ins_explicit_exclusions_and_the_world(self):
        self.run_lua('stand_ins')

    def test_invisible_players_and_npcs_are_left_out(self):
        self.run_lua('living')

    def test_entities_without_a_model(self):
        self.run_lua('no_model')

    def test_a_hidden_ragdoll_wearing_drawn_models_collides(self):
        # The sandbox bonemerge look: the base ragdoll made invisible, models merged onto its bones show.
        self.run_lua('children')


if __name__ == '__main__':
    unittest.main()
