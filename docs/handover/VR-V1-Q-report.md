# VR-V1-Q: integration and Index evidence

Current startup correction after the second runtime review: the VR creation list guarantees two
instance and four device names independently of FSR, six names in total. The five-name delta
measured in this report belongs to the original installation with FSR present;
VK_KHR_get_memory_requirements2 was then supplied by that optional library. See
[ADR 0157](../decisions/0157-steamvr-requirements-do-not-depend-on-fsr.md) and the
[second-review report](VR-V1-Q-runtime-review-report.md) for the corrected code and renewed evidence.

The [independent-review and render-pacing follow-up](VR-V1-Q-review-report.md) supersedes affected
API/path/pacing descriptions below. The original measurements remain historical evidence.
The current artifact is **out/dist/gmod-rtx-remix-0.0.0-vrq.review-final2.gma**; use the follow-up's
preview/recenter commands and final 910-test gate receipt. The old artifact/serial figures below
are retained for comparison, not the current shipping instructions.

Work is on `vr-q`, from `a9aae36`. Scope: [Q brief](VR-V1-Q-integration.md),
[V1 interfaces/test rules](VR-V1-plan.md), [binding design](VR-plan.md).
No loader source change, push, merge into `vr`/`main`, tag, Workshop publication or workflow run.
Commits use the configured SheepyLord identity and required Codex co-author trailer.
Claude's independent review and the user's milestone approval remain separate steps.

