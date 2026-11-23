"""queue_check_session.py: RTX sessions on the PoC for the engine guard's queue check (ADR 0247), run check (ADR 0254)
and queue flush and target check (ADR 0261). A test session launched with -nl_queue_check_test, where every check
first queues one call whose object is gone and a pair whose first call writes over the second's element while the game
runs them, so the level change and the disconnect go through the drop path and the put-back path in the real game; a
plain session that changes level and disconnects with nothing to drop or put back; a busy session that crowds the first
map (queue_busy_server.lua) before the level change and the disconnect; and the stale sessions (queue_stale_client.lua:
material variables set at ShutDown, right before the RTX fixes' map-exit cleanup uncaches every material, at the final
disconnect): stale, where the fixes' cleanup runs the queued calls first through the engine guard's flush, and
stale-net, launched with -nl_queue_check_no_flush, where the run check must skip the calls on variables that are gone;
and the midgame sessions (ADR 0262, queue_midgame_client.lua: file-based materials' variables set, then the fixes'
cleanup in the same frame, in the middle of a game): midgame through the Lua global RTX_CleanupMapTextures,
midgame-console through the console command rtx_flush_textures in one console line with the setters. Holds
out/r10/poc.lock, snapshots the PoC with the VR driver's helpers, keeps each run's new crash dumps and loader session
logs, restores the PoC at the end, judges each run against what its kind must show and exits 1 when one fails. See
queue_check_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import json
import re
import shutil
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import poc_session as poc  # noqa: E402
import vr_session as vs  # noqa: E402

# The engine guard's console lines (engine_guard/queue_check.cpp), counted per run.
LINES = {
    'installed': r'\[NativeLoader\] Queued render calls are checked before the game leaves threaded rendering',
    'run_installed': r'\[NativeLoader\] Queued render calls are also checked while the game runs them',
    'run_off': r'\[NativeLoader\] The run check is off',
    'test_armed': r'\[NativeLoader\] Queue check test: each check first queues one call whose object is gone',
    'test_pair_armed': r'\[NativeLoader\] Queue check test: each check also queues a pair of calls',
    'test_dropped': r'\[NativeLoader\] Queue check test: the test call was dropped',
    'test_put_back': r'\[NativeLoader\] Queue check test: the run check put back the test call',
    'dropped': r'\[NativeLoader\] Dropped \d+ queued render call',
    'put_back': r'\[NativeLoader\] Put back \d+ and skipped \d+ queued render call',
    'not_walked': r'\[NativeLoader\] The queue check could not walk a render call list',
    'stopped': r'\[NativeLoader\] The queue check stopped on a fault',
    'busy_started': r'\[nlqueue\] busy: started',
    'busy_report': r'\[nlqueue\] busy: \d+ props',
    # ADR 0261: the queue flush, the target check and the stale runs.
    'flush_installed': r'\[NativeLoader\] Queued render calls can be run before the RTX fixes\' map-exit cleanup',
    'flush_off': r'\[NativeLoader\] The queue flush is off',
    'target_installed': r'\[NativeLoader\] Queued calls on a material variable that is gone are skipped',
    'target_off': r'\[NativeLoader\] The target check is off',
    'no_flush_armed': r'\[NativeLoader\] Queue flush test: the flush runs nothing',
    'gone': r'\[NativeLoader\] Skipped \d+ queued render call\(s\) on a material variable that was already gone',
    # The RTX fixes' cleanup (its native module since ADR 0262).
    'cleanup_flushed': r'\[RTX Texture Cleanup\] Ran \d+ queued render calls before the purge',
    'cleanup_skipped': r'\[RTX Texture Cleanup\] Purge skipped: queued render calls could not be run first',
    'cleanup_started': r'\[RTX Texture Cleanup\] Starting cleanup',
    'cleanup_uncached': r'\[RTX Texture Cleanup\] Source material cache fully uncached',
    'stale_armed': r'\[nlqueue\] stale: armed',
    'stale_queued': r'\[nlqueue\] stale: queued restores',
    # ADR 0262: the midgame runs (queue_midgame_client.lua and the console line the driver sends).
    'midgame_armed': r'\[nlqueue\] midgame: armed',
    'midgame_queued': r'\[nlqueue\] midgame: queued setters',
    'midgame_returned': r'\[nlqueue\] midgame: RTX_CleanupMapTextures returned',
    'midgame_sent': r'nlqueue midgame console sent',
}
# The midgame runs' console line: the setters and the cleanup in one pass of the command buffer, then a marker; both
# sent before the run's own disconnect.
MIDGAME_CONSOLE = ['nlqueue_touch;rtx_flush_textures', 'echo nlqueue midgame console sent']
MIDGAME_QUEUED = '[nlqueue] midgame: queued setters'
MIDGAME_END = {'midgame': '[nlqueue] midgame: RTX_CleanupMapTextures returned', 'midgame-console': 'nlqueue midgame console sent'}
# What ties a cleanup to the setters queued right before it: the cleanup's count of the calls it had run first, its
# uncache line, and the number of setter calls or materials each client prints.
RAN = re.compile(r'\[RTX Texture Cleanup\] Ran (\d+) queued render calls before the purge')
UNCACHED = '[RTX Texture Cleanup] Source material cache fully uncached'
MIDGAME_SETTERS = re.compile(r'\[nlqueue\] midgame: queued setters for \d+ file-based materials \((\d+) calls\)')
STALE_QUEUED = re.compile(r'\[nlqueue\] stale: queued restores for (\d+) materials')
# queue_stale_client.lua sets a texture on every material: the setter and its texture's release, two queued calls.
STALE_CALLS_EACH = 2
# The log's lines (engine_guard/queue_check.cpp), counted per run: the walks before a run, the watched runs that wrote
# events (a header at the first, each event as it happened, a summary at the end), the flushes.
LOG_LINES = {
    'log_checks': r'(?m)^\S+ (?:check|flush) \d+ before',
    'log_runs': r'(?m)^\S+ (?:check|flush) \d+ while the game ran',
    'log_run_ends': r'(?m)^\S+ (?:check|flush) \d+ run ended',
    'log_run_events': r'(?m)^  (?:list \d+|an element outside).*: .*(?:put back|skipped|ends here)',
    'log_gone_events': r'(?m)^  .*: its call\'s material variable is gone',
    'log_test_events': r'(?m)\(the test call\)$',
    'log_flushes': r'(?m)^\S+ flush \d+: list \d+ held \d+ calls',
}
LOG = Path('garrysmod/data/native-loader/render-queue-check.log')
BUSY_SOURCE = Path(__file__).resolve().with_name('queue_busy_server.lua')
BUSY_DATA = Path('garrysmod/data/nlqueue/busy.txt')
BUSY_RUN = 'lua_run RunString(file.Read("nlqueue/busy.txt","DATA"),"nlqueue_busy")'
STALE_SOURCE = Path(__file__).resolve().with_name('queue_stale_client.lua')
MIDGAME_SOURCE = Path(__file__).resolve().with_name('queue_midgame_client.lua')
# What the restore removes and a crash leaves: copied into each run's evidence first.
KEEP = ('crashes', 'native-loader/logs/sessions')
KINDS = ('test', 'plain', 'busy', 'stale', 'stale-net', 'midgame', 'midgame-console')
MIDGAME_MODES = {'midgame': 'lua', 'midgame-console': 'console'}


def plan_runs(args) -> list[dict]:
    runs = []
    for n in range(1, args.repeat + 1):
        for kind in args.kinds:
            runs.append({'name': f'{kind}-{n}', 'kind': kind, 'test': kind == 'test', 'busy': kind == 'busy',
                         'stale': kind in ('stale', 'stale-net'), 'no_flush': kind == 'stale-net',
                         'midgame': MIDGAME_MODES.get(kind)})
    return runs


def midgame_lua(run: dict, evidence: Path) -> Path:
    """The run's copy of queue_midgame_client.lua with its mode set first (NLQ_MODE), in the evidence folder."""
    path = evidence / f'{run["name"]}-client.lua'
    path.write_text(f'NLQ_MODE = "{run["midgame"]}"\n' + MIDGAME_SOURCE.read_text(encoding='utf-8'), encoding='utf-8')
    return path


