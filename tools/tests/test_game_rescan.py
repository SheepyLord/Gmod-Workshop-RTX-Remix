"""ADR 0263: the RTX fixes' seventeenth native patch, game-rescan. A Model Hotloader character imported again in the same
game keeps its asset id when its PMX did not change, so its material names; ToPBR's game maps submitted each name once a
session and the worker kept each model folder's scan and each texture's resolution, so maps put beside the model after
its first import were found only after a restart. ToPBR.RescanGameSource(source, prefix) forgets the character's
submissions and has the worker drop its folder scans and those resolutions, and the driver's MMDHL.Imported hook asks
for it after each import. The folder's complete files are the patch applied, pins.json builds the module with it right
after cleanup-drain, the SDK-free regression passes, the binding is registered and refuses what it does not take, the
worker handles the job before any identity logic, and the driver's hook has its shape (topbr_harness.lua runs it)."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text
from test_queued_draws import added, body

FOLDER = SKINNING / 'game-rescan'
PATCH = FOLDER / 'game-rescan.patch'
PINS = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
TO_PBR = 'source/material_pipeline/to_pbr'
# Each file the patch changes and the folder holding its complete copy before it (the last earlier patch to change it).
CHANGED = {f'{TO_PBR}/to_pbr.cpp': 'lua-guards', f'{TO_PBR}/to_pbr.h': 'topbr-scope'}
NEW = [f'{TO_PBR}/game_rescan.h', 'tests/game_rescan_test.cpp']
SOURCE = FOLDER / f'{TO_PBR}/to_pbr.cpp'
HEADER = FOLDER / f'{TO_PBR}/game_rescan.h'
# The patched native tree (fixes.patched_tree.source) the seventeen patches give; the folder's README names it.
SEVENTEEN = '41dc27fc1717a5e3d7b35197f76a1bfdf999d358'
PREVIOUS = 'packages/fixes/licenses/oversized-skinning/cleanup-drain/cleanup-drain.patch'
DRIVER = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_topbr_conversion.lua'
HOTLOADER = REPO / 'packages/model-hotloader'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 $Source /Fegame_rescan_test.exe /Fogame_rescan_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'game_rescan_test.exe')
exit $LASTEXITCODE
'''


def folders():
    """The patch folders in pins.json's order, each once (autopbr holds two patches)."""
    result = []
    for patch in PINS['patches']:
        folder = (REPO / patch).parent
        if folder not in result:
            result.append(folder)
    return result


def between(source, start, end):
    """The text of `source` from `start` to the next `end` after it."""
    at = source.index(start)
    return source[at:source.index(end, at)]


class GameRescanPatchTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """The patch touches exactly its four files; to_pbr.cpp is lua-guards' copy and to_pbr.h topbr-scope's (no
        folder between changed them) with the patch applied, the header and the regression its added lines (no earlier
        folder holds them); pins.json builds the module with it right after cleanup-drain; the README names it the
        seventeenth native patch and the tree the seventeen give, which pins.json records while it is the last."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), sorted(list(CHANGED) + NEW))
        order = [folder.name for folder in folders()]
        at = order.index(FOLDER.name)
        for path, before in CHANGED.items():
            self.assertEqual(apply(patch, path, text(SKINNING / before / path)), text(FOLDER / path), path)
            later = [name for name in order[order.index(before) + 1:at] if (SKINNING / name / path).exists()]
            self.assertEqual(later, [], path)
        for path in NEW:
            self.assertEqual(added(patch, path), text(FOLDER / path).rstrip('\n').split('\n'), path)
            earlier = [name for name in order[:at] if (SKINNING / name / path).exists()]
            self.assertEqual(earlier, [], path)
        patches = PINS['patches']
        index = patches.index(PATCH.relative_to(REPO).as_posix())
        self.assertEqual(patches[index - 1], PREVIOUS)
        self.assertEqual(len(patches), len(set(patches)))
        self.assertIn('source/*', PINS['patch_paths'])
        readme = text(FOLDER / 'README.md')
        self.assertIn('seventeenth native patch', readme)
        self.assertIn(SEVENTEEN[:8], readme)
        if patches[-1] == patches[index]:
            self.assertEqual(PINS['patched_tree']['source'], SEVENTEEN)

    def test_the_header_needs_no_sdk(self):
        """game_rescan.h is standard C++ only; to_pbr.h includes it, declares RescanGameSource and holds the limit."""
        header = text(HEADER)
        self.assertEqual(re.findall(r'#include <(\w+)>', header),
                         ['chrono', 'cstddef', 'cwctype', 'filesystem', 'set', 'string', 'string_view'])
        self.assertNotIn('#include "', header)
        self.assertIn('static constexpr Clock::duration Interval = std::chrono::seconds(1);', header)
        self.assertIn('constexpr std::size_t MaxSource = 2048;', header)
        declarations = text(FOLDER / f'{TO_PBR}/to_pbr.h')
        self.assertIn('#include "game_rescan.h"', declarations)
        self.assertIn('bool RescanGameSource(const std::string& source, const std::string& prefix);', declarations)
        self.assertIn('GameRescan::Limit m_rescanLimit;', declarations)

    def test_the_binding_is_registered_and_refuses_what_it_does_not_take(self):
        """The Lua function is registered beside ClearCache and takes both strings whole. RescanGameSource refuses
        unless the converter is initialized and the player's game maps are on, the prefix is one character's and the
        source a .pmx on a local drive, before it locks; then a full queue, then the one-a-second limit; it forgets only
        the prefix's submissions, sets their views waiting and queues the job; it opens no file. GameMaterialAction's
        actions stay as they were, so no other Lua function can queue a rescan."""
        source = text(SOURCE)
        self.assertIn('LUA->PushCFunction(ToPBR_ClearCache);\n    LUA->SetField(-2, "ClearCache");\n'
                      '    // A character imported again (the native loader\'s ADR 0263).\n'
                      '    LUA->PushCFunction(ToPBR_RescanGameSource);\n    LUA->SetField(-2, "RescanGameSource");',
                      source)
        binding = body(source, 'LUA_FUNCTION(ToPBR_RescanGameSource) {')
        self.assertIn('for(int i=1;i<=2;++i)LUA->CheckType(i,GarrysMod::Lua::Type::String);', binding)
        self.assertIn('LUA->GetString(1,&sourceSize)', binding)
        self.assertIn('LUA->GetString(2,&prefixSize)', binding)
        self.assertIn('RescanGameSource(\n        std::string(source,sourceSize),std::string(prefix,prefixSize))', binding)
        rescan = body(source, 'bool TextureProcessor::RescanGameSource(const std::string& source, const std::string& prefix) {')
        lock = rescan.index('std::lock_guard<std::mutex> lock(m_queueMutex);')
        for check in ('!m_initialized', '!m_gameEnabled.load()', '!GameRescan::Prefix(prefix)', '!GameRescan::Source(source)',
                      '!LuaPathPolicy::LocalDrivePath(source)'):
            self.assertLess(rescan.index(check), lock, check)
        self.assertLess(lock, rescan.index('m_gameQueue.size() >= 128'))
        self.assertLess(rescan.index('m_gameQueue.size() >= 128'), rescan.index('m_rescanLimit.Take(std::chrono::steady_clock::now())'))
        self.assertLess(rescan.index('m_rescanLimit.Take('), rescan.index('GameRescan::Forget(m_gameSubmitted, prefix);'))
        self.assertIn('GameRescan::Wait(m_gameViews, prefix);', rescan)
        self.assertIn('job.action = "rescan";', rescan)
        self.assertLess(rescan.index('job.action = "rescan";'), rescan.index('m_gameQueue.push(std::move(job));'))
        for opens in ('ifstream', 'filesystem', 'fs::', 'CreateFile', 'GetFileAttributes', 'exists(', 'Normal('):
            self.assertNotIn(opens, rescan, opens)
        queue = body(source, 'bool TextureProcessor::QueueGameMaterial(const std::string& name, const std::string& source, '
                             'const std::string& base,')
        self.assertIn('if(action!="" && action!="options" && action!="automatic" && action!="none" && action!="maps")'
                      'return false;', queue)
        self.assertNotIn('rescan', queue)
        self.assertEqual(source.count('action = "rescan"') + source.count('action="rescan"'), 1)

    def test_the_worker_handles_the_rescan_before_the_identity_logic(self):
        """The rescan job is taken before any live-job or identity work: it drops the folder scans, lets go of the
        identities of the character's live jobs and of the same model's, forgets their views and prints one line. The
        first resolution since then replaces the registered maps or, finding none or failing, takes them back; a manual
        choice still comes first (overrides.Select)."""
        source = text(SOURCE)
        worker = body(source, 'void TextureProcessor::WorkerThreadFunc() {')
        branch = between(worker, 'if (gotGame && gameJob.action=="rescan") {', '        if (gotGame) {')
        self.assertLess(worker.index('if (gotGame && gameJob.action=="rescan") {'), worker.index('liveJobs[gameJob.name]=gameJob;'))
        self.assertLess(branch.index('gotGame=false;'), branch.index('try {'))
        for line in ('discovery=GamePBR::DiscoveryCache();',
                     'const auto identities=GameRescan::Identities(liveJobs,gameJob.name,gameJob.source);',
                     'gameSession.Erase(identity);identityViews.erase(identity);',
                     'if(rescanned.size()<GameRegistry::MaxRecords)rescanned.insert(identity);',
                     '"[MaterialPipeline::ToPBR] Game maps looked at again: %s (%zu textures)\\n"',
                     'GameRescan::FileName(gameJob.source).c_str(),identities.size()',
                     'catch (const std::exception& e)'):
            self.assertIn(line, branch, line)
        self.assertNotIn('m_processedMaterialInfo', branch)
        self.assertNotIn('discovery.Get(', worker)
        retract = between(worker, 'const auto retract=[&](const std::string& identity) {', '    };')
        self.assertIn('i->second.importedGame', retract)
        self.assertIn('if(removed)m_publishRequested.store(true);', retract)
        resolve = worker.index('const auto record = gameSession.ResolveOnce(gameJob.identity, gameJob.hashes,\n'
                               '                    resolving, [&]() {')
        self.assertLess(worker.index('const bool resolving=m_gameEnabled.load() || !gameJob.action.empty();'), resolve)
        after = worker.index('if(resolving && rescanned.erase(gameJob.identity) && !record)retract(gameJob.identity);')
        self.assertLess(resolve, after)
        self.assertLess(after, worker.index('if (record) {'))
        failed = worker[worker.index('} catch (const std::exception& e) {\n                // The panel shows'):]
        self.assertIn('if(rescanned.erase(gameJob.identity))retract(gameJob.identity);', failed)
        self.assertIn('auto selected=overrides.Select(gameJob.identity,gameJob.hashes,true,[&]() {', worker)

    def test_the_driver_rescans_after_an_import(self):
        """cl_rtx_topbr_conversion.lua listens to MMDHL.Imported (the Model Hotloader fires it with the full asset id,
        64 hex digits, after the library is refreshed; material names take its first 16), outside the R12 panel's
        section: it asks RescanGameSource with the library entry's source and the prefix, and only then forgets the
        character's submissions and starts a pass at once. Its behaviour runs in topbr_harness.lua (test_topbr.py)."""
        driver = text(DRIVER)
        hook = between(driver, 'hook.Add("MMDHL.Imported", "RTXToPBR_GameRescan", function(id)', '\nend)\n')
        self.assertLess(driver.index('hook.Add("MMDHL.Imported"'), driver.index('-- BEGIN R12 IMPORTED GAME PBR PANEL'))
        self.assertIn("ADR 0263", driver[driver.index('hook.Add("MMDHL.Imported"') - 1200:driver.index('hook.Add("MMDHL.Imported"')])
        self.assertIn('if not isstring(id) or #id ~= 64 or id:find("[^0-9a-f]") then return end', hook)
        self.assertIn('local prefix = "mmd/" .. id:sub(1, 16) .. "/"', hook)
        self.assertIn('mmdhl.library.entries', hook)
        self.assertNotIn('mmdhl.assets', hook)
        ask = hook.index('pcall(p.RescanGameSource, source, prefix)')
        self.assertLess(ask, hook.index('gameSubmitted[name] = nil'))
        self.assertIn('if not ok or rescanned ~= true then return end', hook)
        self.assertIn('gameAssets, gameNext = nil, 0', hook)
        library = text(HOTLOADER / 'mmd_hotloader/lua/mmdhl/library.lua')
        fired = library.index("hook.Run('MMDHL.Imported',status.asset)")
        self.assertIn('library.Refresh()', library[library.rindex("elseif status.state=='complete' then", 0, fired):fired])
        self.assertIn("local function validId(id) return isstring(id) and #id==64 and not id:find('[^a-f0-9]') end", library)
        naming = text(HOTLOADER / 'source/mmdhl/native/naming.cpp')
        self.assertIn('return "mmd/"+id.substr(0,16)+"/"', naming)


@unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
class GameRescanRegression(unittest.TestCase):
    def test_the_regression_passes(self):
        """game_rescan_test.cpp with /W4 /WX on the header as the patches leave it (every folder's source/ and tests/ in
        pins.json's order, later over earlier)."""
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='game-rescan-', dir=scratch) as folder:
            root = Path(folder)
            tree = root / 'tree'
            for patch_folder in folders():
                for part in ('source', 'tests'):
                    if (patch_folder / part).is_dir():
                        shutil.copytree(patch_folder / part, tree / part, dirs_exist_ok=True)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            done = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                   '-Repo', str(REPO), '-Source', str(tree / 'tests/game_rescan_test.cpp'),
                                   '-Scratch', str(root)], capture_output=True, text=True, timeout=600)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS game rescan:', done.stdout)


if __name__ == '__main__':
    unittest.main()
