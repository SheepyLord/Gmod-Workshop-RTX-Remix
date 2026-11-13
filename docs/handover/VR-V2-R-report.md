# VR V2 R: runtime work

Follow-up status, 2026-11-11: the GPU-selected per-frame range is implemented and the selected
runtime is imported once. Module provenance is current, runtime/base.json has no pending patches,
and tools/test.ps1 -Config Release passes. The old absolute left-eye ghost value of 153 is not
reproduced in the merged context; the selected steady count is 163 versus 172 for the unchanged
fixed-runtime control. This limitation is explicit in the follow-up below. The original fixed-range
handover is retained as history; its old provenance blocker is superseded by the authorised refresh.

Status: runtime work and the requested PoC comparisons are complete on v2r and runtime vr2. The
Release gate retains the native-package provenance dependency described below. API version stays 3;
no structure changes. No package input, loader, field install or other task's tracked file was
changed. All runtime builds used -NoImport.

The complete Release gate currently has one integration dependency: the mandated shared-header
addition changes the native module's declared input fingerprint. tools/check_repo.py reports that
packages/vr/bin/gmcl_nlvr_win64.dll was built from other sources. The task forbids imports and
assigns neither tools/ci/pins.json nor the module implementation to R. The runtime has pending-patch
support; native provenance does not (tools/ci/repo_builds.py:117). I retained the truthful packaged
record. The full gate's 34 native tests and 934 Python tests pass, including header identity;
conventions alone fail. Q must refresh the packaged native build record when integrating/importing
N's module.

## What changed

After matching the headers, I completed the compositor-free path early to unblock task N's
simulations. The runtime can render a complete session without a compositor. NO_SUBMIT accepts a
null interface provider, skips SDK acquisition, pacing, timing queries, texture submission and
shutdown calls, and clears borrowed interfaces between generations. It still traces, warps, mirrors,
copies overlay pictures and captures. Copied overlays acknowledge an update without inventing a
submitted frame. The flag policy is at rtx_vr_policy.h:13 in the runtime fork; PoC receipts prove
the complete path.

The new rtxvr_SetOverlayWindow export is forwarded through the runtime and shim. SHOW copies the
actual window after its 2D, at present. The aspect-preserving copy is at most 1920 pixels wide. SHOW
+ NO_MIRROR clears opaque black before 2D, including frames without a traced world. Flags zero end
the source. Render-target and window sources are mutually exclusive. Unknown flags and an orphan
NO_MIRROR are rejected. A new source remains requested until the renderer is ready. Only the render
thread allocates/copies/retires its images, clearing the SDK texture binding and waiting for GPU
retirement before replacement. See rtx_vr.cpp:153, :248, :288 and :849, and d3d9_device.cpp:1574 in
runtime commit 36df1ef0. Stop remains the SDK barrier.

Thin reconstructed colour now receives a matching near-depth footprint at a discontinuity. A VR-only
R32F pass takes the minimum valid absolute depth over nine primary texels, but uses it only when
that minimum is below 90% of the centre depth. Smooth gradients keep their original depth. The CPU
reference and shader use the same rule (rtx_vr_math.h:116 and vr_depth_coverage.comp.slang:20). The
nearest-surface inverse-depth search remains unchanged. Captures include the raw and coverage depth
PNGs plus little-endian float32 depth files, in world units. The GPU profile splits depth_coverage
from eye_warp; the status warp sum includes both.

The final guaranteed near depth is 0.4 m, with a 0.05 m experiment step to avoid selecting a fine
boundary from GPU clock noise. The 0.2 m and 0.3 m candidates exceed 1.0 ms in the near-prop runs.
The 0.35 m candidate fits the static barrel/prop scenes but exceeds it with the moving thin scene.
The launch-only RTX_VR_TEST_NEAR_METRES diagnostic reproduces 0.2 to 0.5 m experiments; it is read
at Start, never from Lua or a saved option. [ADR
0162](../decisions/0162-vr-thin-colour-coverage-and-near-limit.md) and [ADR
0163](../decisions/0163-vr-window-panels-and-compositor-free-output.md) record these choices.

## Fixtures, machines and evidence

All PoC experiments use gm_construct on the RTX 5090, driver 617.42. The preset is scale 1, DLSS
Performance with Ray Reconstruction, and one to four bounces. Weather is clear at a fixed noon. The
scripted head turns to +/-20 degrees and leans 0.2 m; near-prop timelines hold the head and one hand
fixed. The Index is unworn at 90 Hz, with recommended 2468 x 2740 pixel eyes. SteamVR was already
running for these Index tests and was left running, unchanged. Simulated tests use no VR lock or
SDK; Index tests use both shared locks. Foreign labs were waited for, never ended.

Evidence names below are relative to the MAIN checkout's out/vr/v2r. Analysis, source snapshots,
custom package configurations, scripts and crops are in THIS worktree's out/vr/v2r. The unshipped
controlled scene fragment is retained in runtime/vr_v2_scene.lua with its usage document. Each
session keeps its sources.json, console and runtime logs, modules.json, GPU inventory, summary.json,
restoration.json and cleanup.json. Every completed run so far quit normally, restored settings and
verified a clean rollback, including the two evaluator-only failures described below. The field game
was not ended or modified. Early preparation saw it at 3840 x 2160 with 56% GPU utilization and 9762
MiB in use; those observations are not comparison timings. The reported Index window pair began at
7% GPU utilization, about 4154 MiB, with no field game running. The per-run GPU and process receipts
are authoritative if a later run has a different background load.

