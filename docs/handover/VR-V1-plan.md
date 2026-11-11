# VR V1 work plan: RTX in the headset

The design is [VR-plan.md](VR-plan.md) (made with the user on 2026-11-10); its table "Decisions taken with the
user" is binding. This file is the work plan for milestone V1: who builds what, the interfaces between the pieces,
and the rules for tests. Claude directs and reviews; Codex (`gpt-6.1-sol`, reasoning effort max, priority tier, as
the user asked for the VR work) writes the code, in tasks that each have a brief beside this file. Standing rules:
[AGENTS.md](../../AGENTS.md).

## The user's brief for V1 (2026-11-10, verbatim)

> Implement VR for the RTX package, milestone V1 ("RTX in the headset") of docs/handover/VR-plan.md.
>
> I made that plan with a side session on 2026-11-10. It is committed on main as a0074b1 [...]. Read the whole plan
> first. Its table "Decisions taken with the user" is binding: if something you find contradicts a decision there,
> stop and tell me with the options, rather than quietly changing the approach.
>
> What V1 must deliver (the plan's V1 row, "The runtime's VR output mode" and "Spikes for V1"):
>
> 1. The spikes S1-S8 first, the ones that could break the plan before the rest (S1 the Vulkan extensions SteamVR
>    needs, S3 Submit from the runtime, S2 a VR-sized path-traced picture, S5 how my unworn Index behaves, then S4,
>    S6, S8, S7). Record each result, with numbers, in RESEARCH.
> 2. The runtime's VR output mode, as patches against the fork: a VR-sized centre view with the headset's
>    projection, the depth warp to both eyes, Submit to SteamVR with the frame's pose, the left eye mirrored into the
>    game window, overlay textures from game render targets, and the VR option layer.
> 3. Our own module gmcl_nlvr_win64.dll (MIT): the OpenVR session, poses and frame pacing, SteamVR Input with Index
>    bindings, overlays, the pose handed to the runtime for the frame it belongs to, and the test mode that scripts
>    head, hands and buttons.
> 4. The VR page in the RTX Remix tab: Start VR and Exit VR, SteamVR and headset status, the GPU warning, frame
>    times; translated like the rest of the tab; plus nl_vr_start and nl_vr_exit.
> 5. Just enough of the add-on for V1: the game's view at the head, the flat HUD kept out of the eyes, and a wrist
>    HUD overlay (health, armour, ammo) on the left controller.
> 6. Exit VR returns to the flat game with my settings. With VR off nothing changes: show it with the usual PoC
>    screenshots and frame times before and after the new runtime.
>
> Rules for this work:
>
> - Work on a branch `vr` in out\worktrees\vr. Do not merge it to main, do not push it, and publish nothing to the
>   Workshop: VR reaches main only when I approve a milestone.
> - gVRMod is a reference only. Its clones are in out\vr-plan\src (gVRMod and vrmod-x64): read them for behaviour,
>   copy no code from them. Our code is MIT.
> - OpenVR only. You may download Valve's OpenVR SDK (the headers, the win64 openvr_api.dll and its BSD-3-Clause
>   licence) from github.com/ValveSoftware/openvr at a pinned release; check its hash and record the pin the way the
>   repository records its other pinned downloads.
> - No loader change. If something seems to need one, stop and tell me.
> - Everything stays off until Start VR: openvr_api.dll not loaded, no VR work per frame, the add-on's files not
>   loaded; only the VR page exists. Tell me exactly what the runtime does differently at start-up with VR off, and
>   measure that it costs nothing.
> - Test on my Valve Index through SteamVR, which is running. Nobody wears the headset and its controllers may be
>   asleep, so drive head, hands and buttons from the module's test mode, and judge by the frames SteamVR received,
>   their timing and saved eye images, not by the display. Take a VR lock (out\vr\vr.lock) as well as the PoC lock.
>   No other Claude session will be using the PoC while you work on this; check for running games and labs anyway.
>   Do not change SteamVR's settings or Steam's registry, and leave SteamVR running as you found it. If SteamVR or
>   the headset is not available, tell me instead of working around it.
> - Measure and report the GPU time by pass and the frame rate at the Index's recommended size on this RTX 5090, at
>   80 and 90 Hz. V1 needs one fixed, sensible preset; the Auto preset is V6.
> - The usual duties: offline and PoC tests, an independent review by a Claude subagent, decision records,
>   CHANGELOG, COMPONENTS, RESEARCH, TESTING, ROADMAP, a handover report docs/handover/VR-V1-report.md, and
>   tools\test.ps1 -Config Release passing on the branch. Mind the LFS quota: import a runtime DLL into packages\
>   only for the build you hand over, not for every experiment.
>
> When V1 is done, stop and report [...]. Then wait for my approval before you merge anything or start V2.

