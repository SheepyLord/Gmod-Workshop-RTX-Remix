# VR V8: report

The user, 2026-11-13: "Fix the V4 neutral-yaw fixture now. Also, improve the grabbing interaction with physical objects
like ragdolls, make the grabbing more hands-on and precise. Allow rotate using 1 hand and use two hands to grab at the
same time. Add a key when grabbing to freeze that object. Also, allow enabling frame generation in VR if possible. If
the desktop still renders at full resolution (VR headshot usually is not 4K), adjust it to match VR to save compute. Do
not launch game to test, write code and validate them first then ask me for permission for in-game test."

Claude wrote all of it on the branch `vr8` (worktree `out/worktrees/vr8`, from `main` `a897abe9`), validated it
offline first, then ran the three in-game runs the user allowed ("Run all three", 2026-11-13; results below). The
user approved the merge to `main` on 2026-11-13 ("Merge and publish").

## 1. The V4 neutral-yaw fixture

**Cause.** V4's shared test adapter (`companion/tests/vr_v4_fixture.py`) turned the VR room to yaw 0 as soon as VR ran,
a step copied from the combined probe, whose drivers all request yaw 0. The weapons and reload drivers request 180, so
their neutral view faced the head's own yaw instead: 0, or 45 in the gun phases. That is exactly what V4's final run
reported. A second, intermittent cause showed in V6's `quality-sim-03`, which does not use the adapter: the move module
turns the room with physical mouse X, and 22 counts of desktop mouse input had moved the view 0.484 degrees, against
the 0.5-degree check.

**Fix.** The adapter no longer turns the room. The shared probe (`tools/vr_session.lua`) now, once per VR start in
scripted sessions, clears physical mouse X/Y in a mover that runs before the move module, and turns the room so the
camera faces the requested yaw. Live-pose and manual look sessions are untouched.

**Tests.** The adapter's real generated block, run under LuaJIT for the weapons, reload and tools roles, must not turn
the room and must clear movement, buttons and mouse; this test fails against V4's adapter. The probe's hold is checked
against a 0.484-degree mouse offset, a head turned 45 degrees, a restart, a core without a yaw yet, and look and
live-pose sessions. In the game every section's neutral view faced 180 degrees (run 1 below).

## 2. Grabbing: precise, hands-on, one-hand turning, two hands ([ADR 0203](../decisions/0203-precise-vr-holds-follow-the-hand.md))

**What was wrong.** V3's hold pushed the body toward a pose taken from the hand's physics proxy, which itself lags the
controller by about 45 ms. The push was a force spring that softened with mass (10 kg settled in about 40 ms, 100 kg in
230 ms). Rotation was a weak nudge from Euler-angle differences (time constant 0.3 to 1 s), so turning the wrist barely
turned the object. Neither the hand's velocity nor its spin was fed forward, and the client drew the body where the
server last had it.

**What it does now.**

- A grab keeps the body's pose in the hand's frame. If the touched point was farther than 3.5 cm from the palm, it is
  brought to rest against the palm, so the object meets the hand instead of floating up to 16 cm away.
- The hold follows the tracked palm itself, stopped at world brushes as the drawn hand is, with the hand's own velocity
  and spin fed forward. A new shared maths file (`sh_grab_math.lua`) holds the velocity controller: quaternion rotation
  error, errors closed in two ticks without overshoot, and the hand's strength (900 N, 150 N m) limiting heavy bodies.
  Light and medium objects follow tightly and turn with the wrist; a 250 kg crate still lags, as V3's tests require.
  Correcting an error is capped (3 m/s, 10 rad/s; gentler for ragdoll bones), so a body pressed on a wall or a bone
  held by its joints is not slammed.
- **Two hands on one object** hold it on the line between them, rolled by the mean of both wrists. The relation is
  captured where the object is when the second hand closes, and re-captured for the remaining hand when one lets go, so
  neither moves it. Two hands on different ragdoll bones drive those bones separately.
- **Drawn at the hand**: the client draws a held one-body prop at the hold's pose from this frame's hands, instead of
  where the server's physics last had it, and blends back over 0.12 s when the prop is held back or released.
  Ragdolls are drawn by their physics.

**Offline evidence** (LuaJIT, rigid bodies, one physics step a tick):

| Check | Result |
|---|---|
| 5 kg hold, hand moving 1 m/s and turning 3 rad/s | within 0.004 units and 0.02 degrees of the hold |
| Swing at 1 m/s (1 Hz), up to 30 kg | within 0.057 units (1.4 mm) |
| Wrist turning 6 rad/s, up to 30 kg | within 0.65 degrees |
| Overshoot, 0.2 to 250 kg, 20-unit step | none |
| 250 kg: error after 0.6 s of a 20-unit step / moving lag | 3.58 units (needs over 3) / peak 6.8, over 3 for 0.44 s (needs at least 0.36) |
| Second hand closes, still hands | body moves under 0.05 units and 0.2 degrees |
| One hand lets go | body moves under 0.1 units and 0.5 degrees |
| Both wrists roll 30 degrees / left hand rises 8 units | body rolls 30 degrees / tilts with the hand line |