Evidence paths below are relative to the **main checkout's `out/vr/q/`**:
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\q`.
Build/scratch paths refer to this worktree's ignored `out/`.

## Built and packaged

The module, runtime, add-on and page run together. SDK readiness starts the camera producer;
the first traced frame follows its first WaitGetPoses/camera push. A camera-armed completion
ticket orders later compositor epochs. A no-scene timeout parks the ticket without repeatedly
sleeping the game thread. Exit removes the view immediately and acknowledges SDK unloading.

Runtime patches **0060** (`fa0b19ec`) and **0061** (`72f3cb83`) consume each fresh camera once
and preserve VR extents/projection/last mirror while waiting. Both are exported individually.
The version 1 C header is unchanged. The ordinary Python gate reconstructs it from the patch
hunks and compares it with the module header, ignoring only line endings.

The fifteenth package part, `vr`, carries both DLLs, the no-autorun add-on, four real on-disk
input JSON files, MIT licence and OpenVR BSD-3-Clause licence. No eager OpenVR dependency or
loader change. CI's generic collectors read the new repository_builds/fetched entries; OpenVR
is no longer staged. [vr_session.py](../../tools/vr_session.py.md) and its Lua probe provide both
shared locks, snapshot/preserved originals, local package install, scripted or actual poses,
production Start/Exit, captures/native telemetry, inventories, shared-setting restoration,
SteamVR log tails and verified rollback. Long JSON uses checked base64 packets because Source
truncates console lines at 4095 bytes. Manual preview, listen-host, no-scene, active shutdown and
expected-failure modes use the same driver. An optional test-only read-only helper measures
the Lua thread's CPU time and queries the already-initialized SDK's eyes; it never initializes
OpenVR or renders/submits and is absent from the shipped package.

The translated page gives low-FPS-cap/install instructions. Culling defaults to the tested
**145 degrees at 16:9**. The fixed V1 preset is **scale 1, DLSS Performance, Ray Reconstruction,
1-4 bounces**. Low tier or below 12 GiB still warns/caps scale at 0.5 without blocking. Auto is V6.

| Input | Bytes | SHA-256 |
|---|---:|---|
| Runtime, fork `vr` at `72f3cb83` | 418332672 | `66cbcc7c64f84b31e0e18de0e9644affbdfea31d3810d80d0ae6a7021786c52a` |
| gmcl_nlvr_win64.dll, sources `3d45d72` | 441856 | `58921be51c2d437c6da5b84bd14dc0c1bc13c9d4ab3b289243d2a9d0f3afdcb2` |
| OpenVR v2.15.6, `0924064316de3effbcd1acf1e309182a2deb1c05` | 837272 | `bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a` |

Each was imported once: runtime through build_runtime.ps1, module through repo_builds.py refresh,
SDK through inputs.py import. No experiment imported a runtime. base.json now records every
packaged patch/dependency with no pending suffix; repository module records are current.
The pinned SDK header/licence stay unchanged. Shared C header LF SHA-256:
`645ac84ac0cd35b1731c444a7e20402b9db23e79102bdd0b742142cd4a206872`.

`python tools/build_package.py --version 0.0.0-vrq.v1` builds the whole package locally, checked
by nlctl: **1785 files, 2185360905 bytes**, content digest prefix **4cfdca0eeecbee67**.
Artifact: `out/dist/gmod-rtx-remix-0.0.0-vrq.v1.gma` in this worktree. The baseline package has
the same other parts/page/add-on and the exact published runtime
`35ce500857c852e7babf0bd5a6fdc9495eef39703cfb2d4c33547c0bcec33054`, read from main's indexed input.
The performance candidate has these same runtime/module/add-on bytes; each scale was explicitly
passed through the page. Its page's earlier default does not change those measured StartInfo values.

## Mismatches and corrections

1. **First-frame dependency/order:** D's State/BeginFrame waited for renderer RUNNING; E loaded
   view hooks at RUNNING; C could render before a camera. First combined smoke: **3 unposed frames**.
   `Info.sdk_ready` now identifies producer readiness while State can still be starting. BeginFrame
   bootstraps then; 0060 requires a fresh camera before output. No C ABI/version change.
2. **Ticket/extent:** the 25 ms wait held the session API mutex and repeated during absent scenes.
   It now releases the mutex while sleeping, keeps its timer alive across cleanup, and after one
   timeout polls once without sleeping until completion. No early WaitGetPoses resets the epoch.
   The first gated runtime then oscillated flat/VR extents: smoke-02 made **157 pairs in 25 s,
   13.91 game FPS**. 0061 keeps the centre extent/projection and mirror without duplicate submission.
   Smoke-03 recovered **45.05 FPS / 2933 accepted pairs**, zero errors/unmatched.
3. **Stop:** the page used to claim off/remove its poll immediately. It now holds stopping until
   native off acknowledges runtime barrier/SDK release, refusing restart meanwhile. View hooks
   are already removed. Native module unload still joins an unfinished worker, as D documented.
4. **Return conventions:** native mutators return nil plus an error, rather than throwing. Camera/
   overlay mutations are checked. BeginFrame nil without error holds the last camera and never
   pushes the same sequence twice. Rejected pushes clean up.
5. **Limits/counts:** native 32 overlays/16384-pixel sides now match runtime **16/8192**. The fake
   renderer counts accepted pairs, matching the runtime, instead of counting two eyes as two frames.
   Opaque string handles, Info/frame field names and input-manifest discovery otherwise matched.
6. **FOV/default/cap:** provisional FOV 140 becomes C's tested **145**. Default/fallback scale is
   now **1**, matching the module and StartInfo. fps_max is Lua-blocked; the page gives the physical
   console command. nl_vr_start accepts an optional out/ timeline for integration tests.
7. **Fixture corrections:** command dispatch is asynchronous, so diagnostics attach next tick.
   A test server command is installed from the physical console; client Lua cannot call lua_run.
   Noclip prevents the actor falling 40 units. Flat controls freeze clear/noon with zero weather
   transition. Long native/status/projection JSON exceeded **4095 bytes**; missing/truncated packets
   now fail. `scale-070` is developmental evidence with truncated sample lines; **scale-070-r2**
   is the accepted repeat.
8. **Readback:** GetConfigVariable reads file configuration, not live layered options. Fourteen
   unset entries returned empty strings: their equality is **not live-option restoration proof**.
   Source convars, unchanged user.conf, flat images/frame times, reversible layer code and the
   actual live upscaling snapshot are the relevant checks.

D's material queue result and camera ring stand. E established real CalcView precedes PreRender;
once-per-engine-frame acquisition at the first callback stands. Actual SDK eyes have identity
rotations/asymmetric frusta, rather than the design's cant assumption. No binding decision changed.

## Spikes S1-S8

| Spike | Numeric result |
|---|---|
| S1 | A: **6 instance / 7 device** required names, all offered on the 5090; published runtime lacked **2 + 3** enabled names. C adds those five supported names with no OpenVR load. Q's starts validate complete required lists against actual enabled names, lastError **0**. A: main `out/vr/s1/extensions-final.json`; Q: required-extension lines in each runtime log. |
| S2 | Scale 1 eyes **2468 x 2740**, centre **3072 x 2752**, tracing **1536 x 1376**, unchanged desktop **1280 x 720**. C's equal-extent control: **128.15 flat / 128.20 no-submit FPS** at 2392 x 2160. Q has PNGs/timing JSON at each pose. |
| S3 | C unfenced: **139 failed eye calls / 6436 frames**, error 108. Q scale-1 long run: **8557 rendered / accepted / matched**, **0 Submit errors, unmatched or drops**; **17131 presents / 8561 reprojected**. Other accepted pairs: **9099** at 0.85, **9597** at 0.7, **5956** on Modern House, all zero Submit errors/unmatched. Offline tickets preserve W-S-W-S; SDK-ready hooks bootstrap first output. |
| S4 | D, queue mode **2**: **360 attempts, 0 accepted, 0 callbacks**, 120 frames; public ICallQueue path is an arena ABI on this build. Keep the nearest-camera ring. Q's moving/stationary scripted views match with **0 unmatched**. D: main `out/vr/d/s4/`. |
| S5 | A, **840.010121 s** active unworn scene: **74763 waits / 149526 accepted eye calls / 0 API errors / 0 invalid poses**, **831/835 standby samples**. Its **292 drops / 1700 reprojections** and 15 transient not-responding events remain disclosed. Q continues in activity Standby (3); actual-head shutdown accepts **908/908** pairs, zero errors/unmatched/drops. No proximity/panel-luminance claim. |
| S6 | Engine FOV **145** at 16:9; SDK union **114.072 x 109.363 degrees**, 0.5 m coverage margin retained. **8557 matched / 0 unmatched**. Image motion for scripted +/-20 degrees: **+20.236 / -20.303 degrees**; 0.2 m lean shifts **77.5 px**, predicted **76.294**. Painted texture stereo NCC **0.932-0.997**, near tangent disparity about **0.0315**, implied depth about **87 units**; far building **1660-1754 units**. Depth PNG code 103 means about **87.2-91.1 units**, consistent within pixel/depth quantization. |
| S7 | Index **90 Hz**, RTX 5090 **32607 MiB**, driver **617.42**. Scale 1: **44.999 FPS**, **9.404 ms** command/SDK work, **10.485 ms** queue gap, **19.890 ms** elapsed span. Fine path **5.935**, upscale/RR **2.232**, both warps **0.111 ms**. Other scales/map below. **80 Hz is derived**, native/half budgets **12.5/25 ms**. |
| S8 | Wrist **769 x 257 / 0.23 m**, visible true, texture/absolute-transform errors **0**. Real HUD **87 health / 31 armour / 18-256 ammo** becomes **63 / 47 / 9-54**. Mirror world error against left-eye crop **0.58-0.77/255**, against right **34.6-56.8**. Magenta desktop witness **4231 mirror pixels / 0 in either eye**, five captures. |

Image evidence: `scale-100/captures/`, `image-analysis.json`, `feature-matches.json`. Silhouette
midpoints are not corresponding stereo surface points; the exploratory midpoint depth estimates
are labelled invalid. Depth uses matched painted texture patches. Pictures are upright and follow
the head; no flat HUD/hand/view model reaches the eyes. Foreground/disocclusion limits remain.
`camera-log-check.json` records **73/77/81/51/19** main-camera diagnostics for scale 1/0.85/0.7,
Modern House and real-pose preview respectively, with **zero cut=1 entries**. No repeated camera cuts.

## Performance and preset

Static windows are approximately second 70-197, after captures/gestures; exact ranges/counts,
native/SDK fields and fine profiles are in summary.json. Used profiles have known coverage and
zero untracked submissions. Percentages below are SDK reprojected/presents deltas, not 1-FPS/refresh.

| Scene / scale | Submitted eye | Centre / traced | FPS | Work + SDK ms | Queue gap ms | Reprojected | Steady / whole drops |
|---|---|---|---:|---:|---:|---:|---:|
| gm_construct 1 | 2468 x 2740 | 3072 x 2752 / 1536 x 1376 | 44.999 | 9.404 | 10.485 | 50.00% | 0 / 0 |
| gm_construct 0.85 | 2098 x 2329 | 2616 x 2336 / 1308 x 1168 | 48.004 | 7.345 | 11.467 | 52.47% | 2 / 2 |
| gm_construct 0.7 | 1728 x 1918 | 2152 x 1928 / 1076 x 964 | 49.018 | 6.016 | 8.982 | 48.09% | 0 / 0 |
| modern_house 1 | 2468 x 2740 | 3072 x 2752 / 1536 x 1376 | 32.894 | 14.219 | 6.566 | 82.83% | 2 / 119 |

Modern House's whole-session drops include startup/transitions/captures; they are not hidden.

| Fine stage, mean ms | Construct 1 | 0.85 | 0.7 | Modern House 1 |
|---|---:|---:|---:|---:|
| Preparation / AS | 0.349 | 0.350 | 0.349 | 0.545 |
| Path / volumetrics / lighting | 5.935 | 4.840 | 4.083 | 10.752 |
| Demodulation | 0.040 | 0.036 | 0.022 | 0.055 |
| Separate NRD denoising | <0.001 | <0.001 | <0.001 | <0.001 |
| Composition | 0.329 | 0.227 | 0.149 | 0.314 |
| Upscale, including fused RR | 2.232 | 1.571 | 1.176 | 2.099 |
| Post / tone mapping | 0.316 | 0.200 | 0.145 | 0.285 |
| Both warps | 0.111 | 0.062 | 0.043 | 0.104 |
| Mirror | 0.007 | 0.006 | 0.008 | 0.007 |
| SDK Submit/handoff interval | 0.069 | 0.040 | 0.028 | 0.044 |
| Late raster | 0.016 | 0.012 | 0.012 | 0.013 |
| Steady capture / overlay transfer | <0.001 | <0.001 | <0.001 | <0.001 |

SDK intervals may contain IPC/host wait, not pure shader execution. Public gpuMsTotal/Other include
the queue gap: the full 19.890 ms is not GPU execution. RR fuses denoising into NGX, leaving NRD empty.
CS running CPU means: **3.312 / 3.392 / 3.362 / 8.441 ms**. The read-only helper measures actual
Lua/game-thread CPU **4.673 / 4.905 / 12.419 ms** for 0.85/0.7/Modern House. The first scale-1 cohort
predates its CPU samples; native-call/fence/WaitGetPoses/game-work wall breakdown is retained.
C's same-resolution control was **44.91 FPS / 9.66 ms work** versus **101.62 FPS** without Submit/
pacing. Q reproduces the hand-over limit with real module/add-on; reducing pixels does not sustain 90.

**Default 1** keeps SteamVR-requested detail and stable half-rate on the reference scene. Lower
scales save 22%/36% work for only about 7%/9% more throughput here. Neither reaches native 90.
This fixed V1 preset does not promise 45 FPS on every map: Modern House misses it and has much
greater game/CS CPU cost. The manual slider remains; automatic adaptation/scheduling is V6.
At unchanged size, 80 Hz gives **12.5 ms native / 25 ms half-rate (40 FPS) budgets**: derived
headroom, not measured 80-Hz throughput or a heavier-map guarantee. Every actual run remained 90 Hz.
GPU/process CSVs record shared desktop load. No compile/Release gate overlapped steady timings;
ordinary desktop/SteamVR programs still share the GPU. No SteamVR setting was changed.

## Lifecycle and restoration

- `smoke-03`: two Start/Exit cycles, **2933** accepted pairs in 65 s, zero errors/unmatched/drops;
  flat **128.50 before / 128.79 after FPS**. SteamVR-already-running startup **2.67 s**, median/p99
  frame **7.893/19.090 ms**, maximum **281.503 ms** at first resource transition. VR_Init stays on
  the worker and the game otherwise remains responsive.
- `host-pause-exit`: real listen host, fps_max **60**, **1132/1132** pairs, zero errors/unmatched/
  drops. **37** samples show `Type fps_max 90`; cap stays 60 through Exit. Counter holds **1132**
  during no trace. The timeout count increases once for the pause, then stays fixed; calls poll
  without sleeping. Exit from pause and second Start/Exit work. Only menu hook/no timer remains.
- `live-shutdown`: actual unworn head poses, no timeline, **908/908** accepted pairs, zero errors/
  unmatched/drops, then genuine normal quit in VR. SDK is intentionally present in the pre-quit
  module list; process exits normally, shared settings and verified rollback restore the session.
- `manual-look`: the documented manual-preview route was exercised with physical-console
  `nl_vr_start`, actual (unworn) tracking/capture, and **nl_vr_demo_done**. Samples observe at least
  **2165 accepted pairs**, zero errors/unmatched. Live readback proves **DLSS-G 1 before -> 0 in VR
  -> 1 after**, with upscaler 1 and support flags restored. All **14 real Source convars** match,
  SDK is absent after Exit, no session hooks/timers remain and rollback is clean. Saved actual
  capture includes both eyes/centre/depth/wrist/mirror/timings.
- `missing-runtime`: the real baseline DLL has no VR exports. Production Start refuses before
  OpenVR loads, with **"This Remix runtime has no VR output. Update the RTX package and restart
  Garry's Mod."** Expected reason runtime, zero acquired frames, normal quit and clean rollback.
- Offline actionable cases cover missing module/version/runtime/SteamVR, HMD/init/interface/
  manifest failures, active VRMod/gVRMod and remote refusal. A missing SteamVR installation gives
  install instructions. Held fake VR_Init **1000 ms** exercises responsive API/cancellation/readiness
  and paced ordering without initializing the real headset.
- Completed Q rollbacks verify **2877 depot files**, original trees, config/Source registry and
  protected user.conf SHA-256 **743bd25806b9e2b2ebd82f7d39248f05af4ae20e8747d85a59f1a8c7718d4f56**.
  user.conf was never moved/written; field/RTX_c/backups untouched. Shared locks are exclusively
  created in main/out and only the caller's matching owner is released.

No scene means no new eyes. SteamVR may retain/reproject/fade the previous submission or show
its own loading/dashboard presentation; no runtime loading world is synthesized. C's composited
no-scene mirror retained the world under the dashboard (RGB mean change **0.372/0.313/0.325**).
Exit clears the session submission. V1 refuses Start before a local map, before loading OpenVR.
Map/menu realm teardown stops the session. Fatal Vulkan loss/replacement was not induced or promised.
Native off acknowledges SDK release. GMod caches one **790532-byte Source wrist canvas**/fonts
until exit; no add-on frame hook/timer/active SDK remains. Runtime images/queries/preset retire at
the next render boundary, including menus.

## Flat parity and gate

All six alternating controls pass with the same clear/noon map/camera/settings and 30 s timed
windows. Both the native VR module and openvr_api.dll are absent in every control. Raw Source
frame intervals count game frames, not interpolated DLSS-G display frames.

| Run | Runtime | Map ready s | FPS | Median / p99 ms |
|---|---|---:|---:|---:|
| b1 | published | 23.7 | 127.950 | 7.8705 / 10.6339 |
| n1 | new | 25.0 | 129.624 | 7.7526 / 10.5518 |
| b2 | published | 24.5 | 130.091 | 7.7455 / 10.4342 |
| n2 | new | 24.3 | 130.085 | 7.7375 / 10.4299 |
| b3 | published | 24.1 | 130.902 | 7.6721 / 10.6222 |
| n3 | new | 24.4 | 130.677 | 7.6915 / 10.6998 |

Mean run medians **7.7627 -> 7.7272 ms**, **-0.0355 ms / -0.457%**; mean p99
**10.5634 -> 10.5605 ms**. No consistent frame penalty is detected. Mean map readiness is
**24.100 -> 24.567 s**, +0.467 s, with mixed pair differences (+1.3/-0.2/+0.3 s); excluding
neither run, this is not proof of mathematical zero startup overhead. Last two pairs average
+0.05 s, but all six numbers are retained. Pixel full-image means are **0.77-0.97/255**;
world-region means **0.87-1.04/255** across all three pairs, with no visible behavior change.
Evidence: `flat-{b,n}{1,2,3}/`, `flat-analysis.json`, retained analysis source and original PNGs.
The before/after-Exit world comparison also differs only **0.778/0.667/0.670 RGB codes / 255**.

`binary-verification.json` checks x64 PE files, **8 VR exports**, no OpenVR runtime import,
**KERNEL32.dll only** for the module, identical shared header, all actual package VR inputs/
licences and no eager SDK dependency. The CI collectors locally collect the VR target and
hash-checked SDK. **18 completed Q rollbacks are clean** (`rollback-summary.json`).
The original SteamVR server/compositor/monitor PIDs **27812/49804/42488** remain running;
no PoC game remains (`processes-after.json`).

**Final Release gate PASS** on implementation/report commit **a95c843**:
`tools\test.ps1 -Config Release` from this worktree, **34/34 CTests**, Python groups
**29 + 26 + 847 = 902 tests**, **7 availability skips**, no failures, ending **All checks passed**.
The main Python group took **104.375 s**. Normalized full receipt:
`build/gate-release.log`; raw worktree log: `out/vr-release-gate.log`.
The ten driver safety/packet/math tests, shared-header check, 48 page/add-on/catalog tests and
native mock tests are included. Existing negative fixtures print expected diagnostics; they are
not gate failures. The following commit only fills this report's completed receipts; code is unchanged.

Source sites for RESEARCH/review: `vr/native/session.cpp:138` (renderer readiness/deadline),
`:266` (unlocked/parked completion wait), `:396` (async Stop), `:426` (first frame);
`companion/.../nativeloader_vr.lua:87` (acknowledged Stop), `:125` (SDK-ready producer), `:197`
(FPS warning); runtime `rtx_vr.cpp` pushPose/projection/beginFrame/output/mirror in patches
0060-0061; `tools/vr_session.py:217` (complete packet parsing), `:276` (steady work/gap accounting).
Build/import/package/collector logs and binary-verification.json accompany the gate. The retained
input and output images remain unmodified; analysis scripts and source/helper receipts are in out/vr/q.

In this original FSR-present build, the off-state device delta was five supported names: instance **VK_KHR_external_fence_capabilities**,
**VK_NV_external_memory_capabilities**; device **VK_KHR_timeline_semaphore**,
**VK_KHR_dedicated_allocation**, **VK_KHR_win32_keyed_mutex**. Timeline functionality already used
Vulkan 1.2; no new feature boolean. Empty CPU state, dormant predicates and input-FOV bookkeeping
remain. No OpenVR load/init/call, VR images/queries, warp prewarm or active VR worker before Start.
The second review independently requests VK_KHR_get_memory_requirements2 too, giving the six-name
guarantee in ADR 0157 linked at the top; FSR supplied that name in this original measurement.

## User preview

From this worktree, after `tools\build.ps1 -Config Release` (already built here):

```powershell
python tools/vr_session.py --package out/dist/gmod-rtx-remix-0.0.0-vrq.v1.gma --evidence H:/BACKUP_20260815/Modding/!NVIDIA-RTX-Remix/out/vr/q/user-look-01 --look --seconds 900
```

It locks/snapshots first, installs the local allowlisted package and launches the PoC's own exe.
Put the Index on; RTX Remix > VR > VR settings > Start VR, or `nl_vr_start`. Expect a head-tracked
path-traced view/depth stereo, left-eye desktop mirror with desktop UI, and wrist canvas when
the left controller is awake/in view. Page Exit VR or `nl_vr_exit` returns flat. Finish with
**`nl_vr_demo_done`** in the game console: it waits for off, restores shared settings, quits and
verifies rollback. The 900 s timeout does the same. Use a fresh evidence name each time. V1 has
no rendered hands/controller movement/grabbing/weapons/VR menus. After a failed preparation and
after that PoC process has exited:

```powershell
python tools/vr_session.py --evidence H:/BACKUP_20260815/Modding/!NVIDIA-RTX-Remix/out/vr/q/user-look-01 --rollback
```

Direct PoC launches while SteamVR runs succeed without a library interstitial and preserve the
original SteamVR processes. Logs mark AppID 4000 as VR only at module Start. A's 04:02 library
launches waited at ShowInterstitials; vrmonitor requested quit-all, then launch continued after
SteamVR exited. Logs preserve no button labels/initiating UI action. Use the tested direct driver;
cancel a library dialog proposing to exit SteamVR. No unverified button or automatic 13-minute
shutdown is asserted. Steam settings/launch options/registry were never changed.

## Text for Claude's shared documents and decisions

**CHANGELOG:** Opt-in V1 Index output: headset-density centre/depth stereo, synchronized Submit,
left-eye mirror, wrist overlay, translated page, reversible fixed preset, capture/timing and
rollback-verifying driver/package part. Keep on VR branches pending review/approval; disclose limits.

**COMPONENTS:** vr/native (session/worker/input/poses/timeline/shared ABI/probe), vr/addon (late
view/hiding/wrist), vr/input (four SDK-readable JSON), packages/vr, third_party/openvr,
tools/vr_session.py/.lua and tests. Runtime owns images/preset; module owns SDK; add-on owns game
view; companion owns activation. CI generic collectors take the recorded VR module and pinned SDK.

**ROADMAP:** Q integration/package/Index evidence complete after the final gate, pending independent
Claude review and user approval before merge. No V2-V7 work. V6 owns adaptation and hand-over tuning.

**RESEARCH:** Add S1-S8 tables, five-name delta, actual size/90 Hz/identity eye rotations, SDK-ready
producer/fresh-pose gate/parked ticket/stable extent, public queue negative, work/gap/SDK separation,
4095-byte Source console limit, file-only GetConfigVariable, image/pose/overlay/rollback evidence.
Keep A/C/D/E raw receipts and measurement limits linked.

**TESTING:** vr_session.py takes both locks for real SDK runs, records source/probe hashes, scripted
or actual poses, native/cumulative stats, PNG/timing JSON/SteamVR tails, restores shared settings
before quit and requires clean depot rollback. Flat parity uses three alternating pairs, identical
clear/noon fixture and no SDK. User preview/completion commands above are repeatable. No settings change.

**packages/README.md row:** `vr` | gmcl_nlvr_win64.dll and pinned openvr_api.dll; add-on from vr/addon,
real JSON from vr/input to nlvr/input | repository nl_vr_client and Valve v2.15.6 at its recorded
commit | MIT plus OpenVR BSD-3-Clause; SDK native dependency loads only at Start.

New decision-record proposals (Claude assigns numbers; accepted decisions are not rewritten):

1. **Runtime VR / warp:** one enlarged symmetric centre at headset density, full eye transforms,
   primary-depth gather, 0.5 m policy, observed-background fill, left mirror. Hidden surfaces and
   eye-dependent lighting remain approximations; true stereo V7.
2. **Ownership/poses/pacing:** module alone loads/initializes SDK. SDK-ready installs producer;
   fresh camera starts output. Camera ring owns queued poses, completion counters serialize epochs;
   sleeping releases locks, absent-scene ticket parks. Lua Stop asynchronous, runtime Stop is the
   no-more-SDK-call barrier, off acknowledges release; module unload joins unfinished initialization.
3. **Overlays/game view:** unique exact-size raster canvases feed Vulkan overlays outside tracing;
   post-centre 2D remains desktop. Own CalcView and ordinary 3D/proxy suppression only, restoring
   registrations/flags. Keep the single cached Source canvas bounded.
4. **Prerequisites/off:** enable five supported names at device creation without SDK or VR resources;
   validate complete SDK lists at Start/name missing extensions. Record flat timing/startup limits.
5. **Preset:** scale 1, DLSS Performance/RR/1-4 bounces in a highest-priority fileless session layer;
   FG, blur/aberration/vignette/free camera/shake off, restore on Exit without user.conf writes.
   Warning cap 0.5; no automatic adaptation claim.

## Open and cleanup

- Q live cold SteamVR start is unmeasured: it was already running and rules forbid stopping it.
  A's scene VR_Init started SteamVR; 1000 ms held-init tests exercise the production async path,
  not live cold-start game frame times. Every Q run leaves SteamVR running.
- 80 Hz is derived at unchanged size, not measured. Modern House misses 45 FPS at scale 1; V6
  scheduling/adaptation remains. Phase-1 edge/disocclusion/view-dependent lighting, worn comfort/
  controller placement, other headsets/aspects/hardware and fatal device recreation remain open.
- Independent review, shared-document/ADR integration and user milestone approval remain.
- Per-run verified snapshot/generated bulk copies are removed; logs/numbers/PNGs remain.
  **Automatic approval review rejected deleting old development package/runtime copies with
  "blocked by policy".** No workaround was attempted. They remain in this worktree's
  `out/vr/development/`; receipt: `development-cleanup-refused.json`.
