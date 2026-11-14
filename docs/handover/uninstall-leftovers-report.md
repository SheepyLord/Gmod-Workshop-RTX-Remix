# RTX left in the game after removing it: report (2026-11-13)

The user's request: "User still reports uninstallation issue where after unsubscribed from the workshop addon, leftover
files are still in the game. as quoted: "so I removed the addon. However, the RTX Remix menu is still showing in-game,
and the skybox now has a missing texture error. How can I fix this? I would really appreciate your help!" Please make
the uninstallation process more robust and make sure no RTX and bundled addon exist after user unsub from the workshop
addon or launch with RTX disabled." Done by Claude on the branch `uninstall-orphans` (worktree
`out\worktrees\orphan`), package only: no loader (`winmm.dll`) change, no runtime change
([ADR 0206](../decisions/0206-rtx-a-removed-loader-left-removes-itself.md)).

## Why RTX stayed

The loader removes the package at the first start after the item goes (ADR 0025) and keeps the package's add-ons out
of every start where RTX does not activate, the RTX-off setting included (ADR 0013). Both happen only in a start that
runs the loader. What stays in the game otherwise is exactly the report:

- **"The RTX Remix menu is still showing"**: the companion's RTX Remix tab (`addons/nativeloader`), and `remixbinary`'s
  Utilities > RTX Remix options, its RTX Remix entities and tool category. Garry's Mod mounts every folder in
  `garrysmod/addons` by itself; without the loader nothing hides them.
- **"The skybox now has a missing texture error"**: `remixbinary/materials/skybox/painted*.vmt` replace GMod's painted
  sky (gm_construct, gm_flatgrass) with a `"sky"` material whose textures (`skybox/g_sky_baked_*`) ship beside them;
  with part of the folder gone the sky shows the checkerboard. Its Lua also changes `sv_skyname` on other maps, and
  `cl_rtx.lua` fails at its `require` without the runtime. The RTX session's console settings (`r_3dsky 0`, ...) stay
  too: only the loader puts them back.

