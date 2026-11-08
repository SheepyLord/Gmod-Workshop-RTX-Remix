"""R23 (ADR 0130): the companion's engine guard autorun under LuaJIT (engine_guard_harness.lua)."""
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
class EngineGuardAutorunTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('engine_guard_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_only_in_this_machines_rtx_start(self):
        self.run_case('off')

    def test_client_translates_the_message_and_keeps_it_for_the_other_realms(self):
        self.run_case('client')
        self.run_case('server')

    def test_a_module_from_the_early_view_or_none_at_all(self):
        self.run_case('already-loaded')
        self.run_case('no-module')

    def test_a_start_that_went_on_leaves_no_report(self):
        self.run_case('recovered')

    def test_the_next_start_names_the_add_on_once(self):
        self.run_case('notice')


if __name__ == '__main__':
    unittest.main()
