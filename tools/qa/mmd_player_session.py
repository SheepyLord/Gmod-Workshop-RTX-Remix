"""mmd_player_session.py: times the Advanced MMD Animation Player (the character motion importer's tool) in a
locked PoC RTX session: selecting motions in the tool's list, selecting yourself, assigning motions to two
imported characters spawned as NPCs, with a copy of the field's motion library. See mmd_player_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
import json
import shutil
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / 'qa'))

import poc_session as poc  # noqa: E402
import vr_session as vs  # noqa: E402
import mmd_reimport_session as r12a  # noqa: E402

DATA = vs.POC / 'garrysmod/data'
TASK = 'MMD animation player hitches (character motion importer)'


class Lock(vs.ExclusiveLock):
    """vr_session's lock, tried four times a second: other tasks' queued holds retake it within a second
    of its release, so a three-second poll can wait behind a whole series."""

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        deadline, announced = time.monotonic() + self.timeout, False
        while True:
            try:
                with self.path.open('x', encoding='utf-8') as stream:
                    stream.write(self.owner)
                return self
            except FileExistsError:
                if not announced:
                    print('Waiting for lock', self.path, flush=True)
                    announced = True
                if time.monotonic() >= deadline:
                    raise TimeoutError(f'lock remains owned by another session: {self.path}')
                time.sleep(0.25)


def settings_lua(args) -> str:
    motions = ', '.join(json.dumps(m) for m in args.motions)
    return (f'NLMP_SETTINGS = {{window = {args.window:g}, settle = {args.settle:g}, '
            f'manager = {"true" if args.manager else "false"}, tab = {"true" if args.tab else "false"}, '
            f'features = {"true" if args.features else "false"}, steps = {"false" if args.no_steps else "true"}, '
            f'motions = {{{motions}}}}}\n')


def run_command(args, evidence: Path, probe: Path) -> list[str]:
    # The server half waits in the session's (fresh) data folder: as hex console lines it outgrew
    # Windows' 32,767-character command line.
    command = ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', args.label,
               '--addons', '--players', '1', '--map', args.map, '--width', str(args.width), '--height', str(args.height),
               '--console', 'engine_no_focus_sleep 0',
               '--console', 'lua_run RunString(file.Read("nlmp_probe/server.txt","DATA"),"nlmp_server")']
    command += ['--lua', str(probe), '--lua-manual', '--screenshots', '0', '--timeout', str(args.timeout),
                '--hang-grace', str(args.hang_grace)]
    if args.workshop:
        command.append('--workshop')
    command += [f'--extra={extra}' for extra in args.extra]
    return command


def move_in(source: Path, destination: Path, receipt: Path) -> None:
    if destination.exists():
        raise RuntimeError(f'{destination} exists; the PoC data must be fresh')
    vs.write_json(receipt, {'from': str(source), 'to': str(destination), 'listing': vs.listing(source)})
    source.rename(destination)


def move_back(receipt: Path) -> dict | None:
    if not receipt.exists():
        return None
    record = json.loads(receipt.read_text(encoding='utf-8'))
    source, destination = Path(record['from']), Path(record['to'])
    if destination.exists() and not source.exists():
        destination.rename(source)
    changed = sorted(k for k, v in vs.listing(source).items() if record['listing'].get(k) != v)
    receipt.unlink()
    return {'moved_back': str(source), 'changed_files': changed}


def summarize(results: Path) -> list[dict]:
    rows = []
    for path in sorted(results.glob('step_*.json')):
        data = json.loads(path.read_text(encoding='utf-8'))
        frames = data.get('frames', {})
        client = data.get('client') or []
        server = (data.get('server') or {}).get('stats') or []
        rows.append({
            'step': data.get('name'), 'max_ms': round(frames.get('max_ms', 0)), 'over_100': frames.get('over_100'),
            'median_ms': round(frames.get('median_ms', 0), 1), 'window_ms': round(frames.get('window_ms', 0)),
            'client_top': [(r['name'], round(r['self_ms'], 1), r['calls']) for r in client[:6]],
            'server_top': [(r['name'], round(r['self_ms'], 1), r['calls']) for r in server[:6]],
            'server_ticks': (data.get('server') or {}).get('longest_ticks_ms', [])[:3],
            'sent': data.get('sent') or {},
            'error': data.get('action_error'),
        })
    return rows


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help='a new folder under this repository\'s out')
    parser.add_argument('--package', type=Path, help='the RTX package (.gma) to deploy')
    parser.add_argument('--label', default='run', help='the run\'s name in the evidence')
    parser.add_argument('--data', type=Path, help='a folder holding a copy of the field\'s data/mmd_vmd_npc as mmd_vmd_npc')
    parser.add_argument('--workshop', action='store_true', help='mount the Workshop subscriptions, as the field does')
    parser.add_argument('--manager', action='store_true', help='also open the Motion Manager window')
    parser.add_argument('--tab', action='store_true', help='also open the RTX package\'s Motion importer spawn-menu tab')
    parser.add_argument('--features', action='store_true',
                        help='after the steps, check keep-expressions, ragdoll collision and the debug timeline in the game')
    parser.add_argument('--no-steps', action='store_true', help='skip the timed click-through (with --features: the checks alone)')
    parser.add_argument('--motions', nargs='*', default=[], help='the two motion ids to select (default: a third and two thirds down the list)')
    parser.add_argument('--window', type=float, default=4, help='seconds measured after each action')
    parser.add_argument('--settle', type=float, default=8, help='seconds after the NPCs spawn before the first step')
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--width', type=int, default=1600)
    parser.add_argument('--height', type=int, default=900)
    parser.add_argument('--timeout', type=int, default=1200, help='map start deadline (a fresh deployment unpacks)')
    parser.add_argument('--hang-grace', type=float, default=600)
    parser.add_argument('--extra', action='append', default=[], help='a launch option for the game (repeatable)')
    parser.add_argument('--lock-timeout', type=int, default=6 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted run')
    args = parser.parse_args(argv)
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    receipt = evidence / 'data-moved.json'
    if not args.rollback:
        if not args.package or not args.package.is_file():
            parser.error('--package must name a built .gma')
        if not args.data or not (args.data / 'mmd_vmd_npc').is_dir():
            parser.error('--data must hold mmd_vmd_npc')
    results: list[dict] = []
    with contextlib.ExitStack() as stack:
        stack.enter_context(Lock(main_root / 'out/r10/poc.lock', TASK, timeout=args.lock_timeout))
        if args.rollback:
            if poc.game_processes(vs.POC):
                raise RuntimeError('the PoC still runs')
            print(move_back(receipt))
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
        registry = r12a.video_settings()
        vs.write_json(evidence / 'plan.json', {'args': {k: str(v) for k, v in vars(args).items()},
                                               'package_sha256': vs.sha256(args.package)})
        vs.command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'snapshot', '--root', vs.POC,
                    '--manifests-from', vs.FIELD], evidence, 'snapshot')
        try:
            vs.preserve(vs.POC, evidence)
            DATA.mkdir(parents=True, exist_ok=True)
            library = evidence / 'originals/garrysmod/data/mmd_hotloader'
            if library.is_dir():
                shutil.copytree(library, DATA / 'mmd_hotloader')
            move_in(args.data / 'mmd_vmd_npc', DATA / 'mmd_vmd_npc', receipt)
            vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install', '--allow-local',
                        args.package.resolve(), '--remix', 'on', '--replace-config'], evidence, 'install')
            vs.write_json(evidence / 'field-games.json', r12a.end_field_games())
            folder = evidence / args.label
            folder.mkdir(parents=True, exist_ok=True)
            probe = folder / 'mmd_player_probe.lua'
            probe.write_text(settings_lua(args) + (TOOLS / 'qa/mmd_player_probe.lua').read_text(encoding='utf-8'),
                             encoding='utf-8')
            (DATA / 'nlmp_probe').mkdir(parents=True, exist_ok=True)
            shutil.copyfile(TOOLS / 'qa/mmd_player_server.lua', DATA / 'nlmp_probe/server.txt')
            started = time.time()
            vs.command(run_command(args, evidence, probe), evidence, args.label, allowed=(0, 1))
            history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
            last = history[-1]
            vs.write_json(folder / 'session.json', {key: last.get(key) for key in (
                'failed', 'normal_quit', 'exit', 'lua', 'lua_manual_done', 'seconds_to_map', 'workshop_ready',
                'device_lost', 'declined_crash_prompts', 'crash_reports')} | {'seconds': round(time.time() - started)})
            if (DATA / 'nlmp_probe').is_dir():
                shutil.copytree(DATA / 'nlmp_probe', folder / 'results')
                results = summarize(folder / 'results')
                vs.write_json(folder / 'summary.json', results)
        finally:
            if not poc.game_processes(vs.POC):
                moved = move_back(receipt)
                if moved:
                    vs.write_json(evidence / 'data-back.json', moved)
                if (evidence / 'originals.json').exists():
                    vs.restore(vs.POC, evidence)
            r12a.restore_video_settings(registry)
            if any(vs.sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        if not args.keep_copies:
            vs.cleanup(evidence)
    for row in results:
        print(f'{row["step"]:<28} max {row["max_ms"]:>6} ms  >100ms {row["over_100"]:>3}  median {row["median_ms"]:>5} ms'
              + (f'  ERROR {row["error"]}' if row['error'] else ''))
        print('    client:', row['client_top'][:4])
        print('    server:', row['server_top'][:4], 'ticks', row['server_ticks'])
        if row['sent']:
            print('    sent:', row['sent'])
    features = evidence / args.label / 'results' / 'features.json'
    if features.is_file():
        print('features:', features)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
