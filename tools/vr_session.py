"""Snapshot, run and restore live or simulated PoC VR; never configure or stop SteamVR."""
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
import vr_crash

REPO = Path(__file__).resolve().parents[1]
POC = Path(r'H:\SteamLibrary\steamapps\common\GarrysMod_PoC')
FIELD = POC.with_name('GarrysMod')
ROOTS = ('native-loader', 'garrysmod/addons', 'garrysmod/data', 'garrysmod/settings',
         'garrysmod/lua/bin', 'rtx-remix/mods', 'rtx-remix/logs', 'rtx-remix/captures')
FILES = ('bin/win64/winmm.dll', 'bin/win64/winmm.pdb', 'garrysmod/cfg/nativeloader_session.cfg')
MARKER = re.compile(r'^NLVR_Q (\{.*\})\s*$', re.M)
_RETRY_TOKEN=uuid.uuid4().hex


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


def require_free_space(path, minimum_gib):
    existing=path
    while not existing.exists():existing=existing.parent
    free=shutil.disk_usage(existing).free
    required=minimum_gib*(1<<30)
    if free<required:
        raise RuntimeError(f'evidence volume has {free} free bytes; reserve {required} bytes before preparation')
    return {'free_bytes':free,'required_bytes':required,'volume_path':str(existing)}


def pending_transaction(main):
    return main/'out/r10/vr-poc-pending.json'


def require_clean_transaction(main):
    marker=pending_transaction(main)
    if marker.exists():
        data=json.loads(marker.read_text(encoding='utf-8'))
        raise RuntimeError(f'PoC has an unfinished VR transaction; recover with --rollback --evidence {data["evidence"]}')


def begin_transaction(main,evidence):
    require_clean_transaction(main)
    marker=pending_transaction(main);marker.parent.mkdir(parents=True,exist_ok=True)
    with marker.open('x',encoding='utf-8') as stream:
        json.dump({'schema':1,'evidence':str(evidence.resolve()),'root':str(POC.resolve()),'pid':os.getpid()},stream)
        stream.flush();os.fsync(stream.fileno())


def complete_transaction(main,evidence):
    validate_recovery_transaction(main,evidence)
    marker=pending_transaction(main)
    if not marker.exists():return  # legacy interrupted sessions predate the marker
    marker.unlink()


def validate_recovery_transaction(main,evidence):
    marker=pending_transaction(main)
    if not marker.exists():return
    data=json.loads(marker.read_text(encoding='utf-8'))
    if Path(data['evidence']).resolve()!=evidence.resolve() or Path(data['root']).resolve()!=POC.resolve():
        raise ValueError('unfinished transaction belongs to a different recovery')


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


def restore(root, evidence, manifests=None):
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
    depot_args=[part for path in manifests or () for part in ('--manifest',str(path))]
    command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'rollback', '--config', 'Release',*depot_args],
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
    deduplicate_captures(evidence)
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


def deduplicate_captures(evidence):
    """Retain every raw capture once; discard only independently hash-verified duplicate copies."""
    if not json.loads((evidence/'restoration.json').read_text(encoding='utf-8'))['clean']:
        raise ValueError('capture deduplication requires verified clean restoration')
    source, retained = evidence/'native/captures', evidence/'captures'
    if not source.exists():
        return
    for root in (source, retained):
        if not root.resolve().is_relative_to(evidence.resolve()) or linked(root):
            raise ValueError('capture copy escapes owned evidence')
    files=[]
    for path in sorted(source.rglob('*')):
        if linked(path):
            raise ValueError('linked capture is not an owned ordinary file')
        if not path.is_file():
            continue
        rel=path.relative_to(source)
        other=retained/rel
        if not other.is_file() or linked(other) or path.stat().st_size!=other.stat().st_size:
            raise ValueError('capture duplicate is missing/different: '+str(rel))
        digest=sha256(path)
        if digest!=sha256(other):
            raise ValueError('capture duplicate hash differs: '+str(rel))
        files.append({'path':rel.as_posix(),'bytes':path.stat().st_size,'sha256':digest})
    write_json(evidence/'capture-deduplication.json', {'source':'native/captures','retained':'captures',
               'files':files,'bytes':sum(f['bytes'] for f in files),'all_bytes_verified':True})
    shutil.rmtree(source)


