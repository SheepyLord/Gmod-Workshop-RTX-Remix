# VR weapons offline tests

`python -m unittest discover -s companion/tests -p vr_weapons_test.py -v` runs W's
LuaJIT scenarios. S's test_companion_vr_weapons bridge imports the same cases in the gate.
Inputs: W's real Lua and shared stand-ins, installed LuaJIT. No game or OpenVR.
Outputs unittest results (0 success, nonzero failures; explicit skip if LuaJIT is absent).
Covers kinds, rigid grip placement, model changes/handedness/pitch/stops/world draws,
claims, convergence, foregrip, host muzzle validation/walls, bullets/callbacks/projectiles,
hands lifecycle, P's melee/throw reuse, effects and camera isolation. Writes no game files.

C adds both-hand anatomical palm anchoring, level/upright aim, wrist alignment and curl-release regressions.

## Review correction (2026-11-12)

Retained review regressions: holding_grasp ignores opposite grip values 3.3/13.1/8035 and bounds its own anchor; generic_models covers crossbow/pistol/shotgun/AR2 with/without muzzle and an unknown negative-X model; trigger_release_latch covers both physical roles/dominant settings; tip_only_aim checks -30.3-degree raw pose with a valid level tip. Old cross-hand basis assertions are superseded by holding-hand ownership.

## Placement review (2026-11-12)

uncalibrated_thumb_up uses measured c_arms frames and three real weapon mount angles; left_grip_basis again asserts thumb up. independent_grip uses model-owned finger bones instead of the solver point. unknown_up_muzzle covers an unlisted upward attachment and no attachment. tip_only_aim now composes actual raw/tip frames through cl_frames before invoking W, matching production.

Includes the independent-review regressions listed in REVIEW_CASES, with the two hook
orders forced independently of Lua table iteration. The harness models downstream
gamemode application separately from W's preparation. Native captures/timing remain
required in the PoC; unit cases do not claim particle rendering or native physics proof.
An independent strict-time-order check guards the full native timeline and foregrip subset.
The second review runs bullet/launch/tracer scenarios with both stock and ULib-style
priority tables, plus unknown-library fallback cases. Movement tests compare the same
tracked swing during standing, walking, sprinting and platform translation. The former
model_decals_scope case now checks that the setting is untouched, as explicitly requested.
An evidence case accepts a native held contact on an indestructible target only with
matching Impact evidence; wrong/missing entities and zero damage are rejected.

Third-review evidence cases require an engine damage witness on the spawned target,
matching phase id/tick/window, and a nonzero Impact ray. Missing/mismatched witnesses,
start-solid rays, wrong phases and out-of-window damage all fail.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Q4 adds independent posed-mesh grip references for ten stock models and all-class captures in both hands. Stock weapon_fists has an empty WorldModel: its avatar hands are checked, and no nonexistent weapon mesh is required. Other modeled weapons retain strict independent grip limits. Private fixture Lua now stages as plain files in the journaled test add-on and installs the shared ULib API into the existing engine hook table.

Q4 adds all ten remaining stock grip landmarks against independent posed-mesh points, both holding hands, and rejects treating a rotated SMG attachment marker as its barrel. An actually misdirected rendered barrel still fails the unchanged 2-degree bound.

Review adds two death-ownership mutants requiring their specific failure, plus camera/feedback/world-model policy regressions.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


The independent rig oracle omits frame.grip and rejects a grip moved onto the same model's muzzle/barrel. Old SMG X fallback and real2.9degree skew are rejected at.1degree.

Round5 mutations include pistol reverse/90degree roll, AR2 reverse, SMG/AR2 magazines/stocks, barrel/muzzle,3cm placement, X fallback,2.9degree skew and old melee tips. Every rejected path must hit its independent witness.
