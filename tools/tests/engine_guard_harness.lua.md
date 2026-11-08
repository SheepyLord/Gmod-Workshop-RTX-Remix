# engine_guard_harness.lua

LuaJIT harness for the companion's `lua/autorun/!!!!nativeloader_engine_guard.lua` (R23,
[ADR 0130](../../docs/decisions/0130-an-engine-guard-for-lua-start-up.md)). Invoked by
[test_engine_guard_lua.py](test_engine_guard_lua.py.md):
`luajit engine_guard_harness.lua REPO SCENARIO`.

Mocks DATA (`file.Read/Write/Exists/Find/Delete`), the loader's `status.json` and session marker, the
`nlengineguard` module (`require`, `SetMessage`, `StartupDone`), `include` of the i18n and notice
modules, `util` JSON, hooks, ordered timers, `engine.GetAddons` with per-add-on file lookups and
legacy add-on folders. Each boot reloads the autorun with fresh locals for one realm while DATA
persists, as a new map or a new start does.

Scenarios: `off`, `client`, `server`, `already-loaded`, `no-module`, `recovered`, `notice` (see the
test's `.md`). Prints `PASS <scenario>` and exits 0, or raises an assertion error. No side effects.
