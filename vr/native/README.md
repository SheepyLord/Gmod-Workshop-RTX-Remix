# Native VR client module (V1 and V2-N)

V2-N adds launcher-only simulated sessions, keyboard input/events, the binding UI, finger splay,
overlay tint/sort order and an optional game-window source. Live tracking still uses V1's
render-side pacing, native quit worker and deferred IPD reads. The shared wire header is unchanged.

## Simulated sessions for feature tests

The launcher must set absolute `NLVR_TEST_ROOT` and copy [sim/index-v1.json](sim/index-v1.json) to
`NLVR_TEST_ROOT/simulated-index.json`, and a timeline to `NLVR_TEST_ROOT/timelines/NAME.json`.
Then Lua may call `nlvr.Start{simulate=true,timeline="NAME"}`. Without that environment root,
or without a timeline, Start refuses before loading the renderer. Lua cannot select another
device file, root, DLL or manifest. Existing named-data/link checks remain in force (ADR 0150).

Simulation loads no OpenVR DLL and initialises no SteamVR scene. A high-resolution waitable
timer paces frames at the recorded refresh (ordinary timer fallback if unavailable). It starts
the runtime with NO_SUBMIT, no render-side pacing flag and a null getGenericInterface. Info says
simulated=true, sdk_ready=false, openvr_loaded=false and reports simulation_high_resolution.
Compositor timing is unavailable; rendered progress is not eye submission. Task R's runtime
accepts this combination; an older runtime can refuse with its exact native error.

Simulated overlay handles increase across restarts. OverlayInfo reports their visibility, absolute
OpenVR-basis transform, requested texture size, alpha, color, sort_order and window source flag.
The runtime still owns/copies/captures their pixels; local registration is not a GPU-copy assertion.
Hands/head attach to scripted poses. Haptic and binding-UI calls succeed without platform work,
with request counts in Info. Keyboard state is retained locally. All overlays/timers go at off.

## V2 APIs and timeline example

Task M follow-up, 2026-11-11: `WindowInput(kind,...)` is an additional client API. It refuses while
VR is off/starting/stopping/failed, and before the first acquired frame. It discovers the unique
top-level `Valve001` window in **this process**, rechecks class/process ownership before every post,
and never accepts a window handle from Lua. Missing/ambiguous/recycled/foreign windows are refused.
Only `PostMessageW` is used: no SendInput, hooks, focus activation, cursor warp or executable access.

- `WindowInput("cursor",x,y)`: integer client pixels within the current client dimensions (1..32767).
- `WindowInput("button","left"|"right"|"middle",down)`: boolean down/up, tracked and balanced.
- `WindowInput("wheel",steps)`: nonzero integer -8..8; posts WHEEL_DELTA units with screen coordinates.
- `WindowInput("char",scalar)`: printable Unicode scalar; posts one UTF-16 WM_CHAR or a surrogate pair.
- `WindowInput("key",name,down)`: enter/backspace/delete/escape/tab/left/right/up/down/home/end only.
- `WindowInput("release")`: releases this dispatcher's held buttons/keys, never another input owner's.

At most **64 messages per BeginFrame sequence**; surrogate pairs reserve both slots. Duplicated downs
and unmatched ups do not post. Errors release held input; Exit, renderer failure and unload do too.
At most fourteen safety releases bypass the normal budget. Failed release posts retain their held bits
for retry/cleanup; an unavailable/destroyed target is cleared rather than sending to a different window.
`Info().window_input` reports ownership/foreground, dimensions, last client pixels, held count, posted
count, failures and normal frame-message count, never a handle. Posting success is delivery to Windows'
queue, not proof that the engine/HTML consumed it. PoC foreground/acceptance evidence is in M's report.

- `ShowKeyboard(text, description, multiline, maxchars)` opens SteamVR's modal keyboard (or local
  simulated state). Existing text may be empty, description is at most 512 UTF-8 bytes, text is
  at most 16384 bytes and maxchars is 1..4096. `HideKeyboard()` hides only a keyboard this session
  opened. Stop hides it before SDK shutdown. Events gives `{type="keyboard_done",text=...}` and
  `{type="keyboard_closed"}`. Duplicate SDK done/closed variants are suppressed; other overlays'
  keyboard events are ignored. No clipboard, filesystem path or global settings API is exposed.
