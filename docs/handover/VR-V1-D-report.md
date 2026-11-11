# VR V1 D: native OpenVR module

Task: [VR-V1-D-module.md](VR-V1-D-module.md). Binding interfaces and test rules:
[VR-V1-plan.md](VR-V1-plan.md); binding design decisions: [VR-plan.md](VR-plan.md).
The initial delivery was accepted at `f52d0e5` and merged by Claude into `vr` (`4605fd4`). The
review follow-up below fast-forwarded that integration into `vr-d`, as the user requested.
No push, merge into `vr`/`main`, tag, Workshop upload, loader change or package import was made here.

## Review follow-up (after f52d0e5)

All five requested fixes, plus build integration, are implemented on `vr-d`. The camera/pose ring
and version 1 C header remain unchanged. Original Index/S4 receipts below belong to the accepted
delivery; this follow-up's receipts are in the **main checkout's `out/vr/d/review/`**.

0. **Integration:** fast-forwarded `vr` (`4605fd4`), retained root `add_subdirectory(vr/native)`
   and the module's `add_subdirectory(probe)`. Deleted the old configure hook, cleared
   `CMAKE_PROJECT_native_loader_INCLUDE`, and linked `nl_vr_probe_data` for shared SteamVR discovery.
   No duplicate paths-file/process-list implementation remains in Session.
1. **Responsive calls:** all Session API acquisition uses try-locks. Busy getters return empty/nil;
   busy mutators reject immediately. The regression holds fake VR_Init for **1000 ms**, calls all
   Lua-facing Session entries before and after Stop, and times each. The maximum including the
   explicit filesystem/process Probe was **13.5252 ms**; the maximum State/Info/Events poll was
   **0.0025 ms** and Stop/StopAgain **0.0008 ms**, listed individually in `native-benchmark.log`.
   This is native entry-point timing, without Lua table
   construction; the thin Lua wrappers call these same methods. Version is a constant return.
2. **Exit during startup:** Stop posts cancellation and returns, leaving `stopping` until the
   worker can unwind. It does not join VR_Init. The worker checks cancellation before initialising
   OpenVR and before starting the renderer, and owns ordered teardown. Start refuses while startup
   or cleanup is pending. The worker sleeps on a condition variable while active; cancellation
   changes its predicate under the same mutex as the wait, preventing a lost wakeup during the
   transition from init to idle. That mutex never spans OpenVR/renderer calls. `off` means the
   runtime Stop barrier, overlay destruction, OpenVR shutdown and DLL release have completed.
   The held-init test observes stopping, rejects immediate restart, releases the init, verifies
   cleanup, then restarts successfully. Explicit DLL/module destruction still joins: unloading
   code/session storage under an unfinished VR_Init would be unsafe, and OpenVR offers no init
   cancellation function. This limitation applies to module unload, not the Exit VR Lua call.
3. **Queued-frame pacing:** after each successful WaitGetPoses the module samples framesRendered.
   Only successful SetFrameCamera arms its completion fence. Before another WaitGetPoses, the
   module requires that count to advance, which VR-C publishes after Submit/handoff. A **25 ms**
   budget covers the **40–45 fps** target frame interval and bounds a stalled-renderer call. The
   initial 8 ms candidate was replaced to allow a full target frame. A **0.25 ms high-resolution
   waitable-timer poll** parks the thread; no spin or timeBeginPeriod/system timer change. If timer
   creation fails it falls back to Sleep(1), reported by completion_wait_high_resolution=false.
   A timeout returns nil, keeps the fence, counts the timeout, and makes **no WaitGetPoses call**.
   OS scheduling can extend the nominal budget. The test measured **3** stalled timeouts with
   **25.1590 ms** last wait and **25.3077 ms** maximum, then resumed after completion.
   Fast, 3 ms delayed, and stalled/released fake renderers all recorded exactly **WSWS**, with
   **0** premature pose acquisitions. With no SetFrameCamera, repeated BeginFrame calls do not wait.
   Info exposes completion_wait_ms, completion_wait_max_ms, completion_wait_timeouts,
   completion_wait_count, completion_wait_polls and completion_wait_high_resolution. Successful
   frame tables add completion_wait_ms; wait_ms remains the time inside WaitGetPoses.
