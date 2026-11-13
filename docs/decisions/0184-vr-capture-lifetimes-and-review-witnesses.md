# 0184: VR capture lifetimes and review witnesses

Accepted for Q's branch integration, 2026-11-12, under the independent review directed by Claude.
Extends [0183](0183-vr-review-resource-and-physics-corrections.md); no native/runtime cap changes.

A logical canvas may already have been painted before its first or recreated native handle binds.
The runtime copies a render target when that target is painted. Binding therefore invalidates the
canvas immediately and for the following render frame, covering deferred render-thread registration.
Static ghosts, glove markers and disabled/re-enabled HUDs must not return as empty native overlays.
Ordinary duplicate paints in the same frame remain avoided.

The private probe queues captures until visible handles have had two frames to paint, forwarding at
most one per frame because the runtime has one capture-request slot. It records semantic roles at
dispatch. Missing visible source images, native refusal, readiness timeout and unfinished requests
remain failures. A hidden source can retire between dispatch and copying; its absent image is allowed.
This does not make a missing visible image acceptable. Generated probes retain the full helper bytes.

Review fixtures must prove their preconditions. A player-hull-blocking BSP coordinate does not prove
a hand-height sweep is blocked. The lifecycle witness uses a native thin collision box, proves the
sweep hits it, and attempts an otherwise eligible behind-wall grab for start, tracking recovery,
respawn and a synthetic destination discontinuity. Real blink/shift wiring is tested separately.
Paused room walking translates the held controllers with the head so reach validation stays meaningful.

The deliberately throwing close hook is expected only with its exact private source/message, a
counted invocation, and a surviving real menu. Other UI errors still fail. The stale-FOLLOW fixture
restores the deliberately stopped server move module and its cumulative room baseline before paired
CPU control; health probes at both ends require live modules, hand physics and fresh sync. These are
private evidence controls, not a product module-reloading feature or a V4 acceptance claim.
