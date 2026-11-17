"""remix_workers_session.py: the RTX runtime's geometry workers (runtime patch 0105, ADR 0243) measured in the PoC.

For packages that differ only in d3d9.dll, alternately: the CPU time of each `geometry-processing(N)` thread (and of
the game's other threads) in the main menu at start, in gm_construct with a fixed camera and after returning to the
menu; and the frame times in the map. Holds out/r10/poc.lock for one session at a time (exclusive create, waits for
another owner, removes only its own); each session keeps the PoC's native-loader/config.json byte for byte and GMod's
video settings in the registry value for value, and puts both back before the lock goes. See
remix_workers_session.py.md."""
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
import winreg
from ctypes import wintypes
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import poc_session as poc  # noqa: E402
import vr_session as vs  # noqa: E402

POC = vs.POC
CONFIG = POC / 'native-loader' / 'config.json'
VIDEO_KEY = r'Software\Valve\Source\garrysmod\Settings'
CAMERA = [823.0, -657.0, -40.0, 8.0, 180.0, 0.0]  # gm_construct, facing west (the queued-draws lab's view)
GEOMETRY = re.compile(r'^geometry-processing\(\d+\)$')
PROBE = re.compile(r'(?m)^NL_RW_PROBE\s*$')
START = re.compile(r'(?m)^NL_RW_START\s*$')
END = re.compile(r'(?m)^NL_RW_END\s*$')
FRAMES = re.compile(r'(?m)^NL_RW_FPS (\{.*\})\s*$')
BUSY_NAMES = re.compile(r'^(gmod|hl2|cl|link|ninja|slangc|glslangValidator|dxc|msbuild|vrserver|vrcompositor)\.exe$', re.I)

# ---------------------------------------------------------------- CPU time of threads, the process and the machine

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
TH32CS_SNAPTHREAD = 0x00000004
THREAD_QUERY_LIMITED_INFORMATION = 0x0800
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value


class THREADENTRY32(ctypes.Structure):
    _fields_ = [('dwSize', wintypes.DWORD), ('cntUsage', wintypes.DWORD), ('th32ThreadID', wintypes.DWORD),
                ('th32OwnerProcessID', wintypes.DWORD), ('tpBasePri', wintypes.LONG), ('tpDeltaPri', wintypes.LONG),
                ('dwFlags', wintypes.DWORD)]


FILETIME_P = ctypes.POINTER(wintypes.FILETIME)
kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
kernel32.Thread32First.argtypes = [wintypes.HANDLE, ctypes.POINTER(THREADENTRY32)]
kernel32.Thread32Next.argtypes = [wintypes.HANDLE, ctypes.POINTER(THREADENTRY32)]
kernel32.OpenThread.restype = wintypes.HANDLE
kernel32.OpenThread.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.GetThreadTimes.argtypes = [wintypes.HANDLE, FILETIME_P, FILETIME_P, FILETIME_P, FILETIME_P]
kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE, FILETIME_P, FILETIME_P, FILETIME_P, FILETIME_P]
kernel32.GetSystemTimes.argtypes = [FILETIME_P, FILETIME_P, FILETIME_P]
kernel32.GetThreadDescription.restype = ctypes.c_long
kernel32.GetThreadDescription.argtypes = [wintypes.HANDLE, ctypes.POINTER(ctypes.c_void_p)]
kernel32.LocalFree.argtypes = [ctypes.c_void_p]
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]


def ticks(value: wintypes.FILETIME) -> int:
    return (value.dwHighDateTime << 32) | value.dwLowDateTime