4. **Manifest location:** default is the module-relative
   `../../addons/nlvr/input/nlvr_actions.json`, lexically normalised; default OpenVR remains beside
   the module. The explicit manifest override remains. A generated game-folder fixture, including
   spaces, verifies the exact path passed to OpenVR. VR-Q deploys vr/input into the add-on folder.
5. **First frame:** BeginFrame still returns nil until the renderer reports RUNNING. In a fresh
   scene session I expect the first valid left/right Submit pair to return **None (0)** even before
   the first WaitGetPoses: there is no previously submitted eye in that session to duplicate.
   This is an **inference**, not a tested SteamVR startup guarantee. The pinned SDK documents
   AlreadySubmitted for submitting an eye twice before another WaitGetPoses, but does not specify
   a separate "WaitGetPoses never called" return code; normal examples wait before rendering.
   See [the pinned compositor declaration](https://github.com/ValveSoftware/openvr/blob/0924064316de3effbcd1acf1e309182a2deb1c05/headers/openvr.h#L3683).
   VR-Q must test the actual module/runtime sequence and inspect first Submit errors; if priming is
   required, it belongs before rtxvr_Start on the worker, with a regression for first-frame ordering.
   No priming call or shared-header change was silently added. After rtxvr_Start returns, the module
   allows **10000 ms** for renderer STARTING. State/Info/BeginFrame polling then reports failed with
   `RTX VR output did not render its first frame within 10000 ms; Exit VR and try again after the game has finished loading`
   and requests worker cleanup. At the page's 0.1 s poll interval that is about **10.1 s** visibility.
   A **50 ms** injected deadline verifies the message, nil frames, no pose acquisition and cleanup.

Pacing was measured with the fake runtime because the exclusive PoC lock was held by **VR-V1-C
parity**, PID **55180**, at **2026-11-10 15:46:43 UTC** (`lock-availability.json`). No game/VR
session or setting was disturbed for these measurements. Each row below uses **300 frames**;
the completion-to-pose figure includes the poll's wakeup, fake pose/input work and sampling overhead:

| Fake render delay | Mean / max completion wait ms | Mean / max completion-to-pose ms | Main-thread CPU / wall ms | Timeouts |
|---|---:|---:|---:|---:|
| 0 ms | 0 / 0 | 0.004101 / 0.021300 | 0 / 1.2677 | 0 |
| 1 ms | 1.938729 / 2.650900 | 0.473008 / 1.045700 | 62.5 / 616.0384 | 0 |
| 3 ms | 3.660436 / 4.407500 | 0.453527 / 1.186400 | 31.25 / 1132.6954 | 0 |

The high-resolution timer was available in every row. CPU time is for the **whole main-thread
benchmark loop**, including fake render-thread creation and all input/pose work, not just the wait;
GetThreadTimes here has **15.625 ms** accounting granularity, so the fast row's zero is below its
resolution. These are not real Index/runtime rendering results. The measured added completion
latency is about **0.45–0.47 ms** for delayed fake rendering, with a worst observed **1.19 ms**.

A runtime event would remove polling/quantisation. A future API could add
`int rtxvr_WaitFrameRendered(uint64_t afterFramesRendered, uint32_t timeoutMicroseconds)` returning
OK only after the count advances, plus timeout/stopped outcomes. It must wait on a runtime-owned
completion event, signal cancellation from Stop, recheck the counter to avoid lost wakeups, and
promise bounded blocking (an explicit exception to version 1's quick-call rule). This function
is **proposed only**; the shared rtxvr_api.h is byte-for-byte unchanged. VR-Q's real measurements
should decide whether the additional API/lifetime complexity is justified.

Review tests add five cases to the original nine: held-init responsiveness/cancellation, WSWS
order, loading/no-camera and startup deadline, the add-on path, and pacing measurements. All
**14 native cases** pass. Final `tools/test.ps1 -Config Release` passes with **34 CTest entries**
(including the merged probe), **0 failures**, **29 + 26 + 788 = 843 tool Python tests**, and
**5 existing skips**. The native input entry also runs its three consistency tests.

Final review module: **438272 bytes**, SHA-256
`53168b83dcb1f0c04504a9dd64a8775fb189c0e414e31d27044faba46afe4426`, built from `eea630f`
(the following report-only commit does not change it). It still imports only **KERNEL32.dll**.
The shared header remains LF SHA-256
`645ac84ac0cd35b1731c444a7e20402b9db23e79102bdd0b742142cd4a206872` and is unchanged from the merge.

Review receipts under `out/vr/d/review/`: `gate-release.log`, `ctest-release.log`,
`native-benchmark.log`, `measurements.json`, `lock-availability.json`, `build.json`, and
`module-imports.txt`. `build.json` confirms the removed hook/cache entry and binary identity.
The separate benchmark receipt predates only the cancellation wakeup-mutex correction; pacing
code is identical. The final CTest receipt includes the corrected worker and all 14 cases.

For shared docs at integration: record the async Stop/stopping acknowledgement and module-unload
join limitation; bounded, camera-armed completion fencing and its diagnostics; the 10-second
renderer-first-frame deadline; shared Probe discovery; and the add-on input folder. The proposed
runtime completion-wait API is not implemented. VR-Q still owns the real first-Submit/startup
sequence and queued-frame measurements with VR-C's runtime; the existing S4/ring decision stands.

## What was built

[vr/native](../../vr/native/README.md) builds the MIT C++20 client module
`gmcl_nlvr_win64.dll`, a static session/pose/timeline library, offline OpenVR/runtime stand-ins,
CTest checks, and an explicit real-hardware session host. [vr/input](../../vr/input/README.md)
supplies the action manifest and original Index, Touch and Vive bindings. No reference mod code,
comments or data tables were copied. The pinned Valve SDK remains unchanged.

`require("nlvr")` publishes/returns the client-owned table and creates no thread, timer or OpenVR
load. Only `Probe` reads SteamVR's bounded paths file and process list. Start runs DLL loading,
OpenVR scene initialisation, SDK/interface negotiation, input setup, eye data and the renderer
request on a worker. The page stays responsive while SteamVR starts. Stop posts cancellation;
the worker stops the runtime as a barrier, destroys owned overlays, shuts OpenVR down and frees
the DLLs, then reports off. Only module destruction must join the worker.
Repeated Stop, failed start, cancellation during initialisation and restart are covered offline.

The production module loads OpenVR only from its own folder, using a full path and restricted DLL
search. The renderer comes from the already-loaded `d3d9.dll`. Native test hosts can select a
stand-in renderer; that override is not exposed to Lua. Missing runtime exports are reported
before OpenVR is initialised. Runtime error text, including missing extension names, reaches State.

Each successful BeginFrame performs one WaitGetPoses, converts poses/velocities into Source tracking axes,
updates input and events, and keeps the last 16 raw head poses by rising sequence. SetFrameCamera
pushes the selected pose with the game's camera through the unchanged version 1 ABI. There is
no engine call-queue dependency in the production module. Timeline poses carry
`RTXVR_POSE_SCRIPTED`; positions interpolate, rotations take the shortest slerp arc, and terminal
poses hold with zero velocity. Button/axis snapshots are type-checked against the input metadata.

Overlays are owned, bounded to 32, and reject foreign handles. A scripted hand/head attachment
becomes an absolute transform from the script; live hands use their tracked-device role, retrying
when a sleeping controller appears. Lua receives decimal **string** overlay handles: OpenVR's
uint64 values can exceed the exact range of Lua numbers. Keep these opaque in the add-on.

## Lua API as built

The [native README](../../vr/native/README.md) documents every function, field, unit, error and the
complete timeline format. Version 1 implements Version, Probe, Start, State, Stop, BeginFrame,
SetFrameCamera, Info, Actions, Haptic, OverlayCreate/Source/Attach/Show/Alpha/Destroy, Events,
Capture and TestState. Additional read-only OverlayVisible exposes SteamVR's flag for testing.

Start options are scale, render_scale, timeline, no_submit; test-only full-path overrides are
openvr_dll and manifest. Ordinary failures return `nil, detail`; Start returns `false, detail`.
Mutators return true. Haptic returns success plus the actual OpenVR input error code, and does
not throw merely because a controller is unavailable. No C++ exception crosses the Lua boundary.

Info returns every runtime status field, raw SDK timing/cumulative fields and the convenience
fields already expected by VR-E: devices.left/right, presents, dropped, reprojected,
compositor_gpu_ms and compositor_cpu_ms. Controller booleans describe the last acquired frame;
compositor times are absent when timing is invalid. Poses use metres, Source angles in degrees,
linear velocity in metres/s and angular velocity as a Source-basis vector in radians/s.

## Interface and build integration

[include/rtxvr_api.h](../../vr/native/include/rtxvr_api.h) copies the plan's C block literally,
with MIT identification, standard integer/wchar includes and an extern-C wrapper. No declaration,
flag, field, comment within that block, or ABI version changed. VR-C should copy this file, and
VR-Q must compare the two files byte-for-byte. C and C++ compilation assert x64 sizes:
Matrix34 **48**, Eye **64**, StartInfo **168**, FramePose **88**, Status **384** bytes.
The LF-normalised header SHA-256 is
`645ac84ac0cd35b1731c444a7e20402b9db23e79102bdd0b742142cd4a206872`;
`api-contract.json` records the exact plan-block comparison and sizes.

The integrated root now includes `add_subdirectory(vr/native)`, and the module's CMake includes
VR-A's probe. The original worktree-only configure hook was removed, and
`CMAKE_PROJECT_native_loader_INCLUDE` was cleared from the build cache. Normal build.ps1/test.ps1
now build the module and probe without a hook, including in a clean checkout. Probe reuses
VR-A's `nl_vr_probe_data` discovery helper instead of duplicating SteamVR filesystem/process checks.

## S4: frame ownership

**Settled: keep the binding version 1 nearest-camera ring.** The current x64 client can reach
the render context and its raw queue, but that queue does **not** implement the public SDK's
virtual ICallQueue interface. No call-queue transport was added. The experiment is isolated in
[spike_s4](../../vr/native/spike_s4/README.md), never shipped.

The live RTX PoC already used **mat_queue_mode 2**; no cvar change or second session was needed.
Across **120 frames**, the probe bracketed draws into a **333 x 197** raster target with three
requested markers per frame: **360 attempts, 0 accepted, 0 callbacks**. The ABI guard rejected
the arena head rather than dereferencing it as a vtable. Main-thread ID was **25948**; a callback's
render-thread ID and execution order are explicitly **unmeasured**, because none could be queued.

| Interface observation | Current x64 result |
|---|---|
| VMaterialSystem080 GetRenderContext | Windows slot **102**, method RVA **0x1dd40**, material-system vtable **0xb78c8** |
| Live render context | CMatQueuedRenderContext, vtable RVA **0xb70a0**, including PostRender and while the target is pushed |
| GetCallQueue | Windows slot **145**, RVA **0x1d6b0**, queue at context + **688** bytes (**0x2b0**) |
| Queue first word | **0** initially; **queue + 56** during rendering, an arena pointer with no module vtable |
| Hardware-context alternative (static) | Vtable **0xbc070**; GetCallQueue implementation at **0xe940** returns null |

These offsets apply only to PoC `bin/win64/materialsystem.dll`, SHA-256
`6c9075c5384a1f9b99921928151a1d17b69faa81f1534e8f7c633a30fdb3e1ad`.
The ASLR queue pointer was **140727349356968**, with first word **140727349357024** during rendering;
do not reuse those process addresses. The public SDK pin is
[ValveSoftware/source-sdk-2013 e1f1fd42271805072f052051c26c21caa2c87b04](https://github.com/ValveSoftware/source-sdk-2013/tree/e1f1fd42271805072f052051c26c21caa2c87b04).
Its [material interfaces](https://github.com/ValveSoftware/source-sdk-2013/blob/e1f1fd42271805072f052051c26c21caa2c87b04/src/public/materialsystem/imaterialsystem.h)
and [callqueue.h](https://github.com/ValveSoftware/source-sdk-2013/blob/e1f1fd42271805072f052051c26c21caa2c87b04/src/public/tier1/callqueue.h)
establish the public virtual dispatch being tested. Windows counting excludes Xbox-only methods.

Evidence under `out/vr/d/s4/`: `poc/queue-default/console.log`, `static.json`,
`sdk-provenance.json`, `summary.json`, `findings-final.md`, the **28-record**
`rea-materialsystem.json` and the closed Ghidra **12.1.4** snapshot `materialsystem.analysis.json`.
The REA getter/queue/constructor observations are respectively
`ev_9f0ed639c2fc8db406be37a51d89349b6943653a3b267b99310813c977d47cad`,
`ev_bb7ee42173ddfbcf82a6abe8d33e8f55796d2ae2f16329494b87a0979526dfba`, and
`ev_eb70fe2bb86c3fc6b3ee090afce9f63e67fbf9e7ac781f0b25a1f0435bb4a471`.
Static analysis corroborates the raw arena layout; the live result is a bounded negative for the
**public SDK path on this build**, not proof that a private allocator/functor ABI is impossible.

The ring avoids an engine vtable/allocator ABI dependency. Its limitations remain visible:
identical game cameras can correspond to different tracking poses (for example after changing
the play-space origin), and another hook or the engine can alter the camera after CalcView.
The runtime should prefer the newest equally good match and expose posesMatched/posesUnmatched;
integration must exercise queue mode 2 with moving and stationary scripted views. A proven,
guarded call queue could remove the identical-camera ambiguity, but changing the transport needs
Claude's review and the shared-interface update explicitly required by the brief.

## Accepted initial delivery: validation and evidence (f52d0e5)

Evidence root is the **main checkout's**
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\d\`.
No evidence binaries or generated SDK stubs are committed. Working build and scratch stay in
this worktree's ignored out directory; large PoC snapshots are deleted only after verified rollback.

- Offline: nine C++ test cases cover dormant construction/module load, axis/angle round trips,
  timeline interpolation/derivatives/end/bad input, two cycles, missing DLLs/exports/versions,
  SteamVR/headset/interface/manifest/renderer failures, cancellation/retry, exact large overlay
  handles, events, source ownership, scripted attachments and flags, and DLL unloading.
  The fake renderer checks the Stop barrier precedes OpenVR shutdown, and a delayed renderer
  verifies BeginFrame stays nil until its state changes from starting to running. Three Python consistency
  checks validate all 20 manifest actions and all three binding files against native readers.
- The pinned real OpenVR DLL is fetched by `tools/ci/fetch_prebuilt.py --only openvr`, **837272**
  bytes, SHA-256 `bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a`.
  It stays under out; no package input was imported.
- `tools/test.ps1 -Config Release` passes: **32 CTest entries**, **0 failures**; tool Python
  groups **29 + 26 + 788 = 843 tests**, **5 existing skips**. The VR entry contains nine C++ cases
  and the additional input entry contains three Python consistency checks. Evidence: `gate-final.log`
  and `ctest-final.log`. The earlier successful 31-entry run is retained as `gate-first.log`.
- Final Release module: **414720 bytes**, SHA-256
  `42f2867f6a6f736f61c4faec4c114f561512a7a576c3ceb861ff6a9f6037673e`.
  The preceding build used for the four 15-second Index cycles and S4 Lua smoke was also
  **414720 bytes**, SHA-256 `f55ff0e0eb68efe1e86d4929351f3b55b59301a5806e47104db2791997f93a60`.
  The final build adds the renderer-readiness check in BeginFrame, with its offline regression;
  the Lua adapter, start/stop path, ABI and S4 probe are unchanged.
  `module-imports.txt` shows **KERNEL32.dll only**, with no OpenVR or VC runtime import;
  `module-exports.txt` records `gmod13_open` and `gmod13_close`.

The real unworn Index passed **four** starts and Stops: two live-pose cycles, then two scripted
cycles, each measured for 15 seconds, at the unchanged **90 Hz** setting. SteamVR recommended
**2468 x 2740 per eye**. The controllers were asleep (both live poses invalid); the head was valid
on every acquired frame. Both overlay visibility checks and both haptic calls succeeded in every
cycle (haptic input error **0**, eight calls total). SteamVR was already running and was left running.

| Run / cycle | Acquired frames | Mean / max WaitGetPoses ms | Action reads / API errors |
|---|---:|---:|---:|
| Live 1 | 1350 | 11.0463 / 12.3995 | 24300 / 0 |
| Live 2 | 1351 | 11.0488 / 11.5054 | 24318 / 0 |
| Scripted 1 | 1351 | 11.0291 / 13.2593 | 24318 / 0 |
| Scripted 2 | 1351 | 11.0313 / 11.6698 | 24318 / 0 |

The scripted cycles measured **90.0205 / 90.0082 WaitGetPoses calls/s**. Both observed grip true
and false; stick x ranged from **0 to 0.998588 / 0.999467**. Scripted hands remained valid, the
timeline ended at **6 seconds** and held its final head position `[0,0,1.6]`. The native offline
test separately verifies the scripted submission flag and absolute hand-overlay placement.
All **97254** action reads across the four cycles returned OpenVR error 0. Physical button/finger
activation and Touch/Vive hardware are not claimed from sleeping Index controllers.

Files: `index-live.jsonl`, `index-scripted.jsonl`, `host-timeline.json`, `host-summary.json`, and
`steamvr-host-server.txt`. The server records successful manifest registration. It also logs
transient unconfigured `indexhmd` input (there are no headset input actions; a generic legacy HMD
binding loads) and an old-connection warning on immediate same-PID reinitialisation. All session,
manifest, action, overlay and haptic API operations nevertheless succeed; these log messages are
retained instead of being hidden by changing SteamVR settings.

A separate read-only check against Valve's installed physical input profiles validates **16 Index,
14 Touch and 10 Vive source entries** (including skeletons/haptics): `input-profiles.json` records
the source paths and profile hashes. This caught and fixed the Touch file's physical path names:
`joystick` and left `x/y`, while keeping logical left_a/left_b actions. Those devices still need
physical activation tests; reading their installed profiles does not claim hardware coverage.

These are **module acquisition/pacing tests with a stand-in renderer**, not rendered frame-rate
measurements. No eye image was submitted. Raw cumulative presents were 1350 / 1351 / 1351 / 1350;
dropped were 0 / 0 / 1455 / 0, with reprojected 0 throughout. In particular the third run's raw
dropped counter must not be described as successful image delivery or a GPU-performance result.
VR-C/VR-Q must validate actual submissions, images, GPU timings and D3D9 target content. Other V1
PoC work and the background Open WebUI service shared the machine during the host runs.

The **final build** (with the renderer-readiness guard) then passed **two additional 8-second
scripted Index cycles**, again at **90 Hz**, **2468 x 2740**. Results: **720 / 721 frames**,
mean WaitGetPoses **11.0654 / 11.0550 ms**, maximum **18.3729 / 11.3919 ms**, and measured rates
**89.9180 / 90.0009 calls/s**. Both grip states and stick 0..**0.997766 / 0.998332** were observed;
**25938 additional action reads** had **0 errors**. Both overlays were visible and all four
sleeping-controller haptic calls returned 0. Both Stops completed. Raw presents **719 / 720**,
dropped/reprojected **0 / 0**, still with **no eye submission**. Evidence: `index-final.jsonl`
and `host-final-summary.json`, which names the final binary hash. In total the hardware tests
cover **6 start/stop cycles**, **6844 measured frames**, **123192 action reads**, **6 visible
overlay checks**, and **12 successful haptic calls**. SteamVR remains running; the test host exited.

The real GMod Lua adapter smoke ran in that same S4 RTX session using the preceding production DLL
hash `f55ff0e0...`, with **0 Lua errors**. Require succeeded, Version returned **1**, Probe found SteamVR
installed/running, initial State was **off**, and off BeginFrame returned **nil**. Start returned
true asynchronously, then failed with exact detail **`missing export: rtxvr_GetApiVersion`** from
the pre-VR runtime. Both Stops returned true, final State was off and BeginFrame was nil. The
session's module inventory contained **0 openvr_api.dll** modules. No fake runtime or OpenVR DLL
was staged in the game. See `s4/poc/queue-default/console.log`, `modules.json` and `s4/summary.json`.

The game quit normally, process exit **0**, with archived settings **restored**. Snapshot rollback
was **clean=true**: **2877 depot files verified**, **0 missing**, **0 size mismatches**, **0 hash
mismatches**, **0 restoration errors**, both staged modules removed. Original `config.cfg`,
`user.conf` and `materialsystem.dll` hashes match before/after (`s4/hashes-before.json` and
`hashes-after.json`). The snapshot copies were deleted only after these checks; both owned locks
were released. Normal gameplay changed eight existing watched data files and one settings file,
which the standard snapshot tool reports without copying/restoring their contents; no watched
files were added or missing. This is not a claim that every game-generated data byte was restored.

## Open integration work

VR-Q owns CI/repository-build provenance, the one binary import, action/binding
deployment under `garrysmod/addons/nlvr/input/`, and the package part. Root CMake wiring is integrated.
VR-C owns the matching header, renderer output,
the camera ring matcher, texture-source copying and capture. VR-E should preserve string handles
and use the documented Info fields. Neither the module nor this report claims S1/S2/S3/S5/S6/S7/S8
for other tasks. No binding design decision required changing and no loader change was needed.

Claude's independent review and milestone approval remain integration work; no milestone merge is
authorised here. Touch and Vive bindings have offline validation only unless hardware is supplied.

## Proposed additive shared-document text

- CHANGELOG / COMPONENTS: add the dormant MIT OpenVR client module, version 1 renderer bridge,
  original SteamVR Input defaults, timeline-driven test input and overlay ownership. State that
  runtime and packaging integration are separate V1 tasks; loading the module starts nothing.
- ROADMAP: VR-V1-D module implemented and tested on vr-d, held for Claude review and VR-Q integration;
  V1 as a whole is not complete from this task alone.
- TESTING: nl_vr_tests uses isolated DLL stand-ins and no real SteamVR; nl_vr_input cross-checks
  declarations/readers/bindings. The explicit session host exclusively creates the shared VR lock,
  starts/stops twice, reports actual poses, pacing, input errors, haptics and overlay visibility,
  and leaves SteamVR running. S4's separate guarded PoC probe uses both shared locks and rollback.
- Decision record: keep the version 1 pose ring for D; no engine ABI use in production, no permanent
  queue-mode change, no pre-Start OpenVR load. Overlay handles are opaque decimal strings in Lua
  to preserve all 64 bits. Native test renderers are selectable only by the explicit C++ host.
- RESEARCH: add the measured SDK/ABI facts and the S4/hardware numbers below, with their evidence;
  distinguish the real Index's OpenVR behaviour from the stand-in renderer's absence of submissions.
