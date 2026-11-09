"""The companion's end to a stuck spawn-menu drag (R25): ended only when nothing can receive the release."""
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
class StuckDragTests(unittest.TestCase):
    def test_scenarios(self):
        source = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_dragdrop.lua'
        harness = Path(__file__).with_name('stuck_drag_harness.lua')
        for scenario in ('idle', 'hidden_cursor', 'visible', 'hidden_panel', 'hidden_then_drop', 'stop_error',
                         'hidden_panel_held', 'drop_menu', 'watch', 'removed_panel'):
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(harness), str(source), scenario], capture_output=True,
                                        text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + scenario, result.stdout)


if __name__ == '__main__':
    unittest.main()
