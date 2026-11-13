# vr_combined_review_server.lua

Private server phases for Q's combined review: real walking/gripping/throw velocity, native spring
responses for 0.5/1/10/250 kg bodies, bounded light/heavy melee, a proxy recreated with a wall between
eye and controller, held blink/shift and intentional server move shutdown. Records actual bodies,
positions, errors, velocities and settling times as NLVR_P review records. Reads ai_serverragdolls
before/after without writing it. Uses existing admin fixture commands and actual production physics
helpers. All created props/hooks live only in the snapshotted PoC process; normal process exit and
rollback remove them. Inputs: nlvr_review_stage NAME and the active server session. Outputs: console
records included in combined receipt. No standalone exit code; missing observations fail acceptance.

The native mass phase also holds the lightest bone of a newly spawned ragdoll. The mesh cost control
temporarily supplies 2,000 triangles from one native PhysObj's GetMeshConvexes, restoring its metatable
method under protected cleanup. Reports 100 full production A.Target iterations for two distinct hands, with the cache bypassed versus enabled, on the actual server game thread. This isolates Lua targeting cost, not a claim about an existing model's
triangle count. Proxy wall cases include a tracking interruption and an actual death/respawn.

The older BSP-coordinate fixture was invalid at controller height; the current thin native box proves its blocking sweep. Carry records include every actual teleport displacement, the same held entity and any release event; shift must exceed the former 480-unit/s proxy cap. Requested test masses are checked against native GetMass readback. Bare Hands is selected explicitly after the test respawn.


The wall witness now uses a 1-unit-thick native VPhysics box, explicitly proves its sweep blocks, and verifies an otherwise in-reach prop cannot be grabbed through it. Covers fresh proxy, tracking recovery, actual respawn and a labelled synthetic destination teleport; real blink/shift are tested separately. A clearance interval puts the proxy beyond the future plane before the destination sweep. After the stale-FOLLOW test, the private fixture restores the server move entry and saved cumulative room baseline before CPU control. Health witnesses require valid hand proxies and fresh sync.


The glove benchmark moves two hand queries/aims at 200 u/s on actual server ticks for 1.5 seconds, using a controlled native-body mesh/hit and real CurTime. Additional negative carry witnesses set up real public grabs and test synthetic displacement against a native wall or weld; release and unchanged body position are mandatory. These do not replace positive real blink/shift checks.

Carry setup waits for a fresh proxy within one unit and an actually delivered grip, then calls the public Grab immediately after spawning the body. review-carry-setup records success/control/entity and is mandatory for hold, blink and shift. Server samples retain tracking-relative and world hand velocities separately.

Carry preparation additionally requires the actual received grip bit, existing permitted control mask and settled real proxy before public Grab. It never forces claim masks or transport results.

Packing correction: protocol grip is bit1; trigger bit2 alone must not satisfy the new carry preparation guard.
