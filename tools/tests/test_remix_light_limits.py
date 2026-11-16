"""Review findings 13, 14 and 22: the RTX fixes' Remix lights and sky editor took networked values unchecked, the six
RT light tools ignored sandbox's spawn limits, owner and cleanup, and the sky editor was spawnable by anyone with an
unclamped dupe. Runs the shipped Lua under remix_light_limits_harness.lua, one scenario per LuaJIT process."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_glass_map import glua_to_lua, luajit  # noqa: E402  (GLua's !, !=, // and continue to plain Lua; the LuaJIT found)

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua'
HARNESS = REPO / 'tools/tests/remix_light_limits_harness.lua'
# The harness's short name for each shipped file it loads.
FILES = {
    'rt_shared.lua': 'entities/remix_rt_light/shared.lua',
    'rt_init.lua': 'entities/remix_rt_light/init.lua',
    'rt_cl_init.lua': 'entities/remix_rt_light/cl_init.lua',
    'sky_shared.lua': 'entities/remix_sky_editor/shared.lua',
    'sky_init.lua': 'entities/remix_sky_editor/init.lua',
    'sky_cl_init.lua': 'entities/remix_sky_editor/cl_init.lua',
    'sv_rtx.lua': 'autorun/sv_rtx.lua',
    'light_wrapper.lua': 'remixlua/cl/remixapi/wrappers/cl_remix_light_wrapper.lua',
    'pt_wrapper.lua': 'remixlua/cl/remixapi/wrappers/cl_remix_projectedtexture_wrapper.lua',
    **{f'stool_{kind}.lua': f'weapons/gmod_tool/stools/remix_rt_light_{kind}.lua'
       for kind in ('sphere', 'rect', 'disk', 'cylinder', 'distant', 'bonemerge')},
}


@unittest.skipUnless(luajit(), 'LuaJIT is not installed')
class RemixLightLimitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        cls.folder = tempfile.TemporaryDirectory(prefix='remix-light-limits-', dir=scratch)
        for short, path in FILES.items():
            text = (LUA / path).read_text(encoding='utf-8')
            (Path(cls.folder.name) / short).write_text(glua_to_lua(text), encoding='utf-8')

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def run_lua(self, scenario):
        result = subprocess.run([luajit(), str(HARNESS), scenario, self.folder.name], cwd=REPO, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_light_tools_apply_the_spawn_policy_and_the_limits(self):
        self.run_lua('stools')

    def test_dupes_the_editor_and_the_spawn_message_keep_the_limits(self):
        self.run_lua('apply')

    def test_sky_editor_is_admin_only_and_clamped(self):
        self.run_lua('sky')

    def test_clients_hand_the_remix_api_finite_values(self):
        self.run_lua('client')


if __name__ == '__main__':
    unittest.main()
