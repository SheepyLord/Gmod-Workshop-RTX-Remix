# cl_move.lua: movement and comfort

Client module, order 30, loaded only at Start VR. Uses the framework's per-frame tracking,
logical input/claims, priority-0 command mover, settings/events, network and owned overlays.
Room-scale translation is consumed into cumulative bounded server input while the head stays
over the collision-checked player hull. The play space owns only horizontal tracking compensation;
Source supplies feet height. Tracking loss reacquires without a movement jump. A render-only
ViewFeet resolver adds room input not yet processed by the server to its final authoritative
origin, clamped by a client hull sweep. Thus horizontal head tracking does not wait for body ticks.
Non-room XYZ movement is interpolated separately at render time; walking, pushes, platforms, shift
steps and already granted flight therefore share the smooth path without delaying room tracking.
An eye-sized sweep from the engine eye to the tracked head catches thin ceilings even when the
endpoint is clear beyond them. Blocked room movement sustains full fade while the person keeps walking.

Off-stick moves in hand/head direction; click sprints and A jumps. Main-stick horizontal turns
about the head (snap latch or smooth degrees/s), down toggles crouch, up holds the teleport arc,
release requests a server-checked blink/shift. Mouse delta turns the play space. Physical crouch
uses standing-height hysteresis; seated mode uses the core's translation.
Virtual crouch offset blends out as physical height falls, avoiding an upward pop when physical
duck becomes active; deeper-than-duck bends remain tracked. Standing/duck hull permissions stay with Source.
Existing noclip uses the off hand's full direction and trigger fraction of run speed; the module never grants noclip.
Blink remains fully opaque until the result and for 0.08 s afterward, then fades out over 0.12 s.

`NLVR.Move.Calibrate()`, `NLVR.Emit("calibrate")` or `height_calibrate` measures standing eye
height, archives `nl_vr_height` and the matching `nl_vr_scale`, and emits `calibrated` with
`{height,scale,restart}`. Native stereo scale is latched at Start, so a changed scale applies on
the next Start; the current camera and stereo retain one scale. Task M owns the page/button.
`NLVR.Debug.move` exposes plain positions, play space, follow receipts, turn error, crouch,
speed, fade/vignette, target/refusal, teleport outcome and calibration state.

Uses messages 24..27 (see the maths sidecar); cumulative room coordinates use explicit float32
components, avoiding Source's bounded/quantized net vector codec. No file writes, autoruns or global input overrides.
Calibration is the sole archived-setting edit; normal sessions only read settings. Resources,
receivers, events, ViewFeet resolver and overlays are framework-owned and removed at Exit. Missing collision queries
or player movement APIs leave the core camera usable and movement inactive. Errors go through the framework.
User command angles copy head pitch/yaw with roll zero; tracked camera roll stays intact.

Integration: reuses Debug.move and its position, head, room, anchor and target arrays; calibration restart is exposed to the page.

FOLLOW debug exposes motor_buffer_seconds so the added motor latency is measured explicitly rather than confused with head latency.


Review correction: single-player game-menu room motion is discarded while paused, updating the tracking baseline/anchor so resuming after 3 m does not accumulate a rejected reach offset.


FOLLOW receipts increment the core MoveRevision so an authoritative origin change invalidates the pose cache. CalcView samples motor interpolation at its actual view boundary, sharing the result with both rendered hands.


Water and ladders steer with the head, independently of gun or off-hand direction setting. Water retains pitch; ladder intent uses head yaw.


Ladder forward/side command magnitudes are supplied in the head basis, whose pitch is preserved by Core rather than flattened.

Noclip takes precedence over swimming at water levels2/3. At the movement mover end, ladder-only intent is sectorized before physgun distance controls. Small sideways inputs inside22.5degrees stay in the forward/back ladder sector.

The ladder button stamp belongs at the end of move(cmd), never before_overlay_paint. Native medium02 exposed a nil-command call in that render callback; the retained real overlay/mover pipeline test fails before and passes after the correction.