def thread_times(pid: int) -> dict[int, tuple[str, int]]:
    """{thread id: (description, user + kernel time in 100 ns units)} of every thread of a process."""
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
    if snapshot in (None, INVALID_HANDLE_VALUE):
        raise ctypes.WinError(ctypes.get_last_error())
    found = {}
    try:
        entry = THREADENTRY32()
        entry.dwSize = ctypes.sizeof(entry)
        more = kernel32.Thread32First(snapshot, ctypes.byref(entry))
        while more:
            if entry.th32OwnerProcessID == pid:
                handle = kernel32.OpenThread(THREAD_QUERY_LIMITED_INFORMATION, False, entry.th32ThreadID)
                if handle:
                    try:
                        times = [wintypes.FILETIME() for _ in range(4)]
                        if kernel32.GetThreadTimes(handle, *map(ctypes.byref, times)):
                            name, text = '', ctypes.c_void_p()
                            if kernel32.GetThreadDescription(handle, ctypes.byref(text)) >= 0 and text.value:
                                name = ctypes.wstring_at(text.value)
                                kernel32.LocalFree(text)
                            found[entry.th32ThreadID] = (name, ticks(times[2]) + ticks(times[3]))
                    finally:
                        kernel32.CloseHandle(handle)
            more = kernel32.Thread32Next(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return found


def process_time(pid: int) -> int:
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return 0
    try:
        times = [wintypes.FILETIME() for _ in range(4)]
        return ticks(times[2]) + ticks(times[3]) if kernel32.GetProcessTimes(handle, *map(ctypes.byref, times)) else 0
    finally:
        kernel32.CloseHandle(handle)


def system_times() -> tuple[int, int]:
    """(idle, total) time of every logical processor, 100 ns units."""
    idle, kernel, user = wintypes.FILETIME(), wintypes.FILETIME(), wintypes.FILETIME()
    kernel32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kernel), ctypes.byref(user))
    return ticks(idle), ticks(kernel) + ticks(user)  # kernel time includes idle time


def sample(pid: int) -> dict:
    return {'at': time.perf_counter(), 'threads': thread_times(pid), 'process': process_time(pid),
            'system': system_times()}


def usage(a: dict, b: dict) -> dict:
    """What each thread used between two samples, in percent of one core, by thread name (unnamed threads by id)."""
    seconds = b['at'] - a['at']
    scale = 100.0 / (seconds * 1e7)
    by_name: dict[str, float] = {}
    for tid, (name, spent) in b['threads'].items():
        before = a['threads'].get(tid, (name, 0))[1]  # a thread started in between counts from zero
        key = name or f'thread {tid}'
        by_name[key] = by_name.get(key, 0.0) + (spent - before) * scale
    geometry = {name: round(value, 1) for name, value in sorted(by_name.items()) if GEOMETRY.match(name)}
    idle = b['system'][0] - a['system'][0]
    total = b['system'][1] - a['system'][1]
    busiest = sorted(by_name.items(), key=lambda item: -item[1])[:12]
    return {'seconds': round(seconds, 2), 'geometry_threads': geometry,
            'geometry_total_pct': round(sum(geometry.values()), 1),
            'process_pct': round((b['process'] - a['process']) * scale, 1),
            'machine_busy_pct': round(100.0 * (total - idle) / total, 1) if total else None,
            'busiest': [[name, round(value, 1)] for name, value in busiest]}


def other_load() -> list[str]:
    """Processes that would skew a measurement: other games, compilers, SteamVR."""
    return sorted({name for _pid, _parent, name in poc.process_entries() if BUSY_NAMES.match(name)})


def machine_busy(seconds: float = 3.0) -> float:
    a = system_times()
    time.sleep(seconds)
    b = system_times()
    total = b[1] - a[1]
    return round(100.0 * (total - (b[0] - a[0])) / total, 1) if total else 0.0


# ---------------------------------------------------------------- the shared PoC lock, one session per hold

class SessionLock:
    """out/r10/poc.lock of the main checkout, held for one session. Only an exclusive create takes it; while another
    owner's file exists it polls every second (an old-looking file included: it is never deleted, overwritten or taken
    over); at the end it is removed only if it still holds this process's pid and token."""

    def __init__(self, path: Path, task: str, timeout: float):
        self.path, self.task, self.timeout = path, task, timeout
        self.token = uuid.uuid4().hex
        self.waited = 0.0

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        owner = {'task': self.task, 'pid': os.getpid(), 'token': self.token,
                 'started': dt.datetime.now(dt.timezone.utc).isoformat()}
        began, said = time.monotonic(), False
        while True:
            try:
                with self.path.open('x', encoding='utf-8') as stream:
                    json.dump(owner, stream)
                self.waited = round(time.monotonic() - began, 1)
                return self
            except FileExistsError:
                if not said:
                    try:
                        held = self.path.read_text(encoding='utf-8', errors='replace')
                    except OSError:
                        held = '?'
                    print(f'Waiting for the PoC lock, held by {held}', flush=True)
                    said = True
                if time.monotonic() - began > self.timeout:
                    raise TimeoutError(f'the PoC lock stayed with another owner: {self.path}')
                time.sleep(1.0)

    def __exit__(self, *exc):
        try:
            owner = json.loads(self.path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            return
        if owner.get('pid') == os.getpid() and owner.get('token') == self.token:
            self.path.unlink()


# ---------------------------------------------------------------- what the session changes outside the PoC's files

def video_settings() -> dict:
    values = {}
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, VIDEO_KEY) as key:
            index = 0
            while True:
                try:
                    name, value, kind = winreg.EnumValue(key, index)
                except OSError:
                    break
                values[name] = [value, kind]
                index += 1
    except FileNotFoundError:
        pass
    return values


