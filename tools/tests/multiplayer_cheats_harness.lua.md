# multiplayer_cheats_harness.lua

LuaJIT harness for the companion's menu script
[`multiplayer_cheats.lua`](../../companion/nativeloader/lua/nativeloader/menu/multiplayer_cheats.lua.md) (the
repository review of 2026-11-16, finding 16). It runs the real script against mocked menu-realm globals: the data
folder (`file.Exists`, `Read`, `Delete`), `timer.Create`, `IsInGame`, `RunConsoleCommand`, `print` and `os.time`.

```powershell
luajit tools\tests\multiplayer_cheats_harness.lua <repository root> <scenario>
```

| Scenario | Checks |
|---|---|
| `fresh` | one timer a second; nothing without a request; a request a few seconds old in a running game runs `sv_cheats 0` once, deletes the request and prints one line |
| `loading` | while the game loads the request waits and is kept; once the game runs it is carried out |
| `stale` | a request older than five minutes, one more than a minute in the future and one that is not a time are deleted unused, also while no game runs |
| `realm` | outside the menu realm nothing loads; loaded twice, one timer |

Prints `PASS <scenario>` and exits 0, or stops with the failed check (exit 1). Run by
[`test_multiplayer_cheats.py`](test_multiplayer_cheats.py.md).