Added by the user the same day: Codex does "all of the coding and relevant task"; Claude reviews its work and gives
it instructions.

## Where things stand at the start (2026-11-10, 07:30 local)

- `main` is `c0c55fb` (R28 published). Branch `vr` starts there, in `out\worktrees\vr`.
- **SteamVR is installed but was not running**: `vrmonitor` quit everything at 04:02:37 after 13 minutes of standby
  (`C:\Program Files (x86)\Steam\logs\vrmonitor.txt`, `vrserver.txt`). A scene application's `VR_Init` starts
  SteamVR, as it does for any player; see "Rules for VR tests".
- The runtime's source is the clone `out\worktrees\r17\out\runtime-src` in the main checkout (branch
  `claude/r26-sky`, `17dcc86c` = `runtime/base.json` plus the 37 patches), with its build in `_CompRelease_x64`.
  It carries an old OpenVR header (`include/openvr/openvr.hpp`: `IVRSystem_019`, `IVRCompositor_022`,
  `IVROverlay_018`) and DXVK's extension provider `src/dxvk/dxvk_openvr.cpp`, which acts only when
  `openvr_api.dll` is already loaded at device creation.
- No Vulkan SDK is installed (`VULKAN_SDK` is empty); the runtime clone has Vulkan headers in `include/vulkan`.
- The PoC (`H:\SteamLibrary\steamapps\common\GarrysMod_PoC`) is deployed with the published package and
  `"subscribed_content": false`. No game and no lab was running.
- OpenVR SDK releases: the newest is **v2.15.6** (2026-03-27, commit `0924064316de3effbcd1acf1e309182a2deb1c05`).
  That is the pin.

## The pieces and who builds them

| Task | Brief | Branch / worktree | Builds |
|---|---|---|---|
| VR-A | [VR-V1-A-sdk-and-probe.md](VR-V1-A-sdk-and-probe.md) | `vr-a`, `out\worktrees\vr-a` | The OpenVR SDK pin (`third_party/openvr`, `tools/ci/pins.json`), the probe tool; spikes **S1** and **S5**, and a reference Vulkan `Submit` |
| VR-C | [VR-V1-C-runtime.md](VR-V1-C-runtime.md) | `vr-c`, `out\worktrees\vr-c`; the runtime clone's branch `vr` | The runtime's VR output mode as patches; spikes **S2, S3, S6, S7, S8** |
| VR-D | [VR-V1-D-module.md](VR-V1-D-module.md) | `vr-d`, `out\worktrees\vr-d` | `gmcl_nlvr_win64.dll`, the action manifest and Index bindings, the test mode; spike **S4** |
| VR-E | [VR-V1-E-addon-and-page.md](VR-V1-E-addon-and-page.md) | `vr-e`, `out\worktrees\vr-e` | The add-on (`vr/addon`) and the VR page with `nl_vr_start` / `nl_vr_exit`, translated |
| VR-Q | [VR-V1-Q-integration.md](VR-V1-Q-integration.md) (written when A-E were in) | `vr-q`, `out\worktrees\vr-q` | `tools/vr_session.py`, the package part `packages/vr`, the whole thing in the PoC on the Index, flat-mode parity, the 80 and 90 Hz measurements |

Claude merges each task's branch into `vr`, has an independent Claude subagent review the result, and writes
`VR-V1-report.md`. Nothing is pushed, nothing goes to `main`, nothing is published.

## Interfaces (binding for every task; a task that cannot keep one says so in its report at once)

### 1. Module to runtime: the C API `rtxvr`, version 1

One header, `vr/native/include/rtxvr_api.h` (MIT, owned by VR-D, written from this section). The runtime patch
carries a byte-identical copy (`src/dxvk/rtx_render/rtx_vr_api.h`); VR-Q checks the two are the same. The runtime
exports the functions from `d3d9.dll` by name (`src/d3d9/d3d9.def`); the module resolves them with
`GetModuleHandleW(L"d3d9.dll")` and `GetProcAddress`, as `loader/client/module.cpp` does for its own export. A
runtime without `rtxvr_GetApiVersion` has no VR output: Start VR then says so.

