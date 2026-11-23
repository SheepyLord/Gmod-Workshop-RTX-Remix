"""ADR 0262: the RTX fixes' sixteenth native patch, cleanup-drain. PerformTextureCleanup (the map-exit hook, the Lua global
RTX_CleanupMapTextures, the console command rtx_flush_textures) has the engine guard run the render calls the main thread
has queued before it uncaches every material, and skips the purge when nobody can make sure. The folder's complete
files are the patch applied, pins.json builds the module with it last, the SDK-free regression passes, the export it
asks for is the engine guard's, the fixes' Lua hook no longer asks the engine guard itself, and the engine guard's Lua
surface and the PoC driver's kinds, counts and verdicts stay as the cleanup's lines and the QA runs need."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text
from test_queued_draws import added

FOLDER = SKINNING / 'cleanup-drain'
PATCH = FOLDER / 'cleanup-drain.patch'
PINS = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
# Each file the patch changes and the folder holding its complete copy before it (the last earlier patch to change it).
CHANGED = {'source/module.cpp': 'lua-guards'}
NEW = ['source/cleanup_drain.h', 'tests/cleanup_drain_test.cpp']
MODULE = FOLDER / 'source/module.cpp'
HEADER = FOLDER / 'source/cleanup_drain.h'
CL_RTX = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua'
ENGINE_GUARD = REPO / 'engine_guard/queue_check.cpp'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 $Source /Fecleanup_drain_test.exe /Focleanup_drain_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'cleanup_drain_test.exe')
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


def function(source, signature):
    """One function of module.cpp, from its signature to its closing brace at the signature's own indentation."""
    start = source.index(signature)
    indent = source[source.rindex('\n', 0, start) + 1:start]
    return source[start:source.index('\n' + indent + '}\n', start)]


def driver():
    sys.path.insert(0, str(REPO / 'tools/qa'))
    try:
        import queue_check_session as q
    finally:
        sys.path.pop(0)
    return q


def parameters(declaration):
    """A C++ parameter list without names: the types, white space normalized."""
    types = []
    for parameter in declaration.split(','):
        words = ' '.join(parameter.split())
        types.append(re.sub(r'\s*\b\w+$', '', words).replace(' *', '*'))
    return types


class CleanupDrainPatchTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """The patch touches exactly its three files; module.cpp is lua-guards' copy (no patch between changed it) with
        the patch applied, the header and the regression its added lines; pins.json builds the module with it last,
        right after lua-guards."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), sorted(list(CHANGED) + NEW))
        order = [folder.name for folder in folders()]
        self.assertEqual(order[-1], FOLDER.name)
        for path, before in CHANGED.items():
            self.assertEqual(apply(patch, path, text(SKINNING / before / path)), text(FOLDER / path), path)
            between = [name for name in order[order.index(before) + 1:-1] if (SKINNING / name / path).exists()]
            self.assertEqual(between, [], path)
        for path in NEW:
            self.assertEqual(added(patch, path), text(FOLDER / path).rstrip('\n').split('\n'), path)
            earlier = [name for name in order[:-1] if (SKINNING / name / path).exists()]
            self.assertEqual(earlier, [], path)
        self.assertEqual(PINS['patches'][-1], PATCH.relative_to(REPO).as_posix())
        self.assertEqual(PINS['patches'][-2], 'packages/fixes/licenses/oversized-skinning/lua-guards/lua-guards.patch')
        self.assertIn('source/*', PINS['patch_paths'])
        readme = text(FOLDER / 'README.md')
        self.assertIn('sixteenth native patch', readme)
        self.assertIn(PINS['patched_tree']['source'][:8], readme)

    def test_the_cleanup_asks_the_drain_first(self):
        """PerformTextureCleanup returns early for a closing module and the map-exit switch, then asks the drain, and
        only then prints Starting cleanup, clears the pipeline's map state and uncaches; a refusal returns false with
        one line; a count line when calls ran."""
        module = text(MODULE)
        cleanup = function(module, 'bool PerformTextureCleanup(const char* reason, bool honorMapExitConvar) {')
        drain = cleanup.index('DrainQueuedRenderCalls()')
        self.assertLess(cleanup.index('if (g_moduleClosing) {'), drain)
        self.assertLess(cleanup.index('rtx_flush_textures_on_map_exit->GetBool()'), drain)
        for later in ('Starting cleanup', 'PrintVramStats();', 'ClearMapState();', 'materials->UncacheAllMaterials();'):
            self.assertLess(drain, cleanup.index(later), later)
        refusal = cleanup[drain:cleanup.index('Starting cleanup')]
        self.assertIn('if (!drain.mayRun) {', refusal)
        self.assertIn('"[RTX Texture Cleanup] Purge skipped: queued render calls could not be run first (%s)\\n"', refusal)
        self.assertLess(refusal.index('Purge skipped'), refusal.index('return false;'))
        self.assertIn('"[RTX Texture Cleanup] Ran %llu queued render calls before the purge\\n"', refusal)
        self.assertIn('if (drain.calls > 0) {', refusal)
        # The Flush(true) call stays, without the comment that said it drained queued material work.
        self.assertIn('materials->Flush(true);', cleanup)
        self.assertNotIn('Drain it before releasing', module)
        self.assertIn('it does not run the calls the main', cleanup)

    def test_every_caller_reaches_the_uncache_only_through_the_cleanup(self):
        module = text(MODULE)
        self.assertEqual(module.count('UncacheAllMaterials('), 1)
        self.assertEqual(module.count('ClearMapState('), 1)
        self.assertEqual(len(re.findall(r'\bPerformTextureCleanup\(', module)), 3)  # the definition and two callers
        command = function(module, 'void FlushTexturesCommand(const CCommand&) {')
        self.assertIn('PerformTextureCleanup("manual console command", false);', command)
        lua = function(module, 'LUA_FUNCTION(CleanupMapTextures_Lua) {')
        self.assertIn('PerformTextureCleanup("client Lua ShutDown", true)', lua)
        self.assertIn('catch (...)', lua)

    def test_the_drain_asks_both_engine_guard_copies_for_the_engine_guards_export(self):
        """The module resolves the export from gmcl_ and gmsv_nlengineguard_win64.dll; its name and its signature are
        the ones engine_guard/queue_check.cpp exports; the header needs no SDK and no Windows header."""
        module = text(MODULE)
        drain = function(module, 'CleanupDrain::Result DrainQueuedRenderCalls() noexcept {')
        self.assertIn('materials && materials->GetThreadMode() == MATERIAL_SINGLE_THREADED', drain)
        self.assertLess(drain.index('L"gmcl_nlengineguard_win64.dll"'), drain.index('L"gmsv_nlengineguard_win64.dll"'))
        self.assertIn('GetModuleHandleW(names[i])', drain)
        self.assertIn('GetProcAddress(module, CleanupDrain::kExport)', drain)
        self.assertIn('CleanupDrain::Decide(singleThreaded, copies, CleanupDrain::kCopies)', drain)
        self.assertIn('catch (...)', drain)
        self.assertIn('#include "cleanup_drain.h"', module)
        header = text(HEADER)
        name = re.search(r'constexpr const char\* kExport = "(\w+)";', header)[1]
        ours = re.search(r'using QueueFlush = int \(\*\)\(([^)]*)\);', header)[1]
        guard = text(ENGINE_GUARD)
        exports = {m[0]: m[1] for m in re.findall(r'extern "C" __declspec\(dllexport\) int (\w+)\(([^)]*)\) noexcept',
                                                  ' '.join(guard.split()))}
        self.assertIn(name, exports)
        self.assertEqual(name, 'nl_engine_guard_queue_flush_v1')
        self.assertEqual(parameters(ours), parameters(exports[name]))
        self.assertEqual(parameters(ours), ['std::uint64_t*', 'char*', 'std::size_t'])
        self.assertNotIn('#include <windows', header.lower())
        self.assertEqual(re.findall(r'#include <(\w+)>', header), ['cstddef', 'cstdint', 'cstring'])
        # The contract is named on the engine guard's side too.
        self.assertIn('ADR 0262', guard[guard.index('int nl_engine_guard_queue_flush_v1') - 800:
                                       guard.index('int nl_engine_guard_queue_flush_v1')])

    def test_the_lua_hook_calls_the_cleanup_alone(self):
        source = text(CL_RTX)
        start = source.index('hook.Add("ShutDown", "RTXTextureCleanup_MapExit"')
        hook = source[start:source.index('\nend)', start)]
        self.assertIn('if not RTX_CleanupMapTextures then', hook)
        self.assertIn('local ok, queued = pcall(RTX_CleanupMapTextures)', hook)
        self.assertIn('ADR 0262', hook)
        for gone in ('nlengineguard', 'RunQueuedRenderCalls', 'mat_queue_mode', 'purge skipped'):
            self.assertNotIn(gone, hook)


@unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
class CleanupDrainRegression(unittest.TestCase):
    def test_the_regression_passes(self):
        """cleanup_drain_test.cpp with /W4 /WX on the header as the sixteen patches leave it (every folder's source/ and
        tests/ in pins.json's order, later over earlier)."""
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='cleanup-drain-', dir=scratch) as folder:
            root = Path(folder)
            tree = root / 'tree'
            for patch_folder in folders():
                for part in ('source', 'tests'):
                    if (patch_folder / part).is_dir():
                        shutil.copytree(patch_folder / part, tree / part, dirs_exist_ok=True)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            done = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                   '-Repo', str(REPO), '-Source', str(tree / 'tests/cleanup_drain_test.cpp'),
                                   '-Scratch', str(root)], capture_output=True, text=True, timeout=600)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS cleanup drain:', done.stdout)


