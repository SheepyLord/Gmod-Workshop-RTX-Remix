"""queue_check_session.py: RTX sessions on the PoC for the engine guard's queue check (ADR 0247). A test session
launched with -nl_queue_check_test, where every check first queues one call whose object is gone, so the level change
and the disconnect go through the drop path in the real game; and a plain session that changes level and disconnects
with nothing to drop. Holds out/r10/poc.lock, snapshots the PoC with the VR driver's helpers and restores it at the
end. See queue_check_session.py.md."""
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
    'test_armed': r'\[NativeLoader\] Queue check test: each check first queues one call whose object is gone',
    'test_dropped': r'\[NativeLoader\] Queue check test: the test call was dropped',
    'dropped': r'\[NativeLoader\] Dropped \d+ queued render call',
    'not_walked': r'\[NativeLoader\] The queue check could not walk a render call list',
    'stopped': r'\[NativeLoader\] The queue check stopped on a fault',
}
LOG = Path('garrysmod/data/native-loader/render-queue-check.log')


def plan_runs(args) -> list[dict]:
    runs = []
    for n in range(1, args.repeat + 1):
        for kind in args.kinds:
            runs.append({'name': f'{kind}-{n}', 'test': kind == 'test'})
    return runs


def run_arguments(run: dict, evidence: Path, args) -> list[str]:
    result = ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', run['name'],
              '--addons', '--players', '1', '--map', args.map, '--change-map', args.then_map,
              '--width', str(args.width), '--height', str(args.height), '--settle', str(args.settle),
              '--screenshots', '0', '--timeout', str(args.timeout), '--hang-grace', str(args.hang_grace),
              '--before-quit-console', 'disconnect']
    if run['test']:
        result.append('--extra=-nl_queue_check_test')
    return result


def count_lines(text: str) -> dict:
    return {key: len(re.findall(pattern, text)) for key, pattern in LINES.items()}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help="a new folder under the main checkout's out")
    parser.add_argument('--package', type=Path, help='the local RTX package to run (.gma)')
    parser.add_argument('--kinds', nargs='+', choices=('test', 'plain'), default=['test', 'plain'])
    parser.add_argument('--repeat', type=int, default=1, help='runs of each kind')
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--then-map', default='gm_flatgrass', help='the level change: map <this>')
    parser.add_argument('--settle', type=int, default=20, help='seconds in each map')
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
        stack.enter_context(vs.ExclusiveLock(main_root / 'out/r10/poc.lock', 'queue check (engine guard, ADR 0247)',
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
                started = time.time()
                record = {'name': run['name'], 'test': run['test'],
                          'started': dt.datetime.now(dt.timezone.utc).isoformat()}
                print(run['name'], flush=True)
                vs.command(run_arguments(run, evidence, args), evidence, run['name'], allowed=(0, 1))
                record['seconds'] = round(time.time() - started, 1)
                history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
                last = history[-1]
                record.update({key: last.get(key) for key in (
                    'failed', 'normal_quit', 'exit', 'exit_hex', 'exit_name', 'map_changed', 'crash_reports',
                    'declined_crash_prompts', 'lua_errors')})
                console = evidence / 'poc' / run['name'] / 'console.log'
                record['lines'] = count_lines(console.read_text(encoding='utf-8', errors='replace')) if console.exists() else None
                if log.exists():
                    copy = evidence / run['name'] / 'render-queue-check.log'
                    copy.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(log, copy)
                    record['log'] = str(copy)
                    record['log_checks'] = len(re.findall(r'(?m)^\S+ check \d+ ', copy.read_text(encoding='utf-8')))
                record['crashed'] = last.get('exit') not in (0, None) and not last.get('normal_quit')
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
        print(f'{record["name"]}: {"CRASHED" if record["crashed"] else "no crash"} after {record["seconds"]} s'
              f' (exit {record.get("exit_hex") or record.get("exit")}); installed {lines.get("installed")},'
              f' test drops {lines.get("test_dropped")}, stale drops {lines.get("dropped")},'
              f' log checks {record.get("log_checks", 0)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
