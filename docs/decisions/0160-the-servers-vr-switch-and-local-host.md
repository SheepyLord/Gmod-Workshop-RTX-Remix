# 0160: The server's VR switch and local host

Accepted for the V2/V3 task branches, 2026-11-11, implementing
[interfaces 6 and 7](../handover/VR-V2V3-plan.md). Remote/full multiplayer remains V5.

The companion has one server autorun stub: one network string and one receiver named nlvr.
It includes nothing and adds no hook or timer while off. Only a player in single-player or the
listen-server host's own player can start the server component. Authority is checked in the stub
before payload reads and again in the server core. V2/V3 do not distribute the add-on to other
clients or change the loader's multiplayer bootstrap.

A type byte distinguishes Start, Stop, Sync and the fixed module ranges. Start carries the
validated 10..100 world scale, needed to express the 2.5 m reach in game units. Repeated Start
updates scale without resetting sequence/history; calibration can therefore change scale later.
Stop carries no payload. Each sync is exactly 1467 bits including its type: uint32 sequence,
head pose and validity, and two hand poses/validity, velocities, grip/trigger values, curls and
button masks. Position, Euler angles and velocities use float components, avoiding compressed
net vector/angle loss. A valid sequence must advance modulo uint32. The client sends from
CreateMove at most once per engine tick; the server permits two arrivals per server tick for
normal transport bunching. Invalid length, non-finite data, impossible control ranges, stale
sequences and positions beyond reach of authoritative EyePos are dropped without changing state.
Invalid tracking is transmitted explicitly; modules must not interact through an invalid hand.

The server owns the last second of each hand's accepted samples, with a hard 1024-entry cap.
Start, Stop, Sync, Death and Spawn events give modules their player state. Death leaves the VR
session running so interaction can release its objects. Disconnect, shutdown or the last Stop
releases every server module and hook and removes NLVR_SV, leaving only the stub's receiver.

Server movers run in ascending priority in SetupMove. The first true result owns that command;
Move then returns true to suppress default movement. Modules mutate move data rather than the
entity. They choose climbing before teleport before noclip before normal by those priorities.

Module Send writers receive a bounded, net-shaped buffer argument instead of writing to global
net. This preserves the specified Send(type,writer) interfaces without replacing any global net
function and permits snapshotting, changed-only comparisons and deferred sends. Readers use
matching net.Read functions. Server output sends at most one changed module packet per player
per tick, coalescing pending intermediate states. Incoming module packets are bounded to 4096
bytes and 64 per tick. The sync uses its separate tighter limit. Feature tasks own their assigned
message ranges and the semantics/validation of their own payloads.

These constraints grant no new native trust or remote physics authority. A malicious local host
already controls its own server, but malformed traffic still must not create unbounded work.