- `OpenBindingUI()` opens this application's main action set on the desktop. It returns true,
  or false and an input-error message. It supplies controller source handles, then the valid
  `/user/head` source if sleeping controllers return InvalidDevice (a zero device handle is
  rejected by SteamVR). Players still own their bindings; it changes no mapping.
- `OverlaySortOrder(handle,n)` takes uint32 order. `OverlayColor(handle,r,g,b)` takes 0..1 RGB.
  Both require an owned handle, just like the existing overlay APIs.
- `OverlayWindow(handle,enable)` selects the game's final 2D window picture with SHOW|NO_MIRROR,
  or flags zero to remove it. It returns false plus a clear message when the loaded runtime has
  no rtxvr_SetOverlayWindow export, and false plus its error when refused. Start still works with
  older runtimes. Info.overlay_window_supported reports availability. The declaration is private
  until task R's shared header is integrated; API version 3 was not altered here.
- `Actions().left_skeleton` and right_skeleton now include splay={4} beside curls={5}. Both use
  SteamVR's normalised 0..1 values: closed/curled and adjacent-finger separation respectively.

This is a complete named timeline a feature task can copy (Source tracking axes, metres/degrees):

```json
{"version":1,"events":[
 {"time":2,"type":"keyboard_done","text":"a scripted label"},
 {"time":2.1,"type":"keyboard_closed"}
],"steps":[
 {"time":0,"hmd":{"pos":[0,0,1.6],"ang":[0,0,0]},
  "left":{"pos":[0.25,0.25,1.2],"ang":[0,0,0]},
  "right":{"pos":[0.25,-0.25,1.2],"ang":[0,0,0]},
  "actions":{"left_grip":false,"left_grip_force":0,"right_trigger_value":0,
   "left_stick":[0,0],"left_skeleton":{"curls":[0,0,0,0,0],"splay":[0,0,0,0]}}},
 {"time":3,"hmd":{"pos":[0.2,0,1.6],"ang":[0,20,0]},
  "left":{"pos":[0.45,0.25,1.2],"ang":[0,0,0]},
  "right":{"pos":[0.45,-0.25,1.2],"ang":[0,0,0]},
  "actions":{"left_grip":true,"left_grip_force":1,"right_trigger_value":1,
   "left_stick":[1,0],"left_skeleton":{"curls":[1,1,1,1,1],"splay":[1,1,1,1]}}}
]}
```

The twenty manifest actions remain unchanged: skeleton summaries provide splay, so no new binding
is necessary. Buttons are held until the next step; scalar/stick axes, curls and splay interpolate
between matching actions. A skeleton may also be a five-number curls-only array with neutral splay.
Unspecified actions are neutral for that step. The final step holds. Events are ordered by nondecreasing
wall time from successful startup, emitted once by the 20 ms native worker even without BeginFrame.
A scripted keyboard_closed also hides this session's real keyboard. A script does not open a real
keyboard or binding editor itself: the feature's ShowKeyboard/OpenBindingUI calls do that. quit_at
keeps its V1 native-stop behavior. Events allow only keyboard_done/closed, with at most 16384 UTF-8
text bytes each and 10000 entries within the existing 1 MiB document/parser limits.

The second review moves IPD eye reads out of the event worker and into the next BeginFrame,
under that call's existing lock. The worker only publishes a dirty flag, so it cannot contend
with SetFrameCamera while adjusting IPD. Wire API 3 adds focusLossIntervals and waitFailures;
the page and module require this version together. Native mismatch messages use the actual
compiled version. Tests prove an IPD event causes no worker-side eye reads before the next pose.

Current review boundary: **any client script can call these functions**, including server-supplied
client Lua. The page's host check is not an authorization boundary. Start refuses Lua openvr_dll,
runtime_dll and manifest keys. Executable code and the manifest are found relative to this module;
only native test hosts may override their paths. Probe returns SDK presence, not an absolute path.

