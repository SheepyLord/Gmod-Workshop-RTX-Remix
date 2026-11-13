"""VR V6 in the PoC: every ladder step applied as named, then Auto holding, stepping down and climbing back."""
from pathlib import Path
import argparse
import json
import math
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'tools'), str(ROOT / 'companion/tests')]
import vr_session as driver  # noqa: E402

BASE_SCRIPT = driver.lua_script
LADDER_FILE = ROOT / 'vr/addon/lua/nlvr/modules/cl_perf_ladder.lua'
COOLDOWN = 3.0
SECONDS = 150


def ladder(path=LADDER_FILE):
    """The steps as the add-on defines them, parsed from its Lua table."""
    text = path.read_text(encoding='utf-8')
    steps = []
    pattern = re.compile(r'\{name = "(\w+)",\s*render_scale = ([0-9.]+), dlss = (\d), min_bounces = (\d+), '
                         r'max_bounces = (\d+), volumetrics = (true|false),\s*fine_clouds = (true|false)\}')
    for m in pattern.finditer(text):
        steps.append({'name': m.group(1), 'scale': float(m.group(2)), 'dlss': int(m.group(3)),
                      'min_bounces': int(m.group(4)), 'max_bounces': int(m.group(5)),
                      'flags': (1 if m.group(6) == 'true' else 0) | (2 if m.group(7) == 'true' else 0)})
    return steps


def f32(value):
    """The value as a C float, the type the runtime multiplies in."""
    return struct.unpack('f', struct.pack('f', value))[0]


def eye_size(recommended, scale):
    """The eye image side the runtime allocates: ceil(float(side) * float(scale)) in float arithmetic."""
    return max(1, math.ceil(f32(f32(recommended) * f32(scale))))


def write_probe(path, config):
    BASE_SCRIPT(path, config)
    text = path.read_text(encoding='utf-8')
    text += '\ndo\n' + Path(__file__).with_name('vr_quality_probe.lua').read_text(encoding='utf-8') + '\nend\n'
    path.write_text(text, encoding='utf-8')


def quality_rows(summary):
    rows = []
    for record in summary.get('records', []):
        if record.get('kind') == 'V6-quality':
            rows += [r for r in record.get('rows', []) if isinstance(r, dict)]
    return rows


def changes(trace):
    """(time, step) at every change of the step Auto is using."""
    out, last = [], None
    for row in trace:
        step = (row.get('perf') or {}).get('step')
        if step is not None and step != last:
            out.append((row['t'], step))
            last = step
    return out


