# test_load_callbacks.py

Load speed-up round 3, item D2 ([ADR 0241](../../docs/decisions/0241-the-load-overlay-names-the-slowest-lua-callbacks.md)):
the hooks, timers and net receivers of a map load timed, the slowest named and written for the load overlay's end
line, the originals put back.

- `LoadCallbackTests` runs [`load_callbacks_harness.lua`](load_callbacks_harness.lua.md) with LuaJIT once per scenario
  (`client`, `server`, `off`); skipped without LuaJIT.
- `LoadCallbackSourceTests` reads the add-on's autorun: it sends the file to clients and includes it before the ARC9
  file, so that it times the other add-ons' callbacks from their start.

```powershell
python -m unittest tests.test_load_callbacks      # from tools\
```

Touches no game; writes nothing. Exit 0 on pass.