Timeline/Capture use a name (1-64 ASCII letters/digits/_/-), not a path. Default storage is
garrysmod/data/nlvr/timelines/NAME.json and garrysmod/data/nlvr/captures/NAME/. Reserved Windows
names and links are refused. A launching process may set absolute NLVR_TEST_ROOT for automation;
Lua cannot select that root. The driver uses an out/ root and collects the captures afterwards.
Lua can control its local VR session/input/haptics/owned overlays and those data images, but
cannot select executable code or access arbitrary filesystem locations through this API.
lua_policy.h implements this boundary.

The C wire ABI is version 3: 112-byte FramePose, 456-byte Status. The Lua Version() stays 1.
V1 uses only render-side Submit/WaitGetPoses and nonblocking predicted tracking. The module
contains no WaitGetPoses call, completion ticket or serial wait; only simulated sessions use a frame timer. Start pacing="serial"
is refused; retained comparison packages/commits reproduce the serial control. Prediction uses measured
compositor scheduling feedback, reporting pipeline intervals, display-age estimate and timing
prediction error. It is not a physical panel-latency measurement. Native event polling runs every
20 ms independently of Lua: quit is acknowledged and ends the session, retaining its reason.
An optional timeline quit_at wall-time supports a safe synthetic quit test. Invalid head tracking
omits the submitted pose; sleeping/disconnected hands keep overlays hidden until placed.

This folder also holds the standalone [probe](probe/README.md) (`vrprobe.exe`, VR V1 A): a development tool for
the spikes that never enters the package. The root `CMakeLists.txt` adds this folder; this folder's adds `probe`.

MIT C++20 implementation of `gmcl_nlvr_win64.dll`. It owns the OpenVR session; the Remix runtime
owns images. The pinned OpenVR header is a SYSTEM include. No OpenVR import library is linked.
Loading the module allocates its Lua table and session object only: no thread, timer, OpenVR DLL,
registry query or filesystem scan. Only an explicit `Probe` inspects SteamVR's paths and processes.

## Build

The root CMake build includes this directory and VR-A's probe. Use the normal commands:

```powershell
tools/build.ps1 -Config Release
tools/test.ps1 -Config Release
```

Output: `out/build/win64-release/vr/native/gmcl_nlvr_win64.dll` and PDB. Deploy the pinned
`openvr_api.dll` beside the module in `garrysmod/lua/bin`. Deploy `vr/input/nlvr_actions.json`
and its three binding files to **`garrysmod/addons/nlvr/input/`**; the module derives that path
from its own folder (`../../addons/nlvr/input`), independent of the game's working directory.
The package format permits these DLLs in `garrysmod/lua/bin`. Native hosts alone can override manifest discovery for tests. VR-Q packages these inputs; D imports no binaries.

## Sources

