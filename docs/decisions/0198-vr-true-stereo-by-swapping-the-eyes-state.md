# 0198: True stereo path traces each eye with its own swapped state

- Status: Accepted 2026-11-13 for V7 on the branch `vr6`; reaching `main` needs the user's approval. The user approved V6 and V7 on 2026-11-13 and they were merged to `main`.
- Decided by: Claude, from the V7 design spike the [VR plan](../handover/VR-plan.md) asked for.

## Context

V1 to V4 path trace **one centre view** per frame, a symmetric frustum covering both eyes, and warp it to each eye
with depth (`RtxVr::output`, `vr_warp.comp.slang`). V7 is to path trace **each eye with its own history** as a
quality mode. The plan left the approach to a spike, between two passes per frame and one double-wide picture.

The runtime has no notion of a second view. There is one main camera, one `Resources` holding every ray-tracing
target, and one instance of each denoiser, upscaler and history, all advancing once per presented frame.

## The two options, as surveyed

**One double-wide picture** keeps that per-frame rhythm: one pass, so every ping-pong, parity, previous-frame stamp
and cache cadence stays exactly as it is, and both eyes share one auto exposure. Its cost is in the shaders:

- The eye must be chosen from the pixel in about **143 `cb.camera` uses across 35 shader files**, plus 66 uses of
  `camera.resolution`, and the pixel/UV helpers in `camera.slangh`. Jitter and motion vectors become per half.
- **Eight spatial filters read across the seam**: RTXDI spatial reuse (30 px), ReSTIR GI spatial reuse (85/200 px),
  composite's neighbour reads, the Ray Reconstruction disocclusion blur, TAA, the bloom pyramid, NRD's blur and the
  256x128 sparse-rendering tiles. Temporal reprojection that lands in the other eye must be rejected.
- **DLSS-RR takes one camera's matrices per call**, so it needs two NGX features on subrects; the SDK has the
  subrect fields but the runtime never sets them.
- **NRD cannot do it at all**: one matrix pair per instance, and its `rectOrigin` shifts only the G-buffer guides,
  behind a compile switch in a prebuilt DLL.

**Two passes per frame** leaves every shader alone, but each eye needs its own history, and the survey found the
per-frame scratch aliasing would let one eye overwrite the other's history, with TAA parity, RTXDI parity, the
"written last frame" stamps, the camera update guard and the random seed all keyed on the frame number.

## Decision

**Two passes, with the per-eye state swapped behind the existing accessors.** Every one of those frame-keyed
mechanisms is a property of the state it lives in, so giving each eye its own copy answers all of them at once
instead of teaching each one about eyes:

- `DxvkObjects` holds the ray-tracing `Resources`, the denoisers and the DLSS and DLSS-RR contexts per eye with an
  active index. `getResources()` (38 call sites) and `SceneManager::getCamera()` (40) are the only ways the pass
  chain reaches that state, so making those two accessors eye-aware carries every call site unchanged.
- Each eye's state advances once per frame, so its ping-pongs, parities, stamps and upscaler history are already
  consistent; nothing keyed on the frame number has to change.
- The eyes are two camera types beside Main, which is how the runtime already keeps separate histories and jitter
  for the portal and view-model cameras.
- `RtxContext::injectRTX` splits into once-per-frame work on the centre camera (scene preparation, the atmosphere
  integrators, NRC, SHaRC, the NEE cache, froxel volumetrics, whose frustum already covers both eyes) and per-eye
  work (path tracing, resampling, denoising, upscaling, post-processing).
- True stereo is a **quality mode**, not the default, and is offered only with Ray Reconstruction, where NRD is off.
  Without DLSS the warp stays.

## Consequences

- No shader file changes and no seam, so flat rendering cannot regress through this work and neither eye can read
  the other's pixels. That matters most for a mode whose whole purpose is image quality.
- VRAM holds a second copy of every ray-tracing target and history, and the CPU records the pass chain twice.
- Roughly 1.6 times today's traced pixels and the same in upscaling; V6's ladder is what keeps it affordable, and
  true stereo starts at a lower rung.
- The double-wide option stays open: it is the cheaper one per frame, and a later milestone could take it once the
  seam and the NGX subrects are proved. This decision does not foreclose it.