```c
#define RTXVR_API_VERSION 1u

typedef struct rtxvr_Matrix34 { float m[3][4]; } rtxvr_Matrix34;      /* OpenVR's HmdMatrix34_t layout */

typedef struct rtxvr_Eye {
  float tanLeft, tanRight, tanTop, tanBottom;   /* IVRSystem::GetProjectionRaw, as OpenVR returns them */
  rtxvr_Matrix34 eyeToHead;                     /* IVRSystem::GetEyeToHeadTransform (the Index's eyes are canted) */
} rtxvr_Eye;

typedef void* (*rtxvr_GetGenericInterfaceFn)(const char* interfaceVersion, int* error);

typedef struct rtxvr_StartInfo {
  uint32_t structSize;                          /* sizeof(rtxvr_StartInfo) */
  uint32_t apiVersion;                          /* RTXVR_API_VERSION */
  rtxvr_GetGenericInterfaceFn getGenericInterface;  /* openvr_api.dll's VR_GetGenericInterface, session initialised */
  uint32_t eyeWidth, eyeHeight;                 /* IVRSystem::GetRecommendedRenderTargetSize */
  float    refreshHz;                           /* Prop_DisplayFrequency_Float */
  float    worldUnitsPerMetre;                  /* game units in a metre, for the eye offset */
  rtxvr_Eye eyes[2];                            /* 0 left, 1 right */
  float    renderScale;                         /* the preset's scale on eyeWidth x eyeHeight; 1 = as recommended */
  uint32_t flags;                               /* RTXVR_START_* */
} rtxvr_StartInfo;

#define RTXVR_START_NO_SUBMIT   0x1u   /* render and warp, hand nothing to the compositor (tests without SteamVR) */
#define RTXVR_START_NO_MIRROR   0x2u   /* leave the game's own target alone */

typedef struct rtxvr_FramePose {
  uint32_t structSize;
  uint32_t flags;                               /* RTXVR_POSE_* */
  uint64_t sequence;                            /* the module's frame number, rising */
  rtxvr_Matrix34 hmdToTracking;                 /* the head pose this frame is rendered for */
  float cameraOrigin[3];                        /* the game camera the add-on set for it: world units */
  float cameraAngles[3];                        /* pitch, yaw, roll in degrees, Source's convention */
} rtxvr_FramePose;

#define RTXVR_POSE_SCRIPTED     0x1u   /* a test pose: submit without a pose (the compositor uses its own) */

typedef struct rtxvr_Status {
  uint32_t structSize;
  uint32_t state;                               /* RTXVR_STATE_* */
  int32_t  lastError;                           /* RTXVR_E_*; 0 when none */
  char     lastErrorText[256];                  /* UTF-8, for the page and the log; names a missing extension */
  uint32_t centreWidth, centreHeight;           /* the centre view's output size */
  uint32_t renderWidth, renderHeight;           /* what is path traced before upscaling */
  uint32_t eyeWidth, eyeHeight;                 /* the eye images submitted */
  uint64_t framesRendered, framesSubmitted, submitErrors;
  int32_t  lastSubmitError;                     /* EVRCompositorError of the last failed Submit */
  uint64_t posesMatched, posesUnmatched;        /* frames whose camera matched a pushed pose, and those that did not */
  float    gpuMsTotal, gpuMsPathTrace, gpuMsUpscale, gpuMsWarp, gpuMsOther;   /* GPU time of the last frame by pass */
  float    cpuMsSubmit;                         /* time inside the two Submit calls, last frame */
  uint32_t overlaysBound;                       /* overlay sources that found their render target */
  uint64_t overlayUpdates;
} rtxvr_Status;

enum { RTXVR_STATE_OFF = 0, RTXVR_STATE_STARTING = 1, RTXVR_STATE_RUNNING = 2, RTXVR_STATE_FAILED = 3 };
enum { RTXVR_OK = 0, RTXVR_E_VERSION = 1, RTXVR_E_ARGUMENT = 2, RTXVR_E_NO_DEVICE = 3, RTXVR_E_ALREADY = 4,
       RTXVR_E_NOT_RUNNING = 5, RTXVR_E_EXTENSION = 6, RTXVR_E_INTERFACE = 7, RTXVR_E_RESOURCES = 8 };

uint32_t rtxvr_GetApiVersion(void);
int  rtxvr_Start(const rtxvr_StartInfo* info);
void rtxvr_Stop(void);
int  rtxvr_UpdateEyes(const rtxvr_Eye eyes[2]);                       /* the IPD or the projection changed */
int  rtxvr_PushFramePose(const rtxvr_FramePose* pose);
int  rtxvr_SetOverlaySource(uint64_t overlayHandle, uint32_t width, uint32_t height);   /* 0 x 0 removes it */
int  rtxvr_Capture(const wchar_t* folder, uint32_t what);             /* RTXVR_CAPTURE_*: the next frame's images as PNG */
int  rtxvr_GetStatus(rtxvr_Status* status);

#define RTXVR_CAPTURE_EYES     0x1u   /* left.png, right.png: what is submitted */
#define RTXVR_CAPTURE_CENTRE   0x2u   /* centre.png and centre_depth.png */
#define RTXVR_CAPTURE_OVERLAYS 0x4u   /* overlay_<handle>.png */
#define RTXVR_CAPTURE_MIRROR   0x8u   /* mirror.png: the game window's picture */
```

