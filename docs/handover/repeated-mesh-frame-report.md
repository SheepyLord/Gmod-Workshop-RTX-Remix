# Repeated meshes in Modern House

Codex, 2026-11-27. Branch `codex/sky-postfx-frame-time` in the task worktree. Runtime patch 0124 extends the staged [lower-cloud and post-effect changes](renderer-frame-output-report.md) with [ADR 0276](../decisions/0276-share-frequently-rebuilt-repeated-meshes.md). The comparison baseline for this change is the package through 0123.

## Implementation

The acceleration-structure manager records substantial duplicate mesh work only when it submits merged geometry to the GPU. Three successive rebuilt frames can qualify a rigid mesh for its existing object-space BLAS. The current instance table determines whether sharing is still worthwhile and compatible. Each copy retains its own top-level placement. The [Modern House probe](../../tools/qa/repeated_mesh_probe.lua.md) repeats the original two routes with PBR enabled.

The original field trace counted the same triangle and buffer range 82 times. The runtime uses the actual geometry entry and current micromap requests to decide which copies are compatible. The first prototype kept all 82 copies merged. The second shared the right group and exposed a 573-triangle full build still issued every frame. The final change distinguishes retaining the already-built structure from issuing a Vulkan update. It checks the full input record, including the identity of the pinned micromap.

## Verification

The local evidence folder is `out/repeated-mesh-qa` in the main checkout. The clean reference is the staged package through 0123, which already contains the sky and post-effect optimizations. A single-player PoC mounted the subscribed Modern House map (item 3495468649) at 3840 × 2160 on the RTX 5090, with ToPBR, Enhanced No horizon, DLSS and frame generation active. Camera positions, settings and loaded DLLs were recorded.

The camera was stationary in the courtyard for both GPU captures. The comparisons below use 47 interior game-rendered frames for 0123 and 46 for 0124. The affected merged group had the same counts in every sampled frame. The GPU times are medians of the measured commands.

| Courtyard measurement | 0123 | 0124 |
| --- | ---: | ---: |
| Geometries in the affected merged build | 373 | 291 |
| Triangles in that build | 113,164 | 66,178 |
| Copies of the 573-triangle mesh in that build | 82 | 0 |
| Top-level instance count across the traced builds | 49 | 131 |
| Bottom-level build commands, ms per rendered frame | 0.4451 | 0.4011 |
| Top-level build commands, ms per rendered frame | 0.0810 | 0.0832 |

The runtime identified 82 placements of the 573-triangle mesh and issued 46,986 fewer triangles in the affected merged build each frame. The intermediate micromap-compatible prototype built one standalone copy in 46 of 46 sampled frames. The final runtime built it once in 46 frames. That frame contained nine bottom-level builds in total. The other 45 frames reused the built object. The trace verifies the submitted GPU work. The exact input responsible for the single rebuild is unmeasured.

## Unprofiled gameplay

Six launches ran in reference, combined, combined, reference, combined, reference order. The last pair replaced interrupted windows in the walking route. Each route produced two 12-second windows per launch. Within each adjacent launch pair, windows were matched in acquisition order by scene and focus. Interrupted windows were excluded. The background cap was zero and all matched windows had background focus. The hallway camera moved about 470 Source units per timed window. Raw windows, focus changes, and individual paired deltas are in `timing-summary.json`.

| Route | Matched 12-second windows per build | Median frame time, 0123 → 0124 | Rendered FPS, 0123 → 0124 | 99th percentile, 0123 → 0124 |
| --- | ---: | ---: | ---: | ---: |
| Stationary courtyard | 6 | 16.641 → 15.976 ms | 59.91 → 61.10 | 24.359 → 23.512 ms |
| Walking hallway | 3 | 14.025 → 14.529 ms | 70.75 → 68.82 | 19.203 → 20.046 ms |

Frame time and the 99th percentile are medians of the matched windows’ respective statistics. FPS is the total game-rendered frames divided by their total measured time. Four of the six courtyard windows and one of the three hallway windows were faster with 0124. The per-window median ranges overlapped on both routes. The courtyard showed a whole-frame gain on this machine. The walking sample was slower and came from two matched pairs of launches.

