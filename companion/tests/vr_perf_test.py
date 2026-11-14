"""Offline tests for VR V6's quality ladder and Auto controller (LuaJIT)."""
from pathlib import Path
import subprocess
import unittest

from test_mmd_alpha import LUAJIT, ROOT

SCENARIOS = ("ladder_order", "ladder_ceiling", "ladder_start", "control_down", "control_cooldown",
             "control_up", "control_bounds", "control_no_oscillation", "control_window", "control_cpu_bound", "control_half_rate",
             "frame_generation_rates")


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRPerfTests(unittest.TestCase):
    def run_scenario(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_perf_harness.lua")), str(ROOT), scenario],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + scenario, result.stdout)


for _scenario in SCENARIOS:
    setattr(VRPerfTests, "test_" + _scenario, lambda self, s=_scenario: self.run_scenario(s))


class VRQualityAnalysisTests(unittest.TestCase):
    """The PoC driver's checks, on synthetic records, so a broken analysis cannot pass a real run."""
    def setUp(self):
        import vr_quality_poc as poc
        self.poc = poc
        self.steps = poc.ladder()

    def runtime(self, step):
        s = self.steps[step - 1]
        return {'scale': s['scale'], 'dlss': s['dlss'], 'min_bounces': s['min_bounces'],
                'max_bounces': s['max_bounces'], 'flags': s['flags']}

    def summary(self, held=(1,), down=(1, 2, 3, 4, 5, 6, 7), up=(7, 6, 5, 4, 3, 2, 1), gap=3.2, cpu_limited=True,
                first=None):
        rows = []
        for i, step in enumerate(self.steps, 1):
            runtime = dict(self.runtime(i), rec_width=2468, rec_height=2740,
                           eye_width=self.poc.eye_size(2468, step['scale']), eye_height=self.poc.eye_size(2740, step['scale']))
            rows.append({'kind': 'fixed', 'step': i, 't': 3 + 3.5 * i, 'perf': {'step': i, 'auto': False},
                         'runtime': runtime})

        def phase(what, start, stop, path, hold, lead=0.0):
            # `lead` shortens the phase's first step: a real step may come soon after a phase begins.
            rows.append({'kind': 'mark', 'what': what, 't': start})
            t, index = start, 0
            while t < stop - 1e-9:
                step = path[min(index, len(path) - 1)]
                rows.append({'kind': 'trace', 't': t, 'runtime': self.runtime(step),
                             'perf': {'step': step, 'auto': True, 'cpu_limited': cpu_limited and what == 'auto'}})
                t += 0.5
                index = max(0, int((t - start + lead) // hold))
        phase('auto', 28.5, 38.5, held, 10.0 / len(held))
        phase('load', 38.5, 68.5, down, gap, lead=gap - first if first else 0.0)
        phase('unload', 68.5, 138.5, up, gap * 3)
        rows.append({'kind': 'mark', 'what': 'end', 't': 138.5})
        return {'records': [{'kind': 'V6-quality', 'rows': rows}]}

    def checks(self, **kwargs):
        return self.poc.analyse(self.summary(**kwargs), self.steps)['checks']

    def test_ladder_parses_seven_steps(self):
        self.assertEqual([s['name'] for s in self.steps], ['full', 'high', 'balanced', 'fast', 'faster', 'low', 'floor'])
        self.assertEqual(self.steps[0]['flags'], 3)
        self.assertEqual(self.steps[-1]['flags'], 0)

    def test_a_good_run_passes(self):
        result = self.poc.analyse(self.summary(), self.steps)
        self.assertTrue(result['success'], result['checks'])

    def test_a_step_down_while_the_gpu_has_room_fails(self):
        self.assertFalse(self.checks(held=(1, 2))['cpu_bound_holds'])

    def test_a_hold_without_its_reason_fails(self):
        self.assertFalse(self.checks(cpu_limited=False)['cpu_bound_holds'])

    def test_a_skipped_rung_fails(self):
        self.assertFalse(self.checks(down=(1, 3, 4, 5, 6, 7))['down_one_rung_at_a_time'])

    def test_the_phase_start_is_not_a_step(self):
        # The first step down 1.5 s after the load began is two missed windows, not a short cool-down.
        self.assertTrue(self.checks(first=1.5)['down_respects_cooldown'])

    def test_float_eye_sizes(self):
        # The runtime multiplies in float: 2740 x 0.6f is 1644.00007, so the eye is 1645 rows.
        self.assertEqual(self.poc.eye_size(2740, 0.6), 1645)
        self.assertEqual(self.poc.eye_size(2468, 0.5), 1234)

    def test_steps_inside_the_cooldown_fail(self):
        self.assertFalse(self.checks(gap=1.0)['down_respects_cooldown'])

    def test_a_step_applied_wrongly_fails(self):
        summary = self.summary()
        summary['records'][0]['rows'][2]['runtime']['dlss'] = 3
        self.assertFalse(self.poc.analyse(summary, self.steps)['checks']['every_step_applied'])

    def test_no_climb_fails(self):
        self.assertFalse(self.checks(up=(7,))['up_reaches_top'])

    def test_oscillation_at_the_top_fails(self):
        self.assertFalse(self.checks(up=(7, 6, 5, 4, 3, 2, 1, 2, 1))['up_settles'])

    def test_a_runtime_behind_auto_fails(self):
        summary = self.summary()
        rows = summary['records'][0]['rows']
        late = [r for r in rows if r.get('kind') == 'trace' and r['t'] > 100][0]
        late['runtime'] = self.runtime(1 if late['perf']['step'] != 1 else 2)
        self.assertFalse(self.poc.analyse(summary, self.steps)['checks']['runtime_follows_auto'])


if __name__ == "__main__":
    unittest.main()
