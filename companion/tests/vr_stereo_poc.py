"""VR V7 in the PoC: true stereo against the warp at one step, the eyes compared picture by picture."""
from pathlib import Path
import argparse
import json
import math
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'tools'), str(ROOT / 'companion/tests')]
import vr_session as driver  # noqa: E402

BASE_SCRIPT = driver.lua_script
SECONDS = 66
SETTLE = 3.0          # seconds into a phase before the mode must hold
LABELS = ('warp', 'stereo', 'warp-again', 'stereo-again')
SIDE = 96             # the pictures are compared at this many pixels a side


def still_timeline(seconds):
    """The head held still for the whole session, so the warp and stereo pictures of a pair share one pose. The
    driver's own timeline turns the head between 10 and 50 s, inside the first pair."""
    def step(t):
        return {'time': t, 'hmd': {'pos': [0, 0, 1.6], 'ang': [0, 0, 0]},
                'left': {'pos': [0.25, 0.25, 1.2], 'ang': [0, 0, 0]},
                'right': {'pos': [0.25, -0.25, 1.2], 'ang': [0, 0, 0]}}
    return {'version': 1, 'steps': [step(0), step(seconds + 30)]}


def write_probe(path, config):
    BASE_SCRIPT(path, config)
    text = path.read_text(encoding='utf-8')
    text += '\ndo\n' + Path(__file__).with_name('vr_stereo_probe.lua').read_text(encoding='utf-8') + '\nend\n'
    path.write_text(text, encoding='utf-8')


def stereo_rows(summary):
    rows = []
    for record in summary.get('records', []):
        if record.get('kind') == 'V7-stereo':
            rows += [r for r in record.get('rows', []) if isinstance(r, dict)]
    return rows


def grey(path):
    """The picture as SIDE x SIDE luminance, 0-1, or None."""
    try:
        from PIL import Image
    except ImportError:
        return None
    if not path.is_file():
        return None
    with Image.open(path) as image:
        small = image.convert('L').resize((SIDE, SIDE), Image.BILINEAR)
        return [value / 255 for value in small.tobytes()]


def correlation(a, b):
    if not a or not b:
        return None
    ma, mb = statistics.fmean(a), statistics.fmean(b)
    da = [x - ma for x in a]
    db = [y - mb for y in b]
    num = sum(x * y for x, y in zip(da, db))
    den = math.sqrt(sum(x * x for x in da) * sum(y * y for y in db))
    return num / den if den > 0 else None


def compare(captures):
    """What the eye pictures say: each stereo eye matches its warped eye better than the other eye does, the two
    stereo eyes differ (disparity) but share their brightness, and stereo keeps the warp's brightness."""
    images = {label: {eye: grey(captures / ('v7-' + label) / (eye + '.png')) for eye in ('left', 'right')}
              for label in LABELS}
    out = {'available': all(v is not None for eyes in images.values() for v in eyes.values())}
    if not out['available']:
        out['missing'] = [f'{label}/{eye}' for label, eyes in images.items() for eye, v in eyes.items() if v is None]
        return out
    pairs = []
    for warp, stereo in (('warp', 'stereo'), ('warp-again', 'stereo-again')):
        w, s = images[warp], images[stereo]
        item = {'pair': [warp, stereo]}
        for eye, other in (('left', 'right'), ('right', 'left')):
            item[eye + '_same'] = correlation(w[eye], s[eye])
            item[eye + '_other'] = correlation(w[eye], s[other])
        item['stereo_eyes'] = correlation(s['left'], s['right'])
        item['stereo_eye_difference'] = statistics.fmean(abs(x - y) for x, y in zip(s['left'], s['right']))
        means = {eye: statistics.fmean(s[eye]) for eye in ('left', 'right')}
        warp_means = {eye: statistics.fmean(w[eye]) for eye in ('left', 'right')}
        item['stereo_mean'] = means
        item['warp_mean'] = warp_means
        pairs.append(item)
    out['pairs'] = pairs
    return out


