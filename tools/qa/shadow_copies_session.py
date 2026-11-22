"""shadow_copies_session.py: Local player shadow (the RTX fixes' body and weapon copies) switched on and off in a
locked PoC RTX session: a screenshot and frame times before and after each switch, and the server's entities that
have a model but no model scale. See shadow_copies_session.py.md."""
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
from mmd_player_session import Lock  # noqa: E402

DATA = vs.POC / 'garrysmod/data'
TASK = 'Local player shadow switched on mid-session (the RTX fixes body and weapon copies)'
BODY, WEAPON = 'rtx_pseudoplayer', 'rtx_pseudoweapon'
ORDERS = {
    'body-first': [('02_body_on', [(BODY, '1')], None), ('03_both_on', [(WEAPON, '1')], None)],
    'weapon-first': [('02_weapon_on', [(WEAPON, '1')], None), ('03_both_on', [(BODY, '1')], None)],
    # A third-person view (drawviewer, as the motion importer's camera): without the copies, with the weapon copy,
    # with both, then both in first person.
    'third-person': [('02_third_off', [], 'third'), ('03_third_weapon', [(WEAPON, '1')], 'third'),
                     ('04_third_both', [(BODY, '1')], 'third'), ('05_first_both', [], 'first')],
}


# Which part of the weapon copy brings the body copy into your first-person view (the tool gun in hand): its entity's
# own draw, its client-side model's, the tool gun's screen add-on, another scripted weapon, its private textures.
COPY_ENTITIES = 'for _, e in ipairs(ents.FindByClass("rtx_pseudoweapon")) do '
DIAGNOSE = [
    {'label': '02_body_on', 'set': [(BODY, '1')]},
    {'label': '03_weapon_on', 'set': [(WEAPON, '1')]},
    {'label': '04_entity_hidden', 'lua': COPY_ENTITIES + 'e.RenderOverride = function() end end'},
    {'label': '05_model_hidden', 'lua': COPY_ENTITIES + 'for _, c in ipairs(e:GetChildren()) do '
                                        'c.RenderOverride = function() end end end'},
    {'label': '06_drawn_screen_off', 'set': [('dts_enabled', '0')],
     'lua': COPY_ENTITIES + 'e.RenderOverride = nil for _, c in ipairs(e:GetChildren()) do '
                            'c.RenderOverride = PseudoweaponRender end end'},
    {'label': '07_camera_swep', 'set': [('dts_enabled', '1'), ('nlshadow_weapon', 'gmod_camera')]},
    # The switch back to the tool gun makes the copy build its private textures (MaterialSet, on a weapon change).
    {'label': '08_private_textures', 'set': [('rtx_pseudoweapon_unique_hashes', '1'), ('nlshadow_weapon', 'gmod_tool')],
     'wait': 16},
]


# Both copies with the tool gun in first person and in third person, then the gravity gun and the tool gun again
# (each weapon change makes the weapon copy's private textures anew).
VERIFY = [
    {'label': '02_body_on', 'set': [(BODY, '1')]},
    {'label': '03_both_on', 'set': [(WEAPON, '1')]},
    {'label': '04_third_both', 'view': 'third'},
    {'label': '05_gravity_gun', 'view': 'first', 'set': [('nlshadow_weapon', 'weapon_physcannon')]},
    {'label': '06_tool_gun_again', 'set': [('nlshadow_weapon', 'gmod_tool')]},
]


def steps(args) -> list[dict]:
    if args.order == 'verify':
        rows = [dict(row) for row in VERIFY]
        rows.append({'label': '07_both_off', 'set': [(BODY, '0'), (WEAPON, '0')]})
        return rows
    if args.order == 'diagnose':
        rows = [dict(row) for row in DIAGNOSE]
        rows.append({'label': '09_both_off', 'set': [(BODY, '0'), (WEAPON, '0'), ('rtx_pseudoweapon_unique_hashes', '0')]})
        return rows
    rows = [{'label': label, 'set': changes, **({'view': view} if view else {})}
            for label, changes, view in ORDERS[args.order]]
    if args.player_model:
        rows.append({'label': '06_player_model', 'run': ['nlshadow_player_model'], 'wait': 20})
    rows.append({'label': '07_both_off', 'set': [(BODY, '0'), (WEAPON, '0')], 'view': 'first'})
    return rows


def lua_value(value) -> str:
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return f'{value:g}'
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, dict):
        return '{' + ', '.join(f'{key} = {lua_value(item)}' for key, item in value.items()) + '}'
    return '{' + ', '.join(lua_value(item) for item in value) + '}'


def settings_lua(args) -> str:
    settings = {'settle': args.settle, 'wait': args.wait, 'measure': 3, 'character': args.character,
                'steps': steps(args)}
    if args.weapon:
        settings['weapon'] = args.weapon
    if args.hour is not None:
        settings['hour'] = args.hour
    return f'NLSH = {lua_value(settings)}\n'


