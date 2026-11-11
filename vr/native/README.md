# Native VR client module (VR V1 D)

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
contains no WaitGetPoses call, completion ticket, timer or serial wait. Start pacing="serial"
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
| `input_actions.h` | Shared button/axis metadata for input reads and strict script validation |
| `session.h`, `session.cpp` | Worker start, ordered stop, DLL exports, poses, input, overlays, events and facts |
| `module.cpp` | Thin client-realm Lua adapter, validated arguments and exact overlay handles |
| `tests/make_stubs.py` | Generates concrete inert SDK interface bases in the build tree |
| `tests/fake_control.h` | Offline test fault/counter ABI |
| `tests/fake_openvr.cpp` | Stand-in `openvr_api.dll`, never the user's SteamVR |
| `tests/fake_runtime.cpp`, `tests/fake_runtime.def` | Stand-in runtime exports and failure injection |
| `tests/missing_runtime.cpp` | A renderer with no VR exports |
| `tests/test_vr.cpp` | Offline CTest coverage of lifecycle, maths, timeline, overlays and failures |
| `tests/api_layout.c` | Compiles the current header as C and asserts the Windows x64 ABI layout |
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
  no_submit (default false), and comparison pacing render/serial. A missing renderer fails before
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
- `Actions()` -> named action records `{active,state,changed,x,y,z,error,curls={5 numbers}}`.
  See [input README](../input/README.md). Updated once by BeginFrame; reads do not advance input.
  Inactive/sleeping devices keep error codes and never fail an otherwise usable VR session.
  `Haptic("left"|"right",seconds,frequency,amplitude)` -> success boolean, OpenVR input error code.
- `OverlayCreate(key,name)` -> decimal **string** handle (Lua numbers lose bits above 2^53).
  All overlay calls accept this string; exact positive numeric handles up to 2^53-1 also work.
  Up to 16 overlays are owned, matching the runtime limit; maximum source sides are 8192 pixels.
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
