"""R26: the load accelerator's Lua (its add-on's autorun and the companion's menu script) under LuaJIT
(load_accel_harness.lua)."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / 'fs_accel/addon/lua/autorun/!!!!!nlloadaccel.lua'
MENU = REPO / 'companion/nativeloader/lua/nativeloader/menu/load_accel.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('serve', 'not-title', 'selftest-mismatch', 'selftest-skip', 'selftest-none', 'selftest-changing', 'verify',
             'left-out', 'off', 'off-client', 'on-client', 'no-module', 'invalidate', 'tally', 'server-dedicated',
             'server-listen', 'menu-install', 'menu-left-out', 'menu-not-menu', 'menu-off', 'not-rtx',
             'not-rtx-marker')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class LoadAccelTests(unittest.TestCase):
    def test_scenarios(self):
        harness = Path(__file__).with_name('load_accel_harness.lua')
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                done = subprocess.run([LUAJIT, str(harness), str(ADDON), str(MENU), scenario], capture_output=True,
                                      text=True, timeout=30)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assertIn('PASS ' + scenario, done.stdout)


if __name__ == '__main__':
    unittest.main()
