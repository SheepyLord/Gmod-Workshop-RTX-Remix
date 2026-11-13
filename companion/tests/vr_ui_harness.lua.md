# vr_ui_harness.lua

Usage: luajit companion/tests/vr_ui_harness.lua REPO SCENARIO; normally through vr_ui_test.py. Runs production UI modules using F's independent Euler/vector stand-ins and bounded VGUI/native fakes. Covers pixels, claims/capture/restoration, keyboard lifetime, panel transforms/borrow restoration, wrist actions and flat fallback/cleanup. No game, OpenVR, file writes or settings changes. Prints PASS and exits 0; assertion failure is nonzero.
# Follow-up

Adds owned native-window dispatch isolation, Unicode caret editing, fallback lifecycle and a laser-hit
keyboard layout test. The actual merged central keyboard reservation is asserted; the harness supplies no local size fallback.

Integration page test checks calibration restart notice appears and clears with calibration.restart.
The page case now expects 18 option controls, including V4's four weapon settings. Production overlay reservations are read centrally; canvas behavior remains covered.

The wrist case verifies 100 repeated Inventory calls retain list/row identity.

module_debug runs the actual UI module for 100 frames and verifies the complete debug/list/row
producer retains identity; fallback typing also checks keyboard inventory identity.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


The UI stand-in exposes FrameNumber from its controlled clock so deferred native image repaint uses the same game-frame contract as the framework.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

verify_background_drag_cursor resets desktop input to (0,0) between injected movement and a stock-style control CursorPos read. The controller point must continue moving; Close restores a prior instance method, removes an inherited-method override and preserves a later third-party replacement.

verify_background_drag_events covers missing native movement callbacks after a successful press, a moving controller, unchanged-pixel suppression, delivered-native-callback de-duplication and method restoration.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.