def analyse(summary, steps):
    rows = quality_rows(summary)
    marks = {r['what']: r['t'] for r in rows if r.get('kind') == 'mark'}
    checks, detail = {}, {}
    fixed = {r['step']: r for r in rows if r.get('kind') == 'fixed'}
    applied = []
    for index, step in enumerate(steps, 1):
        row = fixed.get(index) or {}
        perf, runtime = row.get('perf') or {}, row.get('runtime') or {}
        rec_w, rec_h = runtime.get('rec_width'), runtime.get('rec_height')
        good = (perf.get('step') == index and perf.get('auto') is False and
                runtime.get('dlss') == step['dlss'] and runtime.get('min_bounces') == step['min_bounces'] and
                runtime.get('max_bounces') == step['max_bounces'] and runtime.get('flags') == step['flags'] and
                isinstance(runtime.get('scale'), (int, float)) and abs(runtime['scale'] - step['scale']) < 1e-4 and
                isinstance(rec_w, (int, float)) and isinstance(rec_h, (int, float)) and
                runtime.get('eye_width') == eye_size(rec_w, step['scale']) and
                runtime.get('eye_height') == eye_size(rec_h, step['scale']))
        applied.append({'step': index, 'ok': good, 'perf': perf, 'runtime': runtime})
    checks['every_step_applied'] = all(a['ok'] for a in applied) and len(applied) == len(steps) == 7
    detail['fixed'] = applied
    trace = [r for r in rows if r.get('kind') == 'trace']
    auto, load, unload, end = marks.get('auto'), marks.get('load'), marks.get('unload'), marks.get('end')

    def between(first, last):
        return [r for r in trace if first is not None and r['t'] >= first and (last is None or r['t'] < last)]
    held, down, up = between(auto, load), between(load, unload), between(unload, None)
    # Frames missed while the GPU has room: Auto holds the top step and says why.
    held_steps = {(r.get('perf') or {}).get('step') for r in held}
    checks['cpu_bound_holds'] = (bool(held) and held_steps == {1} and
                                 any((r.get('perf') or {}).get('cpu_limited') for r in held))
    down_changes, up_changes = changes(down), changes(up)
    detail['held_steps'] = sorted(map(str, held_steps))
    detail['down_changes'], detail['up_changes'] = down_changes, up_changes
    down_steps = [s for _, s in down_changes]
    checks['down_reaches_floor'] = bool(down_steps) and down_steps[-1] == len(steps)
    checks['down_one_rung_at_a_time'] = all(b - a == 1 for a, b in zip(down_steps, down_steps[1:]))
    checks['down_respects_cooldown'] = all(t2 - t1 >= COOLDOWN - 0.6 for (t1, _), (t2, _) in zip(down_changes[1:], down_changes[2:]))
    up_steps = [s for _, s in up_changes]
    checks['up_reaches_top'] = len(up_steps) >= 2 and up_steps[-1] == 1
    checks['up_one_rung_at_a_time'] = all(a - b == 1 for a, b in zip(up_steps, up_steps[1:]))
    checks['up_respects_cooldown'] = all(t2 - t1 >= COOLDOWN - 0.6 for (t1, _), (t2, _) in zip(up_changes[1:], up_changes[2:]))
    # Once back at the top it stays there: no oscillation on the session's own readings.
    top_at = next((t for t, s in up_changes if s == 1), None)
    checks['up_settles'] = top_at is not None and all(s == 1 for t, s in up_changes if t >= top_at)
    # The runtime renders what Auto chose: once a step has held for a second, the applied step matches it.
    followed, mismatches = 0, []
    for row in trace:
        step = (row.get('perf') or {}).get('step')
        earlier = [r for r in trace if row['t'] - 1.2 <= r['t'] <= row['t']]
        if not isinstance(step, int) or not 1 <= step <= len(steps):
            continue
        if any((r.get('perf') or {}).get('step') != step for r in earlier) or row['t'] - earlier[0]['t'] < 0.9:
            continue
        want, runtime = steps[step - 1], row.get('runtime') or {}
        good = (runtime.get('dlss') == want['dlss'] and runtime.get('min_bounces') == want['min_bounces'] and
                runtime.get('max_bounces') == want['max_bounces'] and runtime.get('flags') == want['flags'] and
                isinstance(runtime.get('scale'), (int, float)) and abs(runtime['scale'] - want['scale']) < 1e-4)
        followed += 1
        if not good:
            mismatches.append({'t': row['t'], 'step': step, 'runtime': runtime})
    checks['runtime_follows_auto'] = followed > 0 and not mismatches
    detail['runtime_follows_auto'] = {'rows': followed, 'mismatches': mismatches[:5]}
    checks['no_refusals'] = not any((r.get('perf') or {}).get('error') for r in rows if r.get('kind') in ('fixed', 'trace'))
    checks['plan_completed'] = end is not None
    detail['marks'] = marks
    detail['rates'] = {'held': [(r['t'], (r.get('perf') or {}).get('rate')) for r in held][-4:],
                       'down': [(r['t'], (r.get('perf') or {}).get('rate')) for r in down][-4:],
                       'up': [(r['t'], (r.get('perf') or {}).get('rate'), (r.get('perf') or {}).get('gpu_ms')) for r in up][-6:]}
    return {'success': all(checks.values()), 'checks': checks, 'detail': detail}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--simulate', action='store_true')
    parser.add_argument('--reanalyse', action='store_true',
                        help="check an existing evidence folder's records again, without a session")
    args = parser.parse_args(argv)
    if not args.reanalyse and args.package is None:
        parser.error('--package is required for a session')
    steps = ladder()
    if len(steps) != 7:
        parser.error('could not read the seven ladder steps from ' + str(LADDER_FILE))
    if args.reanalyse:
        # The driver's own verdict on that session is in its summary.
        summary_path = args.evidence / 'summary.json'
        code = 0 if summary_path.exists() and json.loads(summary_path.read_text(encoding='utf-8-sig')).get('success') else 1
    else:
        driver.lua_script = write_probe
        code = driver.main(['--package', str(args.package), '--evidence', str(args.evidence), '--seconds', str(SECONDS),
                            *(['--simulate'] if args.simulate else [])])
    summary_path = args.evidence / 'summary.json'
    if not summary_path.exists():
        return code or 1
    result = analyse(json.loads(summary_path.read_text(encoding='utf-8-sig')), steps)
    result['session_success'] = code == 0
    driver.write_json(args.evidence / 'quality-checks.json', result)
    print(json.dumps({'success': result['success'] and code == 0, 'checks': result['checks']}, separators=(',', ':')))
    return 0 if result['success'] and code == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
