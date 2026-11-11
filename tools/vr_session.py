"""Snapshot, run and restore the PoC with the real VR package; never configure or stop SteamVR."""
from __future__ import annotations

import argparse
import base64
import contextlib
import datetime as dt
import hashlib
import importlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import struct
import sys
import time
import uuid
import zlib

REPO = Path(__file__).resolve().parents[1]
POC = Path(r'H:\SteamLibrary\steamapps\common\GarrysMod_PoC')
FIELD = POC.with_name('GarrysMod')
ROOTS = ('native-loader', 'garrysmod/addons', 'garrysmod/data', 'garrysmod/settings',
         'garrysmod/lua/bin', 'rtx-remix/mods', 'rtx-remix/logs', 'rtx-remix/captures')
FILES = ('bin/win64/winmm.dll', 'bin/win64/winmm.pdb', 'garrysmod/cfg/nativeloader_session.cfg')
MARKER = re.compile(r'^NLVR_Q (\{.*\})\s*$', re.M)


def main_checkout(repo=REPO):
    common = subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                                     cwd=repo, text=True).strip()
    return Path(common).parent


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(data, indent=2), encoding='utf-8')
    os.replace(tmp, path)


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def inside_out(path, main):
    path = path.resolve()
    if not any(path.is_relative_to((root / 'out').resolve()) for root in (REPO, main)):
        raise ValueError('evidence and timelines must stay below this repository\'s out directory')
    return path


class ExclusiveLock:
    def __init__(self, path, task, timeout=600):
        self.path, self.timeout = path, timeout
        self.owner = json.dumps({'task': task, 'pid': os.getpid(), 'token': uuid.uuid4().hex,
                                 'started': dt.datetime.now(dt.timezone.utc).isoformat()})

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
                time.sleep(3)

    def __exit__(self, *exc):
        if self.path.exists() and self.path.read_text(encoding='utf-8') == self.owner:
            self.path.unlink()


def linked(path):
    """Reject reparse points without requiring Python 3.12's Path.is_junction."""
    try:
        return path.is_symlink() or bool(getattr(path.lstat(), 'st_file_attributes', 0) & 0x400)
    except FileNotFoundError:
        return False


def listing(path):
    """Rename verification, preserving links as links and never following them."""
    result, todo = {}, [path] if path.exists() else []
    while todo:
        p = todo.pop()
        rel = p.relative_to(path).as_posix()
        if linked(p):
            result[rel] = ['link', os.readlink(p)]
        elif p.is_dir():
            result[rel] = 'directory'
            todo.extend(p.iterdir())
        else:
            st = p.stat()
            result[rel] = [st.st_size, st.st_mtime_ns]
    return result


def command(args, evidence, name, allowed=(0,)):
    print(name, flush=True)
    with (evidence / (name + '.log')).open('wb') as output:
        done = subprocess.run([sys.executable, *map(str, args)], cwd=REPO,
                              stdout=output, stderr=subprocess.STDOUT)
    if done.returncode not in allowed:
        raise RuntimeError(f'{name} failed with exit {done.returncode}; see {evidence / (name + ".log")}')


def preserve(root, evidence):
    state = {'root': str(root), 'roots': {}, 'files': {}}
    for rel in ROOTS:
        p = root / rel
        if linked(p):
            raise ValueError(f'refusing to move a linked install root: {p}')
        # user.conf must not even move. Its normal location is the game root, outside ROOTS.
        if p.exists() and any(f.name.lower() == 'user.conf' for f in p.rglob('*')):
            raise ValueError(f'user.conf below a test root; leave it untouched: {p}')
        state['roots'][rel] = {'existed': p.exists(), 'listing': listing(p), 'moved': False}
    for rel in FILES:
        p = root / rel
        if p.is_symlink():
            raise ValueError(f'refusing linked bootstrap/session file: {p}')
        state['files'][rel] = {'existed': p.exists(), 'sha256': sha256(p) if p.exists() else None, 'moved': False}
    # Persist before every rename, so an interrupted preparation can always be rolled back.
    write_json(evidence / 'originals.json', state)
    for category in ('roots', 'files'):
        for rel, entry in state[category].items():
            if entry['existed']:
                dest = evidence / 'originals' / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                (root / rel).rename(dest)
                entry['moved'] = True
                write_json(evidence / 'originals.json', state)
    return state


