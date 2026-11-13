# vr_quality_probe.lua

Test-only Lua for VR V6, appended to the production driver's script by
[`vr_quality_poc.py`](vr_quality_poc.py.md). It uses the driver's `phase` and `emit` and the `nlvr` module global, and
waits until `NLVR.Debug.perf` exists (the add-on's [`cl_perf.lua`](../../vr/addon/lua/nlvr/modules/cl_perf.lua.md)).

Timeline from the first active frame:

| Seconds | What |
|---|---|
| 3 to 27.5 | `nl_vr_quality` 1 to 7, 3.5 s each; a `fixed` row per step 0.3 s before the next: the module's report and the runtime's applied step (`qualityRenderScale`, `qualityDlss`, bounces, `qualityFlags`, `qualityChanges`), the eye, centre and traced sizes, and the recommended eye size |
| 27.5 | step 1 |
| 28.5 | `nl_vr_quality 0`: Auto from the top, with frames missed while the GPU has room (`auto` mark) |
| 38.5 | frames missed with the GPU over its budget (`load` mark) |
| 68.5 | the session's own readings again (`unload` mark) |
| 138.5 | settings put back (`end` mark) |

**Staged misses.** `fps_max` cannot be set from Lua in a game (GMod blocks it), and a frame cap would be a miss the
GPU did not cause, which Auto rightly ignores. So from the `auto` mark the probe replaces `nlvr.Info`, through which
the add-on measures, with a wrapper over the real function: it keeps 40 % of the session's frames, and reports the GPU
(`gpuMsWork` and `gpuMsTotal`) at 30 % of the frame budget (`auto` phase) or 150 % (`load` phase). From `unload` every frame counts again and the GPU
time is the session's own, the frame counter kept continuous. Every other field is the session's real state, and the
probe's own rows read the real function. Everything after the measurement is the production path: the controller,
`SetQuality`, and the runtime applying the step.

From the `auto` mark to the end it adds a `trace` row every 0.5 s (the module's report, with `cpu_limited`, and the
runtime's applied step). Rows go out as `V6-quality` records in batches of 64 and at the end; leaving the active phase
early also puts `nlvr.Info` and `nl_vr_quality` back, so the driver's settings check holds. `Q_CPU_SECONDS`,
`Q_DOWN_SECONDS` and `Q_UP_SECONDS`, if a caller defines them, change the three Auto phases.
