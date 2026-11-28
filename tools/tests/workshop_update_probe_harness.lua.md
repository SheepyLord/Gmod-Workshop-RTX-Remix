# workshop_update_probe_harness.lua

Invokes WU's shipped QA client probe and pose helper under LuaJIT with in-memory entities, rendering frames, a duplicator modifier, Sandbox save files, command callbacks, clock and screenshot acknowledgements. Runs v1 and v2 against the same simulated disk.

```powershell
luajit tools/tests/workshop_update_probe_harness.lua tools/qa good
```

`good` restores in place. `reset_realm` exercises the resume marker and the second screenshot acknowledgement across a Lua restart. `wrong_head`, `old_player`, `duplicate`, `stale_pose` and `no_paste` require the probe to reject, respectively, an old head measurement, a stale player selection, two library rows, a palette from the previous frame or a save that never pastes the marked Citizen.

Inputs are the QA directory and scenario name. Prints the probe's JSON and markers to stdout. It writes no game files. Exit 0 means the probe reached its expected verdict. [Python test](test_workshop_update_session.py.md)
