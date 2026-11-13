# VR for the RTX package: plan

Planned with the user on 2026-11-10 in a side session (Claude), for the main thread to implement. Nothing here is
built yet. Implementation runs on a `vr` branch and reaches `main` (and so Workshop item 3829070317) only when the
user approves a milestone.

The request (the user, 2026-11-10): "Refer to: https://github.com/Abyss-c0re/gVRMod [...] Adapt this repo to our own
repo to allow RTX-Remix rendering to VR, add a VR-related tab in the RTX tab, assume SteamVR, consideration of the
performance and the setting from the VR device must be taken. [...] Please also plan and implement (or improve, if
the vrmod already has) how user should interact with the game in VR, including the collision of hands and to
entities and ragdolls with an easy to use HUD designed for VR. Note this VR edit should be standalone, which should
not be on unless user turn it on, and should does nothing (or minimal) to gameplay and performance when it is off."
Later in the session: "I just setup a physical Steam headset. You could test with real headset, but note there is no
human wearing headset when testing", and for the controls: "A Half-life Alyx-like controlling experience is
perferred, but adjusted for sandbox in gmod."

## Decisions taken with the user

| Topic | Decision |
|---|---|
| gVRMod's code | **Reference only.** Our own VR code, in this repository under MIT, written after reading gVRMod (and Catse's zlib-licensed VRMod module) for behaviour, as the GPL fixes are read. No gVRMod or vrmod-x64 code is copied. |
| Stereo | **Phased.** First one centre view path traced per frame and warped to each eye with its depth; then true per-eye path tracing as a quality mode. |
| VR API | **OpenVR** (SteamVR). |
| Headset for tests and tuning | **Valve Index** (Index controllers with finger tracking). |
| Testing | On the user's Index **with nobody wearing it**, at any time, under a VR lock. The user makes sure no other Claude session is using the PoC when VR work starts. SteamVR's settings are not changed. |
| Controls | **Half-Life: Alyx-like, adjusted for the sandbox**: physical hands, grab and throw, ragdoll handling, climbing and melee; gravity gloves, ghost hands, use by hand, physical reload. |
| Weapons and tools | Hand-aimed weapons, physgun and toolgun in VR, the spawn and context menus as VR panels, a weapon wheel. |
| HUD | **Wrist HUD plus floating panels**: health, armour, ammo and notifications on the left wrist, ammo also on the gun, menus as panels used with a laser pointer; all through SteamVR overlays. |
| Movement | Smooth movement with snap turn; teleport (blink and shift); comfort options (vignette, smooth turning, seated mode, height calibration); noclip flight. |
| Performance | **Automatic VR preset** from the GPU and SteamVR's settings, with SteamVR's Motion Smoothing when the game runs at half rate; frame times on the VR page. |
| GPU gate | VR on every RTX card; below 12 GB of VRAM or on the low performance tier the VR page warns and starts with the lowest preset. |
| Multiplayer | Full VR in single-player and as the listen-server host; on other servers a **limited mode**: head-tracked view, local hands, firing along the hand through the player's aim; no physical hands or grabbing. |
| Body | Hands visible; an IK-posed body casts the player's path-traced shadow and shows in mirrors and reflections, never in the player's own view. |
| Activation | **Start VR / Exit VR** on the RTX tab's VR page (and console commands). Nothing VR loads before Start; Exit restores the flat game and its settings. |
| Desktop window | Mirrors the left eye. |
| Milestone 1 | **RTX in the headset** (the runtime spike) before anything else. |
| Shipping | On the `vr` branch until the user approves; flat-mode checks prove a new runtime changes nothing with VR off. |

## What gVRMod is, and what we can use from it

Read at gVRMod `6c0b9e5f` (2026-11-02) with its Lua add-on, the submodule vrmod-x64, at `6f980f16` (2026-11-02);
clones in `out/vr-plan/src/` (git-ignored). Its OpenVR module lives in a third repository, vrmod-module-master (not
read).

- **Pieces.** An OpenXR module in C++ (about 10,000 lines: `src/rendering/openxr`, `src/input/xr_input.cpp`,
  `src/lua/lua_interface.cpp`), the Lua add-on (144 files, about 60,000 lines) and the separate OpenVR module.
