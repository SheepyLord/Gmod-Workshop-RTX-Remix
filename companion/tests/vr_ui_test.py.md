# vr_ui_test.py

Run `python -m unittest discover -s companion/tests -p vr_ui_test.py -v`. Uses the existing LuaJIT resolver, each production-module case in a fresh subprocess. No game, headset or Python packages required. This prefix does not match the older tools gate's test_vr import; run this command alongside Release. Inputs: Lua sources/stand-ins. Outputs: unittest results only, no writes. Exit 0 on pass, nonzero on failures; absent LuaJIT skips explicitly.
# Follow-up

Runs 29 LuaJIT scenarios plus the no-Pillow preflight (30 total), including fallback layout/editing and
native-window dispatch routing. C++ Win32 stand-in coverage is in `vr/native/tests/test_window_input.cpp`.

Q adds module_debug, bringing the UI/preflight suite to 31 cases.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Runs verify_background_drag_cursor as a retained failing-before/passing-after regression.

Also runs verify_background_drag_events.
