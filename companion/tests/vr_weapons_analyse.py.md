# Native weapon acceptance measurements

C's calibrated support-hand frames use the measured handle/tube origin directly. Their foregrip check therefore compares that origin with the weapon foregrip instead of applying the older palm-to-circle offset twice. Uncalibrated models retain the original offset check.

`python companion/tests/vr_weapons_analyse.py out/vr/v4w/<run>` reads the original W
JSON, production summary, sources and capture files, writes weapons-checks.json, and
exits 0 for all applicable checks or 1 for a rejected run. No game/network writes.
Only the phases requested by the run are required; missing receipts fail explicitly.

Independently measures wrist/muzzle positions, barrel and two-hand angles, native bullet
StartPos/HitPos against 5/20 m target faces, zero-spread versus actual weapon shots,
projectile delay and actual launch/post-physics velocities, melee health, Hands grab,
death/respawn/left dominance, pushed camera under view punch, switch frames and Exit.
Positions use 40 game units/metre; velocities retain engine units/s. Raw weapon spread
is reported, not silently tightened. Visual grip/lighting/readability still require image
inspection; the production driver separately validates renderer/capture/rollback receipts.

C: grip_wrist() inverts a receipt's optional anatomical palm frame before comparing the world-model wrist. Older W receipts without that frame retain their wrist-centred comparison. Foregrip and aim checks continue using the shown palm; no original evidence is rewritten.

Calibrated receipts compare grasp centres for the main/support hand; legacy receipts keep wrist/palm checks. The physical target-palm line still tests aim convergence. Independent rotation maths is shared with C without circular imports.

Review acceptance requires ready-launch relocation in the creation tick with EF_NOINTERP;
the native non-VPhysics bugbait path permits its first ready tick only when the first
visible client snapshot is at the hand. Launch direction is compared to the recorded firing ray,
not to a later controller pose. Additional phases validate
eye/muzzle obstacle separation, all three native bullet passes, downstream hook execution,
uninterrupted foregrip attack commands and the corrected conditional Exit selection.
Old receipts retain their original analysis separately when checked against the stricter contract.
The second review's melee-walk also requires measured Source body speed/displacement and
actual held-weapon damage. No model-decal setting or look is an acceptance requirement.
The wide Hunter plate is indestructible: walking acceptance requires positive native
held damage plus an Impact on that same entity, measured speed and displacement, rather
than health loss. An independent test rejects missing/wrong-entity impact and zero damage;
the original health-based failed receipt is retained when reanalysed.

Third-review acceptance supersedes the earlier W-only held-contact criterion. Every
accepted melee hit must pair EntityTakeDamage and Impact on the recorded spawned target,
in the same phase id, tick and measurement window. Start and Origin must differ. It also
requires real command movement and real applied_total room-follow motion where requested.

Q4 keeps the 2-degree barrel bound but measures the actual rendered model against independently measured mesh-axis data. SMG attachment marker orientation is 2.916 degrees off its mesh axis in the retained combined witness; marker orientation is reported separately. Attachment position and all bullet/impact bounds remain unchanged. Known crossbow rail geometry is checked too.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
