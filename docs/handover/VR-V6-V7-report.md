# VR V6 and V7: report

The user, 2026-11-13: "Don't fix now, also Skip V5, currently make it single player only. Proceed directly to V6 and
V7", then "You code it yourself" and, for V6, "Current rate only" (the Index's present 90 Hz; SteamVR's settings
untouched). Claude wrote all of it on the branch `vr6` (worktree `out/worktrees/vr6`, runtime tree
`out/worktrees/r17/out/runtime-src`, branch `vr2`). Plan: [VR-V6-V7-plan.md](VR-V6-V7-plan.md). **The user
approved V6 and V7 on 2026-11-13 ("Merge and publish") and they were merged to `main`**; the end of this report
has the package.

## Single-player only (V5 skipped)

Start VR refuses any multiplayer game, a listen-server host included, with "VR works in single-player games only.
Start a single-player game to use VR." ([ADR 0197](../decisions/0197-vr-is-single-player-only.md)). V5 (body and
multiplayer) is skipped. The weapons and reload drivers' neutral-yaw fixture regression from V4 stays open, as the
user said ("Don't fix now"); it still fails the PoC driver's own `neutral` check now and then (below).

## V6: Auto quality

**What it does.** VR quality is Auto by default. A seven-step ladder runs from V1's preset (`full`: render scale 1,
DLSS Performance, 1-4 bounces, volumetrics, fine clouds) down to `floor` (scale 0.5, Ultra Performance, 0-1 bounces,
no costly effects) ([`cl_perf_ladder.lua`](../../vr/addon/lua/nlvr/modules/cl_perf_ladder.lua.md)). Auto holds half
the headset's refresh, the rate SteamVR's Motion Smoothing fills in: two missed one-second windows step down, eight
settled windows step up, one rung at a time, never within three seconds of the last step
([ADR 0199](../decisions/0199-vr-auto-quality-ladder.md)). A miss counts only while the GPU's work fills 70 % of the
frame budget, so frames the game itself loses never cost quality, and the page says so
([ADR 0200](../decisions/0200-vr-auto-counts-only-the-gpus-misses.md)); the GPU is judged by its work, which runtime
patch 0088 reports without the frame's pacing waits ([ADR 0201](../decisions/0201-vr-auto-reads-the-gpus-work.md)).
The VR page has a Quality step setting (Auto or a fixed step), the render scale slider becomes a ceiling that applies
at once, and the status shows the step and why, the frame rate and the GPU's work against the target and budget.
Start renders at Auto's first step (the floor below 12 GB or on a low tier, step 3 below 16 GB, else the top).

**Runtime.** Patch 0087 adds `rtxvr_SetQuality` (API 4): the render thread writes the step into the `! VR session`
layer and reallocates the eye images when the scale changes. Patch 0088 adds `gpuMsWork` and `stereoActive` to the
status (496 bytes).

**What the runs taught.**

| Run | What it showed | What changed |
|---|---|---|
| `quality-sim-01` | every step reached the runtime, but the module's `Info()` lacked the applied step; `RunConsoleCommand("fps_max")` is blocked in GMod, so the frame cap the probe relied on never applied | `Info()` reports the applied step; the probe stages the measurement instead (below); Auto ignores misses the GPU did not cause (ADR 0200) |
| `quality-sim-02` | all of Auto's behaviour right; three faults in the checker itself (float rounding of the eye size, a phase's first step counted as a step, a too-short look-back) | the analysis fixed, with `--reanalyse` |
| `quality-index-01` | on the Index the frame's GPU span filled the frame interval at every step (22 ms at 45 fps, 11 ms at 90 fps, even at the floor): 6-10 ms of each frame is the queue waiting on the CPU; Auto stopped climbing at step 3 | runtime patch 0088, `gpuMsWork` (ADR 0201) |
| `quality-index-02` | Auto climbed on the work figure, but SteamVR's half-rate lock reads 44.1-45.1 of 45, under the 0.99 keep ratio, so climbing kept resetting | keep ratio 0.97, with an offline case built from those rates |
| **`quality-index-03`** | **every check passed** | |