The simulation descriptor records 68.5366 mm IPD; the live Index now reports 70.0000 mm. The
recorded 0.5/0.4/0.35/0.3/0.2 m projections are respectively 3072/3112/3128/3160/3272 pixels wide,
all 2752 pixels high. Relative pixel increases are 0%/1.3%/1.8%/2.9%/6.5%. The live Index's
0.5/0.35/0.4 m centres are 3080/3136/3112 x 2752 pixels; these must not be confused with the
recorded sizes. The final live 0.4 m size is 1.0% more pixels than its live 0.5 m reference.

## Ghost lines and close props

The controlled fixture places fifteen 3 mm strands and a segmented 0.12 m radius ring at 1.5 m, in
front of a stock-cube wall at 8 m. The centre has a single ring while both eyes acquire extra
displaced dotted portions. Thus this reproduced artifact is made by the warp's colour/depth coverage
mismatch; it is not already present as a second outline in the centre reconstruction.

The neutral-frame metric counts local dark contrast above 8/255 outside a two-pixel allowance of the
projected centre foreground and background edges, in a 260 x 260 pixel ring crop. It uses each run's
projections and IPD. It is a reproducible artifact count for this scene and threshold, not a
universal ground-truth measure. In simulated matched captures it falls from 713/878 pixels to
165/187 pixels in the left/right eyes, a 77%/79% reduction; the centre reference is zero. On the
Index the 0.35 m experiment falls from 709/836 to 167/171 pixels, a 76%/80% reduction. The small
remaining breaks and background disocclusions are retained in the pictures.

The final 0.4 m Index run measures 153/183 extra left/right pixels, about 78% fewer than 709/836. It
accepts 2697 matched submitted pairs, with zero Submit errors or unmatched poses, 5431 compositor
presents, zero dropped frames and 2744 reprojected frames. Quiet depth preparation plus warp is 0.94
ms and total GPU command/SDK work is 11.72 ms. The recorded eyes use 42 search intervals; the live
70 mm IPD uses 43. See ghost-index-final/ring-crops.png and ring-motion-final.png.

Native-scale crops and metric JSON are ghost-before-metric, ghost-after-metric, ghost-index-before
and ghost-index-after035 under this worktree's out/vr/v2r. ring-motion-before.png and
ring-motion-after035.png include the turned and leaning captures. Full source centre, depth, eyes
and mirror pictures remain in each run's captures folder. The CPU reconstructed-colour regression
finds 26/24 displaced left/right samples with raw coarse depth and zero with coverage. Disabling
coverage in a private source copy fails that regression (no-coverage.log); the final built reference
passes. This negative control leaves the runtime clone and exported patches unchanged. Mirrored
discontinuities, one-depth-texel surfaces and layered nearest intersections still pass.

The V1 barrel silhouette is retained. Comparing accepted construct-final7 captures with the 0.35 m
Index candidate, row means are 283.8/284.2/280.7 pixels before and 284.2/284.3/282.3 pixels after,
in centre/left/right order. barrel-metric/barrel-crops.png and barrel-widths.json retain
native-scale pictures and every measured row. The extra near depth therefore does not reintroduce
V1's narrowed foreground strips.

The final 0.4 m barrel run confirms 284.2/284.0/281.8 pixels in centre/left/right order:
barrel-final-metric/barrel-crops.png and barrel-widths.json. It accepts 2696 matched pairs, with
zero Submit errors or unmatched poses, 5438 presents, zero dropped frames and 2732 reprojected
frames. Quiet combined warp is 0.90 ms and GPU command/SDK work is 11.62 ms.

The held-prop fixture follows the scripted left hand. Its nominal model bounds are 0.06 x 0.08 x
0.10 m at 40 world units per metre; the visible cube is slightly smaller than its model bounds. The
commanded front depths of 0.2/0.3/0.5 m measure about 0.201/0.301/0.501 m in raw primary depth. The
three centre/left/right silhouette widths are 366/365/363, 244/243/242 and 147/146/145 pixels. Each
prop is whole in both eyes. After converting the measured centre silhouette by each eye's pixels per
tangent, eye width errors stay within 1.3%. The independent nominal-bounds comparison is also
retained rather than treating padded model bounds as visible mesh vertices. See near-02-metric,
near-03-metric and near-05-metric for the crops, raw depths and coordinates. The 0.2/0.3 m pictures
use their experimental projection limits; they are not a guarantee of coverage below the final 0.4 m
limit. V7 still owns true stereo, hidden surfaces and eye-dependent lighting. Temporal artifacts
already in the centre also remain outside this warp correction.

The final 0.4 m Index prop run accepts 1359 matched pairs with zero Submit errors/unmatched poses.
Its centre/left/right widths are 185/184/184 pixels, with eye errors -0.41%/-0.27% relative to the
centre-derived projection. Raw primary depth gives 16.047 world units, about 0.401 m. The direct
mesh query finds +/-5.9063 model units in visible vertices versus +/-6.1563 units in model bounds,
confirming why nominal bounds alone overestimate the visible cube. See near-final-metric and the
v2r-mesh console record. Quiet combined warp is 0.93 ms and GPU work 11.80 ms on the RTX 5090.

## GPU measurements and session counters

