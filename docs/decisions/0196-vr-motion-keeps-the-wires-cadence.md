# 0196: VR motion keeps the wire's cadence and eases buffer changes

- Status: Accepted 2026-11-12 (Claude, finishing V4 at the user's request); merged to `main` with V2-V4.
- Decided by: Claude, from the final package's simulated motion runs.

## Context

The render predictor ([`cl_move_predict.lua`](../../vr/addon/lua/nlvr/modules/cl_move_predict.lua.md)) draws the
camera's motor position from the server's FOLLOW stamps, a buffer behind them that it learns from their cadence and
delivery age (Q's integration). In V4 the shared wire coalesces FOLLOW with the hands' packets, so it arrives every three
to five ticks and the learned buffer moves between 45, 60, 75 and 90 ms during a walk.

The final package's simulated `allmotion` runs failed the 10 % camera-step spread twice (walk 13.1 and 17.5 %, sprint
25.4 and 46.3 %, flight 21.8 and 21.7 %), where the V2/V3 package had passed at 0.6 %. The probe's rows showed two causes:

- Each one-tick change of the buffer was applied at once and moved the target a whole tick. The cursor never retreats, so
  the camera held for a frame when the buffer grew (the six camera stalls of the first run all fell on 60 -> 75 ms changes)
  and skipped ahead when it shrank.
- Every discontinuity (a blink, respawn or mode change, or 0.3 s without FOLLOW) reset the buffer to one tick. Between
  coalesced packets the first half second of each movement then starved: zero steps until sixteen gaps were relearned.

## Decision

- A discontinuity clears the trajectory (samples, clock mapping, cursor) and keeps the learned cadence and buffer.
- A change of the buffer of up to 1.5 ticks is eased in: the motor clock runs at most 2.5 % slower or faster until the delay
  in use (`delaySeconds`) reaches `bufferSeconds`. Larger changes, such as the first cadence learned in a session, still
  apply at once.
- The buffer grows at once but shrinks only after the larger value went unneeded for ten seconds. With easing alone the
  PoC's buffer still changed three to six times in a 1.4 s window (spread 11-13 %, no stalls): the sixteen-packet
  maximum flips whenever a four-tick gap enters or leaves it. A two-second hold with 5 % easing left one change per walk
  (walk 11.1 %, sprint 4.1 %, flight 8.5 %).

## Consequences

- No camera hold or skip from buffer changes; after a reset the steps are nominal from the first moving frame. Offline
  (`motor_cadence_kept_across_reset`, `motor_buffer_change_without_hold`): steps 1.000 of nominal after a reset and
  0.975-1.025 through a one-tick growth and shrink; the predictor before this decision gives 0.00 in both.
  `motor_buffer_alternating_gaps_hold`: no buffer change and steps of exactly 1.000 on a three/four-tick wire (eight
  changes without the hold).
- The motor delay sits at the larger of the alternating values (75 instead of 60-75 ms on the PoC's wire).
- Motor latency right after a reset is the learned buffer (at most 120 ms, as before) instead of one tick; head tracking
  and room movement stay same-frame.
- The PoC result on the final package is in the [V4 report](../handover/VR-V4-report.md).