| File | Purpose |
|---|---|
| `include/rtxvr_api.h` | Version 3 runtime C ABI, including render pacing and measured prediction telemetry |
| `lua_policy.h` | Removed-option rejection, fixed data root and safe logical names for Lua |
| `pose_math.h`, `pose_math.cpp` | OpenVR to Source basis conversion, transforms, Source angles and slerp |
| `timeline.h`, `timeline.cpp` | Bounded JSON timeline parsing, sampling and derivatives |
| `sim_device.h`, `sim_device.cpp` | Launcher-root recorded-device parser and validation |
| `input_actions.h` | Shared button/axis metadata for input reads and strict script validation |
| `session.h`, `session.cpp` | Worker start, ordered stop, DLL exports, poses, input, overlays, events and facts |
| `window_input.h`, `window_input.cpp` | Bounded owned-game-window message dispatcher and injectable Win32 boundary |
| `module.cpp` | Thin client-realm Lua adapter, validated arguments and exact overlay handles |
| `tests/make_stubs.py` | Generates concrete inert SDK interface bases in the build tree |
| `tests/fake_control.h` | Offline test fault/counter ABI |
| `tests/fake_openvr.cpp` | Stand-in `openvr_api.dll`, never the user's SteamVR |
| `tests/fake_runtime.cpp`, `tests/fake_runtime.def` | Stand-in runtime exports and failure injection |
| `tests/missing_runtime.cpp` | A renderer with no VR exports |
| `tests/test_vr.cpp` | Offline CTest coverage of lifecycle, maths, timeline, overlays and failures |
| `tests/test_v2.cpp` | Simulated sessions, pacing, extended input/events, keyboard, binding UI and optional window-source tests |
| `tests/test_window_input.cpp` | Stand-in window calls, message fields, Unicode, bounds/budget, failures, releases and Session lifecycle |
| `tests/api_layout.c` | Compiles the current header as C and asserts the Windows x64 ABI layout (API 4: `rtxvr_Quality` 24 bytes, `rtxvr_Status` 488) |
| `tests/check_input.py` | Cross-checks bindings, action types and native readers offline |
| `tests/session_host.cpp` | Explicit real Index host, two start/stop cycles, inputs and overlay visibility |

The offline event test collects delivery for up to five seconds, retaining exact count, order
and drain checks; it does not assume the worker runs within a fixed 30 ms sleep. The stand-in
SDK's injected event queue is mutex-protected between the test and native worker threads.
These test files are not inputs to the packaged module.

The optional [S4 spike](spike_s4/README.md) is a separate guarded PoC experiment, not production
code. Its engine ABI observations do not change the version 1 camera ring contract.

## Lua API

`require("nlvr")` leaves global `nlvr` and returns that table. Version 1 follows the work plan.
All operations except `Version` belong to the Lua realm that loaded the module. Errors return
`nil, message`; `Start` returns `false, message`. Mutators return true on success. No C++ exception
crosses the Lua ABI. Close stops and joins the session before unloading the module.

- `Version()` -> 1. `Probe()` -> `{runtime_api?, openvr_dll?, steamvr_installed, steamvr_running}`.
  Probe uses the loaded renderer's exports, `%LOCALAPPDATA%/openvr/openvrpaths.vrpath` (bounded to
  1 MiB), runtime directories and the process list through VR-A's shared
  `nl_vr_probe_data` discovery helper; no registry and no OpenVR load.
- `Start(options?)` -> true when a worker was started. Fields: `scale` (units/metre, default
  39.37007874, range 1-1000), render_scale (default 1, .1-2), timeline (data name),
  no_submit (default false), and pacing="render" only. A missing renderer fails before
  SDK initialization. Lua path overrides are refused; native hosts use native Options.
- `State()` -> state, detail: `off`, `starting`, `running`, `stopping`, `failed`. `starting` covers
  SteamVR launch and the runtime's own first-frame transition. `Stop()` is safe at any time,
  including during start or after a failure. It **requests** cancellation and returns immediately;
  `stopping` lasts until the worker calls runtime Stop as a barrier, destroys owned overlays,
  shuts OpenVR down and releases both DLLs. `off` is the completion acknowledgement. Repeated
  Stop is harmless; Start refuses cleanly while startup/teardown is pending. The worker sleeps
  on a condition variable while VR runs. Every API uses a try-lock instead of waiting for that
  worker: getters return empty/nil when busy, mutators return nil plus an error.
  Module close/destruction must join: code and session storage cannot be unloaded under an
  unfinished OpenVR call. OpenVR has no cancellable `VR_Init`; Exit VR itself never joins it.
- `BeginFrame()` -> nil unless the session is ready, otherwise `{sequence,hmd,left,right,devices,
  ipd,seconds_to_photons,wait_ms,completion_wait_ms}`. Acquisition queries predicted tracking
  without waiting. wait_ms times that query; old completion-wait fields remain zero/false for
  existing diagnostic readers. Render-side SDK waits have separate Status fields. Each pose is
  `{valid,pos=Vector,ang=Angle,vel=Vector,angvel=Vector}`: Source axes, metres, degrees, metres/s,
  radians/s. The devices table uses OpenVR device index + 1. Invalid devices have zero poses.
  Standing tracking origin is used. `SetFrameCamera(sequence,Vector,Angle)` pushes that frame's
  raw head pose and the game's world camera; only the last 16 acquired frames can be referenced.
