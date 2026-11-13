# Weapon world models

Included only by cl_weapons. Measures an initialized model's right-hand bone and muzzle
attachment in its own frame, with authored fallback lengths and foregrip points. `Pose`
inverts that wrist position at the shown hand using the session scale. The built-in
profiles use their authored upright axes; the wrist's rotation basis differs from H's
c_arms. Melee models use their longest bound toward the head. A left-handed player
receives the same unmirrored model. `Draw` runs a
SWEP's draw on the relocated model receiver when possible, otherwise the plain world
model. A temporary method on only that owned model verifies the custom method actually
draws it; an owner-dependent method that returns without drawing also falls back. Restore
the exact raw method value and avoid double draws after errors. No global is patched.
Unsupported custom draw code falls
back once. A muzzle's forward axis is used when it agrees with the profile's barrel;
the crossbow uses its rail axis because its attachment points upwards. Unknown SWEPs
retain their bone-merged grip roll with a muzzle-forward correction. W aims from the
untouched target angle, preventing feedback/compounding. No hooks,
files, settings or process exit codes; errors are handled by W's owner.

Prepare/Restore hold the active toolgun instance's hidden-view-model RenderScreen
callback while T supplies its overlay. Save the raw instance value (including nil) and
restore only W's replacement, preserving a newer writer. No class table/global is patched.

The inherited classic layer ignores the stock camera's measured texture hash
0x35D7392325ED05A9. While that exact camera model is held, add only its negative hash
to the runtime's user-layer delta, then restore the prior string on switch/Stop. A
newer writer's other changes survive; remove only W's added token. Pre-existing negative
tokens remain theirs. Never call SaveConfig or write user.conf. The normal client model
and original material render; the diagnostic mesh/material experiments do not ship.


## V4 controller frames

C adds an optional anatomical hand frame to Measure. The world model wrist is offset to its palm centre and its hand orientation is supplied for H; the gun barrel stays on the aim and upright. K/T model-local attachments follow the resulting model transform unchanged.

The left grip uses the paired anatomical hand frames to orient the left palm on the opposite side of the same upright weapon. Only hand rotation/anchor change; no negative model scale. Measurement resets model scale and bone cache to authored units before reading, so calibration does not compound a previously rendered scale.

Closed-finger grip geometry anchors the same right-authored model grip in either hand. Left-handed placement changes the gun position to the opposite side of the palm, with no mesh reflection; a wrist-bone match alone is insufficient. Crowbar/stunstick hands use the anatomical pointing/up basis. Muzzle and foregrip offsets are measured from the resulting placement.

Review follow-up: every model aligns barrel from its muzzle forward and up from authored +Z. Unknown classes no longer inherit the -90 wrist roll. No-attachment fallback uses known model geometry or bounded +X; generic foregrips project bounds along the barrel. Regressions compare a profiled and unprofiled identical SMG, no muzzle, and a +Y barrel.

## Review correction (2026-11-12)

Every authored/target anchor comes from the holding hand's own stable bounded grasp; the right hand is never an authoring reference for a left gun. Both profiled classes and known models reject a misleading attachment direction (crossbow); an unknown model without a muzzle infers a bounded signed long axis from bounds relative to its wrist. Barrel and model up remain level. Measure records cumulative calls/CPU time; changing the empty hand does not invalidate geometry.

Known-model attachment forward must agree with the authored barrel within 0.5 degrees. The actual w_shotgun muzzle tilts about 8.6 degrees from its barrel, so its position is retained while the authored direction keeps both profiled and unknown classes level. The observed tilt remains in the failed-before regression.

## Placement review (2026-11-12)

The anatomical hand remains thumb-up in calibrated and uncalibrated paths; it never mirrors a weapon wrist. The holding wrist-to-weapon basis conversion applies to both hands. ModelGrip reads a named grip attachment, its own closed finger bones, or a separately measured mesh grip-region point. The source point is independent of the holding-hand target. Unknown muzzle forward is validated within 45 degrees of the signed longest bounding axis through the grip; the no-muzzle path uses that same bounded inference.

Q4 integration centralises armed-hand ownership and released-projectile grace in P; passive touch honours the claim mask. W no longer edits P cooldowns or vetoes proxy damage. Camera override users share a lease and restore on module failure/Exit, preserving other config writers.

Q4: the known physgun profile selects authored attachment 1 when no named muzzle exists, so its exported aim muzzle matches the emitter used by T. Arbitrary SWEP attachments are not guessed.

Independent review removes the unnecessary multi-camera lease. Restore uses compare-and-swap of the exact applied string; a subsequent config writer owns its whole new value, including any negative hash it retained. Screen cleanup always proceeds independently. The special emitter fallback comes only from known world-model data.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


On concurrent ignoreTextures edits, remove only the owned negative camera token. The unchanged-value path restores the exact saved string; pre-existing tokens and screen cleanup remain owned correctly.


Stock holds retain their authored holding-hand bone mount instead of a numeric grip table. Genuine native grip attachments/finger bones remain supported for custom models. barrelSource reports actual mesh/attachment/authored-axis selection.

Stock models again use posed-mesh measured handle data, not the test witness/authored wrist position. Generic models keep their documented fallbacks. Camera restore removes exactly one owned negative token if other writers edited the value.
