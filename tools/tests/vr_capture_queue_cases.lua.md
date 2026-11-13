# vr_capture_queue_cases.lua

LuaJIT regression for tools/vr_capture_queue.lua. Argument: repository root. Injects clocks, source
inventory and a fake native callback; tests newly visible targets, one request per frame, hidden
retirement, native refusal, timeout and teardown. No game, file writes or SDK. Exit 0 prints PASS;
a failed invariant exits nonzero. Launched from test_vr_combined.py in the normal gate.
