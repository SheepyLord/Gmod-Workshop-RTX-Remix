# VR-V1-C: the runtime's VR output mode (spikes S2, S3, S6, S7, S8)

Read first: [VR-plan.md](VR-plan.md) (the design; "The runtime's VR output mode" is your part, and the decisions
table is binding), [VR-V1-plan.md](VR-V1-plan.md) (interfaces, rules for every task and for PoC and VR tests),
[AGENTS.md](../../AGENTS.md), [runtime/README.md](../../runtime/README.md) and
[build_runtime.ps1.md](../../runtime/build_runtime.ps1.md) (how this project patches and builds the Remix runtime
fork; the newest entries first). You are the implementer; Claude reviews.

## Where you work

- **The runtime's source:** the clone
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r17\out\runtime-src` (branch `claude/r26-sky`,
  `17dcc86c`: exactly `runtime/base.json` plus the 37 patches; its build is in `_CompRelease_x64`). Make a branch
  `vr` there from `17dcc86c` and commit on it, as the fork's git identity (its git config). No other task builds
  there while you work. Build with `runtime\build_runtime.ps1 ... -NoImport` as the README's recent entries did
  (two compile passes because of the shaders). Never import a DLL into `packages\runtime` (LFS quota: VR-Q
  imports once, at hand-over).
- **This repository:** branch `vr-c` in `out\worktrees\vr-c`: the exported patches
  (`runtime/patches/0042-...`, each exported alone: `git format-patch -1 --start-number <N>` with an absolute
  `-o`; re-exporting a range rewrites every header), their hashes as `pending_patches` in `runtime/base.json` so
  `tools\check_repo.py` passes without an import, the entry at the top of `runtime/README.md`, your report.
- Test builds of `d3d9.dll` go into the PoC only through a `tools\poc_session.py` session (snapshot and
  rollback); see how earlier runtime rounds tested a `-NoImport` DLL (`docs/TESTING.md`, "R26", "R20").

## What to build

The plan's ten points, with the interface of the work plan ("Module to runtime: the C API `rtxvr`"), which is
binding: write `src/dxvk/rtx_render/rtx_vr_api.h` from that section exactly (task VR-D writes the same header in
this repository; they must end byte-identical, so change nothing silently: a needed change goes in your report).

1. **The C API** exported from `d3d9.dll` (`src/d3d9/d3d9.def`), dormant until `rtxvr_Start`.
2. **A VR-sized centre view.** In VR mode `RtxContext::injectRTX` renders into the runtime's own centre-view image
   instead of the image bound when path tracing ends (`src/dxvk/rtx_render/rtx_context.cpp:510-619` and what
   follows): sized from the eyes (work plan, "The camera"), with the centre projection replacing the game's;
   DLSS and the other upscalers work below it as usual; Start and Stop recreate resources as a resize does. The
   window keeps its size.
3. **The warp.** A compute pass per eye that samples the final centre image backwards with the primary surface's
   depth through the eye's full transform (the Index's eyes are canted: `eyeToHead` has a rotation as well as the
   half IPD), taking the farther surface where the centre view saw none.
4. **Submit.** `IVRCompositor::Submit` per eye with `VRVulkanTextureData_t` and the frame's pose
   (`Submit_TextureWithPose`; without a pose for a `RTXVR_POSE_SCRIPTED` frame), under DXVK's submission lock
   (`DxvkDevice::lockSubmission`), the frame's commands flushed first, then `PostPresentHandoff`. Task VR-A's
   probe (`vr/native/probe`, branch `vr-a`) has a reference Submit and what the compositor expects (formats,
   layout, the queue rule, explicit timing): read its README and report when they exist, and SteamVR's own logs.
   The pose comes from the ring of pushed poses, matched by the frame's camera (work plan, "Which pose a frame
   has").
5. **The mirror.** The left eye, scaled and cropped, in the game's own target: the window shows it, and what the
   game draws after path tracing (console, menus) lands on top.
6. **Overlays.** `rtxvr_SetOverlaySource`: a game render target of the given exact size is copied to an image of
   the runtime's when it was drawn to, and handed to `IVROverlay::SetOverlayTexture`. Painting into such a target
   is a raster canvas draw ([ADR 0122](../decisions/0122-raster-canvases-keep-their-native-draws.md)).
7. **The VR option layer.** While VR runs, the preset's options (the upscaler's mode, path-tracing quality,
   costly effects; frame generation off, and whatever else must be off in VR: say what and why) sit in one layer
   of the runtime's option layers that Stop removes; the player's settings and their files are never written.
   V1 needs one fixed, sensible preset: choose it from S7's numbers and say why.
8. **The window's present** must not wait for the monitor while VR runs (the game's `mat_vsync` is the player's
   and is not touched).
9. **`rtxvr_Capture`** saves the next frame's images (eyes, centre and its depth, overlays, mirror) as PNG into a
   folder; **`rtxvr_GetStatus`** with the GPU time by pass (path tracing, upscaling, the warp, the rest) and the
   Submit time.
10. **Off.** Before Start and after Stop: no VR image, no OpenVR call, no per-frame VR work. The runtime never
    loads `openvr_api.dll` and never initialises OpenVR: it takes its interfaces from
    `rtxvr_StartInfo.getGenericInterface`. Use the pinned OpenVR header for the new code: `headers/openvr.h` of
    `https://github.com/ValveSoftware/openvr` at commit `0924064316de3effbcd1acf1e309182a2deb1c05` (v2.15.6),
    byte-identical in the tree (the fork's old `include/openvr/openvr.hpp` and DXVK's `dxvk_openvr.cpp` keep
    working as they do).
