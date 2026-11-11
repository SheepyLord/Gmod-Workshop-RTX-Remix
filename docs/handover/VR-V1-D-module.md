# VR-V1-D: the module `gmcl_nlvr_win64.dll` (spike S4)

Read first: [VR-plan.md](VR-plan.md) (the design; "The module `gmcl_nlvr_win64.dll`" is your part, and the
decisions table is binding), [VR-V1-plan.md](VR-V1-plan.md) (interfaces, rules for every task and for PoC and VR
tests), [AGENTS.md](../../AGENTS.md). You are the implementer; Claude reviews. Your branch is `vr-d` in
`out\worktrees\vr-d`; it starts from task VR-A's pin commit, so `third_party/openvr/include/openvr.h` (OpenVR
v2.15.6) and the script that fetches the pinned `openvr_api.dll` are there.

## What to build

`vr/native/`: our own client module, MIT, C++20, built by the repository's CMake like `engine_guard/` and
`glass/native/` (a static library with the logic, a thin `module.cpp` for the Lua side, tests in CTest, a
`README.md` naming each source and describing the Lua API and the timeline format). `third_party/gmod` has the
Lua interface headers.

1. **`vr/native/include/rtxvr_api.h`**: the C API of the work plan ("Module to runtime"), written from that
   section exactly. Task VR-C writes the same header into the runtime; they must end byte-identical, so a needed
   change goes in your report, not silently into the file.
2. **The OpenVR session.** At `nlvr.Start`, never before: load `openvr_api.dll` from the module's own folder (the
   package will deploy it beside the module in `garrysmod\lua\bin`; an explicit path for tests), on a worker
   thread, `VR_Init(VRApplication_Scene)` (this starts SteamVR when it is not running: the state stays
   `"starting"` meanwhile), the interfaces, the action manifest, the eye data, then `rtxvr_Start`. No import
   library: resolve `openvr_api.dll`'s exports yourself. `nlvr.Stop` undoes all of it in the right order
   (`rtxvr_Stop` first) and frees the DLL. Loading the module alone starts nothing.
3. **Poses and frame pacing.** `nlvr.BeginFrame` calls `WaitGetPoses` once and returns the frame's poses
   converted to Source's axes; `nlvr.SetFrameCamera` pushes the pose with the game camera to the runtime.
   SteamVR's events (quit, dashboard, standby, IPD change: `rtxvr_UpdateEyes`) reach Lua through `nlvr.Events`.
4. **SteamVR Input.** `vr/input/`: an action manifest and default bindings for the Index controllers (also
   Touch and Vive wands if they cost little), for the controls table of the plan ("Default controls on the
   Index"): V1's add-on uses none of them, but the manifest must load in SteamVR without errors, the actions
   must read, and `nlvr.Actions` and `nlvr.Haptic` must work. Players remap in SteamVR's own binding UI.
5. **Overlays.** Create, place (attached to a controller, to the head, or in tracking space), show, hide, alpha,
   destroy; the source is a game render target through `rtxvr_SetOverlaySource`.
6. **The status** the page needs: `nlvr.Probe` (no OpenVR loaded: SteamVR installed and running; task VR-A's
   probe has these checks in a source file you may take over) and `nlvr.Info` (headset, sizes, refresh rate, the
   runtime's status, `IVRCompositor::GetFrameTiming` and the cumulative stats).
7. **The test mode.** A timeline file (JSON, under `out\`) replaces the head and hand poses and the button and
   axis states over time (steps with a time; positions interpolated, rotations by slerp), so tests drive the head
   and hands without a person; the real headset still receives every frame. Scripted head poses are pushed with
   `RTXVR_POSE_SCRIPTED`. With a timeline an overlay attached to a hand is placed from the scripted pose (the real
   controllers may be asleep). Document the format in the README.
8. **Nothing before Start:** no thread, no timer, no `openvr_api.dll`, no OpenVR registry or file access beyond
   what `nlvr.Probe` is asked for.

## Spike S4: which pose belongs to which frame

The plan's first idea is the material system's call queue (`IMatRenderContext::GetCallQueue`), so that a frame's
pose travels with that frame's draws under `mat_queue_mode 2`. The work plan's interface does without it: the
runtime matches each frame's own camera against a ring of pushed poses. Settle S4 anyway:

- Can a client module reach the call queue on the current GMod x64 (`materialsystem.dll`'s
  `VMaterialSystem080`, `GetRenderContext`, `GetCallQueue`, queueing a functor)? Find it from the public Source
  SDK's interface and the PoC's own binaries (read only), and prove it in the PoC with a throwaway test (a
  functor queued from the main thread runs on the render thread, in order with the frame's draws), or show why
  not. Which `mat_queue_mode` does the PoC actually run with RTX?
- Say which of the two the project should rely on and why (what breaks each: a game update moving a vtable slot;
  two frames with the same camera; a camera the engine changes after `CalcView`). The ring is implemented either
  way; if the call queue is reachable and better, describe the change, do not make it without Claude's word.

## Tests

- Offline, in CTest: a stand-in `openvr_api.dll` and a stand-in for the runtime's `rtxvr_*` exports (as
  `engine_guard/tests` has a stand-in `materialsystem.dll`): start and stop in every order and after failures (no
  SteamVR, no headset, a runtime without the export, a version mismatch), the axis conversion, the timeline
  (interpolation, the end, a bad file), the overlay registry, events, that nothing runs before Start and nothing
  after Stop.
- With SteamVR on the user's Index (the VR lock; rules in the work plan): the session starts and stops cleanly
  twice in one process, poses and frame pacing read, the manifest and bindings load, an overlay shows
  (`IVROverlay` says it is visible), haptics do not fail on a sleeping controller. A small test host or the PoC
  with a `poc_session.py --lua` script, as fits; the runtime side is not there yet (`RTXVR` exports missing is a
  state the module must report well).

## Your paths

`vr/native/**` except `vr/native/probe/**` (VR-A's; you may read it and take its SteamVR checks over), `vr/input/**`,
`vr/native/CMakeLists.txt` (add your targets beside the probe), `docs/handover/VR-V1-D-report.md`. Not the
package (`packages/`), not `tools/ci/pins.json`: VR-Q imports the built module at hand-over.

## Done

The module built by `tools\build.ps1 -Config Release`; the offline tests in the gate; the session, poses, input,
overlays and the test mode shown on the user's Index; S4 settled; `tools\test.ps1 -Config Release` passing in
`out\worktrees\vr-d`; the report (what was built, the Lua API as built, S4, the tests and their evidence under
`out\vr\d\` in the main checkout, what is open, your text for RESEARCH, TESTING and the decision records).
