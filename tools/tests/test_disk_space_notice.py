"""ADR 0260: the companion's menu notice about disk space for the loader's unpacking (nativeloader/menu/disk_space.lua)
under LuaJIT. See test_disk_space_notice.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'companion/nativeloader/lua/nativeloader/menu/disk_space.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class DiskSpaceNoticeTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('disk_space_harness.lua')), str(REPO), scenario],
                                cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_a_start_the_loader_refused_for_space_says_what_to_free(self):
        self.run_lua('failed_need')

    def test_a_drive_that_filled_while_unpacking_is_said_too(self):
        self.run_lua('failed_full')

    def test_too_little_space_for_the_largest_package_is_said_before_an_update(self):
        self.run_lua('low')

    def test_enough_space_shows_nothing(self):
        self.run_lua('enough')

    def test_an_older_client_module_still_explains_a_failure(self):
        self.run_lua('old_module')

    def test_other_failures_and_other_realms_show_nothing(self):
        self.run_lua('unrelated')

    def test_the_sample_cards_show_and_leave_the_real_state(self):
        self.run_lua('preview')

    def test_the_cards_follow_the_players_language(self):
        self.run_lua('translations')

    def test_the_script_compiles(self):
        result = subprocess.run([LUAJIT, '-e', f"assert(loadfile([[{SCRIPT}]]))"],
                                cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_the_loaders_words_are_the_ones_the_script_reads(self):
        # The card parses the loader's own messages: they must stay as the script expects them.
        deploy = (REPO / 'loader/core/src/deploy.cpp').read_text(encoding='utf-8')
        self.assertIn('"not enough free disk space: the new files need "', deploy)
        self.assertIn('" MiB and "', deploy)
        self.assertIn('" MiB should stay free, but only "', deploy)
        self.assertIn('" MiB are free"', deploy)
        self.assertIn('constexpr std::uint64_t kSpareBytes = std::uint64_t{64} << 20;', deploy)
        fs = (REPO / 'loader/core/src/fs.cpp').read_text(encoding='utf-8')
        self.assertIn('" (Windows error " + std::to_string(code) + ")"', fs)
        script = SCRIPT.read_text(encoding='utf-8')
        self.assertIn('local SPARE = 64 * MIB', script)


if __name__ == '__main__':
    unittest.main()
