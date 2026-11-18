# The DirectX level servers see (report)

The user's request of 2026-11-18: "Some servers uses render.GetDXLevel() to detect users using our addon which reject
user with dx level lower than 90. As per our plan, apply fixes to allow players using our addon to join server like
this." Done by Claude in a side session on the branch `multiplayer-dxlevel` (worktree `out\worktrees\dx`), package
only ([ADR 0246](../decisions/0246-the-directx-level-servers-see.md)). Nothing is merged, pushed or published.

## The plan

No plan exists in the main thread's conversation. "Our plan" is the user's own R24 item 1.1 (2026-11-08): "when joining
servers, spoof the dx level of the game to avoid compatibility issues, let the server think the user is at the high dx
level". Claude declined it then as hiding the client from a server's rule
([ADR 0133](../decisions/0133-the-multiplayer-notice-in-the-companion.md) §4, the R24 report, the changelog), and no
later session took it up (other sessions' transcripts searched for the level, `GetDXLevel` and "spoof"). The user has
now decided otherwise. ADR 0246 supersedes 0133 §4 and keeps what that concern was about in reach of server owners:
the value is the session's own setting, nothing is hidden (`NativeLoaderDXLevel`, the changelog), and the player can
switch it off.

## What changed for the player

In a multiplayer game an RTX start answers `render.GetDXLevel()` with `mat_dxlevel`, the level the game was started at
(90 with the package's `-dxlevel 90`), instead of the 80 RTX runs Source at, so a server that refuses levels below 90
lets RTX players in, whether it calls `render.GetDXLevel()` or reads the `mat_dxlevel` convar: the two agree. Single-player answers 80 as before; `nativeloader_multiplayer_dxlevel 0` (a client setting the
game keeps) gives the engine's answer everywhere; the `render.Supports*` shader checks and everything Source renders are
unchanged. The global `NativeLoaderDXLevel` (`real()`, `reported()`, `installation`, `switch`) tells any Lua, a server's
included, that this is so.

## The console: `mat_dxlevel` and `mat_info`

The user's note of 2026-11-18: the level shows in Lua (`render.GetDXLevel()`) and in the console (`mat_dxlevel`,
`mat_info`). Measured (`--console mat_info --console mat_dxlevel`, listen servers):

| | RTX, this branch | Without RTX |
|---|---|---|
| Lua `render.GetDXLevel()` | 90 (80 with the switch off) | 95 |
| Lua `GetConVar("mat_dxlevel")` (`GetInt`, `GetString`), `GetConVarNumber`, `GetConVarString`, `cvars.Number` | 90 | 95 |
| Console `mat_dxlevel` | `"mat_dxlevel" = "90"` | `"95"` |
| Console `mat_info` | `m_nDXSupportLevel: 80`, vertex and pixel shader version 0.0, every shader cap no, `HDR_TYPE_NONE` | 95, 3.0, yes, `HDR_TYPE_INTEGER` |

- **Lua and the convar agree.** In a multiplayer game `render.GetDXLevel()` answers exactly what the `mat_dxlevel`
  convar reads (the probe's `agree` true; no cap: a player's own `-dxlevel 95` gives 95 in both).
- **The console's `mat_dxlevel`** already printed 90 under RTX; it is what Lua now answers.
- **`mat_info` stays the engine's real state** (80, no shaders). A server's Lua cannot read the console. Making it print
  90 would take either changing the material system's hardware configuration, which is the level Source draws at (shader
  draws Remix does not path trace, as M4 found), or rewriting the command's printout (the engine guard could take
  `mat_info` over as it takes `poster`), which would show the player numbers the engine does not use and change nothing
  for a server. Neither is done (ADR 0246, point 7).

## Why the RTX client module (a package binary), not only Lua

On a remote server a client realm runs the server's copy of `includes/init.lua`, then the server's autoruns, so the
loader's early view (a view of the local file) never reaches it: C13's dedicated-server session recorded
`installation="verified multiplayer bootstrap"` with the early flag false. The verified bootstrap runs only once the
realm has a gamemode and a valid local player, after `InitPostEntity`: too late for a check at `InitPostEntity`, at
autorun time, or one that keeps a reference to the function taken at load. (R23's documents say the early view also
covers remote servers; the C13 measurement says it does not.)

