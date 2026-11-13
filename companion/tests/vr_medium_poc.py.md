# vr_medium_poc.py

Limited simulated real-Source ladder/water proof, not the blocked full combined sequence.
Run `python -B companion/tests/vr_medium_poc.py --package <candidate.gma> --evidence
out/vr/medium-fresh`. Both shared locks are mandatory even though OpenVR is not initialized.
The driver snapshots/prepares/restores only the PoC; its reviewed crash classification
and single fresh-folder retry apply unchanged. Only the authorized normal field-quit
helper may end a field game, and only when one is present. SteamVR stays running/unchanged.

Fifteen bounded cases cover Hands/pistol+45/pistol-45 on a permanent gm_construct world
ladder (up/down/idle) and pool (head-directed up/down). Head yaw moves through a5degree
script; off-hand yaw deliberately disagrees. Source performs mounting, climbing and
swimming. No ladder move type, water level, velocity result or world target is faked.
Setup resets use WALK/position/zero velocity between trials, not during observation.
World brushes803/330 cannot break or be removed by the fixture. Ordinary weapon-switch
and Exit cleanup remain unchanged. Case preparation briefly resets to a dry position;
underwater windows are short, so no anti-drowning or lighting cvar is needed.

The observer requires actual move type9/real water, ten samples, no ladder side button,
less than.1unit lateral drift, intended vertical travel, actual drawn gun pitch within
1degree, head-directed water wish within.2degree and physical planar motion within3degrees.
Armed/unarmed desired speeds agree within.25unit/s; observed mean velocities within2units/s
(finite66Hz sampling allowance). It records head-sync disagreement, physical displacements,
commands and raw receipts; missing/wrong witnesses fail closed. `medium-checks.json` is
the reducer, with source/target policy and ordinary driver captures alongside it. No old
package timing figure is transferred. Exit0 requires driver AND all semantic checks;
otherwise nonzero, all failed evidence retained.

The target-policy receipt records the unmodified map BSP SHA-256.

Direct CLI startup bootstraps tools imports. Preference staging creates its client autorun directory; both have subprocess/filesystem regressions. Failed pre-game attempts remain separate evidence, with verified rollback where preparation occurred.


--depot-manifest is repeatable and forwarded to the shared driver for a pinned older vanilla copy. No Steam file is written. The ladder approach uses the accessible negative-Y side, facing+Y.


Ladders follow the head pitch/yaw Source rule, not the gun. Gun-pitch comparisons use angle equivalence modulo360, with unchanged1degree tolerance. Water transient settling is.8seconds; all other observer bounds remain unchanged.


The unchanged1degree gun bound applies to the measured rendered barrel; eye command angle is a separate convergence diagnostic. A regression deliberately separates the two.


Final pose error is measured on the actual rendered pistol barrel. Source eye-command convergence is not a gun-pose oracle. The1degree bound is unchanged, with separate recorded eye angle.

Round5:33 cases retain the original15 and add6 five-degree ladder trials,6 underwater noclip idle/throttle trials and6 land noclip controls. Head and off-hand directions plus actual stick components are recorded. The same5mm hold,1degree barrel,3degree water-velocity, .2degree wish and .1unit lateral bounds are retained. No old261104 depot pins are passed; current PoC261112 verifies against field manifests. Both locks and normal driver-owned field quit remain mandatory.