Rules:

- **Threads.** Every function may be called from any thread and returns quickly: it records a request under a lock;
  the runtime acts at its next frame, on its own threads. `rtxvr_Stop` is the exception: when it returns the runtime
  makes no further OpenVR call (the module then shuts OpenVR down and frees `openvr_api.dll`); the Vulkan
  resources may go a frame later.
- **`rtxvr_Start`** validates and returns; the state is `STARTING` until the first VR frame, then `RUNNING` or
  `FAILED` with `lastErrorText`. It checks SteamVR's Vulkan extension lists
  (`IVRCompositor::GetVulkanInstanceExtensionsRequired` / `GetVulkanDeviceExtensionsRequired`) against the
  device's and fails with `RTXVR_E_EXTENSION`, naming what is missing (spike S1 says whether that can happen here).
- **OpenVR in the runtime.** The runtime never loads `openvr_api.dll` and never initialises OpenVR. It takes
  `IVRCompositor` (and `IVROverlay`, `IVRSystem` if it needs them) from `getGenericInterface` with the interface
  version strings of the pinned header.
- **The camera.** Position and orientation are the game's camera (the add-on puts it at the head). In VR mode the
  runtime replaces the projection with one symmetric frustum from the centre of the eyes that covers both eyes'
  frusta (their tangents, turned by `eyeToHead`), and path traces into its own centre-view image, sized so that its
  pixel density at the centre of each eye is that of `eyeWidth x eyeHeight` times `renderScale`.
- **Which pose a frame has.** The module pushes, for every frame, the head pose with the camera the add-on set for
  it. When the runtime renders a frame it takes the pushed entry whose camera is nearest to the frame's own camera
  (position and angles; a ring of the last 16) and submits with that pose (`Submit_TextureWithPose`). That needs
  nothing from the engine and holds under `mat_queue_mode 2`. Spike S4 still settles whether the material system's
  call queue is reachable, and compares the two; the ring is the fallback either way. A frame that matches nothing
  within a tolerance is submitted with the newest pose and counted in `posesUnmatched`.
- **Overlays.** `rtxvr_SetOverlaySource(handle, w, h)` binds an OpenVR overlay to the game render target that has
  exactly that size; the add-on gives each overlay target a size nothing else uses. When the target was drawn to,
  the runtime copies it to an image of its own and calls `IVROverlay::SetOverlayTexture`. Spike S8 settles this,
  and may change how a target is identified (say so in the report; the header changes with it).
- **Off.** Before `rtxvr_Start` and after `rtxvr_Stop` the runtime holds no VR image, makes no OpenVR call and does
  no VR work per frame. The only start-up difference VR may add to a flat session is device extensions (plan,
  "Device prerequisites"); VR-C states exactly what it is and measures it.

### 2. Module to Lua: the `nlvr` table

`require("nlvr")` loads `gmcl_nlvr_win64.dll` (the package deploys it to `garrysmod\lua\bin`) and leaves the global
`nlvr`. Loading the module does nothing else: no thread, no `openvr_api.dll`. The page requires it only when the
player presses Start VR or asks for the status.

