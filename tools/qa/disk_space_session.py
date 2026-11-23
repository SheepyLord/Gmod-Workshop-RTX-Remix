"""disk_space_session.py: the companion's disk space notice (ADR 0260) in a locked PoC RTX session: the RTX client
module's measure of the game drive and the packages at the main menu, and each card's preview, with screenshots.
See disk_space_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
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
import mmd_reimport_session as r12a  # noqa: E402
from mmd_player_session import Lock  # noqa: E402

DATA = vs.POC / 'garrysmod/data'
TASK = 'Disk space notice (companion menu script, ADR 0260)'
COMMANDS = ['nativeloader_disk_space_status', 'nativeloader_disk_space_preview need',
            'nativeloader_disk_space_preview full', 'nativeloader_disk_space_preview low']


def lines_of(console: Path) -> list[str]:
    """The run's own console lines about disk space (its console.log holds only this session)."""
    if not console.is_file():
        return []
    text = console.read_text(encoding='utf-8', errors='replace')
    return [line.strip() for line in text.splitlines() if '[nativeloader] disk space' in line or 'NativeLoader RTX menu' in line]


def free_space(root: Path) -> dict:
    import shutil
    usage = shutil.disk_usage(root)
    return {'free_mib': usage.free // 1048576, 'total_mib': usage.total // 1048576}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help='a new folder under this repository\'s out')
    parser.add_argument('--package', type=Path, help='the RTX package (.gma) to deploy')
    parser.add_argument('--label', default='menu', help='the run\'s name in the evidence')
    parser.add_argument('--language', default='', help='the companion\'s language for the cards (data/nativeloader_companion/language.txt), e.g. ja')
    parser.add_argument('--command', action='append', default=[], help='a menu console command instead of the default four (repeatable)')
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--width', type=int, default=1600)
    parser.add_argument('--height', type=int, default=900)
    parser.add_argument('--timeout', type=int, default=1200, help='map start deadline (a fresh deployment unpacks)')
    parser.add_argument('--hang-grace', type=float, default=600)
    parser.add_argument('--lock-timeout', type=int, default=6 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted run')
    args = parser.parse_args(argv)
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    with contextlib.ExitStack() as stack:
        stack.enter_context(Lock(main_root / 'out/r10/poc.lock', TASK, timeout=args.lock_timeout))
        if args.rollback:
            if poc.game_processes(vs.POC):
                raise RuntimeError('the PoC still runs')
            vs.restore(vs.POC, evidence)
            if not args.keep_copies:
                vs.cleanup(evidence)
            return 0
        if not args.package or not args.package.is_file():
            parser.error('--package must name a built .gma')
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
        summary = {}
        try:
            vs.preserve(vs.POC, evidence)
            DATA.mkdir(parents=True, exist_ok=True)
            if args.language:
                (DATA / 'nativeloader_companion').mkdir(parents=True, exist_ok=True)
                (DATA / 'nativeloader_companion/language.txt').write_text(args.language, encoding='utf-8')
            vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install', '--allow-local',
                        args.package.resolve(), '--remix', 'on', '--replace-config'], evidence, 'install')
            vs.write_json(evidence / 'field-games.json', r12a.end_field_games())
            before = free_space(vs.POC)
            command = ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', args.label,
                       '--addons', '--workshop', '--players', '1', '--map', args.map, '--width', str(args.width),
                       '--height', str(args.height), '--menu-shot', '--screenshots', '0', '--timeout', str(args.timeout),
                       '--hang-grace', str(args.hang_grace)]
            for menu_command in args.command or COMMANDS:
                command += ['--menu-console', menu_command]
            vs.command(command, evidence, args.label, allowed=(0, 1))
            history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
            last = history[-1]
            run = evidence / 'poc' / args.label
            lines = lines_of(run / 'console.log')
            measured = next((line for line in lines if 'drive ' in line and 'MiB free' in line), '')
            match = re.search(r'drive (\S+) has (\d+) MiB free of (\d+) MiB', measured)
            summary = {
                'failed': last.get('failed'), 'exit': last.get('exit'), 'normal_quit': last.get('normal_quit'),
                'menu_console': last.get('menu_console'), 'menu_screenshot': last.get('menu_screenshot'),
                'lines': lines, 'python_free_before': before,
                'module_free_mib': int(match.group(2)) if match else None,
                'module_total_mib': int(match.group(3)) if match else None,
            }
            vs.write_json(evidence / 'summary.json', summary)
        finally:
            if not poc.game_processes(vs.POC):
                if (evidence / 'originals.json').exists():
                    vs.restore(vs.POC, evidence)
            r12a.restore_video_settings(registry)
            if any(vs.sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        if not args.keep_copies:
            vs.cleanup(evidence)
    for line in summary.get('lines', []):
        print(line)
    print('module measured', summary.get('module_free_mib'), 'MiB free of', summary.get('module_total_mib'),
          '; Python before the run', summary.get('python_free_before'))
    for entry in summary.get('menu_console') or []:
        print(entry.get('command'), '->', 'sent' if entry.get('sent') else 'NOT SENT', (entry.get('screenshot') or {}).get('path', ''))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
