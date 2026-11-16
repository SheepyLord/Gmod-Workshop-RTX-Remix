"""ADR 0235: the window that tells a player RTX Remix is left in the game without its loader (LuaJIT harness over the
companion's real client autorun and window module)."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
HARNESS = Path(__file__).with_name('leftovers_popup_harness.lua')
POPUP = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_leftovers_popup.lua'
WINDOW = REPO / 'companion/nativeloader/lua/nativeloader/leftovers_window.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


class LeftoversPopupSourceTests(unittest.TestCase):
    def test_it_returns_in_an_rtx_start_and_with_the_loader_before_anything_else(self):
        text = POPUP.read_text(encoding='utf-8')
        code = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith('--')]
        self.assertEqual(code[0], 'if not CLIENT or MENU_DLL or NativeLoaderLeftoversPopupAutorun then return end')
        self.assertEqual(code[2], 'if NativeLoaderRTXStart and NativeLoaderRTXStart() then return end')
        self.assertLess(text.find('"bin/win64/winmm.dll", "BASE_PATH"'), text.find('hook.Add('))
        self.assertLess(text.find('"bin/win64/winmm.dll", "BASE_PATH"'), text.find('include('))

    def test_the_window_needs_nothing_else_of_the_add_on(self):
        # The server sends this source to a client whose copy of the add-on it has just removed.
        text = WINDOW.read_text(encoding='utf-8')
        code = '\n'.join(line for line in text.splitlines() if not line.strip().startswith('--'))
        for needed in (r'\binclude\(', r'\brequire\(', r'\bAddCSLuaFile\b', r'(?<![\w.:])L\(', r'\bNativeLoaderRTXStart\b'):
            self.assertIsNone(re.search(needed, code), needed)
        self.assertTrue(code.rstrip().endswith('return { Show = Show }'))

    def test_the_guard_knows_both_files_as_the_packages_own(self):
        guard = (REPO / 'companion/nativeloader/lua/autorun/_nativeloader_guard.lua').read_text(encoding='utf-8')
        lines = guard.splitlines()
        self.assertIn('lua/autorun/client/nativeloader_leftovers_popup.lua', lines)
        self.assertIn('lua/nativeloader/leftovers_window.lua', lines)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class LeftoversPopupTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(HARNESS), str(REPO), scenario], capture_output=True, text=True, timeout=20,
                              encoding='utf-8')
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_nothing_in_an_rtx_start(self):
        self.run_case('rtx')

    def test_nothing_while_the_loader_is_installed(self):
        self.run_case('loader')

    def test_nothing_on_another_machines_server(self):
        self.run_case('remote')

    def test_nothing_when_the_server_removed_the_package(self):
        self.run_case('removed')
        self.run_case('partly')

    def test_nothing_after_dont_show_this_again(self):
        self.run_case('dismissed')

    def test_the_window_with_the_reason_and_what_to_delete(self):
        self.run_case('refused')

    def test_the_window_for_a_listen_servers_host(self):
        self.run_case('host')

    def test_the_window_in_the_players_language(self):
        self.run_case('french')

    def test_another_games_state_is_not_this_ones(self):
        self.run_case('stale')
        self.run_case('no-state')

    def test_the_buttons(self):
        self.run_case('click')

    def test_without_the_loaders_journal(self):
        self.run_case('no-journal')

    def test_the_window_writes_only_to_its_folder_and_opens_only_https(self):
        self.run_case('window-paths')


if __name__ == '__main__':
    unittest.main()
