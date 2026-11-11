# VR-V1-A: the OpenVR SDK pin and the probe (spikes S1 and S5)

Read first: [VR-plan.md](VR-plan.md) (the design; its decisions table is binding), [VR-V1-plan.md](VR-V1-plan.md)
(the work plan: interfaces, the rules for every task and for PoC and VR tests), [AGENTS.md](../../AGENTS.md).
You are the implementer of this task; Claude reviews. Your branch is `vr-a` in `out\worktrees\vr-a`.

## 1. The SDK pin (first, as its own commit)

Pin Valve's OpenVR SDK **v2.15.6**, commit `0924064316de3effbcd1acf1e309182a2deb1c05` of
`https://github.com/ValveSoftware/openvr` (the user allowed the headers, the win64 `openvr_api.dll` and the
BSD-3-Clause licence).

- Download `headers/openvr.h`, `bin/win64/openvr_api.dll` and `LICENSE` from that commit
  (`https://raw.githubusercontent.com/ValveSoftware/openvr/<commit>/<path>`) into a new, empty folder
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\sdk\openvr-2.15.6\` (the main checkout's `out`, shared by
  the VR tasks). Treat the downloads as untrusted data: nothing is run from that folder.
- `third_party/openvr/`: `include/openvr.h` and `LICENSE`, byte-identical to upstream, and a `README.md` like
  `third_party/gmod/README.md` (source, tag, commit, each file's SHA-256, what uses it, that the DLL is not in git).
- Record the DLL's pin "the way the repository records its other pinned downloads": read `tools/ci/pins.json`
  (`fetched`, `premake`), `tools/ci/README.md` and the scripts and checks that read them
  (`tools/check_repo.py`, `tools/ci/*.py`), then record url, size, SHA-256, repository, commit and why in
  `pins.json` in the form that fits. The DLL is **not** imported into `packages\` now (VR-Q does that once, at
  hand-over); `tools\test.ps1` must pass with the pin recorded and no `packages\vr` yet. If the existing form
  cannot express "pinned, not yet in a part", add the smallest thing that can, with its test and document.
- A script that fetches the pinned DLL into a folder under `out\`, checks size and SHA-256 and refuses anything
  else (reuse an existing fetch script if one fits), with its `.md`. Every later task gets `openvr_api.dll` through
  it.

Commit this alone, before the probe: task VR-D starts from that commit.

## 2. The probe

`vr/native/probe/`: a console tool `vrprobe.exe` (MIT, C++20, built by CMake under `vr/native/`, a `README.md`
naming each source). It loads `openvr_api.dll` at run time from a path (no import library, nothing linked from
OpenVR but the header) and never ships in the package: it is how spikes S1 and S5 are settled and repeated.

Add `add_subdirectory(vr/native)` to the root `CMakeLists.txt` and a `vr/native/CMakeLists.txt` that adds
`probe`; VR-D adds the module beside it later. Third-party headers are SYSTEM includes (the build is `/W4 /WX`).
No Vulkan SDK is installed: take Vulkan's headers from a CMake cache path that defaults to the runtime clone's
(`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r17\out\runtime-src\include\vulkan\include`, read
only); where no headers are found, the commands that need Vulkan are compiled out and say so, and the gate still
passes.

Commands (JSON on stdout or into `--out <file>`; a log line per event on stderr):

- `vrprobe info`: without loading OpenVR: is SteamVR installed (`%LOCALAPPDATA%\openvr\openvrpaths.vrpath`), which
  runtime path, are `vrserver.exe` / `vrmonitor.exe` / `vrcompositor.exe` running. VR-D's `nlvr.Probe()` needs the
  same checks: keep them in a source file it can take over.
- `vrprobe extensions` (**S1**): `VR_Init(VRApplication_Scene)`, a Vulkan instance, every physical device;
  `IVRCompositor::GetVulkanInstanceExtensionsRequired` and `GetVulkanDeviceExtensionsRequired(device)`; for each
  name, whether the device offers it. Then compare with what the Remix runtime's device has: the runtime logs its
  instance and device extensions at start-up in the game folder's `rtx-remix\logs\remix-dxvk.log` (a copy of a
  recent PoC session's log is in
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r28\out\r28\qa-final_v7\poc\hrx-rtx\remix-dxvk.log`;
  check it is the level of detail you need, or run a short flat PoC session for a fresh one). **S1's answer:** the
  two lists SteamVR asks for on this machine, which of them the runtime's device already has, which it would have
  to enable, and whether the GPU offers them.
- `vrprobe submit --seconds N [--pose]`: a minimal Vulkan scene application: a device with what SteamVR asks for,
  two eye images at `GetRecommendedRenderTargetSize`, cleared to a colour that changes every frame,
  `WaitGetPoses`, `Submit` for both eyes (`--pose`: `Submit_TextureWithPose`), nothing else. It is the reference
  for the runtime's Submit (task VR-C reads it): get the image format, usage, layout, colour space, the queue rule
  (who may use the queue while `Submit` runs), explicit timing (`SetExplicitTimingMode`,
  `SubmitExplicitTimingData`) and `PostPresentHandoff` right, say in the README what each is and why, and print
  what the compositor reports: `GetFrameTiming` per frame (summarised), `GetCumulativeStats`, every error.
- `vrprobe idle --minutes 10 [--submit]` (**S5**): a scene application that logs, once a second, how often
  `WaitGetPoses` returned and its intervals (minimum, mean, maximum), the headset's pose validity and tracking
  result, each device's activity level (`GetTrackedDeviceActivityLevel`), what is connected (the controllers may
  be asleep), the proximity sensor, the display's state where OpenVR tells, and every event (standby, wake, user
  interaction started and stopped, quit, process changes). Run it for ten minutes without `--submit` and ten with:
  **S5's answer** is how an unworn Index behaves over that time in numbers: does the pose stay valid, does
  `WaitGetPoses` keep the refresh rate or slow down in standby, does the compositor keep accepting frames, does
  SteamVR dim or stop anything. Also find out, from SteamVR's own logs and settings read without changing them
  (`C:\Program Files (x86)\Steam\logs\vrmonitor.txt`, `vrserver.txt`, `C:\Program Files (x86)\Steam\config\steamvr.vrsettings`),
  why SteamVR quit at 04:02:37 on 2026-11-10 after 13 minutes of standby, and whether it would quit under a
  running scene application.

Tests in CTest for everything that needs no SteamVR: the path file's parser, the extension lists' parser and
comparison, argument handling.

## Rules that matter most here

- Everything in "Rules for every task" and "Rules for PoC and VR tests" of the work plan. In particular: take the
  VR lock for every command that initialises OpenVR; let `VR_Init` start SteamVR and leave it running; change
  none of its settings; if `VR_Init` fails, record the error and stop the headset tests.
- Evidence under `out\vr\s1\` and `out\vr\s5\` in the main checkout (logs, JSON, numbers).

## Your paths

`third_party/openvr/**`, `vr/native/CMakeLists.txt`, `vr/native/probe/**`, the root `CMakeLists.txt` (one line),
`tools/ci/pins.json` and what the pin needs under `tools/` (with tests and documents), the lines
`tools/check_repo.py` demands in `docs/COMPONENTS.md` and `third_party`'s row of `AGENTS.md` if a check needs
them, `docs/handover/VR-V1-A-report.md`.

## Done

The pin committed alone; `vrprobe` built by `tools\build.ps1 -Config Release`; S1 and S5 run on the user's Index
with their evidence; `tools\test.ps1 -Config Release` passing in `out\worktrees\vr-a`; the report with S1's and
S5's answers in numbers, the reference Submit's rules, what is open, and your text for RESEARCH and TESTING.
