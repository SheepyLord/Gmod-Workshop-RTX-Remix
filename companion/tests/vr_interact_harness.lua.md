# vr_interact_harness.lua

Damage regressions distinguish explicit bare/held curves and the legacy two-argument weapon
API; the latter must retain 32 damage at 150 units/s with scale40, while explicit bare is25.

Independent task P LuaJIT harness. Run `luajit companion/tests/vr_interact_harness.lua ROOT CASE`,
normally through vr_interact_tests.py. Reuses F's independent vector/Euler stand-ins and
implements entity/physics, visibility, damage, use, convar and lifecycle stand-ins.
Cases test maths, throw history, two-hand transforms, hull/bone nearest points/protection,
death/Exit cleanup, grab API/throw/NPC refusal, climb movement, use/melee and heavy inertia.
Inputs: repository root, case name. Output: PASS CASE or assertion/stack trace. Exit 0/1.
No game, OpenVR, file writes or external changes. This harness cannot prove VPhysics contacts;
the separate PoC probe does that.

Integration regressions: bare/held speed caps, real damage application and stable per-hand debug identities.

Q integration adds body_trace for own proxy, player, held/released body, unrelated body and cleanup exclusions.

The client case also checks owned-held body exclusion, unrelated solids and predicate cleanup.

climb_delayed_body applies a 12-unit pull with seven samples of common head/hand body lag; total is 12, with no acquisition jump or repeated movement after stopping.

two_hand_use calls the real action helper with both hands on one button: one native Use
inside 0.3 seconds, then a later intentional press is allowed.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


Additional review cases reproduce/correct an underdamped discretisation, a second damage-force impulse, a destination wall after teleport and two hands evicting one target cache. The production PD loop must settle monotonically for all five tested masses; delay 0..3 climbing remains already correct.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

verify_heavy_moving_lag replays the combined heavy ramp derivative (40,0,16 units/s for half a second at 66 Hz). Its lag must exceed 3.3 units to leave margin for the native >3-unit criterion; the old gains produce 3.016 and fail.

The heavy moving ramp additionally requires at least .36 seconds above 3 units. Former omega4 response stays above for only .303 seconds and fails; retained in reproduce-heavy-duration.log.

Adds actual bare/held collision callback regressions with body velocity200 and no tracked motion, then a genuine relative strike. review_proxy_walk now uses vel0 and wvel200/400, with a zero-error feed-forward check and walking simulation. Pending-marker tests count native hides across idle frames.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.

Review regressions cover individual Use masks, stale touch/held press after claims, explicit grab/drop ownership, collision invalidation on register/expiry, main grip gating versus off damage, and separate projectile feedback cleared at death.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


q4s_trigger_claim_item requires both-hand healthkit grabbing under trigger-only ownership and forbids Use.
