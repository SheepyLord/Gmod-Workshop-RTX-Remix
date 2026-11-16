# nativeloader_leftovers_popup.lua

[ADR 0235](../../../../../docs/decisions/0235-a-window-when-rtx-is-left-without-its-loader.md): a window that tells
the player RTX Remix is still in the game while its loader is gone, and what to do.

- **Why.** A player who deletes `bin\win64\winmm.dll`, often while unsubscribing from the RTX package, keeps every file
  the loader deployed: Garry's Mod mounts the add-on folders by itself, but without the loader RTX Remix neither starts
  nor removes itself (the loader removes the package only in a start it runs, ADR 0025).
- **When.** Garry's Mod runs no add-on code in its main menu: the menu state loads a fixed list of its own files, and
  only the loader adds the companion's menu scripts there. So the first moment is a map. This file runs in the client
  realm and stops at once in a start where this machine's loader started RTX (`NativeLoaderRTXStart()`) or while
  `bin/win64/winmm.dll` is in the game folder (an off switch: the loader removes what it deployed itself). Otherwise,
  four seconds after `InitPostEntity`, in a single-player game or for a listen server's host (on another machine's
  server the companion's client autoruns do not run), it shows the window unless the player chose
  **Don't show this again** (`data/nativeloader_companion/leftovers_popup.txt`).
- **What the server did.** The server's [`nativeloader_leftovers.lua`](../server/nativeloader_leftovers.lua.md) has
  tried to remove the package at `Initialize` and wrote the outcome to
  `data/nativeloader_companion/leftovers_state.json` (`outcome`, `error`, `at`). When it removed the package
  (`removed`, `partly removed`), it shows the short window itself and this file does nothing (it may not even be there
  any more). A state written more than ten minutes ago belongs to another game and is ignored.
- **The window** ([`nativeloader/leftovers_window.lua`](../../nativeloader/leftovers_window.lua.md), long form):
  - the title "RTX Remix is still in this game, but its loader is gone", what happened, and the server's reason when
    it gave one ("It could not remove itself now: ...");
  - **Recommended: put the native loader back**: download `winmm.dll` from the latest release into
    `GarrysMod\bin\win64`; to keep RTX, stay subscribed and start the game; to remove it, unsubscribe, start once and
    quit (the loader removes everything it installed and puts the player's own files back), then delete `winmm.dll`;
  - **Or remove it by hand, with Garry's Mod closed**: the package's folders in `garrysmod\addons`, its files in
    `garrysmod\lua\bin`, its Remix mods in `rtx-remix\mods` and its folders in `garrysmod\data`, read from the
    loader's journal (`native-loader/state.json`, `current.files` of the package `gmod-rtx-remix`; another package's
    files are left out); without the journal, the main folders by name and the uninstall steps on GitHub
    (`README.md#uninstalling`). Last `GarrysMod\native-loader` (its backup folder holds the player's own files the
    loader had moved aside), and the console commands that put the sky and lighting back;
  - buttons: **Open the release page** (the latest release on GitHub), **Copy these steps** (everything as text, with
    the release page), **Don't show this again**, **Close**.
- **Language.** The player's, from the companion's translations (`nativeloader/i18n_data.lua`, `nativeloader_language`
  else `gmod_language`), without loading `nativeloader/i18n.lua`, which is made for RTX starts. Edit the English text
  in `TEXT`; the translations are in `companion/i18n/<language>.po`.

Tested by [`tools/tests/test_leftovers_popup.py`](../../../../../tools/tests/test_leftovers_popup.py.md).
