"""R24 (ADR 0133): the companion's multiplayer notice, in the menu realm (LuaJIT harness) and in the menu page (Node)."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'companion' / 'nativeloader' / 'lua' / 'nativeloader' / 'menu' / 'multiplayer_notice.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
NODE = shutil.which('node')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MultiplayerNoticeMenuTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('multiplayer_notice_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_first_start_turns_the_loader_notice_off(self):
        self.run_case('first-start')

    def test_an_earlier_choice_carries_over(self):
        self.run_case('carry-over')

    def test_the_card_its_three_choices_and_one_at_a_time(self):
        self.run_case('open')

    def test_the_console_commands_show_it_and_bring_it_back(self):
        self.run_case('commands')

    def test_only_the_server_browser_routes(self):
        self.run_case('targets')

    def test_nothing_is_queued_while_the_menu_page_loads(self):
        self.run_case('loading-page')

    def test_translated_from_the_companion_catalog(self):
        self.run_case('translation')

    def test_the_companions_saved_language_for_the_menu(self):
        self.run_case('saved-language')

    def test_the_catalog_loads_without_compile_string(self):
        self.run_case('menu-compile')

    def test_a_card_that_cannot_be_shown_never_closes_the_browser(self):
        self.run_case('failure')

    def test_nothing_outside_the_menu_realm(self):
        self.run_case('not-menu')


@unittest.skipUnless(NODE, 'Node.js is not installed')
class MultiplayerNoticePageTests(unittest.TestCase):
    def test_the_page_half(self):
        done = subprocess.run([NODE, str(Path(__file__).with_name('multiplayer_notice_page.js')), str(SCRIPT)],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        for name in ('page', 'without-loader-notice', 'update-seen', 'never-swallowed'):
            self.assertIn('PASS ' + name, done.stdout)


if __name__ == '__main__':
    unittest.main()
