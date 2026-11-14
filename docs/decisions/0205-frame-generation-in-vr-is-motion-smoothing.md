# 0205: Frame generation in the headset is SteamVR's Motion Smoothing, behind a switch

- Status: Accepted 2026-11-13 for V8 on the branch `vr8`; reaching `main` needs the user's approval. The user approved V8 on 2026-11-13 and it was merged to `main`.
- Decided by: Claude, at the user's request of 2026-11-13 ("allow enabling frame generation in VR if possible. If the
  desktop still renders at full resolution ..., adjust it to match VR to save compute").
- Refines: [ADR 0199](0199-vr-auto-quality-ladder.md), whose Auto held half the refresh in every case.

## Context

The VR session's config layer turns Remix's frame generation off (`rtx.dlfg.enable`, `rtx.fsrfg.enable`,
`rtx.frameGenerationType`). Remix's DLSS-G is a presenter of the desktop window's swapchain (`DxvkDLFGPresenter`,
`rtx_dlfg.h`): it interpolates between two finished frames and presents the extra one to that window. The headset's
eyes leave through OpenVR's Submit on the render thread instead, so DLSS-G never reaches them. Driving it for the eyes
would mean interpolating the centre view, warping the generated frame with an interpolated pose and submitting twice
per rendered frame, which adds at least a rendered frame of latency for everything but head rotation. NVIDIA does not
support DLSS-G in VR. SteamVR's own frame generation, Motion Smoothing, extrapolates from the frames the game submits
when it renders at half the refresh, which is what V6's Auto holds; it is a setting of SteamVR's, the user's.

The desktop: the runtime renders the path-traced view at the headset's size whenever VR runs (`rtx_context.cpp:639`,
the output extent comes from `RtxVr::beginFrame`), and the window only receives a cropped copy of the left eye
(`RtxVr::mirror`) and the game's own 2D. V2 measured the whole difference between a 1280 x 720 and a 3840 x 2160 window
at about 0.04 ms of GPU work a frame, with SteamVR's estimate of the game's GPU time no higher at 4K
([VR-V2-R report](../handover/VR-V2-R-report.md)).

## Decision

- **A switch, Frame generation** (`nl_vr_frame_generation`, on by default): on, Auto holds half the headset's refresh
  and SteamVR's Motion Smoothing makes every other frame (V6's behaviour); off, Auto holds the full refresh and VR
  renders every frame, at the lower quality step that needs.
- **The page says what SteamVR does**: the module reads `IsMotionSmoothingSupported` and `IsMotionSmoothingEnabled`
  (read-only; VR never writes SteamVR's settings), and the perf module watches the compositor's frame timing for frames
  Motion Smoothing made (`m_nReprojectionFlags` bit 0x08, within the last 3 s). The page shows that it is making frames,
  that it is off in SteamVR (with where to turn it on), that this GPU does not offer it, or that the switch is off.
- **Remix's DLSS-G stays off in VR**, as before; the page says it only adds frames to the desktop window.
- **The desktop window is not resized**: it already costs nothing worth saving, and resizing the user's window would
  change the game's UI and GUI Scaler layout.

## Consequences

- Turning frame generation off makes Auto aim for 90 rendered frames a second on the Index. V6 measured 67 to 70 per
  second at steps 4 to 7 (85 at step 4 in one run), with GPU work of 4 to 6 ms that would fit 90: whether 90 holds then
  depends on the game's own frame time, so Auto may settle low and still miss on heavy scenes.
- If Motion Smoothing is off in SteamVR, half-rate frames are shown with SteamVR's older reprojection; the page says so.
