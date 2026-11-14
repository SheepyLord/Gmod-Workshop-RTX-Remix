# 0206: RTX a removed loader left removes itself; the package's Lua stays out of every start without RTX

- Status: Accepted 2026-11-13 (tested offline and on the PoC with the released loader 0.16.0, the user's go-ahead)
- Decided by: the user. Report of a player (2026-11-13): "so I removed the addon. However, the RTX Remix menu is still
  showing in-game, and the skybox now has a missing texture error." Request: "Please make the uninstallation process
  more robust and make sure no RTX and bundled addon exist after user unsub from the workshop addon or launch with RTX
  disabled." Standing constraint (2026-11-11): no loader (`winmm.dll`) release; fix it in the package. Claude choosing
  how.
- Builds on: [0025](0025-unsubscribe-removes-the-package.md) (an unsubscribe removes the package),
  [0013](0013-rtx-only-addons-hidden-without-rtx.md) (the package's add-ons are hidden from starts without RTX),
  [0010](0010-rtx-session-extras.md) (session console settings, put back at a start without RTX),
  [0188](0188-unsubscribing-with-the-loader-already-installed.md) (an earlier RTX installation is archived, never put
  back), [0126](0126-a-record-of-what-this-repositorys-modules-were-built-from.md) (the client module's build record).
- Does not loosen the off switches (AGENTS.md rule 4): with the loader installed, a start through an off switch loads
  none of the package's native code; it now also runs none of its own Lua. Nothing is deleted that the loader's own
  uninstall would keep (AGENTS.md rule 3).

## Context

The loader removes the RTX package at the first start after it goes (ADR 0025), and keeps its add-ons out of every
start where the runtime does not activate (ADR 0013): the RTX-off setting, an unsupported GPU, a failed activation.
Both need the loader to run. Three ways around it remained:

1. **The loader is removed first.** A player who deletes `bin\win64\winmm.dll` together with the unsubscribe, or
   instead of it (the README's "Removing" even said the files then "stay where they are but are no longer used"), keeps
   everything the loader deployed: 22 add-on folders, 18 binary modules, the Remix mods and the runtime. Garry's Mod
   mounts the add-on folders itself, so the companion's RTX Remix tab, the fixes' "RTX Remix" tool menus and entities
   and their Lua run in a game without the runtime: `cl_rtx.lua` fails at its `require`, `sv_skybox_fix.lua` changes
   the sky, `remixbinary`'s `materials/skybox/painted*.vmt` replace GMod's painted sky. The RTX session's console
   settings (`r_3dsky 0`, ...) also stay: only the loader puts them back.
2. **Files a loader left behind**: ADR 0188's adopted copies when the release at the end of a session never ran.
3. **The off switches** (`-nonativeloader`, `NATIVE_LOADER_DISABLE=1`, `native-loader\disable`, `"enabled": false`)
   skip the loader for a start: by design they hide nothing, and the package's add-ons ran without the runtime.

## Decision

1. **The RTX client module removes what a removed loader deployed** (`loader/client/leftovers.cpp`). In the engine's
   server state of a local game it publishes `NativeLoaderLeftovers` (`Check`, `Remove`) and nothing else; the menu
   part is unchanged. `Remove` acts only when the module sits at its deployed path, the process is that folder's
   `bin\win64\gmod.exe` (not a dedicated server), the loader is not installed (`bin\win64\winmm.dll` is absent and
   this process did not load its `winmm.dll` from there), no other Garry's Mod of the folder runs, and the journal
   records the RTX package as deployed. It then does what the loader would have done:
   - no other Garry's Mod of the folder may run (`another_game`): this game's own Chromium helpers are `gmod.exe`
     processes of the same folder, started by it, and do not count (the first PoC run refused because of them, and
     so would the deployer's own check, which the module therefore leaves out);
   - an interrupted deployment is undone (`deploy::recover`);
   - ADR 0188's moves: originals the RTX package displaced below `garrysmod/addons/` and `garrysmod/lua/bin/` and its
     adopted files go to `native-loader/backup/former-rtx/`, so no earlier RTX installation is put back or left;
   - `deploy::uninstall` (what `nlctl uninstall` runs), with this process excluded from its running-game check: every
     file the loader placed goes, the player's own originals come back, user-changed files stay, the journal goes;
   - what this game holds open (the module itself, mapped as an image: Windows refuses to delete it but lets it be
     renamed) moves to `native-loader/backup/in-use/<UTC time>/` with an `index.json`, and a second uninstall
     finishes; nothing loads it from there;
   - the console settings RTX sessions changed are planned as the loader plans them at a start without RTX
     (`session::plan`), returned for the Lua to set, and the record is marked as put back.
2. **The companion asks for it** (`autorun/server/nativeloader_leftovers.lua`, server realm, never sent to clients):
   only in a local game, not in an RTX start of this machine's loader, and only when `bin/win64/winmm.dll` is not in
   the game folder (`BASE_PATH`), so a start through an off switch loads no module. At `Initialize`, after the server's
   autoruns and before the player's client realm, it loads the module and calls `Remove`; it sets the returned console
   settings, logs what happened, and once the player is in the game tells them in the chat (translated) that RTX Remix
   was removed and to restart. A refusal is only logged; the next local game tries again.
3. **The package's Lua does nothing in a start without RTX.** The companion's first autorun
   (`!!!!nativeloader_engine_guard.lua`, sorted before every other autorun of the package) publishes its answer as
   `NativeLoaderRTXStart()`: this machine's loader activated RTX in this start (its report says so and, from loader
   0.14.0, it holds `native-loader/rtx-session.txt` open). Every other companion autorun returns at its first line of
   code when the answer is no, and so does every autorun of the RTX fixes' `remixbinary` add-on unless the verified
   multiplayer initializer runs it. Off-switch starts, removed loaders and leftovers no longer show the RTX Remix tab
   or run the fixes without the runtime. The fixes' debug add-on (`rtx_debug`, which loads its own module) has the same gate, and the load accelerator
   (`nlloadaccel`, whose autorun sorts before the companion's) makes the same decision itself before it loads its
   module: in the PoC's `-nonativeloader` start both had loaded their modules.

## Consequences

- A player who deletes `winmm.dll` first gets a plain game after one local game and a restart: the package's files are
  gone, their own files are back, the console settings are theirs again. What stays is `native-loader\` itself
  (config, logs, the archives), as after `nlctl uninstall`.
- Only the package reaches players: a player whose files predate this package (the reporting player) is helped by the
  manual steps in the report, not by this change.
- With the loader installed, nothing changes for unsubscribing (ADR 0025) or the RTX-off setting (ADR 0013), which
  already removed or hid everything. Entities, tools and materials of add-ons that an off-switch start still mounts
  stay registered, as the README says: off switches are for troubleshooting, not a way to play without RTX.
- The client module is rebuilt and recorded (ADR 0126). Tests: `test_leftovers.cpp` (the real deployer, a module held
  as an image, the lock), `test_module.cpp` (the server realm's narrow part), `test_leftovers_lua.py` (the trigger in
  ten scenarios; every gated file, run with and without RTX).
