# A window when RTX Remix is left without its loader: report (2026-11-16)

The user's request: "Let's address an uninstallation pop-up. It should be implemented as an addon. It is to address
this problem: Sometimes user removed winmm.dll and unsub from the addon at the same time. In this case, remix will not
uninstall and load correctly. At this case, in the main menu, we should have a pop-up (dismissable) to explain the
situation and let user know what to do to correct this. The recommended step is to put the native loader back, and
also give steps for manual uninstallation. This should not pop up when the winmm.dll is present." Done by Claude on
the branch `leftovers-popup`, package only: the companion's Lua and translations, no loader (`winmm.dll`), runtime or
native module change ([ADR 0235](../decisions/0235-a-window-when-rtx-is-left-without-its-loader.md)).

## Where it can appear

Without `winmm.dll` nothing of the package runs in Garry's Mod's main menu: the menu state loads a fixed list of its
own files (no plugin folder, no `lua_run_menu`), and the companion's menu scripts run there only because the loader's
menu view loads the RTX client module (RESEARCH, "What runs without the loader"). The first code of the package that
runs in such a start is the add-ons' autoruns in a map. Asked, the user chose **when a map loads**, and for a removal
the companion manages by itself (ADR 0206), **a short pop-up too**.

## What changed

- **`autorun/client/nativeloader_leftovers_popup.lua` (new):** in the client realm of a local game (single-player or a
  listen server's host), not in an RTX start, with no `bin/win64/winmm.dll` in the game folder, four seconds after
  `InitPostEntity`, unless the player chose Don't show this again or the server removed the package in this start:
  the long window. Its lists come from the loader's journal (`native-loader/state.json`, `current.files` of
  `gmod-rtx-remix`, read through `BASE_PATH`): add-on folders, `lua/bin` files, Remix mods, data folders. Without the
  journal: the main folders by name and the README's steps. Translated into the six languages.
- **`nativeloader/leftovers_window.lua` (new):** the window, self-contained (no include, no translation), scaled by
  `ScrH() / 1080`, `extended` Tahoma fonts, buttons that open only `https://` pages and write only under
  `data/nativeloader_companion/`.
- **`autorun/server/nativeloader_leftovers.lua`:** writes every outcome of its attempt to
  `data/nativeloader_companion/leftovers_state.json`; after a removal sends the short window to the player with the
  chat line. The client's copy of the add-on is gone by then, so the window's source (read when the file loads) and
  its text go as hexadecimal JSON in `Player:SendLua` lines (at most 254 characters; these are 233 and 216).
- **The render guard's list** (`_nativeloader_guard.lua`) names both new files; the gate test's list of files that
  decide for themselves names the client autorun.
- **README:** "If you already deleted `winmm.dll`": put it back (recommended) or the package's folders and files to
  delete by hand.

## Tests

- `tools/tests/test_leftovers_popup.py` with `leftovers_popup_harness.lua` (LuaJIT, the real files): nothing in an RTX
  start, with the loader, on another machine's server, after the server's removal or after Don't show this again; the
  window with the reason and the journal's lists (another package's files left out), for a host, in French, with a
  stale or no state, its buttons, without the journal; the window writes only to its folder and opens only `https://`.
- `tools/tests/test_leftovers_lua.py` (`leftovers_harness.lua`): each of the clean-up's ten scenarios also checks the
  state it writes, and after a removal the short window: every `SendLua` line at most 254 bytes, run in a mocked client
  realm, the compiled source the window file exactly, the window's title (French too), text and OK. Shared helpers
  (JSON, a VGUI stand-in): `leftovers_test_lib.lua`.
- `python tools\companion_i18n.py check`: complete (22 new texts in each language).

## In the PoC

`out\msep\poc_leftovers.py` (scratch, holding `out\r10\poc.lock`): gm_construct at 1920 × 1080, single-player, with
the package built from this branch (`0.0.0-dev.20261116184259+2499c8af`); the consoles and screenshots are in
`out\qa-poc\leftovers-popup`.

1. **Deploy** (`01-deploy`): the loader and the package installed; an RTX start deployed it.
2. **The long window** (`02-long`): `bin\win64\winmm.dll` and the RTX client module
   (`garrysmod/lua/bin/gmsv_nlrtxclient_win64.dll`) deleted, so the server's removal could not run. The next start
   (no loader, no RTX) recorded `no module` with its reason and, four seconds into the map, showed the long window at
   760 × 624 px: the title, the explanation, the server's reason, the three recommended steps, the journal's lists
   (20 add-on folders, 18 files in `lua/bin`, 8 Remix mods, `remix_map_configs`), `native-loader`, the console line
   and the four buttons. It fits its text: nothing cut off, no scroll bar.
3. **Repair** (`03-repair`): the loader reinstalled; an RTX start put the module back.
4. **The short window** (`04-short`): only `winmm.dll` deleted. The server removed the package ("RTX Remix removed.
   1910 files deleted, 0 of yours put back"), recorded `removed`, and sent its window to a client realm in which the
   companion never ran (`NativeLoaderRTXStart` nil): 560 × 198 px with the title, both paragraphs and OK, fitted to
   its text. Afterwards the game had no loader, no RTX module and no companion.

**A two-slot listen game** (`out\msep\poc_leftovers_listen.py`, the same package, `+maxplayers 2`). It ran without
the Lua probe: `lua_run_cl` needs `sv_allowcslua 1` there, which would also let the client read Lua files the server
never sent, and that was what this run checked. The evidence is the screenshot and the console:

- **The long window** (`22-listen-longa`, `winmm.dll` and the module deleted): the host saw it as in single-player,
  with the server's reason and the journal's lists. The window module was included although nothing sent it with
  `AddCSLuaFile`, so the listen host needs nothing more.
- **The short window** (`24-listen-shorta`, `winmm.dll` alone deleted): the package removed (1910 files), the chat
  line, and the short window for the host.
- **Seen in that removal start, from before this change (ADR 0206):** the host's client still ran the deleted
  add-ons' client autoruns the server had listed, and their own includes failed: "Couldn't include file" lines from
  the material editor, the bullet break simulator and the VMD NPC add-on. The Model Hotloader's notice showed its raw
  key `mmdhl.install.notice_binary`. It happens once, in the start whose windows ask for a restart; single-player
  shows none of it.

Earlier runs of this branch found the short window at a fixed 300 px with an empty band above OK, then, fitted once
from a timer, at 160 px with its second paragraph cut off (a wrapped label has its height only after its own layout);
the window now fits itself on every frame of its first second, and the runs above are of that code.

The PoC was left without the loader and with nothing of the package deployed; the next `poc_session.py install` puts
both back.

**Not checked in the game:** the field install, 4K (the sizes scale by `ScrH() / 1080` as the companion's other
windows do), the other languages (French in the harness), and the buttons' clicks (in the harness: the clipboard text,
the dismissal file, `https://` only).
