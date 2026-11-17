# Debug views through the debug module's developer gate (report)

Claude, 2026-11-16, on the branch `claude/suspicious-jennings-845d66`, package only (the loader and `RTXFixesBinary`
are not changed). Decision: [ADR 0237](../decisions/0237-developers-set-remix-options-through-the-debug-modules-developer-gate.md),
which supersedes in part [ADR 0234](../decisions/0234-what-a-server-a-workshop-item-and-lua-may-reach.md).

## What was wrong

Found on 2026-11-16 while investigating Linlong's hair ([linlong-pbr-tune-report.md](linlong-pbr-tune-report.md)):
`RTXDebug.Remix.SetDebugView` returned nil and "Remix rejected the config value", and the view did not change. Since
the repository review's fixes (ADR 0234, the RTX fixes' fifteenth native patch `lua-guards`),
`RemixConfig.SetConfigVariable` takes only the options the RTX package's own Lua sets, and the debug module wrote every
option through that Lua function (`remix_debug.cpp`, `ApplyConfig`), whatever gate the call had passed. So ADR 0234's
note that developers use `RTXDebug.Remix.SetConfig` held for no option outside the list: debug views, and the
replacement switches the skill `remix-map-pbr` sends agents to the module for.

## What changed

- **The debug module 0.2.2** (its source patch 0004, `packages/fixes/licenses/rtxdebug/0004-Write-Remix-options-through-the-Remix-API-behind-the.patch`,
  commit `4fa8ab6d` on the scratch clone's `debug-view-gate`, made from the user's clone in
  `E:\Modding_Backup\garrys-mod-rtx-remixed\source\debug` by `git clone --shared`; nothing committed there or pushed):
  - `source/render_policy.h`: `Policy::RouteConfig(fullMutation, rendering, key)` says where a write goes:
    `RemixApi` behind the developer gate, `RemixConfig` under the client rendering gate alone, `Refused` without
    either or for a name that is not an `rtx.*` option. `Policy::RestoreThroughApi` keeps a restore on its value's
    route.
  - `source/remix/remix_debug.cpp`: behind the gate the module takes `remixapi_InitializeLibrary` from `d3d9.dll`
    once, at its first such write, with its own headers' version (0.1000.1, those `RTXFixesBinary` and RTX Water use,
    so the runtime's process-wide version does not change), and calls only `SetConfigVariable` on it. The ledger
    records each override's route; `RestoreConfig`, `RestoreAll` and the module's close restore through it (an API
    value even when `RTXFixesBinary` has already closed). `Overrides` and `SessionConfig` give the `route`
    (`remix_api` or `remixconfig`). `RemixConfig`'s refusal message now names the developer gate.
  - `source/module.cpp` 0.2.2; `remix_debug.h`, `session_policy.h` comments; the module's README and the `.md` notes.
  - `tests/render_policy_test.cpp`: the route composed with the session gate (the regression).
- **This repository:** the new module in `packages/fixes/modules` (430,592 bytes, SHA-256 `29b11689...`, xz 172,152
  bytes in Git LFS), `provenance.json` (the fourth patch, the source commit, every changed file's hash, the build),
  `Source.md`, `tools/ci/pins.json` (`rtxdebug.commit`), the gate test
  [`test_rtxdebug.py`](../../tools/tests/test_rtxdebug.py.md), the QA probe
  [`tools/qa/debug_view_probe.lua`](../../tools/qa/debug_view_probe.lua.md), the skills `mmd-remix-pbr` (both copies)
  and `remix-map-pbr`, and the shared docs.

`RemixConfig` itself is unchanged: its list still holds for every Lua, the package's own included.

## Build

`tools\ci\build_modules.ps1 -Only rtxdebug -Work R:\work -Out R:\built -GmodCommon
E:\Modding_Backup\garrys-mod-rtx-remixed\garrysmod_common -Premake out\debug-multiplayer-tools\premake-beta2\premake5.exe`,
with `R:` a `subst` alias of the main checkout's `out\dbgv` (removed afterwards) and `R:\work\fixes` a sparse
`--shared` checkout of the fixes' `/public/` at the pinned base. Without the alias the script's `!`-path branch fails
when garrysmod_common is on another drive (RESEARCH.md, "Debug views through the debug module's developer gate"). The
only warning in the module's own project is the old `INVALID_HANDLE_VALUE` redefinition in `detours.cpp`.

## Tests

- **The regression, offline:** `render_policy_test.cpp` passes with `/W4 /WX`; a copy of the policy whose route sends
  every write to `RemixConfig` (0.2.1's behaviour) fails six checks, the developer-gate ones; a copy that sends every
  write to the API fails six, the `RemixConfig` ones (a remote insecure server with `sv_cheats 1`, a local game without
  `-insecure`, one with `sv_cheats 0`).
- **`test_rtxdebug.py`** (8 tests): the checkout against `provenance.json`, the four patches as one chain from the base
  to the pinned commit, every patched file the last patch's post-image (git object ids), the stored module the recorded
  build, the module's wiring of the route, and the two C++ regressions compiled and run. Applying the four patches to
  the base `ff009d71` in a scratch worktree also reproduced all 37 checkout files byte for byte.
- **In the PoC** (2026-11-16, loader 0.16.0 already installed there, the package built from this branch, evidence in
  this worktree's `out\dbgview\evidence`): gm_construct, single-player, a pinned camera, noon with the clock stopped,
  [`debug_view_probe.lua`](../../tools/qa/debug_view_probe.lua.md):
  - **With `-insecure`** (`a-developer-gate`): `can_mutate` true, `sv_cheats` true, version 0.2.2;
    `RemixConfig.SetConfigVariable` returned false; `SetDebugView(23, 0)` true on the `remix_api` route; the albedo
    `jpeg` differed from view 0 by 56.7/255 per pixel (55.3 on 32-pixel blocks; the window captures the same);
    `RestoreConfig` true, the next capture 1.0/255 from the first (0.3 on blocks).
  - **Without `-insecure`** (`b-ordinary-game`): `can_mutate` false; `SetDebugView` returned nil and "RemixConfig
    refused the option or its value (the console says why); options outside its list need the developer gate: local
    single-player, sv_cheats 1 and -insecure"; the three captures within 1.0/255.
  - Both quit normally (exit 0) and wrote the field's settings back. The PoC's `config.json` was put back byte for byte
    (SHA-256 `b730e681...`), the six JPEGs removed from its `screenshots` folder, the lock released.
- **The Release gate** on the branch: see the commit's message and the session's notes.

## Not checked

- A multiplayer server: covered by the route's regression (a remote server cannot make the client's channel loopback)
  and the 0.2.1 gate, not by a game.
- The field game: it needs `-insecure` in its launch options for the gate, which is the user's call.
- A module close with an API override still recorded (the add-on's `ShutDown` hook restores everything first).
- GitHub's package workflow, which builds the module from `checkout/` the same way, for a release.

## Leftovers

- `out\dbgv` in the main checkout (the build's work folder: the fixes' sparse checkout, the module's build tree, the
  logs) and `out\dbgview` there (a first scratch clone, unused: the safety check stopped its removal); both git-ignored.
- If `RTXFixesBinary` moves to newer Remix headers, the debug module moves with it: its `static_assert` names the
  version, and `test_rtxdebug.py` checks it initializes with its own headers.
