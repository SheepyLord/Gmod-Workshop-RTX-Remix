# vr_stereo_poc.py

VR V7 in the PoC (true stereo, [ADR 0198](../../docs/decisions/0198-vr-true-stereo-by-swapping-the-eyes-state.md)): runs
the production driver [`tools/vr_session.py`](../../tools/vr_session.py.md) for 66 s with
[`vr_stereo_probe.lua`](vr_stereo_probe.lua.md) appended, then compares true stereo with the warp at one step.

```powershell
python -B companion\tests\vr_stereo_poc.py --package <gma> --evidence out\vr\v7\stereo-sim-01 --simulate
python -B companion\tests\vr_stereo_poc.py --package <gma> --evidence out\vr\v7\stereo-index-01
python -B companion\tests\vr_stereo_poc.py --evidence out\vr\v7\stereo-sim-01 --reanalyse
```

The driver takes both shared locks, snapshots and restores the PoC, and quits a running field game through the
guarded helper, as every VR PoC run does. The head is held still for the whole session (`<evidence>-timeline.json`,
passed as `--timeline`): the driver's own timeline turns the head between 10 and 50 s, which put the first pair's
pictures at different poses. `--reanalyse` checks an existing evidence folder again without a session.

Checks (`stereo-checks.json`), each phase from three seconds after its switch:

| Check | Means |
|---|---|
| `mode_follows_the_setting` | the runtime's `stereoActive` is 1 in both stereo phases and 0 in both warp phases |
| `frames_advance` | at least five frames a second in every phase (eye pairs on a headset, rendered frames simulated) |
| `eyes_traced_at_eye_size` | the traced width in stereo is below the warp's, which traces the larger centre view |
| `second_eye_costs` | the GPU's median work in stereo is more than 1.1 times the warp's: the second eye is real work |
| `captures_dispatched` | each phase's capture was accepted |
| `eyes_match_the_warp` | at 96 x 96 grey, each stereo eye correlates with the same warped eye at 0.80 or more and better than the other warped eye does (no swapped, mirrored or misplaced eye), and the two stereo eyes differ (disparity) |
| `brightness_consistent` | each stereo eye's mean brightness within 15 % of its warped eye's, and the two eyes' ratios within 5 % of each other: one shared exposure, whatever each eye sees |
| `no_refusals`, `plan_completed` | the runtime refused no step; the probe reached its end |
| `runtime_says_stereo`, `right_eye_state_made`, `runtime_no_vr_error` | the runtime's log names true stereo and the right eye's state, and no VR error |

`detail` keeps the correlations, the brightness, the traced widths and the GPU work in each mode
(`stereo_cost_ratio`). Pillow reads the pictures (Python 3.12 here has it). Prints a one-line JSON summary; exit 0 only
when the session and every check pass. Offline tests of the analysis: `vr_stereo_test.py`.
