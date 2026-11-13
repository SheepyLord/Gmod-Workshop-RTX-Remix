# vr_hands_test.py

Each case uses C's isolated recorded-fixture context under out/tmp, so concurrent gate/direct runs do not share a writable Lua file.

Runs twenty-one LuaJIT scenarios against the real task-H hands module/helpers without a game,
renderer or OpenVR, using existing LuaJIT discovery and the independent
[skeleton/trace/matrix harness](vr_hands_harness.lua.md).

Usage: `python -m unittest discover -s companion/tests -p vr_hands_test.py -v`.
Inputs: repository sources and LuaJIT. Captures subprocess output; no durable output or game/settings
changes. Exit 0 means all passed (or explicit skips when LuaJIT is absent); 1 means failure.
Each case has a 30 s timeout.

## Review correction (2026-11-12)

skeleton_cache reproduces unthrottled reads, refits and a busy read during a property revision; the stable grasp and last good source must survive. anatomy_reset replaces a measurable model with a wrist-only rig and rejects reuse of old anatomy. The independent fixture supplies non-collinear knuckles and recorded SDK samples.

## Placement review (2026-11-12)

render_rate_sampling requires one WithController update per render frame and fails against the old 30 Hz cap. skeleton_cache still requires no duplicate reads, stable reference identity and last-good retention on busy reads.

Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