Ways to get there: deleting `bin\win64\winmm.dll` before the start that would have removed the package (with the
unsubscribe, or instead of it; the player README's "Removing" even said leftover files "are no longer used"); files
of an earlier installation the loader adopted (ADR 0188's release never ran); an off switch (`-nonativeloader`,
`NATIVE_LOADER_DISABLE=1`, `native-loader\disable`, `"enabled": false`), which skips the loader for a start by design.

## What changed (package only)

- **The RTX client module removes what a removed loader deployed** (`loader/client/leftovers.cpp`; the module rebuilt
  and recorded with `repo_builds.py refresh`). In the engine's server state of a local game it publishes
  `NativeLoaderLeftovers` and nothing else. `Remove()` acts only with the loader gone (`bin\win64\winmm.dll` absent,
  and not loaded by this process), from the module's own folder and that folder's `gmod.exe`, with no other game of the
  folder running and the RTX package in the loader's journal. It undoes an interrupted deployment, archives an earlier
  RTX installation (ADR 0188's two moves), runs `deploy::uninstall` (what `nlctl uninstall` runs) with this process
  excluded from its game check, moves what the game holds open (the module itself: Windows refuses to delete a loaded
  module but lets it be renamed) to `native-loader\backup\in-use\<time>\`, finishes the uninstall, and returns the
  console settings to put back, planned as the loader plans them.
- **The companion asks for it** (`autorun/server/nativeloader_leftovers.lua`, never sent to clients): in a local game
  that is not an RTX start of this machine's loader, only when `bin/win64/winmm.dll` is not in the game folder (so an
  off-switch start loads no module), at `Initialize`, after the server's autoruns and before the player's client realm.
  It sets the console settings back, logs what happened and, once the player moves in the game, says in the chat
  (translated into the six languages) that RTX Remix was removed and to restart.
- **The package's Lua does nothing without RTX.** `!!!!nativeloader_engine_guard.lua`, the package's first autorun,
  publishes its decision as `NativeLoaderRTXStart()`; the companion's other 23 autoruns and `remixbinary`'s five
  (`cl_rtx`, `sh_rtx`, `sv_rtx`, `tmc`, `matdebug`; re-indexed with `inputs.py import`) return at their first line of
  code when it says no. The fixes also accept the verified multiplayer initializer.
- **Docs:** ADR 0206, the player README's "Removing" and off-switch lines, CHANGELOG, ROADMAP, RESEARCH ("A removed
  loader's leftovers"), the client module's and the companion's READMEs, each changed script's `.md`, the translations'
  provenance note, the render guard's list of the package's own Lua (the new file).

## Verified (offline)

- `nl_client_catalog_tests`: 47 cases, 0 failed. New `test_leftovers.cpp` (4 cases): the loader counts as installed
  with its bootstrap in the folder; nothing happens without a journal or without the RTX package in it; through the
  real deployer, with the loader gone, nothing of the package stays at its paths, the journal and lock go, the
  player's own Remix mod comes back, an earlier installation's original and adopted files are archived in
  `former-rtx`, the module the test holds mapped as an image (`DeleteFileW` refused) moves to `in-use` with an index,
  the console setting the player had not changed comes back and the record is marked; another deployment's lock leaves
  everything as it was. `test_module.cpp`: a server realm gets only `NativeLoaderLeftovers`, raw, for that state, the
  module's folder and this `gmod.exe`.
- `tools/tests/test_leftovers_lua.py` (LuaJIT): every gated file starts with its gate, returns without touching any
  global without RTX and goes on with RTX; the clean-up in ten scenarios (RTX start, dedicated server, loader
  installed, no module, "not needed", a module error, a refusal, a removal with the setting and the chat notice, the
  notice in French, a partial removal).
- `python tools\companion_i18n.py check`: the catalogs are complete.
- The full gate passes; see "Gate" below.

## Verified in the game (PoC, 2026-11-13, the user's go-ahead "Run all three")

After the VR V8 session released the PoC, holding `out\r10\poc.lock`, with the released loader 0.16.0 (the field's
`winmm.dll`, read only) and the branch's package from a local source, driven by `tools\poc_session.py` (single
player, gm_construct, a client probe and a server probe each start). Evidence: `out\uninst-poc\evidence` (first
series) and `evidence2` (second series, the final build `0.0.0-uninst.2`, digest `4f6bba9d...`).

The first series found three faults, all fixed before the second:
- **The removal refused in the game**: "another Garry's Mod runs from this folder". The game's own Chromium helpers
  are `gmod.exe` of the same folder, and both `former_rtx.cpp`'s check and the deployer's would count them.
  `leftovers.cpp`'s `another_game` now leaves out processes whose parents lead to the game; the deployer's own check
  is skipped after it (C++ test with a `ping.exe` named `gmod.exe`, as a child and orphaned).
- **An off-switch start still loaded native code**: `gmcl_rtxdebug_win64.dll` (the fixes' `rtx_debug` add-on) and the
  load accelerator. Both now take the same RTX-start decision (the load accelerator itself, since its autorun sorts
  first).

Second series, every run exit 0, a normal quit and 0 Lua errors:

| Run | Start | Result |
|---|---|---|
| `01-rtx` | RTX, package deployed (1,626 changes) | RTX active; `NativeLoaderRTXStart()` true in both realms; the RTX Remix tab, the fixes' menus, entities and tool, the load accelerator all as before |
| `02-rtx-off` | the RTX-off setting | all 20 add-on folders hidden; none of the package runs; the loader put the console settings back |
| `03-off-switch` | `-nonativeloader` | the answer false; no RTX Remix tab, no fixes' Lua (no `gmRTX` line), no module of the package loaded; nothing removed (1,234 add-on files, 18 modules) |
| `04-removed` | `winmm.dll` taken away | "The native loader (bin/win64/winmm.dll) is gone: RTX Remix removed. 1831 files deleted"; the module moved to `native-loader\backup\in-use\20261114T041559Z`; journal, lock, add-ons, modules and `status.json` gone; the player's console got the notice; already in that session the client had no RTX Remix tab, no fixes, no entities or tool; gm_construct's sky is GMod's own |
| `05-restart` | still without the loader | plain Garry's Mod: no package Lua at all, no `[nativeloader]` line |

Seen on the way, left as they are: in an off-switch start the fixes' entities and tool still register (from their
files; the README says off switches keep the add-ons); files the package's Lua writes at run time
(`rtx-remix\mods\~gmod_topbr`'s PBR registry and backups, `!advanced_material_editor`) stay after any uninstall, as
the loader keeps files it did not place; the chat notice is shown when the player arrives and had faded from the chat
box by the driver's screenshots (it is in the console). The PoC's `config.cfg` holds none of the RTX session settings,
so the restore list was empty there (the offline test covers it); `BASE_PATH` found no `winmm.dll` in runs 04 and 05,
as it should.

Afterwards the PoC is as it was before the first series: no `winmm.dll`, no `config.json`, nothing deployed; what the
runs made (`native-loader`, `rtx-remix`, `garrysmod\data`) was moved into `evidence2\poc-after`, never deleted; its
`rtx.conf` and `user.conf` (2026-11-12) untouched; SteamVR left running.

## For the reporting player (their files predate this change)

A package update cannot reach a game that already unsubscribed, so they need to do it by hand:

1. Close Garry's Mod. If `GarrysMod\bin\win64\winmm.dll` is still there, start the game once and quit: the loader
   removes what it still tracks. Then delete `winmm.dll`.
2. Delete these folders from `GarrysMod\garrysmod\addons\` (only these): `!advanced_material_editor`,
   `!gmod_bullet_break_simulator`, `GMod-Seamless-Portals-Remix`, `Remove_halo`, `advanced_bodygroup_tool`,
   `gm_poolrooms_rtx`, `mmd_hotloader`, `mmd_vmd_npc`, `mount-hl2rtx`, `nativeloader`, `niknaks`, `nlblood`,
   `nldynamic_toolgun_screen`, `nlglass`, `nlloadaccel`, `nlvr`, `remixbinary`, `rtx_agent`, `rtx_debug`, `rtx_water`.
   (`nativeloader` and `remixbinary` are what show the RTX Remix menu and change the sky.)
3. Delete these files from `GarrysMod\garrysmod\lua\bin\` if present: `gmcl_RTXFixesBinary_win64.dll`,
   `gmcl_advmat_rtx_bridge_win64.dll`, `gmcl_mmdhl_win64.dll`, `gmcl_nlengineguard_win64.dll`,
   `gmcl_nlfsaccel_win64.dll`, `gmcl_nlglass_win64.dll`, `gmcl_nlvr_win64.dll`, `gmcl_rtxdebug_win64.dll`,
   `gmcl_rtxwater_win64.dll`, `gmsv_mmdhl_win64.dll`, `gmsv_nlengineguard_win64.dll`, `gmsv_nlfsaccel_win64.dll`,
   `gmsv_nlrtxclient_win64.dll`, `lib_coacd.dll`, `mmdhl-native-release.json`, `mmdhl_runtime_win64.dll`,
   `mmdhl_worker.exe`, `openvr_api.dll`.
4. Optional: `GarrysMod\native-loader\`, `GarrysMod\rtx-remix\` (unless another Remix setup uses it),
   `GarrysMod\garrysmod\data\nativeloader_ui` and `remix_map_configs`.
5. If something still looks different after a restart (no 3D skybox, flat lighting): in the console run
   `exec nativeloader_restore.cfg` if that file is in `garrysmod\cfg`, or `r_3dsky 1` and `mat_specular 1`.

## Gate

`tools\test.ps1 -Config Release` passes on the branch (uncommitted, 2026-11-13), last after the PoC series' fixes: the
conventions, the C++ build and CTest (35 of 35; the client module's 48 cases among them), Python 29 + 26 + 1,868
tests. An earlier run failed only on two documentation checks (the decision index takes table rows; a roadmap link
was checked before this report existed), both fixed. The branch was cut from `a897abe9`; `main` has moved since
(issue 5, `951fafa2`), so the merge needs a rebase and the gate again.
