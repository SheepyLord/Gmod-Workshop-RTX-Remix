# vr_move_tests.py

Task L's offline LuaJIT scenarios, using the actual movement modules and F's independent
vector/wire stand-ins. Run `python -m unittest discover -s companion/tests -p vr_move_tests.py -v`.
Requires LuaJIT; missing LuaJIT skips the scenarios. No game, OpenVR, files outside the repository,
or other processes are touched. Each scenario runs a fresh Lua process; stdout includes measured
values. Covers arcs, standing destinations/refusals, room follow and steps, network bounds,
turn pivots, stick direction and mirroring, crouch, jump/sprint, noclip, calibration, vignette,
blink/shift, changing obstacles, tracking loss, claims and teardown. Exit 0 passes; unittest
uses nonzero for failure. Q can import `VRMoveTests` into the tools-only gate at integration;
this task's allowed paths exclude that gate's discovery bridge.

Integration adds debug_reuse, bringing the suite to 49 scenarios.

Q integration now includes 50 scenarios.

Q adds coalesced_motion; 51 scenarios.

Q now has 52 scenarios including render_time_motor.


Review regressions cover overlay lifetimes/budgets, walking world velocity and prediction, light-body stability and impulses, safe proxy spawning, teleport carry, delayed climbing, borrowed-menu errors, pause/stale-FOLLOW recovery, unchanged corpse settings, wrist Exit and cached refresh. The Python suite retains the corresponding Lua cases in the normal repository gate; tests use stand-ins without SteamVR or game settings writes.


Includes the same-frame render-hand motor coherence regression in addition to the 3 m pause/rebaseline and stale FOLLOW cases.


Includes q4s_medium_head_rule in normal discovery.

Registers q5_noclip_underwater in the real move/core harness.

Registers the real ladder overlay/movement pipeline regression.

Registers motor_cadence_kept_across_reset, motor_buffer_change_without_hold and motor_buffer_alternating_gaps_hold (ADR 0196).
