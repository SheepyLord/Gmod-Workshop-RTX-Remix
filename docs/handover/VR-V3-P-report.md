# VR V3 task P: physical interaction

Task P is implemented and accepted on **v3p**. Production implementation is **d1dae31**,
after the release-contact fix **434929b**. The final probe adds an acknowledged first phase.
N was merged from vr2 through **38405e9** and reviewed H through **ff0a671**; both additive
decision-index conflicts kept both tasks' entries. No F core change was needed.

No push, merge into main/vr2, Workshop publication, workflow start, loader edit, field-file
write or trust-rule change was made. Commits use the configured SheepyLord identity and the
required Codex trailer. No P native binary or package input was imported; N's accepted
module/provenance arrived through the authorised upstream merge.

## Built

- **Server hands and grabs:** invisible non-transmitting 8 kg spheres, radius 0.075 m,
  follow by bounded velocity, push props/ragdolls, stop at geometry and exclude their own
  player. The server world stop retains H's 18 cm finger envelope; movable-body contact uses
  the sphere. Sweep hits supply contact feedback when base_anim omits PhysicsCollide.
  Living NPCs receive velocity pushes and are never grabbed.
- **Protected physical holding:** nearest physics-triangle surface within 0.16 m, per
  ragdoll bone, with hull/bone-centre fallbacks. The box broad phase includes distant-origin
  long props. Holding uses a damped force spring, bounded angular acceleration and unchanged
  prop mass/gravity/owner/collision flags. Two grips align the local grip baseline with the
  hand baseline; separate ragdoll bones are driven independently. Contact displacement stays
  hand-local, preventing a surface from snapping into the wrist sphere.
- **Grab API for V4:** `NLVR_SV.Grab(ply,hand,ent,bone,localPos,localAng)`,
  `Release(ply,hand,throw)`, `Holding(ply,hand) -> ent,bone`. Hands are physical left/right;
  offsets are physics-bone local. Omitted offsets choose the nearest surface/current hand
  orientation. Invalid requests preserve an existing grip. Server events include player;
  client grab/release events carry hand/entity/bone. Hand.held/grip_curls are set before
  events. An unoccupied squeezed hand can acquire a later contact without another edge.
- **Throws:** recency-weighted 120 ms server history, world-radian to local-degree spin,
  and mass-centre velocity correction. The last grip releases; one hand letting go while
  another holds the body adds no throw. A 0.2 s hand/player pair grace prevents an opening
  proxy from punching its own throw. World collisions stay active; grace expires through
  the module tick and is cleared immediately at death/Exit/unload.
- **Gravity gloves:** protected loose-body ray up to 6 m/150 kg, grip lock and inward
  displacement/speed flick, ballistic launch with actual gravity, final-segment retargeting,
  and a catch through Grab. Miss/obstruction/permission/setting changes end assistance.
  Target markers use the two reserved SteamVR overlay canvases, with no halo/world UI.
- **Climbing, use and melee:** world lips/side edges and native/brush ladders; priority-5
  hull-swept move-data arbitration suppresses ordinary gravity while anchored, supports two
  hands and keeps release velocity. Floor/ceiling do not stop an anchored hand. Climbing
  closes the grip pose. Touch/press uses buttons, doors, levers and authored Lua Use. Native
  kits use their engine inventory trigger, not handmade rewards; refused/full staging restores
  transform/velocities after 0.15 s or cleanup. Base_anim's empty Use cannot consume a grab.
  Club damage starts at 1.5 m/s, scales to 65, and has a 0.35 s target cooldown. Held-object
  callbacks queue work outside the physics solver. Contact/grab/release/catch/hit pulse distinctly.
- **Lifecycle/debug:** invalid/stale tracking, vehicle entry, moved-player reach violations,
  death, module failure and Exit release bodies and remove proxies/callbacks. Death keeps VR
  active. Player custom checks and session-only ai_serverragdolls restore. Message 40 carries
  settings/claim masks; 41 coalesces proxy/grip/climb/target/throw/haptic state. Client priority
  200 resolves after H; stale state expires. No permanent P hook, timer or receiver exists off.

The design records are [0169](../decisions/0169-physical-vr-hands-and-grabbing.md),
[0170](../decisions/0170-gravity-gloves-and-climbing.md),
[0171](../decisions/0171-vr-use-by-hand-and-melee.md). Implementation lives only in the
assigned interact modules/helpers and tests; shared-document text is below.

## Accepted measurements

Evidence root: **this worktree's out/vr/v3p/**. Raw before/after world vectors are retained in
`measurements.json` and each `interaction.json`, alongside the eye/overlay/mirror pictures.
`sim-14/interaction-checks.json` accepts **every phase 0..13 in one run**. This is the final
certificate; earlier partial/composite certificates are superseded.

