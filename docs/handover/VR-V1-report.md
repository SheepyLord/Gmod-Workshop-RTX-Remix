# VR V1 report: RTX in the headset

Milestone V1 of [VR-plan.md](VR-plan.md), asked for by the user on 2026-11-10 and built the same day on the branch
`vr` (worktree `out\worktrees\vr`). **The user looked with the headset on and approved V1 the same evening; it
was then merged into `main` as one commit, which the hooks publish to the Workshop item** ("Approval and merge" at
the end). Until that approval nothing of it was on `main`, pushed or published. No loader change was needed.
`main` was merged *into* `vr` once before, so that the branch was current (the Hotloader import fixes, Seamless
Portals, the two maps' removal). The sections below are the report as the user had it when deciding, with the
look's instructions corrected.

Claude directed and reviewed; Codex (`gpt-6.1-sol`, reasoning effort max, priority tier, as the user asked for the VR
work) wrote the code in five tasks, each on its own branch with a brief and a report: the SDK pin and the probe
([brief](VR-V1-A-sdk-and-probe.md), [report](VR-V1-A-report.md)), the runtime's VR output
([brief](VR-V1-C-runtime.md), [report](VR-V1-C-report.md)), the module ([brief](VR-V1-D-module.md),
[report](VR-V1-D-report.md)), the add-on and the page ([brief](VR-V1-E-addon-and-page.md),
[report](VR-V1-E-report.md)) and the integration ([brief](VR-V1-Q-integration.md), [report](VR-V1-Q-report.md),
[after the first review](VR-V1-Q-review-report.md), [after the second](VR-V1-Q-runtime-review-report.md)). The
interfaces they were built against are in [VR-V1-plan.md](VR-V1-plan.md); the decisions are records 0145 to 0151 and
0156 to 0158 in [docs/decisions](../decisions/README.md). Two independent Claude subagents reviewed the result
(below), and Claude ran the final build itself at the end (the numbers marked "Claude's check").

## What V1 does

Start VR on the new VR page of the RTX Remix tab (or `nl_vr_start`) puts the path-traced game into the headset:

- The runtime path traces **one centre view** sized to cover both eyes at SteamVR's recommended density, warps it
  to a left and a right eye image with the primary surface's depth, and submits both to SteamVR with the pose the
  frame was rendered for. The game window keeps its size and shows the left eye, with the game's own 2D on top.
- The module `gmcl_nlvr_win64.dll` owns the OpenVR session (loaded only at Start VR), gives Lua the head and hand
  poses predicted for the moment the frame will be shown, and hands each frame's pose to the runtime together with
  the game camera it belongs to. The runtime paces the frames itself: it waits for the compositor right after
  submitting, so the game runs at the headset's rate where the scene allows.
- The add-on puts the game's view at the head, leaves the first-person weapon model and the body proxies out, and
  shows a **wrist HUD** (health, armour, ammo) as a SteamVR overlay on the left controller. `nl_vr_recenter` (and a
  button) takes the standing position and the forward direction again.
- **The VR page** has Start VR and Exit VR, says whether SteamVR is installed and running, names the headset with
  its refresh rate and recommended size, warns on a GPU with less than 12 GB or a low performance tier, and while
  VR runs shows the compositor's and the runtime's frame times (total, tracing, upscaling, warp) and the frames
  submitted, refused and matched. It is translated like the rest of the tab (French, Japanese, Korean, Russian,
  Simplified and Traditional Chinese). `nl_vr_start` and `nl_vr_exit` do the same from the console.
- Exit VR (the page, `nl_vr_exit`, a SteamVR quit, leaving the game) returns to the flat game: OpenVR is shut
  down and unloaded, the runtime's VR images and its option layer go, and no setting of the player's is left
  changed.
- With VR off nothing runs: no `openvr_api.dll`, no thread or timer, no per-frame work, the add-on's files not
  loaded. Only the VR page exists.

Not in V1, by plan: hands, moving and turning by controller, menus in VR (V2); grabbing and physics (V3); weapons
and tools (V4); the body and multiplayer (V5); the automatic preset (V6); true stereo (V7). In V1 the player moves
and turns with the keyboard and the mouse.

## What works and what does not

Everything below was shown on the user's Valve Index through SteamVR, with nobody wearing it: the headset sat on
its stand, the controllers were asleep, and head, hands and buttons came from the module's test mode, except in the
runs that used the headset's real tracking. It is judged by the frames SteamVR accepted, their timing and saved eye
images, never by the display.

**Works:**

- **Start VR and Exit VR**, from the page and from the console, repeatedly in one game. Start takes 2.7 to 3.0 s
  with SteamVR already running (SteamVR is started when it is not); the game stays responsive meanwhile. Exit
  takes under 0.2 s. After Exit the flat game has the frame time it had before (Claude's check: 10.3 ms before,
  10.0 ms after), `openvr_api.dll` is unloaded, no hook or timer of the session is left, and all checked settings
  read as before (14 game variables, and the runtime's live upscaler and frame generation choice: frame generation
  is off in VR and back on after).
- **Frames reach the headset and belong to their pose.** In the final 310 s run on gm_construct SteamVR accepted
  26,199 eye pairs, refused none, and none went out with a pose that did not match its camera. A scripted head
  turn of +/-20 degrees moves the eye images by +20.2 and -20.3 degrees, a 0.2 m lean shifts them 77.5 pixels where
  the geometry says 76.3 (measured on the first integrated build; the final build's captures show the same turns
  and lean). The first frame of a session already has the headset's projection and a matched camera.
- **Both eyes show near things at their true width.** After the second review's fix a barrel 284 pixels wide in the
  centre view is 284 and 281 pixels wide in the eyes (it was 270 and 269 before the fix).
- **The game window** shows the left eye; the game's HUD, menus and console are on the window and in neither eye
  (a marker painted on the HUD: 4,255 pixels in the window, 0 in each eye).
- **The wrist HUD** reaches SteamVR as an overlay on the left controller, shows the real health, armour and ammo
  and follows them, with queued rendering on and off.
- **Leaving in every way:** Exit VR; a SteamVR quit, also while the single-player game is paused (9.4 s of wall
  time, 0.013 s of game time); quitting the game while in VR; a listen-server host with `fps_max 60` (the page then
  says what to type, VR still runs).
- **Failures that must not take the game down:** a refused start names its reason on the page (in the game with
  a runtime that has no VR output; no SteamVR, no headset and a running VRMod with stand-ins, offline); an image
  allocation failure, injected at three places, ends Start with a reason; a loss of focus to another VR
  application, injected, skips frames and resumes.
- **The headset's real tracking**, unworn: 908 pairs in one run and 2,165 in another, none refused, none unmatched.

**Does not work, or is not known:**

- **Nobody has looked through the lenses.** Scale (`nl_vr_scale`, 40 units a metre), comfort, how depth edges look,
  where the wrist HUD sits on an awake controller, and SteamVR's Motion Smoothing are all unjudged. This is the
  first thing to settle ("How to look for yourself").
- **The headset's rate is held only on a light map on an otherwise idle GPU:** 85 frames a second on gm_construct
  at 90 Hz, 30 on Modern House. With another game using the GPU (Claude's check) gm_construct ran at a steady 45,
  every second frame filled in by SteamVR. See "What it costs".
- **Thin outlines at depth edges.** One centre view cannot show what one eye sees behind a near object; there the
  warp keeps the background it has. The centre view covers things from half a metre away; nearer than that an eye
  can see past its edge. True stereo is V7.
- **Controllers do nothing yet.** The module reads SteamVR Input (20 actions, with bindings for the Index, Touch
  and Vive controllers) and every read succeeded, but the controllers were asleep, so no physical press was seen,
  and V1's add-on uses the controllers only to place the wrist HUD. Moving, turning and hands are V2.
- **Other add-ons' cameras are held while VR runs.** The session owns the game's view; a camera add-on's
  `CalcView` hook is put back at Exit.
- **`fps_max` below the headset's rate limits VR**, and Lua may not change it: the page says what to type.
- **Not tested:** other headsets and their controllers (offline validation of the bindings only), an AMD or Intel
  GPU, moving the IPD slider on the headset (the code path is tested without hardware), another VR application
  really taking the focus, 80 Hz (derived, as agreed).
- **If SteamVR stops answering during Exit,** Exit waits for it without a time limit.
- **An old start-up crash in NVIDIA's driver** showed up during the tests, with the published runtime as well as
  with the new one. It is not VR's ("With VR off").

## The spikes

Each was settled on the user's Index (unworn, on its stand) and this RTX 5090; the numbers with their sources are in
[RESEARCH](../RESEARCH.md) (VR V1) and in the tasks' reports.

| | Question | Result |
|---|---|---|
| S1 | Which Vulkan extensions does SteamVR ask for, and does the runtime's device have them? | SteamVR asks for six instance and seven device extension names here. The published runtime's device lacked two and three of them (`VK_KHR_external_fence_capabilities`, `VK_NV_external_memory_capabilities`; `VK_KHR_timeline_semaphore`, `VK_KHR_dedicated_allocation`, `VK_KHR_win32_keyed_mutex`), and had a sixth (`VK_KHR_get_memory_requirements2`) only because the FSR library was there; the GPU offers all of them. The runtime now enables the six at device creation when the GPU has them, and Start VR compares SteamVR's lists with the device's and names what is missing |
| S2 | Can the runtime path trace a VR-sized picture while the window keeps its size? | Yes: eyes of 2468 x 2740, a centre view of 3072 x 2752 traced at 1536 x 1376, in a 1280 x 720 window. At equal output size (2392 x 2160) the flat game ran at 128.15 frames a second and the centre view with the warp, without Submit, at 128.20 |
| S3 | Does Submit from the runtime work without stalls? | Submit itself does (0.2 ms of CPU for both eyes, under DXVK's submission lock). What failed was the order: with `WaitGetPoses` on the game thread the compositor refused 139 eye images of 6,436 frames (`AlreadySubmitted`). With the runtime pacing itself, the final run: 26,199 frames in 310 s, none refused, none unmatched |
| S4 | Can the module reach the material system's call queue? | Not through its public interface: on this game build the queue is a private arena (360 guarded attempts, no callback ran). The PoC runs `mat_queue_mode 2`. Each frame's pose is found by matching the frame's camera instead; no frame went unmatched in any accepted run |
| S5 | How does an unworn Index behave? | Its pose stays valid (the base stations see it), it goes to standby after about five seconds, and `WaitGetPoses` keeps the refresh rate in standby: 89.7 calls a second over ten minutes without Submit, 89.0 over fourteen minutes with it (149,526 eye images accepted, no error; 292 dropped and 1,700 reprojected frames while builds ran beside it). SteamVR did not quit under a running scene application |
| S6 | Does a wide game field of view with the runtime's projection keep the camera the main camera? | Yes. The engine culls with 145 degrees at 16:9; the two eyes together need 114.1 x 109.4 degrees. No camera cut after a session's first frame in any run. The turn and lean figures are above |
| S7 | What does the centre view plus the warp cost? | See "What it costs": the warp is 0.56 ms of a 9.7 ms frame |
| S8 | Can overlay textures come from game render targets through the runtime? | Yes, found by their exact size. The wrist HUD's 769 x 257 target reaches SteamVR (visible, no error), shows the real values and follows their changes |

## What it costs

The fixed V1 preset: SteamVR's recommended size at scale 1 (2468 x 2740 an eye; SteamVR chose 150 % for this GPU by
itself), a centre view of 3072 x 2752 path traced at 1536 x 1376 with DLSS Performance and Ray Reconstruction, one
to four bounces, frame generation and the camera and post effects off, all in a layer that exists only while VR
runs ([ADR 0151](../decisions/0151-the-fixed-v1-vr-preset.md)). `nl_vr_render_scale` (on the page) scales the size.

GPU time by pass, in milliseconds a frame, RTX 5090, driver 617.42, Index at 90 Hz. The first two columns are the
final runs on an idle GPU (0 to 1 % before the launch), 310 s on gm_construct and 120 s on Modern House, steady
state after the first minute. The third is Claude's check of the same build, 310 s, while another game was using
the GPU (11 to 25 % of it by itself): the passes are the same, each waits its turn longer.

| Pass | gm_construct | Modern House | gm_construct, GPU shared |
|---|---:|---:|---:|
| Scene preparation and acceleration structures | 0.350 | 0.561 | 0.354 |
| Path tracing and volumetrics | 6.128 | 10.705 | 8.064 |
| Demodulation and composition | 0.354 | 0.385 | 0.469 |
| DLSS with Ray Reconstruction | 2.029 | 2.175 | 3.003 |
| Post-processing and tone mapping | 0.267 | 0.286 | 0.341 |
| Warp to both eyes | 0.558 | 0.645 | 0.778 |
| Mirror, Submit, late raster | 0.063 | 0.064 | 0.109 |
| **All passes** | **9.749** | **14.820** | **13.117** |
| Game thread / render thread CPU | 4.27 / 2.94 | 14.21 / 8.51 | not taken / 4.44 |
| **Frames a second at 90 Hz** | **85** | **30** | **45** |
| Frames SteamVR filled in (reprojected) | 8.6 % | 79 % | 50 % |
| Eye pairs accepted / refused / unmatched | 26,199 / 0 / 0 | 3,782 / 0 / 0 | 13,925 / 0 / 0 |

- **90 Hz, measured.** A 90 Hz frame has 11.1 ms. gm_construct's 9.7 ms of GPU work fits, with nothing to spare:
  on the idle GPU it holds 85 frames a second, and with another game on the GPU the work grows to 13.1 ms and
  SteamVR settles the game at a steady half rate, 45, with no dropped frame and no refused image. Modern House
  fits neither way: the GPU needs 14.8 ms and the game thread alone 14.2 ms.
- **80 Hz, derived** (the headset stayed at 90 Hz, as agreed). An 80 Hz frame has 12.5 ms. Carrying the measured
  cadence over gives about 75 frames a second on gm_construct and 27 on Modern House; gm_construct's work and its
  11.7 ms from frame start to hand-over both fit 12.5 ms, so the full 80 is likely there, but it is not measured.
- **Render scale.** With the GPU shared, scale 0.85 (eyes of 2098 x 2329, traced at 1308 x 1168) took 9.69 ms where
  scale 1 took 13.12 ms. It still ran at half rate, because SteamVR only goes back to the full rate with a clear
  margin.
- **The preset has no reserve at 90 Hz.** I left the default at SteamVR's recommended size, which the plan names
  and all measurements used. If the worn look shows reprojection, `nl_vr_render_scale 0.85` is the first thing to
  try, and whether V1's default should be lower is a decision for after that look. The automatic preset is V6.
- **Start VR** costs one stall of about 0.3 s when the runtime makes its images (the longest frame of a session,
  281 to 392 ms).

## With VR off

**What the new runtime does differently when VR is never started** (read from the patches against the fork, each
hook checked; this is all of it):

- At start-up it asks Vulkan for six more extension names, when the driver offers them: two for the instance
  (`VK_KHR_external_fence_capabilities`, `VK_NV_external_memory_capabilities`) and four for the device
  (`VK_KHR_timeline_semaphore`, `VK_KHR_dedicated_allocation`, `VK_KHR_win32_keyed_mutex`,
  `VK_KHR_get_memory_requirements2`; the last was already asked for whenever the FSR library is present, as it is
  in the package). They switch nothing on: no feature bit, no allocation. SteamVR needs them on the device from its
  creation, and the device is created long before anyone can press Start VR
  ([ADR 0149](../decisions/0149-steamvr-vulkan-extensions-at-device-creation.md),
  [ADR 0157](../decisions/0157-steamvr-requirements-do-not-depend-on-fsr.md)).
- It keeps a copy of the names it enabled (two small lists) and creates the VR object: a few empty containers, no
  thread, no GPU image, no shader.
- `d3d9.dll` exports eight more functions (`rtxvr_*`) and is 99,328 bytes larger.
- Every frame it reads two flags ("VR has work", "VR is active") in about a dozen places (where a command list
  starts and ends, where the render target changes, at each submission, at the camera, at the frame's injection
  and at the present) and stores one number, the main camera's field of view. With VR off every one of those
  branches is skipped; the view-model and camera tests compare exactly what they compared before.
- Nothing else: `openvr_api.dll` and the module are not loaded (checked in every control's module list), no
  environment variable is read, the warp shader is not compiled, the add-on's files are not loaded.

**Measured.** gm_construct, 1280 x 720, a fixed camera, clear noon sky, `fps_max 0`, the same package twice with
only `d3d9.dll` exchanged (the other 1,784 files identical by hash), published and final runtime alternating:

| Series | Published runtime | New runtime | |
|---|---:|---:|---|
| The first V1 runtime, idle GPU: 3 + 3 runs of 30 s | 7.763 ms | 7.727 ms | medians' mean; -0.5 % |
| The final runtime, the worker's 3 + 3 runs of 30 s | 9.474 ms | 9.819 ms | +3.6 %, of which the first pair (8.245 against 9.127) is all: the other two differ by -0.005 and +0.158 ms |
| The final runtime, Claude's check: 13 + 13 launches (30 s and 15 s), another game on the GPU | 10.19 ms (12 valid) | 10.12 ms (11 valid) | medians' median; the runs of one runtime spread by 0.2 ms |
| The same launches: start to map loaded | 25.45 s | 25.37 s | |

No series shows a cost. What they can resolve is limited by what else used the GPU: single runs moved between 5
and 19 ms over the evening with the other programs' load (one of the new runtime's runs measured 6.4 ms beside
neighbours at 10.1), so a cost below about 0.2 ms, 2 % of a frame, could hide in them; the code above gives no
reason to expect one. The start-up times of the two runtimes overlap in all series (-0.4 to +0.5 s).

**Pictures.** The first screenshot of 22 valid controls (12 published, 10 new): two runs of the same runtime
differ by 0.62 of 255 levels on average (0.48 to 0.80), a published and a new run by 0.63 (0.29 to 0.77); the mean
colour is 100.13 / 126.69 / 141.29 against 100.13 / 126.70 / 141.32. A path-traced picture is never bit-identical
twice; the two runtimes differ exactly as much as one runtime differs from itself. (Compare first screenshots
only: a control's second one is taken while the probe removes its camera and shows either view. One control's
first shot is left out because the Steam overlay was open over the window.)

**Two things that went wrong in these launches, neither of them the new runtime's:**

- **A start-up crash in NVIDIA's driver:** one of the 13 launches of each runtime ended in the first seconds of
  rendering with an access violation at `nvoglv64.dll+0xe622f8`, the published runtime's just after the map
  loaded, the new one's before. It is the crash this repository has recorded since R5 (2 of about 16 field starts on
  2026-10-31) and in R13 (2 of 8 PoC launches), at this same address, and once in G1; the PoC's own session
  records hold one from 2026-11-09 23:19, the night before any VR patch existed, with the same address and the
  same bad pointer (`0x300060059`). It comes when another program is using the GPU, as one was all evening. The worker's
  26 flat launches of its last round had none; its two "launch crashes before VR" were this one and a second
  address in the same driver (`+0xafa3aa`).
- **One control of the new runtime ended by itself** half a minute after its start, with a normal quit (exit code
  0, the game saved its configuration), which the driver had not asked for. The likely cause is on the desktop:
  the tests ran while the user was playing another game, the test windows take the keyboard, and in a later run
  the Steam overlay, with its Exit Game button, was found open over the test window. It did not happen again in
  the 23 flat launches and two VR sessions after it.

## What in the plan turned out wrong

- **The Index's eyes are not canted for the application.** OpenVR gives parallel eyes (identity rotations) with
  asymmetric projections; the plan assumed a rotation in `GetEyeToHeadTransform`. The warp handles a rotation
  anyway (tested with synthetic +/-5 degrees).
- **The size SteamVR recommends here is 2468 x 2740 per eye**, not the 2016 x 2240 the plan guessed: SteamVR chose
  150 % by itself for this GPU. The centre view is 3072 x 2752, path traced at 1536 x 1376.
- **`WaitGetPoses` in the module does not pace a queued game.** The plan had the module call it once a frame. With
  `mat_queue_mode 2` the game thread is a frame ahead of the render side, so the next `WaitGetPoses` could come
  before the previous frame's Submit and the compositor refused frames (`AlreadySubmitted`: 139 failed eye calls in
  6,436 frames). Making the game thread wait for the render side cured the errors and halved the frame rate (45
  frames a second at 90 Hz on gm_construct, although the GPU needs 9.4 ms). V1 therefore paces on the render
  side: the runtime calls `WaitGetPoses` right after its Submit, and the module predicts the poses instead
  ([ADR 0147](../decisions/0147-frame-poses-and-render-side-pacing.md)).
