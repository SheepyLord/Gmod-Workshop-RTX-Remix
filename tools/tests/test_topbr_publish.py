"""Issue 6 (ADR 0212): ToPBR publishes what it converts although a scan of the other mods could not read every file.
The fixes' eleventh patch's complete files are the patch applied, its SDK-free regression (fallback_guard_test.cpp)
passes, pins.json builds the module with it after queued-draws, and the RTX Remix pages say what ToPBR does."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text
from test_queued_draws import added

FOLDER = SKINNING / 'topbr-publish'
PATCH = FOLDER / 'topbr-publish.patch'
TO_PBR = 'source/material_pipeline/to_pbr'
FILES = [f'{TO_PBR}/fallback_guard.h', f'{TO_PBR}/to_pbr.cpp', f'{TO_PBR}/to_pbr.h', 'tests/fallback_guard_test.cpp']
SETTINGS = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_settings.lua'
LUA = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 $Source /Fefallback_guard_test.exe /Fofallback_guard_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'fallback_guard_test.exe') (Join-Path $Scratch 'fixture')
exit $LASTEXITCODE
'''


class ToPBRPublishTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """fallback_guard.h, to_pbr.cpp and to_pbr.h are autopbr's copies (no patch between changed them) with this
        patch applied; the regression is its added lines. pins.json builds the module with it, right after queued
        draws, and records the tree the twelve patches give."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), FILES)
        for path in FILES[:3]:
            self.assertEqual(apply(patch, path, text(SKINNING / 'autopbr' / path)), text(FOLDER / path), path)
        self.assertEqual(added(patch, FILES[3]), text(FOLDER / FILES[3]).rstrip('\n').split('\n'))
        pins = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
        patches = pins['patches']
        queued = 'packages/fixes/licenses/oversized-skinning/queued-draws/queued-draws.patch'
        self.assertEqual(patches.index(PATCH.relative_to(REPO).as_posix()), patches.index(queued) + 1)

    def test_a_partial_scan_no_longer_suppresses(self):
        """The shipped selector ignores whether the scan was complete; the publication rescans at most every 30 s
        and logs a partial scan's first unread file once."""
        guard = text(FOLDER / FILES[0])
        select = guard.split('Materials Select(', 1)[1].split('\n}\n', 1)[0]
        self.assertNotIn('complete', select)
        self.assertIn('!guard.hashes.count(pair.first)', select)
        source = text(FOLDER / FILES[1])
        write = source.split('bool TextureProcessor::WriteModUSDA() {', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('std::chrono::seconds(30)', write)
        self.assertIn('&state.cache', write)
        self.assertIn('Mod scan partial', write)
        self.assertNotIn('uncertain/suppressed', source)

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_guard_regression_passes(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='topbr-publish-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(FOLDER / FILES[3]), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS fallback guard:', result.stdout)

    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT unavailable')
    def test_the_settings_pages(self):
        result = subprocess.run([LUA, str(REPO / 'tools/tests/rtx_settings_harness.lua'), str(SETTINGS)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS RTX settings pages:', result.stdout)


if __name__ == '__main__':
    unittest.main()
