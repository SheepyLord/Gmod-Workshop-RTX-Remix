"""Load speed-up round 3 (ADR 0241): the hooks, timers and net receivers of a map load timed, the slowest named and
written for the load overlay's end line, the originals put back. Runs the load accelerator's
nlloadaccel/load_callbacks.lua under LuaJIT (load_callbacks_harness.lua), once per scenario."""
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
class LoadCallbackTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('load_callbacks_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, encoding='utf-8', timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_the_client_times_names_and_puts_back(self):
        self.run_case('client')

    def test_the_server_times_names_and_puts_back(self):
        self.run_case('server')

    def test_the_switch_replaces_nothing(self):
        self.run_case('off')


class LoadCallbackSourceTests(unittest.TestCase):
    """The add-on's autorun includes it first, so that it times the other add-ons' callbacks from their start."""

    def test_included_first_in_both_realms(self):
        autorun = (REPO / 'fs_accel' / 'addon' / 'lua' / 'autorun' / '!!!!!nlloadaccel.lua').read_text(encoding='utf-8')
        self.assertIn('AddCSLuaFile("nlloadaccel/load_callbacks.lua")', autorun)
        self.assertLess(autorun.index('include("nlloadaccel/load_callbacks.lua")'),
                        autorun.index('include("nlloadaccel/arc9_icons.lua")'))


if __name__ == '__main__':
    unittest.main()
