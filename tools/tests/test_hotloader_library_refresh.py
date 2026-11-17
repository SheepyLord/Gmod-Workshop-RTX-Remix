"""Load-speedup round 2 (ADR 0238): the Model Hotloader's library is built again once for a server's whole catalog
(not once per message), never for a single-player catalog, and decodes each character's manifest once.
Runs the shipped library.lua and sharing.lua under LuaJIT with the disk, timers and network messages instrumented."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/model-hotloader/mmd_hotloader/lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('single_player_catalog', 'multiplayer_catalog', 'manifest_cache')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class LibraryRefreshTests(unittest.TestCase):
    def test_scenarios(self):
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(Path(__file__).with_name('hotloader_library_refresh_harness.lua')),
                                         str(LUA / 'mmdhl'), scenario], cwd=REPO, capture_output=True,
                                        encoding='utf8', errors='replace', timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + scenario, result.stdout)


class LibraryRefreshSourceTests(unittest.TestCase):
    def test_catalog_messages_do_not_rebuild_the_library_each(self):
        sharing = (LUA / 'mmdhl/sharing.lua').read_text(encoding='utf8')
        for name in ("net.Receive('mmdhl_catalog',", "net.Receive('mmdhl_catalog_forget',"):
            body = sharing[sharing.index(name):]
            body = body[:body.index('\n end)')]
            self.assertNotIn('library.Refresh()', body, name)
            self.assertIn('catalogChanged()', body, name)
        helper = sharing[sharing.index('local function catalogChanged()'):]
        helper = helper[:helper.index('\n end')]
        self.assertIn('game.SinglePlayer()', helper)
        self.assertIn('RequestRefresh', helper)

    def test_rigs_decoded_once_at_a_map_start(self):
        sharing = (LUA / 'mmdhl/sharing.lua').read_text(encoding='utf8')
        hook = sharing[sharing.index("hook.Add('InitPostEntity','MMDHL.RestorePublishedActors'"):]
        hook = hook[:hook.index('\n end)')]
        self.assertIn('mmdhl.PruneRigs(decoded)', hook)
        self.assertNotIn("util.JSONToTable(file.Read('mmd_hotloader/rigs/", hook)
        self.assertEqual(hook.count('readRig('), 2)

    def test_host_ready_comes_from_the_hosts_catalog_request(self):
        sharing = (LUA / 'mmdhl/sharing.lua').read_text(encoding='utf8')
        branch = sharing[sharing.index("if command=='catalog' and SERVER then"):]
        branch = branch[:branch.index('\n end')]
        self.assertIn('mmdhl.readiness.HostReady()', branch)
        self.assertIn('IsListenServerHost', branch)
        self.assertIn('game.SinglePlayer()', branch)


if __name__ == '__main__':
    unittest.main()