def run_arguments(run: dict, evidence: Path, args) -> list[str]:
    settle = args.busy_seconds if run.get('busy') else args.settle
    result = ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', run['name'],
              '--addons', '--players', '1', '--map', args.map, '--change-map', args.then_map,
              '--width', str(args.width), '--height', str(args.height), '--settle', str(settle),
              '--screenshots', '0', '--timeout', str(args.timeout), '--hang-grace', str(args.hang_grace),
              '--before-quit-console', 'disconnect']
    if run['test']:
        result.append('--extra=-nl_queue_check_test')
    if run.get('busy'):
        result += ['--console', 'engine_no_focus_sleep 0', '--console', BUSY_RUN]
    if run.get('stale'):
        result += ['--lua', str(STALE_SOURCE)]
    if run.get('no_flush'):
        result.append('--extra=-nl_queue_check_no_flush')
    if run.get('midgame'):
        result += ['--lua', str(midgame_lua(run, evidence))]
        if run['midgame'] == 'console':
            # Before the run's own disconnect: the setters and the cleanup in one console line, then the marker.
            at = result.index('--before-quit-console')
            for command in reversed(MIDGAME_CONSOLE):
                result[at:at] = ['--before-quit-console', command]
    return result


def count_lines(text: str) -> dict:
    return {key: len(re.findall(pattern, text)) for key, pattern in LINES.items()}


