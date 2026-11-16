"""The repository review of 2026-11-16, finding 16 (ADR 0234): a multiplayer RTX start turns sv_cheats off from the
menu realm (LuaJIT harness over the real menu script), since GMod blocks sv_cheats for a game's own realms."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'companion/nativeloader/lua/nativeloader/menu/multiplayer_cheats.lua'
AUTORUN = REPO / 'companion/nativeloader/lua/autorun/!!!!nativeloader_engine_guard.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


class MultiplayerCheatsSourceTests(unittest.TestCase):
    def test_it_runs_only_in_the_menu_realm_and_once(self):
        text = SCRIPT.read_text(encoding='utf-8')
        first = next(line for line in text.splitlines() if line.strip() and not line.startswith('--'))
        self.assertEqual(first, 'if not MENU_DLL or NativeLoaderMultiplayerCheats then return end')

    def test_the_server_asks_through_the_data_folder_not_a_blocked_command(self):
        text = AUTORUN.read_text(encoding='utf-8')
        self.assertIn('file.Write("nativeloader_companion/cheats_off.txt", tostring(os.time()))', text)
        self.assertNotIn('RunConsoleCommand("sv_cheats"', text)
        self.assertIn('local REQUEST = "nativeloader_companion/cheats_off.txt"', SCRIPT.read_text(encoding='utf-8'))

    def test_the_guard_knows_the_file_as_the_packages_own(self):
        guard = (REPO / 'companion/nativeloader/lua/autorun/_nativeloader_guard.lua').read_text(encoding='utf-8')
        self.assertIn('lua/nativeloader/menu/multiplayer_cheats.lua', guard.splitlines())


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MultiplayerCheatsTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('multiplayer_cheats_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_a_fresh_request_in_a_running_game(self):
        self.run_case('fresh')

    def test_a_request_waits_for_the_game_to_load(self):
        self.run_case('loading')

    def test_stale_future_and_unreadable_requests_are_dropped(self):
        self.run_case('stale')

    def test_only_in_the_menu_realm_and_once(self):
        self.run_case('realm')


if __name__ == '__main__':
    unittest.main()