- **The material system's call queue cannot carry the pose** (spike S4): on this game build it is a private arena,
  not the public interface. The runtime instead matches each rendered frame's camera against the poses pushed with
  their cameras; no frame went unmatched in any accepted run.
- **A depth warp that keeps the far surface makes near things too narrow.** The plan's "depth warp to both eyes"
  was first built to prefer the background at a depth edge, which loses a strip of every near object in each eye.
  The second review found it; the warp now walks each eye ray from near to far and takes the first surface it
  meets ([ADR 0156](../decisions/0156-the-vr-warp-finds-the-nearest-visible-surface.md)). It costs 0.56 ms
  instead of 0.11.
- **A render target cannot be handed over as a Direct3D texture** from Lua or the module. An overlay's source is
  found by its exact size instead (the wrist HUD's target is 769 x 257).
- **The device needs five more Vulkan extension names**, not only "external memory and semaphore" (spike S1), and
  one more that was enabled only beside FSR.
- **`fps_max` cannot be raised from Lua** (it is on Garry's Mod's blocked list). When it is below the headset's rate
  the page says so and says what to type.
- **Nothing has to hide the flat HUD.** The eye images are made before the game draws its 2D, so the HUD, the
  menus and the console stay on the desktop window by construction.
- **SteamVR was not running when the work began.** It had quit at 04:02; its logs show two launches of Garry's Mod
  through Steam waiting on a Steam dialog just before, and then the quit. A scene application's `VR_Init` started
  it again, as Start VR does for a player; no SteamVR setting was changed and SteamVR was left running.

## Review

Claude reviewed each task's commits as they landed and sent each task back once with findings (the add-on changed
engine console variables in a way the game does not allow and replaced the game's hook dispatch to hide a HUD that
never reaches the eyes; the module's status poll would have frozen the game while SteamVR started; the runtime's
pose matching compared Euler angles, which fails looking straight up or down, and its GPU timing could not say where
6 of 15 ms went). Then two independent Claude subagents reviewed the result. A first attempt at the independent
review was stopped partway by the model's automated safety filter and left no report; it was started again with a
narrower brief (the module's and the Lua side's own files, ordinary correctness).

