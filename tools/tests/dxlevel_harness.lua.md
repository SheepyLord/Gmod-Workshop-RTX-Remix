# dxlevel_harness.lua

Runs the companion's [`nativeloader/prelude/dxlevel.lua`](../../companion/nativeloader/lua/nativeloader/prelude/dxlevel.lua.md)
([ADR 0246](../../docs/decisions/0246-the-directx-level-servers-see.md)) under LuaJIT in a stand-in client realm that
has only what the engine registers before `includes/init.lua`: `render.GetDXLevel` (80), `game.SinglePlayer`,
`GetConVar_Internal` (or `util.lua`'s `GetConVar` in the `guard_route` scenario), `CreateConVar`, `FindMetaTable("ConVar")`
and `mat_dxlevel` (90). Then it checks what `render.GetDXLevel()` answers.

```powershell
luajit tools\tests\dxlevel_harness.lua companion\nativeloader\lua\nativeloader\prelude\dxlevel.lua multiplayer
```

| Scenario | Checks |
|---|---|
| `multiplayer` | 90 in a multiplayer game; `NativeLoaderDXLevel` (`real` the engine's function, `reported` the new one, `installation` "prelude"); the switch made once, archived (128), default 1, with help text; the function is this file's Lua; switch off 80, on 90; single-player 80; a reference taken after the install reports 90; later replacements of `game.SinglePlayer` and `ConVar:GetBool` change nothing |
| `guard_route` | the same after `includes/init.lua` (the render guard's route): `installation` "guard" |
| `server_metatable` | the same with a `__newindex` on `_G` that errors (server Lua on a remote server) |
| `single_player` | 80 |
| `never_lower`, `highest` | an engine level above `mat_dxlevel` stays; the player's own `-dxlevel 81` is reported; never below the engine; at most 95, whole levels |
| `bad_values`, `missing_dxlevel`, `switch_error` | an unreadable or missing `mat_dxlevel`, or a switch that raises an error when read, keeps the engine's level without an error; an engine answer that is not a number passes through |
| `idempotent` | a second run changes nothing and makes no second switch |
| `realm_server`, `realm_menu`, `missing_functions` | nothing changes and nothing is published |

Arguments: the file, the scenario. Prints `PASS <scenario>`; an assertion failure exits non-zero. No game, file or
network. Run by [`test_multiplayer_dxlevel.py`](test_multiplayer_dxlevel.py.md).