def count_log(text: str) -> dict:
    return {key: len(re.findall(pattern, text)) for key, pattern in LOG_LINES.items()}


def new_dumps(root: Path, started: float) -> list[str]:
    """The crash dumps the run made (crashes/*.dmp written since it started). A first start may also gather older dumps
    into a loader session folder; those are not this run's crashes."""
    folder = root / 'crashes'
    if not folder.is_dir():
        return []
    return sorted(item.name for item in folder.glob('*.dmp') if item.is_file() and item.stat().st_mtime >= started - 5)


def stale_before_cleanup(text: str) -> bool:
    """The stale Lua's restores were queued before the fixes' cleanup hook ran (a cleanup line after them)."""
    queued = text.find('[nlqueue] stale: queued restores')
    return queued >= 0 and text.find('[RTX Texture Cleanup]', queued) > queued


def cleanup_in(part: str) -> dict:
    """The fixes' cleanup in a piece of the console: its "Ran <n>" lines (`ran`) and "fully uncached" lines
    (`uncached`), the count of the first "Ran" line (`first_calls`), and whether that line comes before the first
    "fully uncached" one (`ordered`: the queued calls ran before that purge)."""
    ran = list(RAN.finditer(part))
    uncached = part.find(UNCACHED)
    return {'ran': len(ran), 'uncached': part.count(UNCACHED), 'first_calls': int(ran[0][1]) if ran else 0,
            'ordered': bool(ran) and uncached >= 0 and ran[0].start() < uncached}


def stale_after(text: str) -> dict:
    """The fixes' cleanup after the first `[nlqueue] stale: queued restores` line (the stale client queues them right
    before the cleanup hook's body): the materials that line counts (`stale_materials`), the cleanup's lines after it
    (`stale_ran_after`, `stale_uncached_after`), the first "Ran" line's count (`stale_first_ran_calls`) and whether
    that line comes before the uncache (`stale_ran_then_uncached`)."""
    found = STALE_QUEUED.search(text)
    after = cleanup_in(text[found.start():] if found else '')
    return {'stale_materials': int(found[1]) if found else 0, 'stale_ran_after': after['ran'],
            'stale_uncached_after': after['uncached'], 'stale_first_ran_calls': after['first_calls'],
            'stale_ran_then_uncached': after['ordered']}


def midgame_after(text: str, kind: str) -> dict:
    """The fixes' cleanup lines after the first `[nlqueue] midgame: queued setters` line: in all the rest of the
    console (`midgame_ran_after`, `midgame_uncached_after`), and before the run's own end line, the Lua global's
    `returned` line or the console run's marker (`midgame_ran_before_end`, `midgame_uncached_before_end`), so the
    count is the mid-game cleanup's and not the disconnect's. Also the setter calls the client says it made
    (`midgame_setter_calls`), the count of the first "Ran" line before the end line (`midgame_first_ran_calls`) and
    whether that line comes before the uncache (`midgame_ran_then_uncached`)."""
    result = {'midgame_ran_after': 0, 'midgame_uncached_after': 0, 'midgame_ran_before_end': 0,
              'midgame_uncached_before_end': 0, 'midgame_setter_calls': 0, 'midgame_first_ran_calls': 0,
              'midgame_ran_then_uncached': False}
    start = text.find(MIDGAME_QUEUED)
    if start < 0:
        return result
    rest = text[start:]
    setters = MIDGAME_SETTERS.match(rest)
    result['midgame_setter_calls'] = int(setters[1]) if setters else 0
    after = cleanup_in(rest)
    result['midgame_ran_after'] = after['ran']
    result['midgame_uncached_after'] = after['uncached']
    end = rest.find(MIDGAME_END.get(kind, '\0'))
    if end >= 0:
        before = cleanup_in(rest[:end])
        result['midgame_ran_before_end'] = before['ran']
        result['midgame_uncached_before_end'] = before['uncached']
        result['midgame_first_ran_calls'] = before['first_calls']
        result['midgame_ran_then_uncached'] = before['ordered']
    return result


