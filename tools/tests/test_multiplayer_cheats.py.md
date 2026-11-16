# test_multiplayer_cheats.py

The repository review of 2026-11-16, finding 16
([ADR 0234](../../docs/decisions/0234-what-a-server-a-workshop-item-and-lua-may-reach.md)): a multiplayer game started
with RTX outside the New Game screen gets `sv_cheats 0`. GMod blocks `sv_cheats` for `RunConsoleCommand` and
`game.ConsoleCommand` in a game's realms, so the server realm writes a request to the data folder and the companion's
menu script [`multiplayer_cheats.lua`](../../companion/nativeloader/lua/nativeloader/menu/multiplayer_cheats.lua.md)
carries it out.

```powershell
cd tools; python -m unittest tests.test_multiplayer_cheats
```

| Test | Checks |
|---|---|
| it runs only in the menu realm and once | the script's first statement returns outside the menu realm or when it already ran |
| the server asks through the data folder, not a blocked command | the engine guard autorun writes the time to `nativeloader_companion/cheats_off.txt` and runs no `sv_cheats` command; the script reads that file |
| the guard knows the file as the package's own | `_nativeloader_guard.lua` lists `lua/nativeloader/menu/multiplayer_cheats.lua` |
| a fresh request in a running game, a request waits for the game to load, stale, future and unreadable requests are dropped, only in the menu realm and once | [`multiplayer_cheats_harness.lua`](multiplayer_cheats_harness.lua.md)'s scenarios (skipped without LuaJIT) |

The server realm's side is also in [`test_engine_guard_lua.py`](test_engine_guard_lua.py.md) (`cheats`). Exit 0 when
every test passes.
