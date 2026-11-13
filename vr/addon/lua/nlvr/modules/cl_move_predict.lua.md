# cl_move_predict.lua

Render-only movement predictor. `New()` returns `Receive(consumed, applied, origin, mode,
blocked, simulationTime, wallTime, generation)` and `Feet(ply, base, total, enabled)`.
Receipts carry cumulative room attribution and final authoritative feet. Subtracting actual room
displacement gives a non-room trajectory: walking, pushes, platforms, gravity and shift movement.
It is linearly interpolated one server tick behind on a monotonic render wall clock mapped to the
uniform simulation ticks. Packet arrival is not the presentation clock. The cursor never retreats
and never extrapolates beyond the newest sample, avoiding stop overshoot/backward corrections.
Generation/mode changes clear history for blink/respawn/discontinuities; paused-clock drift resets
the mapping without reversing the cursor. History is bounded to one second.

Current room intent and actual room displacement are added outside that delayed trajectory, so
head tracking stays same-frame. Pending walking is swept from authoritative feet with the player
hull; already granted noclip bypasses the collision sweep. The same interpolator handles XYZ,
including gravity/flight. No player state or permission is changed.

No player entity is moved, no movement permission changed, no hook/file/setting/receiver added.
The caller owns its lifetime and installs/removes the core's ViewFeet resolver. Caching keys include
render frame, receipt revision, room total and floor height. Invalid vectors are rejected. Outside
valid walking/flight state returns the unchanged core feet. Errors propagate to the module/core.

Q integration learns a bounded motor-only buffer from recent FOLLOW source-stamp cadence and measured delivery age when the shared wire coalesces movement with physical-hand packets. Delivery padding is quantized to simulation ticks; no extrapolation/backwards cursor, unchanged same-frame room addition, and generation/mode resets. The maximum is 120 ms; single-tick streams retain one tick.

The motor trajectory is now sampled at each actual view lookup; only room collision/pending correction is frame-cached. Earlier CreateMove/resolver calls in a busy frame cannot freeze the rendered motor position at an uneven earlier wall time.


Review correction: FOLLOW older than 0.3 seconds returns the engine base position; fresh packets reset the stale motor buffer. Initial room prediction has a bounded 0.3-second acknowledgement grace.

V4 final ([ADR 0196](../../../../../docs/decisions/0196-vr-motion-keeps-the-wires-cadence.md)): a discontinuity clears the trajectory
(samples, clock, cursor) but keeps the learned cadence and buffer, so movement after a blink, respawn, mode change or pause is
not starved between coalesced FOLLOW packets while sixteen gaps are relearned. A buffer change of up to 1.5 ticks is eased in:
the motor clock runs at most 2.5 % slower or faster until the delay in use (`delaySeconds`) reaches `bufferSeconds`; applied at
once it held the camera for a frame or skipped one. Larger changes (the session's first learned cadence) still apply at once. The buffer grows at once and shrinks only
after the larger value went unneeded for ten seconds, so a wire whose sixteen-packet maximum flips between two gaps
keeps one buffer instead of easing all the time.
