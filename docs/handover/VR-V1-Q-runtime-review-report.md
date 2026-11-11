# VR V1 Q: the second independent runtime review

The ten findings are corrected on `vr-q`, with runtime patches exported one commit at a time from
the clone's `vr` branch. The review was read first from the main checkout's
`out/vr/review/independent-2.md`; it reviewed runtime `9d22eef6` and module/Lua `dddbfe3`.
The accepted shared documents were at `038bf04`. Nothing was pushed, merged or published, no
GitHub workflow was started, and neither the loader nor the standing AGENTS rules were changed.
Claude's `VR-V1-report.md` is untouched. The field install was not changed.

The selected runtime is `d29445c5`, patches 0065 through 0071. Its final Index run reached 85
frames/s on gm_construct and 30 frames/s on modern_house at 90 Hz, with zero failed Submit calls
or unmatched poses. The new warp averaged 0.56/0.64 ms respectively. The corrected first-camera
test withheld 505 deliberately mismatched startup cameras before accepting matched output.

## Findings, using the review's numbering

1. The warp searches near to far in inverse depth, from the covered 0.5 m axial depth to infinity.
   It refines both surfaces bordering an interval and accepts the nearest settled intersection
   within the depth already searched. A refinement that jumps ahead is deferred. Unresolved
   disocclusions keep observed background. CPU and shader use the same formula; the reference
   tests mirrored discontinuities, thin objects, alternating depth layers and a single-depth-texel
   foreground object at the actual Index projections. The final crops and costs are below.
2. The native event worker only marks IPD dirty (`vr/native/session.cpp:281`); BeginFrame reads and
   applies the eyes under its existing lock (`:402`). Native assertions prove no worker-side eye
   read occurs before BeginFrame. A busy camera push holds the last accepted camera. Lua tests
   cover recovery, forty repeated queries in one engine frame and thirty consecutive failing frames.
3. The wrist repaints until the runtime acknowledges its first copy, then latches success. An
   unchanged acknowledged HUD makes no further native Info call. Both Info results are read and
   persistent errors are bounded. Lua tests cover the missed initial copy. Real default/automatic
   resolved to queue mode 2; a separate fixture proved actual mode 0 with gmod_mcore_test 0. Both
   neutral wrist PNGs are byte-identical, contain the correct text and have 8223 bright glyph pixels.
   Capture acceptance now rejects a blank wrist even when every expected file exists.
4. DoNotHaveFocus counts a skipped interval and keeps the session. RequestFailed has a five-second
   continuous recovery window; incompatible errors fail immediately. Initialization waits for
   focus before images/preset creation. CPU policy tests and three injected focus returns on the
   real render thread prove recovery. The safe native quit then completed while paused: wall time
   advanced 9.436 s while CurTime advanced 0.0134 s. SteamVR itself stayed running.
5. Projection eligibility needs the current frame and generation, and the first eye output also
   needs an actual camera match. A physical look exposed a queued flat camera under the already
   correct 1.90874 radian projection, so checking FOV alone was insufficient. The new CPU case uses
   an offset VR camera. A five-second metadata mismatch on the Index produced 505 initial skips,
   then 2014 matched pairs with zero Submit errors or unmatched poses. The physical look and final
   package look also passed. Later unknown cameras retain the plan's counted fallback; known
   consumed cameras remain skips ([ADR 0158](../decisions/0158-the-first-headset-frame-must-match-its-camera.md)).
6. VR allocation boundaries catch DxvkError as well as standard exceptions and report
   RTXVR_E_RESOURCES, error 8 (`rtx_vr_policy.h:11`). They cover eyes, overlays, capture staging,
   colour views and timestamp allocation. Real-renderer probes throw the actual non-standard type
   at eye, overlay and capture sites. All three returned the exact page reason, released VR and
   quit normally with settings restored. They did not exhaust the GPU or crash the game.
7. VK_KHR_get_memory_requirements2 is requested independently of FSR. The explicit creation list is
   two instance and four device names, six total. S1's original five-name delta was correct with
   FSR present; that library supplied the sixth then. A package without the optional FSR DLL
   accepted 810 matched pairs with zero Submit errors and proved the DLL absent from loaded modules
   ([ADR 0157](../decisions/0157-steamvr-requirements-do-not-depend-on-fsr.md)).
