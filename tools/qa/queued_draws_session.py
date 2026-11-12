"""queued_draws_session.py: RTX sessions on the PoC that spawn and remove props, gibs and doors in view, to show the
RTX fixes' crash on the queued render thread before the queued-draws patch and its absence after (ADR 0192), and a
still scene for before/after captures of prop lighting. Holds out/r10/poc.lock, snapshots the PoC with the VR
driver's helpers, and restores it at the end. See queued_draws_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import json
import math
import shutil
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import poc_session as poc  # noqa: E402
import vr_session as vs  # noqa: E402

# WER LocalDumps on this machine (docs/RESEARCH.md): every crashed gmod.exe's dump. Only read.
WER = Path(r'H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\_debug_tools\hangdumps\wer')
CAMERA = (823.0, -657.0, -40.0, 8.0, 180.0, 0.0)  # gm_construct, the VR fixture's eye, facing west


def settings_lua(mode: str, seconds: int, shots: int, camera, distance: float, per_frame: int, settle: int,
                 console_churn: int, load: int) -> str:
    x, y, z, _, yaw, _ = camera
    forward = forward_xy(yaw)
    center = (x + forward[0] * distance, y + forward[1] * distance, z - 50)
    return (f'NLQD = {{mode = "{mode}", seconds = {seconds}, shots = {shots}, yaw = {yaw:g}, '
            f'center = Vector({center[0]:.1f}, {center[1]:.1f}, {center[2]:.1f}), per_frame = {per_frame}, '
            f'settle = {settle}, console_churn = {console_churn}, load = {load}}}\n')


def forward_xy(yaw: float):
    return (math.cos(math.radians(yaw)), math.sin(math.radians(yaw)))


def plan_runs(args) -> list[dict]:
    runs = []
    for label, package in (('before', args.before), ('after', args.after)):
        if not package:
            continue
        for mode in args.modes:
            for n in range(1, (args.repeat if mode == 'stress' else 1) + 1):
                runs.append({'name': f'{label}-{mode}-{n}', 'label': label, 'mode': mode,
                             'package': str(Path(package).resolve())})
    return runs


def run_arguments(run: dict, evidence: Path, args) -> list[str]:
    camera = args.camera
    header = settings_lua(run['mode'], args.seconds, args.shots, camera, args.distance, args.per_frame, args.settle,
                          args.console_churn, args.load)
    folder = evidence / run['name']
    folder.mkdir(parents=True, exist_ok=True)
    probe = folder / 'queued_draws_probe.lua'
    probe.write_text(header + (TOOLS / 'qa/queued_draws_probe.lua').read_text(encoding='utf-8'), encoding='utf-8')
    server = header + (TOOLS / 'qa/queued_draws_server.lua').read_text(encoding='utf-8')
    (folder / 'queued_draws_server.lua').write_text(server, encoding='utf-8')
    x, y, z, pitch, yaw, roll = camera
    result = ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', run['name'],
              '--addons', '--players', '1', '--map', 'gm_construct',
              '--width', str(args.width), '--height', str(args.height),
              '--extra=-insecure', '--extra=+mat_queue_mode', f'--extra={args.queue_mode}',
              '--extra=+fps_max', f'--extra={args.fps_max:g}', '--console', 'engine_no_focus_sleep 0',
              '--console', f'lua_run local p=Entity(1) p:SetMoveType(MOVETYPE_NOCLIP) p:SetPos(Vector({x:g},{y:g},{z - 64:g})) '
                           f'p:SetEyeAngles(Angle({pitch:g},{yaw:g},{roll:g}))']
    for line in poc.client_lua_lines('qd_server', server):
        result += ['--console', line.replace('lua_run_cl', 'lua_run', 1)]
    seconds = args.seconds if run['mode'] == 'stress' else args.settle + 30
    result += ['--camera', ','.join(f'{v:g}' for v in camera), '--hide-hud', '--lua', str(probe),
               '--lua-shots', str(seconds + 120), '--settle', '5', '--screenshots', '0',
               '--timeout', str(args.timeout), '--hang-grace', str(args.hang_grace)]
    return result


def new_dumps(since: float, known: set[str]) -> list[Path]:
    """Dumps written since `since` that no earlier run of the series took (WER can finish one after the next run
    has started)."""
    if not WER.is_dir():
        return []
    return sorted(p for p in WER.glob('gmod.exe.*.dmp') if p.name not in known and p.stat().st_mtime >= since)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help='a new folder under the main checkout\'s out')
    parser.add_argument('--before', type=Path, help='the package with the RTX fixes before the patch (.gma)')
    parser.add_argument('--after', type=Path, help='the package with the patch (.gma)')
    parser.add_argument('--modes', nargs='+', choices=('stress', 'lighting'), default=['lighting', 'stress'])
    parser.add_argument('--seconds', type=int, default=600, help='stress duration per run')
    parser.add_argument('--repeat', type=int, default=1, help='stress runs per package')
    parser.add_argument('--shots', type=int, default=60, help='seconds between stress checkpoint screenshots')
    parser.add_argument('--per-frame', type=int, default=0,
                        help='client models created and removed per frame (8 a frame exhausted an engine list in 4 min)')
    parser.add_argument('--console-churn', type=int, default=400,
                        help='stress: up to this many characters of console text a frame (0: none)')
    parser.add_argument('--settle', type=int, default=20, help='lighting: seconds before the first capture')
    parser.add_argument('--distance', type=float, default=220, help='units from the camera to the scene')
    parser.add_argument('--camera', type=lambda t: tuple(float(v) for v in t.split(',')), default=CAMERA)
    parser.add_argument('--queue-mode', choices=('-1', '0', '1', '2'), default='2')
    parser.add_argument('--fps-max', type=float, default=0, help='the session\'s fps_max (0: uncapped, as the VR driver)')
    parser.add_argument('--load', type=int, default=24,
                        help='stress: frozen citizen ragdolls in view, skinned on the CPU on the render thread')
    parser.add_argument('--width', type=int, default=1600)
    parser.add_argument('--height', type=int, default=900)
    parser.add_argument('--timeout', type=int, default=900, help='map start deadline (a fresh deployment unpacks)')
    parser.add_argument('--hang-grace', type=float, default=180)
    parser.add_argument('--lock-timeout', type=int, default=4 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted run')
    args = parser.parse_args(argv)
    if len(args.camera) != 6:
        parser.error('--camera needs x,y,z,pitch,yaw,roll')
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    runs = plan_runs(args)
    if not args.rollback and not runs:
        parser.error('give --before and/or --after')
    for run in runs:
        if not Path(run['package']).is_file():
            parser.error(f'no package {run["package"]}')
    scratch = REPO / 'out/tmp'
    scratch.mkdir(parents=True, exist_ok=True)
    with contextlib.ExitStack() as stack:
        stack.enter_context(vs.ExclusiveLock(main_root / 'out/r10/poc.lock', 'queued-draws crash repro (fixes)',
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
        known = {p.name for p in WER.glob('gmod.exe.*.dmp')} if WER.is_dir() else set()
        try:
            vs.preserve(vs.POC, evidence)
            for run in runs:
                if run['package'] != current:
                    step = 'install' if not installed else 'config'
                    extra = ['--replace-config'] if step == 'install' else []
                    vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', step, '--allow-local',
                                run['package'], '--remix', 'on', *extra], evidence, f'{run["name"]}-{step}')
                    installed, current = True, run['package']
                started = time.time()
                record = {'name': run['name'], 'label': run['label'], 'mode': run['mode'],
                          'started': dt.datetime.now(dt.timezone.utc).isoformat()}
                print(run['name'], flush=True)
                vs.command(run_arguments(run, evidence, args), evidence, run['name'], allowed=(0, 1))
                record['seconds'] = round(time.time() - started, 1)
                history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
                last = history[-1]
                record.update({key: last.get(key) for key in (
                    'failed', 'normal_quit', 'exit', 'exit_hex', 'exit_name', 'lua_shots', 'lua_shots_done',
                    'crash_reports', 'device_lost', 'declined_crash_prompts')})
                dumps = []
                if last.get('exit') not in (0, None) or not last.get('normal_quit'):
                    time.sleep(20)  # WER writes a crashed game's dump after the process has gone
                for dump in new_dumps(started - 5, known):
                    known.add(dump.name)
                    copy = evidence / run['name'] / 'wer' / dump.name
                    copy.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(dump, copy)
                    dumps.append(str(copy))
                record['wer_dumps'] = dumps
                record['crashed'] = bool(dumps) or (last.get('exit') not in (0, None) and not last.get('normal_quit'))
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
        print(f'{record["name"]}: {"CRASHED" if record["crashed"] else "no crash"} after {record["seconds"]} s'
              f' (exit {record.get("exit_hex") or record.get("exit")}, dumps {len(record["wer_dumps"])})')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