- `Info()` -> model, tracking, refresh, eye_width, eye_height, ipd, activity, input_detail, every
  `rtxvr_Status` field, plus `timing` and `cumulative` tables using the SDK's original field names.
  `timing.valid` says whether a frame timing was available. Initialising/stopping/off returns an
  empty snapshot; after OpenVR initialises, renderer-starting facts remain available.
  Info's `sdk_ready` becomes true once OpenVR/interfaces/input and rtxvr_Start are ready. The page
  installs the camera producer then, while State can still be starting. BeginFrame accepts this
  first-frame bootstrap; the runtime emits no eyes before a fresh SetFrameCamera. Once OpenVR is ready, State reports running; a renderer waiting for its first scene does not impose a startup deadline. Info also exposes the per-session completion_wait_ms,
  completion_wait_max_ms, completion_wait_timeouts, completion_wait_count, completion_wait_polls
  (last call) and completion_wait_high_resolution; these compatibility fields remain zero/false.
  Stop owns cleanup on its worker and outwaits the current runtime SDK call barrier.
  Page convenience fields: `devices={left=bool,right=bool}` (last acquired frame), `presents`,
  `dropped`, `reprojected` (counts), `compositor_gpu_ms`, `compositor_cpu_ms` (only with valid timing).
  V8: `motion_smoothing_supported` and `motion_smoothing_enabled` (booleans, false when simulated) read
  `IVRCompositor::IsMotionSmoothingSupported`/`IsMotionSmoothingEnabled`: SteamVR's frame generation and
  whether the user has it on. The module only reads that setting; it never writes SteamVR's settings.
  `timing.m_nReprojectionFlags` bit 0x08 says Motion Smoothing made the latest frame.
- `Actions()` -> named action records `{active,state,changed,x,y,z,error,curls={5 numbers}}`.
  See [input README](../input/README.md). Updated once by BeginFrame; reads do not advance input.
  Inactive/sleeping devices keep error codes and never fail an otherwise usable VR session.
  `Haptic("left"|"right",seconds,frequency,amplitude)` -> success boolean, OpenVR input error code.
- `OverlayCreate(key,name)` -> decimal **string** handle (Lua numbers lose bits above 2^53).
  All overlay calls accept this string; exact positive numeric handles up to 2^53-1 also work.
  Up to 32 overlays are owned; maximum source sides are 8192 pixels. The runtime separately bounds
  pending source requests to 16 distinct handles between render-thread drains. The add-on manager
  batches requests and retires native handles two seconds after hiding (21 reserved roles including V4).
  Foreign and destroyed handles are rejected.
  `OverlaySource(handle,w,h)` binds the runtime target size (both zero unbind).
  `OverlayAttach(handle,"left"|"right"|"head"|"world",Vector,Angle,width_m)` takes a Source-basis
  local transform in metres; the identity preserves OpenVR's neutral quad orientation.
  Live hand attachments follow their tracked-device role, retrying when a sleeping hand reappears.
  A timeline makes attachments absolute from its scripted pose, so sleeping hands do not matter.
  `OverlayShow(handle,bool)`, `OverlayAlpha(handle,0..1)`, `OverlayDestroy(handle)`.
  Extra read-only `OverlayVisible(handle)` returns OpenVR's visibility flag for tests.
  `OverlayInfo(handle)` additionally reads width, texture dimensions/error and the absolute
  transform/error directly from SteamVR. Its `openvr_matrix34` is a flat 12-number SDK-basis
  matrix, explicitly for diagnostics; gameplay poses still use Source axes. A live relative
  attachment can return a transform-type error; scripted attachments are absolute.
