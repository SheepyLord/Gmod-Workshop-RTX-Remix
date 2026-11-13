# vr_interact_tests.py

Runs task P's real Lua modules under LuaJIT with the independent vr_interact_harness.lua.
Usage: `python companion/tests/vr_interact_tests.py -v`. Python standard library only; LuaJIT
discovery follows the existing companion test helper. Each case is a separate bounded process.
Twenty-eight scenarios cover geometry/gesture/arc/damage, history/spin, two-hand transforms, permissions,
nearest ragdoll bone, API validity, cleanup, climbing, mass-dependent response, client events,
claim/config coalescing, stale hands, haptics, glove catch/release, and climbing through floor
contacts while lateral walls still stop hands.
Also checks point-ladder endpoints and restoration of pull/player collision pairs and two-hand references.
Inventory tests ensure native touch staging restores a refused/full kit on timeout or Exit and obeys permissions.
The native-prop case keeps the entity table's engine-method fallback, proving it is not mistaken for scripted Use.
The held-contact case queues a physics callback, consumes it outside the solver and checks one club hit/cooldown.
Includes vertical grip baselines and rebuilding proxy radii after calibrated world-scale changes.
Player-position discontinuities release/reset remote proxies without a throw or stale-location pickup.
Scripted props inheriting base_anim's empty Use still grab; a scripted kit's real Use stays authoritative.
The physics stand-in applies impulses; gravity compensation is verified at 30/66/120 Hz so a force cannot be passed unintegrated.
Held grip acquires a later contact; the authoritative world stop keeps H's full finger envelope and bypasses it for climbing.
Usable contacts stay claimed without repeat toggles or accidentally becoming physical grabs; grip reaches use targets at normal grab reach.
Contact offsets avoid snapping a held surface into the wrist; release grace suppresses stale proxy impact/damage and expires cleanly.
Collision-sweep hits queue contact feedback when base_anim omits PhysicsCollide; it is consumed outside physics and throttled.
No game/SteamVR/file writes; console unittest output. Exit 0 on pass, 1 on failure. LuaJIT
absence is a reported availability skip. Run alongside tools/test.ps1, whose discovery is tools-only.

Q integration adds body_trace; 29 scenarios.

Q adds climb_delayed_body; 30 scenarios.

Q adds two_hand_use; 31 scenarios.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


The normal gate now includes review_critical_spring, review_melee_damage_force, review_teleport_wall and review_glove_two_hands, alongside the first review regressions.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Includes verify_heavy_moving_lag in the retained offline regression cases.

Mutation coverage copies Lua sources into out/tmp, reverts bare contact subtraction, Follow world feed and held contact conversion separately, and requires their dedicated regressions to fail. Workspace source is never modified by mutation tests.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Review mutation tests revert each collision/claim guard independently in an out/tmp clone and require its specific assertion, not an incidental loader failure. Existing motion mutants remain.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


Registers the trigger-only healthkit regression.
