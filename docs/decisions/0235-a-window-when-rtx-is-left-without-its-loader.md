# 0235: A window when RTX Remix is left in the game without its loader

- Status: Accepted 2026-11-16 (the user's request and their two choices; the checks in the report)
- Decided by: the user ("Let's address an uninstallation pop-up. It should be implemented as an addon. ... Sometimes
  user removed winmm.dll and unsub from the addon at the same time. In this case, remix will not uninstall and load
  correctly. At this case, in the main menu, we should have a pop-up (dismissable) to explain the situation and let
  user know what to do to correct this. The recommended step is to put the native loader back, and also give steps for
  manual uninstallation. This should not pop up when the winmm.dll is present."). Asked where it can appear, since no
  add-on code runs in the main menu without the loader, they chose "When a map loads"; asked what a successful
  automatic removal shows, "A short pop-up too".
- Builds on: [0206](0206-rtx-a-removed-loader-left-removes-itself.md) (the companion removes what a removed loader
  left, in a local game, and says so in the chat).
- Report: [leftovers-popup-report.md](../handover/leftovers-popup-report.md).

## Context

The loader removes the RTX package only in a start it runs (ADR 0025). A player who deletes `bin\win64\winmm.dll`,
often while unsubscribing, keeps everything it deployed: Garry's Mod mounts the add-on folders itself, and without the
loader RTX Remix neither starts nor removes itself. Since ADR 0206 the companion's server autorun removes the package
in a local game through the RTX client module, and says so in one chat line; when it cannot (the module missing,
another game of the folder running, the journal gone), nothing tells the player anything.

Garry's Mod's main menu runs only its own Lua (`lua/menu/menu.lua` includes a fixed list of files; no plugin folder,
no `lua_run_menu`, RESEARCH "What runs without the loader"); the companion's menu scripts run there only because the
loader's menu view loads the RTX client module, which runs them. Without `winmm.dll` the first code of the package
that runs is the add-ons' autoruns in a map's server and client realms. The loader cannot be changed, and would not
help a game that no longer has it.

## Decision

1. **A window when a map loads** (`autorun/client/nativeloader_leftovers_popup.lua`): in the client realm of a local
   game (single-player, or a listen server's host), four seconds after `InitPostEntity`, in a start this machine's
   loader did not make an RTX start and with no `bin/win64/winmm.dll` in the game folder. It says RTX Remix is still in
   the game but its loader is gone and why that matters, gives the server's reason when it could not remove the
   package, recommends putting the loader back (the latest release; stay subscribed to keep RTX; unsubscribe, start
   once and quit to remove it, then delete `winmm.dll`), and lists what to delete by hand: the package's add-on
   folders, `lua/bin` files, Remix mods and data folders from the loader's journal (`native-loader/state.json`, read
   only), else the main folders by name and the README's uninstall steps; then `native-loader` (its backup holds the
   player's own files) and the console commands for the sky and lighting. Buttons: Open the release page, Copy these
   steps, Don't show this again (`data/nativeloader_companion/leftovers_popup.txt`), Close.
2. **A short window after an automatic removal**: removed (or partly), restart to finish, how to get RTX back; OK.
   The removal takes the client's copy of the add-on before the client realm starts, so the server sends the window
   as Lua: the window module's source, read before the removal, and its text as hexadecimal JSON in `Player:SendLua`
   lines of at most 254 characters, a last line compiling and showing it. The chat line stays.
3. **Never** while `winmm.dll` is in the game folder (an off switch: the loader removes what it deployed itself), in an
   RTX start, or on another machine's server (the companion's client autoruns do not run there).
4. **The server tells the client what it did**: every outcome of its attempt goes to
   `data/nativeloader_companion/leftovers_state.json` (`outcome`, `error`, `at`); the client's window stays away
   after a removal, and ignores a state older than ten minutes.
5. **One window module** (`nativeloader/leftovers_window.lua`) draws both: self-contained, scaled by `ScrH() / 1080`,
   fonts with every script, opening only `https://` pages and writing only under `nativeloader_companion/`.

## Consequences

- The main menu itself still shows nothing in this state; the player sees the window at their first map (local
  game). A player who only joins other servers sees it at their first local game.
- The companion has a second file that runs in starts without RTX; the gate test lists it among the files that decide
  for themselves. Its texts are translated into the six languages.
- The README's Uninstalling section says what to do when `winmm.dll` is already gone, with the package's folders and
  files.
