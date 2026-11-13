# 0202: True stereo shares the frame's work and keeps each view's history

- Status: Accepted 2026-11-13 for V7 on the branch `vr6`; reaching `main` needs the user's approval. The user approved V6 and V7 on 2026-11-13 and they were merged to `main`.
- Decided by: Claude, building V7 to [ADR 0198](0198-vr-true-stereo-by-swapping-the-eyes-state.md).
- Refines: ADR 0198, which named the per-eye state in outline.

## Context

ADR 0198 chose two passes a frame with each eye's state behind the runtime's own accessors. Building it showed which
state belongs to a view and which to the frame, and three pieces the outline did not name: the sky, the neural
radiance cache's library, and what the right eye may read from the left's state.

## Decision

**Per eye** (the left eye keeps the default state; the right eye's is a second set made when true stereo starts and
released when it stops):

- `Resources`: every ray-tracing output and history, RTXDI's reservoirs among them, and the constants.
- ReSTIR GI, Ray Reconstruction, the neural radiance cache and SHaRC: each holds per-pixel history or a per-frame
  begin/end cycle with the library.
- The camera: each eye's camera stands in for Main while that eye is traced, from the centre camera's view and the
  eye's offset and off-centre frustum.
- The sky's cloud history (it reprojects with the eye's own camera) and its aerial perspective volume, fitted to the
  eye's off-centre frustum by shifting the volume's forward vector, so the shader needs no change.

**Once a frame, on the centre camera**: the scene (BLAS, TLAS, lights, particles), the sky's integrators and LUTs,
the froxel volumetrics (their camera is the centre's, whose frustum holds both eyes, so both eyes read one grid), and
auto exposure, which the left eye adapts and both use. The right eye reads the frame's TLAS, noise, white texture, sky
probe and matte and the atmosphere LUTs from the default state.

**The NRC library** starts with the first context and stops with the last: it refuses a second `Initialize`, and one
context's `Shutdown` would stop the other's, which would have switched both eyes to importance sampling.

**Where it applies**: only with Ray Reconstruction, which denoises inside the upscaler and so keeps all of its history
in per-eye state (NRD, TAA and DLSS without it would each need more instances), and with the physical sky (the
rasterized sky's matte is a picture of the centre view). Otherwise the runtime keeps the warp and the page says why.

## Consequences

- No shader changes; flat and warp rendering run the same code with the centre selected.
- Two caches learn the same scene; their pictures agreed in the PoC (each stereo eye correlates 0.93 with its own
  warped eye), and both eyes share one exposure.
- The second eye costs its own path tracing, denoising and upscaling, but not the frame's shared work or the warp:
  1.19 times the warp's GPU work on the Index and 1.28 times in the simulated headset, at the top step.
