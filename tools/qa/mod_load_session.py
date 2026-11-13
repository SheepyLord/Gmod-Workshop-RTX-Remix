"""mod_load_session.py: how long the Remix runtime takes to load the rtx-remix mods ("Loading enhancements") at each
start of the PoC, for one or more packages in turn, with the user's subscribed content packages deployed as in the
field. Holds out/r10/poc.lock, snapshots the PoC with the VR driver's helpers and restores it at the end. See
mod_load_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import json
import re
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / 'qa'))

import poc_session as poc  # noqa: E402
import vr_session as vs  # noqa: E402
import purge_file_cache  # noqa: E402

STAMP = re.compile(r'^\[(\d\d):(\d\d):(\d\d)\.(\d{3})\]')
# Runtime patch 0086 (ADR 0195): one line per mod and one for the whole load, and the cache's counters per mod.
MOD_LINE = re.compile(r'\[RTX Mod Load\] mod=(?P<mod>\S+) (?P<fields>.*)$')
ALL_LINE = re.compile(r'\[RTX Mod Load\] all mods=(?P<mods>\d+) (?P<fields>.*)$')
CACHE_LINE = re.compile(r'\[RTX Mod Texture Cache\] mod=(?P<mod>\S+) (?P<fields>.*)$')
CAMERA = (823.0, -657.0, -40.0, 8.0, 180.0, 0.0)  # gm_construct, facing west (the queued-draws lab's view)
FIELD = re.compile(r'(\w+)=([-\d.]+)')
# Any runtime: a mod's search paths are published when its walk starts.
SEARCH_PATH = re.compile(r'Adding asset search path: .*[\\/]mods[\\/](?P<mod>[^\\/]+)[\\/]')
SECRET = re.compile(r'\[SecretReplacement\] Could not find stage: .*[\\/]mods[\\/](?P<mod>[^\\/]+)[\\/]')


def seconds_of(line: str) -> float | None:
    match = STAMP.match(line)
    if not match:
        return None
    h, m, s, ms = (int(v) for v in match.groups())
    return h * 3600 + m * 60 + s + ms / 1000


def parse_log(text: str) -> dict:
    """The mod load as the Remix log tells it: the patched runtime's own lines when present, and for any runtime the
    span from the first mod's search paths to the last mod's secret-replacement warnings (its walk's end)."""
    mods, total, first, last, order, cache = [], None, None, None, [], []
    start = None
    for line in text.splitlines():
        t = seconds_of(line)
        if start is None and t is not None:
            start = t
        match = MOD_LINE.search(line)
        if match:
            entry = {'mod': match['mod'], **{k: float(v) for k, v in FIELD.findall(match['fields'])}}
            entry['at'] = None if t is None or start is None else round(t - start, 3)
            mods.append(entry)
            continue
        match = CACHE_LINE.search(line)
        if match:
            cache.append({'mod': match['mod'], **{k: float(v) for k, v in FIELD.findall(match['fields'])}})
            continue
        match = ALL_LINE.search(line)
        if match:
            total = {'mods': int(match['mods']), **{k: float(v) for k, v in FIELD.findall(match['fields'])}}
            total['at'] = None if t is None or start is None else round(t - start, 3)
            continue
        match = SEARCH_PATH.search(line) or SECRET.search(line)
        if match and t is not None:
            first = t if first is None else first
            last = t
            if not order or order[-1] != match['mod'].lower():
                order.append(match['mod'].lower())
    result = {'mods': mods, 'total': total, 'mod_order': list(dict.fromkeys(order)), 'cache': cache}
    if cache:
        result['cache_sum'] = {key: sum(entry.get(key, 0) for entry in cache)
                               for key in ('lookups', 'repeats', 'hits', 'misses', 'unkept', 'unlisted', 'folders',
                                           'list_ms', 'read_ms', 'save_ms')}
    if first is not None and start is not None:
        result['markers'] = {'first_s': round(first - start, 3), 'last_s': round(last - start, 3),
                             'span_s': round(last - first, 3)}
    return result


def plan_runs(args) -> list[dict]:
    runs = []
    for spec in args.package:
        label, _, path = spec.partition('=')
        for n in range(1, args.starts + 1):
            name = f'{label}-{n}'
            runs.append({'name': name, 'label': label, 'start': n, 'package': str(Path(path).resolve()),
                         'cold': name in args.cold})
    return runs


def purge_mods() -> dict:
    """Windows' file cache emptied of the PoC's rtx-remix files (mods and the runtime's cache), as after a reboot."""
    folders = [vs.POC / 'rtx-remix' / 'mods', vs.POC / 'rtx-remix' / 'cache']
    paths = purge_file_cache.files_below([f for f in folders if f.is_dir()])
    started = time.perf_counter()
    result = purge_file_cache.purge(paths)
    result['files'] = len(paths)
    result['seconds'] = round(time.perf_counter() - started, 1)
    return result


def run_arguments(run: dict, evidence: Path, args) -> list[str]:
    return ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', run['name'],
            '--map', args.map, '--players', '1', '--width', str(args.width), '--height', str(args.height),
            '--extra=+fps_max', '--extra=60', '--settle', str(args.settle), '--screenshots', str(args.screenshots),
            '--camera', ','.join(f'{v:g}' for v in CAMERA), '--hide-hud',
            '--timeout', str(args.timeout), '--hang-grace', str(args.hang_grace)]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help='a new folder under the main checkout\'s out')
    parser.add_argument('--package', action='append', default=[], metavar='LABEL=GMA',
                        help='a package to run (repeatable, in order); each gets --starts sessions')
    parser.add_argument('--starts', type=int, default=2, help='game starts per package (the first after its deployment)')
    parser.add_argument('--subscribed-content', choices=('on', 'off'), default='on',
                        help='deploy the user\'s subscribed content packages too, as the field does (default on)')
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--settle', type=int, default=90, help='seconds in the map before the quit (the mods load meanwhile)')
    parser.add_argument('--screenshots', type=int, default=1, help='screenshots of the pinned view after --settle')
    parser.add_argument('--cold', action='append', default=[], metavar='RUN',
                        help="before this run (LABEL-N), empty the file cache of the PoC's rtx-remix files (repeatable)")
    parser.add_argument('--width', type=int, default=1600)
    parser.add_argument('--height', type=int, default=900)
    parser.add_argument('--timeout', type=int, default=1200, help='map start deadline (a fresh deployment unpacks)')
    parser.add_argument('--hang-grace', type=float, default=300)
    parser.add_argument('--lock-timeout', type=int, default=6 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted run')
    parser.add_argument('--parse', type=Path, metavar='REMIX_LOG', help='only print what a remix-dxvk.log says')
    args = parser.parse_args(argv)
    if args.parse:
        print(json.dumps(parse_log(args.parse.read_text(encoding='utf-8', errors='replace')), indent=2))
        return 0
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    runs = plan_runs(args)
    if not args.rollback and not runs:
        parser.error('give --package')
    for run in runs:
        if not Path(run['package']).is_file():
            parser.error(f'no package {run["package"]}')
    (REPO / 'out/tmp').mkdir(parents=True, exist_ok=True)
    with contextlib.ExitStack() as stack:
        stack.enter_context(vs.ExclusiveLock(main_root / 'out/r10/poc.lock', 'mod load timing (Loading enhancements)',
                                             timeout=args.lock_timeout))
        if args.rollback:
            vs.restore(vs.POC, evidence)
            if not args.keep_copies:
                vs.cleanup(evidence)
            return 0
        if evidence.exists() and any(evidence.iterdir()):
            raise ValueError('use a new evidence folder; --rollback recovers an interrupted run')
        evidence.mkdir(parents=True, exist_ok=True)
        if poc.game_processes(vs.POC):
            raise RuntimeError('a game is already running in the PoC')
        protected = {str(p): vs.sha256(p) for p in vs.POC.rglob('user.conf')}
        vs.write_json(evidence / 'protected-before.json', protected)
        vs.write_json(evidence / 'plan.json', {'runs': runs, 'args': {k: str(v) for k, v in vars(args).items()},
                                               'packages': {r['package']: vs.sha256(Path(r['package'])) for r in runs}})
        vs.command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'snapshot', '--root', vs.POC,
                    '--manifests-from', vs.FIELD], evidence, 'snapshot')
        results, installed, current = [], False, None
        try:
            vs.preserve(vs.POC, evidence)
            for run in runs:
                if run['package'] != current:
                    step = 'install' if not installed else 'config'
                    extra = ['--replace-config'] if step == 'install' else []
                    vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', step, '--allow-local',
                                run['package'], '--remix', 'on', '--subscribed-content', args.subscribed_content,
                                *extra], evidence, f'{run["name"]}-{step}')
                    installed, current = True, run['package']
                record = {'name': run['name'], 'label': run['label'], 'start': run['start'], 'cold': run['cold'],
                          'started': dt.datetime.now(dt.timezone.utc).isoformat()}
                if run['cold']:
                    record['purge'] = purge_mods()
                started = time.time()
                vs.command(run_arguments(run, evidence, args), evidence, run['name'], allowed=(0, 1))
                record['seconds'] = round(time.time() - started, 1)
                history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
                last = history[-1]
                record.update({key: last.get(key) for key in ('failed', 'normal_quit', 'exit', 'exit_hex')})
                log = evidence / 'poc' / run['name'] / 'remix-dxvk.log'
                record['load'] = parse_log(log.read_text(encoding='utf-8', errors='replace')) if log.exists() else None
                cache = vs.POC / 'rtx-remix' / 'cache'
                record['cache_bytes'] = sum(p.stat().st_size for p in cache.rglob('*') if p.is_file()) if cache.exists() else 0
                results.append(record)
                vs.write_json(evidence / 'results.json', results)
                total = (record['load'] or {}).get('total') or {}
                print(f'{run["name"]}: all mods {total.get("ms")} ms, markers {(record["load"] or {}).get("markers")}',
                      flush=True)
        finally:
            if (evidence / 'originals.json').exists():
                vs.restore(vs.POC, evidence)
            vs.write_json(evidence / 'protected-after.json', {p: vs.sha256(Path(p)) for p in protected})
            if any(vs.sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        if not args.keep_copies:
            vs.cleanup(evidence)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
