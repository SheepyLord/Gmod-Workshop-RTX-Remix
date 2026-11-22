"""pack_install_session.py: what a freshly subscribed content package costs in a locked PoC RTX session: the loader's
deploy at the start, then, in the game, the Model Hotloader installing the package's models into a fresh library,
frame by frame. See pack_install_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
import json
import re
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
from mmd_player_session import Lock  # noqa: E402

DATA = vs.POC / 'garrysmod/data'
PROBE_ADDON = vs.POC / 'garrysmod/addons/zz_nlpack_probe'
TASK = 'Content package install timing (pack_install_session)'
ATTACH = 'print("NLPACK_ATTACHED " .. tostring(NLPACK ~= nil))\n'


OVERRIDE = ('library.lua', 'workshop.lua', 'ui.lua')


def settings_lua(args) -> str:
    override = ', '.join(f'"{name}"' for name in OVERRIDE) if args.hotloader_lua else ''
    return (f'NLPACK_SETTINGS = {{quiet = {args.quiet:g}, start = {args.start:g}, limit = {args.limit:g}, '
            f'long = {args.long:g}, spawnmenu = {"true" if args.spawnmenu else "false"}, override = {{{override}}}}}\n')


def write_probe(args, folder: Path) -> Path:
    """The probe as a one-session add-on, so it runs from the map's first frame; a copy goes to the evidence. With
    --hotloader-lua, the branch's library.lua, workshop.lua and ui.lua go beside it, and it includes them over the
    package's."""
    code = settings_lua(args) + (TOOLS / 'qa/pack_install_probe.lua').read_text(encoding='utf-8')
    target = PROBE_ADDON / 'lua/autorun/client/zz_nlpack_probe.lua'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(code, encoding='utf-8')
    if args.hotloader_lua:
        (PROBE_ADDON / 'lua/nlpack_override').mkdir(parents=True, exist_ok=True)
        for name in OVERRIDE:
            shutil.copy2(args.hotloader_lua / name, PROBE_ADDON / 'lua/nlpack_override' / name)
            shutil.copy2(args.hotloader_lua / name, folder / name)
    (PROBE_ADDON / 'addon.json').write_text(json.dumps({'title': 'nlpack probe', 'type': 'tool', 'tags': ['fun']}),
                                            encoding='utf-8')
    (folder / 'pack_install_probe.lua').write_text(code, encoding='utf-8')
    attach = folder / 'attach.lua'
    attach.write_text(ATTACH, encoding='utf-8')
    return attach


def run_command(args, evidence: Path, attach: Path) -> list[str]:
    command = ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', args.label,
               '--addons', '--players', '1', '--map', args.map, '--width', str(args.width), '--height', str(args.height),
               '--console', 'engine_no_focus_sleep 0', '--lua', str(attach), '--lua-manual', '--screenshots', '0',
               '--timeout', str(args.timeout), '--hang-grace', str(args.hang_grace)]
    command += [f'--extra={extra}' for extra in args.extra]
    return command