def collect_captures(native_root, evidence):
    """The owned game has exited: retain generated captures by a same-volume directory rename."""
    source,retained=native_root/'captures',evidence/'captures'
    if not source.exists():
        return
    boundary=evidence.resolve()
    for root in (source,retained):
        if not root.resolve().is_relative_to(boundary) or linked(root):
            raise ValueError('capture collection escapes owned evidence')
    if retained.exists():
        raise ValueError('retained capture destination already exists')
    source.rename(retained)
    write_json(evidence/'capture-collection.json',{'source':'native/captures','retained':'captures',
               'method':'same-volume directory rename after the owned game exited; raw files unchanged'})


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


def simulation_adapter():
    """A generated-test-only virtual-backend availability shim, not a native authorization bypass."""
    return '''-- V1's page requires SteamVR installation even for an explicit virtual test backend.
require("nlvr")
local function simulated_start(options)
    options.simulate = true
    local probe = nlvr.Probe
    local actual, detail = probe()
    if type(actual) ~= "table" then return false, detail end
    local virtual = {} for key, value in pairs(actual) do virtual[key] = value end
    virtual.steamvr_installed = true -- Availability for this one virtual-backend Start only.
    nlvr.Probe = function() return virtual end
    local called, success, message = pcall(NativeLoaderVR.Start, options)
    nlvr.Probe = probe
    NativeLoaderVR.probe = actual -- Records and later probes keep the real installation facts.
    if not called then error(success) end
    return success, message
end
'''


def lua_script(path, settings):
    text = Path(__file__).with_suffix('.lua').read_text(encoding='utf-8')
    text=text.replace('__CAPTURE_QUEUE__',Path(__file__).with_name('vr_capture_queue.lua').read_text(encoding='utf-8'))
    if settings.get('simulate'):
        # Keep the accepted V1 probe untouched. Only the generated simulated probe changes:
        # real submission counters cannot establish progress when there is no compositor.
        changes = {
            'NativeLoaderVR.Start({timeline = not CONFIG.live_poses and CONFIG.timeline or nil, pacing = CONFIG.pacing})':
                'simulated_start({simulate = true, timeline = CONFIG.timeline, pacing = CONFIG.pacing})',
            'RunConsoleCommand("nl_vr_start", CONFIG.timeline)':
                'simulated_start({simulate = true, timeline = CONFIG.timeline, pacing = CONFIG.pacing})',
        }
        for before, after in changes.items():
            if text.count(before) != 1:
                raise ValueError('simulation adapter no longer matches the accepted probe: ' + before)
            text = text.replace(before, after)
        text = text.replace('native.Info().framesSubmitted', 'native.Info().framesRendered')
        text = text.replace('start did not reach submitted frames', 'simulation did not reach rendered frames')
        text = simulation_adapter() + text
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


def overlay_pixels(path):
    """Decode bounded runtime RGBA8 canvases without a Pillow dependency or size-based roles."""
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
    if not (1 <= width <= 4095 and 1 <= height <= 4095):
        raise ValueError('invalid overlay extent')
    stride = width * 4 + 1
    decoder = zlib.decompressobj()
    raw = decoder.decompress(payload, stride * height + 1)
    if len(raw) != stride * height or not decoder.eof:
        raise ValueError('invalid overlay pixels')
    rows = []
    for row in range(height):
        start = row * stride
        if raw[start] != 0: raise ValueError('expected runtime filter-zero PNG')
        rows.append(raw[start+1:start+stride])
    pixels = b''.join(rows)
    return width, height, pixels


def overlay_bright_pixels(path):
    """Wrist glyph metric; role comes from the probe's handle manifest, never dimensions."""
    _, _, pixels = overlay_pixels(path)
    return sum(min(pixels[p:p+3]) > 150 and pixels[p+3] >= 128 for p in range(0, len(pixels), 4))