class SurfaceTests(unittest.TestCase):
    """What ADR 0261 put around the cleanup and stays: the engine guard's Lua fields, the QA driver's lines, log counts
    and plans, the stale client's lines; and ADR 0262's midgame kinds."""

    def test_the_engine_guard_publishes_the_flush_in_the_client_and_server_realms(self):
        module = (REPO / 'engine_guard/module.cpp').read_text(encoding='utf-8')
        self.assertIn('LUA_FUNCTION_STATIC(RunQueuedRenderCalls)', module)
        for field in ('"queue_flush"', '"target_check"', '"RunQueuedRenderCalls"'):
            self.assertIn(field, module)

    def test_the_qa_driver_counts_the_lines(self):
        q = driver()
        sample = '\n'.join([
            '[NativeLoader] Queued render calls can be run before the RTX fixes\' map-exit cleanup (engine guard, ADR 0261).',
            '[NativeLoader] Queued calls on a material variable that is gone are skipped (engine guard, ADR 0261).',
            '[NativeLoader] Queue flush test: the flush runs nothing and says it succeeded (-nl_queue_check_no_flush).',
            '[NativeLoader] Skipped 3 queued render call(s) on a material variable that was already gone (engine guard, '
            'ADR 0261). Details: garrysmod/data/native-loader/render-queue-check.log',
            '[RTX Texture Cleanup] Ran 12 queued render calls before the purge',
            '[RTX Texture Cleanup] Purge skipped: queued render calls could not be run first (not on the main thread)',
            '[RTX Texture Cleanup] Starting cleanup (manual console command)',
            '[RTX Texture Cleanup] Source material cache fully uncached',
            '[nlqueue] stale: armed with 4 made and 5 disk materials (both)',
            '[nlqueue] stale: queued restores for 9 materials at ShutDown (both)',
            '[nlqueue] midgame: armed (lua) with 5 disk materials',
            '[nlqueue] midgame: queued setters for 5 file-based materials (10 calls)',
            '[nlqueue] midgame: RTX_CleanupMapTextures returned true true',
            'nlqueue midgame console sent',
        ])
        counts = q.count_lines(sample)
        for key in ('flush_installed', 'target_installed', 'no_flush_armed', 'gone', 'cleanup_flushed', 'cleanup_skipped',
                    'cleanup_started', 'cleanup_uncached', 'stale_armed', 'stale_queued', 'midgame_armed',
                    'midgame_queued', 'midgame_returned', 'midgame_sent'):
            self.assertEqual(counts[key], 1, key)
        # The module's refusal line, not ADR 0261's hook line.
        self.assertEqual(q.count_lines('[RTX Texture Cleanup] Map-exit purge skipped: x')['cleanup_skipped'], 0)
        log = '\n'.join([
            '2026-11-23T10:00:00Z flush 1: list 0 held 40 calls; watched; ran 40 queued render call(s) through the '
            "queued context's flush",
            '2026-11-23T10:00:01Z check 1 while the game ran the queued calls (each event as it happened):',
            '  list 1, call 12 of 40 (element +0x2938): its call\'s material variable is gone (destroyed while the call '
            'waited): skipped',
            '2026-11-23T10:00:01Z check 1 run ended: 39 calls run, 0 put back, 1 skipped (1 on a material variable that '
            'was gone), 0 lists ended early',
        ])
        found = q.count_log(log)
        for key in ('log_flushes', 'log_runs', 'log_run_ends', 'log_run_events', 'log_gone_events'):
            self.assertEqual(found[key], 1, key)

    def test_the_qa_driver_plans_each_kind(self):
        q = driver()
        kinds = ['stale', 'stale-net', 'midgame', 'midgame-console']
        runs = q.plan_runs(type('A', (), {'repeat': 1, 'kinds': kinds})())
        self.assertEqual([r['name'] for r in runs], ['stale-1', 'stale-net-1', 'midgame-1', 'midgame-console-1'])
        self.assertEqual([r['kind'] for r in runs], kinds)
        self.assertEqual([r['stale'] for r in runs], [True, True, False, False])
        self.assertEqual([r['no_flush'] for r in runs], [False, True, False, False])
        self.assertEqual([r['midgame'] for r in runs], [None, None, 'lua', 'console'])
        self.assertEqual(set(q.KINDS), {'test', 'plain', 'busy', 'stale', 'stale-net', 'midgame', 'midgame-console'})
        args = type('A', (), {'busy_seconds': 240, 'settle': 20, 'map': 'gm_construct', 'then_map': 'gm_flatgrass',
                              'width': 1600, 'height': 900, 'timeout': 900, 'hang_grace': 180})()
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            evidence = Path(folder)
            lua_run = q.run_arguments(runs[2], evidence, args)
            console_run = q.run_arguments(runs[3], evidence, args)
            self.assertEqual(lua_run[lua_run.index('--lua') + 1], str(evidence / 'midgame-1-client.lua'))
            self.assertTrue((evidence / 'midgame-1-client.lua').read_text(encoding='utf-8')
                            .startswith('NLQ_MODE = "lua"\n'))
            self.assertTrue((evidence / 'midgame-console-1-client.lua').read_text(encoding='utf-8')
                            .startswith('NLQ_MODE = "console"\n'))
            self.assertNotIn('nlqueue_touch;rtx_flush_textures', lua_run)
            final = [console_run[i + 1] for i, word in enumerate(console_run) if word == '--before-quit-console']
            self.assertEqual(final, ['nlqueue_touch;rtx_flush_textures', 'echo nlqueue midgame console sent', 'disconnect'])
            stale = q.run_arguments(runs[1], evidence, args)
            self.assertIn('--extra=-nl_queue_check_no_flush', stale)
            self.assertEqual(stale[stale.index('--lua') + 1], str(q.STALE_SOURCE))

    def test_the_client_lua_prints_its_lines(self):
        stale = (REPO / 'tools/qa/queue_stale_client.lua').read_text(encoding='utf-8')
        self.assertIn('[nlqueue] stale: armed', stale)
        self.assertIn('[nlqueue] stale: queued restores', stale)
        # It wraps the fixes' own hook, re-added under its name, so its setters come right before the cleanup.
        self.assertIn('hook.GetTable().ShutDown', stale)
        self.assertIn('hook.Add("ShutDown", "RTXTextureCleanup_MapExit"', stale)
        self.assertTrue(re.search(r'hook\.Add\("ShutDown", "nlqueue_stale"', stale))
        midgame = (REPO / 'tools/qa/queue_midgame_client.lua').read_text(encoding='utf-8')
        for line in ('[nlqueue] midgame: armed', '[nlqueue] midgame: queued setters',
                     '[nlqueue] midgame: RTX_CleanupMapTextures returned'):
            self.assertIn(line, midgame)
        # The setters line ends with the number of setter calls made, in the form the driver reads, and the stale
        # client's with its materials.
        q = driver()
        self.assertIn('" file-based materials (" .. calls .. " calls)"', midgame)
        self.assertEqual(q.MIDGAME_SETTERS.match('[nlqueue] midgame: queued setters for 5 file-based materials (10 calls)')[1],
                         '10')
        self.assertEqual(midgame.count('calls = calls + 1'), 2)  # one for each setter call
        self.assertIn('print("[nlqueue] stale: queued restores for " .. count .. " materials at ShutDown")', stale)
        self.assertEqual(q.STALE_QUEUED.search('[nlqueue] stale: queued restores for 29 materials at ShutDown')[1], '29')
        self.assertIn('m:SetTexture("$basetexture", other)', stale)  # two queued calls for each material
        self.assertEqual(q.STALE_CALLS_EACH, 2)
        self.assertIn('concommand.Add("nlqueue_touch", touch)', midgame)
        self.assertIn('local mode = NLQ_MODE or "lua"', midgame)
        timer = midgame[midgame.index('if mode == "lua" then'):]
        self.assertLess(timer.index('touch()'), timer.index('pcall(RTX_CleanupMapTextures)'))
        # The console command is defined in both modes, before the mode is read.
        self.assertLess(midgame.index('concommand.Add'), midgame.index('local mode'))


