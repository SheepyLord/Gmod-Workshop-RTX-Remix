"""Static props draw their own meshes: no GetRenderMesh/DrawModel entity, which crashed queued rendering."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/render.lua'
HARNESS = REPO / 'tools/tests/hotloader_props_render_harness.lua'


def luajit():
    found = shutil.which('luajit')
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
    return found or (str(local) if local.is_file() else None)


class HotloaderPropsRenderTests(unittest.TestCase):
    def test_no_render_mesh_entity_in_the_source(self):
        source = SOURCE.read_text(encoding='utf-8')
        for gone in ('GetRenderMesh', 'DrawModel', 'CreateClientside', 'scripted_ents.Register'):
            with self.subTest(gone=gone):
                # Only the explanation in the header comment may name the crashing path.
                code = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('--'))
                self.assertNotIn(gone, code)

    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_actual_renderer_draws_meshes_directly(self):
        result = subprocess.run([luajit(), str(HARNESS), str(SOURCE)], cwd=REPO, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: static props draw their meshes directly', result.stdout)


if __name__ == '__main__':
    unittest.main()