| Requirement | Final simulation measurement |
|---|---|
| Push / obstruction | Barrel displacement **50.993 units**; blocked controller/proxy separation **26.235 units** |
| Grab / native throw | **9** held samples; scripted wrist **120 units/s**; native velocity **(-117.4609,-5.2018,0)**; vector error **4.824%**, under 20% |
| Native spin | **1.163526 rad/s**, against **1.1636** scripted |
| Two-hand plank | Alignment dot **0.998230** |
| Heavy body | 250 kg crate lags **8.898 units** |
| Ragdoll | Separate nearest physics bones **5 and 7**; both drag/pose |
| Gloves | Mark, arc and catch pass; **2** in-flight / **17** held samples; first catch surface distance **3.447 units** |
| Use / kits | Button on; door opening/open states; health **50 -> 75**, armour **10 -> 25**, pistol ammo **20 -> 44** |
| Climb / ladder | Ledge rise **12.302 units** against scripted 12; **16** ladder-grip samples; release falls at **-24.869 units/s**, later **-330.869** before landing |
| Melee | Punch breaks melon; held-object impact **125.018 units/s / 24.505 club damage**, second melon breaks |
| Living NPC | Health **100 -> 49**; horizontal push **2.304 units**; no living grab |
| Death / cleanup | Server NPC death ragdoll grabbed; player death leaves VR active with **0 held / 0 proxy**; Exit restores state |
| Haptics | Contact/grab/release/catch/hit kinds **1/2/3/4/5** witnessed |

The final simulation renders **9266 matched frames**, **0 unmatched/Submit errors**, without
OpenVR or a VR lock. It keeps **20 complete capture sets**. These are rendered simulation
frames, not compositor submissions. The scene's native baseline is selected from a clear
brush volume; natural ragdoll joints are preserved under a rigid transform. Phase 13 isolates
held impact from punch debris. The server acknowledges each phase before retries stop.

The required real **Index session index-03** uses the same **v3p.14** package, scripted
grab/throw/gloves, and both locks. It accepts **1169 / 1169** submitted/matched
eye pairs, **0** Submit errors, unmatched poses, dropped compositor frames or Lua errors.
Native throw vector error is **4.776%**, spin **1.163126 rad/s**;
mark/pull/catch and all short-session checks pass. Native haptics make **18 requests** and
record success/error **true / 0**. Five complete capture sets remain.

Index: **90 Hz**, **2468 x 2740 per eye**, centre **3080 x 2752**, traced **1540 x 1376**,
window **1280 x 720**, scale 1, mat_queue_mode 2. The capture-heavy short interval is
**38.200 pairs/s**, GPU commands/SDK **14.099 ms**,
compositor app GPU **12.089 ms**, **49.00%** reprojected presents.
These are reference receipts on a shared machine, not a performance or worn-comfort claim.

Both accepted runs complete two Start/Exit cycles, restore every compared variable/live
selector, unload OpenVR, and leave only PopulateToolMenu:nativeloader_vr on the client.
Server lifecycle returns to **0 session hooks**, with F's one permanent receiver. Each rollback
verifies **2877 depot files**, no missing/size/hash mismatches and unchanged protected user.conf.
No field game was running in the accepted inventories, so the authorised quit helper was
not needed. SteamVR was already running; P neither started it nor quit/reconfigured it.

## Tests, rejected attempts and reproduction

- **28/28** standalone interaction LuaJIT cases pass (`offline-final-current.log`): geometry,
  long-prop/bone reach and protection, 100 rigid round trips, vertical/two-hand frames, twenty
  ballistic endpoints, flicks, history/spin, impulse integration at 30/66/120 Hz, heavy inertia,
  use/inventory staging, damage/cooldown/held callbacks, claims/events/stale state, floor/wall
  climbing, scale changes, moved-player reach, contact offsets/release grace and sweep haptics.
- Original framework/page/guard/catalog **80/80** and reviewed H's **21/21** pass separately.
- Final `tools/test.ps1 -Config Release` **PASS**: **34/34 CTest** in **56.25 s**; Python
  **29 + 26 + 909 = 964 tests**, one availability skip, no failures,
  ending **All checks passed** (`release-final-current.log`). The assigned prefix suites run
  explicitly; Q can add their imports to the tools-only discovery at integration.
- `acceptance.json`, `measurements.json`, `git-audit.json`, package JSON and raw run folders
  consolidate the receipts. Captures were visually inspected using display thumbnails;
  original PNGs are untouched. Whole near hands in both warped eyes are not claimed below.
