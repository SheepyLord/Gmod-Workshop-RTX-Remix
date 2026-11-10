"""No entity in the package hands GMod a Lua mesh through ENT:GetRenderMesh (ADR 0153): drawn with DrawModel, that
path crashes the material system's render thread under queued rendering (studiorender.dll+0x6603b). Runs the Seamless
Portals entity's shipped client file under seamless_portal_draw_harness.lua and scans the package's Lua."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_glass_map import glua_to_lua  # noqa: E402  (GLua's !, != and // to plain Lua)

REPO = Path(__file__).resolve().parents[2]
PORTAL = REPO / 'packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/cl_init.lua'
HARNESS = REPO / 'tools/tests/seamless_portal_draw_harness.lua'
# Lua the package ships: its parts' add-ons, and the add-ons read from this repository.
LUA_ROOTS = ['packages', 'glass/addon', 'companion', 'fs_accel/addon']
DEFINITION = re.compile(r'function\s+[A-Za-z_][\w.]*[:.]GetRenderMesh\s*\(([^)]*)\)(.*?)\bend\b', re.S)


def luajit():
    found = shutil.which('luajit')
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
    return found or (str(local) if local.is_file() else None)


def render_mesh_providers(text):
    """The GetRenderMesh definitions in a Lua source whose body returns something (a mesh table); an empty one,
    which switches the engine's path off (procedural_shard.lua), is fine."""
    code = '\n'.join(line.split('--', 1)[0] for line in text.splitlines())
    return [m.group(0)[:80] for m in DEFINITION.finditer(code) if 'return' in m.group(2)]


class RenderMeshEntityTests(unittest.TestCase):
    def test_no_lua_in_the_package_provides_a_render_mesh(self):
        found = {}
        for root in LUA_ROOTS:
            for path in (REPO / root).rglob('*.lua'):
                hits = render_mesh_providers(path.read_text(encoding='utf-8', errors='replace'))
                if hits:
                    found[path.relative_to(REPO).as_posix()] = hits
        self.assertEqual(found, {})

    def test_the_scan_finds_a_provider(self):
        # The portal's old definition, and the Model Hotloader's proxy before ADR 0152.
        old = ('local render_matrix = Matrix()\nfunction ENT:GetRenderMesh()\n\treturn {\n\t\tMesh = m,\n'
               '\t\tMatrix = render_matrix,\n\t}\nend\n')
        self.assertEqual(len(render_mesh_providers(old)), 1)
        self.assertEqual(len(render_mesh_providers('function proxy:GetRenderMesh() return self.MMDHLMesh end')), 1)
        self.assertEqual(render_mesh_providers('function ENT:GetRenderMesh() end -- switched off'), [])

    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_portals_draw_their_mesh_directly(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='seamless-portal-', dir=scratch) as folder:
            converted = Path(folder) / 'cl_init.lua'
            converted.write_text(glua_to_lua(PORTAL.read_text(encoding='utf-8')), encoding='utf-8')
            result = subprocess.run([luajit(), str(HARNESS), str(converted)], cwd=REPO, capture_output=True,
                                    encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: portals draw their mesh directly', result.stdout)


if __name__ == '__main__':
    unittest.main()
