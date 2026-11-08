"""R23 item 4: the Advanced Material Editor's material carries over between its sheets (ame_tabs_harness.lua)."""
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
class EditorSheetTests(unittest.TestCase):
    def test_the_edited_material_carries_over_between_material_and_source(self):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('ame_tabs_harness.lua')), str(REPO)],
                              capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ame tabs', done.stdout)


if __name__ == '__main__':
    unittest.main()
