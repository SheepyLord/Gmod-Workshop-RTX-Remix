# vr_v4_test.py

Runs nine real-framework scenarios and 24 engine stand-in contracts in LuaJIT subprocesses. Use `python -m unittest discover -s companion/tests -p vr_v4_test.py -q`; tools/tests/test_companion_vr_scaffold.py exposes the same 33 cases to the Release gate and prints their count. Reads production Lua and harness files, changes only subprocess state, no game/OpenVR or network. Missing LuaJIT is a named availability skip; a failing assertion/process is a test failure. Exit 0 for unittest success, nonzero for failures.
