# vr_framework_cases.lua: Framework offline scenarios

Invoked by vr_harness.lua for f_* cases through test_vr.py. Exercises play-space round trips, head-pivot turns/feet shifts, poses/resolvers/rays, dominant input/claims/taps/holds, scoped settings, movers/aim, failed-module cleanup/order, invalidation/odd sizes/front-face hits, exact wire length/round trip/rejections, server validation/history/rate, movement priority/events, changed-only sends, dormant stub authority/restart and once-per-tick client sync. Uses the production Lua and independent stand-ins; no game, SteamVR, filesystem or real network side effects. PASS marks completion; assertions exit nonzero.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

Additional cases cover attached rotated overlay hits, invalid-tracking sync, stale hand/history expiry, failure during mover iteration, immutable deferred packets, bounds and queue fairness.

The closing-channel cleanup and fatal-frame-in-CreateMove cases also require zero leaked receiver and no post-STOP sync.

V4 updates the settings count to 19 and checks world movement after Aim rebasing. Loads vr_v4_cases.lua with the existing environment/helpers; those nine scenarios run in the separate scaffold gate suite.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


f_review_overlay_repaint covers hidden-first canvas painting, late native binding, following-frame registration and retirement/recreation. It first reproduced a blank native image from a static reused canvas.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Independent review regressions exercise ladder/swim commands and both SetupMove paths at +/-45 gun pitch; move pitch stays zero and weapon command pitch is retained.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


Second-review regressions cover late head yaw .05/1/5degrees, small/side inputs and armed/unarmed water/ladder parity at head-45 and gun+/-45.


Native ladder follow-up preserves head pitch as well as yaw. Flattening pitch caused Back to climb up in real Source; armed/unarmed head-directed parity replaces that incorrect chosen rule without relaxing any angular/direction bound.

Round5 adds fail-before/pass-after8-way ladder sectors(0,3,5,10,20,22.5+/-.001,45,67.5+/-.001,90degrees; head0/-45), untouched vehicle buttons, underwater noclip bypass, and tool commands surviving core dispatch. Tiny .02 side against3 forward now expects no side button.