def restore(root, evidence):
    import poc_session as poc
    if poc.game_processes(root):
        raise RuntimeError('PoC still running; retain originals and roll back after its exit')
    state = json.loads((evidence / 'originals.json').read_text(encoding='utf-8'))
    if Path(state['root']).resolve() != root.resolve():
        raise ValueError('snapshot belongs to a different install')
    checks = {}
    for category in ('roots', 'files'):
        for rel, entry in state[category].items():
            p, original = root / rel, evidence / 'originals' / rel
            # A second rollback is harmless; a missing original must already match its receipt.
            if original.exists():
                if p.exists():
                    debris = evidence / 'generated' / rel
                    if debris.exists():
                        raise ValueError(f'prior generated files retained: {debris}')
                    debris.parent.mkdir(parents=True, exist_ok=True)
                    p.rename(debris)
                p.parent.mkdir(parents=True, exist_ok=True)
                original.rename(p)
            elif not entry['existed'] and p.exists():
                debris = evidence / 'generated' / rel
                debris.parent.mkdir(parents=True, exist_ok=True)
                p.rename(debris)
            same = (listing(p) == entry['listing']) if category == 'roots' else (
                sha256(p) == entry['sha256'] if p.is_file() else not entry['existed'])
            checks[rel] = same
            if not same:
                raise RuntimeError(f'original tree/file differs after restoration: {rel}')
    command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'rollback', '--config', 'Release'],
            evidence, 'rollback', allowed=(0, 1))
    rollback = json.loads((evidence / 'snapshot/rollback.json').read_text(encoding='utf-8'))
    result = {'originals': checks, 'clean': rollback['clean'], 'rollback': rollback}
    write_json(evidence / 'restoration.json', result)
    if not result['clean']:
        raise RuntimeError('rollback did not verify clean; retain snapshot and generated files')
    return result


def cleanup(evidence):
    """Only owned bulk copies, only after a verified rollback; receipts always remain."""
    result = {'removed': [], 'errors': []}
    if not json.loads((evidence / 'restoration.json').read_text(encoding='utf-8'))['clean']:
        raise ValueError('cleanup requires verified clean restoration')
    for relative in ('originals', 'generated', 'snapshot/files', 'snapshot/debris'):
        p = (evidence / relative).resolve()
        if not p.is_relative_to(evidence.resolve()) or linked(p):
            raise ValueError('cleanup path escapes owned evidence')
        if p.exists():
            try:
                shutil.rmtree(p)
                result['removed'].append(relative)
            except OSError as error:
                result['errors'].append(str(error))
    write_json(evidence / 'cleanup.json', result)


def timeline(seconds):
    def step(t, yaw=0, lean=0):
        return {'time': t, 'hmd': {'pos': [0, lean, 1.6], 'ang': [0, yaw, 0]},
                'left': {'pos': [0.25, 0.25 + lean, 1.2], 'ang': [0, yaw, 0]},
                'right': {'pos': [0.25, -0.25 + lean, 1.2], 'ang': [0, yaw, 0]}}
    result = {'version': 1, 'steps': [step(0), step(10), step(14, 20), step(22, 20),
                                  step(26, -20), step(34, -20), step(38, 0, 0.2),
                                  step(46, 0, 0.2), step(50)]}
    for i in range(204, int(max(52,seconds)*4)+1):
        t=i/4
        result['steps'].append(step(t,3*math.sin(t*.08)+t*.0001,.001*math.sin(t*.11)))
    return result


def lua_script(path, settings):
    text = Path(__file__).with_suffix('.lua').read_text(encoding='utf-8')
    # JSON has no Lua code; decode it through the game's parser with a collision-free literal.
    encoded = json.dumps(settings)
    eq = '===='
    while ']' + eq + ']' in encoded:
        eq += '='
    path.write_text('local CONFIG = util.JSONToTable([' + eq + '[' + encoded + ']' + eq + '])\n' + text,
                    encoding='utf-8')


