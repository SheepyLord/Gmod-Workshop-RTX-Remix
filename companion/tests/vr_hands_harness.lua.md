# vr_hands_harness.lua

Offline harness: `luajit companion/tests/vr_hands_harness.lua <repo> <scenario>`.
Loads production hands/pose helpers and F's actual resource registry. Reuses F's independent
Euler/vector stand-ins, adding rigid matrices, skeletons, analytic wall traces, client models
and overlays.

Twenty-one scenarios cover both skeletons/aliases, missing/invalid/index-zero bones, curls/axes/splay,
time-step-independent smoothing, grip override, scalar bounds, world/shoulder/solid traces,
finger-envelope contact, ghost visibility/one-time painting, model/skin/body changes (including
unprecached local models), fallback, depth/skybox suppression,
independent shown/target/head vectors under later in-place resolver edits,
wrist placement/scaling/collapse/stable rebuilds, deferred engine bone-name initialization,
dominant roles, invalid tracking and fault/Exit
cleanup. Prints `PASS <scenario>`, exit 0; assertions/errors exit nonzero. Everything is in memory;
no game, native module, OpenVR or file writes.


## V4 controller frames

C adds independent GetAngles to the rigid matrix stand-in for the anatomical calibration helper. The original scenarios and assertions remain.
Integration regressions: unsafe solid casts hide the model, preserve controller/head vectors, and repeated frames keep debug table identities.

## Review correction (2026-11-12)

skeleton_cache reproduces unthrottled reads, refits and a busy read during a property revision; the stable grasp and last good source must survive. anatomy_reset replaces a measurable model with a wrist-only rig and rejects reuse of old anatomy. The independent fixture supplies non-collinear knuckles and recorded SDK samples.

## Placement review (2026-11-12)

render_rate_sampling requires one WithController update per render frame and fails against the old 30 Hz cap. skeleton_cache still requires no duplicate reads, stable reference identity and last-good retention on busy reads.

Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

The pending ghost test also counts Show(false) calls: cancellation occurs once and five following idle frames must not issue another hide.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


The hook.Add observer forwards every trailing argument; q4r_dispatch_peer asserts actual ULib monitor registration before dispatch.
