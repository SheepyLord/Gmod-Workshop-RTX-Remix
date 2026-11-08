"""R23 item 3: the progress notice while imported characters' game PBR maps convert (pbr_progress_harness.lua)."""
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
class PBRProgressNoticeTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('pbr_progress_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_a_quick_restore_shows_nothing(self):
        self.run_case('quick')

    def test_progress_then_ready_then_a_new_batch(self):
        self.run_case('progress')

    def test_a_closed_notice_stays_closed_for_its_batch(self):
        self.run_case('closed')

    def test_without_the_fixes_nothing_and_a_failure_stops_the_poll(self):
        self.run_case('absent')


if __name__ == '__main__':
    unittest.main()
