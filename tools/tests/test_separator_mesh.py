"""ADR 0232: the Mesh Separator's selection engine (packages/model-hotloader/.../separator/mesh.lua) in a LuaJIT harness."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'] if p.is_file()), None)
REPO = Path(__file__).resolve().parents[2]
HARNESS = Path(__file__).with_name('separator_mesh_harness.lua')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class SeparatorMeshTest(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(HARNESS), str(REPO), scenario], capture_output=True, text=True,
                              encoding='utf-8', timeout=120)
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        self.assertIn(f'PASS {scenario}', done.stdout)

    def test_pieces_join_at_seams_and_back_face_copies(self):
        self.run_case('islands')

    def test_rays_find_the_nearest_triangle_through_the_grid(self):
        self.run_case('raycast')

    def test_the_brush_takes_triangles_within_its_radius(self):
        self.run_case('brush')

    def test_box_and_lasso_through_the_model_or_only_what_is_seen(self):
        self.run_case('region')

    def test_the_selection_set(self):
        self.run_case('selection')


if __name__ == '__main__':
    unittest.main()
