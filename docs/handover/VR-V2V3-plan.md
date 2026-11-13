# VR V2 and V3 work plan: hands, movement, menus, physical interaction

Claude's plan for milestones V2 and V3 of [VR-plan.md](VR-plan.md), run together as the user asked. Codex writes the
code in the tasks below, Claude directs and reviews (the user's choice for the VR work). Everything stays on the
branch `vr2` and its task branches until the user approves; V4 follows on top of it before that approval.

## The user's request (2026-11-11, verbatim)

"Already tested V1, much better than expected, well done. Still in VR headset and desktop view, some ghost shade
could be seen, this should be addressed. Also frame gen is off and framerate is low, note user can launch the game
at 4K but VR usually have a different resolution and desktop view's high resolution render could hinder the
performance. This could be the artifact V6 / V7 to resolve.

Let's Start V2 and V3 together. When finished, also proceed to V4."

With a screenshot of the left eye (the desktop mirror) in the field game: an imported character in Modern House,
with thin repeated copies of the hair's and a ring ornament's outlines just to the left of them, over the wall
behind.

What that means for this plan:

- **The ghost lines.** In the left eye, the background just left of a near object is a strip the centre view never
  saw (a disocclusion); the right eye has it on the right. The lines sit exactly there, so they are most likely the
  warp's, not DLSS's: thin foreground (hair, rings) hit at several steps of the warp's search. Task R reproduces
  them, proves where they come from (centre image or warp), and reduces them. True stereo stays V7.
- **Hands near the eyes.** The warp searches from 0.5 m (`kNearestEyeDepthMetres`,
  `src/dxvk/rtx_render/rtx_vr_math.h:43` in the runtime fork): anything nearer is missed or wrong in the eyes. V2's
  hands come closer than that. Task R brings the near limit down; this is V2's hardest runtime question.
- **The 4K desktop.** The user plays with a 3840 x 2160 window; V1 was measured with 1280 x 720. Task R measures
  what the window size costs in VR and removes what is not needed. The Auto preset stays V6.
- **Frame generation** stays off in VR: DLSS frame generation makes frames for the desktop window, not for
  SteamVR. SteamVR's Motion Smoothing is the VR equivalent (a SteamVR setting, the user's).

## Where things stand (2026-11-11)

V1 is on `main` (`7f335d5`, report [VR-V1-report.md](VR-V1-report.md)) and published. The work branch is `vr2`
from `main` at `8704ae8` (worktree `out\worktrees\vr2`). The runtime fork's clone is
`out\worktrees\r17\out\runtime-src`, branch `vr` at `d29445c5`; task R works on a new branch `vr2` there.

What V1 gives the tasks: the module `nlvr` (table below), the add-on's session (`vr/addon/lua/nlvr/client.lua`:
camera at the head, view-model and body proxies hidden, wrist HUD), the page
(`companion/nativeloader/lua/autorun/client/nativeloader_vr.lua`: `nl_vr_start`, `nl_vr_exit`, `nl_vr_recenter`,
`nl_vr_scale`, `nl_vr_fov`, `nl_vr_render_scale`), raw SteamVR Input actions per physical control
(`vr/input/nlvr_actions.json`: grip, trigger, stick, stick click, A, B, grip force, trigger value, skeleton, haptic,
for each hand), the test timeline (scripted head, hands and actions, curls included), and the session driver
`tools/vr_session.py` with its probe `tools/vr_session.lua`.

## Decisions for V2 and V3

The table "Decisions taken with the user" in [VR-plan.md](VR-plan.md) is binding. If a task finds that one cannot
work, it stops that part and says so in its report with the options; it does not change the approach. These are
Claude's decisions for V2 and V3 (new decision records record them):

