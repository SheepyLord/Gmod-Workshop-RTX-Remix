"""ADR 0251: the RTX fixes' weapon copy draws nothing before the frame is rendered. Runs pseudoweapon_harness.lua under
LuaJIT. See test_pseudoweapon.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/rtx_pseudoweapon.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class PseudoweaponTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('pseudoweapon_harness.lua')), scenario,
                                 str(SOURCE)], cwd=REPO, capture_output=True, encoding='utf-8', errors='replace',
                                timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_a_lua_weapon_in_first_person(self):
        # The tool gun and every scripted weapon have DrawWorldModel: Think once drew it before the frame.
        self.run_lua('first_lua')

    def test_a_lua_weapon_in_third_person(self):
        # The case that left the whole frame without path tracing.
        self.run_lua('third_lua')

    def test_an_engine_weapon(self):
        # An engine weapon (the physics gun) has no DrawWorldModel: its bones are still set up.
        self.run_lua('first_engine')
        self.run_lua('third_engine')


if __name__ == '__main__':
    unittest.main()
