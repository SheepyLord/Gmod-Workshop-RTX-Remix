# 0246: The DirectX level servers see

- Status: Accepted 2026-11-18 (the user's request of 2026-11-18: "Some servers uses render.GetDXLevel() to detect users
  using our addon which reject user with dx level lower than 90. As per our plan, apply fixes to allow players using our
  addon to join server like this." The plan is their R24 item 1.1 of 2026-11-08: "when joining servers, spoof the dx
  level of the game to avoid compatibility issues, let the server think the user is at the high dx level".)
- **Supersedes [ADR 0133](0133-the-multiplayer-notice-in-the-companion.md) §4** ("Not done: a different DirectX level
  for servers", declined by Claude then) and the matching sentence of
  [ADR 0135](0135-view-model-materials-and-arc9.md) §3. **Amends [ADR 0052](0052-scoped-rtx-multiplayer-bootstrap.md)**:
  in a client realm of an RTX start one global helper, `render.GetDXLevel`, changes, and the RTX client module runs the
  companion's verified prelude scripts there before `includes/init.lua`.
- Package only: the companion (`lua/nativeloader/prelude/dxlevel.lua`, the render guard's fallback) and the RTX client
  module (`gmsv_nlrtxclient_win64.dll`, the fixes part, built from `loader/client`). No `winmm.dll` change: the user
  rejected loader changes (2026-11-17).

## Context

Measured in the PoC (RESEARCH.md, "The DirectX level servers see"):

| Start | `render.GetDXLevel()` | `mat_dxlevel`, `GetConVarNumber`, `cvars.Number` | `SupportsPixelShaders_2_0`, `_1_4`, `SupportsVertexShaders_2_0` |
|---|---|---|---|
| RTX (the package's `-dxlevel 90`), single-player or a listen server | 80 | 90 | false |
| Without RTX, `-dxlevel 90` | 90 | 90 | true |
| Without RTX | 95 | 95 | true |

- **Why 80.** The runtime offers Source no shaders (`d3d9.shaderModel = 0`): Source loads only `stdshader_dx6`/`dx7` and
  draws fixed-function, which Remix path traces. With shaders Remix gets draws it cannot path trace (M4's PoC-only
  `shaderModel=3` layer: "not path-traced"). The real level cannot rise without losing the path tracer.
- **The servers.** A server that asks a client for `render.GetDXLevel()` (a net message, or the client's report at
  `InitPostEntity`) and refuses below 90 refused every RTX player: in the PoC a scratch server of that kind gave the
  verdict "reject level=80" to the RTX listen host (its kick only printed "Preventing kick of local server host!": GMod
  keeps a listen server's host). Such checks are meant for DirectX 8 players.
- **When a server's Lua runs.** On a remote server the client realm runs the server's copy of `includes/init.lua`, then
  its autoruns and gamemode. The loader's early view is a local file's view and never reaches it (C13's dedicated
  server: `installation="verified multiplayer bootstrap"`, early flag false); the verified bootstrap runs only once the
  realm has a gamemode and a valid local player, after `InitPostEntity`. A check at `InitPostEntity`, at autorun time or
  through a reference taken at load would see 80 under a late override.

## Decision

1. **What `render.GetDXLevel()` answers.** In a client realm of an RTX start, in a multiplayer game
   (`game.SinglePlayer()` false), it answers `mat_dxlevel`, the level the game was started at, when that is higher than
   the engine's level: whole levels, never lower than the engine. The engine's level is never above `mat_dxlevel`, so in
   a multiplayer game Lua that calls `render.GetDXLevel()` and Lua that reads the convar (`GetConVar("mat_dxlevel")`,
   `GetConVarNumber`, `cvars.Number`) agree (the user's note of 2026-11-18). With the package's launch arguments that is
   90, what the same game answers without RTX at those arguments. Single-player answers the engine's level as before.
   `mat_dxlevel` and the convar routes already read 90 and are not touched.
2. **A switch.** `nativeloader_multiplayer_dxlevel` (a client setting the game saves; default 1): 0 gives the engine's
   answer everywhere. Read at every call.
3. **Nothing hidden.** `render.GetDXLevel` is a plain Lua function of `lua/nativeloader/prelude/dxlevel.lua`
   (`debug.getinfo` names it), and the global `NativeLoaderDXLevel` says what it does and gives the engine's own level
   (`real()`) to any Lua, a server's included: a server that wants to refuse RTX players can still tell. No trick hides
   the override. The package's own code reads `NativeLoaderDXLevel.real()`; none reads the level today.
4. **Before any server's Lua.** The RTX client module (loaded in the menu realm at menu start of every RTX start, ADR
   0052) hooks `ILuaInterface::FindAndRunScript` once per process through the menu state's vtable, which every Lua state
   shares (client.dll starts a realm with `call [vtable+0x308]` and `"includes/init.lua"`). Only where sure: that call
   found in the loaded `client.dll` (`lea rdx` naming the file, then `call [reg+0x308]` within 64 bytes), so the slot is
   the one that starts a realm in this build and takes exactly FindAndRunScript's arguments; the vtable in
   `lua_shared.dll`'s data, its IsClient, FindAndRunScript and RunStringEx slots in that module's code. Otherwise
   nothing changes, the status line says why, and the fallback (5) applies. Before the engine runs a client realm's
   `includes/init.lua`, the companion's verified `lua/nativeloader/prelude/*.lua` run there (the catalog's bytes, as for
   the menu scripts of ADR 0133; no other source, no new Lua API), with the raw global `__NATIVELOADER_CLIENT_PRELUDE`
   while they run. Every other call passes straight to the engine.
5. **A fallback.** Where the module did not run the prelude, the render guard includes it in its own route: early in a
   local game, after the server's autoruns on a remote one.
6. **Not changed:** the engine's real level and everything Source renders; `render.SupportsPixelShaders_2_0`,
   `SupportsPixelShaders_1_4` and `SupportsVertexShaders_2_0` (capabilities, false under RTX: an add-on that reads them
   picks its fixed-function path as before); ARC9's patch (ADR 0135), which answers its own check in single-player too.
7. **The console** (the user's note of 2026-11-18: the level shows in Lua through `render.GetDXLevel()` and in the
   console through `mat_dxlevel` and `mat_info`). Typing `mat_dxlevel` prints `"mat_dxlevel" = "90"` in an RTX start,
   the same as what Lua now answers in a multiplayer game. `mat_info` prints the material system's hardware
   configuration, the engine's real state: `m_nDXSupportLevel: 80`, vertex and pixel shader version 0.0, every
   `m_Supports*Shaders*` no (without RTX: 95, 3.0, yes). It stays so. A server's Lua cannot read the console. Making
   `mat_info` print 90 would take one of two things: changing the hardware configuration Source reads its level from,
   which is the level Source draws at (shader draws Remix does not path trace, as raising the real level above), or
   rewriting the command's printout (the engine guard could take the `mat_info` command over as it takes `poster`, ADR
   0226), which would show the player numbers the engine does not use and change nothing for any server. Neither is
   done.

## Why the earlier decline is superseded

ADR 0133 §4 declined this as hiding the client from a server's rule. The user decided otherwise, twice. The shape keeps
what that concern was about within reach of server owners: the value reported is the session's own setting (the game is
started at DirectX level 90, its hardware supports 95; only the renderer RTX needs keeps Source at fixed-function), the
override is visible and documented (`NativeLoaderDXLevel`, the changelog, which is the Workshop change note), and the
player can switch it off. It does not lift any other check, and the multiplayer notice (ADR 0133) still says that a
server's rules and a kick or ban are the player's own risk.

## Considered and not done

- **Raising Source's real level** (shader model 2 or 3 in the runtime): Source would draw with shaders, which Remix
  does not path trace (M4).
- **A constant 95**: not the session's setting and unlike its `mat_dxlevel` (90); `mat_dxlevel` is what the same game
  answers without RTX.
- **Changing `render.Supports*`**: those are capabilities with no setting behind them; claiming shaders would send
  add-ons down shader paths that do not draw under RTX.
- **Only the render guard (Lua)**: on a remote server it installs after the server's autoruns and after
  `InitPostEntity`, too late for the usual checks.
- **The loader's early view for remote servers, or any loader change**: the user rejected loader changes; the client
  module is a package binary.
- **Hiding the override** (a C function, a native detour of the engine's function, spoofing `debug.getinfo`): not done
  by design.

## Consequences

- Players of the RTX package pass a server's check that refuses `render.GetDXLevel()` below 90, whatever the check's
  timing (autorun, `InitPostEntity`, a reference taken at load, a later request): measured on a listen server; on a
  remote server the same `includes/init.lua` call starts the realm (one call site in `client.dll`), not tested there.
  Servers that check `render.Supports*` still refuse them.
- In a multiplayer game other add-ons that read `render.GetDXLevel()` see 90 as well. Source's own drawing is unchanged;
  an add-on that would pick a shader path from the level gets the inert or fixed-function result the render guard already
  handles (ADR 0086).
- A server's Lua can read `NativeLoaderDXLevel` and can set the client's switch like any client setting.
- The RTX client module's status line and `NativeLoaderRTXClient.Status()` (`prelude`, `prelude_runs`) say whether the
  prelude is hooked and how many client realms it ran in.