def run_command(args, evidence: Path, probe: Path) -> list[str]:
    command = ['tools/poc_session.py', '--evidence', str(evidence / 'poc'), 'run', '--name', args.label,
               '--addons', '--players', '1', '--map', args.map, '--width', str(args.width), '--height', str(args.height),
               '--console', 'engine_no_focus_sleep 0',
               '--console', 'lua_run RunString(file.Read("nlshadow/server.txt","DATA"),"nlshadow_server")']
    for setting in args.console:
        command += ['--console', setting]
    command += ['--lua', str(probe), '--lua-shots', str(args.timeout), '--settle', '2', '--screenshots', '0',
                '--timeout', str(args.timeout), '--hang-grace', str(args.hang_grace)]
    return command


def summary(folder: Path) -> dict:
    out: dict = {}
    client, server = folder / 'results/client.json', folder / 'results/server.json'
    if client.is_file():
        data = json.loads(client.read_text(encoding='utf-8'))
        out['original'] = data.get('original')
        out['steps'] = [{key: step.get(key) for key in ('label', 'rtx_pseudoplayer', 'rtx_pseudoweapon', 'body_copies',
                                                        'weapon_copies', 'frame')} for step in data.get('steps', [])]
    if server.is_file():
        data = json.loads(server.read_text(encoding='utf-8'))
        out['asked'] = [{key: row.get(key) for key in ('class', 'model', 'time', 'caller')} for row in data.get('asked') or []]
        out['present'] = data.get('present') or {}
    return out


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--evidence', type=Path, required=True, help='a new folder under this repository\'s out')
    parser.add_argument('--package', type=Path, help='the RTX package (.gma) to deploy')
    parser.add_argument('--label', default='run', help='the run\'s name in the evidence')
    parser.add_argument('--order', choices=sorted([*ORDERS, 'diagnose', 'verify']), default='body-first',
                        help='which copy is switched on first (default: the body), the third-person sequence, the '
                             'diagnostic sequence for the weapon copy in first person, or the verification sequence')
    parser.add_argument('--character', action='store_true',
                        help='spawn the PoC library\'s first imported character as an NPC in front of you first')
    parser.add_argument('--player-model', action='store_true',
                        help='with both copies on, make that character your own model (a step of its own)')
    parser.add_argument('--weapon', help='a weapon class to hold from the start (gmod_tool draws a screen of its own)')
    parser.add_argument('--hour', type=float, help='hold the time of day at this hour (the sky\'s clock stops)')
    parser.add_argument('--console', action='append', default=[],
                        help='a console command after the map, before the probe (repeatable)')
    parser.add_argument('--settle', type=float, default=15, help='seconds after the probe starts before the first shot')
    parser.add_argument('--wait', type=float, default=12, help='seconds after each switch before its shot')
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
    if not args.rollback and (not args.package or not args.package.is_file()):
        parser.error('--package must name a built .gma')
    result: dict = {}
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
            vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install', '--allow-local',
                        args.package.resolve(), '--remix', 'on', '--replace-config'], evidence, 'install')
            folder = evidence / args.label
            folder.mkdir(parents=True, exist_ok=True)
            probe = folder / 'shadow_copies_probe.lua'
            probe.write_text(settings_lua(args) + (TOOLS / 'qa/shadow_copies_probe.lua').read_text(encoding='utf-8'),
                             encoding='utf-8')
            (DATA / 'nlshadow').mkdir(parents=True, exist_ok=True)
            shutil.copyfile(TOOLS / 'qa/shadow_copies_server.lua', DATA / 'nlshadow/server.txt')
            started = time.time()
            vs.command(run_command(args, evidence, probe), evidence, args.label, allowed=(0, 1))
            history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
            last = history[-1]
            vs.write_json(folder / 'session.json', {key: last.get(key) for key in (
                'failed', 'normal_quit', 'exit', 'lua', 'lua_shots_done', 'lua_shots', 'seconds_to_map',
                'device_lost', 'declined_crash_prompts', 'crash_reports')} | {'seconds': round(time.time() - started)})
            if (DATA / 'nlshadow').is_dir():
                shutil.copytree(DATA / 'nlshadow', folder / 'results')
                result = summary(folder)
                vs.write_json(folder / 'summary.json', result)
        finally:
            if not poc.game_processes(vs.POC):
                if (evidence / 'originals.json').exists():
                    vs.restore(vs.POC, evidence)
            r12a.restore_video_settings(registry)
            if any(vs.sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        if not args.keep_copies:
            vs.cleanup(evidence)
    for step in result.get('steps', []):
        frame = step.get('frame') or {}
        print(f'{step["label"]:<16} body {step["rtx_pseudoplayer"]} ({step["body_copies"]})  weapon '
              f'{step["rtx_pseudoweapon"]} ({step["weapon_copies"]})  median {frame.get("median_ms")} ms  '
              f'p90 {frame.get("p90_ms")} ms')
    for row in result.get('asked', []):
        print('no model scale, asked:', row['class'], row['model'], 'at', row['time'])
    for key, row in (result.get('present') or {}).items():
        print('no model scale, present:', key, row)
    print('screenshots:', evidence / 'poc' / args.label)
    return 0


if __name__ == '__main__':
    sys.exit(main())
