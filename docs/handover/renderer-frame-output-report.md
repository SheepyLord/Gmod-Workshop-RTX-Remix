# Lower-sky visibility and post-effect color

Codex, 2026-11-27. Branch `codex/sky-postfx-frame-time`, from `823fc55e`. The user requested findings 2 and 3 from the Modern House runtime study. This report records the prepublication package through 0123.

## Changes

- Runtime patch 0121 restores the memory-statistics unit source already named in Meson. The prior build machine had it in an ignored file. A clean fork worktree stopped during configuration without it.
- Runtime patch 0122 classifies current camera misses and skips covered workgroups of the lower screen cloud renderer. A one-tile margin protects filtering and the shifted sampling schedules. [ADR 0274](../decisions/0274-skip-covered-lower-cloud-tiles.md)
- Runtime patch 0123 passes color images between sharpening, motion blur and lens effects and resolves the current color in the existing sRGB pass. [ADR 0275](../decisions/0275-pass-color-between-post-effects.md)
- The [PoC probe](../../tools/qa/renderer_frame_probe.lua) includes a [run command](../../tools/qa/renderer_frame_probe.lua.md). The package source remains the fork pin, its recorded dependencies and the ordered patches.

## Build and package

The runtime was built with the x64 Release Meson configuration. Applying all 119 patch files through 0123 to the recorded fork base produced Git tree `2b8c2c5b54e3ae48793a154c1e2a1df633f4bc4c`, identical to the expanded source used for the build. The submodule and clone pins were checked separately. The DLL SHA-256 is `3be40a41a21320f81490ab12e68e8451a67ccf30a72d118657331b86940a9102`.

The candidate and published GMAs each list 2,279 files. Comparing both manifests and hashing the DLL streams inside the archives found one changed payload, `native/payload/runtime/d3d9.dll`. The branch's Release `nlctl` validated the package. The short staging path under `out` was needed for long HL2 texture names on Windows. The separate checked-out runtime source was staged to verify its tree without creating a fork commit.

Embedding the 13 masked variants added 9.04 MiB to the DLL and 1.13 MiB to its compressed package input. The tile image at the tested 1920 × 1080 internal resolution contains 8,160 bytes of texels before Vulkan allocation alignment. The post effects reuse the two existing full-resolution color images.

## GPU and game checks

Evidence is in the main checkout's ignored `out/renderer-opt-qa`. `validation-summary.json` contains the trace, screenshot and unprofiled comparisons. `source-verification.json` records the source tree and pinned dependencies.

- The compiler reflected all 13 host-masked variants. Each has the original workgroup size, push constants and descriptors plus the tile map. The optional `renderer_outputs_gpu` regression runs the production visibility classifier at odd sizes, verifies hidden colour, depth and history over five sampling schedules and four shifts, and compares in-place and separate-input sRGB output bit for bit in four conversion, dither and inversion modes.
- The four passing fork regressions were `test_memory_stats_data`, `test_dlfg_hudless`, `renderer_outputs_gpu` and `test_enhanced_sky`. The last ran against the same Release DLL used in the PoC. Deep verification of the runtime package input passed.
- The published and candidate packages ran in the snapshotted PoC on gm_flatgrass at 3840 × 2160 with DLSS and frame generation active. The corrected capture sequence used the same floor coordinate, suppressed first-start dialogs, and waited for Enhanced sky before recording. An earlier run captured Standard during startup and was excluded from the Enhanced-sky timings.
- In 46 interior rendered frames per trace, the lower cloud march on opaque ground took **0.2514 ms** median in the published runtime. In the candidate it took **0.0347 ms**, or **0.0373 ms with the visibility commands included**. The main cloud renderer remained active. Sharpening, motion blur, lens effects and sRGB ran in every sampled frame. The three RGBA16F copy-backs took **0.1143 ms** in the baseline and were absent from the candidate trace.
- Both packages completed all 14 camera/effect cases with zero Lua errors and a normal quit. The baseline and candidate pictures include exposed lower clouds, a partly covered horizon, the turn, Enhanced with No horizon off, Standard and all eight sharpening/blur/lens combinations. The covered view differed by 0.15 mean absolute RGB levels out of 255 after area downsampling. The revealed clouds differed by 0.86. The cloud simulation is temporal, so the game captures are a visual regression check.
- Without the profiler, four separate launches in baseline–candidate–candidate–baseline order provided four ten-second windows per scene and build. On the covered view the median of the window medians changed from **10.36 to 10.06 ms** and weighted rendered FPS from **96.1 to 99.2**. At the map edge it changed from **10.53 to 10.06 ms** and from **96.3 to 98.6 FPS**. All windows had the same background focus state. Their ranges overlapped.
- The PoC, video settings and protected configuration hashes were restored. Hardware coverage was a desktop RTX 5090. Radeon, headset presentation, FSR/XeSS and optional DLSS neural rendering remain separate hardware or feature checks.

## Release checks

`tools/test.ps1 -Config Release` passed with 35 native tests and 2,338 Python tests, including 6 skips. The complete log is `release-host-complete.log` in the evidence folder.

Earlier parallel runs hit the catalog's game-process checks. The catalog passed three consecutive isolated runs and the final six-job preset with fresh CTest scheduling history. Windows also denied temporary folder renames in four packager fixture cases across two runs. Each case passed on an isolated retry. The final run used the host Python 3.14 with NumPy, Pillow and xxhash in the ignored QA folder. The three Python groups also passed on Python 3.12 with four skips in total. The loader and packager sources and tests match the base revision.

## Review

The staged project worktree is `out/worktrees/render-opt`. The source pin, complete patch series and LFS payload are in the staged diff. No commit or publication was made.

The follow-up for finding 1 combines this work with repeated-mesh routing in runtime patch 0124 on the same branch. [Combined runtime and test evidence](repeated-mesh-frame-report.md)
