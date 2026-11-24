# 0265. The runtime merges upstream dxvk-remix main of 2026-11-23

Date: 2026-11-24. Status: accepted (the user: "The most recent dxvk carries a few useful fixes. Please up our package's
remix version and test carefully.").

## Context

[ADR 0218](0218-the-runtime-follows-upstream-dxvk-remix-main.md) brought the runtime to NVIDIA's `dxvk-remix` `main` of
2026-11-14 (`2b46bed0c`, runtime patch 0093) and set the procedure for the next update: merge `2b46bed0c..<new main>`
the same way, as one patch. By 2026-11-23 `main` had moved 25 commits to `58ac72412`. Among them: GPU and CPU crashes
under VRAM pressure and invalid input fixed (REMIX-6191), VRAM logging and tracking, a merged BLAS that wrote its
transform into shared mesh geometry (GPU-instanced draws in the wrong place), diffusion-profile SSS on view models, fewer
locks on the draw path (RtxOption reads, the bridge's and DXVK's thread pools, 64 command buffers per queue), faster
texture budget lookups and D3D9 light conversion, colour grading after either tonemapper, the alpha blend dissolve's 3D
noise and cutout on alpha-blended parts, particle birth masks, the revert of the GH:1112 translucent resolve change (it
broke decals behind transparent surfaces), hand-authored NoSave options kept in saved layers (GH:798), SHaRC tweaks, and
an experimental GPU-resident scene for API hosts. 99 of the 194 files upstream changed are files this project's patches
change too; 49 conflicted.

## Decision

1. **Patch 0106 is upstream's `2b46bed0c..58ac72412`**, merged onto patches 0001-0105 with `2b46bed0c` as the merge
   base (a temporary `git replace --graft` of 0093's squashed commit onto it) and squashed into one commit on the fork
   clone's branch `claude/upstream-main-1123`. `base.json`'s fork commit and patches 0001-0105 stay as they are. The
   next update merges `58ac72412..<main>` the same way.
2. **Remix API 0.1000.3.** Upstream's `SceneInstanceAdd`, `SceneInstanceUpdate`, `SceneInstanceRemove` and
   `UpdateMaterial` (0.6.12) follow `SetWaterSim` and `AddWaterDisturbance` (slots 43-46, 376 bytes); the particle spawn
   mask struct is type 34 (33 upstream, where the fork's `PARTICLE_SCREEN_SIZE_EXT` stands). A 0.1000.2 client is
   written its 344 bytes and a 0.1000.0 or 0.1000.1 client its 328, so the package's modules, built against 0.1000.1,
   load unchanged. The four functions answer `GENERAL_FAILURE` unless `rtx.gpuResidentScene` is on (off by default;
   nothing in the package turns it on).
3. **Where both sides took the same resource, the fork keeps its place and upstream moves**, as in ADR 0218:
   upstream's view-model material bit is texture flag bit 31 (22 upstream; bits 19-30 hold the MMD alpha cutoff of
   [ADR 0081](0081-mmd-alpha-texture-category.md)); `RtInstance` holds the fork's MMD alpha key beside
   upstream's original mesh members (832 bytes, every member in its copy constructor); the particle constants take one
   more padded row (480 bytes, 464 upstream).
4. **Upstream's behaviour where it fixes a fault, the fork's structure where the fork had one:**
   - a failed queue submission or fence wait ends the process with the GPU crash report, as upstream now does (a
     dropped command list never signals, so later waits hung), through the fork's single `handleDeviceLost(reason)`;
   - a trivially copyable option is read without the mutex from upstream's published copy, which a re-resolve cannot
     leave half written, inside the fork's `kLockFreeRead` branch; the fork's revision counter and hash set copies stay;
   - a failed RTX IO read keeps its target until its reads complete and is never published, as upstream does; with the
     fork's upload generations it is marked failed only while its generation is current;
   - texture categories keep the fork's `TextureCategorySets` (effect colours, imported characters' smooth normals,
     the session's categories); upstream's new `getTargetBuffer()` uses the fork's effect colour rule; under upstream's
     new option lock around the fixed-function stage loops the fork reads only its copies, refreshed before the lock
     is taken (the update mutex is not recursive);
   - the fork has no local tonemapper, so upstream's changes to it stay out; the global tonemapper's colour grading
     uses upstream's shared function, which clamps a saturation above 1.
5. **The package ships upstream's changed particle schema** (`RemixParticleSystem/generatedSchema.usda`, the birth mask
   properties) with the new `d3d9.dll`.

## Consequences

- RTX Remix's fixes of the week reach players: above all the VRAM pressure crashes, the GPU-instanced draw position,
  view-model SSS and the decal regression of GH:1112.
- A GPU queue error that the runtime used to wait out now ends the game with the GPU crash dialog; upstream found such
  waits hung, and the crash report names the memory state.
- Remix API clients built against 0.1000.3 can call the GPU-resident scene functions; the package's own modules do not.
- Done in the fork's tree: patch 0106 also fixes what the merge left to the build (the spawn shader's birth mask
  rejection in the fork's `SpawnSample` form, upstream's spawn mask test fitted to type 34) and what the PoC found in
  the first build: its D3D9 stage loop refreshed the category copies under the option lock, locking the update mutex
  twice on one thread, so the game crashed (`std::system_error`, EDEADLK) at its first draw after any option changed.
