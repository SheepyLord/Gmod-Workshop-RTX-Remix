"""ADR 0188: the companion's notice for a Steam account that does not subscribe to the RTX package (LuaJIT harness)."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class UnsubscribedNoticeTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('unsubscribed_notice_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_a_subscribed_account_sees_nothing(self):
        self.run_case('subscribed')

    def test_an_account_that_does_not_subscribe_sees_the_card_once(self):
        self.run_case('not-subscribed')

    def test_nothing_is_decided_before_steam_lists_the_subscriptions(self):
        self.run_case('waits-for-the-list')

    def test_a_list_still_growing_is_not_trusted(self):
        self.run_case('growing-list')

    def test_steamworks_is_subscribed_is_a_second_opinion(self):
        self.run_case('steam-says-subscribed')

    def test_dont_show_this_again_and_the_console_commands(self):
        self.run_case('dismissed')

    def test_the_dismiss_button_remembers(self):
        self.run_case('dismiss-button')

    def test_subscribing_again_in_the_menu(self):
        self.run_case('resubscribed')

    def test_nothing_for_a_local_source(self):
        self.run_case('local-source')

    def test_nothing_without_the_loaders_report(self):
        self.run_case('no-status')

    def test_translated_with_the_item_in_the_text(self):
        self.run_case('translation')

    def test_a_card_that_cannot_be_built_is_only_logged(self):
        self.run_case('failure')

    def test_nothing_outside_the_menu_realm(self):
        self.run_case('not-menu')


if __name__ == '__main__':
    unittest.main()