def lua_stages(path):
    """Bound each console burst; poc_session acknowledges every --lua file before the next."""
    source = path.read_bytes()
    ready = path.with_name('probe-stage-ready.lua')
    ready.write_text('-- Client Lua readiness acknowledgement before fragment transfer.\n', encoding='ascii')
    stages = [ready]
    for number, offset in enumerate(range(0, len(source), 512), 1):
        stage = path.with_name(f'probe-stage-{number:02}.lua')
        reset = 'NLVR_Q_SOURCE={}\n' if number == 1 else ''
        stage.write_text(reset + f'NLVR_Q_SOURCE[{number}]="{source[offset:offset+512].hex()}"\n',
                         encoding='ascii')
        stages.append(stage)
    stage = path.with_name('probe-stage-run.lua')
    stage.write_text('local parts=NLVR_Q_SOURCE NLVR_Q_SOURCE=nil\n'
                     'local text=table.concat(parts)\n'
                     'RunString((text:gsub("..",function(h) return string.char(tonumber(h,16)) end)),"nlvr_q_probe")\n',
                     encoding='ascii')
    return stages + [stage]


def records(console):
    found, packets = [], {}
    for line_number, line in enumerate(console.splitlines()):
        if line.startswith('NLVR_Q '):
            found.append((line_number, json.loads(line[len('NLVR_Q '):])))
        elif line.startswith('NLVR_Q_CHUNK '):
            match = re.fullmatch(r'NLVR_Q_CHUNK (\d+) (\d+)/(\d+) ([A-Za-z0-9+/=]+)', line)
            if not match:
                raise ValueError('malformed VR console packet')
            record, index, total = map(int, match.groups()[:3])
            if not 1 <= index <= total <= 1024:
                raise ValueError('invalid VR console packet count')
            packet = packets.setdefault(record, {'line': line_number, 'total': total, 'chunks': {}})
            if packet['total'] != total or index in packet['chunks']:
                raise ValueError('duplicate or inconsistent VR console packet')
            packet['chunks'][index] = match[4]
    for packet in packets.values():
        if len(packet['chunks']) != packet['total']:
            raise ValueError('incomplete VR console evidence')
        encoded = ''.join(packet['chunks'][i] for i in range(1, packet['total'] + 1))
        found.append((packet['line'], json.loads(base64.b64decode(encoded, validate=True))))
    return [record for _, record in sorted(found, key=lambda pair: pair[0])]


def overlay_bright_pixels(path):
    """Read our runtime's filter-zero RGBA8 PNG; an accepted copy must contain wrist glyphs."""
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a PNG')
    offset, header, payload = 8, None, bytearray()
    while offset + 12 <= len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset+4:offset+8]
        if offset + size + 12 > len(data):
            raise ValueError('truncated PNG')
        part = data[offset+8:offset+8+size]
        if kind == b'IHDR': header = struct.unpack('>IIBBBBB', part)
        if kind == b'IDAT': payload.extend(part)
        offset += size + 12
    if not header or header[2:] != (8,6,0,0,0):
        raise ValueError('expected runtime RGBA8 PNG')
    width, height = header[:2]
    if not 1 <= width * height <= 1048576:
        raise ValueError('invalid wrist extent')
    stride = width * 4 + 1
    decoder = zlib.decompressobj()
    raw = decoder.decompress(payload, stride * height + 1)
    if len(raw) != stride * height or not decoder.eof:
        raise ValueError('invalid wrist pixels')
    bright = 0
    for row in range(height):
        start = row * stride
        if raw[start] != 0: raise ValueError('expected runtime filter-zero PNG')
        for pixel in range(start+1, start+stride, 4):
            if min(raw[pixel:pixel+3]) > 150 and raw[pixel+3] >= 128: bright += 1
    return bright


def capture_problems(root, records):
    problems=[]
    for record in records:
        if record.get('kind')!='capture' or not record.get('ok'):
            continue
        folder=root/record['label']
        missing=[name for name in ('centre.png','centre_depth.png','left.png','right.png','mirror.png','timings.json')
                 if not (folder/name).is_file()]
        overlays=list(folder.glob('overlay_*.png'))
        if not overlays:
            missing.append('overlay PNG')
        if missing:
            problems.append(record['label']+': missing '+', '.join(missing))
        for path in overlays:
            try:
                if overlay_bright_pixels(path) < 16:
                    problems.append(record['label']+': blank wrist image '+path.name)
            except (ValueError, zlib.error, struct.error) as error:
                problems.append(record['label']+': invalid wrist image: '+str(error))
    return problems


