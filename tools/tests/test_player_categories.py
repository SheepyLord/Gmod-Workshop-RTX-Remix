"""Automatic categorization (ADR 0213): the fixes' twelfth patch's complete files are the patch applied, its SDK-free
regression (player_categories_test.cpp) passes, every automatic write path asks the player's rtx.conf, and the
packaged category manager (cl_remix_category_0_manager.lua) passes its harness."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text
from test_queued_draws import added, blocks, body

FOLDER = SKINNING / 'player-categories'
PATCH = FOLDER / 'player-categories.patch'
AUTO = 'source/material_pipeline/auto_categorisation'
TRACKER = 'source/d3d9_texture_tracker.cpp'
FILES = [TRACKER, f'{AUTO}/auto_categorisation.cpp', f'{AUTO}/player_categories.h',
         'source/remixapi/material_lua_bindings.cpp', 'tests/player_categories_test.cpp']
MANAGER = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_category_0_manager.lua'
LUA = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 $Source /Feplayer_categories_test.exe /Foplayer_categories_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'player_categories_test.exe') (Join-Path $Scratch 'fixture')
exit $LASTEXITCODE
'''


class PlayerCategoriesTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """auto_categorisation.cpp and material_lua_bindings.cpp are autopbr's copies (lua-paths changed them last)
        with this patch applied; the tracker (no earlier copy: the base's) has the patch's new side at every hunk;
        the two new files are its added lines. pins.json builds the module with it, last."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), FILES)
        for path in (FILES[1], FILES[3]):
            self.assertEqual(apply(patch, path, text(SKINNING / 'autopbr' / path)), text(FOLDER / path), path)
        tracker = text(FOLDER / TRACKER).split('\n')
        for start, _, new in blocks(patch, TRACKER):
            self.assertEqual(tracker[start:start + len(new)], new, f'{TRACKER} at line {start + 1}')
        for path in (FILES[2], FILES[4]):
            self.assertEqual(added(patch, path), text(FOLDER / path).rstrip('\n').split('\n'), path)
        pins = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
        self.assertEqual(pins['patches'][-1], PATCH.relative_to(REPO).as_posix())

    def test_every_automatic_add_asks_the_players_rtx_conf(self):
        """The two native paths that add categories filter their bits first; the Lua binding does when its third
        argument says the call is automatic; the policy reads rtx.conf in the game folder, not user.conf."""
        auto = text(FOLDER / FILES[1])
        apply_to_hash = body(auto, 'void ApplyToHash(uint64_t hash, uint32_t flags, const std::string& materialName) {')
        self.assertLess(apply_to_hash.index('PlayerCategories::File::Instance().Allowed(hash, flags)'),
                        apply_to_hash.index('AddTextureHash'))
        self.assertIn("player.SetPath(root / L\"rtx.conf\")", auto)
        tracker = text(FOLDER / TRACKER)
        category = body(tracker, 'void D3D9TextureTracker::ApplyCategoryToHash(uint64_t hash, uint32_t categoryFlags, const char* materialName) {')
        self.assertLess(category.index('PlayerCategories::File::Instance().Allowed(hash, categoryFlags)'),
                        category.index('AddTextureHash'))
        binding = text(FOLDER / FILES[3])
        set_category = body(binding, 'LUA_FUNCTION(RemixMaterial_SetHashCategory) {')
        self.assertIn('LUA->IsType(3, Type::Bool) && LUA->GetBool(3)', set_category)
        self.assertLess(set_category.index('Allowed('), set_category.index('AddTextureHash'))
        policy = text(FOLDER / FILES[2])
        self.assertNotIn('user.conf"', policy)

    def test_the_lua_marks_its_automatic_writes(self):
        """Every automatic path of the category manager passes automatic = true; manual commands do not."""
        manager = text(MANAGER)
        self.assertIn('return RemixMaterial.SetHashCategory(textureHash, categoryFlags, automatic == true)', manager)
        self.assertIn('RemixCategoryManager.SetHashCategory(hashStr, mergedFlags, pending.automatic)', manager)
        self.assertEqual(manager.count('SetMaterialCategory(materialName, category, forceAlbedoCallback, true)'), 2)
        self.assertEqual(manager.count('matName, category, forceAlbedoCallback, true)'), 2)
        self.assertIn('RemixCategoryManager.SetMaterialCategory(materialName, categoryFlags)\n', manager)

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_policy_regression_passes(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='player-categories-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(FOLDER / FILES[4]), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS player categories:', result.stdout)

    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT unavailable')
    def test_the_category_manager(self):
        result = subprocess.run([LUA, str(REPO / 'tools/tests/category_manager_harness.lua'), str(MANAGER)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS category manager:', result.stdout)


if __name__ == '__main__':
    unittest.main()
