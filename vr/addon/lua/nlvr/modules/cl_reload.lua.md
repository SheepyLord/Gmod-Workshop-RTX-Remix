# cl_reload.lua

Client module `reload`, order 46, included at Start by the fixed composition root.
Uses W's `NLVR.Weapon.Active`, claims, networking and overlay manager.
Owns main A for physical detachable-magazine guns (tap eject, >=300 ms secondary),
main B only on a <300 ms released tap for ordinary reload, and off grip over the
shoulder / while carrying. CreateMove priority 70 adds command bits and sends
actions; it never runs attack console commands. Config heartbeat is 0.5 seconds.

The server acknowledges pickup before a stock model is held. A matching token
travels with insertion. Release drops it; switching/death/settings discard carry.
Held ammo and ten-second client physics drops draw as world models. All models
are removed at Stop/failure. No client inventory mutation.

The reserved 387 x 129 ammo canvas shows clip/reserve and secondary reserve using
numeric text; reserve-only guns omit clip. Attached to the physical weapon device,
beside our local port, facing the head. Only number changes invalidate paint;
placement/visibility do not. Hidden for no ammo, disabled setting, missing tracking
or model, or a visible wheel overlay.

Outputs: Debug.reload (counts, zone, hold, reason, paints, drops), command bits,
models, overlay and off-hand insertion haptic. Hooks/receivers are registry-owned.
No file/archived setting writes; errors stop this module. No process exit code.

Without W's API Start remains inert. A priority-250 shown-hand resolver (after P,
before W) marks carried ammo as occupying the off hand and closes its fingers;
this prevents foregrip takeover. W's off-trigger secondary remains available when
K owns main A. Model-local points scale with the gun's own model scale.

Unchanged state packets are coalesced by the core: a granted ammo token persists
for its 30-second carry lifetime with fresh heartbeat acknowledgements, plus a bounded short-lapse grace.
Debug includes the three counter values and insertion haptic result. Losing W
stops K; Stop best-effort disables the server path after completing local cleanup.
The counter sits 11 cm toward the other hand and 8 cm above the model-local port,
converted through that stock model's frame. The offset mirrors for left dominance.
Drops use stock physics when present, otherwise a box from the scaled model bounds;
motion/gravity are enabled and the cosmetic body uses the debris collision group.
Debug records live physics-body count, position and remaining lifetime.
The last insertion result is separate from the last operation, so a subsequent
pickup/drop does not erase the accepted/refused insertion reason.
Stock ammo meshes are normalized once from their model bounds to physical lengths:
pistol 12 cm, revolver 7 cm, SMG 16 cm, AR2 14 cm, shell 6.5 cm, bolt 50 cm,
rocket 65 cm. The same scale drives held/drop models and fallback physics bounds;
held_metres records the actual model-scale readback for the probe.

A B tap is retained until exactly one user command consumes it. Render-only frames reassert its claim; changing weapon, dominant hand, physical mode, death or vehicle invalidates it. This avoids dropping release edges between render and command cadences.

The pending B bit also survives zero-number/zero-tick preview or prediction commands; only a nonzero networked command consumes it. The predicted bit is retained as [TickCount](https://wiki.facepunch.com/gmod/CUserCmd:TickCount) advises; [CommandNumber](https://wiki.facepunch.com/gmod/CUserCmd:CommandNumber) documents zero calls.

A fresh server carry grant marks the off hand occupied in resolver 250 even before its first visual model exists. W therefore cannot claim a foregrip in its earlier frame callback. Physical disable, release/discard or a different weapon immediately invalidate that marker.

The occupied marker is explicitly tagged as K-owned, so cleanup also clears a marker that predates creation of its visual entity. It never relies on nil-entity equality to identify another module's hand state.


Review follow-up: physical ownership requires a fresh server acknowledgement for
the current weapon, plus local alive/vehicle/setting checks. No ACK/expired ACK or
server inactive leaves the engine reload bit and ordinary B path available.
Shoulder claims require a free, non-climbing hand with no other module claim;
P's held prop is never displaced by entering the shoulder zone. B is retained
through player deploy/attack locks, and rate-refused gestures retry up to three
times with real-time spacing (the refusal remains visible in debug).

Counter setup, placement and paint failures are contained: only the counter is
disabled with counter_error in Debug.reload; reload/input continues. Appearance,
placement, dimensions and painter output are unchanged. Debug.reload is reused.

Deploy gating reads the documented Entity:GetInternalVariable("m_flNextAttack"); client absolute values are compared with client CurTime, while server ACK readiness uses its relative value. If unavailable clientside, a fresh server ACK's ready bit is used. No invented Player:GetNextAttack API is required.

A fresh negative server readiness ACK also wins over locally ready prediction, so the single B command cannot outrun the server attack lock.

Native verification corrected the realm distinction: the client m_flNextAttack is an absolute deadline compared with client CurTime; the server save value is relative. A fresh negative server-ready ACK still prevents early prediction.

A two-second hitch cannot reinterpret an in-progress eject as secondary attack;
A ownership/intent is latched until release and a hitch cancels secondary intent.
Unknown/stale server state never gives an eject tap to W. Physical B intent is
also latched. Carry visuals/hand ownership survive a short (<=5 s) ACK lapse,
while inventory gestures require a fresh ACK. Glove lock/pull is busy like a prop.
Retries follow the acknowledged action serial/result in later coalesced state,
not a transient action-kind reply. Unacknowledged requests retry at a bounded rate
for up to5 real seconds; refusal/timeout remains debug-visible. The counter reuses
its numeric buffer and compares scalars; it builds strings only in an actual paint.
