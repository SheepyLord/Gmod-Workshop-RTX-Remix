# sv_interact.lua

Server physical interaction module, order 20, included by `nlvr/server.lua` only during VR.
Start takes F's module context; Stop is idempotent, including partial Start/failure. Owns
per-player `state.interact`, hidden hand spheres, held-body callbacks and the public
`NLVR_SV.Grab`, `Release`, `Holding` API (ADR 0169). Offsets are physics-bone local.
A grab stores the body's pose in the hand's frame, with the touched point brought to rest
against the palm (V8, below). Release converts wrist velocity/spin at the actual mass-centre offset.

Uses validated poses/history, tick interval, scale, message 40's three settings/four input
availability bits. Sends the changed state in message 41: both proxy transforms, held
entity/bone, blocked/climb/target/pull state, last throw/spin and haptic sequence/strength/kind.
One combined pulse per tick keeps the strongest amplitude and prioritises hit/catch/grab
above release/contact so a contact cannot erase a catch's feedback.
Hands are physical left/right. Server grab/release events carry player, hand, entity, bone.

Includes `sv_interact_math.lua`, `sv_interact_physics.lua`, `sv_interact_actions.lua`.
Resources use ctx hooks/events/mover/cleanup. Death/stale tracking/vehicles remove hands and
release props. Exit/unload restores player custom checks and the session-only
`ai_serverragdolls` change, if it still has the module's value.
Player movement is rechecked each tick: stale samples cannot recreate an out-of-reach proxy,
and a proxy left outside reach is released/reset without throwing its prop or re-pressing grip.
No prop ownership, collision
flag, gravity or mass is changed. No file write, autorun or permanent receiver. Errors stop
the module through F's registry; production Lua has no process exit code.

Q integration: owns NLVR_SV.BodyTrace while active, restoring/removing it through module cleanup. This lets L sweeps ignore only physical bodies already excluded from the same player by ShouldCollide.


Review correction: never writes ai_serverragdolls. Teleport displacement events carry proxies and holds; Follow precedes interaction. State message 41 includes obstruction offset so the client predicts between server samples.

Q4 integration centralises armed-hand ownership and released-projectile grace in P; passive touch honours the claim mask. W no longer edits P cooldowns or vetoes proxy damage. Camera override users share a lease and restore on module failure/Exit, preserving other config writers.

Independent review: ProjectileFeedback supplies grab then separate release feedback without borrowing a P grab on an owned hand. Pending feedback clears on death/Stop. ClaimHand drops held props; tests assert this and owned-grab refusal.

**V8 ([ADR 0203](../../../../../docs/decisions/0203-precise-vr-holds-follow-the-hand.md), [ADR 0204](../../../../../docs/decisions/0204-the-holding-hands-trigger-freezes.md)).**
`grab` anchors to `physics.Anchor` (the tracked palm, stopped at world brushes) instead of the proxy's physics position,
stores `grip.rel` (the body's pose in the hand's frame, the touched point moved to `Grab.PALM` from the palm if it was
farther; an API `localAng` still sets the body's orientation) and `grip.single` (one physics object), and makes a
partner grip on the same body re-form its pair frame. `release` re-captures the remaining hand's relation where the
body is, so letting go of one hand never moves it; the throw's wrist is the hand's anchor. Message 41 adds, per hand,
whether it holds, the relation as six floats, `tracking` and `single`, then the two-hand pair frame (or false).
Pulse kinds 6 (freeze) and 7 (free) outrank the others in a tick.
