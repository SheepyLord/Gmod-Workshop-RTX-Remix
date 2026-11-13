# vr_combined_clock.lua

Private simulated functional replay, embedded by `vr_combined_session.py`; never packaged or used
by the temporal fixture. Inputs are the recorded combined steps and native frame/action functions.
It replays the entire functional timeline of poses/actions on Source game time, so synchronous GPU/disk
captures cannot skip short crouch/toggle/teleport input windows while physics is stopped. Intentional
single-player menu pauses advance on wall time, retaining the three-metre pause/resume test.

Native sequence/pacing/camera submission remain real. Receipts retain raw `native_time` alongside
functional time and excluded wall seconds. Full-rate temporal measurements retain the unwrapped
native timeline. Stop restores all three functions. No filesystem or external side effects; errors
propagate as test failures. See `tools/tests/vr_combined_clock_cases.lua` for the stall regression.

The whole functional timeline now uses Source time, including physical slots. Native sequences and raw wall times remain unchanged. Replay preserves native analogue/skeleton active fields and interpolation, translation derivatives and single-axis angular derivatives; offline cases check 120 u/s and 1.16 rad/s throw rates. This prevents capture stalls skipping the server death-ragdoll grab window too.

Production fixture EngineTime is simulation tick count times tick interval; predictive client CurTime is not the authoritative physics clock across capture stalls. Deliberate menu pause tracking and unwrapped temporal behavior are unchanged.