| Function | Returns | What it does |
|---|---|---|
| `nlvr.Version()` | number | The module's API version (1) |
| `nlvr.Probe()` | table | Without loading OpenVR: `runtime_api` (the `rtxvr` version of the loaded `d3d9.dll`, or nil), `openvr_dll` (the path it would load, or nil), `steamvr_installed`, `steamvr_running` (from `%LOCALAPPDATA%\openvr\openvrpaths.vrpath` and the process list) |
| `nlvr.Start(options)` | true, or false and a message | Begins the start on a worker thread: loads `openvr_api.dll`, `VR_Init(VRApplication_Scene)`, the interfaces, the action manifest, `rtxvr_Start`. `options`: `scale` (game units a metre), `render_scale`, `timeline` (a test timeline file), `no_submit` |
| `nlvr.State()` | string, detail | `"off"`, `"starting"`, `"running"`, `"stopping"`, `"failed"`; the detail is a message for the page (an OpenVR init error by name, the runtime's `lastErrorText`) |
| `nlvr.Stop()` | | `rtxvr_Stop`, overlays destroyed, `VR_Shutdown`, `openvr_api.dll` freed. Safe at any time, also from a `ShutDown` hook |
| `nlvr.BeginFrame()` | table or nil | `WaitGetPoses`, then the frame: `sequence`, `hmd`, `left`, `right` (each `{valid, pos = Vector, ang = Angle, vel, angvel}` in tracking space, metres, converted to Source's axes), `ipd`, `seconds_to_photons`. nil unless running. With a timeline the poses are the scripted ones |
| `nlvr.SetFrameCamera(sequence, origin, angles)` | | `rtxvr_PushFramePose` for that frame |
| `nlvr.Info()` | table | Headset model and tracking system, `refresh`, `eye_width`, `eye_height`, the runtime's `rtxvr_Status` as fields, `IVRCompositor::GetFrameTiming` of the last frame and the cumulative stats (presents, dropped, reprojected), device activity |
| `nlvr.Actions()` | table | The SteamVR Input action states of this frame (V1: what the bindings define; the add-on uses none yet) |
| `nlvr.Haptic(hand, seconds, frequency, amplitude)` | | A haptic pulse |
| `nlvr.OverlayCreate(key, name)` | handle or nil | A SteamVR overlay |
| `nlvr.OverlaySource(handle, width, height)` | | `rtxvr_SetOverlaySource` |
| `nlvr.OverlayAttach(handle, device, pos, ang, width_m)` | | Places it: `device` is `"left"`, `"right"`, `"head"` or `"world"` (tracking space); with a timeline a hand's overlay is placed absolutely from the scripted pose |
| `nlvr.OverlayShow(handle, shown)`, `nlvr.OverlayAlpha(handle, a)`, `nlvr.OverlayDestroy(handle)` | | |
| `nlvr.Events()` | array | SteamVR events since the last call, as `{type = "quit" | "dashboard_on" | "dashboard_off" | "standby" | "wake" | "ipd" | ...}` |
| `nlvr.Capture(folder, what)` | | `rtxvr_Capture` |
| `nlvr.TestState()` | table or nil | With a timeline: the time in it, the step, whether it ended |

Axes: OpenVR is right-handed, +x right, +y up, -z forward, metres. Source is +x forward, +y left, +z up. The
module converts; Lua never sees OpenVR's axes.

### 3. The frame, in the add-on

```
PreRender:        frame = nlvr.BeginFrame()             -- blocks until SteamVR's next frame: this paces the game
CalcView:         origin, angles = world pose of the head (tracking origin at the player's feet, turned by the
                  play-space yaw; nl_vr_scale units a metre); fov wide enough that the engine culls nothing an eye
                  sees; return the view; nlvr.SetFrameCamera(frame.sequence, origin, angles)
HUDShouldDraw:    false while VR runs; HUDPaint and the default HUD stay out of the eyes
the wrist HUD:    painted into its own render target when its numbers change; an overlay on the left controller
```

Start VR: the page (or `nl_vr_start`) requires the module, calls `nlvr.Start`, shows the state, and when it is
`"running"` includes the add-on's files (they live under `lua/nlvr/`, never under `autorun`). Exit VR
(`nl_vr_exit`, a SteamVR quit event, the game shutting down): the add-on removes its hooks, puts back every setting
it changed, `nlvr.Stop()`. Settings the add-on has to change for VR (for example `fps_max` below the headset's
refresh rate) are changed for the session and put back at Exit and in `ShutDown`; nothing archived is left changed.

### 4. Files

As the plan's "Files to add": `vr/native/` (module, its tests, `include/rtxvr_api.h`, `probe/`), `vr/addon/`,
`vr/input/`, `companion/nativeloader/lua/autorun/client/nativeloader_vr.lua`, `runtime/patches/0042-...`,
`third_party/openvr/`, `tools/vr_session.py`, `packages/vr/`. Every script and C++ folder gets its document
(AGENTS.md, "Documentation duties").

## Rules for every task

- **Your branch, your paths.** Commit on your own branch in your own worktree, only under the paths your brief
  assigns; shared documents (CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING) are edited by Claude at
  integration: put your text for them in your report. Commit as the repository's git identity,
  `SheepyLord <37598021+SheepyLord@users.noreply.github.com>` (it is the git config; do not pass another author),
  and end each message with `Co-Authored-By: Codex <noreply@openai.com>`.
- **Never** push, merge into `main` or `vr`, publish to the Workshop, start a GitHub workflow, or change the loader
  (`loader/`). If something seems to need a loader change, stop and say so in your report.
- **gVRMod is a reference only** (`out\vr-plan\src\gVRMod`, `out\vr-plan\src\vrmod-x64` in the main checkout): read
  for behaviour, copy no code, no comments, no data tables. Our code is MIT.
- **No binaries in git** (AGENTS.md rule 6). `openvr_api.dll` and built DLLs stay under `out\`; the import into
  `packages\` happens once, at hand-over, by VR-Q.
- Temporary and build files under the git-ignored `out\` of your worktree (or `out\vr\` in the main checkout for
  what tasks share). Never the system temp folder.
- Do not ask questions: decide, record why in your report, carry on. If a decision of the plan's table "Decisions
  taken with the user" seems wrong, do not change the approach: stop that part and say so in your report with the
  options.
- Finish with `docs/handover/VR-V1-<letter>-report.md` (what you built, each spike's result with numbers, the
  tests and where their evidence is, what is open, your text for the shared documents) and, where your task has
  code in this repository, `tools\test.ps1 -Config Release` passing in your worktree (run it from the worktree:
  its path is short enough).

## Rules for PoC and VR tests

- **The PoC lock.** One game at a time in the PoC: take
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock` (exclusive create, your task's name and the time
  in it), release it when your session is over, never remove another task's lock; poll every few seconds when it is
  taken. [`tools/poc_session.py`](../../tools/poc_session.py.md) is the driver: it snapshots, launches with
  `-multirun`, answers the Remix crash prompt with No, and rolls back. Before a session, check for running
  `gmod.exe` and other labs (`python.exe` command lines).
- **The VR lock.** SteamVR shows one scene application at a time: take
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\vr.lock` the same way for anything that initialises OpenVR
  (the probe, a game in VR), as well as the PoC lock when a game runs.
- **SteamVR.** Never change SteamVR's settings, its driver configuration or Steam's registry; never use the null
  driver; never quit SteamVR or end its processes. SteamVR was not running when this work began: let a scene
  application's `VR_Init` start it, the way it starts for a player, and leave it running. Start it in no other
  way. If `VR_Init` fails (no headset, a driver error), record the exact error, stop the tests that need the
  headset, and carry on with what does not: Claude tells the user. Nobody wears the headset and the controllers
  may be asleep: judge by what the compositor received (frame timing, cumulative stats), by saved images and by
  logs, never by the display.
- **The user's files.** Never write Steam's depot files; never touch the PoC's or any install's Remix `user.conf`;
  never the field install (`...\common\GarrysMod`), `GarrysMod_RTX_c` or its backups. Never set
  `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES` (it grants crash-upload consent); decline crash prompts (No, then
  OK). Read a game's `console.log` only from your own session's start.
- **Settings shared through Steam Cloud.** GMod's `cfg/config.cfg` is shared by the PoC and the user's own game: do
  not leave an archived console variable changed (`fps_max`, `mat_vsync`, `mat_queue_mode` and the like). Set what
  a test needs on the command line or for the session, and end the session as `poc_session.py` does.
- **The loader's update reminder** covers screenshots in the PoC some seconds into a session: remove the Derma
  frame whose title contains "loader update" from Lua; never press "Don't remind me".
- Quit a game as soon as a test is over. Delete large evidence copies (snapshots, built DLL copies) once a
  rollback is verified; keep logs, numbers and pictures.
- Other programs on this computer (games, AI jobs) share the GPU: launch tests anyway, and note it beside timings.

## Done, for V1

The V1 row of the plan: Start VR from the page shows the path-traced view in the Index, the centre view warped to
both eyes, following scripted head poses; the compositor receives every frame (frame timing, no errors); the window
mirrors the left eye; the wrist HUD overlay follows the left controller; Exit VR returns to the flat game with its
settings; flat-mode parity holds; S1-S8 settled and recorded; GPU time by pass and frame rate at the Index's
recommended size at 80 and 90 Hz with one fixed preset.