`client.dll` starts every client realm with one call, `FindAndRunScript("includes/init.lua", ...)` through
`[vtable+0x308]` (one string, one reference in the x64 build), whatever server the file comes from. The RTX client module
(`gmsv_nlrtxclient_win64.dll`, loaded by the loader's menu view at menu start of every RTX start) now hooks that slot
once through the menu state's vtable, which every Lua state shares, only where sure (`loader/client/prelude.h`): only
after finding that very call in the loaded `client.dll`, so a game update that moves the slot leaves the hook out
instead of wrapping another method, and only when the vtable and its slots are `lua_shared.dll`'s. Before
the engine runs a client realm's `includes/init.lua`, the companion's verified `lua/nativeloader/prelude/*.lua` run there
from the catalog; every other call passes straight through. The render guard runs the same file where the module could
not. No loader (`winmm.dll`) change.

## Files

| Path | Change |
|---|---|
| `companion/nativeloader/lua/nativeloader/prelude/dxlevel.lua` (+ `.md`) | New: the override, the switch, `NativeLoaderDXLevel`; only C functions (it runs before `includes/init.lua`) |
| `loader/client/prelude.h`, `prelude.cpp` | New: the `FindAndRunScript` hook and its "only where sure" checks (`confirm_engine_call`: client.dll's own call of the slot with `includes/init.lua`, found by `calls_through_slot`; the vtable and slots in `lua_shared.dll`), `starts_realm`, `is_prelude_script` |
| `loader/client/module.cpp` | `run_prelude` (client realms of a verified start, the catalog's prelude scripts, a raw marker while they run), `install_prelude` after the menu scripts; `Status()` has `prelude`, `prelude_runs` |
| `loader/client/CMakeLists.txt`, `tests/CMakeLists.txt`, `tests/test_prelude.cpp`, `tests/test_module.cpp`, both READMEs | The prelude in the client library; its tests |
| `packages/fixes/modules/gmsv_nlrtxclient_win64.dll.xz`, `packages/fixes/files.json`, `tools/ci/pins.json` | The module refreshed with `tools/ci/repo_builds.py refresh` (one new Git LFS object, about 260 KB, local until pushed); the index entry names `<repo>`, not a local path |
| `companion/nativeloader/lua/autorun/_nativeloader_guard.lua` (+ `.md`) | The fallback include; the file in the exact bundled-source inventory |
| `tools/tests/dxlevel_harness.lua`, `test_multiplayer_dxlevel.py` (+ `.md`), `render_guard_harness.lua`, `test_render_guard.py` (+ `.md`) | Offline tests |
| Docs | ADR 0246 (and status notes on 0052, 0133, 0135), the decisions index, CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS, the companion README, AGENTS.md, the handover index, this report |

## Evidence

**Offline.** `nl_client_catalog_tests` 55/55 (the six prelude cases: the slot numbers checked against the vendored
header as MSVC compiles it, refusals, the runner before the engine's call with the arguments and answer passed through,
one hook on a second install, client.dll's call pattern and its look-alikes, the real `client.dll` of the PoC through
`NL_CLIENT_DLL`; the module's contract). LuaJIT: `test_multiplayer_dxlevel.py` 8/8 and the render guard's 55 tests
with the three new fallback scenarios.

**Gate:** `tools\test.ps1 -Config Release` with `NL_FIXES_CLONE` set, in `out\worktrees\dx`, on 0ee56fe1 and again on
0c5773f7 (the agreement with `mat_dxlevel` and the console): exit 0 both times. Conventions OK, CTest 35/35, Python 2,159
(tools) + 29 (gmapack) + 26 (steam), one skip each, "All checks passed".

**PoC** (`tools/poc_session.py`, holding `out\r10\poc.lock`; gm_construct, 1280 x 720; before = main's published
`0.0.0-dev.20261118054812+70191713`, after = this branch's `0.0.0-dev.20261118200230+f309d7b6`, and again with the final
module, which also confirms client.dll's call before hooking, `0.0.0-dev.20261118202319+773d352b` (runs `after2-*`: the
same results, frames 0.22 and 0.22 from before), and with the final Lua, which answers exactly what `mat_dxlevel` reads,
`0.0.0-dev.20261118203956+8c8287fc` (runs `after3-listen` and `vanilla-matinfo`, with `mat_info` and `mat_dxlevel` typed
into the console: the table above); a scratch server add-on asks each client 2 s after it spawns and takes the
client's own report at `InitPostEntity`, refusing below 90):

| Run | `render.GetDXLevel()` at autorun / `InitPostEntity` / request | Verdicts | Notes |
|---|---|---|---|
| RTX off, default | 95 | admit | `mat_dxlevel` 95, `Supports*` true, System32 `d3d9.dll` |
| RTX off, `-dxlevel 90` | 90 | admit | `mat_dxlevel` 90, `Supports*` true |
| before, single-player | 80 | (reject, never kicked in single-player) | `mat_dxlevel`, `GetConVarNumber`, `cvars.Number` 90; `Supports*Shaders*` false; `SupportsHDR` true |
| before, listen server (`--players 2`) | 80 / 80 / 80 | reject, reject | the kick: "Preventing kick of local server host!" |
| after, single-player | 80 | (reject) | `installation` "prelude"; the menu module: "client prelude hooked"; a client autorun already sees the prelude's function |
| after, listen server | 90 / 90 / 90 | admit, admit | a reference taken by a client autorun: 90; switch 0: 80, re-check "reject"; switch 1: 90, "admit" |

Every run quit normally. The rendering is unchanged: block difference before/after 0.22 (single-player) and 0.38
(listen server), the same camera; about 1 is two captures of one install. The one Lua error of the listen runs
("[gmRTX - Hardware Skinning] Timed out restoring r_forcehwskin before model reload", the fixes' `cl_rtx.lua`) and its
guard line are the same before and after. Evidence: the worktree's `out\dx\poc\<run>\` (console, loader and Remix
logs, status, modules, screenshots); the scratch add-on, probe and drivers in `out\dx\`.

## Not covered, not verified

- **A remote dedicated server.** C13's official dedicated server (`srcds_win64.exe`, steamcmd app 4020) is no longer in
  `out`, and installing it again is a download from Steam, which needs the user's OK. A stand-in,
  `gmod.exe -dedicated -nonativeloader -noaddons` from the PoC, ran a client realm of its own (it answered the check
  itself, at 95), and the RTX client's `connect 127.0.0.1:<port>` gave up after 6 retries (C13's client had
  `+net_usesocketsforloopback 1`, this one did not); that attempt ended as a local game. The prelude's hook point is the one `client.dll` call that starts any client realm, so the
  remote path differs only in where `includes/init.lua`'s text comes from; still, a real remote join, and a real kick of
  a remote player before the change, are not measured.
- The field install (not touched), VR (single-player only), other GPUs.
- Servers that check `render.SupportsPixelShaders_2_0()` or the other shader checks still refuse RTX players (by design:
  those are capabilities).

## For the main thread

- **Branch** `multiplayer-dxlevel` from `main` 152053da; commits are listed in the hand-over note. Merge notes: shared docs
  additive (CHANGELOG top, a ROADMAP paragraph after the invisible-colliders one, the ends of RESEARCH and TESTING, the
  decisions index after 0245, the handover index after the invisible-colliders line, AGENTS.md's status line and
  "latest is" chain); ADR 0246 is the next free number (0244 stays with the rejected loader branch).
- **The module's Git LFS object** (`packages/fixes/modules/gmsv_nlrtxclient_win64.dll.xz`, OID `c3d6c241...`, 266 KB)
  is in the shared local LFS store; a push uploads it. (An earlier refresh's object, `f716b461...`, is in the store
  too, referenced by no commit.)
- **This reverses a decline recorded in ADR 0133 §4** on the user's explicit request; the ADR says why the shape is
  acceptable (the session's own setting, visible, switchable).
- **PoC as left**: `native-loader\config.json` names main's published package (`out\workshop\...70191713.gma`; the
  config found named `...a8e6cb04.gma`, no longer there, kept as `out\dx\poc\state\config.json.before`); this branch's
  package stays deployed until the next start redeploys; the scratch add-on, loose Lua and `data/nldx` removed;
  `cfg\client.vdf` keeps `nativeloader_multiplayer_dxlevel "1"`; `out\r10\poc.lock` released.
