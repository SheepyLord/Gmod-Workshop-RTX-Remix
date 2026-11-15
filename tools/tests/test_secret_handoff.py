"""The About tab takes the secret replacements whole (runtime patch 0098): no race with a mod load.

Compiles and runs the handoff's unit test from the committed patch (MSVC, as the runtime builds it), and checks
that the asset replacer builds the map on its own and publishes it whole, and that the About tab's accessors go
through the handoff."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PATCHES = sorted((REPO / 'runtime' / 'patches').glob('0098-*.patch'))
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
HANDOFF = 'src/dxvk/rtx_render/rtx_secret_handoff.h'
TEST = 'tests/rtx/unit/test_secret_handoff.cpp'
REPLACER_H = 'src/dxvk/rtx_render/rtx_asset_replacer.h'
REPLACER_CPP = 'src/dxvk/rtx_render/rtx_asset_replacer.cpp'


def patch_text() -> str:
    if len(PATCHES) != 1:
        raise AssertionError(f'expected one runtime patch 0098, found {[p.name for p in PATCHES]}')
    return PATCHES[0].read_text(encoding='utf-8')


def file_block(patch: str, path: str) -> str:
    return patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]


def postimage(patch: str, path: str) -> str:
    """A file the patch creates, whole (one hunk from line 1 with every line added)."""
    block = file_block(patch, path)
    if 'new file mode' not in block.split('@@', 1)[0]:
        raise AssertionError(f'{path}: not a new file in the patch')
    header, body = block.split('@@', 2)[1:]
    match = re.search(r'\+1,(\d+)', header)
    count = int(match[1]) if match else 1
    lines = [line[1:] for line in body.splitlines()[1:] if line.startswith('+')]
    if len(lines) != count:
        raise AssertionError(f'{path}: hunk length mismatch ({len(lines)} != {count})')
    return '\n'.join(lines) + '\n'


def added_lines(patch: str, path: str) -> str:
    return '\n'.join(line[1:].rstrip('\r') for line in file_block(patch, path).splitlines()
                     if line.startswith('+') and not line.startswith('+++'))


def removed_lines(patch: str, path: str) -> str:
    return '\n'.join(line[1:].rstrip('\r') for line in file_block(patch, path).splitlines()
                     if line.startswith('-') and not line.startswith('---'))


SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_secret_handoff.cpp /Fehandoff.exe /Fohandoff.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./handoff.exe
exit $LASTEXITCODE
'''


class SecretHandoffTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_handoffs_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='secret-handoff-', dir=scratch) as directory:
            root = Path(directory)
            for path in (HANDOFF, TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(postimage(patch, path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS secret handoff: \d+ checks')

    def test_the_handoff_publishes_and_copies_under_one_lock(self):
        handoff = postimage(patch_text(), HANDOFF)
        self.assertEqual(handoff.count('std::lock_guard<std::mutex> lock(m_mutex);'), 2)  # publish and take
        self.assertIn('m_map = std::move(map);', handoff)
        self.assertIn('m_updated.store(updated, std::memory_order_release);', handoff)
        self.assertIn('return m_updated.load(std::memory_order_acquire);', handoff)
        # take() returns a copy, never a reference into the published map.
        self.assertIn('    Map take() {', handoff)
        self.assertNotIn('Map& take()', handoff)
        # Self-contained: the gate compiles it with the standard library only.
        self.assertEqual(re.findall(r'#include <([^>]+)>', handoff), ['atomic', 'mutex', 'utility'])
        self.assertNotIn('#include "', handoff)

    def test_the_replacer_builds_the_map_and_publishes_it_whole(self):
        patch = patch_text()
        cpp = added_lines(patch, REPLACER_CPP)
        self.assertIn('SecretReplacements secretReplacements;', cpp)
        self.assertIn('secretReplacements[secrets.first].emplace_back(', cpp)
        self.assertIn('m_variantInfos.erase_if([&secretReplacements](const auto& it) {', cpp)
        self.assertIn('m_secretHandoff.publish(std::move(secretReplacements), updated);', cpp)
        # The shared map is no longer cleared and refilled in place, nor the bare flag set.
        removed = removed_lines(patch, REPLACER_CPP)
        self.assertIn('m_secretReplacements.clear();', removed)
        self.assertIn('m_bSecretReplacementsUpdated = updated;', removed)
        # The variants are checked against the new map before it is published.
        block = file_block(patch, REPLACER_CPP)
        self.assertLess(block.index('m_variantInfos.erase_if([&secretReplacements]'),
                        block.index('m_secretHandoff.publish(std::move(secretReplacements), updated);'))

    def test_the_about_tabs_accessors_go_through_the_handoff(self):
        patch = patch_text()
        header = added_lines(patch, REPLACER_H)
        self.assertIn('#include "rtx_secret_handoff.h"', header)
        self.assertIn('return m_secretHandoff.pending();', header)
        self.assertIn('SecretReplacements getSecretReplacementInfo() {', header)
        self.assertIn('return m_secretHandoff.take();', header)
        self.assertIn('SecretHandoff<SecretReplacements> m_secretHandoff;', header)
        removed = removed_lines(patch, REPLACER_H)
        for line in ('const SecretReplacements& getSecretReplacementInfo() {', 'bool m_bSecretReplacementsUpdated = false;',
                     'SecretReplacements m_secretReplacements;'):
            self.assertIn(line, removed)
        # The About tab binds the returned copy (const auto&), so it needs no change.
        self.assertNotIn('diff --git a/src/dxvk/imgui/dxvk_imgui_about.cpp', patch)
        self.assertIn("'rtx_render/rtx_secret_handoff.h',", added_lines(patch, 'src/dxvk/meson.build'))
        self.assertIn("executable('test_secret_handoff'", added_lines(patch, 'tests/rtx/unit/meson.build'))


if __name__ == '__main__':
    unittest.main()