- **Licence.** All three are under "CUBECHAIN 1.0", which GitHub cannot classify: it allows use, change,
  distribution and sale, but every copy and derivative must carry its full text and a link to the repository, and it
  adds "Obey The Cube Law", "Do not corrupt the core with money" and "ensure it is not used for evil". The Lua descends
  from Catse's original VRMod (Workshop 1678408548) and Pescorr's semi-official VRMod (2780083257). Catse's module is
  zlib-licensed (2019; mirrored at github.com/samueldoodoo/vrmod-module, and Pescorr's altered module keeps that
  licence); no licence is stated for their Lua. Hence the decision above.
- **How it renders.** Each eye is drawn with `render.RenderView` into one side-by-side render target
  (`lua/vrmod/core/cl_vrmod.lua`, `PerformRenderViews`). On Windows a one-shot inline patch of
  `IDirect3DDevice9::CreateTexture` (vtable slot 23) gives that target an NT shared handle, which a separate D3D11
  device opens and submits (`src/rendering/d3d/d3d_hooks.cpp`, from Catse's module). **Under our runtime this cannot
  show RTX**: the runtime path traces one camera per frame into the target bound when path tracing ends
  ([ADR 0136](../decisions/0136-arc9-scopes-path-traced.md), "What ends path tracing for a frame"), and draws into
  other targets are rasterized ([ADR 0122](../decisions/0122-raster-canvases-keep-their-native-draws.md)). The headset
  would get raster pictures. The runtime's raytraced render targets (ADR 0136) are windows into the one traced frame,
  not a second picture. Stereo therefore has to be built into the runtime fork.
- **How it shows UI.** Panels are painted into render targets (`PaintManual`) and drawn as quads with
  `cam.Start3D2D` (`ui/cl_ui.lua`, `ui/cl_panel2vr.lua`); the HUD is painted into `vrmod_hud_paint` (`ui/cl_hud.lua`).
  Under RTX a perspective draw is a lit object to the runtime (ARC9's HUD card, R25), and the path tracer does not
  show a render target's pixels. Hence SteamVR overlays for every piece of VR UI.
- **Highlights.** Its pickup highlight uses `halo`; the render guard turns `halo.Render` off under RTX
  (`companion/nativeloader/lua/autorun/_nativeloader_guard.lua`, `installPost`). Our highlights need another way (an
  overlay marker or an emissive outline draw; to try).
- **What to read for behaviour** (not to copy): physical hand proxies, a server physics sphere or box per hand that
  pushes props (`physics/sv_collision_proxies.lua`); the hands' push-out from walls (`utils/sh_collisions.lua`);
  pickup, with ragdoll bone offsets and NPC death ragdolls (`pickup/sh_pickup.lua`, `utils/sh_pickup.lua`); climbing
  (`input/sh_climbing.lua`); locomotion (`input/sh_locomotion.lua`); the foregrip (`player/cl_foregrip.lua`); melee
  (`combat/sh_combat.lua`); SteamVR bindings (`input/cl_steamvr_bindings.lua`); character IK, of Pescorr's two-bone IK
  lineage (`utils/cl_character_ik.lua`); panels with a laser (`ui/cl_panel2vr.lua`); the HUD, keyboard, quick menu
  and weapon select (`ui/`).
- **Lessons it records** (`state/polish_loop/PAIN_POINTS.md` in gVRMod): it pins `mat_queue_mode 1` in VR and never
  2; it keeps one pose pipeline (raw, tracking, modifiers), never two; hand collision must not fight a climbing grip
  (floor and ceiling are not walls for the hands); never nest `render.RenderView` while a VR target is pushed
  (`drawmonitors = false`); keep the desktop mirror a framed window.

## This machine

SteamVR is installed (`C:\Program Files (x86)\Steam\steamapps\common\SteamVR`, build 1792185270, drivers including
`indexhmd`, `lighthouse` and `null`) and was running at planning time; it is the active OpenXR runtime. The user's
Valve Index is connected; nobody wears it during tests. GPU: RTX 5090 (32 GB). The runtime's source tree is
`out/worktrees/r17/out/runtime-src` (fork commit `17dcc86c`). It already carries OpenVR's header and DXVK's OpenVR
helper (`src/dxvk/dxvk_openvr.cpp`), which asks SteamVR for the Vulkan extensions it needs, but only if
`openvr_api.dll` is already loaded when the device is created (`GetModuleHandle`, line 309): at a normal start it is
not.

## Architecture

```
SteamVR (vrserver, vrcompositor)
   ^ Submit: Vulkan eye images + pose; overlay textures      ^ WaitGetPoses, input, haptics, overlays
   |                                                         |
d3d9.dll: runtime patch "VR output"  <---- frame info ----  gmcl_nlvr_win64.dll: module (MIT, this repo)
   renders a VR-sized centre view, warps it to the eyes,      OpenVR session, SteamVR Input, overlays,
   submits, mirrors the left eye into the window,             test mode; Lua API nlvr.*
   feeds overlays from the game's render targets
   ^                                                         ^
   +-------------- draw calls ---- GMod (engine and Lua) ----+
                       nlvr add-on (loaded at Start VR): view from the head, hands, interaction,
                       movement, weapons and tools, HUD and panels, networking
                       RTX tab, VR page (companion, always loaded, does nothing until Start VR)
```

### Who owns what

- **The module** (`gmcl_nlvr_win64.dll`, MIT, built here) owns the OpenVR session. At Start VR, never before, it
  loads `openvr_api.dll` (Valve, BSD-3-Clause, shipped in the VR part with its licence), calls
  `VR_Init(VRApplication_Scene)`, sets the SteamVR Input action manifest and the default bindings shipped beside it,
  calls `WaitGetPoses` once a frame for pacing, drives haptics, creates and places overlays and handles SteamVR's
  events (dashboard opened, quit, headset taken off). It hands the runtime the interface pointers it needs
  (`IVRSystem`, `IVRCompositor`, `IVROverlay`) through a small C API the runtime exports (`rtxvr_*`), so
  `openvr_api.dll` is loaded once, by the module, and the runtime never starts SteamVR.
- **The runtime** owns pictures: the VR output mode below, the overlay textures, the mirror and VR frame
  statistics. It is dormant until the module attaches.
- **The add-on** (`nlvr`, Lua) owns the game: the view at the head, the hands, interaction, movement, weapons and
  tools, painting the HUD and panels into render targets, networking.
- **The companion** owns the switch: the VR page in the RTX tab and the commands `nl_vr_start` and `nl_vr_exit`.

### The runtime's VR output mode (patch; milestone 1)

1. **Device prerequisites.** SteamVR needs some Vulkan extensions
   (`IVRCompositor::GetVulkanInstanceExtensionsRequired` and `GetVulkanDeviceExtensionsRequired`), and the device
   exists long before Start VR. The runtime enables the external memory and semaphore extensions SteamVR asks for on
   Windows whenever the GPU has them; unused, they cost nothing. At Start VR the module compares SteamVR's lists with
   the device's; if one is missing, the VR page says a restart is needed, with a runtime option set for the next start
   (`rtx.vr.prepareDevice`, name to settle). Spike S1 records what SteamVR asks for on this machine.
2. **A VR-sized target.** `RtxContext::injectRTX` takes its output size from the image bound when path tracing ends
   (`src/dxvk/rtx_render/rtx_context.cpp:510-619`). In VR mode it is given the runtime's own centre-view image instead,
   sized to cover both eyes at SteamVR's recommended density (`IVRSystem::GetRecommendedRenderTargetSize`, which
   includes the player's SteamVR resolution setting; roughly 2016 x 2240 per eye on an Index at 100 %, to be read) times
   the VR preset's scale. DLSS renders below that as usual. Start and Exit VR recreate resources as a window resize
   does.
3. **Camera.** Position and orientation come from the game's camera, which the add-on puts at the head; the projection
   comes from the headset (`GetProjectionRaw` for each eye and `GetEyeToHeadTransform`). Phase 1 uses one symmetric
   frustum from the centre eye that covers both eyes' frusta. The add-on sets the game's field of view wide in
   `CalcView` so the engine culls nothing an eye sees (to check: at 16:9 a horizontal FOV of about 140 degrees covers
   about 114 vertically). Spike S6 checks that the runtime still classifies this camera as the main camera (no camera
   cut every frame, no view-model camera).
4. **Warp to the eyes (phase 1).** A compute pass per eye samples the final centre image backwards along the eye's
   horizontal offset (half the IPD from `GetEyeToHeadTransform`, in game units) with the primary surface's depth,
   taking the farther surface where the centre view saw none. Right for head rotation and for distance; approximate
   near the hands, which phase 2 fixes.
5. **Submit.** `IVRCompositor::Submit` per eye with `VRVulkanTextureData_t` and the pose the frame was rendered for
   (`Submit_TextureWithPose`), under DXVK's submission lock (`DxvkDevice::lockSubmission`, `dxvk_device.h:552`, what
   the D3D11 interop path uses), then `PostPresentHandoff`.
6. **Mirror.** The left eye, scaled and cropped into the game's own target: the desktop window shows it.
7. **Overlays.** `rtxvr_SetOverlaySource(overlay, IDirect3DTexture9*)` registers a game render target; when it
   changed, the runtime copies it into an overlay image and calls `IVROverlay::SetOverlayTexture` (Vulkan). The wrist
   HUD, the panels and the flat-screen panel reach SteamVR this way and are never path traced. Painting into such a
   target is a raster canvas draw, which keeps its native draws (ADR 0122).
8. **A VR option layer.** While VR runs, the preset's Remix options (DLSS mode, path-tracing quality, costly effects)
   sit in one runtime layer that Exit VR removes, so the player's own settings come back untouched. DLSS Frame
   Generation is off in VR.
9. **Which pose belongs to which frame.** With queued rendering (`mat_queue_mode 2`, common in RTX sessions; see
   `cl_rtx.lua`'s model flush in the fixes) the runtime presents frame N while Lua builds frame N+1. The module passes
   each frame's head pose and eye data through the material system's call queue (`IMatRenderContext::GetCallQueue`,
   which runs on the render thread in order with that frame's draws), so the pose submitted is the one the frame was
   rendered for. Spike S4 finds the call queue on GMod x64. If it is out of reach: `mat_queue_mode 1` while VR runs
   (gVRMod's choice), the player's value put back at Exit.
10. **Off.** No `openvr_api.dll`, no VR images, no per-frame VR work; only the device extensions of point 1.

### The module `gmcl_nlvr_win64.dll`

- Lua API (`nlvr.*`): `Start` and `Stop`; poses (head, hands, all tracked devices) in tracking space; actions
  (booleans, axes, the Index's grip force, skeletal finger curls); haptics; overlays (create, place: absolute,
  head-relative or attached to a controller; show, hide, size, alpha; laser hit tests); SteamVR facts for the VR page
  and the performance preset (model, refresh rate, recommended size, IPD, `IVRCompositor::GetFrameTiming`); events.
- SteamVR Input: an action manifest and default bindings for the Index controllers, Touch (Quest through Steam Link)
  and Vive wands, shipped in the VR part; players remap in SteamVR's own binding UI.
- **Test mode**: a timeline file (JSON under `out\`) replaces the head and hand poses and the button states, so tests
  drive grabbing, throwing, gravity gloves, teleport, reload or menus without a person; the real headset still
  receives every frame.
- Native code rules: the module is ours and ships in our allowlisted package
  ([ADR 0003](../decisions/0003-native-trust-allowlist.md)); its build is recorded like the repository's other modules
  ([ADR 0126](../decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)). No loader change is
  expected.

### The add-on and the VR page

- **The VR page** (companion, a new "VR" category in the RTX Remix tab, translated like the rest of the tab): Start VR
  and Exit VR; status (SteamVR found and running, headset model, refresh rate, recommended size, controllers); the
  GPU warning (below 12 GB or the low tier); the quality preset (Auto and fixed levels) with frame times and the share
  of reprojected frames; comfort (movement and turn modes, snap angle, vignette, seated mode, height calibration);
  dominant hand; HUD options; the Alyx mechanics' switches (gravity gloves, physical reload); a link to SteamVR's
  binding UI. While VR is off the page is the only VR code loaded: it adds no hook that runs per frame.
- **The add-on** (`nlvr`, deployed as `garrysmod/addons/nlvr`) loads its files at Start VR and removes its hooks at
  Exit VR. Server files run where our package runs the server (single-player and the listen host).
- If VRMod or gVRMod is installed and active (both would drive the view), Start VR refuses and says which add-on to
  turn off.

## Interaction design: Alyx-like, for the sandbox

### Default controls on the Index (right-handed; mirrored for left-handed)

| Control | Left hand | Right hand |
|---|---|---|
| Grip (squeeze) | Grab; gravity gloves (point, grip, flick) | Grab; gravity gloves |
| Trigger | Use by hand, laser click on panels, off-hand actions | Fire, tool primary, use by hand, laser click |
| Stick | Move (direction from the hand or the head) | Snap turn; up (hold) teleport arc; down crouch toggle |
| Stick click | Sprint | Flashlight (on the off hand's wrist) |
| A | Jump | Eject magazine; tool secondary; physgun freeze |
| B | Wrist menu (spawn menu, context menu, settings) | Tap: tool reload; hold: weapon wheel |

A starting proposal; SteamVR's binding UI can change everything.

### Hands

- **Models**: GMod's hands for the player model (`player_manager.TranslatePlayerHands`, the `c_arms` models), posed
  from the Index's finger tracking (skeletal input); a grab closes the fingers around what is held.
- **Physical hands**: on the server each hand has a physics proxy that follows the controller by velocity, so hands
  push props, ragdolls and NPCs and stop at walls (gVRMod's proxy idea, our code). Floor and ceiling do not stop a
  climbing grip.
- **Ghost hands**: a blocked hand is drawn at the surface where it stopped, with a faint outline where the controller
  really is (how the outline draws under RTX is a thing to try: an emissive translucent draw, or an overlay).

### Holding things

- **Grab and throw**: grip grabs the nearest prop within reach at the point touched; it follows the hand physically,
  so a heavy prop lags behind and nothing passes through walls; two hands for big props; letting go throws with the
  hand's velocity and spin, averaged over the last frames.
- **Gravity gloves**: point at a loose prop within range, hold grip (the target is marked, without `halo`), flick
  the wrist toward you: the prop flies to the hand on an arc, and grip still held catches it.
- **Ragdolls**: grab the nearest physics bone and drag or pose it, with two hands; NPCs' death ragdolls too. Living
  NPCs can be pushed, not grabbed.
- **Use by hand**: touch or grab buttons, doors, levers and other usable entities to use them; no use key.
- **Climbing**: grip a ledge, ladder or wall edge to climb; the body follows the hands' movement; letting go of both
  falls. A teleport onto a ledge mantles.
- **Melee**: punches and held melee weapons damage what they hit, scaled by hand speed.

### Weapons and tools

- **Hand-aimed weapons**: each weapon is a model in the hand, drawn as world geometry, never through the engine's
  view-model pass: the runtime draws view models with their own camera and scale (R25), which would be wrong in VR.
  Shots leave along the gun; on our own server from the muzzle, on other servers through the player's aim.
- **Two-handed grip**: the off hand on a rifle's foregrip aims it along the line between the hands.
- **Physical reload** for the HL2 weapons: eject with A, take ammo from over the shoulder, put it into the gun's
  magazine well (shotgun shells one by one, the crossbow's bolt, the RPG's rocket); every other weapon reloads on
  tap B.
- **Ammo on the gun**: a small counter overlay attached to the weapon hand.
- **Weapon wheel**: hold right B, point at a weapon or tool, release.
- **Physgun**: the trigger grabs; the held prop turns with the hand; the stick pushes and pulls; A freezes.
- **Toolgun**: aimed by the hand; the tool is chosen in the wrist menu's tool panel; trigger and A are its primary and
  secondary.
- **Spawn and context menus**: floating panels in front of the player (overlays) used with a laser from the right
  hand; the context menu's world clicks (properties) aim with the hand's ray.
- **Flat-screen panel**: any 2D screen the add-on does not convert (the escape menu, the console, other add-ons'
  windows) can be shown on a floating panel with the laser as mouse, so nothing leaves the player stuck.
- **Keyboard**: SteamVR's own keyboard.

### Movement and comfort

- Smooth movement on the left stick (hand or head direction), snap turn on the right (angle settable), smooth turning
  as an option.
- Teleport: blink (fade) or shift (a quick dash) along an arc from the hand; also mantles onto ledges.
- Physical crouching, plus a crouch toggle; jump and sprint on buttons.
- Vignette while moving or turning: a head-locked overlay, so it costs no path tracing.
- Seated mode with a height offset; height calibration (stand straight, press a button) for the world's scale.
- Noclip flight in the hand's direction, speed on the trigger.

### HUD and panels

- Wrist HUD on the left wrist (shows when you look at it): health, armour, the weapon hand's ammo, the current tool,
  notifications, a clock. Panels open from the wrist menu. All are SteamVR overlays fed from render targets the add-on
  paints (runtime point 7).
- The flat HUD (`HUDPaint` and the default HUD elements) is not drawn into the eyes while VR runs.

### Body

- Hands only in the player's own view. A player model posed by IK from the head and hands (two-bone arms, a spine
  that follows the head, legs that step and crouch) casts the player's shadow and shows in mirrors and reflections,
  through the runtime's player-model handling, never in primary view; this extends the local body proxy of
  [ADR 0043](../decisions/0043-player-body-viewmodel-and-shadows.md).

### Multiplayer

- **Full mode** wherever our package runs the server side: single-player and the listen-server host. Other players
  with the package see a VR player's head and hands.
- **Limited mode** on other servers: the view at the head, local hand models, the HUD and panels, movement and turning
  through the user command, and firing along the gun by setting the player's aim while firing; no physical hands,
  grabbing, gravity gloves, climbing or physical reload (the server would have to do those). Our client scripts reach
  a remote server's client realm only through the verified bootstrap
  ([ADR 0052](../decisions/0052-scoped-rtx-multiplayer-bootstrap.md)); whether it can carry the VR add-on is a
  question for the loader (loader changes need the user's approval).

## Performance

- **Inputs**: the GPU's performance tier and memory profile
  ([ADR 0062](../decisions/0062-loader-layers-performance-tiers-and-gpu-dumps.md),
  [ADR 0101](../decisions/0101-memory-profiles.md)); SteamVR's recommended size and refresh rate (the Index offers 80,
  90, 120 and 144 Hz); measured frame timing (`IVRCompositor::GetFrameTiming`: GPU time, missed and reprojected
  frames).
- **Preset ladder**: render scale on top of SteamVR's size, DLSS mode (down to Ultra Performance), path-tracing
  quality (bounces, sample counts), costly effects (volumetrics, the sky's cloud detail). Auto starts from the tier
  and moves one step at a time with hysteresis: down when frames keep missing the half rate, up when there is
  headroom.
- **Target**: half the refresh rate (45 frames a second at 90 Hz) with SteamVR's Motion Smoothing filling in; the VR
  page suggests 80 or 90 Hz for RTX.
- **Warnings**: below 12 GB of VRAM or on the low tier the page warns and Auto starts at the lowest step; nothing is
  blocked.
- **The game's own frame**: GMod's CPU time must keep up too. Add-ons that lag the flat game lag VR more, and R28's
  lag safeguards (the main thread's current round) help here.
- **VRAM**: VR-sized targets are larger than a 1080p window's; the presets account for the memory profile.

## Testing without a person in the headset

- **The headset is real but unworn**: its proximity sensor reports nobody, the head pose is fixed (or invalid if the
  base stations cannot see the headset), the controllers may sleep, and SteamVR may dim or idle the display and change
  how often `WaitGetPoses` returns. Spike S5 measures this; tests check frames submitted and their timing, not what the
  display shows.
- **One VR test at a time**: a VR lock under `out\` (for example `out\vr\vr.lock`), separate from the PoC lock,
  because SteamVR shows one scene application at a time. The user makes sure no other Claude session uses the PoC when
  VR work starts. SteamVR's settings are not changed.
- **Scripted input**: the module's test mode (above) drives head and hands from a timeline; Lua probes check the
  outcome (a prop's position after a throw, ammo after a reload, the player's position after a teleport).
- **Pictures**: a runtime test option saves the submitted eye images and the overlay images to `out\` on request;
  the mirror window gives a third view.
- **Flat-mode parity**: with VR off, the new runtime and the VR page must change nothing: the usual PoC screenshots and
  frame times before and after.
- **Offline**: LuaJIT harness tests for the maths (IK, throws, gestures, teleport arcs, comfort), C++ tests for
  the projection union and the warp's maths on synthetic depth, the module's API against a mock of OpenVR's
  interfaces.
- A test driver `tools/vr_session.py` on top of `tools/poc_session.py` (snapshot, roll back, the VR lock, the
  timeline, image collection).

## Milestones

| | Milestone | Done when |
|---|---|---|
| V1 | **RTX in the headset** | Start VR from the VR page shows the path-traced view in the Index: the centre view warped to both eyes, following scripted head poses; the compositor receives every frame (frame timing, no errors); the desktop window mirrors the left eye; a wrist HUD overlay with health, armour and ammo follows the left controller; Exit VR returns to the flat game with its settings; flat-mode parity holds; spikes S1-S8 settled and recorded |
| V2 | Hands, movement, menus | Finger-tracked hands; ghost hands; smooth movement, snap turn, teleport (blink and shift), comfort options, noclip flight, physical crouch, height calibration; spawn and context menus and the flat-screen panel with the laser; dominant hand |
| V3 | Physical interaction | Physical hands against props, ragdolls and NPCs; grab, two-hand grab and throw; gravity gloves; ragdoll handling; use by hand; climbing; melee |
| V4 | Weapons and tools | Hand-aimed weapons; foregrip; physical reload for the HL2 weapons and the button reload; ammo on the gun; weapon wheel; physgun and toolgun controls |
| V5 | Body and multiplayer | **Skipped** (the user, 2026-11-13): VR is single-player only ([ADR 0197](../decisions/0197-vr-is-single-player-only.md)) |
| V6 | Performance | The Auto preset and its ladder tuned on the Index at 80, 90 and 120 Hz; the page's warnings and readouts |
| V7 | True stereo | Each eye path traced with its own history as a quality mode, after a design spike: two passes per frame or one double-wide picture |

Each milestone ends with its handover report, an independent review and the user's approval before the merge.

## Spikes for V1 (the hard part first)

| | Question | How to settle it |
|---|---|---|
| S1 | Which Vulkan extensions does SteamVR ask for, and does the runtime's device have them? | Query both lists at Start VR on this machine; record them in RESEARCH |
| S2 | Can `injectRTX` render into a VR-sized image while the window keeps its size? | Patch, then compare its pictures and timings with the flat game |
| S3 | Does `Submit` from DXVK's queue under `lockSubmission` work without stalls? | Frame timing from SteamVR; the compositor's own stats |
| S4 | Can the module reach the material system's call queue on GMod x64? | Find `GetRenderContext` and `GetCallQueue` in the interfaces; otherwise measure `mat_queue_mode 1` |
| S5 | How does an unworn Index behave (pose valid, standby, how often `WaitGetPoses` returns)? | A test session with logging over 10 minutes |
| S6 | Does a wide game FOV with the runtime's projection keep the camera "main" (no cut every frame, no view-model camera)? | The runtime's camera log and its debug views |
| S7 | What does the centre view plus warp cost at the Index's size on the RTX 5090? | GPU times by pass at 80 and 90 Hz targets |
| S8 | Can overlay textures come from D3D9 render targets through the runtime? | The wrist HUD's target shown in SteamVR, and saved to `out\` |

## Files to add (proposal)

| Path | What |
|---|---|
| `vr/native/` | The module (CMake; a README naming each source, as every module folder has) |
| `vr/addon/` | The Lua add-on, deployed as `garrysmod/addons/nlvr` |
| `vr/input/` | SteamVR's action manifest and default bindings (Index, Touch, Vive) |
| `companion/nativeloader/lua/autorun/client/nativeloader_vr.lua` | The VR page and `nl_vr_start` / `nl_vr_exit` |
| `runtime/patches/00NN-VR-output*.patch` | The runtime's VR output mode (exported one at a time) |
| `packages/vr/` | A new package part: the module, the add-on, `openvr_api.dll` with OpenVR's BSD-3-Clause licence, the bindings |
| `third_party/openvr/` | OpenVR's headers and licence for the module's build |
| `tools/vr_session.py` | The VR test driver with the VR lock |

Docs to add while implementing: decision records (the VR architecture and phase 1's warp; UI through overlays; the
controls; the performance presets; the limited multiplayer mode), CHANGELOG, COMPONENTS (new folders), ROADMAP (a VR
line), RESEARCH (measured facts), TESTING, a handover report per milestone, and the player guide's pages.

## Not decided yet

- The Index's default refresh rate for RTX VR (80 or 90 Hz), from V6's measurements.
- Whether the hands are the player model's `c_arms` or dedicated gloves.
- Phase 2's approach (two passes or a double-wide picture), after its design spike.
- How the gravity gloves' target and the ghost hands' outline draw under RTX.
- Whether the verified multiplayer bootstrap can carry the VR add-on (limited mode).
- What the VR page's text says in the companion's languages (translated with the page).
