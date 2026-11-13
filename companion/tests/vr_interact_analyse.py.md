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