8. Only the published render context reaches the overlay map; the swap-chain context returns before
   reading render-owned state (`rtx_vr.cpp:755`). Publication uses the DxvkContext base pointer.
   A concurrent test covers 100000 ownership changes, and the real queued/unqueued HUD copies pass.
   beforeSubmission reads pacing flags under the request mutex too.
9. A capture stays pending until output (`rtx_vr.cpp:612`). Overlay requests are also consumed only
   after camera eligibility, so an initial/stale skip cannot discard registration or removal.
   Both queue modes produced centre, depth, both eyes, mirror, timing and overlay files after a
   capture requested during a five-second absent-scene interval. CPU policy tests cover deferred
   consumption. A capture cancelled by an expected resource failure is not image acceptance.
10. New storage images begin UNDEFINED and transition to GENERAL before writes (`rtx_vr.cpp:179`).
    The strong preset selects DLSS with Ray Reconstruction when supported and TAAU otherwise;
    policy tests check that selection and its enum identity. Closed timing records are capped at
    1024 without eligible frames, tested from an overfull queue (`:440`). Native mismatch errors
    name the compiled API, tested against a stand-in. AMD/Intel hardware was unavailable; the
    layout/capability correction has source and offline proof, not a physical run on those cards.

The recovery, allocation, queue and no-FSR probes above used the pre-startup-correction runtime
`2cbf7f0d`; patch 0071 changes only initial camera eligibility. Their handlers/shader code remain
unchanged. Final normal acceptance, physical tracking and the deterministic camera test use
`d29445c5`. All raw runs remain identified separately rather than relabelled as the latest binary.

## Source, binaries and package

The seven runtime commits are `823796d0`, `e2b3a349`, `381cfb2d`, `5718fa25`, `8d348e14`,
`2cbf7f0d` and `d29445c5`. Each was exported separately as patches 0065 to 0071. Experimental
builds used -NoImport. Wire API 3 adds focus/wait counters; both header copies are identical:
StartInfo is 168 bytes, FramePose 112 bytes and Status 456 bytes. Lua Version remains 1.

| Final DLL | Size, bytes | SHA-256 |
|---|---:|---|
| d3d9.dll | 418358272 | `e43aef99a74d333fa75cbb27f8848ae7ba25ce4e8e200f5c7d0f936a69382046` |
| gmcl_nlvr_win64.dll | 446976 | `fa1ce35e3656eb22fd5d408af047992fdb83e8ef4ee78fa447523d6a11f4e1d9` |
| Unchanged openvr_api.dll, v2.15.6 | 837272 | `bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a` |

The canonical local package is this worktree's
`out/dist/gmod-rtx-remix-0.0.0-vrq.runtime-review-final2.gma`: 1785 files, 2185396433 bytes,
SHA-256 `58e3d3d09b5efba73f55e4d1d7e8c881f5df4ec1cce59ceb09878671742ed268`.
Its nlctl check passed. The JSON beside it and `out/vr/review2/final2-package.log` record the build.
Package extraction and decompression independently reproduce both selected DLL hashes.

There was one premature local runtime import, SHA-256 63fabdf9..., before the physical first-camera
hole was found. Its uncommitted package inputs were restored. After the corrected -NoImport build
passed the physical/injected tests, long runs, flat pairs and original-scale image inspection,
the exact e43aef99... bytes were verified and imported. Thus there were two local runtime import
calls and one module import call; only the selected runtime blob is committed. No intermediate
runtime blob was committed, pushed or published. This is an explicit exception to the requested
single-import sequence, caused by the late test finding, not an unreported experimental shipment.
`import-selected7-started.json`, `runtime-verify-selected7.log` and `runtime-import-selected7.log`
record it. Native source provenance was refreshed with repo_builds.py, not a second module import.

## Nearest-surface pictures and cost

All final measurements use the RTX 5090, driver 617.42 and an unworn Index at 90 Hz. Recommended
eyes are 2468 x 2740 pixels; the centre is 3072 x 2752 pixels and primary depth 1536 x 1376 pixels.
The preset is scale 1, DLSS Performance with Ray Reconstruction and one to four bounces. The
fixture fixes clear weather, noon, player view and a head timeline. No person judged comfort.

The fixed-interval prototypes used the earlier `381cfb2d` search, 75 s active each. Post-capture
warp brackets for 16/32/64 intervals averaged 0.23/0.36/0.73 ms on gm_construct and 0.24/0.46/0.74 ms
on modern_house. They precede the final two-surface refinement and HUD acknowledgement latch.
The heavy 32/64 pilots failed with one/three unmatched cameras; their failures are retained.

