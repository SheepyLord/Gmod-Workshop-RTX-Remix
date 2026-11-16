# multiplayer_cheats.lua

The repository review of 2026-11-16, finding 16
([ADR 0234](../../../../../docs/decisions/0234-what-a-server-a-workshop-item-and-lua-may-reach.md)): cheats off in a
multiplayer game started with RTX.

- **Why here.** An RTX start's session turns `sv_cheats` on for its rendering settings (the loader's session
  variables, from the fixes' `autoexec.cfg`). GMod's New Game screen turns it off for the games it starts, from the menu
  realm; a multiplayer game started another way (`+maxplayers 8 +map ...` on the command line, the console) kept it,
  so every player who joined a listen server had cheats. GMod blocks `sv_cheats` for `RunConsoleCommand` and
  `game.ConsoleCommand` in the client and server realms ("Command is blocked!", PoC 2026-11-16), and a cfg run with
  `exec` from an add-on folder is not found; the menu realm may run it.
- **How.** The server realm of a game that is not single-player and has more than one slot, in an RTX start with
  `sv_cheats` on, writes the time (`os.time()`) to `data/nativeloader_companion/cheats_off.txt`
  ([`!!!!nativeloader_engine_guard.lua`](../../autorun/!!!!nativeloader_engine_guard.lua.md)). This script, run once in
  the menu realm by the RTX client module like the companion's other menu scripts, looks for that file once a second:
  a request older than five minutes (or more than a minute in the future), or one that cannot be read, is deleted
  unused; while the game is still loading (`IsInGame()` false) it waits; then it deletes the request, runs
  `sv_cheats 0` and prints one console line. Turning cheats off resets the cheat-protected settings to their defaults,
  as a New Game start does.
- **Who else can write the request.** Any realm's Lua can write `data/`; connected to another machine's server,
  `sv_cheats 0` from the client changes nothing (only the server sets its replicated value), and turning cheats off is
  the safe direction anyway.
- **Once.** `NativeLoaderMultiplayerCheats` marks it loaded; the timer is `NativeLoaderMultiplayerCheats`.

Tested by [`tools/tests/test_multiplayer_cheats.py`](../../../../../tools/tests/test_multiplayer_cheats.py.md) (LuaJIT
harness) and in the PoC in a two-slot listen game.
