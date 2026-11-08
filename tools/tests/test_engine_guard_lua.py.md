# test_engine_guard_lua.py

Unit tests (R23, [ADR 0130](../../docs/decisions/0130-an-engine-guard-for-lua-start-up.md)) that run
the companion's real `!!!!nativeloader_engine_guard.lua` under LuaJIT through
[engine_guard_harness.lua](engine_guard_harness.lua.md), one scenario per run.

```powershell
cd tools; python -m unittest tests.test_engine_guard_lua
```

- `off`: no module without this machine's RTX start (an inactive report; a 0.14.0+ report without the
  session marker); a 0.13.0 report alone, or the marker alone, is one.
- `client` / `server`: the client realm sets the translated message and keeps the words in DATA, not
  rewriting them when unchanged; the server realm sets the kept words; Initialize and the first tick
  both end the watch.
- `already-loaded` / `no-module`: the early view's module is used as it is; without the module nothing
  else happens.
- `recovered`: a start that was reported and went on removes the report.
- `notice`: the next start names the add-on (a mounted Workshop add-on, a legacy folder, or the path
  alone) in a 30-second notice after eight seconds, once per report, and logs it in English.

Skipped without LuaJIT. Exit code 0 when every test passes. No side effects.