Sixteen intervals also miss single-depth-texel foreground in the Index CPU fixture. Normal spacing
follows the ray segment in the actual depth texture, with one extra interval, local refinement
and a ceiling of 128. The Index segment spans about 33 depth texels, producing 34 intervals and
35 positions. Pictures, the thin-object test and measured cost support that choice. The launch-only
RTX_VR_WARP_TAPS override is read at VR initialization; it is not Lua input or a saved option.

Final original-scale panels and per-row edge coordinates are in this worktree's
`out/vr/review2/analysis/final7/{barrel,lantern}-crops.png` and the corresponding widths JSON files.
Rows are aligned through the measured asymmetric projections. Widths below are row means in pixels.

| Object and run | Centre | Left eye | Right eye |
|---|---:|---:|---:|
| gm_construct barrel, original scale-100 | 283.3 | 270.3 | 268.8 |
| Barrel, final runtime | 283.8 | 284.2 | 280.7 |
| Modern House target called lantern in the review, original | 285.3 | 277.4 | 277.3 |
| The same target, final runtime | 285.2 | 285.7 | 282.9 |

The lost foreground strips are restored. Both eyes now agree within a few pixels rather than
losing 8 to 14 pixels each. Half-resolution depth, reconstructed colour boundaries and genuine
disocclusions still leave small outlines; this is not exact stereo geometry. The probe's near
target is the same oildrum model on both maps, including the target called lantern in the review.

Final warp means are 0.558 ms on gm_construct and 0.645 ms on modern_house, from 349 and 28 steady
profiles. The old quoted 0.11 ms belongs to the old algorithm and a different run. The pre-guard
loaded-host runs measured 1.98/2.65 ms for this search while other programs occupied the GPU.
Those are not an isolated shader-cost ratio. The final runs began at 0%/1% GPU utilization;
their 0.56/0.64 ms brackets are the representative low-load measurements.

## Final acceptance and pacing

Raw final sessions are the main checkout's `out/vr/q/review2/construct-final7` and `house-final7`.
They used the exact selected DLL before import, in the candidate7b package. Rendered, submitted
and matched pair counts are equal in each row. Whole counters include startup and capture work.

| Map / active duration | Accepted pairs | Failed Submit | Unmatched | Presents | Dropped | Reprojected | Steady pairs/s |
|---|---:|---:|---:|---:|---:|---:|---:|
| gm_construct / 310 s | 26199 | 0 | 0 | 27895 | 33 | 2582 | 85 |
| modern_house / 120 s | 3782 | 0 | 0 | 10625 | 0 | 8680 | 30 |

Steady windows start after 60 s. Compositor reprojected/present ratios are 8.59% and 78.97%; steady
drops are 31 and 0. Longer-than-refresh work reprojected without Submit errors or a stalled progress
counter. All five usual pose/HUD captures have the full seven-file set. Both runs quit normally,
unloaded the SDK and restored settings. First FOV is 1.90874 radians, about 109 degrees, with no
unknown-camera log. The first-camera diagnostic run separately proves the withheld-startup branch.

| Mean bracket, ms per accepted pair | gm_construct | modern_house |
|---|---:|---:|
| Scene preparation and acceleration structures | 0.350 | 0.561 |
| Path tracing and volumetrics | 6.128 | 10.705 |
| Demodulation / separate denoising | 0.040 / 0.0002 | 0.069 / 0.0002 |
| Composition | 0.314 | 0.316 |
| DLSS and fused Ray Reconstruction | 2.029 | 2.175 |
| Post-processing and tone mapping | 0.267 | 0.286 |
| Eye warp | 0.558 | 0.645 |
| Mirror / SteamVR Submit span | 0.007 / 0.043 | 0.008 / 0.043 |
| Late raster | 0.013 | 0.013 |
| Covered commands plus opaque SDK span | 9.749 | 14.820 |
| Queue gap / total elapsed span | 1.954 / 11.703 | 9.416 / 24.236 |
| Game-thread / render-thread CPU | 4.269 / 2.937 | 14.214 / 8.513 |
| Render injection wall time | 10.675 | 20.052 |

Ray Reconstruction runs inside DLSS; the tiny separate denoising bracket does not mean it is free.
Capture/overlay transfers are zero or below 0.00001 ms in these post-capture means. SDK spans and
queue gaps are not exclusive application shader work. BeginFrame averaged 0.160/0.205 ms, with
zero completion wait. Its legacy wait_get_poses field measures the predicted-pose query, not a
second pacing wait. Actual WaitGetPoses is only on the render side: means 9.29/16.99 ms, with
whole-run maxima 42.16/40.03 ms. Stop outwaits that SDK-call mutex and remains a barrier. It has
no independent upper bound if SteamVR stops answering; Lua stays in Stopping until native off.

