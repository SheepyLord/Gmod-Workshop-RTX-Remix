"""The Remix splash (runtime patches 0102 and 0103; the review of 2026-11-16, findings 10 and 17): it shows once, as the
process starts, for at most a minute, and its editable text comes from rtx-remix/mods/nativeloader_ui, never from
garrysmod/data, where any server's client Lua writes .txt files.

Rebuilds the startup text's header and its unit test from the patches that create and change them (0012, 0034,
0103), compiles them with MSVC and runs them; checks the splash's timing and the text's folder in the patches, and
that the fixes packager deploys the text where the runtime reads it."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import package_fixes  # noqa: E402
import runtime_patch_text as patches  # noqa: E402

REPO = patches.REPO
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
HEADER = 'src/util/util_startup_message.h'
TEST = 'tests/rtx/unit/test_splash_message.cpp'
SPLASH = 'src/dxvk/imgui/dxvk_imgui_splash.cpp'
SPLASH_H = 'src/dxvk/imgui/dxvk_imgui_splash.h'
I18N = 'src/dxvk/rtx_render/rtx_fork_i18n.cpp'
OLD_FOLDER = '"garrysmod/data/nativeloader_ui"'

SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W3 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_splash_message.cpp /Fesplash.exe /Fosplash.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./splash.exe (Join-Path $Scratch 'fixture')
exit $LASTEXITCODE
'''


def folder_of(header: str) -> str:
    match = re.search(r'static constexpr std::string_view folder = "([^"]+)";', header)
    if not match:
        raise AssertionError('StartupMessage::folder is missing')
    return match.group(1)


class RuntimeSplashTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_startup_texts_unit_test_from_the_patches(self):
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='runtime-splash-', dir=scratch) as directory:
            root = Path(directory)
            for path in (HEADER, TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(patches.rebuilt(path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Startup text policy tests passed', result.stdout)

    def test_the_text_comes_from_a_folder_lua_cannot_write(self):
        header = patches.rebuilt(HEADER)
        self.assertEqual(folder_of(header), 'rtx-remix/mods/nativeloader_ui')
        self.assertNotIn('garrysmod/data', folder_of(header))
        test = patches.rebuilt(TEST)
        self.assertIn('check(StartupMessage::folder == "rtx-remix/mods/nativeloader_ui");', test)
        patch = patches.read(patches.one_patch(103))
        for path in (SPLASH, I18N):
            self.assertIn(OLD_FOLDER, patches.removed_lines(patch, path))
            self.assertIn('StartupMessage::load(StartupMessage::folder, ', patches.added_lines(patch, path))
        # No code the series keeps reads the old folder.
        left = [path for path, lines in patches.live_added_lines().items()
                if any(OLD_FOLDER in line for line, count in lines.items() if count > 0)]
        self.assertEqual(left, [])

    def test_the_packager_deploys_the_text_where_the_runtime_reads_it(self):
        self.assertEqual(package_fixes.STARTUP_TEXT, folder_of(patches.rebuilt(HEADER)))
        self.assertEqual(package_fixes.policy_for(package_fixes.STARTUP_TEXT), 'create-only')

    def test_the_splash_shows_once_for_at_most_a_minute(self):
        patch = patches.read(patches.one_patch(102))
        header = patches.added_lines(patch, SPLASH_H)
        self.assertIn('static constexpr std::uint32_t kMaxDisplaySeconds = 60;', header)
        self.assertIn('static constexpr long long kStartWindowSeconds = 120;', header)
        self.assertIn('std::chrono::steady_clock::time_point m_startTime;', header)
        self.assertIn('std::chrono::system_clock::time_point m_startTime;', patches.removed_lines(patch, SPLASH_H))
        splash = patches.added_lines(patch, SPLASH)
        # The option's maximum, and again where it is read.
        self.assertIn('args.maxValue = ImGuiSplash::kMaxDisplaySeconds);', splash)
        self.assertIn('std::min(SplashSettings::splashMessageDisplayTimeSeconds(), kMaxDisplaySeconds);', splash)
        # It starts only in the first two minutes, never times from the epoch, and stays closed once its time passed.
        self.assertIn('duration_cast<seconds>(now - m_firstUpdateTime).count() > kStartWindowSeconds', splash)
        self.assertIn('if (!m_hasStarted) {', splash)
        self.assertIn('if (elapsedSeconds > static_cast<long long>(displaySeconds)) {', splash)
        self.assertEqual(splash.count('m_hasFinished = true;'), 2)
        self.assertIn('if (static_cast<std::uint32_t>(elapsedSeconds) <= SplashSettings::splashMessageDisplayTimeSeconds()) {',
                      patches.removed_lines(patch, SPLASH))
        # RtxOptions.md, which the runtime's documentation test compares with the build, has the maximum.
        self.assertIn('|rtx.splashMessageDisplayTimeSeconds|int|12||60|', patches.added_lines(patch, 'RtxOptions.md'))


if __name__ == '__main__':
    unittest.main()
