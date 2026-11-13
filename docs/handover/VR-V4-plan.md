# VR V4 work plan: weapons and tools

Claude's plan for milestone V4 of [VR-plan.md](VR-plan.md), on branch `vr2` after V2 and V3
([VR-V2V3-plan.md](VR-V2V3-plan.md)). V4 reaches `main` together with V2 and V3, and only when the user approves
them. Codex writes the code, Claude directs and reviews (the user's choice for the VR work).

## The user's request (2026-11-11, verbatim)

> Let's Start V2 and V3 together. When finished, also proceed to V4.

And, later the same day:

> carry on, report when V4 is done. You are allowed to terminate any field games when needed.

The design's line for V4: "Hand-aimed weapons; foregrip; physical reload for the HL2 weapons and the button reload;
ammo on the gun; weapon wheel; physgun and toolgun controls" (VR-plan.md, Milestones), with its sections
"Default controls on the Index" and "Weapons and tools".

## Where things stand

V2 and V3 are built by tasks F, N, R, H, L, M and P and merged into `vr2`; task Q integrates and accepts them (its
report `docs/handover/VR-V2V3-Q-report.md`). V4's tasks start from `vr2` once every V2/V3 task branch is merged into
it, beside Q's integration, and merge `vr2` into their branches when Q's fixes land.

What V4 builds on (read the reports in `docs/handover/`: F, N, H, L, M, P and, when it exists, Q):

- The client core `NLVR` (F): modules with `ctx.hook`, `ctx.On("frame")`, movers in `CreateMove` by priority,
  resolvers for the shown hands, `NLVR.Aim(angles, owner)` (the user command's view angles this tick, first owner
  wins), `NLVR.Ray(hand)`, `NLVR.Input` with claims, taps (released within 0.3 s) and holds, `NLVR.Overlay` with
  unique odd sizes (`ammo` 387 x 129 is already reserved), `NLVR.Net.Send(type, writer)`, `NLVR.Debug`.
- The server core `NLVR_SV` (F): VR players, their synced head and hands with a one-second history, `OnStart`,
  `OnStop`, `OnSync`, `OnDeath`, `OnSpawn`, server movers, `NLVR_SV.Net.On(type, fn)`.
- Hands (H): the c_arms world models drawn in `PreDrawTranslucentRenderables`, `NLVR.Hand[hand].grip_curls`
  closing the fingers, `NLVR.Hand[hand].shown` stopped at walls.
- Physical interaction (P): server hand proxies, grab and throw (`sv_interact*.lua`, P's report names its API),
  the client's claims sent to the server (a hand's grip or trigger claimed by another module is not P's), melee.
- Menus (M): the wrist menu, the spawn and context menus as panels with the laser (the spawn menu's tool list
  included), the flat-screen panel, the page's options (`VR.BuildOptions`).
- Movement (L): the main stick's turn, teleport and crouch, unless another module claims the stick.

## Decisions for V4

The table "Decisions taken with the user" in [VR-plan.md](VR-plan.md) and the V2/V3 decisions stay binding. These
are Claude's decisions for V4 (the tasks' decision records record them):

| Topic | Decision |
|---|---|
| The gun in the hand | The active weapon's world model as a client-side model at the main hand's **shown** pose (so it stops at walls with the hand), drawn as world geometry in the same stage as the hands; never the view-model pass. Placed through the world model's own right-hand bone (`ValveBiped.Bip01_R_Hand`, the bone a third-person bone merge uses) where it has one, with per-class corrections for the HL2 weapons and GMod's tools, the hand's fingers closed around the grip with the index finger on the trigger. A left-handed player holds the same model in the left hand, not mirrored. SWEPs with a `DrawWorldModel` of their own use it where it draws at our model's pose; otherwise the plain world model. |
| Where shots go | **Aim convergence**: every tick a weapon is out, the user command's view angles (`NLVR.Aim`) point from the player's eye (`EyePos`) to the first thing the gun's ray hits (or its far point), so every eye-based trace (the toolgun, SWEPs, the engine's aim) lands where the gun points. On our server, bullets of a VR player's weapon start at the gun's muzzle and fly along the gun (`EntityFireBullets`); the muzzle comes from the **server's** pose of the hand (P's stopped hand) and a trace from the eye to it, so no shot starts beyond a wall. The HL2 projectiles (rocket, bolt, SMG grenade, AR2 orb, frag) are moved to the muzzle (or the hand, for the frag) with their speed along the gun on the tick they appear. Tracers and the muzzle flash appear at the gun in the hand. |
| No recoil on the head | A weapon's view punch never moves the head camera; the gun model kicks briefly instead. |
| The hands weapon | `nlvr_hands`: a VR-only weapon with no models and no attacks, registered in both realms at Start (`weapons.Register`, not spawnable), given on our server at Start and after each spawn, stripped at Stop with the previous weapon selected again. Selecting it frees the main hand. GMod cannot unregister a weapon class: the table stays registered, unused, until the map changes; no instance exists outside VR. |
| Who owns the main hand | With any weapon but `nlvr_hands` out, the main hand's grip and trigger are the weapon's (claimed each frame); P's grab and use by hand keep the off hand. The off hand holds the foregrip, takes ammo and grabs. |
| Foregrip | The off hand's grip within 0.12 m of a weapon's foregrip point holds it: the gun aims along the line from the main hand to the off hand, the off hand is drawn on the foregrip; letting go of the grip or pulling the hands more than 0.25 m from the point ends it. Weapons with a foregrip: SMG1, AR2, shotgun, crossbow, RPG, physgun; SWEPs whose world model is longer than 0.45 m get a point along the barrel. Setting `nl_vr_foregrip`. |
| Physical reload | For the HL2 guns, while `nl_vr_physical_reload` is on: the engine's reload never runs. The user command's reload is dropped for them and, while the clip is empty or out, the weapon's next primary fire is held in the future (`SetNextPrimaryFire`), which also stops HL2's automatic reload and its switch away from an empty gun. Our server puts the rounds in (`SetClip1`, `RemoveAmmo`) when the client's insertion checks out against the server's own hand poses. Pistol, .357, SMG1 and AR2: **A ejects** (rounds still in the magazine go back to the reserve; the dropped magazine is a client-side model for 10 seconds), the off hand gripping **over the shoulder** takes a magazine (only with reserve ammo), **inserting it into the well** reloads. Shotgun: shells one at a time into the loading port. Crossbow: a bolt onto the rail. RPG: a rocket into the tube; after each shot the RPG is empty until one goes in. The models held are base-game models (HL2 items and projectiles), no new assets unless original and redistributable. |
| Button reload | A tap of the main B is the reload button for one tick (every weapon without physical reload, the HL2 guns with it off, the toolgun's reload, the physgun's unfreeze). |
| A on the main hand | Secondary attack (`IN_ATTACK2`) while held: the toolgun's secondary, the physgun's freeze, the crossbow's zoom, the shotgun's double shot. For a weapon with an ejectable magazine under physical reload, a tap of A ejects and a hold of 0.3 s or more is the secondary attack (the SMG1's grenade, the AR2's orb); the off hand's trigger on the foregrip also fires the secondary. |
| Melee weapons | With `nl_vr_melee` on, the crowbar and the stunstick hit by swinging: the weapon's head moving fast into something deals that weapon's damage type, scaled by speed, through P's melee path; the trigger does not swing them. With it off, the trigger swings as in the flat game. |
| The frag grenade | The trigger held pulls the pin (HL2's own flow), releasing it throws the grenade from the hand with the hand's throw velocity (P's averaging), on our server. |
| Ammo on the gun | The `ammo` overlay (387 x 129) attached to the main hand: clip / reserve and the secondary reserve, painted only when they change, hidden for weapons without ammo. Setting `nl_vr_ammo_counter`. |
| Tool info on the gun | A `tool` overlay beside the gun while the toolgun is out: the tool's name and what trigger, A and B do; painted on change. |
| Weapon wheel | Holding the main B 0.3 s opens a ring overlay at the hand, facing the head: `nlvr_hands`, then the player's weapons by HUD slot (the physgun and toolgun included), each with its selection icon where one exists and its name. Moving the hand toward an entry highlights it (dead zone 3 cm); releasing B selects it. A tap of B never opens it. |
| Physgun | Trigger grabs (the engine's physgun, so prop protection and add-on hooks still decide). While it holds a prop: the prop sits on the gun's line (the aim converges on the held distance, not on the prop itself), it **turns with the hand**, the main stick's up and down push and pull it (the stick is claimed while holding), A freezes, a tap of B unfreezes. The beam starts at the gun in the hand. |
| Toolgun | Aimed by the hand (convergence); trigger primary, A secondary, tap B reload; the tool is chosen on the spawn menu panel's tool list (M). |
| Settings | `nl_vr_physical_reload` (1), `nl_vr_foregrip` (1), `nl_vr_ammo_counter` (1), `nl_vr_gun_angle` (0, -45 to 45 degrees: the gun's pitch in the hand), on the page under "Weapons". |

## The tasks

| Task | What | Branch and worktree | Starts |
|---|---|---|---|
| S | The scaffold: module lists, protocol ranges, overlay sizes, settings and their page controls with translations, stub modules, the harness's weapon stand-ins, the gate's bridges | `v4s` | when the V2/V3 tasks are merged into `vr2` |
| W | Weapons in the hand: models and grip, aim convergence, shots and projectiles from the muzzle, tracers and muzzle flash, no punch on the head, `nlvr_hands`, the main hand's ownership, foregrip, melee weapons, the frag grenade | `v4w` | when S is merged |
| K | Reloading: physical reload of the HL2 guns, the button reload, the ammo counter | `v4k` | when S is merged |
| T | Tools: the physgun, the toolgun and its info overlay, the weapon wheel | `v4t` | when S is merged |
| Q | V4's integration and acceptance on the Index (Q's V2/V3 thread continued), the final report for V2, V3 and V4 | `v2q` | when W, K and T are merged and Q's V2/V3 work is done |

Each worktree is `out\worktrees\<branch>`, cut from `vr2` when the task starts. Claude merges reviewed tasks into
`vr2`. K and T build on W's `NLVR.Weapon` (below): until W is on `vr2` they test against their own stand-in of it
offline, then merge `vr2` into their branches for PoC runs.

## Interfaces (binding; a task that cannot keep one says so in its report at once)

### 1. Files

```
vr/addon/lua/nlvr/modules/
  cl_weapons.lua, sv_weapons.lua (and cl_weapons_*.lua, sv_weapons_*.lua, sh_weapons_*.lua)   W
  cl_reload.lua, sv_reload.lua (and cl_reload_*.lua, sv_reload_*.lua, sh_reload_*.lua)        K
  cl_tools.lua, sv_tools.lua (and cl_tools_*.lua, sv_tools_*.lua, sh_tools_*.lua)             T
```

S adds `weapons`, `reload` and `tools` to the client's fixed list in `client.lua` and `sv_weapons.lua`,
`sv_reload.lua`, `sv_tools.lua` to `server.lua`'s, as stubs that register and do nothing, and makes sure the new
files reach the client the way F's do. After S the lists do not change. Module orders (client): weapons 44, reload
46, tools 48: after the UI (40), whose laser claims the trigger first, before interact (50), so their claims of a
hand's grip and trigger are in place when P reads them.

### 2. Network

S widens the module message range to 16..127 in `sh_protocol.lua`: weapons 64-79, reload 80-95, tools 96-111;
112-127 stay free. Nothing else in the sync changes.

### 3. The weapon in the hand (`NLVR.Weapon`, client, W)

- `NLVR.Weapon.Active`: nil, or `{ent, class, kind, model, hand, twoHanded}`: `kind` is one of `hands`, `melee`,
  `grenade`, `physgun`, `toolgun`, `clip` (the HL2 pistol, .357, SMG1, AR2), `shotgun`, `crossbow`, `rpg`, `swep`;
  `model` the client-side model in the hand (nil for `nlvr_hands`); `hand` `"left"` or `"right"`; `twoHanded` true
  while the off hand holds the foregrip.
- `NLVR.Weapon.Muzzle()`: world position and angles of the muzzle; `NLVR.Weapon.Ray()`: origin and direction of
  the gun's aim (one or two hands).
- `NLVR.Weapon.Kind(class)`: the kind of any weapon class.
- Events: `"weapon_changed"` (Active), `"weapon_fired"` (Active).
- `NLVR.Weapon.ConvergeAt(distance or nil)`: T's physgun sets the held distance, so the aim converges on the point
  at that distance along the gun's ray instead of the first hit; nil returns to the first hit.
- On the server, `NLVR_SV.Weapon(ply)`: `{class, kind, muzzle = {pos, ang}}` from the server's own hand pose, for K
  and T.

K and T compute their own points (the magazine well, the eject port, the overlays' places) from `Active.model`'s
local frame with their own data, so W's placement can change without breaking them.

### 4. Controls (main and off hand, mirrored for left-handed players)

| Control | Owner | Action |
|---|---|---|
| Main trigger | W | `IN_ATTACK` while held (any weapon but `nlvr_hands`; claimed while armed) |
| Main grip | W | Claimed while armed (nothing grabs with the gun hand) |
| Main A | W, or K when it claims it | W: `IN_ATTACK2` while held. K claims it for an ejectable magazine under physical reload: tap ejects, a hold of 0.3 s or more presses `IN_ATTACK2` |
| Main B | K (tap), T (hold) | Tap: `IN_RELOAD` for one tick unless physical reload applies. Hold 0.3 s: the weapon wheel |
| Main stick | T while the physgun holds a prop | Up and down push and pull; otherwise L's |
| Off grip | W near the foregrip, K over the shoulder or holding ammo | Otherwise P's |
| Off trigger | W while on the foregrip | `IN_ATTACK2` (the under-barrel secondary); otherwise P's and M's |

Claims are made in the `"frame"` event (before `CreateMove`'s movers); a module presses buttons in its own mover and
only for controls it owns this frame. Button presses go into the user command; nothing calls `+attack` console
commands.

### 5. Overlays

S adds unique odd sizes to `cl_overlay.lua`: `wheel` 1035 x 1037, `tool` 643 x 133; `ammo` 387 x 129 is F's.

### 6. Settings

S adds `nl_vr_physical_reload` (1, 0-1), `nl_vr_foregrip` (1, 0-1), `nl_vr_ammo_counter` (1, 0-1) and
`nl_vr_gun_angle` (0, -45 to 45) to the page's settings table and a "Weapons" group to `VR.BuildOptions`, with
translations (French, Japanese, Korean, Russian, Simplified and Traditional Chinese) written by a Python script with
explicit UTF-8 and checked for `?` runs.

### 7. Server hooks

The server modules hook through `ctx.hook` (one id per module): W owns `EntityFireBullets` and the projectiles'
`OnEntityCreated`; K owns `StartCommand` (dropping the reload button and holding the next primary fire for physical
reload); T owns the physgun's hooks. A module never overrides another's return value; when two need one hook they
say so in their reports.

## Rules for every task

The V2/V3 plan's "Rules for every task" hold unchanged ([VR-V2V3-plan.md](VR-V2V3-plan.md)), with these additions:

- Your report is `docs/handover/VR-V4-<task>-report.md`; your decision records only the numbers your brief reserves
  (S 0175, W 0176-0178, K 0179-0180, T 0181-0182, Q 0183-0185), with their lines in `docs/decisions/README.md`.
- Your offline tests run in the gate: a bridge file in `tools/tests/` (as `test_companion_vr.py` does for
  `companion/tests/test_vr.py`) imports your companion test cases; the gate's log shows their count.
- PoC sessions use the simulated mode (`tools/vr_session.py --simulate`, the PoC lock only) for features; the Index
  (both locks) for what needs SteamVR: overlays as SteamVR shows them, real timing, the final acceptance runs.
- The user allows ending their field game (`H:\SteamLibrary\steamapps\common\GarrysMod`) when a test needs the GPU
  or SteamVR: a normal console quit with `python H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\v2\quit_field_game.py`
  from the main checkout; say so in your report. SteamVR is running: never quit it or change its settings.
- Every weapon test names the weapon class, the scripted poses, and the measured result (positions in metres,
  angles in degrees, counts); captures of the eyes and overlays for what a person would look at.

## Done for V4

1. **Weapons in the hand**: the crowbar, stunstick, pistol, .357, SMG1, AR2, shotgun, crossbow, RPG, frag grenade
   and bug bait, the physgun, the toolgun and the camera, and two Lua SWEPs (the medkit and the fists) appear in the
   main hand at their grip, lit as world geometry, with the fingers around the grip; a switch changes the model
   within one frame; the left-handed setting moves it to the left hand; a stopped hand stops the gun; Exit leaves no
   model, hook or `nlvr_hands`.
2. **Shots along the gun**: with the head turned 45 degrees away from where the gun points, each HL2 gun's bullets
   start within 5 cm of the muzzle and hit where the gun's ray points (impacts within 5 cm at 5 m and 10 cm at
   20 m, spread aside); the rocket, bolt, SMG grenade and AR2 orb leave the muzzle along the gun; tracers and the
   muzzle flash at the gun; with the hand pressed through a wall no shot starts beyond it; no view punch moves the
   camera.
3. **Foregrip**: with the off hand on the SMG1's and the shotgun's foregrip the aim follows the line between the
   hands (within 2 degrees); letting go returns to one-hand aim; the off hand is drawn on the foregrip.
4. **Physical reload**: pistol, .357, SMG1 and AR2: fire, eject (clip 0, the rounds back in the reserve, a
   magazine drops), wait 5 seconds (no fire, no engine reload, no weapon switch), a magazine from over the shoulder
   into the well (clip = the smaller of clip size and reserve, the reload sound); the shotgun shell by shell; the
   crossbow's bolt; the RPG's rocket; no magazine with an empty reserve; with physical reload off, tap B reloads
   them as in the flat game; other weapons reload on tap B.
5. **Ammo on the gun**: the counter shows the active weapon's clip / reserve and secondary reserve, repaints only
   on change, hides for weapons without ammo, follows the weapon hand.
6. **Weapon wheel**: holding B opens it with `nlvr_hands` and every weapon; pointing and releasing selects (the
   active class changes to the one pointed at); a tap of B does not open it.
7. **Physgun**: the trigger picks up the prop the gun points at; turning the hand turns the prop (yaw, pitch and
   roll each within 5 degrees of the hand's rotation after settling); the stick pushes and pulls it (distance
   changes measured); A freezes it, a tap of B unfreezes; the beam starts at the gun.
8. **Toolgun**: a tool chosen on the spawn menu panel; the trigger applies it where the hand points (the remover
   removes the pointed prop; the colour tool colours it); A and tap B do the secondary and reload; the tool's info
   shows beside the gun.
9. **Melee**: swinging the crowbar into a breakable or a prop damages it, scaled by speed; a slow touch does not;
   the trigger alone does not swing it.
10. **Grenade**: the frag leaves the hand with the hand's velocity (within 20 %) when the trigger is released.
11. **Hands**: selecting Hands frees the main hand (it grabs and uses); with a weapon out the main hand's grip does
    not grab.
12. **Death, respawn and Exit**: death keeps VR running, respawn gives `nlvr_hands` again and rebuilds the models;
    Exit restores the previous weapon; with VR off nothing of V4 runs; flat parity holds.