The table uses profile sets in each driver's steady window, excluding profiles with at least 0.01 ms
of capture transfers. GPU work is the sum of pass command/SDK brackets; it excludes queue gaps and
WaitGetPoses. Warp is depth preparation plus eye warp. The complete profiles and the inclusion rules
are in analysis/runs.json and lab/analyse_runs.py. Short experiments include head motion; the 90 s
window pair measures the later small-motion segment. They are distinct runs.

| Run | Driver success | Rendered / submitted frames | Submit errors / unmatched poses | Frames/s | Warp, ms | GPU work, ms |
|---|---|---:|---:|---:|---:|---:|
| ghost-baseline-sim | True | 2522 / 0 | 0 / 0 | 84 | 0.61 | 11.02 |
| ghost-coverage-sim | True | 2603 / 0 | 0 / 0 | 87 | 0.70 | 11.19 |
| window-source-sim | True | 2619 / 0 | 0 / 0 | 88 | 0.65 | 10.99 |
| near-02-sim | True | 2405 / 0 | 0 / 0 | 80 | 1.47 | 12.52 |
| near-03-sim | True | 2525 / 0 | 0 / 0 | 84 | 1.03 | 11.69 |
| near-05-limit035-sim | True | 2586 / 0 | 0 / 0 | 86 | 0.79 | 11.32 |
| index-720-before | True | 3907 / 3907 | 0 / 0 | 45 | 0.94 | 11.61 |
| index-4k-before | True | 3063 / 3063 | 0 / 0 | 45 | 0.92 | 11.57 |
| ghost-baseline-index | True | 2692 / 2692 | 0 / 0 | 45 | 0.80 | 11.29 |
| ghost-selected-index | False | 2709 / 2709 | 0 / 0 | 45 | 1.05 | 11.64 |
| ghost-final-index | True | 2697 / 2697 | 0 / 0 | 45 | 0.94 | 11.71 |
| window-final-4k-index | True | 1346 / 1346 | 0 / 0 | 45 | 0.78 | 11.71 |
| near-final-04-index | True | 1359 / 1359 | 0 / 0 | 45 | 0.93 | 11.80 |
| final-barrel-index | True | 2696 / 2696 | 0 / 0 | 45 | 0.90 | 11.62 |

In the short simulated near-prop runs, 0.2 m costs 1.47 ms combined warp and 12.53 ms GPU work; 0.3
m costs 1.03 ms and 11.70 ms. The 0.35 m prop-at-0.5 m run costs 0.79 ms and 11.32 ms, while the
moving thin-feature Index scene costs 1.05 ms. Those scene differences are why the static 0.35 m
result did not settle the limit. The coverage pass itself is about 0.015 ms.

## The desktop window and overlay source

The 90 s candidate pair uses identical code, scene, timeline, preset, IPD and a 0.35 m diagnostic
limit. Only the window size changes. Both traced centres remain 3136 x 2752 pixels, with primary
depth 1568 x 1376 pixels; the 4K desktop does not cause a second 4K path-traced view.

| GPU pass, ms | 1280 x 720 window | 3840 x 2160 window |
|---|---:|---:|
| Scene preparation and acceleration structures | 0.351 | 0.351 |
| Path tracing and volumetrics | 7.021 | 6.828 |
| Demodulation | 0.059 | 0.042 |
| Separate denoising | below 0.001 | below 0.001 |
| Composition | 0.374 | 0.370 |
| Upscaling, including fused reconstruction | 2.434 | 2.622 |
| Post processing and tone mapping | 0.365 | 0.332 |
| Depth coverage | 0.014 | 0.015 |
| Eye warp | 0.922 | 0.907 |
| Mirror | 0.008 | 0.022 |
| Later raster | 0.013 | 0.037 |
| Sum of command/SDK brackets | 11.606 | 11.572 |
| Elapsed bracket, including queue gaps | 20.999 | 21.363 |
| Compositor application GPU estimate | 13.815 | 13.329 |

Steady submitted rates are 45 and 45 frames/s. Steady presents/dropped/reprojected are 2362/0/1191
and 2451/0/1270. Full-run counters remain in the table's source JSON; compositor counters include
startup and its scheduling and must not be equated to rendered-pair counts. Mirror and later raster
are the window-scaled work, about 0.04 ms more together at 4K. They are needed to display the
desktop and its UI. V1 already sizes the expensive 3D passes from the headset and bypasses the
ordinary game-target blit (rtx_context.cpp:626 and :861); there was no redundant 4K traced job to
remove. V2 bounds the new window-source copy to 1920 x 1080 pixels, a quarter of the 4K pixels and
7.9 MiB rather than 31.6 MiB for an RGBA8 copy. It does not resize the user's window or remove the
desktop mirror to save an insignificant blit.

At 90 Hz the command work is already above the 11.1 ms refresh budget; path tracing and
reconstruction dominate. The compositor reprojects instead of reporting Submit errors. The same
current published-runtime thin scene also runs near 45 frames/s, so these results must not be
compared directly with V1's earlier 85 frames/s run on a different date and scene. No SteamVR
setting was changed to force a rate. Frame generation remains off, as required by the VR preset; it
is not a source of additional correctly posed headset frames in this design.

The 1280 x 720 simulated menu proof has identical decoded RGB overlay and mirror pixels, mean
difference 0.0/255. The 4K proof compares the 1920 x 1080 overlay against the two-by-two sample mean
of the 3840 x 2160 window: mean error about 0.043/255, maximum 0.5/255, from RGBA8 rounding. It
shows the escape menu and console over black. The ordinary mirror also matches the prescribed linear
crop of the left eye in a region without desktop UI: mean error 0.245/255, maximum 0.585/255
(mirror-720-metric/mirror-picture.json). See window-mirror-proof.png and
window-4k-sim-metric/window-overlay-proof.png, plus window-picture.json. The final Index case uses
the engine's default queue mode (-1); the earlier simulated case uses mode 2, on the command line
for that session only.

