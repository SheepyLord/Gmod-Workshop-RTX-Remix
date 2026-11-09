"""R24 (ADR 0134): the companion's loading status menu script under LuaJIT (loading_status_harness.lua), and a check
that the companion's menu scripts use no name GMod's Lua reserves."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
MENU = REPO / 'companion' / 'nativeloader' / 'lua' / 'nativeloader' / 'menu'


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class LoadingStatusTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('loading_status_harness.lua')), str(REPO), scenario],
                              capture_output=True, text=True, encoding='utf-8', timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_a_load_from_its_start_to_the_summary(self):
        self.run_case('load')

    def test_the_map_named_just_before_the_load_is_seen(self):
        self.run_case('details-first')

    def test_joining_a_server_names_it(self):
        self.run_case('joining')

    def test_a_game_started_here_is_loaded_not_joined(self):
        self.run_case('local')

    def test_translated_from_the_companion_catalog(self):
        self.run_case('translated')

    def test_the_companions_saved_language_for_the_menu(self):
        self.run_case('saved-language')

    def test_the_catalog_loads_without_compile_string(self):
        self.run_case('menu-compile')

    def test_the_setting_turns_it_off(self):
        self.run_case('off')

    def test_nothing_without_the_module_or_outside_the_menu(self):
        self.run_case('no-module')
        self.run_case('not-menu')


class GModSyntaxTests(unittest.TestCase):
    """GMod's Lua makes `continue` a keyword: a field or variable of that name compiles under LuaJIT but not in the
    game (R24: the notice's `continue = N"..."` stopped the whole script in the menu realm)."""

    STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
    NAMED = re.compile(r'\.\s*continue\b|\bcontinue\s*=(?!=)|\[\s*continue\s*\]')

    def test_menu_scripts_use_no_gmod_keyword_as_a_name(self):
        scripts = sorted(MENU.glob('*.lua'))
        self.assertTrue(scripts)
        for path in scripts:
            for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                code = self.STRING.sub('""', line.split('--', 1)[0])
                self.assertIsNone(self.NAMED.search(code), f'{path.name}:{number}: "continue" is a keyword in GMod Lua')

    def test_the_check_finds_the_r24_mistake(self):
        self.assertIsNotNone(self.NAMED.search('    continue = N"I understand, continue",'))
        self.assertIsNotNone(self.NAMED.search('L(TEXT.continue)'))
        self.assertIsNone(self.NAMED.search('local continueText = 1'))
        self.assertIsNone(self.NAMED.search('if x then continue end'))


if __name__ == '__main__':
    unittest.main()