**The first review** (the module, the page and the add-on; `out/vr/review/independent-1.md` in the main checkout)
found ten things, all fixed and each with a test that fails without the fix:

| # | Finding | Outcome |
|---|---|---|
| 1 | High: `nlvr.Start` took the path of the DLL to load, and of the action manifest, from its Lua options, and captures went to any folder. Once loaded, the module can be called by every script in the client, a server's included | Lua passes no path any more: the module finds both files from its own folder, and captures and timelines take a name inside one folder of the game's data ([ADR 0150](../decisions/0150-vr-client-lua-boundary-and-native-quit.md)) |
| 2 | High: a frame for which the module gave no pose was drawn from the flat first-person camera and still went to the headset | Such a frame repeats the last head camera |
| 3 | High: a SteamVR quit was handled only by a Lua timer, and Garry's Mod's timers stand still while a single-player game is paused; SteamVR may then end the game | The module answers the quit itself and ends the session; the page's poll also runs while paused. Proven in the PoC with the escape menu open (9.7 s of wall time, 0.008 s of game time) |
| 4, 6 | Medium: the serial pacing wait's ticket after a timeout, and no pose until the renderer had traced a frame | Gone with the serial wait: the runtime paces the frames |
| 5 | Medium: the module's functions return `nil` and a message, and the Lua never read the message (500 failing frames under "VR is running") | Both results are read; a run of failures ends the session with the reason on the page |
| 7-10 | Low: Start straight after Exit failed with a SteamVR error text; an invalid head pose was pushed as it was; the wrist overlay was shown before it had a place; no way to recentre | The page waits for the stop to finish; such a frame uses the compositor's pose; the overlay shows once it is placed; `nl_vr_recenter` |

