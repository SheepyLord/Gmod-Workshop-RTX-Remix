# VR V4 task W: weapons in the hand

Implemented on **v4w**. The stable interface was committed first as **9cfbbae**; gameplay
is in **7a9f1a7**, calibration in **2e53ca3**, launch/ownership corrections in **9a91715**
and **a524d1d**, final attack/custom-draw handling in **4bebe5a**, and the held camera's
scoped classic-tag correction in **9e9b32e4**. **325927a** is the
authorised inbound merge of reviewed M/R follow-ups from vr2 at **61237bfd**. The later
probe corrections do not change the packaged gameplay. No push, merge out, publication,
workflow, loader edit or W native import was performed.

W's delta from vr2 contains only its assigned weapon modules/sidecars, W-prefixed tests,
decisions 0176–0178 and 0193 (then numbered 0191)/index lines and this report. `out/vr/v4w/package-audit.json` checks
that scope and the actual archive bytes. All evidence paths below are relative to this
worktree, under **out/vr/v4w/**; nothing under out is committed.

## Built and available to K/T

- Session-owned `NLVR.Weapon` with **unchanged plan section 3 interface**: Active has
  ent/class/kind/model/hand/twoHanded; Kind, Muzzle, Ray, ConvergeAt and the two events.
  The table lives until Exit; read its current Active after a switch. Muzzle/Ray return
  nil without a valid armed pose. Distances are game units, angles Source degrees.
  Hands has no model; the stock fists also have an intentionally empty WorldModel and
  use H's posed hands. K/T should derive their points from the current model's own frame.
- `NLVR_SV.Weapon(ply)` returns class/kind and checked world muzzle pos/ang, from P's
  physical hand when available. Muzzle angles describe the **gun ray**, including gun
  pitch/two-hand aim, rather than the model's authored local axes. Invalid/current-class
  geometry or expired tracking returns nil. It uses F's one-second pose validity bound,
  reach validation and an eye-to-muzzle trace with 1 cm skin.
- Main grip/trigger claims precede P; UI keeps first priority. W leaves A unclaimed so
  K can own it, then reads the final claim in its mover. B/stick remain K/T's. Both
  inherited attack bits are discarded while armed; owned controls add IN_ATTACK and
  IN_ATTACK2. No console attack commands. Hands frees the main hand for P.
- World models draw in the hands' world stage, never the view-model pass. Per-model
  right-wrist position, authored upright axes and muzzle/rail calibration keep guns
  upright at the grip. Left dominance uses the same unmirrored model. Skin/bodygroups
  are copied at creation. Known foregrips are SMG1/AR2/shotgun/crossbow/RPG/physgun;
  long unknown SWEPs get a bounded barrel point. The off hand snaps onto that point;
  both its shown baseline and controller baseline agree with the gun line.
- Convergence points engine eye aim at the gun's first hit, or T's ConvergeAt distance.
  Initial native bullets within five units of the player's shoot position start at the
  checked muzzle, retaining spread and the original callback/return value. Penetration,
  ricochet and projectile-impact starts remain theirs, including missing-geometry gaps.
  Only the player/active weapon is redirected; owned turrets are left alone. Missing VR
  geometry suppresses only an unsafe initial VR shot instead of reverting to eye origin.
  Private messages 64/65/66 carry geometry, shot feedback and matching geometry-token
  acknowledgements. Geometry retries at 10 Hz until acknowledged; initial/profile changes
  gate attacks. Gun-angle updates keep firing on the accepted profile; foregrip engagement
  is decided by the host's hand-distance check, without resending the profile.
  Metre offsets and unit directions use explicit floats, avoiding net vector quantisation.
- Rocket, bolt, SMG grenade and AR2 orb preserve launch speed along the gun. Their own
  entity is excluded from the muzzle safety trace. Frag/bugbait retain the velocity from
  P's 120 ms history at trigger release, through the native animation delay. P's public
  Grab/Release(false) registers physical release grace when allowed; owned target
  cooldowns also protect against its separate swept-hand melee force. Temporary native
  no-collide pairs/custom flags last 200 ms, affect only owner/proxies and restore exactly.
  World collisions remain active; subsequent projectile motion belongs to the engine.
- Crowbar/stunstick heads use P's **unchanged** Hit/Damage helpers, cooldown and damage
  type, with sounds/impact effects. Slow contact does nothing; physical melee disables
  trigger swings. Turning that setting off returns attack to the engine. No head punch
  is added: only the gun model kicks for 120 ms. Tracer, world muzzle flash and its brief
  light use explicit muzzle coordinates.
- `nlvr_hands` registers lazily in both realms, has no models/ammo/attacks/auto switching,
  is given at Start/after spawn and stripped at Stop. Only an initially unarmed player
  selects it automatically. Stop changes selection only from Hands: the pre-VR class when
  available, otherwise the best owned weapon. Another selected weapon stays selected. GMod's
  class registration necessarily remains unused until map change.
- Debug records include class/kind, model pose, grip calibration, muzzle/aim, foregrip,
  draw/fire counts, host readiness, actual bullet source/direction/hit and native launches.

The camera's original texture hash **0x35D7392325ED05A9** is ignored by the inherited
classic layer. While its exact stock model is held, W adds only that hash's negative
runtime delta, then restores the prior value at switch/Exit. Existing user negatives
remain theirs; a newer writer's unrelated changes survive. W never saves config or
edits user.conf. The original client model/material render normally; no diagnostic
mesh, substituted material or additional asset ships.

The toolgun's hidden first-person RenderScreen is held only on its real instance while
active, restoring the raw value only if W still owns it. It otherwise erased the traced
hands in the saved toolgun frame; T's overlay supplies tool information. Custom SWEP draw
functions run on the relocated model only when they actually draw it. Errors or an
owner-dependent empty return fall back once to the plain model. Custom drawing leaves
weapon globals/class tables untouched. The review's owned bullet dispatcher is described below.

P's current passive touch Use does not honour its claim mask. W holds/restores only the
armed main hand's existing use cooldown, and suppresses that main proxy's unarmed damage.
Off-hand use/damage remain available. These are scoped W workarounds; no F/H/P file changed.
Q can make per-hand ownership/released-projectile registration explicit in P later.

## Tests and selected evidence

This section records the initial **v4w.11 / 27c509b5** acceptance. The independent-review
corrections and current tests are recorded separately below; no new Index run was requested.

**46 offline cases pass**: 44 actual-module LuaJIT cases plus two independent evidence-
math cases. S's exact bridge discovers `companion/tests/vr_weapons_test.py` in the gate.
They cover classification, 100 rigid grip transforms, handedness, model lifecycle/draw
fallbacks, claims, convergence/distance, shown/controller foregrip lines, finite/reach/wall
guards, callbacks/spread, projectile exclusion/redirection, acknowledgement retry, hands
lifecycle, shared damage/cooldowns/throw averaging, collision-pair cleanup and view isolation.
The capability guard leaves W resource-free when the engine weapon library is absent;
F/S's original core harness has no such library. W's own harness supplies it and runs W.

**Final complete simulation: sim-all-04**, local package **v4w.11**, both standard renderer
acceptance and `weapons-checks.json` pass. **42 phases**, four seconds per phase, **178 s
active interval**, two Start/Exit cycles, **46 full capture sets**. Map startup, console
transport, flat phases and rollback are additional to the active interval. The production
driver owns the PoC lock and no VR lock/OpenVR in simulation. An owned test mover clears
desktop inputs before L/W process the actual native timeline controls.

Scripted inspection: head `(0,0,1.6) m`, main/right `(.5,-.2,1.4)`, off/left
`(.45,.35,1.25)`, controller angles zero. Firing: head yaw **45°**, main
`(.5,.1,1.4)` pointing forward; native frozen target faces exactly **5/20 m from the
muzzle**. SMG/shotgun foregrip controllers move from `(.5+fore,.1,1.375)` to
`(.5+fore,.16,1.375)`, grip held then released. Fast melee advances the wrist **0.5 m
in 0.15 s**, slow melee over **1.8 s**. Frag/bugbait release during a **2 m/s** stroke.
Native grenade/projectile positions/velocities and actual post-spread traces are recorded;
the labelled zero-spread native diagnostics supplement actual trigger shots, not replace them.

| W acceptance | Selected simulation measurement |
|---|---|
| Models/switch | All 16 classes inspected; model wrists agree with shown wrists within 5 mm; ordinary/respawn/dominance switches **0–1 frame** |
| Native hitscan | **84 actual native pellet traces**, plus **10 labelled zero-spread diagnostics**; diagnostics hit both required target ranges with **0 reported lateral error**, gun/head difference **45°** |
| Native starts | Checked native starts equal host muzzle; maximum difference from the rendered static muzzle **0.0000025 m**, at the receipt's printed float precision |
| Foregrip | SMG controller/shown errors **0.00209° / 0.00204°**; shotgun **0.00206° / 0.00184°**; snap error **0 m**; release returns to one-hand aim |
| Projectiles | All six native classes observed; all redirect on **tick 1**; bolt/rocket/SMG grenade/AR2 orb initial direction error **0°** |
| Physical throws | Requested **80 units/s = 2 m/s**; frag post-physics horizontal error **0.611%**, bugbait **0%**; gravity/spin continue natively |
| Physical melee | Slow target **100 -> 100**; crowbar **132.48 units/s / 26.743 club damage**, health **100 -> 74**; stunstick **135.23 / 27.569**, health **100 -> 73** |
| Camera | Nonzero punch witness **(1.3528,0.6348,0.2705)°**; actual pushed camera stays **(0,45,0)°**, equal to the tracked head |
| Hands/lifecycle | Native main-hand prop grab with Hands; death clears weapon/proxies/holds while VR runs; respawn gives Hands; **39 observed models / 0 live after Exit** |
| Gun pitch/settings | Left-hand model, actual **30°** pitch change; dominance and gun-angle strings restore **0 / 0**, live receipt true |

Simulation accepts **13,385 rendered/pose-matched frames**, **0 submissions**, **0 Submit
errors/unmatched poses/Lua errors**. Recorded Index geometry is **2468x2740 per eye**,
centre **3112x2752**, traced **1556x1376**, 1280x720 window, 40 units/metre, queue mode 2.
Reference throughput **74.647 rendered FPS**, GPU command work **15.010 ms**, elapsed
**15.034 ms**, render-thread CPU **3.951 ms**. These include image transfers/shared-host
work and are feature receipts, not a performance-tuning result or compositor measurement.

## Final Index acceptance

**index-all-02**, package **v4w.11** at **9e9b32e4**, is the selected Index run:
**42 phases**, **178 s active interval**, two Start/Exit cycles and **46 full capture
sets**. The production driver takes both shared locks. Re-evaluating its original game
console and capture receipts reproduces the stored renderer success, counters and steady
analysis exactly. Re-running `vr_weapons_analyse.py` also exits **0**, **success true /
no issues**. No further W defect or code change was required; `index-all-01` remains
excluded for its missing camera.

The Index accepts **7,885 rendered / submitted / pose-matched pairs**, **0 Submit
errors**, **0 unmatched poses**, **0 dropped frames** and **0 Lua errors**. The steady
window is **70.786–185.150 s**: **5,048 pairs / 114.364 s = 44.140 pairs/s** at
**90 Hz**, with **5,330 reprojected / 10,291 presents = 51.793%** reprojected.
GPU command work is **16.584 ms**, elapsed **21.952 ms**, render-thread CPU
**4.208 ms**, compositor app GPU **16.218 ms**. Geometry/window/scale/queue settings
match the simulation. Unlike the simulation these are actual OpenVR submissions and
compositor counters; the high reprojected share remains a performance limit.

| W acceptance | Selected Index measurement |
|---|---|
| Models/switch | All **16 classes** visually inspected; maximum measured wrist error **0.0000025 m**; switches **0–1 frame** |
| Native hitscan | **83 actual native pellet traces**, plus **10 labelled zero-spread diagnostics**; diagnostics hit both **5/20 m** target ranges with **0 reported lateral error**, gun/head difference **45°** |
| Native starts | **0 reported error** from the host muzzle; maximum rendered static muzzle difference **0.0000025 m**, at printed float precision |
| Foregrip | SMG controller/shown errors **0.00209° / 0.00204°**; shotgun **0.00206° / 0.00184°**; snap error **0 m**; both release to one-hand aim |
| Projectiles | All **six native classes** observed, redirect on **tick 1**; bolt/rocket/SMG grenade/AR2 orb initial direction error **0°** |
| Physical throws | Requested **80 units/s = 2 m/s**; frag post-physics horizontal error **0.441%**, bugbait **0%**; native gravity/spin retained |
| Physical melee | Slow target **100 -> 100**; crowbar **63.932 units/s / 6.180 club damage**, health **100 -> 94**; stunstick **77.458 / 10.237**, health **100 -> 90** |
| Camera | Nonzero punch witness **(11.7948,5.8887,2.9362)°**; pushed camera remains **(0,45,0)°**, equal to the tracked head |
| Hands/lifecycle | Main-hand prop grab with Hands; death/respawn checks pass; **39 observed models / 0 live after Exit**, server Hands removed and pre-VR pistol restored |
| Gun pitch/settings | Left-hand model and actual **30°** pitch change; dominance/gun-angle strings restore **0 / 0**; camera visibility override cleared |

The pellet count, measured melee speeds/damage, frag drag error and punch witness differ
from simulation; required behavior passes in both. Image review covers every model phase,
all ten firing phases and both effect captures, both foregrips, all three melee phases,
throws, Hands, death/respawn, wall and left dominance. The camera's original textured
model is plainly visible in **centre, left and right** captures, and the toolgun retains
both hands. Fists correctly has no world-model asset. Cropped review sheets are retained
under `index-all-02-qa/`; original images remain untouched. Eye-warp edge/disocclusion
artifacts remain visible and belong to the existing R/Q limit described below; this is
not a claim of true stereo or worn comfort.

The game quits normally with **exit 0**, settings **restored**, OpenVR unloaded after
Exit and no remaining session timers/receiver/global. Protected `user.conf` hashes agree
before/after. Restoration and rollback are **clean**: all **11** original path groups
match, watched data/settings have **0 changes/missing/additions**, registry differences
and rollback errors are empty, and depot verification accepts **2,877 files** with
**0 missing/size/hash mismatches**.

## Final Release gate

The first `tools\test.ps1 -Config Release` attempt **failed (exit 1)** only in
`test_poc_parity.PrepareRestoreTests.test_prepare_and_restore_round_trip`: its synthetic
copy preflight reported **12 GiB free**, below the required **20 GiB spare**. Native
**34/34** and W's **46 cases** passed. The failed log/result remain in
`out/vr/v4w/release-gate.log` and `out/vr/v4w/release-gate-result.json`.

No source/test change was needed. Lossless NTFS compression of W's selected Index and
simulation capture folders preserved paths and contents; **all 10 sampled PNG SHA-256
hashes agree**, and the production capture checks still pass. No evidence was deleted.
`out/vr/v4w/capture-compression.json` and the two compression logs retain that check.
Free space was rechecked above the fixture reserve before the full gate was rerun.

The final **`tools\test.ps1 -Config Release` passes (exit 0), 2026-11-11**:
repository conventions, **34/34 CTests**, and Python suites of **29 / 26 / 1,117 tests**
all pass, including W's **46 cases**. There are **9 skips** across those Python suites;
K/T's missing feature suites remain explicit pending-suite skips, not combined milestone
acceptance. The full successful log is `out/vr/v4w/release-gate-02.log`, with
command/exit/timestamps in `out/vr/v4w/release-gate-02-result.json` (paths from the
worktree root). No simulation or Index rerun was needed for this environment-only retry.

## Independent-review corrections

The review's **1, 2 and 5?12** are addressed on v4w. **82 offline tests pass**:
79 actual-module LuaJIT cases and three independent evidence/timeline cases. The first
22 review regressions failed before their fixes; native-only refinements have their own
failed receipts. All paths in this section are under **out/vr/v4w/review/**.

| Item | Kept test and result |
|---|---|
| **1** artificial-motion melee | `melee_walk/sprint/snap/teleport/tip_jump`: **100 -> 100**; before the fix, walk/sprint/snap caused **6.5 / 59 / 65** damage. Tracked linear/angular swings and the original cooldown test pass. Speed is tracked velocity plus angular velocity cross wrist-to-tip; proxy/physics/locomotion changes and unexplained displacement reset the sweep. |
| **2** secondary bullet starts | `bullet_followup`, `bullet_missing_geometry` pass. The stand-in SWEP's penetration source/direction/callback/tracer remain theirs. Native `bullet-passes` verifies initial, exit-point and missing-geometry passes, with a second hook returning true. Only unsafe initial VR shots are vetoed. |
| **5** Impact fields | `melee_impact_fields`, `impact_reaches_surface`, `model_decals_scope` pass. The precise contact trace extends beyond the hull centre; inward skin survives effect-coordinate quantisation. Start/entity/surface/hitbox bone/club type are supplied. Model decals are session-owned and restore only W's last value. Native image verification is recorded below. |
| **6** muzzle flash | `flash_explicit_origin` covers pistol/.357/SMG/AR2/shotgun/RPG. Engine MuzzleEffect uses explicit origin/angles/scale, with entity/attachment cleared and Lua override disabled. The native 5/20 m captures show the flame itself. Captures wait one Source frame after creation; the former immediate captures read the preceding scene. |
| **7** spin axis | `grenade_spin_frame` passes with compound hand rotation and a non-axis-aligned spin. Physics angles are set first; converting the resulting local angular velocity back to world recovers the requested axis. |
| **8** initial projectile state | `projectile_after_postthink`, `projectile_same_tick`, `grenade_native_initializer`, `grenade_initializing_exit`, `bugbait_without_vphysics`, `bugbait_first_visible` pass. Native launch callbacks follow PlayerPostThink. Ready classes relocate at tick **0**; the frag is held at the hand while its native initializer finishes, then its saved velocity/spin resume at the next pre-physics boundary. Bugbait has no VPhysics/ready launch callback: it is hidden until its first ready tick **1**, then relocated with EF_NOINTERP before first display. Its first visible native position is **0.03005 m** from the launch hand. This exception is explicit, not counted as tick 0. |
| **9** foregrip/pitch pauses | `foregrip_burst`, `pitch_keeps_firing` pass while acknowledgements are withheld. Native bursts retain **208 SMG / 209 shotgun commands, zero dropped attacks**, across grip transitions. Geometry/permission is a profile; the host decides engagement. The steady alignment capture follows the burst after recoil ends. |
| **10** Exit selection | `exit_keeps_active`, `exit_hands_previous/fallback`, `exit_unarmed_fallback` pass. An ordinary selection stays selected; from Hands prefer the previous class, then highest-weight owned weapon. The native fixture measures this before its own selection cleanup. |
| **11** hook order | `bullet_hooks_first/last`, `cached_engine_dispatch`, `bullet_dispatch_cancel/cleanup`, `bullet_hook_added_during_vr` pass. The engine retains its dispatcher, so replacing global hook.Call was insufficient. W instead owns the event table and dispatches the held callbacks once; the outer dispatcher calls its gamemode once. New hooks, cancellation, retained references and later writers survive. Native initial bullet traces now start at the muzzle. |
| **12** listen-server tracers | `server_tracer_broadcast`, `client_predicted_tracer` pass. Server effects have explicit starts and bypass the prediction filter; message 65 requests no duplicate host tracer. The local initial predicted tracer is suppressed; foreign players and follow-up starts remain untouched. Native effect receipts confirm the broadcast path. |

[Decision 0193](../decisions/0193-vr-weapons-after-independent-review.md) records these
choices. No portal callback/class or global hook.Call is rewritten. `scope-checks.json`
verifies C's gun-angle/foregrip and poseGrip blocks plus cl_weapons_model/sh_weapons stay
unchanged. No loader edit, native input/import, push, merge out or publication is included.

**Full affected simulation: sim-after-06, package v4w.17** passes production and W
acceptance: **22 phases / 98 active seconds / 28 capture sets / 7,449 rendered and
pose-matched frames**, **0 submissions, Submit errors, unmatched poses, Lua errors**.
Quit is normal; settings restore, OpenVR stays unloaded and rollback is clean. Native
hitscan includes **44 actual pellet traces plus 6 zero-spread diagnostics**. Foregrip
controller/shown errors are **0.00236 / 0.00247 degrees** (SMG) and **0.00068 / 0.00075**
(shotgun), zero snap displacement. Slow contact leaves health **100**; both fast weapons
report P's **133.333 units/s / 27 club damage** and damage the native crate. Alignment
compares native launch velocity with the firing ray at launch, rather than a later pose.
The first visible bugbait and early/finalized frag records are retained independently.

**Final Impact verification: sim-impact-01, package v4w.18** passes production and W
acceptance: **30 active seconds / 2 melee phases / 10 capture sets / 2,448 matched frames**,
zero Lua/render errors, normal quit and clean restoration/rollback. This last package
change is confined to Impact's precise surface contact; the full v4w.17 run above covers
the other corrected paths. `before-melee-fast` versus `decal-melee-fast` shows a new dark
mark on the crate's centre beam with the hand withdrawn; the effect captures show
contact particles and stunstick sparks. The full run's `effects-pistol-5/20` visibly show
the muzzle plume and explicit-start tracer. `final-qa/` keeps review sheets; originals
are unchanged. Both selected runs preserve protected hashes and verify **2,877 depot
files**, with no missing/size/hash mismatches.

The full run's native starts have **0 reported source error**; projectile launch-angle
errors are **0?0.0000013 degrees**. Frag post-physics horizontal error is **0.5245%**,
bugbait **0%**. Its tick-1 first visible position is **0.03005 m** from the launch hand;
the uninitialized eye-position interval is hidden. Grenade initialization/finalization
and first network/visible positions are separate receipts; no counter is relabelled.

Final local GMA: `out/dist/gmod-rtx-remix-0.0.0-v4w.18.gma`, **1,811 files /
2,085,729,694 bytes**, SHA-256
**8da5d93b5f6d2295836c88715d3dfffaf53ca59b05a3e487d80e0bc0cca80569**.
`package-final-audit.json` verifies all four shipped W Lua files against current source,
with no test fixture packaged. No Index rerun was performed, as requested.

**Final Release gate: `tools\test.ps1 -Config Release` passes, exit 0**, recorded in
`release-final-02.log` and `release-final-02-result.json`: **34/34 CTests**, Python suites
of **29 / 26 / 1,153 tests**, **9 skips** including K/T's explicit pending suites, and
W's **82 cases**. `offline-final-05.log` independently records 82/82. Repository/link
conventions and the staged diff are checked again after this report update.

Failed evidence remains: `offline-before.log`, `flash-before.log`, `impact-bone-before.log`,
`cached-engine-before.log`, `native-refinements-before.log`, `bugbait-visibility-before.log`,
`impact-surface-before.log` and `timeline-before.log`; `sim-before` records the old tick-1
launch. `sim-after-02` rejects a non-monotonic fixture timeline, now independently tested;
`sim-after-04` exposes cached engine dispatch; `sim-order-01/02` measure actual initialization
order; `sim-after-05` rejects recoil in a steady-geometry capture, bugbait's early visibility
and the too-distant crate fixture. Unstarted .12/.13 preflights were superseded without a
snapshot/install/game. `lock_poll_driver.py` is an uncommitted workflow helper: it caps
only the production lock's retry sleep at 0.1 s, retaining exclusive-create/owner/timeout/
release checks; synthetic contention and foreign-writer checks pass. Superseded W GMAs
are removed after newer builds are tested; their W Lua sources and run receipts remain.

## Second independent review ? 2026-11-12

This follow-up supersedes the affected claims in the preceding 05ac4ca5 correction.
Scope is W's two production modules, their sidecars, W tests/harness/fixture, this report
and ADR/index/link corrections. C's client gun-angle/foregrip and poseGrip regions,
cl_weapons_model.lua, sh_weapons.lua and loader/ are byte-unchanged against 05ac4ca5.
Evidence is under **out/vr/v4w/review-2/**. No push, merge, publication or workflow ran.

| Finding | Fix and retained test |
|---|---|
| **1 ? ULib ordering / fallback** | Both the stock live event root and ULib's live priority table plus compatibility table are owned. The original dispatcher retains the order and monitor semantics. An ordinary hook.Add callback remains for unknown libraries, with a private root-replacement capability probe. `hook_library_dispatch`, `priority_observers`, bullet/launch/tracer scenarios run under stock and an independent ULib-style implementation; unknown-copy fallback cases also pass. Cached engine references, cancellations, hook additions/removals and teardown remain covered. |
| **2 ? moving melee** | Body-origin displacement is subtracted from the tip residual and added to the sweep start. Walking/platform translation cannot erase a real tracked swing or become its damaging velocity. Proxy/epoch changes, half-metre body jumps and five-centimetre relative tip discontinuities reset. `swing_walking/sprinting/platform` give the same **32 damage** as a stationary **3.75 m/s** swing. `still_hand_walking` remains **100 -> 100**. `tracked_tip_jump` has nonzero tracked speed and unchanged proxy, explicitly exercising the residual rule; `body_teleport_same_proxy` retains teleport rejection. |
| **3 ? unavailable off hand** | The server rejects P's grip, climb and blocked states plus its public Holding result before engaging a foregrip. `foregrip_held`, `foregrip_climbing`, `foregrip_blocked`, `foregrip_holding_api` pass; the available-hand two-hand case remains positive. C's client claim region is untouched. |
| **4 ? gamemode return** | An owned gamemode method wrapper applies modified bullet tables after a nil return, without terminating other add-on hooks. A later false still cancels. `gamemode_nil_applies` and `gamemode_nil_client` pass under stock and ULib; the server nil case also runs with the unknown-library fallback. Gamemode invocation count and later-writer cleanup are checked. Base's shared.lua returns true; Sandbox's sandbox.txt derives from Base and it has no shared EntityFireBullets override (`gamemode-source.json`, primary Facepunch sources). |
| **5 ? global decal setting** | The r_drawmodeldecals override is removed entirely. `model_decals_untouched` and the retained old scope-test name verify zero writes at Start/Stop. No V4 Done point here requires enabling model decals globally. Its RTX cost/look have not been measured, so no proposal to enable it is made. The earlier decal captures belong to the withdrawn override and are historical. |

`offline-before.log/json` retain **25 failing runs out of 32 new initial regression runs**
against the pre-fix code. The final weapon suite passes **119 tests** (stock/ULib/fallback
and evidence cases); the V4 suite passes **33**. Logs: `offline-final.log`, `v4-final.log`.
ADR **0180** was K's reservation: W's record is now **0184** and every link/index entry
was corrected. The record retains its original history and adds a superseding addendum.

**Exactly one simulated session:** `sim-01`, package **v4w.19**, **30 active seconds /
5 phases / 11 capture sets / 2,079 matched rendered frames**, **0 submissions, Submit
errors, unmatched poses or Lua errors**. Phases: pistol-5, fore-smg, bolt-eye, melee-walk,
bullet-passes. Both shared locks were taken in production order by the temporary
`driver.py` wrapper; it only shortens the lock retry wait and keeps simulation/OpenVR off.
Native bullet starts/passes, tick-0 bolt launch, eye-obstacle separation and the foregrip
pass; the SMG burst retains **191 commands / zero dropped attacks**.

The walking fixture uses actual predicted/host movement commands: **200.000 u/s** maximum
body speed, **38.990 units** displacement, and a **133.333 u/s tracked swing / 27 club-damage
held contact** with a matching native Impact entity. The stationary wide Hunter plate is
indestructible, so health stays **100**. The initial analyser incorrectly required health
loss; `weapons-checks-original.json` preserves that rejection. The corrected criterion
requires positive held damage/contact plus a matching Impact entity, not health loss
from an indestructible prop; `test_unbreakable_native_contact` rejects missing/mismatched
impact and zero damage. Reanalysis passes without another game/session.

Quit is normal, settings restored, protected hashes unchanged and rollback clean;
**2,877 depot files** verify with no missing/size/hash mismatches. The native decal value
was **1 as inherited by the fixture**; W made no setting write and this is not a cost/look
measurement or a recommendation. No live ULib/ULX installation was added to the PoC:
ULib dispatch semantics are verified by the independent offline priority implementation.

Current GMA: `out/dist/gmod-rtx-remix-0.0.0-v4w.19.gma`, **1,811 files /
2,085,735,927 bytes**, SHA-256
**1e1814650ef7501498c5fffe9a5ba69e293120deaf8534aea83138c092e83d42**.
`package-audit.json` checks all four W Lua files against source; `scope.json` checks C and
loader exclusions. v4w.18 is preserved and was not overwritten. No Index run was made.

**Final Release gate passes, exit 0** (`release.log`, `release-result.json`): **34/34 CTests**,
Python suites **29 / 26 / 1,190 tests**, nine skips including K/T's explicit pending suites;
W's **119** cases are included. Repository/link and whitespace checks pass. C's controller/grip work,
K/T combined integration and Q's milestone acceptance remain separate.

## Verification review of c99003f5 ? 2026-11-12

This follow-up supersedes review-2's body compensation and W-only melee acceptance.
Evidence is under **out/vr/v4w/review-3/**. All six initial regression probes failed
before the corrections (`offline-before.log`). **127 weapon tests / 33 V4 tests pass**
(`offline-final.log`, `v4-final.log`), including stock/ULib/fallback coverage retained
from review-2. No Index run, loader edit, C-owned region/file edit or outward action.

| Finding | Correction and kept proof |
|---|---|
| **1 ? room follow counted twice** | Artificial motion is body-origin delta **minus L's applied_total delta**. Room movement remains in the tracked swing. `room_lunge` and `room_walk_swing` reproduce the failure, then pass with **62 damage**, retaining command walking/sprinting/platform and discontinuity cases. Room batching is explicit in the fixture. |
| **2 ? missed outside crossing / thin door** | The old guard compared a one-sample-late physical proxy to the new body origin; the error could exceed 5 cm exactly on the crossing tick. `walk_crossing_proxy_lag` reproduces that rejection. The residual now permits either synchronized body/proxy sampling frame without permitting unexplained jumps. The old translated sweep also skipped surfaces in the body-travel interval (`walk_thin_door`); the sweep now starts at the **previous world tip**, while damage speed stays tracked. Start-solid/zero-length contacts are rejected. Both outside-crossing tests pass; existing still-hand/snap/teleport/jump guards remain positive. |
| **3 ? independent engine witness** | The fixture records the spawned target EntIndex, phase serial/start and tick, and observes EntityTakeDamage on that target with the player/melee inflictor. Acceptance pairs engine damage with Impact on the **same target, phase id and tick**, inside the measurement window. Every pair must have **Start != Origin**. `test_melee_requires_engine_witness` rejects absent engine damage, wrong target, zero-length ray, mismatched tick/phase and out-of-window data. The unbreakable-target test now also needs that independent witness. W's lastHit/util.Effect alone cannot pass. |
| **4 ? copied dispatcher re-entry** | Both twins guard replay and recognize a copied/later event root. They prepare once and leave iteration to that caller, so its other callbacks run once rather than recursively replaying the copy. `dispatch_copied_table` and `dispatch_copied_client` pass; the pre-fix server probe failed on bounded recursion. |
| **5 ? ADR reservation** | W's record was then **0191**, now **0193** (main took 0191 and 0192 on 2026-11-12); 0184 belongs to Q and 0180 to K. Links/index were fixed, including this report's delta line. The historical accepted text is retained with superseding addenda. |

**Exactly one requested simulation:** `sim-01`, new package **v4w.20**, **30 active seconds /
4 phases / 2,016 rendered and pose-matched frames**, **0 submissions, Submit errors,
unmatched poses or Lua errors**. Pistol-5 includes two actual shots and one zero-spread
shot. Standing/walking/lunging each produce exactly **one engine damage witness and one
matching Impact**, with the correct spawned target and phase/tick. Every hit has
**Start != Origin**, with these world-unit ray lengths:

| Case | Target / tick | Engine club damage | Start-to-Origin distance |
|---|---|---|---|
| Standing | **150 / 3580** | **26.999998** | **1.965120 units** |
| Command walking | **139 / 3845** | **26.999998** | **3.620056 units** |
| Room-scale lunge | **151 / 4112** | **47** | **1.937356 units** |

Command walking reaches **200.000 u/s** with **35.9865 units** actual body displacement.
The physical HMD/hand lunge exercises actual L room follow in walk mode on a temporary
static floor: applied_total changes from zero to **(9.4781,-12.5083,0) units**; tracked
swing speed is **200 u/s**. No body/hand translation fakes that room-follow counter.

**Overall production acceptance remains rejected**, solely for
`hud-changed: invalid wrist image: invalid wrist extent`. The generic HUD witness runs
after the final physical lunge, when the old timeline tail returned hands without the
head's physical offset. `test_lunge_tail_keeps_hands_in_front` reproduces this fixture
fault; a neutral post-phase hand settle now preserves that offset. It passes offline,
but **has not been retested live**: the one-session limit is respected. The original
summary/checks/captures remain rejected evidence; no renderer criterion is relaxed and
no second game or Index session ran. All task-specific bullet and strict melee witnesses
above pass. This capture acceptance is the explicit remaining open verification.

Quit is normal, settings restored, OpenVR stays unloaded, protected hashes agree, rollback
is clean, and **2,877 depot files** verify with no missing/size/hash mismatches. `scope.json`
verifies C/loader exclusions. Current GMA: `out/dist/gmod-rtx-remix-0.0.0-v4w.20.gma`,
**1,811 files / 2,085,737,228 bytes**, SHA-256
**9328448ceeac216a1c66a7a31310da6109c996c493318883a8c0b6a2d03ed694**.
`package-audit.json` verifies all four W production Lua files against current source.
The subsequent timeline-tail change is test-fixture-only and is not packaged.

**Final Release gate passes, exit 0** (`release.log`, `release-result.json`): **34/34
CTests**, Python **29 / 26 / 1,198 tests**, nine skips including K/T's explicit pending
suites, and W's **127** cases. Repository/link and whitespace checks pass. C/K/Q
integration remains separate, and a coordinator-authorized future combined run must
verify the HUD tail. No extra session was started to clear that failure.

## Whole-acceptance retry requested before merge ? 2026-11-12

Exactly **one additional simulation** was run: **review-3/sim-02**, using the existing
**v4w.20** GMA because the neutral-tail fix changed only the test fixture. The four
production Lua hashes still match `review-3/package-audit.json`. Fresh evidence directory,
both shared locks taken by the same production-lock wrapper; no shared tool/source change,
package build, Index session, merge, push, publication or workflow.

**Verdict: FAIL ? whole acceptance remains rejected.** The sole production problem is
`hud-changed: invalid wrist image: invalid wrist extent`. The exact rejecting predicate
is `overlay_bright_pixels` in **tools/vr_session.py:331?332**: PNG area must be at most
**1,048,576 pixels**. The captured
`review-3/sim-02/captures/hud-changed/overlay_4.png` is **1031 x 1033 = 1,065,023 pixels**.
The other overlay PNGs are 769x257, 269x271 and 265x267 and fit the guard. This is a shared
capture/validation extent issue, not evidence that a physical wrist is outside the view.
The earlier pose-tail diagnosis was not sufficient and is superseded by this measurement.
**Stopped without changing shared tools or running another session**, as requested.

The run has **30 active seconds / 16 capture sets / 2,039 matched rendered frames**,
**0 submissions, Submit errors, unmatched poses or Lua errors**. The probe's own done
record is true and live-selector checks complete. W's stricter melee and bullet checks
have no separate failure; `weapons-checks.json` is false solely because production
acceptance is false. Every target has exactly one engine damage witness and matching
Impact, bound to its spawned EntIndex, phase serial, tick and time window:

| Case | Target / tick | Engine club damage | Start-to-Origin distance |
|---|---|---|---|
| Standing | **150 / 3652** | **26.999998** | **3.215144 units** |
| Command walking | **139 / 3918** | **26.999998** | **2.228374 units** |
| Room-scale lunge | **151 / 4184** | **47** | **2.786284 units** |

Thus **Start != Origin for every hit** and all three are engine-confirmed on their
recorded targets. Quit is normal, settings restored, OpenVR unloaded, protected hashes
unchanged and restoration/rollback clean. **2,877 depot files** verify with no missing,
size or hash mismatches. Driver log: `out/vr/v4w/review-3/sim-02-driver.log`.

**Open before whole acceptance:** C/Q or the shared capture/validator owner must reconcile
the valid captured overlay dimensions with the shared extent contract. No fix is proposed
or applied here. The failed images, summary, W checks and restoration receipts remain
unchanged for that review. The last Release gate remains the passing gate recorded above;
this retry/report commit changes no production code.

## Pictures and raw receipts

Each `sim-all-04/captures/weapon-<phase>/` has centre/depth, both eyes, mirror, HUD/other
overlay PNGs and timings. The Index uses the same phase names. Model phase paths:

| Classes | Phase folder suffixes after `weapon-` |
|---|---|
| Crowbar, stunstick | `weapon_crowbar`, `weapon_stunstick` |
| Pistol, .357, SMG1, AR2, shotgun | `weapon_pistol`, `weapon_357`, `weapon_smg1`, `weapon_ar2`, `weapon_shotgun` |
| Crossbow, RPG, frag, bugbait | `weapon_crossbow`, `weapon_rpg`, `weapon_frag`, `weapon_bugbait` |
| Physgun, toolgun, camera | `weapon_physgun`, `gmod_tool`, `gmod_camera` |
| Lua medkit, fists | `weapon_medkit`, `weapon_fists` (bare H hands, no world-model asset) |

Other phases: `pistol-5`, `357-5`, `smg1-5`, `ar2-5`, `shotgun-5` and the same at `-20`;
`bolt`, `rocket`, `smg-grenade`, `ar2-orb`, `fore-smg`, `fore-shotgun`, `wall`,
`melee-slow`, `melee-fast`, `melee-stun`, `frag-throw`, `bugbait-throw`, `hands`, `death`,
`respawn`, `left`. Explicit `effects-pistol-5`/`effects-pistol-20` captures retain firing
effects. `weapons.json` keeps the actual poses, bone/attachment values, native traces and
velocity samples; `weapons-checks.json` independently computes the measurements. The
standard `summary.json`, `sources.json`, game console, timings/profiles, protected hashes,
`restoration.json` and `snapshot/rollback.json` remain beside them.

## Development findings and excluded runs

- `sim-models-01` (v4w.1) rendered all classes cleanly, but its inspection head was 45°
  away and the gun was outside the inspection image. It also exposed centimetre-scale
  net.WriteVector quantisation when sending metre offsets. Explicit floats and a neutral
  inspection head fix both. `models-01-qa.png` preserves the rejected inspection.
- `sim-features-01` (v4w.2) proved native shots/foregrip/grab/death/throws, but visual
  inspection found a sideways pistol. c_arms and third-person wrist rotations differ;
  use authored upright axes about the measured wrist position. The crossbow's muzzle
  attachment points up rather than along its rail. `pistol-grip-qa.png` is the rejected crop.
- `sim-models-02` (v4w.3) shows upright models. Its toolgun frame loses both hands while
  the hidden view-model screen paints; the instance-scoped RenderScreen hold restores
  them (`sim-all-01/captures/weapon-gmod_tool/centre.png`). Its early cleanup fixture did
  not yet count models; it is not the final lifecycle certificate.
- `sim-all-01` (v4w.4) rendered **12,041 matched frames**, zero Lua/render errors, but W
  acceptance rejects missing host geometry/eye fallthrough, the relocating projectile
  blocking its own safety trace, and the frag boost. The SMG grenade fixture selected RPG,
  and the stunstick fixture used slow motion; those fixture errors are explicit, fixed
  and retained. Geometry acknowledgements/expiry guards and entity exclusion fix the real paths.
- `sim-critical-01` (v4w.5) passes the other critical weapon cases but rejects the frag:
  a requested **80** becomes **2211 units/s** after physics. Physical no-collide is
  insufficient: P's swept-hand Hit applies its force separately after a damage veto.
  Shared release grace and owned target cooldowns fix that path. No P code/formula was copied.
- `sim-frag-01` (v4w.7, canonical imported runtime) accepts **1107 matched rendered
  frames** and the real post-physics frag velocity, **0.611% error**, with `releaseGrace=true`.
  `sim-frag-00-arguments.log` is only the rejected below-minimum duration preflight, no game.
- `sim-all-02` (v4w.8) passes every feature except its switch clock: it counted the
  replicated respawn weapon while the client still reported dead, producing **2 frames**.
  The final receipt starts when alive with a valid shown hand, retains the one-frame
  bound for actual switches and explicitly records readiness; the original rejection remains.
- `sim-all-03` (v4w.9) passes all numerical checks: **13,312** matched rendered frames,
  switch maximum one frame. `index-all-01` likewise accepts **7884** matched submitted
  pairs, no errors/unmatched/dropped/Lua errors, at **44.331 pairs/s**, **51.530%**
  reprojected. Visual review still excludes its missing camera; draw counts alone were
  insufficient. Its camera-model read-only query is retained in the console and
  `inspect_camera.py`; the query creates/removes one hidden model, changes no settings.
- `sim-camera-01/02` diagnose valid camera bones/materials and a visible debug-white
  direct mesh. `sim-camera-03` rejects a same-texture mesh fallback, and
  `sim-camera-04` rejects fresh same-texture material variants. No such workaround ships.
  `sim-camera-05/06` identify the inherited ignore hash: the live getter exposes only
  the user-layer delta, so subtracting a matching visible token is insufficient. The
  declared negative-hash trial makes every original-textured model visible and restores
  the delta. These diagnostic runs contain extra probe models/materials, never final art.
- The first v4w.10 build ran out of disk space (`package-10-disk-full.log`), before
  producing a GMA. Verified W-only bulk-copy cleanup reclaimed space, then the build
  completed. No lock, foreign evidence or user data was removed.
- `sim-all-04` (v4w.11) is the full selected simulation with the original textured camera
  visible, its scoped override cleared and every native feature check passing.

Source behavior was checked against primary documentation, not copied code. Valve's
[fx_tracer.cpp GetTracerOrigin](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/fx_tracer.cpp#L21)
substitutes a carried local weapon's view model for an attachment tracer. Explicit Start
with no entity/attachment avoids that path, including the separate local-player offset.
[C_BaseCombatWeapon::GetShootPosition](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/c_basecombatweapon.cpp#L318)
also selects the local view-model muzzle. The native PostEntityFireBullets receipt exposes
actual `Trace.StartPos/HitPos`, not the original Bullet.Src/Dir fields. Physics velocity
is measured after simulation, not inferred from the setter. P's independent impulse is
in `sv_interact_actions.lua` after TakeDamageInfo; its released exclusions/throw weighting
are in `sv_interact_physics.lua` and `sv_interact_math.lua`.

## Reproduction, package and integration

```powershell
python -B -m unittest discover -s companion/tests -p vr_weapons_test.py -v
python tools/build_package.py --version 0.0.0-v4w.review --require-nlctl --json
py -3 -B companion/tests/vr_weapons_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v4w.review.gma --evidence out/vr/v4w/next-sim --seconds 178 --camera 0,0,512,0,0,0 --simulate
py -3 -B companion/tests/vr_weapons_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v4w.review.gma --evidence out/vr/v4w/next-index --seconds 178 --camera 0,0,512,0,0,0
python companion/tests/vr_weapons_analyse.py out/vr/v4w/next-index
tools/test.ps1 -Config Release
```

Use a new evidence directory each time. Offline/gate work uses normal Miniconda Python;
the game driver uses installed Python 3.12 with Pillow (`py -3`). No package was installed.
Initial acceptance GMA: `out/dist/gmod-rtx-remix-0.0.0-v4w.11.gma`, **1811 files /
2085718380 bytes**, SHA-256 **b67aae48c69c39e4ef3b8024b3ccf172e3b6fd48dd1d2ccc710480e69701131c**.
`package-audit.json` reads the archive and verifies all four W Lua files byte-for-byte,
with no test fixture packaged. Its canonical imported runtime is **418403840 bytes /
027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278**, and VR module
**510464 / 221c07fb268bc53bcd6281c668605c26695c9d75e0b5d42f31696a50faf576bd**.
Earlier v4w.1–5 used the documented local 541d3caf runtime overlay; v4w.6 onward use
the repository's normal package inputs, without a runtime override/import by W.

Open integration: Claude's W review/merge, K/T's combined reload/tools runs and Q's full
milestone acceptance/user approval remain. W implements no reload/ammo overlay/wheel/
physgun manipulation itself. Complex SWEP custom rendering that needs real weapon internals
uses the plain-model fallback; worn grip/comfort/actuator feel are not established by an
unworn scripted Index. R's reported absolute left-eye ghost threshold remains R/Q's
explicit limit; W does not claim true stereo or performance tuning.

Text for Q's shared documents:

- CHANGELOG: VR gains lit hand-held world weapons, converged initial muzzle shots with
  secondary bullet starts preserved, two-hand foregrips without firing pauses, tracked
  crowbar/stunstick attacks and history-based throws; projectiles relocate before physics.
  Hands frees the main hand; Exit preserves another selected weapon or restores from Hands.
- COMPONENTS: cl_weapons owns the stable API/claims/aim/effects; cl_weapons_model measures
  and draws world models; sh_weapons has profiles/pure maths/hands definition; sv_weapons
  owns validated geometry, host shots/projectiles/lifecycle and P damage/throw integration.
- ROADMAP: W is implemented/verified on v4w for V4 integration; K/T/Q and milestone
  review/approval remain separate.
- TESTING: W's exact 82-case bridge, initial simulated/Index native timelines and independent
  receipt analysis; include empty SWEP draw, token retry, own-projectile trace exclusion,
  swept-hand grenade forces, live pitch/dominance restoration and valid-alive switch timing;
  tracked velocity/angular melee, secondary starts, both short-circuit hook orders, spin
  frames, creation-tick/no-interp projectiles, foregrip bursts and conditional Exit selection.
- RESEARCH: record wrist rotational-basis differences, crossbow rail/attachment distinction,
  explicit-float geometry/directions, native tracer attachment substitution, P's independent
  force after a damage veto, the inherited camera ignore hash/scoped negative delta,
  and the measured native results above. Keep spread and
  zero-spread diagnostics distinct, and simulation counters separate from compositor submissions.
