# dxlevel.lua

[ADR 0246](../../../../../docs/decisions/0246-the-directx-level-servers-see.md): the DirectX level a server sees from an
RTX start. The user's request of 2026-11-18 (first asked as R24's item 1.1 on 2026-11-08, declined then by
[ADR 0133](../../../../../docs/decisions/0133-the-multiplayer-notice-in-the-companion.md) §4): servers that refuse
clients whose `render.GetDXLevel()` is below 90 refused every player of this package.

## Why the level is 80

The runtime offers Source no shaders (`d3d9.shaderModel = 0`), so Source loads only its DirectX 6 and 7 shader DLLs and
draws with fixed-function shaders, which RTX Remix can path trace; `render.GetDXLevel()` (the engine's DirectX support
level) answers 80. The game is started at `-dxlevel 90` (the package's launch arguments), so `mat_dxlevel`,
`GetConVarNumber("mat_dxlevel")` and `cvars.Number("mat_dxlevel")` read 90. Without RTX the same game answers 90 at
`-dxlevel 90` and 95 without it. Raising Source's real level would hand Remix shader draws it cannot path trace
(RESEARCH.md: M4's PoC-only `shaderModel=3` layer was not path traced).

## What it does

- In the client realm of an RTX start, `render.GetDXLevel` becomes a Lua function of this file. In a multiplayer game
  (`game.SinglePlayer()` false) with the switch on, it answers `mat_dxlevel`, the level the game was started at, when
  that is higher than the engine's answer, at most 95 and in whole levels. Otherwise, and in single-player, it answers
  the engine's level. It never answers lower than the engine.
- **The switch**: `nativeloader_multiplayer_dxlevel` (a client setting the game saves, `FCVAR_ARCHIVE`, default `1`); `0`
  gives the engine's own answer everywhere. Read at each call.
- **Nothing is hidden**: the global `NativeLoaderDXLevel` = `{version = 1, installation = "prelude" | "guard", switch =
  "nativeloader_multiplayer_dxlevel", highest = 95, real = <the engine's render.GetDXLevel>, reported = <this
  function>}` is readable by any Lua, a server's included, and `debug.getinfo(render.GetDXLevel)` names this file. The
  package's own code reads the engine's level with `NativeLoaderDXLevel.real()`.
- Not changed: `render.SupportsPixelShaders_2_0`, `render.SupportsVertexShaders_2_0`, `render.SupportsPixelShaders_1_4`
  (false under RTX: Source has no shaders there) and `render.SupportsHDR` (GMod's Lua, true from level 80).
- The engine's functions it uses (`render.GetDXLevel`, `game.SinglePlayer`, the `ConVar` methods) are taken when it
  runs, so later replacements by other Lua do not change what it reads.

## When it runs

- **`installation = "prelude"`**: the RTX client module (`loader/client/prelude.h`, the package's
  `gmsv_nlrtxclient_win64.dll`) runs the companion's verified `lua/nativeloader/prelude/*.lua` in each client realm
  right before the engine runs that realm's `includes/init.lua`, local and remote, so before any Lua a server sends.
  The raw global `__NATIVELOADER_CLIENT_PRELUDE` is true while it runs. At that point only the engine's C functions
  exist: it uses `GetConVar_Internal`, `CreateConVar` and the number 128 for `FCVAR_ARCHIVE`, not `util.lua`'s helpers.
- **`installation = "guard"`**: where the module did not run it (it could not hook the engine), the render guard
  ([`_nativeloader_guard.lua`](../../autorun/_nativeloader_guard.lua.md)) includes it: early in a local game, after the
  server's autoruns on a remote one (the verified multiplayer bootstrap's late route).
- Client realm only (`SERVER` or `MENU_DLL` return at once), once per realm (an existing `NativeLoaderDXLevel` table
  returns at once). Globals are read and written raw: metamethods a server set on `_G` do not stop it.

## Inputs, outputs, side effects

Reads `mat_dxlevel` and its switch; creates the switch; replaces `render.GetDXLevel` and publishes
`NativeLoaderDXLevel` in that realm. No file, network or native call. No exit code (a Lua file).

Tested by [`tools/tests/test_multiplayer_dxlevel.py`](../../../../../tools/tests/test_multiplayer_dxlevel.py.md)
(LuaJIT, [`dxlevel_harness.lua`](../../../../../tools/tests/dxlevel_harness.lua.md)); the guard's route by
[`test_render_guard.py`](../../../../../tools/tests/test_render_guard.py.md); the module's hook by
`loader/client/tests/test_prelude.cpp`.
