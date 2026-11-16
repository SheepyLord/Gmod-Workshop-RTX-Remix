"""Review finding 5: a pasted Seamless Portals dupe with a huge side count hung the host and every client. Runs the
portal entity's shipped files under portal_limits_harness.lua: a crafted side count or size builds a bounded hull and
render mesh on the server and on a client, the tools' sizes stay as they were, and a paste stores bounded values."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_glass_map import glua_to_lua, luajit  # noqa: E402  (GLua's !, != and // to plain Lua; the LuaJIT found)

REPO = Path(__file__).resolve().parents[2]
PORTAL = REPO / 'packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/entities/seamless_portal'
HARNESS = REPO / 'tools/tests/portal_limits_harness.lua'


@unittest.skipUnless(luajit(), 'LuaJIT is not installed')
class PortalLimitTests(unittest.TestCase):
    def test_crafted_side_counts_and_sizes_stay_within_the_limits(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='portal-limits-', dir=scratch) as folder:
            for name in ('sh_init.lua', 'init.lua', 'cl_init.lua'):
                (Path(folder) / name).write_text(glua_to_lua((PORTAL / name).read_text(encoding='utf-8')),
                                                 encoding='utf-8')
            result = subprocess.run([luajit(), str(HARNESS), folder], cwd=REPO, capture_output=True,
                                    encoding='utf-8', errors='replace', timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: portal side counts and sizes stay within their limits', result.stdout)


if __name__ == '__main__':
    unittest.main()
