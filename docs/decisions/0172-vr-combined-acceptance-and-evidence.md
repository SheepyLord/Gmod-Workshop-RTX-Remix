# 0172: VR combined acceptance and its evidence

Accepted for the V2/V3 branch on 2026-11-11, task Q. Implements the acceptance direction in
[the shared plan](../handover/VR-V2V3-plan.md) without changing the user-approved design.

Use tools/vr_session.py for the snapshot, package deployment, locks, counters, screenshots,
normal quit and restoration. The combined fixture composes the existing task fixtures in one
173-second active session, with every production module loaded throughout: physical phases,
near hands, movement/comfort, then the actual menus. Remove only idle time from physical phases
so throw/flick/spin derivatives stay unchanged. Explicitly scale the short locomotion/UI test
clocks and their expected timed distances/angles. Native poses/actions, production input claims,
resolvers and movers remain the implementation under test. UI uses adaptive scripted controller
aim at actual widget geometry, as M's fixture does; it does not invoke the widget's action.

The separate full-duration 127-second allmotion session uses the same complete candidate. It
measures the actual CalcView each rendered frame at 0.5 and 1.5 m/s and 2 Hz sway, plus steady
stick/sprint/flight. Compressed feature timing cannot substitute for these latency/judder data.
Simulation precedes Index acceptance. Neither simulation nor successful native rendering alone
can pass a failed physics/menu/movement requirement. The combined receipt names each result;
missing records fail. Whole near silhouettes still require saved eye/centre/depth inspection.

Every Capture request emits a handle-to-role manifest. Validate wrist glyphs as wrist glyphs,
black comfort canvases as comfort, and panels/window/keyboard/markers as their actual roles.
Never identify an overlay by dimensions, order or the first large PNG. Unknown/unlabelled roles
fail; a successful native request is insufficient without the copied images. Preserve failed
runs, raw logs, generated sources, exact package identities and restorations. JSON argument
transport avoids Windows command-line length limits without relaxing the console boundary.

All temporary files stay under out. The shared PoC and VR locks are respected. The field game's
normal-console-quit helper is authorised by the user when GPU/SteamVR tests need it; record each
invocation and outcome. No SteamVR process/settings, user.conf, depot file or loader source is
changed. No push, merge into vr2/main, workflow or publication is part of Q.

## Duration and coverage follow-up (Q, same integration)

The first prototype's console transport and 173-second active sequence were too long. The
current sequence uses 127 active seconds: 56 physical, 6 near hands, 34 locomotion/comfort,
then 31 menus, mirrored controls and a changed-calibration notice. Physical time halves; throw
displacement and rotation also halve to retain their actual 120 units/s / 1.1636 rad/s. Other
actual physical velocities remain measured, not presented as the old timeline's velocities.
The full-rate allmotion sequence remains unchanged. Exact H near poses replace the prototype
placements that could put forearms at the eye. Every earlier failure stays retained.

Stage the private plain-Lua fixture in a fresh directory inside the snapshotted PoC add-on tree
and invoke it with an acknowledged include, retaining both generated/staged hashes. This
removes scores of per-fragment console waits without adding test code to the shipped package
or bypassing native path/trust rules. Normal rollback removes it. Actual launch-to-exit times
are reported separately from active intervals; neither is silently relabelled.
