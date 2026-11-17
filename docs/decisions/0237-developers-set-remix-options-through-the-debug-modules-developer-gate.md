# 0237: Developers set Remix options through the debug module's developer gate

- Status: Proposed 2026-11-16, awaiting the user's approval before the merge
- Decided by: the agents, on the parent session's task ("Developer debug views can no longer be set from Lua, and that
  should be fixed without reopening what ADR 0234 closed"); the user approves the merge. Package only: the loader
  (`winmm.dll`) and `RTXFixesBinary` are not changed.
- Supersedes in part: [0234](0234-what-a-server-a-workshop-item-and-lua-may-reach.md), decision 1's sentence
  "developers use the debug module's `RTXDebug.Remix.SetConfig` in a local single-player game": it did not hold, and
  this decision says how it holds now. The rest of 0234 stands.
- Report: [debug-views-report.md](../handover/debug-views-report.md).

## Context

ADR 0234 made `RemixConfig.SetConfigVariable` (the RTX fixes' fifteenth native patch, `remix_option_policy.h`) take
only the options the RTX package's own Lua sets, because any server's client scripts and any add-on reach it. It sent
developers to the debug module for everything else. But the debug module's `RTXDebug.Remix.SetConfig` and
`SetDebugView` wrote through that same Lua function (`remix_debug.cpp`, `ApplyConfig`), whatever gate the call had
passed. Since 0234 they return nil and "Remix rejected the config value" for every option outside the list:
`rtx.debugView.debugViewIdx` (found on 2026-11-16 while investigating Linlong's hair in the user's game,
[linlong-pbr-tune-report.md](../handover/linlong-pbr-tune-report.md)) and the replacement switches the skill
`remix-map-pbr` points to for a stock-against-remaster check.

The debug module has two gates (its README, `session_policy.h`, `render_policy.h`):

- **The client rendering gate**: the module's client Lua state, the game thread, `RemixConfig` loaded. It is open in
  every RTX game, multiplayer included, and lets `rtx.*` writes through to `RemixConfig`.
- **The developer mutation gate** (`CanMutate`): the game thread, `-insecure` on the process command line, local
  single-player decided from the engine client itself (connected through the in-process loopback channel to a server
  with one player slot, no demo), and `sv_cheats 1`. It already opens `Lua.Eval` in any realm, memory writes, patches
  and detours. The RTX package stopped asking for `-insecure` in [0052](0052-scoped-rtx-multiplayer-bootstrap.md), so it
  is closed in an ordinary game.

## Decision

1. **`RemixConfig.SetConfigVariable` does not change**: its list holds for every Lua, the package's own included.
2. **Behind the developer gate the debug module writes `rtx.*` options through the Remix API itself** (its source
   patch 0004, module 0.2.2): the runtime's `d3d9.dll` exports `remixapi_InitializeLibrary`, which the module asks
   once, at its first such write, for an interface; it calls only `SetConfigVariable` and never `Startup` or
   `Shutdown`. It initializes with the headers `RTXFixesBinary` and RTX Water are built with (the patched fixes
   checkout's `public/include`, 0.1000.1), so the API version the runtime keeps for the process, which the most recent
   initialize sets, stays the one they asked for. Every `rtx.*` option goes this way behind the gate, not only debug
   views: 0234 promised developers the module for every option outside the list, and behind this gate the module
   already writes memory and runs Lua in any realm, so no Remix option widens what it reaches.
3. **Without the developer gate nothing changes**: the client rendering gate forwards `rtx.*` options to `RemixConfig`,
   whose list decides, and its refusal now names the developer gate. Names that are not `rtx.*` options are refused
   on both routes (the runtime's options are all `rtx.*`; `RemixConfig` has refused every other name since 0234).
   `Policy::RouteConfig` in the module's `render_policy.h` decides; `tests/render_policy_test.cpp` checks it composed
   with the session gate.
4. **A restore goes back the way its value went in**, even after the gate has closed (`Policy::RestoreThroughApi`):
   restoring undoes only the module's own change, to the value it recorded under the gate. The add-on's `ShutDown`
   hook restores everything at a map change, a disconnect and quit; at the module's close a value written through the
   API is restored through it even when `RTXFixesBinary` is already gone. `Remix.Overrides` and `SessionConfig` name
   each override's route (`remixconfig` or `remix_api`).

## Why this does not reopen what 0234 closed

- **A server**: the gate needs the client's own channel to be the engine's loopback. A remote server cannot make it
  so, even when it runs `sv_cheats 1` for a player launched with `-insecure` and tells its scripts they are in
  single-player; its client scripts keep `RemixConfig`'s list, through `RemixConfig` or through the module.
- **A Workshop item's Lua**: in an ordinary game, without `-insecure`, the gate is closed and an add-on reaches the
  list only. A player who adds `-insecure` and plays single-player with `sv_cheats 1` has opened developer mode, in
  which every add-on's Lua could already write memory and run Lua in the menu realm through this module; a Remix
  option is less than that.
- **A Remix mod's option layer** (0234's decision 2) is the runtime's and is not touched.

## Consequences

- Debug views and the other options outside the list need a local single-player game started with `-insecure`, and
  `sv_cheats 1` (an RTX start with `+map` has it; the New Game screen sets it to 0, so type `sv_cheats 1`). Adding
  `-insecure` to the field game's launch options is the user's call.
- A value a developer writes lands in the runtime's User layer, as `RemixConfig`'s values do: the Remix menu's "Save
  Settings" would keep it in `user.conf` while it lasts.
- One more caller of `remixapi_InitializeLibrary` in a developer session, with the same version as the two that
  already call it. If `RTXFixesBinary` moves to newer headers, the debug module moves with it (its `static_assert`
  names the version it was built for).
- The skills `mmd-remix-pbr` and `remix-map-pbr` say which gate debug views and the replacement switches need.
