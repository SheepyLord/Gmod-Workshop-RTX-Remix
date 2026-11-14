"""ADR 0206: the companion's clean-up of RTX a removed loader left, and the RTX-start gates (LuaJIT harness)."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
HARNESS = Path(__file__).with_name('leftovers_harness.lua')
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
COMPANION = REPO / 'companion/nativeloader/lua/autorun'
FIXES = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun'
COMPANION_GATE = 'if NativeLoaderRTXStart and not NativeLoaderRTXStart() then return end'
FIXES_GATE = 'if not (NATIVELOADER_VERIFIED_MULTIPLAYER or NativeLoaderRTXStart and NativeLoaderRTXStart()) then return end'
# The file that answers, the two render-guard files that were RTX-only already, and the clean-up itself.
UNGATED = {'!!!!nativeloader_engine_guard.lua', '_nativeloader_guard.lua', '_nativeloader_effect_categories.lua',
           'nativeloader_leftovers.lua'}


def first_code_line(path):
    for line in path.read_text(encoding='utf-8').splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith('--'):
            return stripped
    return ''


DEBUG = REPO / 'packages/fixes/source/debug/addon/lua/autorun/client/rtx_debug.lua'
LOAD_ACCEL = REPO / 'fs_accel/addon/lua/autorun/!!!!!nlloadaccel.lua'


def gated():
    files = [(path, COMPANION_GATE) for path in sorted(COMPANION.rglob('*.lua')) if path.name not in UNGATED]
    files += [(path, FIXES_GATE) for path in sorted(FIXES.glob('*.lua'))]
    files.append((DEBUG, FIXES_GATE))  # the fixes' debug add-on, which loads its own module (seen on the PoC)
    return files


class GateSourceTests(unittest.TestCase):
    def test_every_companion_and_fixes_autorun_starts_with_its_gate(self):
        files = gated()
        self.assertGreater(len(files), 25)
        for path, gate in files:
            with self.subTest(path=path.relative_to(REPO).as_posix()):
                self.assertEqual(first_code_line(path), gate)

    def test_the_answer_is_set_before_the_engine_guard_stops_outside_rtx(self):
        text = (COMPANION / '!!!!nativeloader_engine_guard.lua').read_text(encoding='utf-8')
        answer = text.find('NativeLoaderRTXStart = function() return isRTXStart end')
        stop = text.find('if not isRTXStart then return end')
        self.assertGreater(answer, 0)
        self.assertGreater(stop, answer)
        self.assertLess(text.find('if NativeLoaderEngineGuardAutorun then return end'), answer)
        # It sorts before every other autorun of the package, the RTX fixes' included.
        names = [p.name for p in COMPANION.glob('*.lua')] + [p.name for p in FIXES.glob('*.lua')]
        self.assertEqual(min(n for n in names if n != '!!!!!nlloadaccel.lua'), '!!!!nativeloader_engine_guard.lua')

    def test_the_load_accelerator_decides_for_itself_before_its_module(self):
        # It sorts before the companion's answer, so it carries the same decision; no convar or module before it.
        text = LOAD_ACCEL.read_text(encoding='utf-8')
        decision = text.find('if not rtx then return end')
        self.assertGreater(decision, 0)
        self.assertIn('native-loader/rtx-session.txt', text[:decision])
        self.assertIn('\'\\n"activation":{"outcome":"active"\'', text[:decision])
        for later in ('CreateConVar(', 'require, "nlfsaccel"'):
            self.assertGreater(text.find(later), decision, later)

    def test_the_clean_up_is_not_sent_to_clients_and_loads_no_module_in_rtx_or_with_the_loader(self):
        text = (COMPANION / 'server/nativeloader_leftovers.lua').read_text(encoding='utf-8')
        self.assertNotIn('AddCSLuaFile', text)
        self.assertLess(text.find('NativeLoaderRTXStart()'), text.find('require'))
        self.assertLess(text.find('"bin/win64/winmm.dll", "BASE_PATH"'), text.find('require'))
        self.assertTrue(re.search(r'hook\.Add\("Initialize", "nativeloader_leftovers"', text))


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class GateRunTests(unittest.TestCase):
    def test_outside_rtx_each_file_returns_before_touching_anything(self):
        for path, _ in gated():
            for rtx in ('no', 'yes'):
                with self.subTest(path=path.relative_to(REPO).as_posix(), rtx=rtx):
                    done = subprocess.run([LUAJIT, str(HARNESS), str(REPO), 'gate', str(path), rtx],
                                          capture_output=True, text=True, timeout=20)
                    self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class TriggerTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(HARNESS), str(REPO), 'trigger', scenario],
                              capture_output=True, text=True, timeout=20, encoding='utf-8')
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_nothing_in_an_rtx_start(self):
        self.run_case('rtx-start')

    def test_nothing_on_a_dedicated_server(self):
        self.run_case('dedicated')

    def test_no_module_is_loaded_while_the_loader_is_installed(self):
        self.run_case('loader-installed')

    def test_without_the_module_nothing_happens(self):
        self.run_case('no-module')

    def test_the_modules_no_is_silent(self):
        self.run_case('not-needed')

    def test_an_error_in_the_module_call_is_contained(self):
        self.run_case('module-error')

    def test_a_refusal_is_only_logged(self):
        self.run_case('refused')

    def test_a_removal_restores_the_settings_and_tells_the_player(self):
        self.run_case('removed')

    def test_the_notice_is_in_the_players_language(self):
        self.run_case('french')

    def test_a_partial_removal_lists_what_stayed(self):
        self.run_case('partly')


if __name__ == '__main__':
    unittest.main()