All 78 harness cases pass: the 64 earlier ones (four updated for velocity control, the palm snap and the message's new
fields) and fourteen new. Eight mutants, each reverting one safeguard, fail their cases.

## 3. A freeze key ([ADR 0204](../decisions/0204-the-holding-hands-trigger-freezes.md))

**The trigger of the hand that holds something freezes it in place**, as the physgun does: a ragdoll's held bone (pose
ragdolls bone by bone), or a whole prop. Both hands let go of it, and it joins the physgun's "unfreeze all" list.
**Gripping a frozen object and pulling the trigger frees it into the hand.** A grip alone never takes a frozen object,
so brushing a frozen build does not loosen it. Unfreezable entities and prop protection (`CPPICanPhysgun`,
`CanPlayerUnfreeze`) are respected. The trigger was chosen because a holding hand's trigger does nothing else: a gun
hand never holds objects, and its trigger stays the gun's. Haptics give each a 50 ms pulse. Tested offline: freeze,
the latch against grabbing something else, unfreeze, the permission veto, unfreezable bodies, both hands, ragdoll bones.

## 4. Frame generation in VR ([ADR 0205](../decisions/0205-frame-generation-in-vr-is-motion-smoothing.md))

**Remix's DLSS frame generation cannot feed the headset.** In this runtime it is a presenter of the desktop window's
swapchain: it makes extra frames for that window only, while the eyes go to SteamVR through OpenVR. Making it serve the
eyes would mean interpolating the centre view and submitting twice per rendered frame, adding at least a frame of
latency, and NVIDIA does not support DLSS-G in VR. So it stays off in VR, and the page now says why.

**Frame generation in the headset is SteamVR's Motion Smoothing**, which V6's Auto was already built for. V8 makes it a
switch and shows its state:

- **Frame generation** on the VR page (`nl_vr_frame_generation`, on by default). On: VR renders half the headset's
  frames and Motion Smoothing makes the rest, as before. Off: VR renders every frame and Auto aims for the full refresh
  at a lower step.