The light map is clearly above the old 45 frames/s serial result, but does not deliver a full
90 frames/s: its observed 11.70 ms elapsed span exceeds the 11.11 ms refresh budget. The house's
14.82 ms work, 9.42 ms queue gap, CPU work and SDK pacing bound it well below native refresh.
No module wait or spin was added. V1 keeps render-side pacing as its only mode.

At 80 Hz the derived native/half-rate budgets are 12.5/25 ms. Holding the measured pairs-per-refresh
cadence constant gives about 75/27 pairs/s (the unrounded 90 Hz rates multiplied by 80/90). These
are extrapolations, not an 80 Hz measurement. Mean light-map work/span fits the native 80 Hz budget,
but changing refresh can change missed cadences and queue scheduling, so 80 frames/s is not promised.
The heavier map still cannot fit native 80 Hz. No SteamVR setting was changed.

Estimated pose age at display averages 38.31/82.20 ms. Mean prediction error is +0.13/-1.68 ms,
with 95th percentiles +0.87/+11.25 ms. Measured pipeline lead averages 2.26/5.94 refresh intervals;
it is not a guessed fixed queue depth. These are scheduling estimates, not optical latency.
The earlier heavily loaded 2cbf7f0d runs reached 28/17 pairs/s, with GPU utilization already
82%/75% before launch, pose ages 112.3/141.3 ms and prediction errors +15.0/+35.8 ms. Their lead
could exceed the module's eight-interval cap. Those runs remain as load/reprojection evidence.

The saved mirror world region differs from a cropped/resized left eye by at most 0.71/255 mean
RGB on gm_construct and 1.89/255 on modern_house. Every desktop witness has 4255 magenta pixels;
both eyes have zero. Turns/lean change the expected view and the wrist updates with the HUD.
`out/vr/review2/final-evidence.json` retains numeric checks, profiles and scheduling distributions.

## Flat comparison with the selected runtime

The control uses the published d3d9.dll, 418258944 bytes, SHA-256
`35ce500857c852e7babf0bd5a6fdc9495eef39703cfb2d4c33547c0bcec33054`, substituted into the current
package inputs. SHA-256 comparison proves all other 1784 archive entries equal; only d3d9.dll
and its manifest differ. The selected six runs are flat-{b1,n1,b2,n2,b3,n3}-r7 under the main
evidence root, alternating published/final. Both sides use gm_construct, Source FOV 90 degrees,
the same fixed pose/sky/settings, 30 s windows and the read-only inspector. Neither VR DLL loaded.

| Alternating run | Process launch to map ready, s | Median frame, ms | 99th percentile, ms | Frames/s |
|---|---:|---:|---:|---:|
| Published 1 | 23.8 | 8.245 | 12.363 | 119 |
| Final 1 | 25.6 | 9.127 | 14.881 | 107 |
| Published 2 | 25.9 | 10.012 | 14.030 | 99 |
| Final 2 | 24.4 | 10.007 | 13.980 | 99 |
| Published 3 | 24.7 | 10.165 | 14.479 | 98 |
| Final 3 | 26.0 | 10.323 | 14.420 | 96 |

The mean of medians is 9.474/9.819 ms, an observed increase of 0.345 ms, or 3.6%. Mean startup is
24.80/25.33 s, an increase of 0.53 s. The first pair dominates the frame-time difference; the other
two differ by -0.005/+0.158 ms. GPU utilization before launch ranged from 0% to 22%, and process/
clock context is retained. The sample does not isolate the cause or establish zero flat cost.
Active-view world regions differ by 0.68/0.65/0.64 mean RGB levels out of 255; original screenshots
and loaded modules remain in each run. The montage is `analysis/final7/flat-pairs.png` under the
worktree evidence folder. Earlier controls are retained but are not substituted for these final bytes.

