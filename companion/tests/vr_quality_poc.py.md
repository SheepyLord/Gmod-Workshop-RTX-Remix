# vr_quality_poc.py

VR V6 in the PoC ([ADR 0199](../../docs/decisions/0199-vr-auto-quality-ladder.md)): runs the production driver
[`tools/vr_session.py`](../../tools/vr_session.py.md) for 150 s with [`vr_quality_probe.lua`](vr_quality_probe.lua.md)
appended, then checks what the runtime and the add-on did.

```powershell
python -B companion\tests\vr_quality_poc.py --package <gma> --evidence out\vr\v6\quality-sim-01 --simulate
python -B companion\tests\vr_quality_poc.py --package <gma> --evidence out\vr\v6\quality-index-01
python -B companion\tests\vr_quality_poc.py --evidence out\vr\v6\quality-sim-02 --reanalyse
```

`--reanalyse` checks an existing evidence folder's records again without a session (the session's verdict is the
driver's `success` in its `summary.json`); it rewrites `quality-checks.json`.

The driver takes both shared locks, snapshots and restores the PoC, and quits a running field game through the
guarded helper, as every VR PoC run does.

Checks (`quality-checks.json`):

| Check | Means |
|---|---|
| `every_step_applied` | each pinned step reached the runtime as the ladder names it (parsed from `cl_perf_ladder.lua`): DLSS mode, both bounce counts, effect flags and scale, and the eye images resized to the recommended size times the scale, rounded up in float arithmetic as the runtime does (2740 x 0.6 gives 1645) |
| `cpu_bound_holds` | frames missed while the GPU had room: Auto stayed at the top step and reported `cpu_limited` |
| `down_reaches_floor` | with the GPU over its budget Auto walked from the top to the floor |
| `down_one_rung_at_a_time`, `up_one_rung_at_a_time` | no step skipped a rung |
| `down_respects_cooldown`, `up_respects_cooldown` | consecutive steps at least the cool-down apart (0.6 s allowed for the 0.5 s trace); the step a phase begins at is not a step |
| `up_reaches_top` | on the session's own readings Auto climbed back to the top step |
| `up_settles` | once back at the top it stayed there |
| `runtime_follows_auto` | wherever Auto's step had held for a second, the runtime's applied step (DLSS, bounces, flags, scale) was that step |
| `no_refusals` | the runtime never refused a step |
| `plan_completed` | the probe reached its end |

Prints a one-line JSON summary; exit 0 only when the session and every check pass. Writes the evidence folder.
Offline tests of the analysis: `vr_perf_test.py` (`VRQualityAnalysisTests`, each check also shown to fail on a
record that breaks it).