def restore_video_settings(before: dict) -> dict:
    """Sets back the values that differ from `before` and deletes values added since; returns what changed."""
    after = video_settings()
    changed = {name: {'before': before.get(name), 'after': value} for name, value in after.items() if before.get(name) != value}
    changed.update({name: {'before': value, 'after': None} for name, value in before.items() if name not in after})
    if changed:
        with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, VIDEO_KEY, 0, winreg.KEY_SET_VALUE) as key:
            for name, change in changed.items():
                if change['before'] is None:
                    winreg.DeleteValue(key, name)
                else:
                    winreg.SetValueEx(key, name, 0, change['before'][1], change['before'][0])
    return changed


def write_record(path: Path, value) -> None:
    """JSON with registry bytes as hex."""
    path.write_text(json.dumps(value, indent=2, default=lambda data: data.hex()), encoding='utf-8')


def write_config(package: Path, original: bytes) -> None:
    """The PoC's config.json as it was, with only allow.local naming the package."""
    data = json.loads(original.decode('utf-8'))
    data.setdefault('allow', {})['local'] = [str(package)]
    text = json.dumps(data, indent=2) + '\n'
    tmp = CONFIG.with_suffix('.json.tmp')
    tmp.write_text(text, encoding='utf-8', newline='\n')
    os.replace(tmp, CONFIG)


# ---------------------------------------------------------------- the client probe

def probe_lua(settle: float, seconds: float) -> str:
    """Waits `settle` seconds of real time, then times every frame (PostRender) for `seconds`: NL_RW_START and
    NL_RW_END frame the window, NL_RW_FPS reports it."""
    return (f'local nl_settle, nl_seconds, nl_t0 = {settle:.1f}, {seconds:.1f}, SysTime()\n'
            'print("NL_RW_PROBE")\n'
            'hook.Add("Think", "nl_rw_wait", function()\n'
            '  if SysTime() - nl_t0 < nl_settle then return end\n'
            '  hook.Remove("Think", "nl_rw_wait")\n'
            '  local times, last = {}, SysTime()\n'
            '  local began = last\n'
            '  print("NL_RW_START")\n'
            '  hook.Add("PostRender", "nl_rw_frames", function()\n'
            '    local now = SysTime()\n'
            '    times[#times + 1] = now - last\n'
            '    last = now\n'
            '    if now - began < nl_seconds then return end\n'
            '    hook.Remove("PostRender", "nl_rw_frames")\n'
            '    print("NL_RW_END")\n'
            '    local n, total = #times, 0\n'
            '    for _, t in ipairs(times) do total = total + t end\n'
            '    table.sort(times)\n'
            '    local function at(q) return times[math.max(1, math.ceil(n * q))] * 1000 end\n'
            '    local median, over = at(0.5), 0\n'
            '    for _, t in ipairs(times) do if t * 1000 > 2 * median then over = over + 1 end end\n'
            '    print(string.format(\'NL_RW_FPS {"frames":%d,"seconds":%.3f,"fps":%.2f,"mean_ms":%.3f,'
            '"median_ms":%.3f,"p90_ms":%.3f,"p99_ms":%.3f,"p999_ms":%.3f,"max_ms":%.3f,"over_2x_median":%d}\','
            ' n, total, n / total, total / n * 1000, median, at(0.9), at(0.99), at(0.999), times[n] * 1000, over))\n'
            '  end)\n'
            'end)\n')


# ---------------------------------------------------------------- one game session