- The page says whether Motion Smoothing is making frames now, whether it is off in SteamVR (with where to turn it on:
  SteamVR > Settings > Video > Motion Smoothing), or whether this GPU does not offer it. The VR module reads SteamVR's
  setting (`IsMotionSmoothingEnabled`/`Supported`, read-only: VR never changes SteamVR's settings), and the perf module
  watches the compositor's frame timing for frames Motion Smoothing made.

Module `gmcl_nlvr_win64.dll` rebuilt: 542,720 bytes, SHA-256
`aa1d8b651caa445e9a8acc97e8c3e68ff6b8307e83d59b6f8798d6cadff5dadf`, recorded clean against `48328f96`. Native tests:
43 cases pass, including fault 27, "Motion Smoothing off in SteamVR".

## 5. The desktop's resolution

**It does not render at full resolution, so nothing was changed.** Whenever VR runs, the path tracer renders at the
headset's size: the runtime takes the output size from the VR frame (`rtx_context.cpp:639`). The 4K desktop window
only gets a centred crop of the left eye blitted into it (`rtx_vr.cpp:943`), plus the game's own 2D. V2 measured the
whole difference between a 1280 x 720 and a 3840 x 2160 window at about 0.04 ms of GPU work a frame, and SteamVR's
estimate of the game's GPU time was no higher at 4K. Resizing the user's window would save nothing measurable, and it
would change the game's UI and GUI Scaler layout.

## Gate and candidate package

- Release gate on `44f3fe1c` (`tools\test.ps1 -Config Release`): 35 of 35 CTest and 1,876 Python tests (one skip),
  with the other two suites' 29 and 26, "All checks passed". Two earlier runs each failed one test for outside reasons:
  a package input edited during the run, then a Windows "access denied" renaming a fresh `out\tmp` folder; both tests
  pass alone, and the clean run above changed nothing.
- After the in-game runs' check and fixture fixes (tests and documents only; no package input changed), the gate
  passed again on the working tree over `92a1716f`: 35 of 35 CTest, 1,881 Python tests (one skip), the other suites'
  29 and 26, "All checks passed" (`out/vr/v8/gate-5.log`).
- Candidate `out/dist/gmod-rtx-remix-0.0.0-v8.1.gma`: 2,086,457,544 bytes (1,834 files), SHA-256
  `6d9cf055fcc84c452d60871133c1940eb6e192dd02bb4fbb96b98f34731bc2be`, content digest `6b7df133...`, checked by the
  branch's `nlctl.exe`.

## In-game runs (the user's "Run all three", 2026-11-13)

All on the candidate `0.0.0-v8.1` (SHA-256 `6d9cf055...`) in the PoC, with both shared locks.

### Run 1: the weapons and reload sections, both hands (simulated headset)

Evidence: `out/vr/v8/fixture-sim-01` (all ten sections), `out/vr/v8/fixture-sim-02` (both hands' guns again after
the fixture fixes below), `out/vr/v8/compare-v7-01`, `compare-v7-02`, `compare-v8-01` and `compare-v8-02` (the same
sections on V7's package `0.0.0-v7.2`, to tell old faults from V8's).

- **The neutral-yaw fix works.** Every section's neutral view faced the requested 180 degrees (the neutral capture's
  camera at yaw -180; V4's final run had 0 and 45). Calibration and the physical reload sections passed on both hands,
  seven guns each. The driver retried two sessions once (left reload, right button) after NVIDIA's OpenGL driver
  crashed at start-up (`nvoglv64.dll+0xe622f8`, before any VR code; the known old-driver start-up crash).
- **The button and empty sections failed on their checks, not in the game.** V7's package fails the button check
  the same way; the empty check's fault depends on a session's length (V7's one-gun run passed).
  - B's delivery mixed two clocks. The server stamps its records with `SysTime` from the phase's start, the client
    with the fixture's own clock; in each session's first phase the server's ran 44-75 ms behind (V7 0.044 s, V8 0.063
    and 0.075 s), so B seemed to reach the server before its release. In fact the server took B at the release's tick
    + 1 for every gun on both hands. The check now reads the delivery tick on the client's clock.
  - Readiness stopped at a clock reading, and one frame runs several commands at one reading: those after B already
    carry the reload's own lock (the AR2's 1.56 s, the test SWEP's 1.43 s on the left hand). It now stops at the first
    record of B in the console's order.
  - The empty-gun hold check wanted over 3500 s left. Physical reload holds an unloaded RPG from the session's start
    (a rocket goes in by hand), so in a seven-gun session the RPG's phase found 3477 s. A hold now counts above 3000 s
    (sessions run under ten minutes).
  - Re-analysed, run 1's button and empty sections pass on both hands; every gun's B arrived in its release's frame.
- **The guns sections had two fixture faults, both in V7 too.** The rocket phase never put a rocket in by hand, so
  physical reload (on by default) kept the RPG from firing: the phase now runs with physical reload off. The left-hand
  melee-walk stepped right in both runs, which walked the left hand's crowbar away from its plate: the step now goes
  toward the gun hand's side. Rerun: the left hand passed every guns check, the right hand all but one (next).
- **The right hand's hands phase missed its can, a third fixture fault.** The fixture spawned the can with its centre
  3 units in front of the palm, inside the hand's 0.075 m rubber physics sphere, gravity off. A probe every 0.1 s
  (`out/vr/v8/hands-probe/v8-guns-r`) showed the sphere bounce it out at about 24 units/s: it was 31 units away when the
  grip closed 1.2 s later, beyond the 6.4-unit reach. V7's package does the same (`v7-guns-r`). The can's surface
  now sits 0.0875 m in front of the palm, outside the sphere and inside the reach, asleep until touched.
- **Final guns run** (`out/vr/v8/fixture-sim-03`, after the three fixture fixes): both hands pass every guns check, 29
  phases each. On both hands the rocket is redirected at its first launch boundary (0 ticks, 1.2e-5 degrees off the
  requested direction), the walked crowbar hits its plate at 133 units/s with an engine damage witness, and the right
  hand's can rests 6.4 units (its centre) from the palm until the grip takes it.

### Run 2: grabbing, simulated headset

`out/vr/v8/interact-sim-02` (V8's phases 14-17 and V3's 1, 3, 4, 5, with the Frame generation check) and
`out/vr/v8/interact-sim-03` (phase 15 again). The first try, `interact-sim-01`, found two fixture faults: the plank's
"roll" turned each controller about its own forward, an axis across the hand line, which rightly rolls nothing (both
hands now turn about the line), and the heavy crate lags only while the hand's motion starts and stops, shorter than
the 0.25 s samples (now timed every tick). In `interact-sim-02` everything passed but the roll, which read 3.9 degrees:
poses interpolate between steps, and the "level" reference sat inside the wrists' turn. Measured from the level pose,
the plank had rolled 24.9 degrees for the 25-degree turn; the timeline now holds it level first (`interact-sim-03`:
24.8 degrees).

### Run 3: the Index, real SteamVR, nobody wearing it

`out/vr/v8/interact-index-02`, both shared locks. **SteamVR was not running, so the run started it through Start VR
(`VR_Init`) at 20:53; it is left running and its settings were not touched.** Every check passes:

| Check | Index | Simulated (`interact-sim-02`/`-03`) |
|---|---|---|
| Wrist turns a 3 kg cube a quarter turn | body 90.0 degrees; hold within 0.58 units and 4.1 degrees | 90.0; 0.23 units, 2.2 degrees |
| Two hands on the plank: second grab / rise / roll | 0.0 units / 7.9 units / 25.7 degrees | 0.0 / 8.4 / 24.8 |
| Two hands: worst hold error | 0.19 units | 0.10 |
| Freeze: frozen body moves / freed and carried | 0.0 units / 8.7 units | 0.0 / 7.6 |
| A ragdoll bone frozen | one bone of the ragdoll | one bone |
| Drawn prop versus its physics | 0.10 units (39 samples) | 1.47 units (45) |
| Haptic kinds (touch, grab, release, freeze, unfreeze) | 1, 2, 3, 6, 7 | 1, 2, 3, 6, 7 |
| V3: throw speed / engine error | 120 units/s / 1.6 % | 122.6 / 1.6 % |
| V3: heavy crate over 1 unit | 4.29 units peak, 0.21 s | 1.85, 0.21 s |
| V3: plank alignment / ragdoll by two bones | 1.0 / bones 5 and 7 | 1.0 / bones 4 and 6 |

**Frame generation on the Index**: SteamVR reports Motion Smoothing supported, enabled and making frames (frame
timing flags 284, which include Motion Smoothing's 0x08); the page reads "Frame generation: SteamVR Motion Smoothing;
making frames now: Yes". With it on, Auto aims for 45 frames per second and got 45.1; switched off for 4 s, the target
became 90, and the setting and target came back after. In those 4 s the game still rendered 44.9 per second: the
ladder had not yet stepped down far enough for 90 at the Index's 2468 x 2740 per eye (the first, interrupted try showed
the page's "frames were missed" step down to High within seconds). Where Auto settles for 90 on this GPU was not
measured.

**The first Index try** (`interact-index-01`) was cut off about two minutes in, when this agent's earlier session
ended and took the game, and the SteamVR it had started, with it. The driver's own rollback restored the PoC afterwards
and verified it clean (2,878 depot files). In that try the server's samples stopped in phase 3 with no error printed,
while the client went on; the probe now reports errors and a lost VR state as records, and the clean rerun showed
neither, so the cause is not known.

## What is still untested

- Nobody has held anything with their own hands in V8: grab feel, the palm snap, two-hand holds and ragdolls under a
  person's motion, held objects pressed on walls, haptics on the controllers.
- Frame generation off for longer than 4 s: where Auto settles for 90 Hz on this GPU.
- The page text in six languages is agent-written and not yet human-reviewed.

**V3's heavy-crate check, restated.** V3's in-game check wanted the 250 kg crate over 3 units behind a 0.5 m/s hand
for a whole second; that described the old spring. V8's crate lags while the hand's motion starts and stops and then
follows (about 1.6 units there, 6.8 at 1 m/s, within the offline bounds V3 set), so the in-game check is now over 1
unit for at least 0.1 s, timed every tick. No acceleration limit can meet both of V3's checks.

## Files

- Add-on: `sh_grab_math.lua` and `cl_interact_predict.lua` (new); `sv_interact.lua`, `sv_interact_physics.lua`,
  `sv_interact_actions.lua`, `cl_interact.lua`, `cl_perf.lua`, `cl_core.lua`.
- Module: `session.h`, `session.cpp`, `module.cpp`, the fake compositor and the lifecycle test.
- Page: `nativeloader_vr.lua`; catalogs `companion/i18n/*.po` and `nativeloader.pot`.
- Fixtures: `tools/vr_session.lua`, `companion/tests/vr_v4_fixture.py`; after the runs `vr_weapons_poc.lua` (the
  hands-phase can, a hands-phase probe), `vr_weapons_poc_client.lua` (the rocket phase, the left-hand walk),
  `vr_interact_poc.py` (phase 15's timeline) and `vr_interact_poc.lua` (the probe's error and lost-state records).
- Checks: `vr_reload_analyse.py` (B's delivery on one clock, readiness in the console's order, `HOLD_FLOOR`),
  `vr_interact_analyse.py` (phase 15's windows), with tests in `vr_reload_test.py` and `vr_interact_tests.py`.
- Tests: the interaction harness and suite, perf harness, VR harness, framework cases, UI harness, the fixture and
  probe tests.
- Docs: ADRs 0203-0205, CHANGELOG, ROADMAP, RESEARCH, TESTING, this report.
