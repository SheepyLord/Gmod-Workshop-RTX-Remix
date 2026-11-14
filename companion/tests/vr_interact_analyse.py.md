# vr_interact_analyse.py

Q integration requires ledge and ladder rises to match the scripted 12-unit pull within 2 units;
a positive but multiplied displacement is a failure. Existing raw prototype receipts are retained.

Standard-library reducer for the actual server records of task P's scripted PoC fixture.
Usage: `python companion/tests/vr_interact_analyse.py out/vr/v3p/RUN`. Reads interaction.json,
`--phases 1,9` explicitly checks only the short Index acceptance; default requires all phases.
`--phases 13,6` checks the isolated held-impact and ledge witness; main and isolated records
are reported separately rather than silently accepting an omitted failing case.
writes interaction-checks.json beside it and prints metrics/checks. Exit 0 only if all V3
fixture checks pass; 1 on a failed check or malformed input. It does not modify the game.

Measures barrel displacement, grab/throw speed/spin, blocked hands, two-hand alignment,
including the first actual native release velocity/spin, not only the requested set values.
heavy lag, separate ragdoll bones, ledge/ladder grips, button/door/health/armour/ammo use,
melon/NPC damage, glove marking/pull/catch, death/Exit cleanup and haptic event classes.
Checks every selected phase's centre/depth, both eyes, mirror, timings and overlay image files.
The shared summary.json remains the authority for rendered/submitted frames, Lua errors,
settings, protected files and rollback. Simulated frames never count as compositor proof.


Heavy lag is still measured and must be positive and finite. The former lower bound of 3 units was an expectation of the old spring: reducing lag via the requested world-velocity correction must not fail the test for improving it. Historical failed receipts are retained without reclassification.


The original heavy-crate lag >3-unit criterion is restored. Any positive lag is no longer sufficient.

Heavy acceptance now requires both finite peak >3 units and >=1.0 continuous actual game second above3 while held, after nominal time3. It uses elapsed_seconds in compressed fixtures, time in standalone runs; a gap >.30 seconds breaks continuity. This rejects spikes, missing coverage and disjoint bursts. Duration is an acceptance check for selected phase4.

V8: `v8_checks` (selected with phases 14 to 17): the cube held through the turn and carry, its worst error (under 1.5
units) and angle (under 6 degrees), its turn (90 degrees within 8); the pair: both hands on one body, a pair frame, under
2 units of jump when both close, an 8-unit rise (within 2.5), a 25-degree roll (within 6), worst error under 2.5 units;
freezing: frozen and let go while the hand stays, under 0.5 units of drift, freed into the hand and carried over 6 units;
one bone frozen of a ragdoll; held props drawn at the hand in at least four client samples, within 2.5 units of the
physics while followed. Phase 16 needs haptic kinds 6 and 7, phase 17 kind 6. Phase 4's heavy-crate check is restated
for V8's hold ([ADR 0203](../../docs/decisions/0203-precise-vr-holds-follow-the-hand.md)): over 1 unit of lag for at
least 0.1 s (seven ticks), from the probe's per-tick `heavy` record when there is one, else from the samples (V3's
spring held it over 3 units for a second).

V8, when `v8-frame-generation` records exist (`fg_checks`): Auto's target doubles with Frame generation off
(`v8_fg_target_switch`), the setting and target come back (`v8_fg_restored`), and the page's status has a Frame
generation line (`v8_fg_page_line`).

V8: `v8_pair_roll_degrees` compares the plank at 4.75-5.15 s (held level) with 6.0-6.45 s (turned). The first windows
(4.9-5.25 s) sat inside the wrists' turn and read 3.9 of the plank's 24.9 degrees in the PoC's second run.