11. **Device prerequisites (S1).** If SteamVR asks for Vulkan extensions the runtime's device does not enable
    (VR-A's S1 result, or log both lists yourself at `rtxvr_Start`), enable them at device creation whenever the
    GPU has them, behind nothing: Start VR comes long after the device exists. The user wants to be told
    **exactly what the runtime does differently at start-up with VR off** and to see it measured that it costs
    nothing: state it (ideally "nothing"; otherwise the list of extensions) and measure start-up and frame times
    against the published runtime.
12. New options and menu texts translated in the fork's six catalogs and `RtxOptions.md` regenerated, as the
    earlier patches did; unit tests in the runtime's suite for the maths: the centre projection that covers both
    eyes, the warp on synthetic depth (rotation exact, distance right, the farther surface in a gap), the pose
    ring's matching.

## The spikes, in this order, each with numbers in your report

Do not wait for task VR-D's module: for your spikes write a throwaway driver (a small GMod binary module built
under `out\`, required from a `poc_session.py --lua` script, that initialises OpenVR and calls `rtxvr_*`, or
`RTXVR_START_NO_SUBMIT` with Index-like numbers where no headset is needed). It is not committed; VR-D's module
replaces it at integration.

- **S2** (no headset needed): can `injectRTX` render into a VR-sized image while the window keeps its size?
  Pictures and timings against the flat game at the same output size and settings.
- **S6**: with the game's field of view set wide (the add-on will do that in `CalcView`) and the runtime's own
  projection, does the camera stay the main camera (no camera cut every frame, no view-model camera, history
  kept)? The runtime's camera log and debug views; which field of view the engine needs so that nothing an eye
  sees is culled.
- **S3** (the headset): does Submit from DXVK's queue under `lockSubmission` work without stalls? SteamVR's frame
  timing and cumulative stats over some minutes: frames presented, dropped, reprojected; the compositor's errors.
- **S8**: an overlay fed from a game render target: shown by SteamVR (its texture set, the overlay visible) and
  saved to `out\`.
- **S7**: what the centre view plus the warp cost at the Index's recommended size on this RTX 5090: GPU time by
  pass and the frame rate with SteamVR at 80 and at 90 Hz. The headset's refresh rate is a SteamVR setting, which
  is not changed: measure at the rate it has, say which, and give the other from the GPU times (a frame budget of
  12.5 and 11.1 ms); if the rate can be requested for the session through OpenVR without changing a setting,
  say how.

Flat mode: with VR off the new DLL must change nothing. Compare it with the published runtime in the PoC:
the usual screenshots and frame times (same map, pose, settings; a fixed clear sky:
`nativeloader_weather clear`, `nativeloader_sky_time_passes 0`), start-up time included.

## Rules that matter most here

- "Rules for every task" and "Rules for PoC and VR tests" of the work plan: the PoC lock and the VR lock, SteamVR
  started only by `VR_Init` and left running, no setting changed, the user's files, the crash prompt, no archived
  console variable left changed.
- Evidence under `out\vr\c\` in the main checkout (pictures, logs, numbers). Delete built DLL copies and
  snapshots once a rollback is verified.
- A GPU crash or device loss in a test shows Remix's crash prompt: decline it (No, then OK); never set the
  automation variable.

## Your paths

The runtime clone's branch `vr`. In this repository: `runtime/**`, `docs/handover/VR-V1-C-report.md`.

## Done

The patches exported and recorded as pending, the DLL built with `-NoImport` and its SHA-256 in the report; every
point above working in the PoC with your driver; S2, S6, S3, S8, S7 settled with numbers; the flat-mode
comparison; the statement of what start-up does with VR off; `tools\test.ps1 -Config Release` passing in
`out\worktrees\vr-c`; the report (what was built and how it works, each spike, what is open, anything in the plan
that turned out wrong, your text for RESEARCH, TESTING and the decision records).