class JudgeTests(unittest.TestCase):
    """The driver's verdict per kind (queue_check_session.judge) and its evidence helpers."""

    def record(self, kind, **lines):
        base = {'dropped': 0, 'put_back': 0, 'gone': 0, 'test_dropped': 0, 'test_put_back': 0, 'stale_queued': 0,
                'cleanup_flushed': 0, 'cleanup_skipped': 0, 'midgame_queued': 0, 'midgame_returned': 0,
                'midgame_sent': 0}
        # What the driver keeps beside the line counts (the log's counts, stale_after's and midgame_after's results).
        beside = ('log_', 'midgame_ran', 'midgame_unc', 'midgame_setter', 'midgame_first', 'stale_materials',
                  'stale_ran', 'stale_unc', 'stale_first')
        extra = {key: lines.pop(key) for key in list(lines) if key.startswith(beside)}
        base.update(lines)
        record = {'kind': kind, 'exit': 0, 'crashed': False, 'normal_quit': True, 'new_dumps': [], 'lines': base,
                  'log_gone_events': 0, 'stale_order': True}
        record.update(extra)
        return record

    def stale(self, **lines):
        good = {'stale_queued': 1, 'cleanup_flushed': 2, 'stale_materials': 29, 'stale_ran_after': 1,
                'stale_uncached_after': 1, 'stale_first_ran_calls': 220, 'stale_ran_then_uncached': True}
        good.update(lines)
        return self.record('stale', **good)

    def stale_net(self, **lines):
        good = {'stale_queued': 1, 'gone': 1, 'log_gone_events': 3, 'stale_materials': 29, 'stale_ran_after': 0,
                'stale_uncached_after': 1, 'stale_first_ran_calls': 0, 'stale_ran_then_uncached': False}
        good.update(lines)
        return self.record('stale-net', **good)

    def midgame(self, kind, **lines):
        good = {'midgame_queued': 1, 'midgame_ran_after': 2, 'midgame_uncached_after': 2, 'midgame_ran_before_end': 1,
                'midgame_uncached_before_end': 1, 'midgame_setter_calls': 10, 'midgame_first_ran_calls': 27,
                'midgame_ran_then_uncached': True}
        good['midgame_returned' if kind == 'midgame' else 'midgame_sent'] = 1
        good.update(lines)
        return self.record(kind, **good)

    def test_each_kind_passes_with_what_it_must_show(self):
        q = driver()
        self.assertEqual(q.judge(self.record('plain')), [])
        self.assertEqual(q.judge(self.record('busy')), [])
        self.assertEqual(q.judge(self.record('test', test_dropped=2, test_put_back=2)), [])
        self.assertEqual(q.judge(self.stale()), [])
        self.assertEqual(q.judge(self.stale(stale_first_ran_calls=58)), [])  # two calls for each of 29 materials
        self.assertEqual(q.judge(self.stale_net()), [])
        self.assertEqual(q.judge(self.midgame('midgame')), [])
        self.assertEqual(q.judge(self.midgame('midgame-console')), [])
        self.assertEqual(q.judge(self.midgame('midgame', midgame_first_ran_calls=10)), [])  # just the setters' calls

    def test_each_kind_fails_with_a_reason(self):
        q = driver()
        self.assertTrue(q.judge(self.record('plain', gone=1)))
        self.assertTrue(q.judge(self.record('busy', put_back=1)))
        self.assertTrue(q.judge(self.record('test', test_dropped=1)))
        for broken in ({'cleanup_skipped': 1}, {'gone': 1}, {'stale_queued': 0}, {'cleanup_flushed': 0},
                       {'stale_materials': 0}, {'stale_ran_after': 0}, {'stale_uncached_after': 0},
                       # Fewer calls than the restores queued: the "Ran" line is some other cleanup's.
                       {'stale_first_ran_calls': 57}, {'stale_first_ran_calls': 0},
                       {'stale_ran_then_uncached': False}):
            self.assertTrue(q.judge(self.stale(**broken)), broken)
        # A "Ran" line somewhere in the console (the level change's) is not enough for the stale run.
        self.assertTrue(q.judge(self.record('stale', stale_queued=1, cleanup_flushed=1)))
        for broken in ({'log_gone_events': 0}, {'gone': 0}, {'stale_queued': 0}, {'stale_uncached_after': 0}):
            self.assertTrue(q.judge(self.stale_net(**broken)), broken)
        for kind in ('midgame', 'midgame-console'):
            for broken in ({'midgame_queued': 0}, {'midgame_ran_after': 0}, {'midgame_uncached_after': 0},
                           {'midgame_ran_before_end': 0}, {'midgame_uncached_before_end': 0}, {'cleanup_skipped': 1},
                           {'gone': 1}, {'dropped': 1}, {'put_back': 1}, {'midgame_setter_calls': 0},
                           # Fewer calls than the setters made: they were not among the calls the cleanup ran.
                           {'midgame_first_ran_calls': 9}, {'midgame_first_ran_calls': 0},
                           {'midgame_ran_then_uncached': False}):
                self.assertTrue(q.judge(self.midgame(kind, **broken)), (kind, broken))
        self.assertTrue(q.judge(self.midgame('midgame', midgame_returned=0)))
        self.assertTrue(q.judge(self.midgame('midgame-console', midgame_sent=0)))
        crashed = self.midgame('midgame')
        crashed.update({'exit': 0xC0000005, 'exit_hex': '0xC0000005', 'crashed': True})
        self.assertIn('exit 0xC0000005', q.judge(crashed))
        dump = self.record('plain')
        dump['new_dumps'] = ['a.dmp']
        self.assertTrue(q.judge(dump))
        unordered = self.record('stale', stale_queued=1, cleanup_flushed=1)
        unordered['stale_order'] = False
        self.assertTrue(q.judge(unordered))
        missing = self.record('plain')
        missing['lines'] = None
        self.assertIn('no console.log', q.judge(missing))

    def test_the_midgame_lines_after_the_setters(self):
        q = driver()
        console = '\n'.join([
            '[RTX Texture Cleanup] Source material cache fully uncached',  # an earlier cleanup: not counted
            '[nlqueue] midgame: armed (lua) with 5 disk materials',
            '[nlqueue] midgame: queued setters for 5 file-based materials (10 calls)',
            '[RTX Texture Cleanup] Ran 14 queued render calls before the purge',
            '[RTX Texture Cleanup] Starting cleanup (client Lua ShutDown)',
            '[RTX Texture Cleanup] Source material cache fully uncached',
            '[nlqueue] midgame: RTX_CleanupMapTextures returned true true',
            '[RTX Texture Cleanup] Ran 220 queued render calls before the purge',
            '[RTX Texture Cleanup] Source material cache fully uncached',
        ])
        self.assertEqual(q.midgame_after(console, 'midgame'),
                         {'midgame_ran_after': 2, 'midgame_uncached_after': 2, 'midgame_ran_before_end': 1,
                          'midgame_uncached_before_end': 1, 'midgame_setter_calls': 10, 'midgame_first_ran_calls': 14,
                          'midgame_ran_then_uncached': True})
        # Only the disconnect's cleanup after the setters: nothing before the end line.
        late = console.replace('[RTX Texture Cleanup] Ran 14 queued render calls before the purge\n', '').replace(
            '[RTX Texture Cleanup] Starting cleanup (client Lua ShutDown)\n[RTX Texture Cleanup] Source material cache '
            'fully uncached\n', '')
        found = q.midgame_after(late, 'midgame')
        self.assertEqual(found['midgame_ran_before_end'], 0)
        self.assertEqual(found['midgame_ran_after'], 1)
        self.assertEqual(found['midgame_first_ran_calls'], 0)  # the disconnect's 220 is not the mid-game cleanup's
        self.assertFalse(found['midgame_ran_then_uncached'])
        # The uncache with no "Ran" line before it (nothing was run first), the "Ran" line only after it.
        unsafe = console.replace('[RTX Texture Cleanup] Ran 14 queued render calls before the purge\n', '').replace(
            '[nlqueue] midgame: RTX_CleanupMapTextures returned true true',
            '[RTX Texture Cleanup] Ran 14 queued render calls before the purge\n'
            '[nlqueue] midgame: RTX_CleanupMapTextures returned true true')
        found = q.midgame_after(unsafe, 'midgame')
        self.assertEqual((found['midgame_ran_before_end'], found['midgame_uncached_before_end']), (1, 1))
        self.assertFalse(found['midgame_ran_then_uncached'])
        # A client without the count (an older line): no setter calls known, which the verdict refuses.
        old = console.replace(' (10 calls)', '')
        self.assertEqual(q.midgame_after(old, 'midgame')['midgame_setter_calls'], 0)
        sent = console.replace('[nlqueue] midgame: RTX_CleanupMapTextures returned true true', 'nlqueue midgame console sent')
        found = q.midgame_after(sent, 'midgame-console')
        self.assertEqual(found['midgame_uncached_before_end'], 1)
        self.assertTrue(found['midgame_ran_then_uncached'])
        self.assertEqual(q.midgame_after('', 'midgame'),
                         {'midgame_ran_after': 0, 'midgame_uncached_after': 0, 'midgame_ran_before_end': 0,
                          'midgame_uncached_before_end': 0, 'midgame_setter_calls': 0, 'midgame_first_ran_calls': 0,
                          'midgame_ran_then_uncached': False})

    def test_the_stale_lines_after_the_restores(self):
        q = driver()
        console = '\n'.join([
            # The level change's cleanup, before the stale Lua is sent: not counted.
            '[RTX Texture Cleanup] Ran 234 queued render calls before the purge',
            '[RTX Texture Cleanup] Source material cache fully uncached',
            '[nlqueue] stale: armed with 24 made and 5 disk materials, right before the RTX fixes\' cleanup hook',
            '[nlqueue] stale: queued restores for 29 materials at ShutDown',
            '[RTX Texture Cleanup] Ran 310 queued render calls before the purge',
            '[RTX Texture Cleanup] Starting cleanup (client Lua ShutDown)',
            '[RTX Texture Cleanup] Source material cache fully uncached',
        ])
        self.assertEqual(q.stale_after(console),
                         {'stale_materials': 29, 'stale_ran_after': 1, 'stale_uncached_after': 1,
                          'stale_first_ran_calls': 310, 'stale_ran_then_uncached': True})
        # -nl_queue_check_no_flush: the cleanup uncaches and prints no "Ran" line.
        net = console.replace('[RTX Texture Cleanup] Ran 310 queued render calls before the purge\n', '')
        self.assertEqual(q.stale_after(net),
                         {'stale_materials': 29, 'stale_ran_after': 0, 'stale_uncached_after': 1,
                          'stale_first_ran_calls': 0, 'stale_ran_then_uncached': False})
        # A refused cleanup: neither line after the restores.
        refused = console[:console.index('[RTX Texture Cleanup] Ran 310')] + (
            '[RTX Texture Cleanup] Purge skipped: queued render calls could not be run first (not available)')
        self.assertEqual(q.stale_after(refused)['stale_uncached_after'], 0)
        self.assertEqual(q.stale_after(''), {'stale_materials': 0, 'stale_ran_after': 0, 'stale_uncached_after': 0,
                                             'stale_first_ran_calls': 0, 'stale_ran_then_uncached': False})
        self.assertEqual(q.cleanup_in(''), {'ran': 0, 'uncached': 0, 'first_calls': 0, 'ordered': False})

    def test_the_stale_order_and_new_dumps(self):
        q = driver()
        self.assertTrue(q.stale_before_cleanup('[RTX Texture Cleanup] Ran 3 queued render calls before the purge\n'
                                               '[nlqueue] stale: queued restores for 29 materials at ShutDown\n'
                                               '[RTX Texture Cleanup] Ran 4 queued render calls before the purge\n'))
        self.assertFalse(q.stale_before_cleanup('[RTX Texture Cleanup] Ran 3 queued render calls before the purge\n'
                                                '[nlqueue] stale: queued restores for 29 materials at ShutDown\n'))
        self.assertFalse(q.stale_before_cleanup(''))
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            root = Path(folder)
            (root / 'crashes').mkdir()
            old = root / 'crashes/old.dmp'
            old.write_bytes(b'x')
            past = time.time() - 3600
            os.utime(old, (past, past))
            started = time.time()
            (root / 'crashes/new.dmp').write_bytes(b'x')
            (root / 'crashes/notes.txt').write_bytes(b'x')
            self.assertEqual(q.new_dumps(root, started), ['new.dmp'])
            self.assertEqual(q.new_dumps(root / 'none', started), [])


if __name__ == '__main__':
    unittest.main()
