# test_vr.py

The second-review cases cover busy camera recovery and the first overlay-copy acknowledgement;
the group has 58 cases with the render-guard and catalog checks.

Review regressions include nil camera retention, thirty nil/message failures with deduplicated
logging, paused render-hook quit polling without timer ticks, page nil/message failure, failed
overlay Start and recenter. The harness models async stopping and SDK-ready bootstrap separately.

VR-Q adds SDK-ready first-frame bootstrap, asynchronous Stop acknowledgement and the translated
fps_max warning cases. The tested Index FOV default is 145 degrees. Catalog tests reject codepage
damage in every new translation.

Run `python -m unittest discover -s companion/tests -p test_vr.py -v` from the repo. Runs the production page and
add-on under LuaJIT in [vr_harness.lua](vr_harness.lua.md). Each scenario has its own Lua process. Skips when
LuaJIT is absent (PATH or LOCALAPPDATA/Programs/LuaJIT/bin); no OpenVR, headset, game, GPU, network or file writes.

Checks off-state work, explicit status probe, native/runtime/API errors, local/remote hosts, active/inactive
VRMod/gVRMod, asynchronous start/cancel/failure/quit/shutdown/hot reload, partial startup and frame/paint failures,
unchanged engine settings, predicted tracking transforms and lost tracking, exclusive CalcView ownership and
late hook restoration, once-per-sequence camera submission, wrist contents/repaints, intact desktop 2D/notices,
GPU boundaries and numeric status readouts. Includes the
[production guard canvas check](vr_guard_harness.lua.md). Exit 0 on success, unittest nonzero on failure.
The session-scale race and body/weapon proxy visibility are covered too: VR never toggles the proxy convars or
their secondary Remix shadow-option callback. All seven session hooks and the temporary CalcView table are gone
after cleanup. The engine convar stand-ins reject SetString, matching GMod rather than accepting unsupported writes.
An additional pure-Python catalog byte check runs even without LuaJIT and catches UTF-8 decode failures,
replacement characters and unexpected question marks in every VR message of all six languages. It caught a
Cyrillic category abbreviation damaged by a PowerShell pipe during development; UTF-8 file edits corrected it.

V2/F adds LuaJIT framework scenarios from vr_framework_cases.lua to the existing discovery suite; no extra driver or game dependency.

The framework currently adds twenty scenarios; the full page/add-on/guard/catalog suite has 78 tests.

Two teardown regressions bring the framework to 22 scenarios and the complete VR suite to 80 tests.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


The normal gate includes f_review_overlay_repaint for late/recreated native images.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Includes faithful ULib lifecycle, private-dispatch removal and ULib-shaped dispatcher refusal regressions from vr_view_ownership_cases.lua.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Adds client/server ladder-water movement-basis tests; the focused core suite currently passes97 cases.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


The options_no_format_write case runs under both hook libraries.


Registers the second-review medium-parity and late-yaw ladder cases in both stock and ULib core suites.

Round5 registers ladder sector, underwater noclip basis and ladder/tool command-order cases in both stock and ULib dispatch.
