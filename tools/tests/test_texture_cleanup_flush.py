"""ADR 0261: the RTX fixes' map-exit cleanup runs the queued render calls first (texture_cleanup_harness.lua), and the
engine guard's Lua surface, QA kinds and log format stay as the hook and the QA driver expect."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[2]
CL_RTX = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ['no-guard', 'no-guard-single', 'no-function', 'no-function-single', 'nothing-queued', 'flushed',
             'refused', 'refused-silent', 'error']


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class CleanupHookTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('texture_cleanup_harness.lua')), str(CL_RTX),
                               scenario], capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_without_the_engine_guard_the_cleanup_runs_only_without_queued_rendering(self):
        self.run_case('no-guard')
        self.run_case('no-function')
        self.run_case('no-guard-single')
        self.run_case('no-function-single')

    def test_the_queued_calls_run_before_the_cleanup(self):
        self.run_case('nothing-queued')
        self.run_case('flushed')

    def test_the_cleanup_is_skipped_when_the_calls_could_not_run(self):
        self.run_case('refused')
        self.run_case('refused-silent')
        self.run_case('error')

    def test_every_scenario_is_run(self):
        for scenario in SCENARIOS:
            self.run_case(scenario)


class SurfaceTests(unittest.TestCase):
    def test_the_hook_calls_the_flush_before_the_cleanup(self):
        text = CL_RTX.read_text(encoding='utf-8')
        start = text.index('hook.Add("ShutDown", "RTXTextureCleanup_MapExit"')
        hook = text[start:text.index('\nend)', start)]
        self.assertLess(hook.index('pcall(guard.RunQueuedRenderCalls)'), hook.index('pcall(RTX_CleanupMapTextures)'))
        self.assertIn('ADR 0261', hook)

    def test_the_module_publishes_the_flush_in_the_client_and_server_realms(self):
        module = (REPO / 'engine_guard/module.cpp').read_text(encoding='utf-8')
        self.assertIn('LUA_FUNCTION_STATIC(RunQueuedRenderCalls)', module)
        for field in ('"queue_flush"', '"target_check"', '"RunQueuedRenderCalls"'):
            self.assertIn(field, module)

    def test_the_qa_driver_counts_the_new_lines(self):
        sys.path.insert(0, str(REPO / 'tools/qa'))
        try:
            import queue_check_session as q
        finally:
            sys.path.pop(0)
        sample = '\n'.join([
            '[NativeLoader] Queued render calls can be run before the RTX fixes\' map-exit cleanup (engine guard, ADR 0261).',
            '[NativeLoader] Queued calls on a material variable that is gone are skipped (engine guard, ADR 0261).',
            '[NativeLoader] Queue flush test: the flush runs nothing and says it succeeded (-nl_queue_check_no_flush).',
            '[NativeLoader] Skipped 3 queued render call(s) on a material variable that was already gone (engine guard, '
            'ADR 0261). Details: garrysmod/data/native-loader/render-queue-check.log',
            '[RTX Texture Cleanup] Ran 12 queued render calls before the purge',
            '[nlqueue] stale: armed with 4 made and 5 disk materials (both)',
            '[nlqueue] stale: queued restores for 9 materials at ShutDown (both)',
        ])
        counts = q.count_lines(sample)
        for key in ('flush_installed', 'target_installed', 'no_flush_armed', 'gone', 'cleanup_flushed', 'stale_armed',
                    'stale_queued'):
            self.assertEqual(counts[key], 1, key)
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
        self.assertEqual(found['log_flushes'], 1)
        self.assertEqual(found['log_runs'], 1)
        self.assertEqual(found['log_run_ends'], 1)
        self.assertEqual(found['log_run_events'], 1)
        self.assertEqual(found['log_gone_events'], 1)
        runs = q.plan_runs(type('A', (), {'repeat': 1, 'kinds': ['stale', 'stale-net']})())
        self.assertEqual([r['name'] for r in runs], ['stale-1', 'stale-net-1'])
        self.assertEqual([r['kind'] for r in runs], ['stale', 'stale-net'])
        self.assertTrue(all(r['stale'] for r in runs))
        self.assertTrue(runs[1]['no_flush'] and not runs[0]['no_flush'])

    def test_the_stale_client_lua_prints_the_two_lines(self):
        lua = (REPO / 'tools/qa/queue_stale_client.lua').read_text(encoding='utf-8')
        self.assertIn('[nlqueue] stale: armed', lua)
        self.assertIn('[nlqueue] stale: queued restores', lua)
        # It wraps the fixes' own hook, re-added under its name, so its setters come right before the cleanup.
        self.assertIn('hook.GetTable().ShutDown', lua)
        self.assertIn('hook.Add("ShutDown", "RTXTextureCleanup_MapExit"', lua)
        self.assertTrue(re.search(r'hook\.Add\("ShutDown", "nlqueue_stale"', lua))


def driver():
    sys.path.insert(0, str(REPO / 'tools/qa'))
    try:
        import queue_check_session as q
    finally:
        sys.path.pop(0)
    return q


class JudgeTests(unittest.TestCase):
    """The driver's verdict per kind (queue_check_session.judge) and its evidence helpers."""

    def record(self, kind, **lines):
        base = {'dropped': 0, 'put_back': 0, 'gone': 0, 'test_dropped': 0, 'test_put_back': 0, 'stale_queued': 0,
                'cleanup_flushed': 0, 'cleanup_skipped': 0}
        base.update(lines)
        return {'kind': kind, 'exit': 0, 'crashed': False, 'normal_quit': True, 'new_dumps': [], 'lines': base,
                'log_gone_events': lines.pop('log_gone_events', 0), 'stale_order': True}

    def test_each_kind_passes_with_what_it_must_show(self):
        q = driver()
        self.assertEqual(q.judge(self.record('plain')), [])
        self.assertEqual(q.judge(self.record('busy')), [])
        self.assertEqual(q.judge(self.record('test', test_dropped=2, test_put_back=2)), [])
        self.assertEqual(q.judge(self.record('stale', stale_queued=1, cleanup_flushed=1)), [])
        net = self.record('stale-net', stale_queued=1, gone=1)
        net['log_gone_events'] = 3
        self.assertEqual(q.judge(net), [])

    def test_each_kind_fails_with_a_reason(self):
        q = driver()
        self.assertTrue(q.judge(self.record('plain', gone=1)))
        self.assertTrue(q.judge(self.record('busy', put_back=1)))
        self.assertTrue(q.judge(self.record('test', test_dropped=1)))
        self.assertTrue(q.judge(self.record('stale', stale_queued=1, cleanup_flushed=1, cleanup_skipped=1)))
        self.assertTrue(q.judge(self.record('stale', stale_queued=1, cleanup_flushed=1, gone=1)))
        self.assertTrue(q.judge(self.record('stale', stale_queued=0, cleanup_flushed=1)))
        self.assertTrue(q.judge(self.record('stale-net', stale_queued=1, gone=1)))  # no log event
        crashed = self.record('plain')
        crashed.update({'exit': 0xC0000409, 'exit_hex': '0xC0000409', 'crashed': True})
        self.assertIn('exit 0xC0000409', q.judge(crashed))
        dump = self.record('plain')
        dump['new_dumps'] = ['a.dmp']
        self.assertTrue(q.judge(dump))
        unordered = self.record('stale', stale_queued=1, cleanup_flushed=1)
        unordered['stale_order'] = False
        self.assertTrue(q.judge(unordered))
        missing = self.record('plain')
        missing['lines'] = None
        self.assertIn('no console.log', q.judge(missing))

    def test_the_stale_order_and_new_dumps(self):
        q = driver()
        self.assertTrue(q.stale_before_cleanup('[RTX Texture Cleanup] Ran 3 queued render calls before the purge\n'
                                               '[nlqueue] stale: queued restores for 29 materials at ShutDown\n'
                                               '[RTX Texture Cleanup] Map-exit renderer purge queued\n'))
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