- sim-02 hit WinError 206 before game launch; JSON launch-argument transport fixed it.
  sim-03's nonexistent button SetToggle and early first phase were corrected. sim-05 is
  excluded after the retained dump proves **nvoglv64.dll+0xe622f8 / 0xC0000005**, the known
  startup driver fault. All preparations restored cleanly.
- Earlier combined fixtures intersected the spawn platform or strained a corpse into two
  contact goals. Those rejections remain. More importantly, the native audit rejected the old
  setter-only throw check: requested about 120 became **1257 units/s** with an own-hand hit.
  **434929b** fixes contact offset/release grace; the final checker measures actual native
  velocity/spin. `superseded-acceptance.json` prevents the old composite from being mistaken
  for final acceptance. Only sim-14 and index-03 certify the delivered behavior.
- Index-01/02 were cancelled before a game launch. The latter released only P's own verified
  VR lock after the throw defect was found. No other task's lock/process was removed. The
  driver verified rollback before deleting its generated bulk copies; hash-checked superseded
  local packages reclaimed **18.769 GB**, with logs/hashes/pictures retained.

```powershell
python companion/tests/vr_interact_tests.py -v
py -3 companion/tests/vr_interact_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v3p.14.gma --evidence out/vr/v3p/next-sim --seconds 116 --simulate
python companion/tests/vr_interact_analyse.py out/vr/v3p/next-sim
py -3 companion/tests/vr_interact_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v3p.14.gma --evidence out/vr/v3p/next-index --seconds 30 --interact-phases 1,9
python companion/tests/vr_interact_analyse.py out/vr/v3p/next-index --phases 1,9
tools/test.ps1 -Config Release
```

Selected package: **1795 files**, **2085497085 bytes**, SHA-256
**a468404a83b2649dc80fc6106e0257a1d341d30ff5c2e96355cde76c2182e1ce**; content digest **a90d99d4449e24ee3dc05c8aa70f571ff327d1ef6800cb48026058d913c986dd**. It is local, not published.
Unattended tests use installed Python 3.12 with Pillow (`py -3`); no package was installed.
The native/launcher path restrictions, allowlist and off switches remain intact.

## Research and open integration

Use-key pickup permission is **AllowPlayerPickup**, sv_playerpickupallowed and optional
CPPICanPickup; inventory uses PlayerCanPickupItem; use retains PlayerUse/CPPICanUse. False
denies. Frozen bodies stay frozen. See [Facepunch's pickup contract](https://wiki.facepunch.com/gmod/GM:AllowPlayerPickup).
The engine, not copied kit reward code, owns health/ammo grants.

[ApplyForceCenter](https://wiki.facepunch.com/gmod/PhysObj:ApplyForceCenter) takes kg*unit/s
**impulse**: force must be multiplied by dt. [GetSaveTable](https://wiki.facepunch.com/gmod/Entity:GetSaveTable)
uses DEFINE_KEYFIELD's map alias, hence point0/point1/StartDisabled. The reference-only Valve
SDK copies in out/vr/v3p show CItem::Use doing ordinary object carrying (item_world.cpp:223),
ItemTouch granting inventory (424), and point ladders being nonsolid with origin-relative
endpoints (func_ladder.cpp:57/116/288). No SDK/gVRMod code, comments or data were copied.

**Open:** Q must combine P with the current L/M/V4 work and R's single native runtime import,
repeat the combined locomotion/menu/weapon acceptance, and obtain milestone approval.
The packaged runtime is unchanged by P; H/R's near-depth/disocclusion limitations remain,
so these captures do not establish whole hands at 0.2 m in both eyes. Worn comfort, actuator
feel, other headsets/controllers and full multiplayer are not claimed. There is no remaining
P implementation/test blocker, and no user approval/main merge/publication was attempted.

## Additive text for Q's shared documents

- CHANGELOG: VR gains authoritative physical hands, protected surface/bone grabs, two-hand
  posing, history throws, gravity gloves, native hand use/kit pickup, climbing, melee and haptics.
- COMPONENTS: sv_interact composes maths/physics/actions and exposes V4's grab API;
  cl_interact owns the late hand resolver, grip state/events, haptics/debug and glove overlays.
  F owns lifecycle/network/movement arbitration; H owns actual models/fingers/ghosts.
- ROADMAP: task P is implemented/accepted on v3p; whole-milestone approval remains Q/user work.
- TESTING: run 28 explicit LuaJIT cases, the fourteen-phase simulated fixture, and the short
  real Index fixture. Require actual native throw velocity/spin, per-phase eye/overlay/mirror
  captures, all teardown/settings/protected-file/depot receipts; retain rejected witnesses.
- RESEARCH: record impulse units/dt, save-table aliases, native item Use versus touch,
  supporting contact offsets and release collision grace, plus the exact measurements above.
  Simulation rendering and real compositor submissions must remain separate.