def judge(record: dict) -> list[str]:
    """Why a run does not show what its kind must (empty: it passes)."""
    kind = record.get('kind')
    lines = record.get('lines')
    reasons = []
    exit_ok = record.get('exit') == 0 or (record.get('exit') is None and record.get('normal_quit'))
    if record.get('crashed') or not exit_ok:
        reasons.append(f'exit {record.get("exit_hex") or record.get("exit")}')
    if record.get('new_dumps'):
        reasons.append(f'{len(record["new_dumps"])} new crash dump(s)')
    if lines is None:
        return reasons + ['no console.log']

    def need(key, test, wanted):
        value = lines.get(key, record.get(key, 0)) or 0
        if not test(value):
            reasons.append(f'{key} {value} (expected {wanted})')

    if kind == 'test':
        need('test_dropped', lambda v: v >= 1, '>= 1')
        need('test_put_back', lambda v: v >= 1, '>= 1')
    elif kind in ('plain', 'busy'):
        for key in ('dropped', 'put_back', 'gone'):
            need(key, lambda v: v == 0, '0')
    elif kind == 'stale':
        # The cleanup right after the restores ran at least their calls, then uncached.
        need('stale_queued', lambda v: v >= 1, '>= 1')
        need('cleanup_flushed', lambda v: v >= 1, '>= 1')
        need('stale_materials', lambda v: v >= 1, '>= 1')
        need('stale_ran_after', lambda v: v >= 1, '>= 1')
        need('stale_uncached_after', lambda v: v >= 1, '>= 1')
        wanted = STALE_CALLS_EACH * (record.get('stale_materials', 0) or 0)
        need('stale_first_ran_calls', lambda v: v >= max(wanted, 1), f'>= {max(wanted, 1)}')
        if not record.get('stale_ran_then_uncached'):
            reasons.append('the cleanup after the stale restores did not run the queued calls before it uncached')
        need('cleanup_skipped', lambda v: v == 0, '0')
        need('gone', lambda v: v == 0, '0')
    elif kind == 'stale-net':
        # The cleanup uncached with the restores still queued (the flush ran nothing), and the net skipped them.
        need('stale_queued', lambda v: v >= 1, '>= 1')
        need('stale_uncached_after', lambda v: v >= 1, '>= 1')
        need('gone', lambda v: v >= 1, '>= 1')
        value = record.get('log_gone_events', 0) or 0
        if value < 1:
            reasons.append(f'log_gone_events {value} (expected >= 1)')
    elif kind in ('midgame', 'midgame-console'):
        need('midgame_queued', lambda v: v >= 1, '>= 1')
        need('midgame_ran_after', lambda v: v >= 1, '>= 1')
        need('midgame_uncached_after', lambda v: v >= 1, '>= 1')
        need('midgame_ran_before_end', lambda v: v >= 1, '>= 1')
        need('midgame_uncached_before_end', lambda v: v >= 1, '>= 1')
        # The mid-game cleanup ran at least the setters' calls, then uncached.
        need('midgame_setter_calls', lambda v: v >= 1, '>= 1')
        wanted = max(record.get('midgame_setter_calls', 0) or 0, 1)
        need('midgame_first_ran_calls', lambda v: v >= wanted, f'>= {wanted}')
        if not record.get('midgame_ran_then_uncached'):
            reasons.append('the mid-game cleanup did not run the queued calls before it uncached')
        need('midgame_returned' if kind == 'midgame' else 'midgame_sent', lambda v: v >= 1, '>= 1')
        for key in ('dropped', 'put_back', 'gone', 'cleanup_skipped'):
            need(key, lambda v: v == 0, '0')
    if kind in ('stale', 'stale-net') and not record.get('stale_order'):
        reasons.append('the stale restores were not queued before the cleanup hook ran')
    return reasons