def capture_problems(root, records):
    problems=[]
    manifests = {r['label']: r['overlays'] for r in records if r.get('kind') == 'overlay-roles'}
    expectations={r['label']:r.get('expected_roles',{'wrist':True}) for r in records if r.get('kind')=='overlay-roles'}
    roles = {'wrist', 'wrist_menu', 'spawn', 'context', 'flat', 'flat_close', 'settings', 'keyboard',
             'laser', 'teleport_arc', 'teleport_arc_2', 'teleport_arc_3', 'teleport_target', 'vignette', 'ghost_left', 'ghost_right',
             'gloves_left', 'gloves_right', 'ammo', 'tool', 'wheel'}
    for record in records:
        if record.get('kind')!='capture' or not record.get('ok'):
            continue
        folder=root/record['label']
        missing=[name for name in ('centre.png','centre_depth.png','left.png','right.png','mirror.png','timings.json')
                 if not (folder/name).is_file()]
        overlays=list(folder.glob('overlay_*.png'))
        declared='overlays' in record or record['label'] in manifests
        manifest = record.get('overlays', manifests.get(record['label'], {})) or {}
        expected=set(record.get('expected_roles',expectations.get(record['label'],{'wrist':True})) or {})
        if not overlays and (not declared or manifest or expected):
            missing.append('overlay PNG')
        if missing:
            problems.append(record['label']+': missing '+', '.join(missing))
        images={path.stem.removeprefix('overlay_') for path in overlays}
        for handle,item in manifest.items():
            if str(handle) not in images and (item.get('required') or item.get('role') in expected or item.get('info',{}).get('visible',True)):
                problems.append(record['label']+': missing declared overlay '+str(handle))
        for role in expected:
            matching=[(h,d) for h,d in manifest.items() if d.get('role')==role]
            if not matching or not any(str(h) in images for h,_ in matching):
                problems.append(record['label']+': missing expected role '+role)
            if any(d.get('required') and not d.get('handle') for _,d in matching):
                problems.append(record['label']+': expected role has no native handle '+role)
        expects_wrist=any(item.get('role')=='wrist' for item in manifest.values())
        wrist = False
        for path in overlays:
            handle = path.stem.removeprefix('overlay_')
            descriptor = manifest.get(handle, {})
            role = descriptor.get('role')
            if role not in roles and not (isinstance(role, str) and re.fullmatch(r'move_arc_[2-8]', role)):
                problems.append(record['label']+': overlay role missing or unknown for '+path.name)
                continue
            wrist |= role == 'wrist'
            try:
                width, height, pixels = overlay_pixels(path)
                if descriptor.get('kind') == 'window':
                    if width > 1920:
                        problems.append(record['label']+': window source exceeds its 1920-pixel bound')
                    window=descriptor.get('window')
                    if window and abs(width/height-window[0]/window[1]) > 1/min(width,height):
                        problems.append(record['label']+': window source aspect differs from its declared window')
                elif descriptor.get('expected') and [width,height] != descriptor['expected']:
                    problems.append(record['label']+': '+role+' extent differs from its declared source')
                if role == 'wrist':
                    if overlay_bright_pixels(path) < 16:
                        problems.append(record['label']+': blank wrist image '+path.name)
                elif descriptor.get('info', {}).get('visible') and not any(pixels[3::4]):
                    problems.append(record['label']+': empty visible '+role+' image '+path.name)
            except (ValueError, zlib.error, struct.error) as error:
                problems.append(record['label']+': invalid '+role+' image: '+str(error))
        if expects_wrist and not wrist:
            problems.append(record['label']+': missing wrist role')
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