- `Events()` drains bounded queued events: `{type,code,device}`. Types include quit, dashboard_on,
  dashboard_off, standby, wake, ipd and other. IPD events refresh eyes through `rtxvr_UpdateEyes`.
  `Capture(name,flags)` forwards capture flags to the runtime.
- `TestState()` -> nil without a timeline, else `{time,step,ended}`; step is one-based.
- `SetQuality{render_scale,dlss,min_bounces,max_bounces,volumetrics,fine_clouds,stereo}` (V6; `stereo` is V7's true
  stereo, `RTXVR_QUALITY_TRUE_STEREO`, which the runtime honours only with Ray Reconstruction and the physical sky;
  [ADR 0199](../../docs/decisions/0199-vr-auto-quality-ladder.md)) -> true, or false and the runtime's error: hands a
  ladder step to `rtxvr_SetQuality` (runtime API 4). Ranges are checked here (scale 0.25-1.5, DLSS 0-3, bounces 0-16)
  and again by the runtime; the add-on's `cl_perf.lua` is the only caller. `Info()` reports the step the render thread
  applied: `qualityRenderScale`, `qualityDlss`, `qualityMinBounces`, `qualityMaxBounces`, `qualityFlags` and
  `qualityChanges`.

## Timeline format

UTF-8 JSON, version 1, at most 1 MiB and 10000 steps. Lua resolves a data name under its fixed root; native test hosts supply a native path. Times are seconds from successful session startup, strictly increasing from zero,
maximum 86400. Every step supplies all three poses, in Source tracking axes and metres:

```json
{"version":1,"steps":[
 {"time":0,"hmd":{"pos":[0,0,1.6],"ang":[0,0,0]},
  "left":{"pos":[0,0.3,1.1],"ang":[0,0,0]},
  "right":{"pos":[0,-0.3,1.1],"ang":[0,0,0]},
  "actions":{"left_grip":false,"left_stick":[0,0,0]}},
 {"time":2,"hmd":{"pos":[1,0,1.6],"ang":[0,30,0]},
  "left":{"pos":[0,0.3,1.2],"ang":[0,0,0]},
  "right":{"pos":[0,-0.3,1.2],"ang":[0,0,0]},
  "actions":{"left_grip":true,"left_stick":[1,0,0]}}
]}
```

Use either `ang:[pitch,yaw,roll]` degrees or `quat:[x,y,z,w]` in the Source basis; quaternions
are normalised and interpolate along the shortest arc. Positions interpolate linearly. Linear and
angular velocities are derivatives of the segment. The final step holds forever, with zero
velocity and `ended=true`. Boolean actions change at their step; numeric/stick axis values
interpolate to the next matching action. Every step is a full action snapshot: unspecified actions
are neutral. Only declared buttons and axes may be scripted: a boolean for a button, a number for
a scalar axis, `[x,y]` or `[x,y,0]` for a stick; values lie in -1..1. Test poses replace head/hands
after the real WaitGetPoses; the compositor still runs.
The pushed pose carries `RTXVR_POSE_SCRIPTED`. This module never submits eye textures itself.

## Tests and hardware host

`tests/qinspect.cpp` is Q's development-only read-only game-thread clock module, built separately
by `tools/vr_measure_build.ps1` into out. It exposes GetThreadTimes CPU ms, QueryThreadCycleTime
cycles and SDK-loaded presence without calling OpenVR. It is not a package input or CTest scene app.

CTest's `nl_vr_tests` uses only local stand-ins. `nl_vr_session_host` is deliberately absent from
CTest and refuses to run unless it exclusively creates the supplied shared VR lock. Usage:

```text
nl_vr_session_host <verified/openvr_api.dll> <test_runtime.dll> <nlvr_actions.json>
                   <timeline.json|-> <seconds-per-cycle> <main/out/vr/vr.lock> <out/log.jsonl>
```