The final default-queue Index menu run accepts 1346 matched pairs with zero Submit errors or
unmatched poses, 2743 compositor presents, zero dropped frames and 1393 reprojected frames. SteamVR
reports the visible window texture at 1920 x 1080 pixels with texture_error zero. Its mean
downsample error is 0.048/255, maximum 0.5/255. The wrist remains nonblank. Its values remain 87
health, 31 armour, 18 rounds and 256 reserve while the escape menu pauses the server; identical
wrist pixels in the two captures are therefore expected, not evidence of a failed number update.
window-final-metric contains the panel proof, comparison JSON and wrist-value receipts.

Two raw summaries intentionally remain failed: window-source-4k-sim treated the new panel as a wrist
and rejected its greater-than-one-megapixel size; ghost-selected-index then exposed my first private
workaround's assumption that a real OpenVR handle was 1. Their probes finish successfully, with
normal quits, no Lua errors, zero Submit errors/unmatched poses, restored settings and clean
rollback. I corrected the private adapter to identify the frozen 769 x 257 wrist by extent, and
validate the window independently. No tracked tool or N file changed. The failed receipts are
retained, not relabelled as successful runs. General overlay-role validation is an N/Q integration
item for the new page/driver.

## Flat controls

Five alternating pairs use the published e43aef99 runtime and the final runtime, at 1280 x 720
pixels, with the same fixed map, pose, sky, settings and other package bytes. The baseline GMA uses
the current canonical package inputs and the same frozen N module; only its runtime and version
differ from the candidate. Thus this isolates the runtime rather than comparing different
generations of the whole package. Frame medians cover 30 s of flat-control Think intervals.

| Pair | Runtime | Median frame interval, ms | Start to map, s | Driver success |
|---|---|---:|---:|---|
| 1 | published | 8.382 | 28.0 | True |
| 1 | final | 8.030 | 24.4 | True |
| 2 | published | 8.521 | 27.8 | True |
| 2 | final | 7.976 | 25.2 | True |
| 3 | published | 7.965 | 24.4 | True |
| 3 | final | 8.368 | 23.2 | True |
| 4 | published | 8.057 | 26.2 | True |
| 4 | final | 8.684 | 25.1 | True |
| 5 | published | 8.153 | 25.6 | True |
| 5 | final | 8.170 | 26.8 | True |

The mean of the five per-run medians is 8.215 ms published and 8.246 ms final, a +0.37% difference.
Sample standard deviations are 0.231 ms and 0.288 ms. Mean start-to-map times are 26.4 s and 24.9 s,
with sample standard deviations 1.5 s and 1.3 s. This small sample does not establish mathematical
zero cost or attribute run-to-run variation to a particular component.

| Pair | Full-window RGB mean difference, /255 | World crop RGB mean difference, /255 |
|---|---:|---:|
| 1 | 0.708 | 0.684 |
| 2 | 0.712 | 0.649 |
| 3 | 0.546 | 0.531 |
| 4 | 0.640 | 0.543 |
| 5 | 0.582 | 0.601 |

These use flat-before captures, while the fixed camera is active. flat-after is requested beside
cleanup and can show the restored camera; it is excluded from the picture comparison. The images are
1280 x 720 pixels. The world crop is x=20 to 740, y=50 to 620 pixels, excluding the weapon and HUD.
Repeated images of the same runtime differ by 0.544 to 0.715/255 over the full window.
flat-pairs.png keeps all five native-scale image pairs.

Module-name union differences, published-only: apphelp.dll; final-only: none. Every flat run has no
OpenVR or nlvr module. Full per-run module lists remain in poc/game/modules.json; analysis/runs.json
has normalized names and the intersections/unions. The runs use fps_max 0, mat_vsync 0,
mat_queue_mode 2, gmod_mcore_test 1, fixed clear weather at noon, and the same live flat
upscaler/frame-generation selectors (1/1). The VR preset is never applied in these controls.

With VR off, V2 adds a dormant window-source set/flag and empty coverage-image handle to the
device's existing VR state, two CPU shader binding descriptors and embedded coverage shader
bytecode, a new export and optional shim forwarder, and an atomic predicate at BeginScene. The
optional remix_with_shim build resolves one additional GetProcAddress when that shim binds
(d3d9_rtx_shim.cpp:201); the tested regular DLL does not use that build path. The shader is not
registered for prewarming (rtx_vr.cpp:39 and rtx_shader_manager.h:38). No OpenVR load/init, SDK
thread, VR GPU image/query allocation, VR preset, window clear/copy or VR pipeline compilation runs
before Start. No additional Vulkan name or feature is requested relative to published V1; the
existing six-name prerequisites remain as ADR 0157 describes. This is a precise list of work, not a
claim that dormant CPU metadata has mathematically zero cost.

## Builds, commits and tests

