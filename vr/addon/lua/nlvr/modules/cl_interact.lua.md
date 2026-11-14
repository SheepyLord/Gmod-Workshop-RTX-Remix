# cl_interact.lua

Client physical interaction module, order 50, included at Start VR. Takes F's context.
Message 41 supplies server hands/held entities/climbing/gloves/throw/haptic debug state.
The priority-200 resolver runs after H, places shown hands at the physical proxies and
fills `Hand[hand].held` and five `grip_curls`. Changed held entities emit local `grab` and
`release` with physical hand, entity and bone. Climbing also provides a closed grip pose,
without inventing a held entity. State expires after 0.4 s without a receipt.

The priority-95 client mover sends changed settings and grip/trigger claim availability
using message 40, after the first host acknowledgement. Frame updates place a small
gravity glove target in F's reserved overlay canvases. Short native Haptic calls follow
new server pulse sequences. No world UI/halo or physics change is performed on the client.
Sequence wrap is accepted; native haptic success/error is retained in Debug.interact.

Stop destroys owned marker overlays, clears held poses/debug. F removes its callbacks,
resolver, mover and message handler. No file writes, new convars, timers or autoruns.
Errors propagate to the module registry; there is no process exit code.

Integration: reuses the two Debug.interact hand tables across network receipts.

Q integration extends BodyTrace to client prediction: exclude only the locally held/pulled entity and 0.2-second owned release grace from the already-known server state. Stop removes the predicate. Unrelated props/world remain solid.


Review correction: state 41 reads authoritative obstruction offset. Drawing follows current tracking with that correction between snapshots, retaining H geometry stops and invalid shown-hand suppression; receipt changes invalidate the core resolver cache.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Unwanted glove markers call Show(false) only while visible or wanted, canceling pending acquisition once without repeated native hide/transform calls.

**V8 ([ADR 0203](../../../../../docs/decisions/0203-precise-vr-holds-follow-the-hand.md)).** Message 41 also carries each hold's relation
(floats), `tracking`, `single` and the two-hand pair frame; they go to [`cl_interact_predict.lua`](cl_interact_predict.lua.md),
which draws a followed one-body prop at the hold's pose from this frame's hands. `Debug.interact[hand]` adds
`holding`, `tracking`, `rel` and `predicted` (`mode`, `follow`, `blending`), and `Debug.interact.pair`. Haptic pulses
last 35 ms for a hit, 50 ms for a freeze or a free, 18 ms otherwise. Stop gives every draw override back.