It starts/stops twice in one process and logs actual OpenVR input errors, visibility, model, size,
refresh, poses, WaitGetPoses time and compositor stats. With the test renderer it submits no eye
image: compositor scene rendering and game render-target overlays remain VR-C/VR-Q integration
checks. Its lock is released on exception too; it never changes SteamVR settings or exits SteamVR.
The offline review tests also hold VR_Init for a second, time every Lua-facing Session entry,
exercise cancellation/restart, check the renderer-start deadline, and verify W/S ordering with
fast, delayed and stalled fake rendering. A 300-frame benchmark at 0/1/3 ms render delays logs
completion wait, completion-to-pose latency and main-thread CPU time. The fake delay uses a
high-resolution timer too, avoiding the coarse system Sleep tick. These measure the module's
polling overhead without claiming real runtime/Index performance.


## V4 controller frames (C)

`controller_frames.h` and `controller_frames.cpp` cache SteamVR's tip and openxr_handmodel components once per connection, through optional IVRRenderModels. The standard 31-bone WithController skeleton, when available, supplies the wrist and the midpoint to the four knuckles as palm centre. Both aim and palm use the tip's forward/thumb-up orientation. Invalid/missing components fall back to raw with one Lua log per controller revision; prediction is unchanged. Device activation/deactivation/update/role changes invalidate the cache; Stop clears it. No render-model file is opened by the production module.

BeginFrame adds `controllers.left/right`: valid, revision, device, model, source, detail, skeleton, and local aim/hand/wrist poses (Source axes/metres) plus skeletal finger/normal vectors. Existing hmd/left/right/devices remain raw. `tests/test_frames.cpp` tests recorded Index/Touch/Vive matrices, natural holds, malformed/reflected transforms, skeleton landmarks and offset velocity. `tests/test_v2.cpp` also checks cache/reconnect/Stop and optional-interface fallbacks. SimDevice optionally reads recorded component matrices from the launcher-selected test description; the Lua API gains no path overrides.

A valid tip plus a standard constrained skeleton also works when openxr_handmodel is absent. Missing both anatomical sources keeps the raw fallback. Tests cover both cases separately.
Q integration raises the per-session owned overlay bound from 16 to 32: lazy movement dots,
ghosts and glove markers otherwise exhaust it before menus/keyboard open. test_v2.cpp exercises
32 sources, overflow refusal, replacement after destroy and a clean second session. The bound
remains finite; the helper and test-only clocks are never shipped.

Q integration resolves the optional window export using the shared rtxvr_api.h declaration
and RTXVR_WINDOW_SHOW/NO_MIRROR flags, after R/M land. No private duplicate C signature or
literal flag declaration remains; wire version stays 3.

Skeleton(hand,reference) returns model-space Source-basis joints (31 poses), valid/error/source, for with_controller (GetSkeletalBoneData WithController), fist, grip_limit or open (GetSkeletalReferenceTransforms). No camera/pose/binding mutation. Simulated sessions return NoData. The opt-in session host --skeleton openvr.dll runtime.dll manifest lock output records all four sources without eye submission. Unit tests cover full joint conversion and input validation.

## Review correction (2026-11-12)

ControllerFrameCache retries incomplete reads with a 100–1600 ms backoff, preserves each valid component and invalidates on PropertyChanged as well as device/role events. A tip-only result has aim.valid=true and valid=false (no complete hand); Lua consumers preserve its pointing direction and leave hand position raw. Cached model names alone authorize no Index offset.

nlvr.Skeleton(hand, kind, destination) optionally reuses destination and its 31 six-number bone arrays [x,y,z,p,y,r], avoiding per-read pose userdata. Invalid/busy reads do not overwrite the caller's last good sample; callers maintain that separate cache. The original two-argument detailed-pose result is preserved. Native review regressions cover retry/backoff, tip-only, independent wrist preservation and property changes; the Lua fixtures cover buffer and last-good policy.

## Placement review (2026-11-12)

PropertyChanged and TrackedDeviceUpdated refresh the model/component fingerprint without clearing usable calibration. Identical geometry retains the same revision and skips reference reads; true geometry/model changes derive landmarks from GripLimit reference transforms, never one live curled WithController sample. A simulated 9 mm live-pose change during a battery-style event cannot change hand/wrist/revision or trigger another skeletal calibration.