| Topic | Decision |
|---|---|
| Hands | The player model's hands (`player_manager.TranslatePlayerHands`, the `c_arms` models), drawn as world models (never the view-model pass), each hand posed from SteamVR's finger curls and splay; the default hands when a model has none. Path traced like everything else. |
| UI elements in 3D | Every piece of VR UI is a SteamVR overlay fed from a render target the add-on paints (as V1's wrist HUD): panels, the laser, the teleport arc and target, the vignette, the ghost hand's outline at the real controller, the gravity gloves' target marker. Nothing of it is path traced. |
| The flat-screen panel | The game window's own picture after its 2D (a new overlay source in the runtime), with the laser as the mouse. While it is open the mirror is left out, so the panel shows the 2D alone. |
| Controls | V1's raw per-control actions stay; the add-on maps them, with the dominant hand mirroring everything, as the plan's control table says. Players can still rebind physical controls in SteamVR's binding UI (a button on the page opens it). |
| Server side | The add-on gets server files. They load only when a VR player starts: a stub in the companion's shared autorun registers one network message and, when the single-player player or the listen-server host says "start", includes `nlvr/server.lua`. When the last VR player stops, the server part removes its hooks. Off: one network string and one receiver, no hook. |
| Who gets full VR | In V2 and V3: the single-player player and the listen-server host's own player. Messages from any other player are ignored. Other players and other servers are V5. |
| Physics authority | The server moves everything physical: hand proxies, held props, ragdoll bones, climbing, teleport. The client sends its head and hand poses and controls every tick; the server checks them (finite, within reach of the player, rate). |
| Tests without SteamVR | The module gets a simulated session for tests (no OpenVR at all: the Index's recorded eyes, timeline poses, the runtime rendering without a compositor). Allowed only when the launcher set the test root, like V1's timelines. Acceptance still runs on the Index. |

## The tasks

| Task | What | Branch and worktree | Starts |
|---|---|---|---|
| F | The add-on's framework: client core, server core and stub, network sync, input mapping, overlay manager, settings, the harness | `v2f` | now |
| N | The module: simulated sessions, SteamVR keyboard, finger splay, binding UI, the window overlay source, timeline additions; the driver's `--simulate` and `--window` | `v2n` | now |
| R | The runtime: hands near the eyes, the ghost lines, the window overlay source, rendering without a compositor, the 4K desktop's cost | `v2r` (repository) and `vr2` (fork clone) | now |
| H | Hands: models, finger posing, dominant hand, ghost hands | `v2h` | when F is merged |
| L | Movement and comfort | `v2l` | when F is merged |
| M | Menus and panels: wrist menu, spawn and context menus, flat-screen panel, laser, keyboard, the page's new options | `v2m` | when F is merged |
| P | V3: physical hands, grab and throw, two hands, gravity gloves, ragdolls, use by hand, climbing, melee | `v3p` | when F is merged |
| Q | Integration and acceptance on the Index, measurements, one runtime import, documents, report | `v2q` | when the others are done |

Each worktree is `out\worktrees\<branch>`, cut from `vr2` when the task starts (H, L, M and P from `vr2` after F is
merged into it). Claude merges finished tasks into `vr2` after review; Q works from there.

## Interfaces (binding; a task that cannot keep one says so in its report at once)

### 1. The add-on's files

```
vr/addon/lua/nlvr/
  client.lua            the page includes it at Start (V1's contract: returns Session {Start, Stop, Recenter})
  server.lua            the companion's stub includes it at a VR player's start (returns SV {Start(ply), Stop(ply)})
  sh_protocol.lua       shared: message types, packing and unpacking of the sync, limits
  core/cl_core.lua      client core: module registry, frame, play space, poses, view (V1's camera moves here)
  core/cl_input.lua     input mapping, edges, holds, dominant hand, claims
  core/cl_overlay.lua   overlay manager
  core/cl_net.lua       client side of the sync
  core/sv_core.lua      server core: VR players, their hands, movement arbitration, network
  modules/cl_hud.lua    the wrist HUD (V1's, moved by F)
  modules/cl_hands.lua                         H
  modules/cl_move.lua, modules/sv_move.lua     L
  modules/cl_ui.lua (and cl_ui_*.lua)          M
  modules/cl_interact.lua, modules/sv_interact.lua (and sv_interact_*.lua)   P
```

F creates every file in this list, the modules as stubs that register and do nothing, so the module list never
changes after F. A task replaces only its own stubs and adds files with its own prefix. Nothing goes under
`autorun` except the companion's stub.

### 2. Modules

A module file returns `{name, order, Start = function(ctx) end, Stop = function() end}`; `ctx` gives the core. A
module adds hooks only through `ctx.hook(event, fn)` (one id per module, `nlvr.<name>`); the core removes them all
at Exit, after `Stop`, also when a module failed. An error in a module's hook is caught: it is logged once, the
module is stopped, the session goes on. Order (client): core, hud, hands, move, ui, interact; Stop in reverse.

### 3. The client core (`NLVR`, a global table only while VR runs)

- **Frame.** `NLVR.Frame`: V1's `nlvr.BeginFrame()` result of this frame, sampled once (V1's rule: CalcView and
  PreRender share one sample).
- **Play space.** `NLVR.Space = {anchor, yaw, scale, seated}`: tracking-space `anchor` (the point under the
  player's feet, metres), `yaw` (degrees, the play space's turn), `scale` (game units a metre, from `nl_vr_scale` or
  the height calibration), `seated` (metres added to the head's height). `NLVR.ToWorld(pos, ang)` and
  `NLVR.ToTracking(pos, ang)` convert with the player's current feet (V1's formula:
  `feet + R(yaw) * (p - anchor) * scale`, height from the floor). Only L changes `anchor` and `yaw` (snap turn about
  the head, following the head, recentre); the core's `NLVR.Space.Turn(degrees)` and `NLVR.Space.Shift(delta)` keep
  the head where it is.
- **Poses.** `NLVR.Pose.head`, `.left`, `.right`: `{valid, pos, ang, vel, angvel}` in world space, this frame;
  `.raw` the tracking-space ones. `NLVR.Pose.main` and `.off` follow the dominant hand. A hand's ray:
  `NLVR.Ray(hand) -> origin, direction` (the controller's pointing axis, fixed per controller model).
- **Shown hands.** `NLVR.Hand[hand] = {target = pose from the controller, shown = pose to draw, blocked = bool,
  held = nil or {ent, bone}, grip_curls = nil or {5}}`. Resolvers fill `shown` and `blocked` in order: the core's
  default is the target; H adds a client-side stop at world geometry; P adds the server proxies' positions.
- **View.** The core owns CalcView (V1's owned registry, camera at the head through `NLVR.Space`) and sets the
  user command's view angles to the head's each tick, unless a module asks for an aim this tick
  (`NLVR.Aim(angles, owner)`, used by V4).
- **Movement in the user command.** `ctx.mover(priority, fn(cmd))`: the core calls them in order inside
  `CreateMove`; a mover may set forward and side movement, buttons and view angles.
- **Events.** `NLVR.On(name, fn)`, `NLVR.Emit(name, ...)` for module-to-module calls (for example `"grab"`,
  `"release"`, `"teleport"`, `"panel_open"`).
- **Debug.** `NLVR.Debug[module] = {...}`: plain values the session probe reads (no functions, no entities).

### 4. Input (`NLVR.Input`)

Per frame, from `nlvr.Actions()`: for `left` and `right`: `grip`, `grip_force`, `trigger`, `trigger_value`,
`stick` (x, y), `stick_click`, `a`, `b`, `curls` (5), `splay` (4, once N supplies them); `pressed` and `released`
edges, the time held. `NLVR.Input.main` and `.off` are the dominant and the other hand. `Claim(hand, control,
owner)` gives a control to one module for this frame (for example the UI takes the trigger while the laser is on a
panel); `Owner(hand, control)`. A module acts on a control only when it owns it or nobody does. Tap and hold:
`Tapped(hand, control)` (released within 0.3 s) and `Held(hand, control, seconds)`.

Default mapping (right-handed; mirrored for left-handed), from the plan:

| Control | Off hand | Main hand |
|---|---|---|
| Grip | Grab; gravity gloves | Grab; gravity gloves |
| Trigger | Use by hand, laser click, off-hand actions | Fire, tool primary, use by hand, laser click |
| Stick | Move | Snap turn; up (hold): teleport arc; down: crouch toggle |
| Stick click | Sprint | Flashlight |
| A | Jump | (V4: eject, tool secondary, physgun freeze) |
| B | Wrist menu | (V4: tap tool reload, hold weapon wheel) |

### 5. Overlays (`NLVR.Overlay`)

`NLVR.Overlay.New{key, name, width, height, paint, device, pos, ang, metres, alpha}` returns an object with
`Show(bool)`, `Place(device, pos, ang, metres)`, `Alpha(a)`, `Invalidate()` (repaint at the next PostRender),
`Destroy()`. The runtime finds an overlay's render target by its exact size (ADR 0148), so every overlay's size is
unique and odd: F keeps the table of sizes in `cl_overlay.lua` (V1's wrist HUD keeps 769 x 257) and refuses a size
in use. Painting happens only when invalidated. `device` is `"left"`, `"right"`, `"head"` or `"world"` (tracking
space), as in V1's `OverlayAttach`. Ray hits on panels are computed in Lua from the overlay's placement
(`NLVR.Overlay.Hit(object, origin, direction) -> u, v, distance`).

### 6. Client to server

One network message name, `nlvr`, with a type byte. Types: `1` start, `2` stop, `3` sync, `16..63` module
messages (`NLVR.Net.Send(type, writer)`, `NLVR_SV.Net.On(type, fn(ply))`; each module's numbers are listed in
`sh_protocol.lua` by F: hands 16-23, move 24-31, ui 32-39, interact 40-63).

The sync, at most once per server tick, from `CreateMove`: a sequence number; the head's world position and angles;
for each hand the world position, angles, velocity and angular velocity, grip force, trigger value, five curls and
the buttons (a bit mask). The server keeps the last second of samples per hand (for throws), and drops a sync that is
not finite, more than `NLVR_SV.REACH` (default 2.5 m in game units at the player's scale) from the player's eyes, or
more than two a tick.

Server to client: what the client draws from the server's physics (hand proxies' positions, what each hand holds)
travels as `NLVR_SV.Net.Send(ply, type, writer)` at most once a tick and only when it changed.

### 7. The server core (`NLVR_SV`)

`NLVR_SV.Players[ply] = {active, head, hands = {left, right}, history, seq, since}`; `Start(ply)` and `Stop(ply)`
(the stub calls them; Stop also when the player leaves and when the server part unloads), `OnStart`, `OnStop`,
`OnSync`, `OnDeath` and `OnSpawn` events for modules (death releases what the hands hold; VR goes on). **Movement on the server**: `NLVR_SV.mover(priority, fn(ply, mv, cmd))` in
`SetupMove`/`Move`: the first mover that returns true handles the player's movement this tick (climbing above
teleport above noclip flight above normal). Server modules register in `server.lua`'s fixed list (move, interact).

### 8. The module (`nlvr`) additions (task N)

| Function | What |
|---|---|
| `nlvr.Start{..., simulate = true}` | Tests only (refused unless the launcher set the test root): no `openvr_api.dll`, no SteamVR. Eyes, IPD, size and refresh from a recorded description of the Index in the test root (V1's numbers); poses and actions from the timeline; frames paced by a timer at the refresh rate; overlays kept in the module (placement, visibility) and their pictures still copied by the runtime; the runtime started with `RTXVR_START_NO_SUBMIT` and no OpenVR interfaces. `Info()` says `simulated = true`. |
| `nlvr.ShowKeyboard(text, description, multiline, maxchars)`, `nlvr.HideKeyboard()` | SteamVR's keyboard; its text arrives as events `{type = "keyboard_done", text}` and `{type = "keyboard_closed"}`. A timeline can script them |
| `nlvr.OpenBindingUI()` | SteamVR's binding UI for this application |
| `nlvr.OverlayWindow(handle, enable)` | The overlay shows the game window's picture (runtime API below) |
| `nlvr.OverlaySortOrder(handle, n)`, `nlvr.OverlayColor(handle, r, g, b)` | Overlay stacking and tint |
| `Actions()` | adds `splay` (4 values) to the skeleton actions |
| Timeline | scripts every action (booleans, axes, grip force, trigger value, curls, splay) and keyboard events, as V1's format already does for poses |

### 9. The runtime additions (task R)

New functions are additional exports, found by name; `RTXVR_API_VERSION` stays 3 unless a structure has to change
(then R raises it, says so in its report, and Q brings the module along at integration). R writes the declarations
into both copies of the header (the fork's `rtx_vr_api.h` through its patches, and `vr/native/include/rtxvr_api.h`;
the gate compares them). N declares what it calls privately in the module until Q switches it to the shared header.

- **Near limit.** Hands and what they hold, down to 0.2 m from the eyes, appear in both eyes whole. If 0.2 m costs too
  much (the warp above 1.0 ms at the Index's recommended size, or the centre view above 10 % more pixels), R picks
  the nearest depth that keeps both, and records the numbers.
- **Ghost lines.** Reproduced on a PoC scene with thin near features in front of a far background; shown to come
  from the warp or from the centre image; reduced, with before and after crops of the same frames and a count of
  the affected pixels. A fix must not bring back V1's narrowed near objects (the barrel test of ADR 0156).
- **Window overlay source.** `int rtxvr_SetOverlayWindow(uint64_t overlay, uint32_t flags)` with
  `RTXVR_WINDOW_SHOW 0x1u` and `RTXVR_WINDOW_NO_MIRROR 0x2u`: while `SHOW` is set the overlay's texture is the game
  window's picture at present, after the game's 2D, scaled to at most 1920 pixels wide; `NO_MIRROR` leaves the
  mirror out of the window meanwhile, so the picture is the 2D alone over black. `flags = 0` ends it.
- **Without a compositor.** With `RTXVR_START_NO_SUBMIT` and a null `getGenericInterface` the runtime renders,
  warps, mirrors, copies overlay pictures (kept for captures) and captures, and never calls OpenVR. Overlay handles
  are then the module's own numbers.
- **The desktop window's cost.** VR frame times and GPU time by pass with a 1280 x 720 and a 3840 x 2160 window,
  same scene and preset; anything that scales with the window and is not needed in VR is removed or made smaller.
- VR off changes nothing (the usual flat controls, 5 + 5 alternating launches at least).

### 10. Settings (client console variables, archived, created by the page; F adds them, M puts them on the page)

| Variable | Default | Range | Meaning | Used by |
|---|---|---|---|---|
| `nl_vr_dominant` | 0 | 0 right, 1 left | Dominant hand | all |
| `nl_vr_move_dir` | 0 | 0 hand, 1 head | Smooth movement direction | L |
| `nl_vr_turn` | 0 | 0 snap, 1 smooth | Turning | L |
| `nl_vr_snap_angle` | 30 | 15-90 | Snap turn, degrees | L |
| `nl_vr_turn_speed` | 120 | 30-360 | Smooth turn, degrees a second | L |
| `nl_vr_teleport` | 1 | 0 off, 1 blink, 2 shift | Teleport | L |
| `nl_vr_vignette` | 0.6 | 0-1 | Vignette while moving or turning; 0 off | L |
| `nl_vr_seated` | 0 | 0, 1 | Seated mode | L |
| `nl_vr_seated_offset` | 0.45 | 0-1 | Metres added in seated mode | L |
| `nl_vr_height` | 0 | 0, 1.2-2.2 | Calibrated standing eye height in metres; 0 uses `nl_vr_scale` | L |
| `nl_vr_ghost_hands` | 1 | 0, 1 | The outline where the controller is when a hand is stopped | H |
| `nl_vr_gloves` | 1 | 0, 1 | Gravity gloves | P |
| `nl_vr_climb` | 1 | 0, 1 | Climbing | P |
| `nl_vr_melee` | 1 | 0, 1 | Melee | P |
| `nl_vr_wrist_hud` | 1 | 0, 1 | Wrist HUD | hud |

Settings are read at Start and when they change (`cvars.AddChangeCallback` registered at Start, removed at Exit).
Tests restore every one they change.

## Rules for every task

V1's rules hold ([VR-V1-plan.md](VR-V1-plan.md), "Rules for every task" and "Rules for PoC and VR tests"), with
these changes and additions:

- **Your branch, your paths.** Commit only on your branch, only in the files your brief assigns. Shared documents
  (CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING, AGENTS) are Q's, at integration: put your text for them in
  your report. Decision records: only the numbers your brief reserves, and their lines in
  `docs/decisions/README.md`.
- Commit as `SheepyLord <37598021+SheepyLord@users.noreply.github.com>` (the git config; pass no other author),
  messages ending with `Co-Authored-By: Codex <noreply@openai.com>`. Never push, merge into `main` or `vr2`,
  publish to the Workshop, start a GitHub workflow, or change `loader/`.
- gVRMod (`out\vr-plan\src` in the main checkout) is read for behaviour only; no code, comments or data are copied.
- **Offline first.** Every module gets LuaJIT tests with the harness's stand-ins (F extends V1's
  `companion/tests/vr_harness.lua`), C++ tests for native code. A PoC session proves what offline tests cannot;
  keep each under three minutes.
- **Simulated sessions before the headset.** Once N's simulated mode is on `vr2`, PoC sessions of features use it
  (the PoC lock only). Sessions on the Index (both locks) are for what needs SteamVR: the compositor, overlays as
  SteamVR shows them, real tracking, timing.
- **SteamVR may be closed.** If `vrserver.exe` is not running, a session on the Index starts it through `VR_Init`,
  as Start VR does for a player, and leaves it running; never start it another way, never quit it, never change its
  settings. Say in your report when your run started it.
- **The user's game may be running** (`...\common\GarrysMod`, often at 3840 x 2160). Never end it or any process you
  did not start; never write to the field install. Our PoC windows take the keyboard focus when they open: keep
  sessions few and short. A normal quit nobody asked for, or a Steam overlay in a screenshot, is likely the user's
  input reaching the test window: rerun, do not chase it in the code. Classify a failed launch from its minidump;
  `nvoglv64.dll+0xe622f8` at start-up is the old driver crash (RESEARCH): rerun.
- **Python.** The user's terminal runs Miniconda's Python without Pillow. Anything a person is told to run
  (`--look`) must work there; test it with a venv without packages.
- Translations of new page text (French, Japanese, Korean, Russian, Simplified and Traditional Chinese) are written
  by a Python script with explicit UTF-8 and checked for `?` runs; no hand-typed non-ASCII.
- Finish with `docs/handover/VR-V2-<task>-report.md` (V3 for P): what you built, the tests and their evidence, the
  numbers, what is open, your text for the shared documents; `tools\test.ps1 -Config Release` passing in your
  worktree.

## Done for V2

Shown on the Index by scripted sessions (test mode), with saved eye, overlay and mirror images and the probe's
records; each also in a simulated session:

1. Both hands drawn from the player model's hands, following the controllers; scripted finger curls bend the
   fingers; with `nl_vr_dominant 1` every mapping mirrors.
2. A hand pushed into a wall is drawn at the wall, with the outline overlay at the controller.
3. Smooth movement in the hand's and the head's direction moves the player the expected distance; snap turn and
   smooth turn turn about the head (its world position unchanged within 1 cm); the player follows the head when the
   person walks (a scripted head offset of 1 m moves the player 1 m) and the view stops at walls.
4. Teleport, blink and shift, lands on the arc's target, refuses a target where the player cannot stand, mantles onto
   a ledge; physical crouch, the crouch toggle, jump and sprint act; noclip flight follows the hand at the trigger's
   speed; height calibration sets the scale; seated mode raises the view; the vignette shows while moving and
   turning.
5. The wrist menu opens on the off hand's B; the spawn menu shows as a panel, and a laser click on a prop's icon
   spawns it; the context menu's world click (a property) aims with the hand's ray; the flat-screen panel shows the
   escape menu over black and a laser click on "Resume Game" resumes; a text field takes text from the keyboard
   (scripted).
6. The ghost lines of the user's report are reduced (R's crops and counts), and hands at 0.2 m (or R's measured
   limit) are whole in both eyes.
7. Exit VR leaves no hook, timer, network receiver of the add-on (the stub's one stays), overlay or setting behind;
   VR off costs nothing measurable with the new runtime.

## Done for V3

1. The hands push props and ragdolls and stop at walls; living NPCs are pushed, not grabbed.
2. Grip grabs the nearest prop within reach at the touched point; it follows the hand physically (a heavy prop lags,
   nothing passes through a wall); two hands hold a long prop along the line between them; letting go throws with
   the hand's velocity (within 20 % of the scripted hand's) and spin.
3. Gravity gloves: a loose prop pointed at within range is marked; a flick toward the body brings it to the hand on an
   arc; grip still held catches it.
4. Ragdolls: grip takes the nearest physics bone; dragging and posing with two hands; an NPC's death ragdoll too.
5. Use by hand: touching or gripping a button, a door or a lever uses it; ammo and health kits are taken by grabbing.
6. Climbing: gripping a ledge or a ladder holds the player; pulling moves the player; letting go of both falls.
7. Melee: a punch or a held object hitting something damages it, scaled by the hand's speed.
8. Haptics on contact, grab and release. Everything stops and is released at Exit and when the player dies.

## After V3: V4 (preview, so F and P leave room for it)

V4 (weapons and tools) follows on `vr2` before the user's approval: hand-aimed weapons drawn in the hand as world
models, shots along the gun (on our server from the muzzle through `EntityFireBullets`), the foregrip, physical
reload for the HL2 weapons and the button reload, ammo on the gun, the weapon wheel, the physgun and the toolgun
aimed by the hand. F's aim override (`NLVR.Aim`) and P's grab API are what it builds on.