def analyse(summary, captures):
    rows = stereo_rows(summary)
    marks = {r['what']: r['t'] for r in rows if r.get('kind') == 'mark'}
    trace = [r for r in rows if r.get('kind') == 'trace']
    checks, detail = {}, {'marks': marks}
    phases = {}
    for label in LABELS:
        start = marks.get(label)
        later = [marks[k] for k in list(LABELS) + ['end'] if k in marks and start is not None and marks[k] > start]
        stop = min(later) if later else None
        phases[label] = [r for r in trace if r.get('label') == label and start is not None and
                         r['t'] >= start + SETTLE and (stop is None or r['t'] < stop)]
    want = {'warp': 0, 'stereo': 1, 'warp-again': 0, 'stereo-again': 1}
    checks['mode_follows_the_setting'] = all(phases[l] and all(r.get('stereo_active') == want[l] for r in phases[l])
                                             for l in LABELS)
    detail['mode'] = {l: sorted({str(r.get('stereo_active')) for r in phases[l]}) for l in LABELS}

    def advancing(rows):
        counter = 'submitted' if any((r.get('submitted') or 0) > 0 for r in rows) else 'rendered'
        values = [r.get(counter) or 0 for r in rows]
        return len(values) >= 4 and values[-1] - values[0] >= 5 * (rows[-1]['t'] - rows[0]['t'])
    checks['frames_advance'] = all(phases[l] and advancing(phases[l]) for l in LABELS)
    # Each eye is traced at the eye's size, smaller than the centre view the warp traces.
    widths = {l: statistics.median(r.get('render_width') or 0 for r in phases[l]) if phases[l] else 0 for l in LABELS}
    detail['render_width'] = widths
    checks['eyes_traced_at_eye_size'] = 0 < widths['stereo'] < widths['warp'] and 0 < widths['stereo-again'] < widths['warp-again']

    def work(label):
        values = [r.get('gpu_work') for r in phases[label] if isinstance(r.get('gpu_work'), (int, float)) and r['gpu_work'] > 0]
        return statistics.median(values) if values else None
    costs = {l: work(l) for l in LABELS}
    detail['gpu_work_ms'] = costs
    if costs['warp'] and costs['stereo']:
        detail['stereo_cost_ratio'] = costs['stereo'] / costs['warp']
    # The second eye is real work: true stereo costs more than the warp.
    checks['second_eye_costs'] = all(costs[s] and costs[w] and costs[s] > costs[w] * 1.1
                                     for w, s in (('warp', 'stereo'), ('warp-again', 'stereo-again')))
    captured = {r['label']: r for r in rows if r.get('kind') == 'capture'}
    checks['captures_dispatched'] = all(captured.get(l, {}).get('ok') for l in LABELS)
    pictures = compare(captures)
    detail['pictures'] = pictures
    ok = pictures.get('available', False)
    for item in pictures.get('pairs', []):
        for eye in ('left', 'right'):
            same, other = item[eye + '_same'], item[eye + '_other']
            ok = ok and same is not None and other is not None and same >= 0.80 and same > other
        ok = ok and item['stereo_eye_difference'] > 0.002
    checks['eyes_match_the_warp'] = ok
    # Exposure, not content: each stereo eye against its own warped eye (the eyes see different things, a hand
    # perhaps in one of them), within 15 %, and the two eyes' ratios within 5 % of each other (one shared exposure).
    bright = pictures.get('available', False)
    for item in pictures.get('pairs', []):
        sm, wm = item['stereo_mean'], item['warp_mean']
        ratios = {eye: sm[eye] / max(wm[eye], 1e-3) for eye in ('left', 'right')}
        item['brightness_ratio'] = ratios
        bright = bright and all(abs(r - 1) <= 0.15 for r in ratios.values()) and abs(ratios['left'] - ratios['right']) <= 0.05
    checks['brightness_consistent'] = bright
    checks['no_refusals'] = not any(r.get('error') for r in trace)
    checks['plan_completed'] = 'end' in marks
    return {'success': all(checks.values()), 'checks': checks, 'detail': detail}


def runtime_log_checks(evidence):
    log = evidence / 'poc/game/remix-dxvk.log'
    text = log.read_text(encoding='utf-8', errors='replace') if log.is_file() else ''
    return {'runtime_says_stereo': 'RTX VR true stereo: each eye is path traced' in text,
            'runtime_no_vr_error': 'RTX VR: error' not in text,
            'right_eye_state_made': "the right eye's view state was made" in text}


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
    if args.reanalyse:
        summary_path = args.evidence / 'summary.json'
        code = 0 if summary_path.exists() and json.loads(summary_path.read_text(encoding='utf-8-sig')).get('success') else 1
    else:
        driver.lua_script = write_probe
        still = args.evidence.with_name(args.evidence.name + '-timeline.json')
        still.parent.mkdir(parents=True, exist_ok=True)
        driver.write_json(still, still_timeline(SECONDS))
        code = driver.main(['--package', str(args.package), '--evidence', str(args.evidence), '--seconds', str(SECONDS),
                            '--timeline', str(still), *(['--simulate'] if args.simulate else [])])
    summary_path = args.evidence / 'summary.json'
    if not summary_path.exists():
        return code or 1
    result = analyse(json.loads(summary_path.read_text(encoding='utf-8-sig')), args.evidence / 'captures')
    result['checks'].update(runtime_log_checks(args.evidence))
    result['success'] = all(result['checks'].values())
    result['session_success'] = code == 0
    driver.write_json(args.evidence / 'stereo-checks.json', result)
    print(json.dumps({'success': result['success'] and code == 0, 'checks': result['checks']}, separators=(',', ':')))
    return 0 if result['success'] and code == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