The final experimental d3d9.dll is out/vr/v2r/final/d3d9.dll in this worktree, 418372608 bytes,
SHA-256 541d3caf77857b348be7d04661a5e1457cdb15872440cd414fc97b407305dfe0. The local GMA is
out/dist/gmod-rtx-remix-0.0.0-v2r.final.gma, 2085400958 bytes, SHA-256
a56bd2ee9c57b5507ced8f3d2b8f4c5396672542ef991515240935d04148c6e8. It is a laboratory package, never
imported or published. package-final.log and the JSON beside the GMA record the nlctl validation.
N's frozen test module is 499200 bytes, SHA-256
b55dea158018c11514642723a407df4b14616493a6f5977aad265ffc5a620b64. lab/sources.json hashes its
driver/probe/descriptor snapshots. Both API headers have SHA-256
e4dd4aacda329dfa1495c8c5ec8515e91fc57f5f7ab3ab5cc2f247910070daa0.

| Runtime commit | Exported patch | Change |
|---|---|---|
| 802826c0 | 0072 | API 3 window declaration and flags |
| 07fceaed | 0073 | Complete compositor-free copies and SDK guards |
| d8df7e54 | 0074 | Post-2D window source and mirror suppression |
| 2cf44de5 | 0075 | Thin colour depth coverage and separate timing/captures |
| 891200bd | 0076 | Reproducible near-limit candidates |
| 6dfc8e5e | 0077 | Thin-colour CPU regression and first measured limit |
| 36df1ef0 | 0078 | Moving-scene limit selection |

Each patch was exported from one commit, one at a time. runtime/base.json truthfully records them as
pending; Q imports the combined runtime once at integration. Replaying patches 0072 to 0078 against
d29445c5 in a temporary index produces exactly the final source tree
4c147a56e1387adc54b17e794e6f49c0596110c7 (replay.log). Both branches use the configured SheepyLord
identity and the Codex trailer. No push, merge, publish or workflow was run. Existing fork
dependency overrides were retained; they were not staged as task changes.

The built runtime CPU suite passes 274 assertions: math-built-final.log. Header identity passes:
header-identity.log. The final tools/test.ps1 -Config Release run exits 1: gate-final.log and
gate-final-exit.json. All 34 native tests and all 934 Python tests pass. The only failed step is
repo conventions, for the packaged native module's stale source fingerprint described at the top.
Thus the requested completely passing gate is not achieved within R's allowed paths. An earlier
isolated loading-window visibility failure passed on both full reruns without a source change.
final-invariants.json verifies all ten flat runs' settings, selectors, module exclusions and clean
restoration. Their pre-launch GPU utilization is 7%, with 4172 to 4219 MiB in use. audit.json checks
the allowed changed paths, ASCII additions, identical headers, commit identity and trailer.

Reproduction uses this worktree's private lab snapshot because N's driver changes are not merged
into v2r. lab/run.py accepts the usual --package, --evidence, --simulate, --window, --seconds,
--queue-mode and --timeline arguments. V2R_CASE selects barrel, ghost, near or window; V2R_NEAR sets
the held-prop fixture's commanded front depth. Run unattended analysis with Python 3.12 and
Pillow/NumPy as recorded in the source receipts. The production manual-look path is unchanged and
does not acquire these image-analysis dependencies. lab/remaining_suite.py and flat_batch.py retain
the exact commands; they take locks through the copied driver rather than bypassing it.

## Open work and text for integration

Q must integrate N's native changes, refresh their packaged source provenance, import the final
runtime, and run the combined acceptance. All requested R PoC controls are complete. The full gate
cannot pass until Q updates the native package provenance; importing it or editing its pins is
outside R's assigned paths. No person judged comfort or the visual limits of the unworn Index in
this task. Other GPU vendors have not been measured here.

For CHANGELOG/ROADMAP: VR V2 reduces displaced thin-feature outlines, extends guaranteed near
coverage from 0.5 m to the measured 0.4 m limit, adds bounded post-2D window panels and
compositor-free render/capture tests. A large desktop window does not create a second path-traced
view. For RESEARCH/TESTING: retain the scene-specific counts, 70 mm live versus 68.5366 mm recorded
IPD, separate coverage/warp timing, GPU command work versus queue gaps, both queue modes,
overlay-role validation and the five flat pairs. True stereo and performance adaptation remain later
milestones.

## Follow-up, 2026-11-11

The director accepted the ghost correction, compositor-free path, window source and measurements,
then changed the near-range requirement for hands and guns. vr2 was merged into v2r first, at
3799571. The merge retains F/N/H/L and the later task briefs; the only conflict was the additive
decision index. Production tools/vr_session.py now owns every new run. runtime/vr_v2_scene.py is a
fixture adapter around that current driver, with no private driver snapshot. H's unchanged
companion/tests/vr_hands_poc.py supplies the full-hands proof.

The centre stays fixed at 0.4 m. Runtime commit 37202ea9, patch 0079, adds a GPU minimum reduction
and a 0.15 m to 0.4 m search range chosen independently each frame. Preparation shares the existing
coverage pass and uses a small tile image plus one float. The warp consumes that float on the GPU;
there is no CPU readback or pacing wait. Normal search spacing remains at most one primary texel
even when more than 128 intervals are required. Out-of-frame coordinates cannot invent border hits.
Capture-only frame_minimum_depth.f32 records the actual frame minimum in world units.

The experimental CPU reference passes 314 assertions, and the merged module's four native test
groups pass. The optional fake window export needed its linkage aligned with the now-present header
declaration; a linker export directive keeps both fake-runtime variants and their tests. No module
or runtime input has yet been imported in this follow-up. Measurements (a) to (d), the authorised
provenance refresh, the single runtime import and the final gate are in progress.

