# test_workshop_update_session.py

The driver also runs end to end against mocked game subprocesses. Both a passing run and a
failed v2 measurement must pass the recorded v1 selector, keep the save and complete rollback.

Offline tests for the [two-launch WU driver](../qa/workshop_update_session.py.md). Run from the worktree.

```powershell
python -I tools/tests/test_workshop_update_session.py -v
```

Runs the two actual Lua probes through the [LuaJIT harness](workshop_update_probe_harness.lua.md) and passes their output through the driver's verifier. Checks the encoded console line lengths, screenshot ordinals, v1 selector argument, false-positive rejection, matching raw and packet sizes for both Helena whitespace variants, and restoration of a pre-existing Sandbox save folder. Temporary files stay in `out/tmp`. Requires Windows for the session tooling and LuaJIT for the game-probe scenarios. Exit 0 on success, nonzero on failure.
