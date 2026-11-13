# vr_harness.lua

Second-review regressions hold the last accepted camera through one busy push, stop after
thirty repeated camera errors, and repaint an unchanged HUD until the runtime acknowledges it.
The stand-in reports wire API 3; the Lua API remains version 1.

The review scenarios call the actual render-based page poll without simulation timer ticks,
return nil/message from native stand-ins, assert the held camera and error log count, and check
recenter against explicit standing-position/yaw arithmetic.

VR-Q covers SDK readiness before renderer RUNNING (view hooks supply the first camera), Stop's
asynchronous off acknowledgement with Start refused during cleanup, and a low FPS-cap warning
that never changes fps_max. These remain offline stand-ins, not headset measurements.

Usage: `luajit companion/tests/vr_harness.lua <repo-root> <scenario>`; test_vr.py enumerates scenarios. Reads the
shipping page/add-on, stubs GMod's player, vectors/yaw transform, hooks, convars, render target, fonts, paint,
menu/timers and the work plan's API-v1 module. No file/network writes, no native load. Asserts cleanup and exact
values, then prints `PASS <scenario>`; assertion failures exit nonzero. The three engine variables reject setters;
Lua-created variables keep working. Cases cover CalcView before PreRender, once-per-frame sampling/sequence
submission, competing/late camera hooks, predicted/current-duck offsets, and proxy children/Think fields. Desktop
2D/global dispatch functions stay intact. The separate vr_poc driver proves the raster canvas in the real game;
native compositor/eye images remain integration's job.

V2/F extends includes to the fixed module tree, scoped convar callbacks, net receiver inventory, engine ticks and shared stand-ins. f_* cases dispatch to vr_framework_cases.lua. Clean requires no nlvr.* hook, callback, receiver or NLVR global. Existing V1 cases still run.

The wrist regression also asserts V1 clear RGBA and depth/stencil flags, preventing a moved canvas from blending its background twice.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.

Adds water/ladder movement stand-ins; client and server SetupMove tests reconstruct intended world motion while preserving gun pitch +/-45.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


options_no_format_write reproduces Derma numeric echoes and requires exact original spelling plus real edit propagation in stock and ULib modes.
