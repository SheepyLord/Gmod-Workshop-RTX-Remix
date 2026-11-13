# vr_move_harness.lua

Run through `vr_move_tests.py`, or `luajit companion/tests/vr_move_harness.lua <repo> <scenario>`.
Loads production movement modules and client core against F's Euler/wire stand-ins, an independent
swept-AABB world, fake player/input/transport, owned hooks and overlay/native stand-ins. The collision
fixtures test the player's real standing dimensions (32 by 32 by 72 game units), floors, walls,
12-unit steps, a 48.25-unit mantle, ceilings and moving obstructions. Native functions never load OpenVR.
Also checks exact trigger-speed server flight, climb arbitration without walking backlog,
toggle/physical eye height, seated offset, restart-aware calibration and a thin ceiling whose
far-side head endpoint is clear but whose eye sweep must fade.
The doorway case fits the 72-unit player under a 76-unit ceiling and requires a level teleport,
so a gratuitous step-up cannot reject a usable corridor or make the shift bob.
The float-wire regression forbids Source vector encoding for cumulative room distance and
continues from 20000 units. The paused-teleport case freezes simulation time while wall time
advances and requires an expired request to stay put.
The blink-ack case checks full opacity after the result, followed by fade-out and hiding.
The crouch-view regression crosses the physical threshold while toggled, requires no upward
camera pop, then bends below virtual duck height and requires the camera to follow farther down.
Follow-up cases drive 180 rendered poses with delayed/asynchronous body receipts, check wall
discard and prediction, retain stick/teleport/floor displacement, test the real core ViewFeet
round trip/lifetime, and preserve camera roll while zeroing the command roll.
Motion cases interpolate 66 server ticks into 90 rendered frames at 400 units/s, stop without any
backwards step, and combine delayed non-room movement with undelayed room input. The owned wire
stand-in encodes double timestamps as actual eight-byte IEEE754 values.
Outputs scenario measurements and `PASS <scenario>`; assertions give nonzero exit. No file writes,
settings outside the process, timers, Steam or game processes.

Integration regression debug_reuse executes 100 real module frames and checks all nested debug table identities.

Q integration adds physical_hands_body_filter, exercising the movement sweep with body-specific exclusion while keeping unrelated solids.

The own-body test covers both server and client prediction filter bridges.

coalesced_motion independently simulates 33/22 Hz FOLLOW streams and one-tick delayed delivery at 90 rendered frames/s; steady increments must remain exact. Room prediction and one-tick streams retain their prior tests.

render_time_motor advances the wall clock by 3 ms within one FrameNumber and requires the rendered motor to advance by 0.6 units at 200 units/s.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


The retained review_render_hands_current_motor regression advances wall-time interpolation inside one FrameNumber without changing the native pose/base. Both the camera head and drawn right hand must use the new motor transform.


Paused room motion now translates both held controllers together with the HMD and asserts their resumed world poses stay within server reach. This avoids a physically detached-controller fixture invalidating whole sync packets.


Arc paint criterion now requires >=256 polygon operations (three dots and target, four 64-segment rings), and all four roles visible. >500 belonged to the former eight-dot arc. The stock hook stand-in supplies hook.Call for the authoritative-dispatch probe.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.


q4s_medium_head_rule runs real L/Core with conflicting off-hand yaw, head-45 and gun+/-45 in water/ladders.


Medium head-rule expectations now preserve head pitch on ladders too, matching ordinary Source climbing.

q5_noclip_underwater covers water0/2/3, unarmed and gun+/-45, stick-only zero speed and hand-directed trigger flight.

q5_ladder_overlay_pipeline dispatches the real before-overlay lifecycle, then verifies repeated actual5degree movement commands still have forward/no-side buttons.

motor_cadence_kept_across_reset and motor_buffer_change_without_hold drive the real predictor at 90 renders and 66 ticks
with FOLLOW every third or second tick (`motorRun`): after a generation change the steps must stay within 20 % of nominal, and
a one-tick buffer growth and its later shrink must neither hold the camera (below half a step) nor skip it (above 1.5 steps).
Both fail on the predictor before ADR 0196 (0.00 of nominal). motor_buffer_alternating_gaps_hold sends three-tick gaps
with a four-tick gap after every twentieth packet: the buffer must not change after two seconds and every step must stay
within 3 % of nominal (without the hold it changed eight times). motor_buffer_change_without_hold also checks
that a grown buffer is still held after eight seconds and shrinks back after the ten-second hold.
