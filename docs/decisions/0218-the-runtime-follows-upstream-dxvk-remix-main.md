# 0218. The runtime follows upstream dxvk-remix main, one patch per update

Date: 2026-11-14. Status: accepted (the user: "Make the dxvk-remix up-to-date from upstream. Test in game and post to
github and workshop.").

## Context

The RTX package's `d3d9.dll` is built from `sambow23/dxvk-remix-gmod` at `c6b48ed1` (`gmod-numos3`) and this
repository's patches ([ADR 0033](0033-one-repository-package-inputs-in-git-lfs.md),
[ADR 0034](0034-the-runtimes-build-inputs-recorded.md)). Patch 0001 is the user's snapshot of that fork with NVIDIA's
`remix-1.6.1` (2026-10-21) merged in, so the runtime was at RTX Remix 1.6.1 plus the fork's work plus patches
0002-0092. Upstream NVIDIA `dxvk-remix` `main` had moved 57 commits on by 2026-11-14 (`2b46bed0c`): the core fixes
patch 0091 ported early, eye shading fixes (corrupted reflections, dark eye whites, parallax), BLAS refit and
bindless buffer fixes, decal and PSR fixes, skinning fixes, particle fixes and features, USDG mesh packages, a water
simulation, an alpha blend dissolve for faded objects, RTXDI's compact reservoirs and Hydra AOVs. `sambow23`'s fork
itself has not moved since 2026-08-31.

## Decision

1. **One patch per upstream update, on top of the series.** Patch 0093 is upstream's `remix-1.6.1..2b46bed0c`
   merged into the runtime with `remix-1.6.1` as the merge base (a temporary `git replace --graft` of patch 0001's
   commit gives git that base, since 0001 is a snapshot and not a real merge), squashed into one commit. `base.json`
   keeps the fork's public commit, which GitHub's package workflow builds from, and patches 0001-0092 stay byte for
   byte; the update is one reviewable file. The next update merges `2b46bed0c..<new main>` the same way as 0094.
2. **RTXDI follows upstream's recorded commit.** The tree records upstream's `dc8eb033` (RemixProjGroup/RTXDI), and
   `runtime/submodules/rtxdi.patch` now holds the fork's Numos volumetrics (`30431e9..3b39a7c`) merged onto it; before,
   it held 1.6.1's RTXDI changes on the fork's `3b39a7c`. The one conflict, `evalVolumetricNEE`'s return, keeps both
   upstream's fetch in uniform control flow (NVBUGS 7020086) and the fork's consumer gain and edge falloff.
3. **The fork's Remix API line stays compatible: 0.1000.2.** Upstream's new functions (`SetWaterSim`,
   `AddWaterDisturbance`), struct types and the sludge category bit come after the fork's own (slots 42-43, types
   29-33, bit 28), because the package's modules were built against 0.1000.1. Upstream's client-sized interface
   write is kept and taught the fork's sizes: a 0.1000.0 or 0.1000.1 client is written the 41 functions it knows, not
   344 bytes into its 328. Upstream reads its new material texture transform fields from clients newer than 0.6.6,
   which every 0.1000.x client is; here they are read only from 0.1000.2 clients.
4. **Where both sides took the same resource, the fork keeps its place and upstream moves.** The alpha blend dissolve
   mode moves to flags0 bits 3-5 (the texture flags' bits 19-30 hold the MMD alpha cutoff of
   [ADR 0081](0081-mmd-alpha-texture-category.md)); the camera material flags move to opaque flag offsets 11 and 12;
   a particle grows from 48 to 64 bytes so the fork's float `timeToLive` (the fix for snow that stopped at high frame
   rates) and upstream's per-particle picking value both fit; `RaytraceArgs` and the particle constants gain one
   padded row; particle bindings 64 and 65 follow the fork's 63.
5. **Upstream's lock in `remixapi_SetConfigVariable` is left out.** The fork's `readOption` takes the option update
   mutex itself (patch 0029); taking it around the call as upstream does would deadlock the game thread.
6. **The package ships upstream's new runtime file**: `usdg.dll` beside `d3d9.dll`, which links it, and its
   `usd/plugins/usdg/resources/plugInfo.json`; the categories and particle schemas carry upstream's additions.
   `usdg-converter.exe`, a packaging tool the build installs too, is not shipped.

## Consequences

- The runtime is NVIDIA's `main` of 2026-11-14 plus the fork plus this project's patches; RTX Remix's own fixes reach
  players without waiting for a release.
- Upstream's 0091-equivalent core fixes are now in the tree twice (identical hunks merge to one); 0091 stays in the
  series unchanged.
- Users' saved `rtx.eye.irisDepth` is no longer read: upstream replaced it with `rtx.eye.irisDepthScale` (relative
  to a real eye) and `rtx.eye.limbalRingScale`.
- A future upstream update is the same procedure; the merge base is the last merged upstream commit, recorded in the
  patch's message and in [runtime/README.md](../../runtime/README.md).