**The second review** (the runtime's VR code and the final pacing; `out/vr/review/independent-2.md`) confirmed the
ten fixes, found the state machine, the lock order, the Submit and wait alternation, the pose ring, the resource
lifetimes and the cost with VR off sound, and found ten more things, all fixed in the final build:

| # | Finding | Outcome |
|---|---|---|
| 1 | High: at a depth edge the warp took the far surface on both sides, so each eye drew every near object too narrow by the stereo disparity, with the background in the strip (the test barrel: 283 pixels wide in the centre view, 270 and 269 in the eyes). The pictures looked plausible one at a time, which is why the image checks had passed | The warp now walks each eye ray from the nearest depth the centre view covers to infinity and takes the first surface it meets (34 steps on the Index, then a refinement), keeping the far surface only at a real disocclusion. The barrel is 284 pixels in the centre view and 284 and 281 in the eyes; a second target on Modern House 285 against 286 and 283. Thin outlines remain at depth edges: one centre view cannot do better there. The warp costs 0.56 ms a frame instead of 0.11 |
| 2 | Medium: moving the IPD slider could end the session (the event thread held the session's lock while one frame call tried it) | The eye update is applied inside `BeginFrame`; a busy answer keeps the last camera instead of ending VR |
| 3 | Medium: without queued rendering the wrist HUD's only paint came before the runtime could copy it, so the overlay stayed empty until a number changed | The add-on repaints until the runtime reports the copy; `mat_queue_mode` 0 and 2 give the same populated HUD |
| 4 | Medium to low: any result of the compositor's wait other than success ended the session, a loss of focus to another VR application included | A loss of focus skips frames and the session resumes; only what cannot recover ends it |
| 5 | Low to medium: the first eye frame of every session was path traced with the flat game's projection and camera | A frame is submitted only when the VR projection and a matched camera were set for it; the first logged frame now has the headset's field of view |
| 6 | Low: a failed image allocation left through the render thread's own handler and closed the game | Caught where VR allocates; Start VR fails with a reason (three injected failures) |
| 7 | Low: one extension SteamVR requires was enabled only when the FSR library loaded | It is one of the VR prerequisites now, six names in all (a start without the FSR library accepted 810 frames) |
| 8 | Low: the overlay copy hook also ran on the game's thread and read what the render thread writes | Only the render context observes targets |
| 9 | Low: a capture asked for on a frame without a scene was lost | The request is kept until a frame is output |
| 10 | Low: new eye images were written without a layout transition; the preset pinned DLSS on a GPU without it; timing records could grow while no frame was eligible; a stale version text | Transitions added; the preset follows what the GPU supports (TAA-U otherwise); the records are bounded; the text corrected |

Not checked by either review and not testable here: SteamVR's behaviour when another VR application really takes
the focus, an AMD or Intel GPU, and what a person sees through the lenses.

**Claude's own check of the final build** (after both reviews): the dormant path was read line by line against the
fork (what "With VR off" lists is all there is), and the build was run in the PoC: six flat controls and two VR
sessions of 310 s and 190 s first, then twenty alternating flat launches, and at the end the look package built
from the merged branch, once unattended and once through the look command itself. That check is where the
shared-GPU frame rate, the driver crash's history and the flat numbers of this report come from.

## Tests

**The gate.** `tools\test.ps1 -Config Release` passes on `vr` as it is handed over, after `main` was merged in:
34 CTest cases and 927 Python tests in three suites (3 skipped), with the repository conventions.

**Offline** (in the gate):

- the module: 16 native test cases against a stand-in for `openvr_api.dll` and one for the runtime (the session's
  states, start and stop on the worker thread, poses and their prediction, the camera ring, input readers against
  the 20 actions and three binding files, overlays, the test mode's timeline, the Lua boundary: no path from Lua,
  capture names);
- the page and the add-on: 58 cases with stand-ins for the game and the module (every refusal and its text, the
  camera and its floor anchor, the wrist HUD's repaint until the runtime has copied it, Exit and quit in every
  state, the translated catalogs complete in every language of the tab);
- the session driver: 16 cases (locks, the snapshot and its rollback, the probe's transport, the summary's checks);
- the runtime's VR arithmetic: 249 assertions in the fork's own unit test (projections and the centre view, the
  warp's search against a reference on mirrored edges, thin objects and layered depth, the pose ring, the
  first-frame and focus policies), built and run with the runtime, not part of this repository's gate;
- that the two copies of the C interface between the runtime and the module are byte-identical, and that OpenVR
  stays a pinned, hash-checked download (`tools/ci/pins.json`). A separate audit of the built files
  (`out\vr\q\binary-verification.json`) found the eight exports, no import of OpenVR in the runtime and nothing but
  `KERNEL32.dll` imported by the module: OpenVR is loaded by path at Start VR.

**In the PoC, on the Index through SteamVR** (each run takes the PoC lock and the VR lock, snapshots the PoC and
verifies its rollback; evidence in the main checkout's `out\vr\q`, the last two rows' in `out\vr`):

| Run | What it shows |
|---|---|
| `review2\construct-final7`, 310 s | 26,199 pairs accepted, none refused or unmatched, 85 frames a second; the pass times |
| `review2\house-final7`, 120 s, Modern House | 3,782 pairs, none refused or unmatched, 30 frames a second |
| `claude\construct-100`, 310 s, GPU shared | 13,925 pairs, none refused, unmatched or dropped, a steady 45; a second Start and Exit in the same game; flat frame time before and after |
| `claude\construct-085`, 190 s, scale 0.85 | 8,693 pairs, none refused, unmatched or dropped; eyes of 2098 x 2329 |
| `smoke-03` | two Start and Exit cycles, flat 128.5 frames a second before and 128.8 after |
| `host-pause-exit` | a listen-server host with `fps_max 60`: the page's hint, Exit from the pause menu, a second Start |
| `live-shutdown`, `manual-look`, `review2\look-final2` | the headset's real tracking; quitting the game in VR; the look command of this report from start to rollback |
| `review2\focus-paused-quit` | three injected losses of focus recovered; a SteamVR quit answered while the game is paused |
| `review2\allocation-*` | an image allocation failing at the eyes, the overlay and the capture: Start fails with its reason, the game goes on |
| `review2\first-camera-injected7` | 505 start-up frames with a camera that does not match are withheld, then 2,014 matched pairs |
| `review2\queue-0*`, `queue-default*` | the wrist HUD and the captures with queued rendering off and on |
| `review2\no-fsr` | a package without the FSR library: 810 pairs accepted, so SteamVR's extensions do not depend on it |
| `missing-runtime` | the published runtime without VR output: Start refuses before OpenVR is loaded, with the page's text |
| `claude\flat-*`, `claude\launch-*`, `review2\flat-*` | the controls of "With VR off" |
| `v1\smoke-01` | the look package of this report, built from the merged branch: 4,023 pairs in 90 s, none refused, unmatched or dropped (half rate, the GPU shared); two Start and Exit cycles; all five capture sets; the PoC restored |
| `look\claude-look-01` | the look command of this report with that package, a script typing what a person would (`nl_vr_start`, `nl_vr_recenter`, a capture, `nl_vr_exit`, `nl_vr_demo_done`): 368 pairs on the headset's real tracking, none refused or unmatched; the capture saved; the PoC restored |

Every run that touched the PoC restored it: the depot files verified against Steam's manifest (2,877 files), the
settings and every Remix `user.conf` unchanged by hash. SteamVR was never quit and none of its settings changed.

**Not covered by any test:** what a person sees and feels; another headset; an AMD or Intel GPU; a real loss of
focus to another VR application; the IPD slider; 80 Hz.

## How to look for yourself

Since the merge the build is the Workshop package: in the real game the VR page is on the RTX Remix tab and Start
VR works there. The command below is the way to look at a build *before* it is merged: it puts the build into the
PoC, starts the game for you and rolls everything back afterwards. SteamVR running and the headset connected is
all it needs, with any Python 3.10 or newer; the field game is not touched. (As first handed over, the look also
needed Pillow in that Python and ended the game a minute after it could not take a screenshot. That cut both of
the user's looks short and is fixed: see "Approval and merge".) The command was run to its end with this package,
a script typing the console commands below in a person's place: `out\vr\look\claude-look-01`, and with a Python
that has no Pillow `out\vr\look\codex-followup4-nopil-look-01`. In PowerShell, from
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\vr`:

```powershell
python tools\vr_session.py --package out\dist\gmod-rtx-remix-0.0.0-vr.v1.gma --evidence H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\look\look-01 --look --seconds 1800
```

What it does, in order:

1. **Puts the build in.** It takes the PoC lock and the VR lock, records the PoC (every depot file's hash, your
   settings, every Remix `user.conf`), moves the PoC's present loader data aside and installs the loader with only
   this local package allowed. The package (1,775 files, 2,085,334,394 bytes, SHA-256
   `9f8667a4bb1d0ea59e33a932c6c51ba3900dbe23775d1c2961331b4e9ccd00f5`) holds the final runtime, the module and
   `openvr_api.dll`, the add-on and the page, with everything else the RTX package has on `main` today.
2. **Starts the game** on gm_construct in a 1280 x 720 window, clear weather at noon. After about half a minute
   the console says `NLVR preview: ...`. Then it is yours:
   - spawn menu > **RTX Remix** > **VR** > **Start VR**, or `nl_vr_start` in the console;
   - put the headset on; `nl_vr_recenter` (or the page's button) takes where you stand and where you face;
   - you move and turn with the keyboard and the mouse (V1 has no controller movement); the window shows the left
     eye, and the page shows the frame times and SteamVR's counters while VR runs;
   - `nl_vr_exit` or **Exit VR** returns to the flat game; start again as often as you like;
   - `nl_vr_render_scale 0.85` (or the page's slider), then Exit and Start again, shows the smaller size;
   - a saved set of pictures of what the eyes got:
     `lua_run_cl local ok,e=nlvr.Capture("look",15) print("NLVR_LOOK_CAPTURE",ok,e)`.
3. **Rolls back.** Type `nl_vr_demo_done` when you are finished (it also ends by itself after `--seconds`, at most
   3600): VR stops, your settings are put back, the game quits, the PoC's own data comes back and every depot file
   is verified. The numbers, logs and pictures stay in the evidence folder; give each look a new folder name.
   Closing the game window ends the look too, with the same rollback. Nothing else ends a look, except a real
   fault: a game window that stops answering for two minutes, or a lost GPU device.

On a heavier map, Modern House (it runs at about 30 frames a second in V1), add
`--map modern_house --mount-workshop 3495468649 --camera 80,928,545,0,0,0`.

**If it is interrupted** (the window closed, a crash, the PC restarted), wait until no `gmod.exe` is left and run
the rollback for the same folder; it restores the PoC from what step 1 recorded:

```powershell
python tools\vr_session.py --evidence H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\look\look-01 --rollback
```

**If the game closes at start-up** before the map is there, start the command again with a new folder name: that is
the old driver crash ("With VR off"), which this evening hit about one launch in seven while another game was
running.

What to look at first, because no test could: whether the world has the right size (`nl_vr_scale`), whether near
things look solid at their edges, whether turning your head feels attached to the world, where the wrist HUD sits
on your left controller, and whether SteamVR's frame timing graph shows reprojection on gm_construct with nothing
else on the GPU.

## What I propose for V2

The plan's V2 stands: finger-tracked hands and ghost hands; smooth movement, snap turn and teleport with the comfort
options; noclip flight, physical crouch and height calibration; the spawn and context menus and the flat-screen panel
with the laser; the dominant hand. From what V1 found I would put five things in front of it or beside it:

1. **A worn check first.** Nobody has looked through the headset yet. Before more is built on it, the user's look
   (above) should settle what cameras and counters cannot: the world's scale (`nl_vr_scale`, 40 units a metre), whether
   the stereo depth feels right at the eyes' real distance, how the edges of near things look, and how the wrist HUD
   sits on a real, awake controller (V1 placed it from scripted poses; the controllers were asleep).
2. **Hands against the phase-1 warp, as V2's first spike.** One centre view cannot show what one eye sees behind a
   near object, and hands are the nearest objects there are. V1's centre view covers things down to half a metre
   from the head; hands come closer. Try the hands under the present warp first, and if their edges are not good
   enough, trace the hands' region per eye or bring part of V7 forward, before the rest of V2 is built on them.
3. **Reserve in the preset.** V1's fixed preset uses 88 % of a 90 Hz frame on a light map with the GPU to itself,
   and anything else on the GPU halves the rate. Either V1's default scale goes down after the worn look, or a first,
   simple version of V6's automatic preset comes forward into V2: drop the render scale when SteamVR reports
   reprojection for a second, raise it again slowly. It needs no new measurement code: the page already reads the
   compositor's timing.
4. **The game's CPU on heavy maps.** On Modern House the game thread alone takes 14.2 ms where a 90 Hz frame has
   11.1 ms, and the GPU 14.8 ms. An automatic preset only helps the GPU half. R28's `nativeloader_lag_report` names
   what the game thread spends its time on; a pass over the package's own hooks for VR sessions belongs in V2 or V6.
5. **Small things V1 left:** a time limit for Exit when SteamVR stops answering; another add-on's `CalcView` is
   held while VR runs (camera add-ons); SteamVR's Motion Smoothing was not judged, because nobody watched; other
   headsets and controllers have bindings that only offline tests have seen; the session driver's second flat
   screenshot is taken as the probe removes its camera and can show either view.

## Open

- **V2** does not start before the user asks for it.
- **What the user saw.** The approval came after two short looks ("Approval and merge"). What they showed about
  scale, depth edges, the wrist HUD's place and the default render scale is still to be heard before V2 is
  planned.
- **The frame rate has no reserve** at the recommended size (see "What it costs" and proposal 3 for V2).
- **The driver's start-up crash** is older than VR and unsolved (see "With VR off"). It is the same item R5, R13
  and G1 recorded; it belongs to the stability work, not to V1, but a VR player will meet it as "the game closed
  when I started it".
- **One flat control ended by itself** (see "With VR off"); not reproduced in the 23 flat launches and the VR
  sessions after it.
- **Three test switches are in the shipped runtime:** the environment variables `RTX_VR_TEST_ALLOCATION_FAILURE`,
  `RTX_VR_TEST_FOCUS_INTERVALS` and `RTX_VR_WARP_TAPS`, read once at Start VR and nowhere else. They are how the
  injected failures above were made on the real renderer. Only someone who starts the game with them set can use
  them, and Lua cannot. They were left in at the merge: the user gave no instruction about them.
- **Merged by squash**, as proposed: the branch's history holds three versions of the runtime's LFS object (61.6
  to 61.8 MB each) from the review rounds, and one commit on `main` pushes only the last (61.8 MB, plus 0.5 MB for
  the module and `openvr_api.dll`). The package's manifest gained no new key or kind, and the loader is unchanged.
- **Other branches.** The tasks' branches `vr-a`, `vr-c`, `vr-d`, `vr-e` and `vr-q` and their worktrees are still
  there, local only; they can go once `vr` is merged or abandoned. The runtime fork's clone
  (`out\worktrees\r17\out\runtime-src`) has the 30 VR commits on its local branch `vr`; they are not pushed to the
  fork either, the patches in `runtime/patches` are their record.

## Where things are

- **On `main`** since the merge, as one commit. The branch `vr` (worktree `out\worktrees\vr`, local only) keeps
  the detailed history. What V1 added, in about 190 files: `vr/` (the module, the
  add-on, the input files), `runtime/patches/0042` to `0071` (30 patches on the fork's `17dcc86c`; the fork clone's
  branch `vr` is at `d29445c5`), `packages/vr` and the runtime in `packages/runtime`, `third_party/openvr`, the page
  and its catalogs in `companion/`, `tools/vr_session.py` with its probe and tests, `tools/ci` (the OpenVR pin and the
  module's build record), and the documents. Nothing under `loader/` or `dist/`.
- **The binaries of the final build:**

  | File | Bytes | SHA-256 |
  |---|---:|---|
  | `d3d9.dll` (the runtime; the published one has 418,258,944 bytes) | 418,358,272 | `e43aef99a74d333fa75cbb27f8848ae7ba25ce4e8e200f5c7d0f936a69382046` |
  | `gmcl_nlvr_win64.dll` | 446,976 | `fa1ce35e3656eb22fd5d408af047992fdb83e8ef4ee78fa447523d6a11f4e1d9` |
  | `openvr_api.dll`, OpenVR v2.15.6, unchanged from Valve | 837,272 | `bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a` |

  OpenVR is pinned in `tools/ci/pins.json` at commit `0924064316de3effbcd1acf1e309182a2deb1c05`; its header
  (`openvr.h`, SHA-256 `1e6ed571...`) and BSD-3-Clause licence are in `third_party/openvr`.
- **The package for the look:** `out\worktrees\vr\out\dist\gmod-rtx-remix-0.0.0-vr.v1.gma` (1,775 files,
  2,085,334,394 bytes, SHA-256 `9f8667a4bb1d0ea59e33a932c6c51ba3900dbe23775d1c2961331b4e9ccd00f5`), built from the
  branch as it is handed over. It is a local file, not on the Workshop.
- **Evidence** (git-ignored, main checkout): `out\vr\q\review2` (the final acceptance runs, the worker's flat
  series, the injected failures), `out\vr\q\claude` (Claude's check: `flat-*`, `launch-*`, `construct-100`,
  `construct-085`), `out\vr\review` (the reviews), `out\vr\s1`, `s5`, `c`, `d`, `e` (the spikes and the tasks). The
  bulky copies of the PoC that failed runs had kept were deleted after their restorations were verified; logs,
  numbers, dumps and pictures stay.
- **The machine as it was left:** SteamVR running (never quit, no setting changed), no game running, no lock held,
  the PoC restored and verified after every run, the field install untouched, Steam's registry untouched.

## Approval and merge (2026-11-10)

- **The approval.** The user ran the look command twice (`out\vr\look\look-01` and `look-02`), started VR in both,
  and wrote: "Tested, approve V1 for now."
- **Both looks were cut short by the session tool, not by V1.** The user's terminal runs Miniconda's Python
  (`C:\ProgramData\miniconda3\python.exe`), which has no Pillow. The look took one desktop screenshot when it was
  ready; that failed (`screenshot failed: No module named 'PIL'`), the tool treated it as a failed run, skipped
  the normal end and ended the game 60 s later, with the user in VR. SteamVR's log shows the game connected as a
  VR scene at 22:18:48 and 22:22:49; the tool ended it about half a minute and about a minute and a half later.
  The PoC was restored and verified both times. Claude's own test of the look had passed only because its shell's
  Python has Pillow: the hand-over was tested in the wrong environment.
- **The fix** (commit `5da4e57` on `vr`; written by Codex, reviewed by Claude): a look takes no screenshot, has no
  time limit of its own besides `--seconds`, and needs no Pillow (`poc_session.py run --lua-manual`, used only by
  the look; the tool's behaviour for every other caller is unchanged). Closing the game window ends a look
  cleanly, with the PoC restored and one line saying so. Unattended runs, whose screenshots are evidence, check
  for Pillow before they take a lock, make a folder or touch the PoC, and stop with exit code 2 and the remedy.
  Proven with a Python that has no Pillow: a look of 171 s in VR, 3,526 eye pairs, none refused or unmatched,
  normal quit, settings and PoC restored (`out\vr\look\codex-followup4-nopil-look-01`); and the refusal, with no
  lock, folder or game created.
- **Left as they were, for want of an instruction:** the preset's default render scale (1), and the three test
  switches in the runtime.
- **The merge.** `main` had not moved since it was merged into `vr`, so the squashed commit's tree is exactly the
  tree that was tested: the gate on it passed (34 CTest cases and 934 Python tests), and the package built from the same inputs is the one
  the unattended session and the looks ran. One commit on `main`, pushed; the repository's hooks build the package
  from `packages/` and upload it to the Workshop item when its content differs. Nothing under `loader/` changed.
- **Published 2026-11-11 UTC.** The merge is commit `7f335d5` on `main`, pushed to GitHub with its three new LFS
  objects (62 MB). Its commit hook built the package from `packages/` and uploaded it to item 3829070317 as
  **0.0.0-dev.20261111060557+bfb14d90** (2,085,334,416 bytes, SHA-256
  `d1a900dc72a69c3b0006a8b8434d1a64fd75747e3c9262f2839525df0ef5eaef`). Its content digest,
  `7bd587faa43ba2ff107d3e530a4523cfb15b832a82014772c9d4963332ebee0e`, is the digest of the package the PoC sessions
  and the looks ran (`0.0.0-vr.v1`): what was published is what was tested. Steam's public record shows that size,
  updated 06:06:40 UTC. The push's hook found the same inputs and uploaded nothing. No GitHub Action was started.
- **A note for the next squash merge.** Staging a squash makes git run the merge hook before the commit exists. The
  publish tool refused that run, because the packaging inputs were still uncommitted, and published from the
  commit's own hook a moment later: nothing went out early, but the first log of such a merge is a refusal.