def keep_new(root: Path, started: float, target: Path) -> list[str]:
    """Copies what the run added under KEEP (crash dumps, the loader's session folders) into the evidence."""
    kept = []
    for folder in KEEP:
        source = root / folder
        if not source.is_dir():
            continue
        for item in source.iterdir():
            if item.stat().st_mtime < started - 5:
                continue
            copy = target / folder / item.name
            copy.parent.mkdir(parents=True, exist_ok=True)
            if item.is_dir():
                shutil.copytree(item, copy, dirs_exist_ok=True)
            else:
                shutil.copy2(item, copy)
            kept.append(f'{folder}/{item.name}')
    return kept


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help="a new folder under the main checkout's out")
    parser.add_argument('--package', type=Path, help='the local RTX package to run (.gma)')
    parser.add_argument('--kinds', nargs='+', choices=KINDS, default=['test', 'plain'])
    parser.add_argument('--repeat', type=int, default=1, help='runs of each kind')
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--then-map', default='gm_flatgrass', help='the level change: map <this>')
    parser.add_argument('--settle', type=int, default=20, help='seconds in each map')
    parser.add_argument('--busy-seconds', type=int, default=240, help="a busy run's seconds in each map")
    parser.add_argument('--width', type=int, default=1600)
    parser.add_argument('--height', type=int, default=900)
    parser.add_argument('--timeout', type=int, default=900, help='map start deadline (a fresh deployment unpacks)')
    parser.add_argument('--hang-grace', type=float, default=180)
    parser.add_argument('--lock-timeout', type=int, default=4 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted series')
    args = parser.parse_args(argv)
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    runs = plan_runs(args)
    if not args.rollback and (not args.package or not args.package.is_file()):
        parser.error('give --package, an existing .gma')
    with contextlib.ExitStack() as stack:
        stack.enter_context(vs.ExclusiveLock(main_root / 'out/r10/poc.lock',
                                             'queue and run check (engine guard, ADR 0247, ADR 0254)',
                                             timeout=args.lock_timeout))
        if args.rollback:
            vs.restore(vs.POC, evidence)
            if not args.keep_copies:
                vs.cleanup(evidence)
            return 0
        if evidence.exists() and any(evidence.iterdir()):
            raise ValueError('use a new evidence folder; --rollback recovers an interrupted series')
        evidence.mkdir(parents=True, exist_ok=True)
        if poc.game_processes(vs.POC):
            raise RuntimeError('a game is already running in the PoC')
        package = args.package.resolve()
        protected = {str(p): vs.sha256(p) for p in vs.POC.rglob('user.conf')}
        vs.write_json(evidence / 'protected-before.json', protected)
        vs.write_json(evidence / 'plan.json', {'runs': runs, 'args': {k: str(v) for k, v in vars(args).items()},
                                               'package': str(package), 'package_sha256': vs.sha256(package)})
        vs.command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'snapshot', '--root', vs.POC,
                    '--manifests-from', vs.FIELD], evidence, 'snapshot')
        results = []
        try:
            vs.preserve(vs.POC, evidence)
            vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install', '--allow-local', package,
                        '--remix', 'on', '--replace-config'], evidence, 'install')
            for run in runs:
                log = vs.POC / LOG
                if log.exists():
                    log.unlink()  # each run's own log
                if run.get('busy'):
                    busy = vs.POC / BUSY_DATA
                    busy.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(BUSY_SOURCE, busy)
                started = time.time()
                record = {'name': run['name'], 'kind': run.get('kind'), 'test': run['test'],
                          'busy': run.get('busy', False),
                          'stale': run.get('stale', False), 'no_flush': run.get('no_flush', False),
                          'midgame': run.get('midgame'),
                          'started': dt.datetime.now(dt.timezone.utc).isoformat()}
                print(run['name'], flush=True)
                try:
                    vs.command(run_arguments(run, evidence, args), evidence, run['name'], allowed=(0, 1))
                finally:
                    record['new_dumps'] = new_dumps(vs.POC, started)
                    record['kept'] = keep_new(vs.POC, started, evidence / run['name'] / 'crash')
                record['seconds'] = round(time.time() - started, 1)
                history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
                last = history[-1]
                record.update({key: last.get(key) for key in (
                    'failed', 'normal_quit', 'exit', 'exit_hex', 'exit_name', 'map_changed', 'crash_reports',
                    'declined_crash_prompts', 'lua_errors')})
                console = evidence / 'poc' / run['name'] / 'console.log'
                text = console.read_text(encoding='utf-8', errors='replace') if console.exists() else None
                record['lines'] = count_lines(text) if text is not None else None
                record['stale_order'] = stale_before_cleanup(text) if text is not None else False
                if run.get('stale'):
                    record.update(stale_after(text or ''))
                if run.get('midgame'):
                    record.update(midgame_after(text or '', run['kind']))
                if log.exists():
                    copy = evidence / run['name'] / 'render-queue-check.log'
                    copy.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(log, copy)
                    record['log'] = str(copy)
                    record.update(count_log(copy.read_text(encoding='utf-8', errors='replace')))
                record['crashed'] = last.get('exit') not in (0, None) and not last.get('normal_quit')
                record['reasons'] = judge(record)
                record['verdict'] = 'FAIL' if record['reasons'] else 'PASS'
                results.append(record)
                vs.write_json(evidence / 'results.json', results)
        finally:
            if (evidence / 'originals.json').exists():
                vs.restore(vs.POC, evidence)
            vs.write_json(evidence / 'protected-after.json', {p: vs.sha256(Path(p)) for p in protected})
            if any(vs.sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        if not args.keep_copies:
            vs.cleanup(evidence)
    for record in results:
        lines = record.get('lines') or {}
        print(f'{record["name"]}: {record["verdict"]}'
              + (f' ({"; ".join(record["reasons"])})' if record['reasons'] else '') + ';'
              f' {"CRASHED" if record["crashed"] else "no crash"} after {record["seconds"]} s'
              f' (exit {record.get("exit_hex") or record.get("exit")}); installed {lines.get("installed")},'
              f' run check {lines.get("run_installed")} (off {lines.get("run_off")}),'
              f' test drops {lines.get("test_dropped")}, test put back {lines.get("test_put_back")},'
              f' stale drops {lines.get("dropped")}, put back {lines.get("put_back")},'
              f' log checks {record.get("log_checks", 0)}, log runs {record.get("log_runs", 0)}'
              f' ({record.get("log_run_events", 0)} events, {record.get("log_test_events", 0)} the test\'s)'
              f'; flush {lines.get("flush_installed")} (off {lines.get("flush_off")}),'
              f' target check {lines.get("target_installed")} (off {lines.get("target_off")}),'
              f' cleanup flushed {lines.get("cleanup_flushed")}, cleanup skipped {lines.get("cleanup_skipped")},'
              f' gone {lines.get("gone")}, log flushes {record.get("log_flushes", 0)},'
              f' log gone events {record.get("log_gone_events", 0)}, new dumps {len(record.get("new_dumps") or [])},'
              f' kept {len(record.get("kept") or [])}'
              + (f', busy reports {lines.get("busy_report")}' if record.get('busy') else '')
              + (f', stale armed {lines.get("stale_armed")}, queued {lines.get("stale_queued")}'
                 f' ({record.get("stale_materials", 0)} materials), the cleanup after them ran'
                 f' {record.get("stale_first_ran_calls", 0)} calls first'
                 f' ({record.get("stale_ran_after", 0)} ran lines, {record.get("stale_uncached_after", 0)} uncached)'
                 + (', no flush' if record.get('no_flush') else '') if record.get('stale') else '')
              + (f', midgame ({record["midgame"]}) armed {lines.get("midgame_armed")},'
                 f' queued {lines.get("midgame_queued")} ({record.get("midgame_setter_calls", 0)} setter calls),'
                 f' cleanup ran {record.get("midgame_ran_after", 0)}'
                 f' and uncached {record.get("midgame_uncached_after", 0)} after the setters'
                 f' ({record.get("midgame_ran_before_end", 0)} and {record.get("midgame_uncached_before_end", 0)}'
                 f' before the run\'s end line, the first having run {record.get("midgame_first_ran_calls", 0)}'
                 f' calls)' if record.get('midgame') else ''))
    failed = [record['name'] for record in results if record['verdict'] != 'PASS']
    print(f'{len(results) - len(failed)} of {len(results)} runs passed' + (f'; failed: {", ".join(failed)}' if failed
                                                                            else ''))
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
