# vr_combined_clock_cases.lua

Offline regression for the combined functional fixture's game clock and replay. Run through
`test_vr_combined.py`, or LuaJIT with the repository root argument. A 2.54-second capture stall
must not skip a toggle; intentional menu pauses still advance tracking. Raw native time and
clock restoration are checked. No game, files or runtime are changed; assertion failure exits nonzero.

Also checks native analogue/skeleton descriptors and a whole-session physical throw replay at 120 u/s and 1.16 rad/s.
