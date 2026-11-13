# cl_perf_ladder.lua

VR V6's quality ladder ([ADR 0199](../../../../../docs/decisions/0199-vr-auto-quality-ladder.md)): seven steps, highest
quality first, each a complete description of what the runtime renders.

| Step | Render scale | DLSS | Bounces | Volumetrics | Fine clouds |
|---|---|---|---|---|---|
| 1 full | 1.00 | Performance | 1-4 | yes | yes |
| 2 high | 1.00 | Performance | 1-3 | yes | no |
| 3 balanced | 0.90 | Performance | 1-3 | yes | no |
| 4 fast | 0.80 | Ultra Performance | 1-3 | yes | no |
| 5 faster | 0.70 | Ultra Performance | 1-2 | no | no |
| 6 low | 0.60 | Ultra Performance | 1-2 | no | no |
| 7 floor | 0.50 | Ultra Performance | 0-1 | no | no |

Step 1 is V1's fixed preset, so the top step renders as V1 to V4 did.

- `Ladder.Count()`: the number of steps.
- `Ladder.Step(index, scaleCeiling)`: a copy of the step (`index` clamped to the ladder), with its render scale
  capped by the ceiling (the player's `nl_vr_render_scale`, itself clamped to 0.25-1.5). The ceiling never raises
  a step's scale.
- `Ladder.Start(tier, vramMib)`: where Auto starts. A low performance tier or less than 12 GB of VRAM starts at the
  floor, which keeps V1's 0.5 cap for such cards; a medium tier or less than 16 GB at step 3; anything else (or
  nothing known) at step 1.

Pure Lua; no engine calls. Tests: `companion/tests/vr_perf_harness.lua` (`ladder_*`).