The first global sweep, sweep-global-sim, accepts 7107 matched rendered frames with zero SDK
submissions/errors/unmatched poses and clean restoration. Captured frame minima are
0.151/0.201/0.301/0.401/0.601 m for the commanded 0.15/0.2/0.3/0.4/0.6 m cases. Quiet combined
preparation/warp costs are 2.222/1.713/1.181/0.854/0.889 ms, with GPU command work
12.997/12.429/11.656/11.301/11.297 ms. The first four prop silhouettes are whole in both eyes, with
width errors below 1.3%. The closest right-eye measurement initially selected a stronger background
edge; the retained guided analysis searches around the independent model projection's bounds and
correctly identifies its silhouette. The raw images and both analyses remain.

Because one close surface made every ray pay the long search, commit 4f764396, patch 0080, adds
conservative per-ray tile minima. A far frame takes the original path without scanning tiles. Close
frames scan the tile rectangle of each ray's possible inverse-depth segment, including colour
coverage at tile borders. This is a GPU-only bound and leaves the projection unchanged. The
323-assertion reference verifies that the bounded search produces the same result as the global
search. hands-global-sim also passes H's unchanged acceptance, with 5349 matched rendered frames and
no SDK submission or unmatched pose. Performance and physical Index proof of the tile-limited build
follow before any import.

Commit 4eb9228b, patch 0081, also makes the CPU raw-depth reference use the shader's signed-depth
normalisation, with a regression for negative view Z. The final reference has 324 assertions. Its
-NoImport DLL is 418384384 bytes, SHA-256
ddf480d657b11f754a1bc7dc79d62346d160ebbc4715e74ece80d4fe19d978f4; the GPU algorithm is unchanged
from the tile-limited prototype. No runtime package import has occurred yet.

The first tile-limited ghost simulation completed both VR cycles and reported successful probe
cleanup, then exited with c0000005 before the next window operation. Windows Event 1000 identifies
owned PID 50472, faulting module unknown and offset zero; no minidump was collected. It is not
classified as the known nvoglv64.dll startup fault. The PoC restored cleanly. The fixture had newly
begun deleting its static client models at finish; that eager deletion is removed so the owned
process retains their lifetime through queued draws and normal quit, as the original scene fixture
did. A fresh run must pass before acceptance. The failed receipt and crash-events.xml remain,
including its 158/189 simulated ghost counts; those are not an accepted physical result.

The final tile-limited simulation, sweep-final-sim, passes with 7422 matched rendered frames, zero
SDK submissions/errors/unmatched poses, restored settings and clean rollback. Centre output remains
3112 x 2752 pixels throughout. The controlled prop's guided luminance edges are:

| Commanded front depth, m | Centre width, pixels | Left width, pixels | Right width, pixels | Maximum eye width error |
|---|---:|---:|---:|---:|
| 0.15 | 485 | 483 | 482 | 0.24% |
| 0.2 | 366 | 365 | 365 | 0.11% |
| 0.3 | 245 | 244 | 243 | 0.44% |
| 0.4 | 185 | 184 | 184 | 0.30% |

All four props are whole in both eyes. Pixel crops and exact edge coordinates are in this worktree's
out/vr/v2r/followup/props-final-sim. These are the Index descriptor's recommended 2468 x 2740 pixel
eyes on the RTX 5090; physical Index measurements follow separately.

| Commanded front depth, m | Combined preparation/warp, ms | GPU command work, ms |
|---|---:|---:|
| 0.15 | 1.108 | 11.712 |
| 0.2 | 1.052 | 11.329 |
| 0.3 | 0.995 | 11.163 |
| 0.4 | 0.947 | 10.944 |
| 0.6 far control | 0.892 | 10.989 |

The far control is within 0.05 ms of the original 0.94 ms reference. The closest simulated case now
stays below the derived 12.5 ms GPU command budget at 80 Hz, whereas the global prototype exceeded
it. These command sums do not include compositor work, queue gaps or a measured 80 Hz run. The query
profile's maximum-step field is a CPU upper bound at 0.15 m, not a readback of the ray-local ranges.
Captured minimum depths and per-interval inclusion rules are retained in
sweep-final-sim-analysis.json and analyse_sweep.py. No rendering path waits for these captures.

The physical sweep, sweep-final-index, passes with 3833 matched submitted pairs, zero Submit
errors/unmatched poses/dropped frames, 7754 compositor presents and 3847 reprojected frames. It uses
the unworn Index at 90 Hz and 2468 x 2740 pixels per eye, with the same fixed 3112 x 2752 centre.
The per-distance results are:

| Front depth, m | Preparation plus warp, ms | GPU command work, ms | Centre / left / right widths, pixels | Maximum eye error |
|---|---:|---:|---|---:|
| 0.15 | 1.249 | 12.359 | 485 / 484 / 482 | 0.35% |
| 0.2 | 1.045 | 11.674 | 366 / 365 / 363 | 0.55% |
| 0.3 | 1.108 | 11.690 | 245 / 245 / 242 | 0.96% |
| 0.4 | 0.909 | 11.621 | 184 / 184 / 182 | 0.82% |

All required props are whole in both eyes. The final measurement locates the actual red face by
colour, then finds its outer luminance edges in a small band. It does not use the predicted width as
the measured width. This avoids the stronger building edge that confused the earlier broad gradient
search. props-final-index-located retains the crops and coordinates; the earlier analyses remain for
diagnosis. Simulation uses the same locator, with all required errors below 0.5%. GPU timings come
from independent per-timeline profile windows excluding capture transfers.

