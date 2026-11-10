"""Detailed prop collision (CoACD) serves one import; the single hull is every import's default."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl'
HARNESS = REPO / 'tools/tests/hotloader_prop_options_harness.lua'


def luajit():
    found = shutil.which('luajit')
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
    return found or (str(local) if local.is_file() else None)


class HotloaderPropOptionsTests(unittest.TestCase):
    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_detailed_collision_is_not_a_remembered_default(self):
        result = subprocess.run([luajit(), str(HARNESS), str(LUA / 'props/library.lua'), str(LUA / 'library.lua')],
                                cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: detailed collision serves one import', result.stdout)

    def test_the_importer_combo_follows_its_setting(self):
        ui = (LUA / 'ui.lua').read_text(encoding='utf-8')
        start = ui.index('local function convarChoices(')
        body = ui[start:ui.index('\nend\n', start)]
        # The combo shows a value the setting took elsewhere (the single hull after an import).
        self.assertIn('combo.Think=function', body)
        self.assertIn('GetConVar(cvar):GetString()', body)


if __name__ == '__main__':
    unittest.main()
