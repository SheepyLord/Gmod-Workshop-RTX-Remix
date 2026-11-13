# W's offline engine stand-ins

Run through vr_weapons_test.py. Uses S's independent Euler maths, weapon/player/model
fixtures and bit wire, and the actual module resource registry. W adds explicit model
configuration, physics velocity, traces, damage, effects and owned event/net fixtures.
Inputs: repository root and scenario. Outputs PASS or a failed assertion (nonzero).
No game, OpenVR, filesystem writes or native prediction/ballistics simulation. Tests
exercise the shipped W modules, P's unmodified Hit/Damage/Throw and the stable K/T API;
real model calibration, native projectile timing and actual rendering require PoC proof.

C exercises the optional measured hand frame through the actual W model, and verifies curl ownership release on Hands/foregrip release.

Review regressions reproduce unprofiled model roll, barrel extent along Y, bounded missing-muzzle placement, and squeezed main/off claims on pull-away, weapon switch and Hands, for both dominant mappings.

## Review correction (2026-11-12)

Retained review regressions: holding_grasp ignores opposite grip values 3.3/13.1/8035 and bounds its own anchor; generic_models covers crossbow/pistol/shotgun/AR2 with/without muzzle and an unknown negative-X model; trigger_release_latch covers both physical roles/dominant settings; tip_only_aim checks -30.3-degree raw pose with a valid level tip. Old cross-hand basis assertions are superseded by holding-hand ownership.

## Placement review (2026-11-12)

uncalibrated_thumb_up uses measured c_arms frames and three real weapon mount angles; left_grip_basis again asserts thumb up. independent_grip uses model-owned finger bones instead of the solver point. unknown_up_muzzle covers an unlisted upward attachment and no attachment. tip_only_aim now composes actual raw/tip frames through cl_frames before invoking W, matching production.

Review cases reproduce artificial-motion melee, tracked linear/angular swings, complete
Impact data, primary versus penetration/missing-geometry passes, grenade spin axes,
same-command projectile relocation/EF_NOINTERP, bursts across foregrip/pitch changes,
Exit selection, both short-circuit hook orders, server tracer broadcast and local predicted
tracer suppression. Dispatch cleanup/cancellation and pre-existing no-interp bits are guards.
Only this harness's bullet defaults use the player's shoot position; shared stubs stay unchanged.
Engine-cache, post-PostThink launch sounds, continued native grenade initialization,
initialization-time Exit, bugbait without VPhysics, hooks added during VR and the model
decal setting's last-writer restoration have explicit regression/cleanup coverage.
The Impact ray's endpoint is independently tested beyond the hull centre at the actual
surface; first-visible bugbait and visibility cleanup have their own scenario.

The optional third argument selects stock (default), ulib (independent priority registry
and plain compatibility table) or unknown (detached GetTable copy) hook implementations.
These are original stand-ins, not vendored ULib code. Review-2 regressions cover hook
ordering/veto/tracers/launches under both known libraries, ordinary fallback, nil-returning
gamemodes, player-relative walking/sprinting/platform swings, a nonzero-speed tip jump,
off-hand holds/climbing/blocks and absence of model-decal writes.

Third-review cases include room-follow physical walking/lunging, first crossing with a
one-sample-late proxy, a thin door in the body-translation interval, and copied hook
registries in both realms. The physical swing examples include nonzero displacement;
stationary tracking velocity alone cannot stand in for a genuine outside sweep.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.

Q4 adds independent posed-mesh grip references for ten stock models and all-class captures in both hands. Stock weapon_fists has an empty WorldModel: its avatar hands are checked, and no nonexistent weapon mesh is required. Other modeled weapons retain strict independent grip limits. Private fixture Lua now stages as plain files in the journaled test add-on and installs the shared ULib API into the existing engine hook table.

Review cases check actual one-camera/two-config-writer cleanup, independent screen cleanup, world-model emitter policy, no fake grenade grab, feedback request and death/dead-tick ownership release in both hands.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


camera_two_writers requires owned-token removal after append/replacement and exact preservation of an originally foreign token.


Regenerated fixtures have no non-shaft grip boxes or frame.grip targets. q4_stock_grips compares authored holding bones with actual hand bones; AXIS diagnostics record the selected source/vector per class/hand.

Round5 measures independent full-mesh handle centreline/finger residuals below5mm, signed bone-relative handle envelopes, rendered barrel/up orientation, and reports nonzero rig-landmark residuals. Beam label names the add-on draw and independent model core. Duplicate camera token test retains one foreign copy.

The orientation case calls the same independent native observer and fails when a gun has no barrel witness.