def evaluate(folder, run, look=False, simulate=False):
    console = (folder / 'console.log').read_text(encoding='utf-8')
    data = records(console)
    summary = {'normal_quit': run.get('normal_quit'), 'lua_errors': run.get('lua_errors'),
               'settings_back': run.get('settings_back'), 'records': data}
    summary['module_failures'] = [line for line in console.splitlines() if re.search(r'\[nlvr\] (?:module|cleanup|stop) ', line)]
    if simulate:
        summary['simulated'] = True
        summary['progress_counter'] = 'framesRendered'
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
    if simulate:
        summary['success'] &= not any(r['info'].get('openvr_loaded') for r in data if 'info' in r)
        if not any(r.get('kind') == 'expected-failure' for r in data):
            summary['success'] &= bool(vr_final)
    # Successful Submit calls do not prove progress: a consumed-camera stall can leave
    # every counter equal forever. Intentional no-scene tests are classified separately.
    if not any(r.get('kind') == 'scene-pause' for r in data):
        active = [r for r in data if r.get('kind') == 'sample' and r.get('phase') == 'active'
                  and r.get('info', {}).get('state') == 2]
        unchanged_since = None
        for a, b in zip(active, active[1:]):
            metric = 'framesRendered' if simulate else 'framesSubmitted'
            if b['info'].get(metric) == a['info'].get(metric):
                unchanged_since = a['seconds'] if unchanged_since is None else unchanged_since
                if b['seconds'] - unchanged_since > 3:
                    summary['success'] = False
                    summary['progress_failure'] = ('No new rendered frame' if simulate else 'No new eye pair') + ' for more than three seconds in an active scene'
            else:
                unchanged_since = None
    if vr_final:
        counters = vr_final[-1]['info']
        summary['counters'] = {key: counters.get(key) for key in
            ('framesRendered', 'framesSubmitted', 'submitErrors', 'posesMatched', 'posesUnmatched',
             'presents', 'dropped', 'reprojected', 'refresh', 'eye_width', 'eye_height',
             'centreWidth', 'centreHeight', 'renderWidth', 'renderHeight', 'eyeWidth', 'eyeHeight', 'simulated')}
        summary['success'] &= counters.get('submitErrors') == 0 and counters.get('posesUnmatched') == 0
        if simulate:
            infos = [r['info'] for r in data if r.get('info', {}).get('simulated')]
            summary['success'] &= bool(infos) and counters.get('simulated') is True
            summary['success'] &= counters.get('framesRendered', 0) > 0 and counters.get('framesSubmitted') == 0
            summary['success'] &= not any(r['info'].get('openvr_loaded') for r in data if 'info' in r)
        else:
            summary['success'] &= counters.get('framesRendered', 0) == counters.get('framesSubmitted', -1)
    summary['success'] &= not summary['module_failures']
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
    simulated = summary.get('simulated', False)
    metric = 'framesRendered' if simulated else 'framesSubmitted'
    inspections = [r for r in samples if r.get('inspection', {}).get('thread_cpu_ms') is not None]
    cpu_per_pair = None
    if len(inspections) >= 2:
        a, b = inspections[0], inspections[-1]
        if a['inspection']['thread_id'] == b['inspection']['thread_id']:
            cpu_per_pair = ((b['inspection']['thread_cpu_ms'] - a['inspection']['thread_cpu_ms']) /
                            (b['info'][metric] - a['info'][metric]))
    return {'window_seconds': [first['seconds'], last['seconds']], 'samples': len(samples),
            'refresh_hz': last['info']['refresh'], 'pair_fps': None if simulated else delta(metric) / duration,
            'frame_fps': delta(metric) / duration, 'progress_counter': metric,
            'pairs': 0 if simulated else delta(metric), 'presents': delta('presents'), 'dropped': delta('dropped'),
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


def window_size(value):
    match = re.fullmatch(r'(\d+)[xX](\d+)', value.strip())
    if not match:
        raise argparse.ArgumentTypeError('window must be WIDTHxHEIGHT, for example 3840x2160')
    width, height = map(int, match.groups())
    if not 320 <= width <= 7680 or not 240 <= height <= 4320:
        raise argparse.ArgumentTypeError('window must be 320..7680 pixels wide and 240..4320 high')
    return width, height


def needs_vr_lock(args):
    # Every PoC mode uses the GPU; the user's shared-session rule includes simulation and flat controls.
    return True


def prepare_native_data(native_root, timeline_content, simulate):
    write_json(native_root / 'timelines/timeline.json', timeline_content)
    if simulate:
        source = REPO / 'vr/native/sim/index-v1.json'
        destination = native_root / 'simulated-index.json'
        shutil.copyfile(source, destination)
        write_json(native_root / 'simulated-index-source.json', {'source': str(source), 'sha256': sha256(source)})


def _main_once(argv=None):
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
    parser.add_argument('--simulate', action='store_true', help='test-only timer-paced VR, without OpenVR or a VR lock')
    parser.add_argument('--both-locks',action='store_true',help='also hold the shared VR lock for a simulated/flat PoC run')
    parser.add_argument('--window', type=window_size, default=(1280, 720), help='game window WIDTHxHEIGHT, default 1280x720')
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
    parser.add_argument('--depot-manifest',type=Path,action='append',help='stock depot manifest describing a pinned PoC revision, repeated per depot; verification remains mandatory')
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--minimum-free-gib',type=int,default=8,help='evidence-volume reserve before preparation, checked again after waiting for locks')
    args = parser.parse_args(argv)
    if args.simulate and (args.flat or args.look or args.live_poses):
        parser.error('--simulate requires an unattended scripted session, not --flat/--look/--live-poses')
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
    if args.minimum_free_gib<1:parser.error('minimum free space must be at least one GiB')
    if not args.rollback:
        try:require_free_space(evidence,args.minimum_free_gib)
        except RuntimeError as error:
            print('vr_session: '+str(error),file=sys.stderr)
            return 2
    if not 15 <= args.seconds <= 3600 or not 0.25 <= args.render_scale <= 1.5 or not 0 <= args.fps_cap <= 1000:
        parser.error('seconds must be 15..3600, render scale 0.25..1.5, FPS cap 0..1000')
    scratch = REPO / 'out/tmp'
    scratch.mkdir(parents=True, exist_ok=True)
    os.environ['TEMP'] = os.environ['TMP'] = str(scratch)
    os.environ.pop('RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES', None)
    import poc_session as poc
    with contextlib.ExitStack() as stack:
        if needs_vr_lock(args):
            stack.enter_context(ExclusiveLock(main_root / 'out/vr/vr.lock', 'VR-V1-Q'))
        stack.enter_context(ExclusiveLock(main_root / 'out/r10/poc.lock', 'VR-V1-Q'))
        if args.rollback:
            validate_recovery_transaction(main_root,evidence)
            restore(POC, evidence, **({'manifests':args.depot_manifest} if args.depot_manifest else {}))
            complete_transaction(main_root,evidence)
            if not args.keep_copies:
                cleanup(evidence)
            return 0
        require_clean_transaction(main_root)
        if evidence.exists() and any(evidence.iterdir()):
            raise ValueError('use a new evidence folder; --rollback recovers an interrupted run')
        if not args.package or not args.package.exists():
            parser.error('--package must name an existing local package')
        space=require_free_space(evidence,args.minimum_free_gib)
        evidence.mkdir(parents=True, exist_ok=True)
        write_json(evidence/'space-before.json',space)
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
                 '--manifests-from', FIELD,*[part for path in args.depot_manifest or () for part in ('--manifest',str(path))]], evidence, 'snapshot')
        prepared = False
        try:
            begin_transaction(main_root,evidence)
            prepared = True
            preserve(POC, evidence)
            command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install',
                     '--allow-dev' if args.package.is_dir() else '--allow-local', args.package.resolve(),
                     '--remix', 'on', '--replace-config'], evidence, 'install')
            if args.inspect_dll:
                inspect_dll = inside_out(args.inspect_dll, main_root)
                destinations = [POC / ('garrysmod/lua/bin/'+realm+'_nlvrqinspect_win64.dll')
                                for realm in ('gmcl','gmsv')]
                for destination in destinations:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(inspect_dll, destination)
                write_json(evidence / 'inspection-helper.json', {'source': str(inspect_dll), 'sha256': sha256(inspect_dll),
                                                               'destinations': [str(p) for p in destinations]})
            script = evidence / 'probe.lua'
            timeline_path = inside_out(args.timeline, main_root) if args.timeline else evidence / 'timeline.json'
            native_root=evidence/'native'
            os.environ['NLVR_TEST_ROOT']=str(native_root)
            content=json.loads(timeline_path.read_text()) if args.timeline else timeline(args.seconds)
            if args.test_quit: content['quit_at']=12
            prepare_native_data(native_root,content,args.simulate)
            if not args.timeline: write_json(timeline_path,content)
            config = {'seconds': args.seconds, 'render_scale': args.render_scale,
                      'timeline': 'timeline', 'captures': '', 'pacing':args.pacing, 'test_quit':args.test_quit,
                      'flat': args.flat, 'quit_in_vr': args.quit_in_vr, 'scene_pause': args.scene_pause,
                      'exit_paused': args.exit_paused, 'look': args.look, 'inspect': bool(args.inspect_dll),
                      'camera': camera, 'live_poses': args.live_poses, 'expect_failure': args.expect_failure,
                      'queue_mode': '-1' if args.queue_mode=='default' else args.queue_mode,
                      'expect_detail': args.expect_detail, 'mcore': args.mcore,
                      'first_camera_mismatch': args.first_camera_mismatch, 'simulate': args.simulate,
                      'window': args.window}
            lua_script(script, config)
            write_json(evidence / 'sources.json', {
                'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
                'driver_sha256': sha256(Path(__file__)), 'probe_sha256': sha256(script),
                'package': str(args.package.resolve()), 'config': config,
                'runtime_diagnostics': {name:os.environ.get(name) for name in
                    ('RTX_VR_WARP_TAPS','RTX_VR_TEST_ALLOCATION_FAILURE','RTX_VR_TEST_FOCUS_INTERVALS')}})
            threading_args=['--extra=+gmod_mcore_test','--extra='+args.mcore] if args.mcore is not None else []
            run_args = ['tools/poc_session.py', '--evidence', evidence / 'poc', 'run', '--name', 'game', '--addons', '--players', str(args.players),
                        '--width', str(args.window[0]), '--height', str(args.window[1]),
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
            wer_copy=None
            if vr_crash.crashed(history[-1]):
                try:wer_copy=vr_crash.copy_wer_dump(vr_crash.WER_SOURCE,evidence,int(history[-1]['pid']))
                except (OSError,ValueError,KeyError) as error:wer_copy={'error':str(error)}
            collect_captures(native_root,evidence)
            summary = evaluate(evidence / 'poc/game', history[-1], look=args.look, simulate=args.simulate)
            if history[-1].get('failed'):
                summary['failure'] = history[-1]['failed']
            summary['capture_problems']=capture_problems(evidence/'captures',summary['records']) if not any(
                r.get('kind')=='expected-failure' for r in summary['records']) else []
            summary['success'] &= not summary['capture_problems']
            crash=vr_crash.record_crash(evidence,history[-1],summary['records'],
                prior_crash=bool(os.environ.get('NLVR_CRASH_RETRY_OF')),wer_copy=wer_copy)
            if crash:
                summary['crash']=crash
                summary['success']=False
            summary['steady'] = analyse(summary)
            write_json(evidence / 'summary.json', summary)
        finally:
            if prepared and (evidence / 'originals.json').exists():
                restore(POC, evidence, **({'manifests':args.depot_manifest} if args.depot_manifest else {}))
            for name, offset in offsets.items():
                (evidence / name).write_text(poc.read_shared(logs / name, offset), encoding='utf-8')
            write_json(evidence / 'protected-after.json', {p: sha256(Path(p)) for p in protected})
            if any(sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
            if prepared and (evidence/'restoration.json').exists() and json.loads((evidence/'restoration.json').read_text())['clean']:
                complete_transaction(main_root,evidence)
        if not args.keep_copies:
            cleanup(evidence)
        if summary.get('outcome') == 'game_closed':
            print('Manual look ended when the game exited with code 0; PoC restored. '
                  'Live settings restoration was unavailable after exit; the snapshot was restored.', flush=True)
        elif not summary['success']:
            print(f'VR session failed: {summary.get("failure", "acceptance checks did not pass")}; '
                  f'PoC restored; see {evidence / "summary.json"}.', flush=True)
        return 0 if summary['success'] else 1


def evidence_argument(arguments):
    for i,value in enumerate(arguments):
        if value=='--evidence' and i+1<len(arguments):return i+1,arguments[i+1],False
        if value.startswith('--evidence='):return i,value.split('=',1)[1],True
    raise ValueError('no reproducible --evidence argument')


def claim_crash_retry(parent,target,pid,token):
    marker=parent/'crash-retry-used.json'
    value={'pid':pid,'token':token,'evidence':str(target),'attempt':1}
    try:
        with marker.open('x',encoding='utf-8') as stream:json.dump(value,stream)
    except FileExistsError:
        existing=json.loads(marker.read_text(encoding='utf-8'))
        if existing!=value:raise RuntimeError('this crash already used its one retry')


def main(argv=None):
    """A known crash retries the complete caller CLI, so its semantic reducers run too."""
    arguments=list(sys.argv[1:] if argv is None else argv)
    prior=os.environ.get('NLVR_CRASH_RETRY_OF')
    if prior:
        parent=inside_out(Path(prior),main_checkout())
        known=json.loads((parent/'crash.json').read_text(encoding='utf-8'))
        restored=json.loads((parent/'restoration.json').read_text(encoding='utf-8'))
        if not vr_crash.retry_allowed(known) or not known.get('retry_eligible') or not restored.get('clean'):
            raise RuntimeError('retry requires one known crash and verified parent restoration')
        _,target,_=evidence_argument(list(sys.argv[1:]))
        target=inside_out(Path(target),main_checkout())
        if target==parent:raise RuntimeError('retry needs a fresh evidence folder')
        claim_crash_retry(parent,target,os.getpid(),_RETRY_TOKEN)
    code=_main_once(arguments)
    if code!=1 or prior:return code
    try:
        _,folder,_=evidence_argument(arguments)
        if not (Path(folder).resolve()/'crash.json').is_file():return code
        evidence=inside_out(Path(folder),main_checkout())
        receipt=json.loads((evidence/'crash.json').read_text(encoding='utf-8'))
    except (ValueError,OSError):return code
    if not receipt.get('retry_eligible') or not vr_crash.retry_allowed(receipt):return code
    restored=json.loads((evidence/'restoration.json').read_text(encoding='utf-8'))
    if not restored.get('clean'):return code
    try:
        entry=Path(sys.argv[0]).resolve()
        if entry.suffix!='.py' or not entry.is_file() or not entry.is_relative_to(REPO.resolve()):
            raise ValueError('caller is not a reproducible repository script')
        cli=list(sys.argv[1:]);index,original,equals=evidence_argument(cli)
        original=inside_out(Path(original),main_checkout())
        fresh=original.with_name(original.name+'-retry1')
        n=2
        while fresh.exists():
            fresh=original.with_name(original.name+f'-retry1-{n}');n+=1
        cli[index]=('--evidence=' if equals else '')+str(fresh)
    except ValueError as error:
        receipt['retry_not_started']=str(error);write_json(evidence/'crash.json',receipt);return code
    receipt['retry']={'evidence':str(fresh),'entry':str(entry),'attempt':1}
    write_json(evidence/'crash.json',receipt)
    print(f'Known crash {receipt["classification"]}; restored; retrying once in {fresh.name}.',flush=True)
    environment=os.environ.copy();environment['NLVR_CRASH_RETRY_OF']=str(evidence)
    result=subprocess.run([sys.executable,'-B',str(entry),*cli],cwd=REPO,env=environment)
    receipt['retry']['exit']=result.returncode;write_json(evidence/'crash.json',receipt)
    # Exit the original caller too: it must not analyze the failed parent as if it
    # were the child. The complete child CLI has performed its own semantic checks.
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    raise SystemExit(main())