This machine remains at about 45 submitted pairs/s at 90 Hz. The closest command-work result is
under both the 22.2 ms half-rate interval and the derived 12.5 ms budget at 80 Hz, but with only
0.14 ms margin against the latter. It is not a measured 80 Hz throughput claim. The short far
interval measured 1.048 ms combined warp, so the dedicated normal-scene Index run remains needed for
(a), rather than assuming that interval meets the 0.05 ms requirement.

H's final physical run on this candidate passes with 3640 matched submitted pairs, zero Submit
errors/unmatched poses/dropped frames, 7714 presents and 4092 reprojected frames. All H acceptance
checks pass. The 0.2/0.3/0.5 m fingers and palms remain whole in both eyes; native-scale comparisons
beside H's V1 captures are hands-final-index-comparison.png. Fine surface/disocclusion patterns
remain. The matching simulation accepts 5601 rendered frames and also passes H's acceptance.

The barrel candidate accepts 2685 matched pairs with zero errors or dropped frames and retains
284.2/284.7/281.8 centre/left/right pixels, compared with ADR 0156's 283.8/284.2/280.7 pixels. Its
combined preparation/warp mean is 1.004 ms. The dedicated 90 s ghost run accepts 4058 matched pairs
with zero errors/dropped frames and clean restoration, but measures 1.009 ms and 170/192 ghost
pixels. Those miss (a) and (d); they are not treated as acceptance merely because the lifecycle
checks pass. No runtime import has occurred.

Commit 9c36516a, patch 0082, addresses the misses. The GPU reduction writes two indirect dispatch
commands, enabling exactly one kernel: a lightweight fixed-range warp for a far frame or the
adaptive tile-limited warp for a close frame. The CPU neither selects the kernel nor reads the depth
minimum. The coverage pass shares a 12 x 8 raw-depth block for 8 x 4 outputs, allowing a 5 x 5
reconstructed-colour footprint without 25 separate texture fetches per output. A one-wave fast
reduction has a subgroup-safe shared fallback for smaller wave sizes. The CPU reference matches the
footprint/tile dimensions and dispatch selection; all 326 assertions pass. This revision is being
tested with -NoImport before choosing the single V2 runtime import.

The wider-footprint trial is rejected. ghost-fast-sim restores cleanly and accepts 5017 rendered
frames, but measures 0.990 ms combined preparation/warp and 223/234 ghost pixels. The larger minimum
footprint moves too much background at foreground disparity. Its preparation alone costs 0.079 ms;
sweep-fast-sim also measures 1.006 ms for the far control. These are retained failed numeric
experiments, not acceptance evidence.

Commit b5de0a9a, patch 0083, restores the accepted 3 x 3 coverage and the original fixed-range
shader, including its original 80-byte push-constant layout. The fixed source body is identical to
36df1ef0 after only header/type renaming, as fixed-shader-identity.json verifies. The GPU still
chooses fixed versus adaptive work through indirect dispatch; the validated close-frame path keeps
the conservative tile search. This version is being tested before import. Its -NoImport DLL is
418403840 bytes, SHA-256 557d752e43ef19d5edfddedc259f79d433ed2d6ff0154ea40103c4872e182550.

The retained-kernel run meets (a): ghost-retained-index accepts 3638 matched submitted pairs, with
zero errors/dropped frames and clean restoration, at 0.974 ms combined preparation/warp (+0.034 ms
from the 0.94 ms reference). Its 167/194 ghost pixels still miss (d), so it is not imported. The
shader body identity does not substitute for that numerical check. The corresponding simulation
accepts 4642 rendered frames and measures 0.853 ms with 144/188 simulated ghost pixels. The retained
prop sweep accepts 6643 rendered frames with all required silhouette errors below 0.5%, but these do
not close the remaining physical ghost condition.

Commit c5dcba3e, patch 0084, retains the 3 x 3 footprint and adds colour guidance only when depth
would otherwise expand into a background texel. It compares the reconstructed 2 x 2 colour footprint
with the nearest-depth neighbour and known-background neighbours. The most distinctive near colour
is retained when any reconstructed pixel is foreground-like or ambiguous; clearly background-like
colour keeps its actual centre depth. This targets background moved at foreground disparity rather
than enlarging the entire minimum footprint. The CPU helper matches the shader, with regressions for
dark and bright thin foreground, background rejection and a smooth-depth path which performs no
colour reads. All 330 assertions pass. This remains a -NoImport experiment.

The colour-guided trial is rejected: its simulation restores cleanly but measures 494/639 ghost
pixels. CPU replay of the same saved inputs predicts the same foreground erosion. Larger colour
tolerances and reduced stencils were evaluated offline; none improved on the accepted footprint.
These do not ship. Commit 39e2ab77, patch 0085, removes guidance and restores the selected source
tree exactly to b5de0a9a (identical tree hash), with 326 passing assertions.

The selected -NoImport rebuild is 418403840 bytes, SHA-256
027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278, retained in
out/vr/v2r/followup/selected/d3d9.dll. A fresh fixed-runtime control uses the accepted 541d3caf DLL
with the same merged module/add-on. Both control and selected runs retain the early neutral capture
and add a declared timeline-8-second steady neutral capture before head motion. Results are kept
separately; no early failed image or crash receipt is relabelled.

