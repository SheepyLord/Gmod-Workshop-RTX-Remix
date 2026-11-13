"""Offline tests for VR V7's PoC analysis: synthetic records and pictures, so a broken check cannot pass a real run."""
from pathlib import Path
import random
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vr_stereo_poc as poc  # noqa: E402

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the gate's Python has Pillow
    Image = None


def pattern(seed=7, size=192):
    """A blocky test picture with enough detail that a shift lowers its correlation."""
    rng = random.Random(seed)
    blocks = [[rng.randint(0, 255) for _ in range(24)] for _ in range(24)]
    return [[blocks[y * 24 // size][x * 24 // size] for x in range(size)] for y in range(size)]


def shifted(pixels, dx, scale=1.0):
    size = len(pixels)
    return [[min(255, int(pixels[y][min(size - 1, max(0, x - dx))] * scale)) for x in range(size)] for y in range(size)]


def save(pixels, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new('L', (len(pixels[0]), len(pixels)))
    image.putdata([value for row in pixels for value in row])
    image.convert('RGB').save(path)


@unittest.skipUnless(Image, 'Pillow is not installed')
class VRStereoAnalysisTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[2] / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch)
        self.captures = Path(self.tmp.name) / 'captures'

    def tearDown(self):
        self.tmp.cleanup()

    def pictures(self, swap=False, same_eyes=False, dark_right=1.0):
        base = pattern()
        left, right = shifted(base, -12), shifted(base, 12)
        for label in poc.LABELS:
            folder = self.captures / ('v7-' + label)
            if label.startswith('stereo'):
                l, r = (right, left) if swap else (left, right)
                if same_eyes:
                    r = l
                save(l, folder / 'left.png')
                save(shifted(r, 0, dark_right), folder / 'right.png')
            else:
                save(left, folder / 'left.png')
                save(right, folder / 'right.png')

    def summary(self, stereo_active=1, stereo_work=19.0):
        rows, t, counter = [], 0.0, 0
        starts = {'warp': 2, 'stereo': 16, 'warp-again': 32, 'stereo-again': 44}
        for label, start in starts.items():
            rows.append({'kind': 'mark', 'what': label, 't': float(start)})
        rows.append({'kind': 'mark', 'what': 'end', 't': 58.0})
        t = 2.0
        while t < 58:
            label = max((l for l, s in starts.items() if s <= t), key=lambda l: starts[l])
            stereo = label.startswith('stereo')
            counter += 40
            rows.append({'kind': 'trace', 'label': label, 't': t, 'stereo_active': stereo_active if stereo else 0,
                         'gpu_work': stereo_work if stereo else 12.0, 'render_width': 1234 if stereo else 1556,
                         'rendered': counter, 'submitted': 0})
            t += 0.5
        for label, start in starts.items():
            rows.append({'kind': 'capture', 'label': label, 't': start + 9.0, 'ok': True})
        return {'records': [{'kind': 'V7-stereo', 'rows': rows}]}

    def checks(self, **kwargs):
        return poc.analyse(self.summary(**kwargs), self.captures)['checks']

    def test_a_good_run_passes(self):
        self.pictures()
        result = poc.analyse(self.summary(), self.captures)
        self.assertTrue(result['success'], result)

    def test_swapped_eyes_fail(self):
        self.pictures(swap=True)
        self.assertFalse(self.checks()['eyes_match_the_warp'])

    def test_eyes_without_disparity_fail(self):
        self.pictures(same_eyes=True)
        self.assertFalse(self.checks()['eyes_match_the_warp'])

    def test_a_darker_eye_fails(self):
        self.pictures(dark_right=0.7)
        self.assertFalse(self.checks()['brightness_consistent'])

    def test_a_still_head_for_the_session(self):
        steps = poc.still_timeline(66)['steps']
        self.assertEqual({str(step['hmd']) for step in steps}, {str(steps[0]['hmd'])})
        self.assertGreater(steps[-1]['time'], 66)

    def test_stereo_that_never_starts_fails(self):
        self.pictures()
        self.assertFalse(self.checks(stereo_active=0)['mode_follows_the_setting'])

    def test_a_free_second_eye_fails(self):
        self.pictures()
        self.assertFalse(self.checks(stereo_work=12.5)['second_eye_costs'])

    def test_missing_pictures_fail(self):
        self.assertFalse(self.checks()['eyes_match_the_warp'])


if __name__ == '__main__':
    unittest.main()
