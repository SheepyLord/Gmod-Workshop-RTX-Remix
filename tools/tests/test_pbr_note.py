"""ADR 0217: the main menu's note on PBR materials for maps and the demo resources (LuaJIT harness)."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'companion/nativeloader/lua/nativeloader/menu/pbr_note.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


class PbrNoteSourceTests(unittest.TestCase):
    def test_it_runs_only_in_the_menu_realm_and_once(self):
        text = SCRIPT.read_text(encoding='utf-8')
        first = next(line for line in text.splitlines() if line.strip() and not line.startswith('--'))
        self.assertEqual(first, 'if not MENU_DLL or NativeLoaderPbrNote then return end')

    def test_it_names_the_collection_the_user_gave(self):
        text = SCRIPT.read_text(encoding='utf-8')
        self.assertIn('local COLLECTION = "3834474695"', text)
        self.assertIn('https://steamcommunity.com/sharedfiles/filedetails/?id=', text)

    def test_the_guard_knows_the_file_as_the_packages_own(self):
        guard = (REPO / 'companion/nativeloader/lua/autorun/_nativeloader_guard.lua').read_text(encoding='utf-8')
        self.assertIn('lua/nativeloader/menu/pbr_note.lua', guard.splitlines())


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class PbrNoteTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('pbr_note_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_the_note_on_the_main_menu(self):
        self.run_case('shows')

    def test_never_over_a_game_or_a_load(self):
        self.run_case('game-and-loading')

    def test_hide_lasts_until_the_next_start(self):
        self.run_case('hide')

    def test_the_card_and_dont_show_again(self):
        self.run_case('card')

    def test_a_dismissed_note_and_the_console_commands(self):
        self.run_case('dismissed')

    def test_the_collection_opens_in_the_overlay_or_the_browser(self):
        self.run_case('open')

    def test_in_the_players_language(self):
        self.run_case('french')

    def test_the_language_and_screen_are_looked_at_every_two_seconds(self):
        self.run_case('throttle')

    def test_no_note_before_the_screen_has_a_size(self):
        self.run_case('tiny-screen')

    def test_a_failed_build_is_said_once(self):
        self.run_case('build-fails')

    def test_a_second_run_changes_nothing(self):
        self.run_case('once')


if __name__ == '__main__':
    unittest.main()
