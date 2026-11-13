# cl_perf_control.lua

VR V6's Auto controller ([ADR 0199](../../../../../docs/decisions/0199-vr-auto-quality-ladder.md)): measured frames in,
at most one rung of movement out. No engine calls, so every decision is testable offline.

`Control.New{steps = n, ...}` returns a controller; its options override these defaults:

| Option | Default | Meaning |
|---|---|---|
| `window` | 1.0 s | frames counted per decision |
| `missRatio` | 0.95 | below this share of the target rate a window is a miss |
| `keepRatio` | 0.97 | at or above this share a window is settled ... (on the Index, SteamVR's half-rate lock reads 44.1 to 45.1 of a 45 target, which 0.99 kept from settling) |
| `headroom` | 0.80 | ... if the GPU time fits in this share of the frame budget (or is unknown) |
| `gpuBound` | 0.70 | a miss counts toward stepping down only while the GPU time fills this share of the budget (or is unknown) |
| `downWindows` | 2 | consecutive misses before stepping down |
| `upWindows` | 8 | consecutive settled windows before stepping up |
| `cooldown` | 3.0 s | no step sooner after the last one: a DLSS or scale change recreates render targets |

- `control.Begin(index, now)`: start (or restart) at a step, clamped to the ladder; resets the counts and starts
  the cool-down.
- `control.Sample(now, frames, targetRate, gpuMs, budgetMs)`: adds `frames` (eye pairs since the last call) and a
  GPU time to the window. When the window is complete it computes `rate` and the mean `gpuMs`, updates the miss and
  settled counts, and returns the step and a reason key (`down` or `up`) when it moves, otherwise the step and nil.
  Moving resets both counts. A step never passes either end of the ladder. `control.cpuLimited` is true after a
  window that missed while the GPU had room: the game, not the GPU, lost those frames, so a cheaper step would not
  bring them back and the controller holds its step.

The asymmetry is deliberate: two missed seconds step down, eight settled ones step up, so a rate that wavers around
the target does not walk the ladder. Tests: `companion/tests/vr_perf_harness.lua` (`control_*`, including a
controller without a cool-down that the cool-down check must catch, and one that ignores the GPU, which the hold
check must catch).