The isolated PoC mounted the user’s existing Modern House subscription. The field game supplied the original research trace. The final profile, prop lifecycle, 14 sky and post-effect cases, and six unprofiled game sessions all quit normally with zero Lua errors. The PoC and protected settings were restored. Evidence for the combined package is in `validation-summary.json`.

## Visual and lifecycle checks

The fixed courtyard pictures from 0123 and 0124 differed by 0.32 mean absolute RGB levels out of 255 after area downsampling to 384 × 216. The moving hallway was checked visually. The comparison images are saved as `modern-house-comparison.jpg` in the evidence folder.

On gm_flatgrass both packages drew 88 two-colour stock oil drums, hid all but three, restored the grid, rendered it with Force merge all meshes on and then off, and removed it. The native log showed the 252-triangle mesh sharing at 88 visible instances, releasing at three, and sharing again when the props returned and the override was restored. All six camera pairs show the expected positions and colours. The final pair shows the empty floor. Both sessions quit normally with zero Lua errors. The paired images are in `lifecycle-comparison.jpg`.

## Build and package

Applying all 120 patch files to fork base `c6b48ed1a40f3451546137766d759dc13815f3a6` reproduced tree `9da27886d27020460afe1cfb07880b77bc906242` from the Release build. The series through 0123 still reproduces `2b8c2c5b54e3ae48793a154c1e2a1df633f4bc4c`. The submodule and clone pins were checked separately.

The packaged DLL SHA-256 is `8ff297c5656e41fb2b6fbd250d189a67c792c1341f710d00ea986ea72850a2a7`. The combined GMA used the stock packager and a short staging path for the existing long texture names. Its Release `nlctl` validation and deep package-input verification passed. Comparing both 2,279-file manifests and hashing the DLL streams found a single changed payload, `native/payload/runtime/d3d9.dll`.

The five native tests covered repeated mesh work, instance descriptions, Enhanced sky, HUD-less frame generation and memory statistics. They passed, as did the Vulkan renderer-output shader regression from the previous round.

The prior round’s 14 in-game cases passed on this DLL, including all eight sharpening, blur and lens combinations as well as the covered, revealed, turning and Standard sky views. The fixed covered and revealed pictures differed from the 0123 reference by 0.19 and 0.20 mean absolute RGB levels out of 255 after downsampling.

## Release checks and handoff

`tools/test.ps1 -Config Release` passed with 35 native project tests and 2,338 Python tests, including 6 skips. The final build also passed the six fork regressions listed above. The logs are `project-release.log`, `supplement-native.log` and `supplement-gpu.log`. The Git LFS object for the compressed input was checked against its staged pointer.

The combined changes were validated on `codex/sky-postfx-frame-time` from `823fc55e`. The user approved the normal local publisher for Workshop item 3829070317. The evidence covers a desktop RTX 5090. Other GPUs, headset presentation and multiplayer remain unmeasured.

## Workshop publication

The normal local publisher updated Workshop item 3829070317 to `0.0.0-dev.20261128044434+589c2535` from GitHub commit `d68b753e`. Steam reports the update at 2026-11-28 04:45:21 UTC. The public change note includes all three renderer changes. [GitHub source](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/commit/d68b753efe8f2b0cacee8c424f6fda334743c8e8) · [Workshop change notes](https://steamcommunity.com/sharedfiles/filedetails/changelog/3829070317)

A clean release checkout rebuilt the combined package and its validator. The new archive matched the play-tested content digest `506032df664e7d48ca5e8bc7edf6004667d41de02882bb00c889aede6447da7a`. All 2,279 payload files in the uploaded archive were checked against their manifest hashes. Its SHA-256 is `85b5c8fd592f185c229aaade8c6ce60b24b5d342ba36175fc1ffffa41bfed042` and its size is 3,497,013,777 bytes.

The prepublication gate passed 35 native tests and ran 2,338 Python tests with 6 skips. All six renderer regressions and all four standard game checks passed. The PoC sessions verified the toolgun, spawn menu, Modern House window and spawned glass with the approved DLL loaded. The PoC and protected settings were restored. The release evidence and public receipt are under `out/ship-renderer-0124` in the main checkout.
