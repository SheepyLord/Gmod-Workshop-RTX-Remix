# vr_perf_harness.lua

Offline LuaJIT cases for VR V6's quality ladder ([`cl_perf_ladder.lua`](../../vr/addon/lua/nlvr/modules/cl_perf_ladder.lua.md))
and Auto controller ([`cl_perf_control.lua`](../../vr/addon/lua/nlvr/modules/cl_perf_control.lua.md)). It loads the two
files from the repository and stubs only `math.Clamp`.

```
luajit companion/tests/vr_perf_harness.lua <repository root> <scenario>
```

| Scenario | Checks |
|---|---|
| `ladder_order` | the top step is V1's preset; every lower step costs less and never raises scale, DLSS, bounces or volumetrics; every step is one the runtime accepts; indices clamp |
| `ladder_ceiling` | the render-scale ceiling lowers a step but never raises one, is clamped, and ignores NaN |
| `ladder_start` | low tier or below 12 GB start at the floor (V1's 0.5 cap); medium or below 16 GB at step 3; otherwise step 1 |
| `control_down` | two missed windows step down one rung, not inside the cool-down; the step lands as it ends |
| `control_cooldown` | a sustained miss steps one rung per cool-down; a controller without a cool-down must fail this check |
| `control_up` | eight settled windows with GPU headroom step up; on target without headroom it never moves |
| `control_bounds` | no step past either end; `Begin` clamps |
| `control_no_oscillation` | a rate wavering across the target (a missed window with the GPU busy, then a settled one) never moves the ladder |
| `control_window` | frames are averaged over the whole window |
| `control_half_rate` | SteamVR's half-rate lock as the Index reads it (44.1 to 45.1 of 45) settles and Auto climbs; a 0.99 keep ratio never would |
| `control_cpu_bound` | frames missed while the GPU has room never step down and set `cpuLimited`; the same misses with the GPU over its share do; a controller that ignores the GPU must fail the hold check |

Prints `PASS <scenario>`; exits non-zero on a failed assertion. Run by [`vr_perf_test.py`](vr_perf_test.py.md).

V8: `frame_generation_rates` loads `cl_perf.lua` and checks `Rates` (half the refresh with frame generation, the full
refresh without, on by default, broken refreshes read as 90 Hz) and `Smoothed` (bit 0x08 of the reprojection flags).