def camera_diagnostics(log):
    fovs=[float(v) for v in re.findall(r'RTX VR camera: main,.*?FOV=([-+.0-9eE]+)',log)]
    later=sorted(fovs[1:])
    reference=later[len(later)//2] if later else (fovs[0] if fovs else None)
    return {'first_fov_radians':fovs[0] if fovs else None,'reference_fov_radians':reference,
            'first_projection_consistent':not fovs or abs(fovs[0]-reference)<0.01,
            'initial_camera_skips':log.count('RTX VR skipped initial camera:'),
            'logged_cameras':len(fovs),
            'stale_camera_frames':max([int(v) for v in re.findall(r'RTX VR stale camera:.*?skipped=(\d+)',log)] or [0]),
            'unknown_cameras':[line for line in log.splitlines() if 'RTX VR unmatched camera:' in line]}


def evaluate(folder, run, look=False):
    console = (folder / 'console.log').read_text(encoding='utf-8')
    data = records(console)
    summary = {'normal_quit': run.get('normal_quit'), 'lua_errors': run.get('lua_errors'),
               'settings_back': run.get('settings_back'), 'records': data}
    final = [r for r in data if r.get('kind') == 'done']
    summary['success'] = bool(final and final[-1].get('success') and run.get('normal_quit') and
                              run.get('settings_back') == 'restored' and not run.get('lua_errors'))
    summary['openvr_loaded_after_exit'] = any(Path(m).name.lower() == 'openvr_api.dll' for m in
                                            json.loads((folder / 'modules.json').read_text(encoding='utf-8')))
    if look and run.get('manual_end') == 'game_exited' and run.get('exit') == 0 and not run.get('failed'):
        summary['outcome'] = 'game_closed'
        summary['success'] = bool(run.get('normal_quit') and not run.get('lua_errors'))
        summary['last_observed_openvr_loaded'] = summary['openvr_loaded_after_exit']
        summary['openvr_loaded_after_exit'] = False
        summary['sdk_unloaded_by_process_exit'] = True
    if look or 'NLVR preview:' in console:
        infos=[r['info'] for r in data if r.get('kind')=='sample' and 'info' in r]
        if infos:
            summary['manual_counters']={key:max(i.get(key,0) for i in infos) for key in
                ('framesRendered','framesSubmitted','posesMatched','posesUnmatched','submitErrors','overlayUpdates')}
            summary['success'] &= not summary['manual_counters']['posesUnmatched'] and not summary['manual_counters']['submitErrors']
    if summary['openvr_loaded_after_exit'] and not (final and final[-1].get('active_shutdown')):
        summary['success'] = False
    vr_final = [r for r in data if r.get('kind') == 'final-vr']
    # Successful Submit calls do not prove progress: a consumed-camera stall can leave
    # every counter equal forever. Intentional no-scene tests are classified separately.
    if not any(r.get('kind') == 'scene-pause' for r in data):
        active = [r for r in data if r.get('kind') == 'sample' and r.get('phase') == 'active'
                  and r.get('info', {}).get('state') == 2]
        unchanged_since = None
        for a, b in zip(active, active[1:]):
            if b['info']['framesSubmitted'] == a['info']['framesSubmitted']:
                unchanged_since = a['seconds'] if unchanged_since is None else unchanged_since
                if b['seconds'] - unchanged_since > 3:
                    summary['success'] = False
                    summary['progress_failure'] = 'No new eye pair for more than three seconds in an active scene'
            else:
                unchanged_since = None
    if vr_final:
        counters = vr_final[-1]['info']
        summary['counters'] = {key: counters.get(key) for key in
            ('framesRendered', 'framesSubmitted', 'submitErrors', 'posesMatched', 'posesUnmatched',
             'presents', 'dropped', 'reprojected', 'refresh', 'eye_width', 'eye_height',
             'centreWidth', 'centreHeight', 'renderWidth', 'renderHeight', 'eyeWidth', 'eyeHeight')}
        summary['success'] &= counters.get('submitErrors') == 0 and counters.get('posesUnmatched') == 0
        summary['success'] &= counters.get('framesRendered', 0) == counters.get('framesSubmitted', -1)
    if final and not final[-1].get('active_shutdown'):
        inventory = final[-1].get('inventory', {})
        summary['success'] &= not inventory.get('timers') and all(
            h == 'PopulateToolMenu:nativeloader_vr' for h in inventory.get('hooks', []))
    summary['profiles'] = []
    log = folder / 'remix-dxvk.log'
    if log.exists():
        runtime_log=log.read_text(encoding='utf-8', errors='replace')
        summary['camera_diagnostics']=camera_diagnostics(runtime_log)
        summary['success'] &= summary['camera_diagnostics']['first_projection_consistent']
        if any(r.get('kind')=='first-camera-mismatch' for r in data):
            summary['success'] &= summary['camera_diagnostics']['initial_camera_skips'] > 0
        for line in runtime_log.splitlines():
            if 'RTX VR profile {' in line:
                summary['profiles'].append(json.loads(line.split('RTX VR profile ', 1)[1]))
    write_json(folder / 'vr-summary.json', summary)
    return summary


def analyse(summary):
    """Keep GPU command work, elapsed queue gaps and compositor timing separate."""
    data = summary['records']
    active = next((r['seconds'] for r in data if r.get('kind') == 'running'), None)
    end = next((r['seconds'] for r in data if r.get('kind') == 'final-vr'), None)
    if active is None or end is None:
        return {}
    # Long runs measure static poses after captures; shorter smokes retain the full active period.
    begin = active + (60 if end - active >= 90 else 5)
    samples = [r for r in data if r.get('kind') == 'sample' and r.get('phase') == 'active' and
               begin <= r['seconds'] <= end - 2 and r.get('info', {}).get('state') == 2]
    if len(samples) < 2:
        return {}
    first, last = samples[0], samples[-1]
    def delta(key):
        return last['info'][key] - first['info'][key]
    lower = first['camera']['sequence']
    upper = last['camera']['sequence']
    profiles = [p for p in summary['profiles'] if lower <= p['pose'] <= upper and p['coverage_known'] and
                p['untracked_submissions'] == 0]
    def mean(values):
        values = list(values)
        return sum(values) / len(values) if values else None
    passes = {name: mean(p['passes'][name]['gpu_ms'] for p in profiles)
              for name in profiles[0]['passes']} if profiles else {}
    duration = last['seconds'] - first['seconds']
    inspections = [r for r in samples if r.get('inspection', {}).get('thread_cpu_ms') is not None]
    cpu_per_pair = None
    if len(inspections) >= 2:
        a, b = inspections[0], inspections[-1]
        if a['inspection']['thread_id'] == b['inspection']['thread_id']:
            cpu_per_pair = ((b['inspection']['thread_cpu_ms'] - a['inspection']['thread_cpu_ms']) /
                            (b['info']['framesSubmitted'] - a['info']['framesSubmitted']))
    return {'window_seconds': [first['seconds'], last['seconds']], 'samples': len(samples),
            'refresh_hz': last['info']['refresh'], 'pair_fps': delta('framesSubmitted') / duration,
            'pairs': delta('framesSubmitted'), 'presents': delta('presents'), 'dropped': delta('dropped'),
            'reprojected': delta('reprojected'),
            'reprojected_percent': 100 * delta('reprojected') / delta('presents') if delta('presents') else None,
            'profiles': len(profiles), 'gpu_pass_ms': passes,
            'gpu_command_and_sdk_ms': sum(passes.values()) if passes else None,
            'gpu_elapsed_ms': mean(p['gpu_total_ms'] for p in profiles),
            'queue_gap_ms': mean(p['gpu_queue_wait_cpu_ms'] for p in profiles),
            'render_thread_cpu_ms': mean(p['render_thread_cpu_average_ms'] for p in profiles),
            'game_thread_cpu_ms_per_pair': cpu_per_pair,
            'render_injection_wall_ms': mean(p['render_injection_wall_ms'] for p in profiles),
            'compositor_app_gpu_ms': mean(r['info']['timing']['m_flTotalRenderGpuMs'] for r in samples
                                          if r['info']['timing'].get('valid')),
            'derived_80hz_native_budget_ms': 12.5, 'derived_80hz_half_budget_ms': 25.0}


def check_screenshot_dependencies():
    """Use the same interpreter/modules as capture_window and all driver sub-steps."""
    for name in ('PIL.Image', 'PIL.ImageGrab', 'PIL.ImageStat'):
        importlib.import_module(name)


def completion_arguments(look, seconds):
    return ['--lua-manual'] if look else ['--lua-shots', str(seconds + 100)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help='new folder under main/out/vr/q')
    parser.add_argument('--package', type=Path, help='local .gma or development package folder')
    parser.add_argument('--seconds', type=int, default=190)
    parser.add_argument('--render-scale', type=float, default=1)
    parser.add_argument('--fps-cap', type=float, default=0, help='test cap on the launch command line; 0 uncaps')
    parser.add_argument('--queue-mode', choices=('default','-1','0','1','2'), default='2', help='session-only mat_queue_mode; default selects engine automatic mode (-1)')
    parser.add_argument('--mcore', choices=('0','1'), help='session-only gmod_mcore_test for a threading fixture')
    parser.add_argument('--timeline', type=Path)
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--players', type=int, choices=(1, 2), default=1, help='1 single-player; 2 listen host')
    parser.add_argument('--camera', default='823,-657,-40,0,180,0', help='fixed baseline eye x,y,z,pitch,yaw,roll')
    parser.add_argument('--mount-workshop', action='append', default=[])
    parser.add_argument('--flat', action='store_true', help='flat control; do not load the VR module')
    parser.add_argument('--quit-in-vr', action='store_true')
    parser.add_argument('--pacing', choices=('render','serial'), default='render')
    parser.add_argument('--test-quit', action='store_true')
    parser.add_argument('--live-poses', action='store_true', help='real unworn HMD poses, no scripted timeline at Start')
    parser.add_argument('--first-camera-mismatch', action='store_true', help='test startup eligibility with deliberately mismatched camera metadata for five seconds')
    parser.add_argument('--expect-failure', choices=('runtime', 'module', 'steamvr', 'server', 'vrmod', 'gvrmod', 'native'),
                        help='accept this page refusal or runtime failure and require clean shutdown')
    parser.add_argument('--expect-detail', help='required literal text in an expected failure')
    parser.add_argument('--scene-pause', action='store_true')
    parser.add_argument('--exit-paused', action='store_true', help='with --scene-pause, Exit before world draws resume')
    parser.add_argument('--look', action='store_true', help='manual headset preview; type nl_vr_demo_done to restore/quit')
    parser.add_argument('--inspect-dll', type=Path, help='optional read-only evidence helper from out/ (not a package input)')
    parser.add_argument('--rollback', action='store_true', help='recover a prior interrupted preparation')
    parser.add_argument('--keep-copies', action='store_true')
    args = parser.parse_args(argv)
    camera = [float(v) for v in args.camera.split(',')]
    if len(camera) != 6 or not all(math.isfinite(v) for v in camera):
        parser.error('--camera needs six finite comma-separated numbers')
    if not args.look and not args.rollback:
        try:
            check_screenshot_dependencies()
        except (ImportError, OSError):
            print(f'vr_session: screenshots require Pillow in "{sys.executable}"; use a Python with Pillow '
                  f'or run "{sys.executable}" -m pip install pillow.', file=sys.stderr)
            return 2
    main_root = main_checkout()
    evidence = inside_out(args.evidence, main_root)
    if not 15 <= args.seconds <= 3600 or not 0.25 <= args.render_scale <= 1.5 or not 0 <= args.fps_cap <= 1000:
        parser.error('seconds must be 15..3600, render scale 0.25..1.5, FPS cap 0..1000')
    scratch = REPO / 'out/tmp'
    scratch.mkdir(parents=True, exist_ok=True)
    os.environ['TEMP'] = os.environ['TMP'] = str(scratch)
    os.environ.pop('RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES', None)
    import poc_session as poc
    with contextlib.ExitStack() as stack:
        if not args.flat:
            stack.enter_context(ExclusiveLock(main_root / 'out/vr/vr.lock', 'VR-V1-Q'))
        stack.enter_context(ExclusiveLock(main_root / 'out/r10/poc.lock', 'VR-V1-Q'))
        if args.rollback:
            restore(POC, evidence)
            if not args.keep_copies:
                cleanup(evidence)
            return 0
        if evidence.exists() and any(evidence.iterdir()):
            raise ValueError('use a new evidence folder; --rollback recovers an interrupted run')
        if not args.package or not args.package.exists():
            parser.error('--package must name an existing local package')
        evidence.mkdir(parents=True, exist_ok=True)
        inventory = subprocess.run(['powershell', '-NoProfile', '-Command',
            'Get-CimInstance Win32_Process | Where-Object { $_.Name -match "^(gmod|python|vrserver|vrcompositor|vrmonitor)\\.exe$" } | '
            'Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json -Depth 3'],
            capture_output=True, text=True)
        (evidence / 'processes-before.json').write_text(inventory.stdout, encoding='utf-8')
        for label, options in (('gpu', ['--query-gpu=name,driver_version,memory.total,utilization.gpu,memory.used']),
                               ('gpu-processes', ['--query-compute-apps=pid,process_name,used_gpu_memory'])):
            try:
                gpu = subprocess.run(['nvidia-smi', *options, '--format=csv'], capture_output=True, timeout=15)
                (evidence / (label + '.csv')).write_bytes(gpu.stdout)
            except (OSError, subprocess.TimeoutExpired) as error:
                (evidence / (label + '.txt')).write_text(str(error), encoding='utf-8')
        if poc.game_processes(POC):
            raise RuntimeError('a game is already running in the PoC')
        logs = Path(r'C:\Program Files (x86)\Steam\logs')
        offsets = {name: (logs / name).stat().st_size if (logs / name).exists() else 0
                   for name in ('vrserver.txt', 'vrcompositor.txt', 'vrmonitor.txt', 'gameprocess_log.txt')}
        protected = {str(p): sha256(p) for p in POC.rglob('user.conf')}
        write_json(evidence / 'protected-before.json', protected)
        command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'snapshot', '--root', POC,
                 '--manifests-from', FIELD], evidence, 'snapshot')
        prepared = False
        try:
            prepared = True
            preserve(POC, evidence)
            command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install',
                     '--allow-dev' if args.package.is_dir() else '--allow-local', args.package.resolve(),
                     '--remix', 'on', '--replace-config'], evidence, 'install')
            if args.inspect_dll:
                inspect_dll = inside_out(args.inspect_dll, main_root)
                destination = POC / 'garrysmod/lua/bin/gmcl_nlvrqinspect_win64.dll'
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(inspect_dll, destination)
                write_json(evidence / 'inspection-helper.json', {'source': str(inspect_dll), 'sha256': sha256(inspect_dll)})
            script = evidence / 'probe.lua'
            timeline_path = inside_out(args.timeline, main_root) if args.timeline else evidence / 'timeline.json'
            native_root=evidence/'native'
            os.environ['NLVR_TEST_ROOT']=str(native_root)
            native_timeline=native_root/'timelines/timeline.json'
            native_timeline.parent.mkdir(parents=True,exist_ok=True)
            content=json.loads(timeline_path.read_text()) if args.timeline else timeline(args.seconds)
            if args.test_quit: content['quit_at']=12
            write_json(native_timeline,content)
            if not args.timeline: write_json(timeline_path,content)
            config = {'seconds': args.seconds, 'render_scale': args.render_scale,
                      'timeline': 'timeline', 'captures': '', 'pacing':args.pacing, 'test_quit':args.test_quit,
                      'flat': args.flat, 'quit_in_vr': args.quit_in_vr, 'scene_pause': args.scene_pause,
                      'exit_paused': args.exit_paused, 'look': args.look, 'inspect': bool(args.inspect_dll),
                      'camera': camera, 'live_poses': args.live_poses, 'expect_failure': args.expect_failure,
                      'queue_mode': '-1' if args.queue_mode=='default' else args.queue_mode,
                      'expect_detail': args.expect_detail, 'mcore': args.mcore,
                      'first_camera_mismatch': args.first_camera_mismatch}
            lua_script(script, config)
            write_json(evidence / 'sources.json', {
                'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
                'driver_sha256': sha256(Path(__file__)), 'probe_sha256': sha256(script),
                'package': str(args.package.resolve()), 'config': config,
                'runtime_diagnostics': {name:os.environ.get(name) for name in
                    ('RTX_VR_WARP_TAPS','RTX_VR_TEST_ALLOCATION_FAILURE','RTX_VR_TEST_FOCUS_INTERVALS')}})
            threading_args=['--extra=+gmod_mcore_test','--extra='+args.mcore] if args.mcore is not None else []
            run_args = ['tools/poc_session.py', '--evidence', evidence / 'poc', 'run', '--name', 'game', '--addons', '--players', str(args.players),
                        '--map', 'gm_construct' if args.mount_workshop else args.map,
                        '--extra=-insecure', '--extra=+fps_max', f'--extra={args.fps_cap:g}', *threading_args,
                        '--extra=+mat_queue_mode', '--extra='+config['queue_mode'],
                        '--console', f'lua_run local p=Entity(1) p:SetMoveType(MOVETYPE_NOCLIP) p:SetPos(Vector({camera[0]},{camera[1]},{camera[2]-64})) p:SetEyeAngles(Angle({camera[3]},{camera[4]},{camera[5]})) p:SetHealth(87) p:SetArmor(31) p:Give("weapon_pistol") p:SelectWeapon("weapon_pistol")']
            hud_code = 'concommand.Add("nlvr_q_hud",function(p,c,a) p=Entity(1) local w=p:GetActiveWeapon() if not IsValid(w) then return end if a[1]=="restore" then local s=NLVRQSaved if s then p:SetHealth(s[1]) p:SetArmor(s[2]) w:SetClip1(s[3]) p:SetAmmo(s[4],w:GetPrimaryAmmoType()) end else NLVRQSaved={p:Health(),p:Armor(),w:Clip1(),p:GetAmmoCount(w:GetPrimaryAmmoType())} p:SetHealth(63) p:SetArmor(47) w:SetClip1(9) p:SetAmmo(54,w:GetPrimaryAmmoType()) end end)'
            for line in poc.client_lua_lines('vr_hud', hud_code):
                run_args += ['--console', line.replace('lua_run_cl', 'lua_run', 1)]
            for stage in lua_stages(script):
                run_args += ['--lua', stage]
            run_args += completion_arguments(args.look, args.seconds)
            run_args += ['--settle', '1', '--screenshots', '0', '--timeout', '600']
            if args.mount_workshop:
                run_args += ['--change-map', args.map]
                for item in args.mount_workshop:
                    run_args += ['--mount-workshop', item]
            command(run_args, evidence, 'game', allowed=(0, 1))
            history = json.loads((evidence / 'poc/session.json').read_text(encoding='utf-8'))
            if (native_root/'captures').exists(): shutil.copytree(native_root/'captures',evidence/'captures',dirs_exist_ok=True)
            summary = evaluate(evidence / 'poc/game', history[-1], look=args.look)
            if history[-1].get('failed'):
                summary['failure'] = history[-1]['failed']
            summary['capture_problems']=capture_problems(evidence/'captures',summary['records']) if not any(
                r.get('kind')=='expected-failure' for r in summary['records']) else []
            summary['success'] &= not summary['capture_problems']
            summary['steady'] = analyse(summary)
            write_json(evidence / 'summary.json', summary)
        finally:
            if prepared and (evidence / 'originals.json').exists():
                restore(POC, evidence)
            for name, offset in offsets.items():
                (evidence / name).write_text(poc.read_shared(logs / name, offset), encoding='utf-8')
            write_json(evidence / 'protected-after.json', {p: sha256(Path(p)) for p in protected})
            if any(sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        if not args.keep_copies:
            cleanup(evidence)
        if summary.get('outcome') == 'game_closed':
            print('Manual look ended when the game exited with code 0; PoC restored. '
                  'Live settings restoration was unavailable after exit; the snapshot was restored.', flush=True)
        elif not summary['success']:
            print(f'VR session failed: {summary.get("failure", "acceptance checks did not pass")}; '
                  f'PoC restored; see {evidence / "summary.json"}.', flush=True)
        return 0 if summary['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
