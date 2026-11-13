# VR V6 (performance) and V7 (true stereo): plan

The user, 2026-11-13: "Skip V5, currently make it single player only. Proceed directly to V6 and V7."
Claude writes the code (the user's choice the same day); V6 is tuned at the Index's **current** refresh rate only,
because SteamVR's settings are never changed ([the VR rules](../../AGENTS.md)). Branch `vr6`, worktree
`out/worktrees/vr6`; the runtime tree is `out/worktrees/r17/out/runtime-src`.

Both milestones reach `main` only when the user approves them.

## What exists today (surveyed 2026-11-13)

- **Nothing adapts.** The VR preset is a fixed option layer `! VR session` at priority `0xFFFFFFFF`, built once in
  `RtxVr::initialise` (`rtx_vr.cpp:372-382`): DLSS Performance with Ray Reconstruction (TAAU without DLSS), 1-4
  bounces, frame generation and post effects off. It outranks the User layer, so Lua's
  `RemixConfig.SetConfigVariable` cannot reach any of its fourteen keys while VR runs.
- **Render scale is latched at Start** (`nl_vr_render_scale`, capped at 0.5 when the page warns). No `rtxvr` export
  carries it afterwards, and the eye images are allocated once (`rtx_vr.cpp:383-385`). The centre projection does
  already change live, for IPD (`rtxvr_UpdateEyes`).
- **Timing is measured but unused.** The runtime fills ~30 status fields (GPU ms by pass, pose age, wait times) and
  the module adds OpenVR's frame timing and cumulative stats; `native.Info()` carries all of it to Lua. The page
  prints some of it at 2 Hz. Nothing acts on it, and nothing reads Motion Smoothing's state.
- **Tier and VRAM** come from the loader's `status.json`; the page warns below 12 GB or on the low tier.

## V6: Auto preset and ladder

### Design

1. **A live quality call.** New export `rtxvr_SetQuality(const rtxvr_Quality*)`, API version 4. It records a request
   under the request mutex; the render thread applies it in `beginFrame`, because the option layer, the eye images
   and the centre projection all belong to the render thread.
   - The fields are the ladder's levers: `renderScale`, `dlssQuality` (the `qualityDLSS` enum),
     `pathMinBounces`/`pathMaxBounces`, and a `flags` word for the costly effects (volumetrics, cloud detail).
   - Applying it rewrites the layer's values in place and calls `applyPendingValues`; a changed `renderScale`
     recomputes the centre projection and reallocates the eye images on the render thread, as `initialise` does.
   - `rtxvr_Status` gains the applied values, so Lua never guesses what is live.
2. **The ladder** is one ordered table, highest quality first, in the add-on. Each step names the four levers. The
   lowest step is DLSS Ultra Performance, 1-2 bounces, volumetrics off and the lowest render scale.
3. **The controller** lives in a new add-on module `cl_perf.lua`. Every frame it reads the module's counters, keeps
   a short window of frame intervals and reprojection flags, and compares the measured rate against the target
   (half the headset refresh). It steps **one** rung at a time with hysteresis: down after a sustained miss, up only
   after a longer settled period with headroom, and never within a cool-down of the last step, because a DLSS mode
   or render-scale change recreates render targets and costs a hitch.
4. **The page** gains a quality setting (Auto, or a fixed step), the ladder's current step with its reason, and the
   measured rate against the target. The in-headset VR settings panel gets the same setting, since it reads the
   page's option list.
5. **Start** chooses the first step from the tier and VRAM instead of only capping the render scale.

### Tests

- Offline (LuaJIT): the ladder's order and bounds; the controller's hysteresis, cool-down, and that it never steps
  more than one rung or past either end; a mutant that drops the cool-down must fail.
- Native (CTest): the quality struct's ABI; `SetQuality` before Start, with a bad struct size, and out of range.
- Runtime unit test: the layer rewrite keeps the keys it does not name, and the eye size follows the scale.
- PoC: a VR session that forces each rung and records the applied values and the measured rate; then an Index
  session at the current refresh rate with Auto on, from a deliberately too-high step, which must settle without
  oscillating.

## V7: true stereo

### The spike's decision

Path tracing each eye separately, with the per-eye state swapped behind the existing accessors
([ADR 0198](../decisions/0198-vr-true-stereo-by-swapping-the-eyes-state.md)). The alternative, one double-wide
picture, needs the eye chosen from the pixel in about 143 shader sites across 35 files, a seam that eight spatial
filters would read across, and two NGX features on subrects; NRD cannot take two cameras in one instance at all.
Swapping the state instead leaves every shader and both upscalers untouched: `getResources()` (38 uses) and
`getCamera()` (40 uses) are the only paths to the per-frame state, so making those two accessors eye-aware carries
the whole pass chain with them.

### Design

1. **Per-eye state.** `DxvkObjects` keeps the ray-tracing `Resources`, the denoisers and the DLSS/DLSS-RR contexts
   in a small array with an active index; the accessors return the active one. Each eye therefore keeps its own
   history, ping-pong parity, previous-frame stamps and upscaler feature, and each advances once per frame, so no
   frame-keyed mechanism has to learn about eyes.
2. **Eye cameras.** `RtxVr` builds each eye's view (the head pose plus the eye offset in world units) and its
   asymmetric projection from the eye's tangents. They are two camera types beside Main, so `RtCamera`'s history
   and jitter work unchanged.
3. **The split.** `RtxContext::injectRTX` runs scene preparation, the atmosphere integrators, NRC, SHaRC, the NEE
   cache and the froxel volumetrics **once** on the centre camera, whose frustum already covers both eyes, and then
   runs path tracing, resampling, denoising, upscaling and post-processing **once per eye**.
4. **Output.** Each eye's final image is copied into its eye image; the warp is not used. The mirror takes the left
   eye as before.
5. **A quality mode, not the default.** True stereo is a step above the warp, chosen on the page and by Auto only
   where it fits the frame budget. Without Ray Reconstruction (no DLSS) the warp stays, because NRD would need two
   instances per denoiser role.

### What it costs

About 1.6 times today's traced pixels and the same again in upscaling, plus a second copy of every history in VRAM
and a second recording of the pass chain on the CPU. V6's ladder is what makes it usable: true stereo starts at a
lower rung.

### Tests

- Native and runtime unit tests for the eye cameras' projections and for the state swap's bookkeeping.
- Offline: the mode's selection rules (never without Ray Reconstruction).
- PoC and Index: both eyes' captures compared against the warp's, and the measured cost of each mode.