With VR off, the final runtime explicitly requests six supported prerequisites at Vulkan creation:
VK_KHR_external_fence_capabilities and VK_NV_external_memory_capabilities at instance creation;
VK_KHR_timeline_semaphore, VK_KHR_dedicated_allocation, VK_KHR_win32_keyed_mutex and
VK_KHR_get_memory_requirements2 at device creation. It copies enabled-name sets, constructs dormant
CPU/container state, exports eight rtxvr entry points and executes inactive predicates/camera-FOV
bookkeeping in existing hooks. No new feature boolean, OpenVR/module load, scene initialization,
VR worker, VR GPU image/query allocation, preset or warp prewarm occurs before Start. Diagnostics
are read only at VR initialization. This describes the work; it is not a mathematical zero-cost claim.

## Retained failures and test limits

The 16/32/64-interval pilots, failed overlay-allocation harness attempt, two pre-VR launch crashes
and rejected camera fixture are preserved. The crash exception addresses were nvoglv64.dll+0xafa3aa
and +0xe622f8; no cause was isolated. An initial construct run faced about -54 degrees instead of
180 degrees, so counters alone were rejected. Automated CreateMove now pins angles and clears
input, with a neutral-yaw check; manual look keeps input. Flat controls own the CalcView table
temporarily and restore it. Compare flat-before images: flat-after is dispatched beside cleanup
and can show the restored camera. An apparent blank wrist preview was disproved by byte identity
and a separate RGB preview; no add-on code was changed for that false alarm.

The whole 20 KB probe once overflowed Source's command buffer. A later launch never acknowledged
its first 2048-byte stage while client startup continued; subsequent fragments correctly failed.
That loss was not causally isolated. Final transport starts with a tiny client-Lua acknowledgement,
then idempotent stages of at most 512 source bytes, each below 4096 serialized command bytes.
This is separate from the 512-byte argument and 4095-byte printed-line limits. The final hardware
runs and byte-reassembly regression pass; failed attempts and clean rollback receipts remain.

The pre-guard physical look's one unmatched first camera was initially missed by the manual
validator. It now checks sampled counters even without a scripted final-vr record. The old
uncommitted import was restored and the subsequent quiet run was deliberately ended through
Stop plus the probe's normal completion marker; its restoration is clean and it is not a benchmark.
The controlled mismatch and offset-pose regression close that startup gap.

## The user's look and the gate

Run from this worktree with fresh evidence. The same command was tested with evidence named
look-final2, including Start, Recentre, Capture, Exit and Done:

```powershell
python tools\vr_session.py --package out\dist\gmod-rtx-remix-0.0.0-vrq.runtime-review-final2.gma --evidence H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\q\review2\user-look-01 --look --seconds 900
```

After the preview message, use Start VR on the RTX page or `nl_vr_start`. Position the headset,
then use `nl_vr_recenter`. This uses physical tracking, not the scripted timeline, and leaves
mouse/keyboard input available. The tested optional capture command is
`lua_run_cl local ok,e=nlvr.Capture("look",15) print("NLVR_LOOK_CAPTURE",ok,e)`.
Use `nl_vr_exit`, then `nl_vr_demo_done` to restore settings, quit normally and roll back the
temporary package. It also ends after 900 s. If interrupted, wait for its game to exit and use
the driver's --rollback for that evidence folder; never remove another task's lock.

The canonical-package look observed 354 rendered/submitted/matched pairs, zero Submit errors or
unmatched poses, four overlay updates and all seven capture files. It quit normally, unloaded
the SDK and restored the PoC. Nobody wore the headset. Its look-commands.json records the actual
delivered commands, and restoration.json is clean.

`tools\test.ps1 -Config Release` passes in `out/worktrees/vr-q`. The selected code has 34 CTest
cases, 918 Python tests with seven skips, 16 native VR cases, 58 page/add-on/catalog cases,
16 driver cases and 249 standalone runtime assertions. Receipts are this worktree's
`out/vr/review2/gate-release-final.utf8.log`, `gate-summary.json` and `runtime-math-final.log`;
the raw PowerShell log remains beside them. New prose is ASCII and check_repo.py verifies links.

Raw game evidence is in the main checkout's `out/vr/q/review2/`; build, import, analysis, crops and
gate receipts are in this worktree's `out/vr/review2/`. Every selected run has clean restoration
and protected-file checks. No foreign lock/game or SteamVR process was ended.

Open: the cause of the small flat comparison difference, physical AMD/Intel validation, real
other-application focus throttling, optical latency, worn-headset comfort and the two pre-VR driver
crashes. Phase 1 retains small depth-edge/disocclusion outlines and cannot recover hidden surfaces
or eye-dependent lighting. Controller turning/movement are V2; true stereo remains V7. Approval
and any merge remain Claude's task. All changes and packages stay local.
