# vr_stereo_probe.lua

Test-only Lua for VR V7 (true stereo, [ADR 0198](../../docs/decisions/0198-vr-true-stereo-by-swapping-the-eyes-state.md)),
appended to the production driver's script by [`vr_stereo_poc.py`](vr_stereo_poc.py.md). It uses the driver's `phase`
and `emit` and the `nlvr` module global, and waits until `NLVR.Debug.perf` exists.

It pins one quality step (`nl_vr_quality`, step 1 unless a caller defines `S_STEP`) so the modes compare at the same
step, then switches `nl_vr_stereo`. Timeline from the first active frame:

| Seconds | What |
|---|---|
| 2 | `warp`: one view warped to both eyes |
| 16 | `stereo`: each eye path traced |
| 32 | `warp-again` |
| 44 | `stereo-again`: the right eye's state is made a second time |
| 58 | settings put back (`end` mark) |

Nine seconds into each phase it captures through `nlvr.Capture("v7-<phase>", flags)`: the eyes, overlays and the
mirror, and in the warp also the centre view (true stereo has none). The driver's capture queue waits until the
overlays are painted. Every 0.5 s it adds a `trace` row: the runtime's `stereoActive`, GPU work and span, the traced,
eye and centre sizes, the frame counters, and the add-on's step, rate and stereo setting. Rows go out as `V7-stereo`
records; leaving the active phase early puts both settings back.