**The final Index run** (`out/vr/v6/quality-index-03`, package `0.0.0-v6.4`, digest `0eddbc28...`, PoC
`gm_construct`, headset on the desk, nobody wearing it, 90 Hz): each pinned step reached the runtime as named (DLSS mode,
bounces, flags, scale and the eye images' size). With frames staged as missed while the GPU had room, Auto held the top
step and reported why. With the GPU staged over its budget it walked from step 1 to the floor, one rung every 3.0-3.1 s.
On the session's own readings it climbed back 7 to 1 between 68.8 s and 119.7 s, one rung every 8-10 s, and stayed at the
top; in 190 trace rows the runtime's applied step matched Auto's. 8,935 eye pairs, no submit errors, no unmatched poses.

| Step (pinned) | Eye size | Traced width | Frame rate | GPU work | GPU span |
|---|---|---|---|---|---|
| 1 full | 2468 x 2740 | 1548 | 44.4 | 14.8 ms | 21.3 ms |
| 2 high | 2468 x 2740 | 1548 | 45.1 | 14.1 ms | 20.8 ms |
| 3 balanced | 2222 x 2466 | 1392 | 45.0 | 11.5 ms | 22.3 ms |
| 4 fast | 1975 x 2192 | 827 | 70.0 | 6.2 ms | 22.6 ms |
| 5 faster | 1728 x 1918 | 723 | 67.0 | 5.5 ms | 11.0 ms |
| 6 low | 1481 x 1645 | 619 | 67.2 | 5.2 ms | 12.6 ms |
| 7 floor | 1234 x 1370 | 517 | 66.8 | 4.1 ms | 4.7 ms |

Steps 1-3 hold SteamVR's half rate; the cheaper steps run faster than the target. The rates at steps 4-7 depend on
how long SteamVR keeps its half-rate lock after the step that caused it (85 fps for step 4 in one run, 44.6 in the next).

**How it was tested.**

- Offline: the ladder and controller under LuaJIT (`vr_perf_harness.lua`, ten scenarios, each guard shown to catch a
  controller without it), the PoC analysis on synthetic records (`VRQualityAnalysisTests`), the native ABI and
  `SetQuality` pass-through, the runtime's `validQuality`. The gate now reaches them through
  `tools/tests/test_companion_vr_perf.py`.
- PoC: [`vr_quality_poc.py`](../../companion/tests/vr_quality_poc.py.md). GMod blocks `fps_max` from Lua, and a frame
  cap would be a miss the GPU did not cause, so the probe stages the measurement: it wraps `nlvr.Info`, through which
  the add-on measures, keeps 40 % of the frames and sets the GPU's work to 30 % or 150 % of the budget. Everything after
  the measurement (the controller, `SetQuality`, the runtime applying the step) is the production path, and the climb
  back runs on the session's real readings.

**Limits.** Tuned at 90 Hz only (the user's choice); the target follows the reported refresh, but 80, 120 and 144 Hz
were not measured. A step change costs a hitch (render targets are recreated); the cool-down keeps those rare.

## V7: true stereo

**What it does.** A **True stereo** switch on the VR page (and in the headset's settings panel, `nl_vr_stereo`, off by
default) path traces each eye with its own history instead of warping one centre view to both eyes. It needs DLSS Ray
Reconstruction and the physical sky; otherwise the runtime keeps the warp and the page says why. The status says which
mode runs ("Stereo: each eye path traced" or "one picture turned into both eyes"). Auto's ladder applies as before;
true stereo rides on every step.

**How** ([ADR 0198](../decisions/0198-vr-true-stereo-by-swapping-the-eyes-state.md),
[ADR 0202](../decisions/0202-true-stereo-shares-the-frames-work.md)), runtime patch 0089, no shader changes:

- `rtx_vr_eye.h` names the eye the render thread is tracing (-1 the centre, 0 left, 1 right). The left eye keeps the
  default view state; the right eye's `Resources`, ReSTIR GI, Ray Reconstruction, neural radiance cache and SHaRC are a
  second set in `DxvkObjects`, behind the accessors every pass already uses, so each eye's histories advance once a
  frame. The right eye reads the frame's TLAS, noise, sky probe and matte from the default state.
- Each eye's camera stands in for Main while that eye is traced, from the centre camera, the eye's offset and its own
  off-centre frustum (`vrmath::eyeToCentreView`, `eyeProjection`, unit-tested against the warp's own eye rays).
- `RtxContext::injectRTX` runs one view's pass chain per call: the centre, or each eye in turn. Once a frame, on the
  centre camera: the scene, the sky's integrators, the froxel volumetrics (whose frustum holds both eyes) and auto
  exposure. Per eye: the aerial perspective volume, fitted to the eye's frustum by shifting its forward vector, and the
  cloud history.
- The NRC library starts with the first context and stops with the last; before, a second cache would have failed to
  start and switched both eyes to importance sampling.
- `RtxVr` copies each eye's picture into its eye image and submits as before; `rtxvr_Status.stereoActive` says which
  mode ran. The module passes the step's `stereo` flag (`RTXVR_QUALITY_TRUE_STEREO`).

**What the runs showed** (PoC `gm_construct`, top step pinned, head held still, nobody wearing the headset; evidence
`out/vr/v7/`). [`vr_stereo_poc.py`](../../companion/tests/vr_stereo_poc.py.md) runs the warp, true stereo, the warp and
stereo again, captures both eyes in each phase and compares them at 96 x 96 grey:

| | Simulated (`stereo-sim-02`) | Index (`stereo-index-01`) | Index, final package (`stereo-index-02`) |
|---|---|---|---|
| Mode follows the switch, twice each way | yes | yes | yes |
| Traced width per eye / centre | 1234 / 1556 | 1234 / 1548 | 1234 / 1548 |
| GPU work, warp then stereo (median) | 13.4 then 17.1 ms (1.28 times) | 14.7 then 17.5 ms (1.19 times) | 13.4 then 17.9 ms (1.34 times) |
| Frame rate in both modes | timer-paced | 45.0, SteamVR's half rate | 45.0 |
| Each stereo eye against its own warped eye / the other | 0.95 and 1.00 / 0.64 | 1.00 / 0.64 | 0.99 and 1.00 / 0.65 |
| Brightness, stereo against warp, left and right | 1.02-1.03, equal | 1.024 and 1.024 | 1.02-1.03, equal |
| The driver's own checks | failed only its capture check (fixed after) | failed only its capture check | **passed** |

So each traced eye is the warped eye's picture (nothing swapped, mirrored or misplaced) with the disparity a second
viewpoint gives, both eyes keep one exposure, and the second eye costs a quarter to a third more GPU work (1.19 to
1.34 times on the Index), because the warp and the frame's shared work are not paid twice. The first simulated run (`stereo-sim-01`) rendered correctly too, but
its first pair was captured while the driver's timeline turned the head; the PoC now holds the head still. The PoC
driver's capture check learned that a stereo capture has no centre view (both early runs failed only that check, on
the driver's own scheduled captures that fell into a stereo phase).

**Limits.** Stereo is honoured only with Ray Reconstruction and the physical sky (NRD, TAA or DLSS without Ray
Reconstruction would each need more instances; the rasterized sky's matte is a picture of the centre view). The two
eyes' neural caches learn separately; their pictures agreed in every run. A switch, or Auto's step change, costs a
hitch (render targets are made again, and the right eye's state on the first stereo frame). The VR profile's pass
breakdown covers the left eye; its total, and `gpuMsWork`, cover both.

## The candidate

Everything above was built on the branch `vr6`; the user approved it on 2026-11-13 and it was squash-merged to `main`.

- **Package** `out/dist/gmod-rtx-remix-0.0.0-v7.2.gma`: 2,086,420,546 bytes (1,832 files, 2,085,859,058 bytes of
  content), SHA-256
  `1e81f06fae2609d989e5057bc1d1da002d999fe0236cdb4d21faa5c62785193e`, content digest `eb7c0556...`.
- **Runtime**: patches 0001-0089 from the clone's `vr2` at `1097d701`, `d3d9.dll` 418,468,864 bytes, SHA-256
  `8d64393fdb4343f7e4db2f71c683a9becbd5fe167c84d23924712fb052fd437f` (0087 the quality step, 0088 the GPU work, 0089
  true stereo).
- **VR module** `gmcl_nlvr_win64.dll` 542,720 bytes, SHA-256 `8d1b6f30b3e5...`, recorded clean against its sources.
- **On that package, on the Index at 90 Hz**: the true-stereo run passed every check, the driver's own included
  (`out/vr/v7/stereo-index-02`), and the V6 quality run passed every check (`out/vr/v7/quality-index-04`: Auto from the
  top to the floor under load, back to the top in 51 s and settled; the runtime's step matched Auto's in 190 rows).
- SteamVR was not running at the start of the Index runs; the first one started it through OpenVR, as Start VR does,
  and it was left running. Its settings were not changed.

**Published:** squash-merged into `main` as `c8eba6d0` (tree `275b1570`, the tested `vr6`'s) and pushed. The commit's
hook uploaded the package to item 3829070317 as `0.0.0-dev.20261113173439+d1cc7cda` (2,086,420,569 bytes, SHA-256
`e41f442cd20572cd0c5375d46c7b0f932c44c220905b09d5ff7173a92f888973`, content digest `eb7c0556...`, the tested `v7.2`'s digest,
so its content is the candidate's; Steam took 33.2 MB of changes); the push's hook found the inputs unchanged. The
field gets it at its next start (Steam's update of the item).

**Open:** the V4 neutral-yaw fixture regression (left as asked, it
still trips the driver's `neutral` check now and then: `quality-sim-03`; `quality-sim-01` failed the driver on the
three blocked `fps_max` calls, which the probe no longer makes); refresh rates other than 90 Hz were not measured
(as chosen).
