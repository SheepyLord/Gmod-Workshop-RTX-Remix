# cl_perf.lua

VR V6's quality module ([ADR 0199](../../../../../docs/decisions/0199-vr-auto-quality-ladder.md)): it chooses the
ladder step the runtime renders at and reports it. It renders nothing itself.

- **Start.** On its first frame it reads the headset's refresh from `native.Info()`, sets the target with `Rates`
  (V8, [ADR 0205](../../../../../docs/decisions/0205-frame-generation-in-vr-is-motion-smoothing.md)): half of it with frame generation on (the
  rate SteamVR's Motion Smoothing fills in), all of it with `nl_vr_frame_generation` 0; the frame budget is
  `1000 / target` ms. Changing the setting re-targets at once and measures afresh from the step in use. It applies the step
  the VR page chose for this start (`NativeLoaderVR.StartStep()`): the pinned step, or Auto's first step from the
  GPU's tier and VRAM.
- **Auto.** Every 0.25 s it reads the eye pairs submitted (rendered frames in a simulated session, which submits
  none) and the runtime's last GPU work (`gpuMsWork`: on a headset the frame's total `gpuMsTotal` also holds the
  queue's waits for the CPU, 6 to 10 ms at 45 fps on the Index; the total is the fallback), and feeds them to [`cl_perf_control.lua`](cl_perf_control.lua.md). A step
  the controller returns is applied with `native.SetQuality`; a refused step is reported and the controller goes
  back to the step in use.
- **Fixed steps.** `nl_vr_quality` above 0 pins that rung (clamped to the ladder); setting it back to 0 resumes
  Auto from the step in use. The `setting` event applies the change at once.
- **Render scale.** `nl_vr_render_scale` is a ceiling on every step's scale
  ([`cl_perf_ladder.lua`](cl_perf_ladder.lua.md)); a change callback re-applies the current step, so lowering it
  takes effect at once. The callback is removed with the module.
- **Report.** `NLVR.Debug.perf`: `step`, `step_name`, `reason` (a key: `gpu`, `hand`, `auto`, `down`, `up`; the
  VR page owns the translated words), `render_scale`, `dlss`, `min_bounces`, `max_bounces`, `volumetrics`,
  `fine_clouds`, `rate`, `gpu_ms`, `cpu_limited` (the last window missed while the GPU had room, so Auto holds),
  `target_rate`, `budget_ms`, `auto`, `changes`, `error`, `frame_generation` and `motion_smoothing` (`supported`,
  `enabled`: SteamVR's setting, read by the module; `generating`: a frame Motion Smoothing made, seen in the
  compositor's frame timing (`module.Smoothed`, bit 0x08) within the last 3 s). The table is removed when the session
  stops.

Pure helpers for tests: `module.Rates(refresh, generation)` -> target rate, budget ms; `module.Smoothed(flags)`.

Inputs: the native module's `Info()` and `SetQuality()`; `nl_vr_quality`, `nl_vr_render_scale`, `nl_vr_frame_generation`; the page's
`NativeLoaderVR.StartStep`. Outputs: the runtime's quality step; `NLVR.Debug.perf`. No files, no network.
