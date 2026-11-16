"""ToPBR's range (the user's request of 2026-11-16, ADR 0229): the fixes' fourteenth native patch (topbr-scope) holds
world conversion to the materials the player's rtx_topbr_scope takes in, its complete files are the patch applied, its
SDK-free regression (topbr_scope_test.cpp) passes, and the client driver starts at the map's own surfaces."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text
from test_queued_draws import added, body

FOLDER = SKINNING / 'topbr-scope'
PATCH = FOLDER / 'topbr-scope.patch'
TO_PBR = 'source/material_pipeline/to_pbr'
FILES = [f'{TO_PBR}/to_pbr.cpp', f'{TO_PBR}/to_pbr.h', f'{TO_PBR}/topbr_scope.h', 'tests/topbr_scope_test.cpp']
DRIVER = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_topbr_conversion.lua'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 $Source /Fetopbr_scope_test.exe /Fotopbr_scope_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'topbr_scope_test.exe')
exit $LASTEXITCODE
'''


class ToPBRScopeTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """to_pbr.cpp and to_pbr.h are topbr-publish's copies (no patch between changed them) with this patch applied;
        the header and the regression are its added lines. pins.json builds the module with it right after eye-texgen
        (lua-guards, the fifteenth, follows it)."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), FILES)
        for path in FILES[:2]:
            self.assertEqual(apply(patch, path, text(SKINNING / 'topbr-publish' / path)), text(FOLDER / path), path)
        for path in FILES[2:]:
            self.assertEqual(added(patch, path), text(FOLDER / path).rstrip('\n').split('\n'), path)
        patches = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']['patches']
        eye = 'packages/fixes/licenses/oversized-skinning/eye-texgen/eye-texgen.patch'
        self.assertEqual(patches.index(PATCH.relative_to(REPO).as_posix()), patches.index(eye) + 1)

    def test_every_queue_takes_only_the_players_range(self):
        """The three places that queue world conversion ask the range; the worker drops what a narrower range left
        out without marking it done; the player's setting is read natively and Lua only adds names."""
        source = text(FOLDER / FILES[0])
        queue = body(source, 'int TextureProcessor::QueueMaterialsForProcessing() {')
        self.assertIn('if (!m_scope.Allows(matName)) continue;', queue)
        self.assertLess(queue.index('if (!m_scope.Allows(matName)) continue;'), queue.index('materialsToQueue.push_back(matName);'))
        single = body(source, 'bool TextureProcessor::ProcessSingleMaterial(const std::string& materialName) {')
        self.assertIn('if (!m_scope.Allows(materialName)) return false;', single)
        worker = body(source, 'void TextureProcessor::WorkerThreadFunc() {')
        dropped = worker.split('} else if (!m_scope.Allows(metadataName)) {', 1)[1].split('} else {', 1)[0]
        self.assertIn('m_queuedMaterials.erase(metadataName);', dropped)
        self.assertNotIn('m_processedMaterials', dropped)
        self.assertIn('SyncScope();', body(source, 'void TextureProcessor::PumpSnapshots() {'))
        self.assertIn('PlayerConVar("rtx_topbr_scope")', source)
        for name in ('AllowScopeMaterials', 'ClearScope', 'GetScope', 'InScope'):
            self.assertIn(f'LUA->SetField(-2, "{name}");', source)
        self.assertNotIn('Restrict(', body(source, 'LUA_FUNCTION(ToPBR_AllowScopeMaterials) {').replace('SyncScope', ''))
        header = text(FOLDER / FILES[2])
        self.assertIn('bool m_restricted = true;', header)
        self.assertNotIn('#include <windows', header.lower())

    def test_the_driver_starts_at_the_maps_own_surfaces(self):
        driver = text(DRIVER)
        self.assertIn('CreateClientConVar("rtx_topbr_scope", "0", true, false,', driver)
        self.assertIn('if after < before then RTXToPBR.ClearCache() end', driver)

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_regression_passes(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='topbr-scope-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(FOLDER / FILES[3]), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS topbr scope:', result.stdout)


if __name__ == '__main__':
    unittest.main()