ghost-steady-index passes with 4036 matched pairs, zero Submit errors/unmatched poses/dropped
frames, 8163 presents and 4108 reprojected frames. Combined preparation/warp is 0.869 ms and GPU
command work is 12.328 ms in its quiet window. Early neutral counts are 168/187; the declared steady
neutral gives 163/178. The right-eye guard passes at steady state; the left still exceeds 153 by ten
pixels. The fresh unchanged fixed-runtime control remains pending, rather than assuming those pixels
are a code regression or silently accepting them.


### Final selected result and imports

The selected tree is 39e2ab77 in the fork, exported through patch 0085. The base for this follow-up
is the authorised merge 3799571 on v2r. No change was merged into main or vr2 in this repository,
and no push, publication or workflow was run. API version remains 3.

(a) The selected normal-scene Index run measures 0.869 ms combined preparation/warp. The fresh
fixed-runtime control measures 0.853 ms, so the matched overhead is 0.016 ms, within the 0.05 ms
allowance. Both are faster than the earlier 0.94 ms observation. They start at 13% GPU utilization,
4378/4380 MiB in use, on the RTX 5090 with driver 617.42. The earlier physical prop/hand runs start
at 7% GPU utilization and 4247/4239 MiB. No field game was running. SteamVR was already running and
was left running, unchanged.

(b) At the recommended 2468 x 2740 pixel eyes and fixed 3112 x 2752 centre, the physical
0.15/0.2/0.3/0.4 m results are 1.249/1.045/1.108/0.909 ms combined preparation/warp and
12.359/11.674/11.690/11.621 ms GPU command work. Eye-width errors are at most
0.35%/0.55%/0.96%/0.82%; all required props are whole. The selected dispatch combination's
simulation also passes, with 485/483/484, 366/365/365, 245/244/243 and 185/184/184 centre/left/right
pixel widths. Its close shader and 3 x 3 coverage source are byte-identical to the physically
validated version, as final-audit.json checks. The closest physical command sum fits the derived
12.5 ms budget with only 0.14 ms margin; 80 Hz throughput is not measured. At 90 Hz the observed
rate remains about 45 pairs/s, with the 22.2 ms half-rate interval available.

(c) H's original near-020/030/050 cases pass in simulation and on the Index. The physical run
accepts 3640 matched pairs with zero errors/unmatched poses/dropped frames; the simulation accepts
5601 rendered frames with no SDK submissions. Fingers and palms remain connected and whole in both
eyes. hands-final-index-comparison.png and hands-final-sim-comparison.png retain native pixel crops
beside H's V1-runtime images. Fine depth/colour seams and hidden-surface limits remain; these are
not a comfort judgment or true-stereo proof.

(d) Barrel widths remain 284.2/284.7/281.8 pixels versus ADR 0156's 283.8/284.2/280.7 pixels. The
old absolute ghost guard is not fully reproduced: the selected early/steady counts are 168/187 and
163/178, while the unchanged accepted runtime now gives 170/188 and 172/195 with the same merged
module/add-on, scene, metric and pose. The selected result is better than that matched control, and
the far shader body is retained exactly, but 163 still exceeds the old left-eye value 153 by ten
pixels. I retain this as an explicit absolute-threshold limitation, not a claimed literal pass or a
reason to ship the foreground-eroding trials. All source images, both early and predeclared steady
captures, replay results and control receipts remain under out.

The module refresh was executed as authorised:

    python tools/ci/repo_builds.py refresh vr/bin/gmcl_nlvr_win64.dll

It verifies that the merged-source build is the same executable image as N's packaged module. It
updates tools/ci/pins.json and keeps the existing binary; no extra source-list entry is needed. The
packaged gmcl_nlvr_win64.dll is 499712 bytes, SHA-256
980ba98f80e371ff04c2f63af121f0e28d5462e0f1905f1baf5e7d10d5d7d8eb. The local build's raw SHA-256
450192f2524a6bb7a8fe5e07eacde9630b85c45637799f0f4ef8b9fd16ce4b11 differs in linker/debug metadata;
the refresh tool performs the executable-image comparison rather than pretending those bytes match.

The one V2 runtime import was executed by runtime/build_runtime.ps1 without -NoImport after the
experiments. import-runtime.log records exactly one stored file. The packaged d3d9.dll is 418403840
bytes, SHA-256 027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278. runtime/base.json
records all patches and dependency settings, with no pending_patches member. Q does not need another
runtime import unless the runtime changes later.

The canonical package is this worktree's out/dist/gmod-rtx-remix-0.0.0-v2r.adaptive-final.gma,
2085528178 bytes, SHA-256 f022a56434c05922a65189efdc998b18708ff4840302f392c0d26d83cc5fbf67. It was
rebuilt from packages/ with the normal build configuration, no test DLL override, and passes nlctl
validation. package-smoke-sim then passes through the unmodified production driver: 2206 matched
rendered frames, zero SDK submissions/errors/unmatched poses, normal quit, restored settings, SDK
unloaded and clean PoC restoration. The package is local and unpublished.

tools/test.ps1 -Config Release passes in v2r: all 34 native tests and 964 Python tests, including
conventions. The selected runtime reference separately passes 326 assertions. Evidence is this
worktree's out/vr/v2r/followup/gate-imported.log, math-retained.log, native-tests.log,
refresh-module.log, import-runtime.log, package-imported.log, final-audit.json and the per-run
main-checkout evidence folders. Rejected experiments and the unclassified post-probe crash are
preserved above. The only remaining review issue specific to these numeric requirements is the old
absolute left-eye ghost threshold; the matched-control result shows no worsening.