def session(run: dict, evidence: Path, args) -> dict:
    folder = evidence / run['name']
    folder.mkdir(parents=True, exist_ok=True)
    record = {'name': run['name'], 'label': run['label'], 'kind': run['kind'], 'package': run['package'],
              'width': run['width'], 'height': run['height'], 'started': poc.now(),
              'machine_busy_before_pct': machine_busy(), 'other_processes': other_load()}
    if poc.game_processes(POC):
        raise RuntimeError('a game is already running in the PoC')
    console_log = POC / 'garrysmod' / 'console.log'
    if console_log.exists():
        shutil.move(str(console_log), str(folder / 'console-before-run.log'))
    remix_log = POC / 'rtx-remix' / 'logs' / 'remix-dxvk.log'
    remix_mtime = remix_log.stat().st_mtime_ns if remix_log.exists() else None
    remix_before = poc.read_shared(remix_log)
    menu = run['kind'] == 'menu'
    arguments = ['-game', 'garrysmod', '-multirun', '-console', '-windowed', '-w', str(run['width']), '-h',
                 str(run['height']), '-condebug', '-noworkshop', '+maxplayers', '1', '+mat_dxlevel']
    if not menu:
        arguments += ['+map', args.map]
    environment = dict(os.environ)
    environment.pop('NATIVE_LOADER_DISABLE', None)
    environment['NATIVE_LOADER_EXIT_REPORT'] = 'quiet'
    environment.pop('RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES', None)  # it would grant crash upload consent
    settings = poc.field_settings()
    poc.keep_crash_reports(POC, folder / 'crash-reports-before')
    launched_at = poc.filetime_now()
    process = subprocess.Popen([str(POC / 'bin' / 'win64' / 'gmod.exe'), *arguments], cwd=str(POC), env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    record['pid'] = process.pid
    health = poc.RunHealth(process, remix_log, remix_before, record, args.hang_grace)
    watchdog = poc.CrashPromptWatchdog(process, POC, folder)
    watchdog.start()
    began = time.monotonic()
    modules: list[str] = []

    def log() -> str:
        return poc.read_shared(console_log)

    def send(hwnd: int, command: str) -> bool:
        health.before_window(hwnd)
        return poc.console(hwnd, command, check=health.before_window)

    def lua(hwnd: int, name: str, code: str) -> bool:
        health.before_window(hwnd)
        return poc.client_lua(hwnd, name, code, check=health.before_window)

    def wait_for(pattern: re.Pattern, count: int, seconds: float, step: float = 0.1) -> bool:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            health.check()
            if process.poll() is not None:
                return False
            if len(pattern.findall(log())) >= count:
                return True
            time.sleep(step)
        return False

    def wait_quiet(seconds: float, limit: float) -> bool:
        deadline, size, since = time.monotonic() + limit, -1, time.monotonic()
        while time.monotonic() < deadline and process.poll() is None:
            health.check()
            now_size = console_log.stat().st_size if console_log.exists() else 0
            if now_size != size:
                size, since = now_size, time.monotonic()
            elif time.monotonic() - since >= seconds:
                return True
            time.sleep(0.5)
        return False

    def measure(seconds: float) -> dict:
        a = sample(process.pid)
        health.sleep(seconds)
        return usage(a, sample(process.pid))

    try:
        health.check()
        if menu:
            # The main menu at start: the pool exists once Remix has hashed its first draw.
            deadline = time.monotonic() + args.menu_wait
            while time.monotonic() < deadline and process.poll() is None:
                health.check()
                if any(GEOMETRY.match(name) for name, _ in thread_times(process.pid).values()):
                    record['menu_pool_after_s'] = round(time.monotonic() - began, 1)
                    break
                time.sleep(1)
            health.sleep(args.menu_settle)
            record['menu_start'] = measure(args.menu_seconds)
            hwnd = poc.console_window(process.pid)
            record['map_command'] = bool(hwnd) and send(hwnd, f'map {args.map}')
        record['map_loaded'] = wait_for(poc.MAP_MARKER, 1, args.timeout, step=0.5)
        record['seconds_to_map'] = round(time.monotonic() - began, 1)
        if not record['map_loaded']:
            raise poc.Failure('the map did not load')
        hwnd = poc.console_window(process.pid)
        if not hwnd:
            raise poc.Failure('no console window')
        record['quiet_after_map'] = wait_quiet(5, 90)
        for command in ('engine_no_focus_sleep 0', 'fps_max 0', 'cl_drawhud 0', 'r_drawviewmodel 0'):
            send(hwnd, command)
        record['camera'] = False
        for _ in range(3):
            printed = len(poc.EYE_MARKER.findall(log()))
            if lua(hwnd, 'camera', poc.camera_lua(CAMERA, True)) and wait_for(poc.EYE_MARKER, printed + 1, 20):
                record['camera'] = True
                break
        record['probe'] = False
        for _ in range(3):
            printed = len(PROBE.findall(log()))
            if lua(hwnd, 'rwprobe', probe_lua(args.settle, args.seconds)) and wait_for(PROBE, printed + 1, 20):
                record['probe'] = True
                break
        if not record['probe']:
            raise poc.Failure('the probe did not start')
        if not wait_for(START, 1, args.settle + 120):
            raise poc.Failure('the probe did not start timing')
        a = sample(process.pid)
        if not wait_for(END, 1, args.seconds + 120):
            raise poc.Failure('the probe did not finish timing')
        record['map'] = usage(a, sample(process.pid))
        if wait_for(FRAMES, 1, 10):
            record['frames'] = json.loads(FRAMES.findall(log())[-1])
        modules = poc.modules_of(process.pid)
        if menu:
            # Back to the main menu after a map: the pool lives as long as the device.
            send(hwnd, 'disconnect')
            health.sleep(args.menu_settle)
            record['menu_after_map'] = measure(args.menu_seconds)
            hwnd = poc.console_window(process.pid) or hwnd
        send(hwnd, 'cl_drawhud 1')
        send(hwnd, 'r_drawviewmodel 1')
        if settings is not None:
            record['settings_back'] = poc.settings_back(POC, settings, lambda command: send(hwnd, command), health.sleep)
        record['quit'] = 'console' if send(hwnd, 'quit') else 'console unavailable'
        if poc.wait_exit(process, 90, health.check):
            record['normal_quit'] = record['quit'] == 'console' and process.returncode == 0
        else:
            record['terminated'] = poc.stop_ours(process, POC, launched_at)[0]
            poc.wait_exit(process, 5)
            record['normal_quit'] = False
    except poc.Failure as error:
        record['failed'], record['normal_quit'] = str(error), False
        if not poc.wait_exit(process, poc.FAILURE_EXIT_TIMEOUT):
            record['terminated'] = poc.stop_ours(process, POC, launched_at)[0]
            poc.wait_exit(process, 5)
    finally:
        try:
            time.sleep(2)
            leftovers = poc.stop_ours(process, POC, launched_at)[0]
            if leftovers:
                record['terminated_helpers'] = leftovers
        finally:
            watchdog.close()
    record['exit'] = process.poll()
    poc.describe_exit(record)
    if watchdog.answered:
        record['declined_crash_prompts'] = watchdog.answered
    (folder / 'console.log').write_text(log(), encoding='utf-8', newline='')
    poc.copy_if_present(POC / 'native-loader' / 'logs' / 'loader.log', folder / 'loader.log')
    if remix_log.exists() and remix_log.stat().st_mtime_ns != remix_mtime:
        poc.copy_if_present(remix_log, folder / 'remix-dxvk.log')
    d3d9 = next((m for m in modules if os.path.basename(m).lower() == 'd3d9.dll'), None)
    record['d3d9'] = d3d9
    record['d3d9_sha256'] = vs.sha256(Path(d3d9)) if d3d9 and Path(d3d9).exists() else None
    record['finished'] = poc.now()
    vs.write_json(folder / 'record.json', record)
    return record


def plan(args) -> list[dict]:
    packages = []
    for spec in args.package:
        label, _, path = spec.partition('=')
        packages.append((label, str(Path(path).resolve())))
    runs = []
    if args.warmup:
        label, path = packages[0]
        runs.append({'name': f'warmup-{label}', 'label': label, 'package': path, 'kind': 'map',
                     'width': args.map_width, 'height': args.map_height})
    for n in range(1, args.menu_runs + 1):
        for label, path in (packages if n % 2 else packages[::-1]):
            runs.append({'name': f'menu-{label}{n}', 'label': label, 'package': path, 'kind': 'menu',
                         'width': args.menu_width, 'height': args.menu_height})
    for n in range(1, args.map_runs + 1):
        for label, path in (packages if n % 2 else packages[::-1]):
            runs.append({'name': f'map-{label}{n}', 'label': label, 'package': path, 'kind': 'map',
                         'width': args.map_width, 'height': args.map_height})
    return runs


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help="a new folder under this repository's out")
    parser.add_argument('--package', action='append', default=[], metavar='LABEL=GMA', required=True,
                        help='a package (repeatable): sessions alternate between them, in order')
    parser.add_argument('--menu-runs', type=int, default=2, help='rounds of menu, map and menu sessions per package')
    parser.add_argument('--map-runs', type=int, default=3, help='rounds of map sessions per package')
    parser.add_argument('--warmup', action='store_true', help='one map session first with the first package, not counted')
    parser.add_argument('--map', default='gm_construct')
    parser.add_argument('--menu-width', type=int, default=1280)
    parser.add_argument('--menu-height', type=int, default=720)
    parser.add_argument('--map-width', type=int, default=3840)
    parser.add_argument('--map-height', type=int, default=2160)
    parser.add_argument('--menu-wait', type=float, default=60, help='seconds to wait in the menu for the workers')
    parser.add_argument('--menu-settle', type=float, default=15)
    parser.add_argument('--menu-seconds', type=float, default=30, help='seconds of CPU time measured in the menu')
    parser.add_argument('--settle', type=float, default=60, help='seconds in the map before timing frames')
    parser.add_argument('--seconds', type=float, default=60, help='seconds of frames timed in the map')
    parser.add_argument('--timeout', type=float, default=600, help='map start deadline')
    parser.add_argument('--hang-grace', type=float, default=300)
    parser.add_argument('--lock-timeout', type=int, default=3 * 3600, help='seconds to wait for the lock, per session')
    parser.add_argument('--gap', type=float, default=10, help='seconds between sessions, the lock free for others')
    args = parser.parse_args(argv)
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    runs = plan(args)
    for run in runs:
        if not Path(run['package']).is_file():
            parser.error(f'no package {run["package"]}')
    if evidence.exists() and any(evidence.iterdir()):
        raise ValueError('use a new evidence folder')
    evidence.mkdir(parents=True, exist_ok=True)
    (REPO / 'out' / 'tmp').mkdir(parents=True, exist_ok=True)
    vs.write_json(evidence / 'plan.json', {'runs': runs, 'args': {k: str(v) for k, v in vars(args).items()},
                                          'packages': {p: vs.sha256(Path(p)) for p in {r['package'] for r in runs}}})
    lock_path = main_root / 'out' / 'r10' / 'poc.lock'
    results, restorations = [], []
    for index, run in enumerate(runs):
        if index:
            time.sleep(args.gap)  # a peer waiting for the lock takes it now
        # One session per hold: the PoC's config.json and the video settings are taken as they are now (another lab
        # may have run in between) and put back before the lock goes.
        with SessionLock(lock_path, f'remix workers A/B (runtime patch 0105) {run["name"]}', args.lock_timeout) as lock:
            if poc.game_processes(POC):
                raise RuntimeError('a game is already running in the PoC')
            original = CONFIG.read_bytes()
            video = video_settings()
            if index == 0:
                (evidence / 'config.json.before').write_bytes(original)
                write_record(evidence / 'video-settings-before.json', video)
            print(f'{run["name"]} ({run["width"]}x{run["height"]}), lock after {lock.waited} s', flush=True)
            try:
                write_config(Path(run['package']), original)
                record = session(run, evidence, args)
            finally:
                CONFIG.write_bytes(original)
                restored = {'run': run['name'], 'config_json_restored': CONFIG.read_bytes() == original,
                            'video_settings_changed_and_restored': restore_video_settings(video)}
                restored['video_settings_equal'] = video_settings() == video
                restorations.append(restored)
                write_record(evidence / 'restoration.json', restorations)
        record['lock_waited_s'] = lock.waited
        results.append(record)
        vs.write_json(evidence / 'results.json', results)
        frames = record.get('frames') or {}
        print(f'  map: geometry {record.get("map", {}).get("geometry_threads")} '
              f'frames {frames.get("mean_ms")} ms mean, {frames.get("median_ms")} median, '
              f'{frames.get("p99_ms")} p99; menu {record.get("menu_start", {}).get("geometry_threads")} / '
              f'{record.get("menu_after_map", {}).get("geometry_threads")}; d3d9 {str(record.get("d3d9_sha256"))[:12]}; '
              f'{record.get("failed") or "ok"}; restored {restored["config_json_restored"]} '
              f'{restored["video_settings_equal"]}', flush=True)
    return 0 if all(not r.get('failed') for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
