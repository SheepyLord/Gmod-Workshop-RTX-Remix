"""ADR 0255: the Model Hotloader installs a Workshop package's models several at once, lists them in the library
without a rebuild per model, and runs its install work below normal CPU priority. Runs the shipped workshop.lua and
library.lua under LuaJIT with the natives, disk, timers and frames instrumented, and reads the native module's source."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/model-hotloader/mmd_hotloader/lua'
NATIVE = REPO / 'packages/model-hotloader/source/mmdhl/native/module.cpp'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('parallel', 'failures', 'replace', 'library_add',
             # ADR 0278: updates that keep every file's size, older records, an interrupted update, a server.
             'update_same_size', 'update_in_use', 'unchanged', 'legacy_same_package', 'legacy_other_package',
             'legacy_other_stale', 'resume', 'server_update', 'pack_owners',
             'supersede_key', 'supersede_legacy', 'supersede_save', 'supersede_owned', 'supersede_shared',
             'supersede_ambiguous', 'supersede_legacy_collision', 'supersede_failure', 'supersede_private',
             'supersede_field', 'supersede_settings', 'legacy_other_binary', 'journal_owners', 'supersede_previous',
             'supersede_demo', 'supersede_rollback')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class WorkshopInstallTests(unittest.TestCase):
    def test_scenarios(self):
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(Path(__file__).with_name('hotloader_workshop_install_harness.lua')),
                                         str(LUA / 'mmdhl'), scenario], cwd=REPO, capture_output=True,
                                        encoding='utf8', errors='replace', timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + scenario, result.stdout)


class WorkshopInstallSourceTests(unittest.TestCase):
    def lambda_body(self, source: str, function: str) -> str:
        body = source[source.index(f'FUNCTION({function})'):]
        return body[:body.index('END_FUNCTION')]

    def test_install_work_runs_in_background_mode(self):
        source = NATIVE.read_text(encoding='utf8')
        helper = source[source.index('struct BackgroundWork{'):]
        helper = helper[:helper.index('};')]
        self.assertIn('SetThreadPriority(GetCurrentThread(),THREAD_PRIORITY_BELOW_NORMAL)', helper)
        self.assertIn('SetThreadPriority(GetCurrentThread(),was)', helper)
        # Not Windows' background mode: its very low I/O priority held a large model's check to a tenth of its speed.
        self.assertNotIn('THREAD_MODE_BACKGROUND_BEGIN', helper)
        for function in ('CommitSharedFile', 'StartAssetCheck'):
            body = self.lambda_body(source, function)
            self.assertRegex(body, r'std::async\(std::launch::async,\[[^\]]*\]\{\s*BackgroundWork background;', function)
        # A spawn waits for its load: that stays at the game's priority.
        self.assertNotIn('BackgroundWork', self.lambda_body(source, 'RequestAsset'))

    def test_installed_models_are_listed_without_a_rebuild_each(self):
        workshop = (LUA / 'mmdhl/workshop.lua').read_text(encoding='utf8')
        installed = workshop[workshop.index('local function installed(job)'):]
        installed = installed[:installed.index('\nend')]
        self.assertIn('listInstalled(item)', installed)
        self.assertIn('saveStateSoon()', installed)
        self.assertNotRegex(installed, r'\bsaveState\(\)')
        library = (LUA / 'mmdhl/library.lua').read_text(encoding='utf8')
        self.assertIn('function library.Add(ids)', library)
        self.assertIn('function library.Prime(id)', library)
        listed = workshop[workshop.index('local function listInstalled(item)'):]
        listed = listed[:listed.index('\nend')]
        self.assertIn('mmdhl.library.Prime(item.asset)', listed)


if __name__ == '__main__':
    unittest.main()
