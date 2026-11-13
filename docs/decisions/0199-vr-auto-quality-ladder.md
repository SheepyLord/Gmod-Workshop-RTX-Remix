# 0199: VR's Auto quality: a seven-step ladder moved live by the add-on

- Status: Accepted 2026-11-13 for V6 on the branch `vr6`; reaching `main` needs the user's approval. The user approved V6 and V7 on 2026-11-13 and they were merged to `main`.
- Decided by: Claude, building V6 at the user's request ("Proceed directly to V6 and V7"), tuned at the Index's
  current refresh rate only (the user's choice).
- Supersedes: [ADR 0151](0151-the-fixed-v1-vr-preset.md)'s fixed preset as the only one; its values are the top step.

## Context

V1 to V4 render VR with one fixed preset: a runtime option layer `! VR session` (DLSS Performance with Ray
Reconstruction, 1-4 bounces) built at the first VR frame, and a render scale latched at Start (0.5 on a low tier or
below 12 GB). The layer outranks the User layer, so nothing in Lua can reach its keys, and no `rtxvr` export carried
the scale after Start. The runtime and the module measured everything needed (GPU time by pass, OpenVR's frame
timing and cumulative stats), but nothing acted on it.

## Decision

1. **A live quality call in the runtime** (patch 0087, `rtxvr_SetQuality`, API version 4). A step has five levers:
   render scale (0.25-1.5 on SteamVR's recommended eye size), DLSS mode (Ultra Performance to Quality), the minimum
   and maximum bounces (0-16), and two costly effects as flags (froxel volumetrics; the sky's finer cloud sampling,
   32 instead of 16 view samples). The request is recorded under the request mutex; the render thread writes the
   values into the session layer with `setDeferred(value, layer)` and applies them, and reallocates the eye images
   when the scale changes. The centre projection follows the scale at once, as it already did for an IPD change.
   The status reports the step in use. The top step is V1's preset, so an untouched session renders as before.
2. **The ladder is the add-on's**, seven steps from that top step down to a floor of scale 0.5, Ultra Performance,
   0-1 bounces and no effects ([`cl_perf_ladder.lua`](../../vr/addon/lua/nlvr/modules/cl_perf_ladder.lua.md)).
   Each step costs less than the one above on at least one lever and more on none.
3. **The controller** ([`cl_perf_control.lua`](../../vr/addon/lua/nlvr/modules/cl_perf_control.lua.md)) holds half
   the headset's refresh, the rate SteamVR's Motion Smoothing fills in. It counts eye pairs over one-second windows;
   two missed windows step down, eight settled windows with the GPU inside 80 % of the frame budget step up, never
   more than one rung, never past either end, and never within three seconds of the last step, because a DLSS or
   scale change recreates render targets.
4. **Start** renders at the step Auto begins from, so the first frames need no resize: the floor for a low tier or
   below 12 GB (V1's 0.5 cap), step 3 for a medium tier or below 16 GB, otherwise the top.
5. **The player's controls**: `nl_vr_quality` (0 Auto, 1-7 a fixed step) on the VR page and the in-headset
   settings panel; `nl_vr_render_scale` becomes a ceiling on every step and takes effect at once. The page shows
   the step, why it is there, and the measured rate and GPU time against the target and budget.

## Consequences

- Older runtimes (API 3) are refused at Start with the page's runtime message; the module and the runtime ship
  together in the package.
- A step change costs a hitch: a DLSS mode or scale change recreates the ray-tracing outputs, a scale change also
  the eye images. The cool-down and the asymmetric up/down counts keep those rare.
- Tuned only at the Index's current 90 Hz: the target follows the reported refresh, but 80, 120 and 144 Hz were not
  measured, as the user chose.
- The quality layer's own presets are untouched outside VR; Exit releases the session layer with all five values.
