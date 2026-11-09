"""Endfield maps (ADR 0137): the fixes' matching regression on the ToPBR headers the module is built from."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SKINNING = REPO / 'packages/fixes/licenses/oversized-skinning'
FOLDER = SKINNING / 'endfield-maps'
PATCH = FOLDER / 'endfield-maps.patch'
TO_PBR = 'source/material_pipeline/to_pbr'
# Each patch that changed the ToPBR sources keeps its complete changed files; in patch order, a later
# folder's files replace an earlier one's. autopbr holds them all, the later folders their changes.
LAYERS = ('autopbr', 'wuwa-maps', 'endfield-maps', 'game-emission')
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'

SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 tests/game_matching_test.cpp /Fegame_matching_test.exe /Fogame_matching_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'game_matching_test.exe') (Join-Path $Scratch 'matching')
exit $LASTEXITCODE
'''


def text(path):
    return path.read_bytes().decode('utf-8').replace('\r\n', '\n')


def apply(patch, path, before):
    """One file's hunks of a git diff applied to `before` (LF text), each context and removed line checked."""
    block = patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]
    old, new, at = before.split('\n'), [], 0
    for hunk in re.finditer(r'^@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@[^\n]*\n((?:[ +\\-][^\n]*(?:\n|$))*)', block, re.M):
        start = int(hunk[1]) - 1
        if start < at:
            raise AssertionError(f'{path}: overlapping hunks')
        new += old[at:start]
        at = start
        for line in hunk[2].splitlines():
            tag, rest = line[:1], line[1:]
            if tag == '\\':
                continue
            if tag in ' -':
                if at >= len(old) or old[at] != rest:
                    raise AssertionError(f'{path}: line {at + 1} does not match the patch')
                at += 1
            if tag in ' +':
                new.append(rest)
    return '\n'.join(new + old[at:])


class EndfieldMapsTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """The folder's complete files are the preceding complete files with endfield-maps.patch applied,
        and pins.json builds the module with that patch."""
        patch = PATCH.read_text(encoding='utf-8')
        files = re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M)
        self.assertEqual(files, [f'{TO_PBR}/game_matching.inl', 'tests/game_matching_test.cpp'])
        before = {files[0]: SKINNING / 'wuwa-maps' / files[0], files[1]: SKINNING / 'autopbr' / files[1]}
        for path in files:
            self.assertEqual(apply(patch, path, text(before[path])), text(FOLDER / path), path)
        pins = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
        self.assertIn(PATCH.relative_to(REPO).as_posix(), pins['patches'])
        self.assertIn('source/*', pins['patch_paths'])
        self.assertNotIn('tests/*', pins['patch_paths'])

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_matching_regression_on_the_shipped_headers(self):
        """Compiles the regression with assertions and /W4 /WX on the shipped ToPBR headers: Endfield's
        NPC, weapon and item families pair by exact stem and are never UV candidates; R12's cases hold."""
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='endfield-maps-', dir=scratch) as directory:
            root = Path(directory)
            (root / TO_PBR).mkdir(parents=True)
            (root / 'tests').mkdir()
            for layer in LAYERS:
                for file in (SKINNING / layer / TO_PBR).iterdir():
                    shutil.copyfile(file, root / TO_PBR / file.name)
            shutil.copyfile(SKINNING / 'autopbr/tests/game_pbr_types.h', root / 'tests/game_pbr_types.h')
            shutil.copyfile(FOLDER / 'tests/game_matching_test.cpp', root / 'tests/game_matching_test.cpp')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS Endfield maps:', result.stdout)
            self.assertIn('PASS R12 matching:', result.stdout)


if __name__ == '__main__':
    unittest.main()