def seed_library(source: Path, target: Path) -> dict:
    """What the library lists, copied from another Model Hotloader data folder (read only): each character's manifest
    and settings, and the props (their bundles and settings). No model data, workshop records or other state."""
    counts = {'characters': 0, 'settings': 0, 'props': 0}
    for manifest in sorted(source.glob('assets/*/manifest.json')):
        destination = target / 'assets' / manifest.parent.name / 'manifest.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(manifest, destination)
        counts['characters'] += 1
    for settings in sorted(source.glob('library/*.json')):
        (target / 'library').mkdir(parents=True, exist_ok=True)
        shutil.copy2(settings, target / 'library' / settings.name)
        counts['settings'] += 1
    if (source / 'static').is_dir():
        for path in sorted((source / 'static').rglob('*')):
            if path.is_file() and path.parent.name in ('assets', 'library'):
                destination = target / path.relative_to(source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
                counts['props'] += path.parent.name == 'assets'
    return counts


DEPLOY = re.compile(r'(?i)(deploy|unpack|extract|journal|installed|changes?)')


def loader_lines(evidence: Path, label: str) -> list[str]:
    """The loader log's lines about deploying, as poc_session kept the log."""
    for name in ('loader.log', 'native-loader.log'):
        path = evidence / 'poc' / label / name
        if path.is_file():
            return [line for line in path.read_text(encoding='utf-8', errors='replace').splitlines() if DEPLOY.search(line)][:400]
    return []


def remix_mod_lines(evidence: Path, label: str) -> list[str]:
    path = evidence / 'poc' / label / 'remix-dxvk.log'
    if not path.is_file():
        return []
    return [line for line in path.read_text(encoding='utf-8', errors='replace').splitlines() if '[RTX Mod Load]' in line]


def report(result: dict) -> None:
    install = result.get('install_frames') or {}
    print(f"install: {result.get('seconds')} s for {len(result.get('installed') or [])} models; frames {install.get('frames')}, "
          f"over 50 ms {install.get('over50')}, over 100 ms {install.get('over100')}, over 250 ms {install.get('over250')}, "
          f"over 1 s {install.get('over1000')}, longest {install.get('max')} ms")
    for item in result.get('installed') or []:
        print(f"  {item['t']:>9.3f} s  {item['name']}")
    print('longest frames:')
    for frame in sorted(result.get('long_frames') or [], key=lambda f: -f['ms'])[:12]:
        print(f"  {frame['ms']:>8} ms at {frame['t']} s (busy {frame['busy']}, installed {frame['installed']}): {frame['top'][:4]}")
    print('top functions (self time):')
    for row in (result.get('functions') or [])[:15]:
        print(f"  {row['self_ms']:>10} ms self, {row['incl_ms']:>10} ms incl, {row['calls']:>7} calls, max {row['max_ms']} ms  {row['name']}")
    watched = [e for e in result.get('events') or [] if e['kind'] in (
        'library_revision', 'window_shown', 'window_hidden', 'spawnmenu_close_kept_open')]
    if watched:
        print('library revisions (listed: characters library.Add listed; none: a rebuild) and the library window:')
        for e in watched:
            print(f"  {e['t']:>9.3f} s  {e['kind']} {e.get('detail') or ''}")
    updates = result.get('library_updates') or []
    if updates:
        print("library window updates (rebuild: the whole list again; rows: new rows added alone):")
        for update in updates:
            spent = update.get('refresh_ms') if update['kind'] == 'rebuild' else update.get('add_rows_ms')
            print(f"  {update['t']:>9.3f} s  {update['kind']:<7} {spent} ms in the call, frame {update['ms']} ms, "
                  f"next frame {update.get('next_ms')} ms (busy {update['busy']}, installed {update['installed']})")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help="a new folder under this repository's out")
    parser.add_argument('--package', type=Path, help='the RTX package (.gma) the loader deploys')
    parser.add_argument('--pack', type=Path, help='the content package (.gma) under test, deployed as a local package')
    parser.add_argument('--label', default='run', help="the run's name in the evidence")
    parser.add_argument('--library', action='store_true',
                        help="keep the PoC's own Model Hotloader library (default: a fresh one, as a new subscriber has)")
    parser.add_argument('--seed-library', type=Path,
                        help="a Model Hotloader data folder (data/mmd_hotloader) whose library to list: its characters' "
                             "manifests and settings and its props are copied in, so the install meets a library that size")
    parser.add_argument('--spawnmenu', action='store_true', help="open the spawn menu on the Model Hotloader's tab while the models install")
    parser.add_argument('--hotloader-lua', type=Path,
                        help="a Model Hotloader lua/mmdhl folder whose library.lua, workshop.lua and ui.lua run over the "
                             "package's for this session (a branch's change, before a package is built from it)")
    parser.add_argument('--quiet', type=float, default=10, help='seconds without an install before the probe ends')
    parser.add_argument('--start', type=float, default=180, help='seconds for an install to begin after the spawn')
    parser.add_argument('--limit', type=float, default=1200, help='seconds for the whole probe')
    parser.add_argument('--long', type=float, default=50, help='a long frame, in milliseconds')
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--width', type=int, default=1600)
    parser.add_argument('--height', type=int, default=900)
    parser.add_argument('--timeout', type=int, default=1800, help='map start deadline (the first start deploys both packages)')
    parser.add_argument('--hang-grace', type=float, default=900)
    parser.add_argument('--extra', action='append', default=[], help='a launch option for the game (repeatable)')
    parser.add_argument('--lock-timeout', type=int, default=6 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--keep-field-game', action='store_true',
                        help="leave a running field game alone (another task's test uses it); the timings share the computer with it")
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted run')
    args = parser.parse_args(argv)
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    if not args.rollback:
        for name in ('package', 'pack'):
            path = getattr(args, name)
            if not path or not path.is_file():
                parser.error(f'--{name} must name a .gma')
    result = None
    with contextlib.ExitStack() as stack:
        stack.enter_context(Lock(main_root / 'out/r10/poc.lock', TASK, timeout=args.lock_timeout))
        if args.rollback:
            if poc.game_processes(vs.POC):
                raise RuntimeError('the PoC still runs')
            vs.restore(vs.POC, evidence)
            if not args.keep_copies:
                vs.cleanup(evidence)
            return 0
        if evidence.exists() and any(evidence.iterdir()):
            raise ValueError('use a new evidence folder; --rollback recovers an interrupted run')
        # Another task's game in the PoC (one started without the lock): wait for it to end, as for the lock, and for
        # the PoC to stay free for 90 s, so that task's next run, if it has one, starts first.
        waited, free_since = time.time(), None
        while True:
            if poc.game_processes(vs.POC):
                free_since = None
            elif free_since is None:
                free_since = time.time()
            if free_since is not None and (time.time() - free_since >= 90 or time.time() - waited < 1):
                break
            if time.time() - waited > args.lock_timeout:
                raise RuntimeError('a game is already running in the PoC')
            time.sleep(10)
        evidence.mkdir(parents=True, exist_ok=True)
        protected = {str(p): vs.sha256(p) for p in vs.POC.rglob('user.conf')}
        registry = r12a.video_settings()
        vs.write_json(evidence / 'plan.json', {'args': {k: str(v) for k, v in vars(args).items()},
                                               'package_sha256': vs.sha256(args.package), 'pack_bytes': args.pack.stat().st_size})
        vs.command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'snapshot', '--root', vs.POC,
                    '--manifests-from', vs.FIELD], evidence, 'snapshot')
        try:
            vs.preserve(vs.POC, evidence)
            DATA.mkdir(parents=True, exist_ok=True)
            library = evidence / 'originals/garrysmod/data/mmd_hotloader'
            if args.library and library.is_dir():
                shutil.copytree(library, DATA / 'mmd_hotloader')
            if args.seed_library:
                vs.write_json(evidence / 'seeded.json', seed_library(args.seed_library, DATA / 'mmd_hotloader'))
            vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install', '--allow-local',
                        args.package.resolve(), '--allow-local', args.pack.resolve(), '--remix', 'on', '--replace-config'],
                       evidence, 'install')
            if args.keep_field_game:
                # Another task's test in the field game: left running, and the timings share the computer with it.
                vs.write_json(evidence / 'field-games.json', {'time': poc.now(), 'kept': poc.game_processes(poc.FIELD_ROOT)})
            else:
                vs.write_json(evidence / 'field-games.json', r12a.end_field_games())
            folder = evidence / args.label
            folder.mkdir(parents=True, exist_ok=True)
            attach = write_probe(args, folder)
            started = time.time()
            vs.command(run_command(args, evidence, attach), evidence, args.label, allowed=(0, 1))
            history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
            last = history[-1]
            vs.write_json(folder / 'session.json', {key: last.get(key) for key in (
                'failed', 'normal_quit', 'exit', 'lua', 'lua_manual_done', 'seconds_to_map', 'device_lost',
                'declined_crash_prompts', 'crash_reports')} | {'seconds': round(time.time() - started)})
            if (DATA / 'nlpack_probe').is_dir():
                shutil.copytree(DATA / 'nlpack_probe', folder / 'results')
            vs.write_json(folder / 'loader-deploy.json', {'loader': loader_lines(evidence, args.label),
                                                          'remix_mod_load': remix_mod_lines(evidence, args.label)})
            result_path = folder / 'results/result.json'
            if result_path.is_file():
                result = json.loads(result_path.read_text(encoding='utf-8'))
        finally:
            if not poc.game_processes(vs.POC) and (evidence / 'originals.json').exists():
                vs.restore(vs.POC, evidence)
            r12a.restore_video_settings(registry)
            if any(vs.sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        if not args.keep_copies:
            vs.cleanup(evidence)
    if result:
        report(result)
        print('result:', evidence / args.label / 'results/result.json')
    else:
        print('no probe result; see', evidence / 'poc' / args.label)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
