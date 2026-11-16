# nativeloader_leftovers.lua

[ADR 0206](../../../../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md): removes RTX a removed loader
left in the game. The loader removes the RTX package at the first start after an unsubscribe, but only a start that
runs the loader does: when the player deletes `bin\win64\winmm.dll` first, or instead of unsubscribing, everything the
loader deployed stays and Garry's Mod runs the package's add-ons without the runtime (the RTX Remix tab, the fixes'
"RTX Remix" menus, the painted sky replaced).

- **When.** Server realm (`autorun/server`), never sent to clients. Only in a local game (not a dedicated server), not
  in an RTX start of this machine's loader (`NativeLoaderRTXStart()`, set by `!!!!nativeloader_engine_guard.lua`),
  and only when `bin/win64/winmm.dll` is not in the game folder (`file.Exists(..., "BASE_PATH")`): with the loader
  installed, a start through an off switch loads no native code, and the loader removes what it deployed itself.
- **What.** At `Initialize`, after the server's autoruns (none loses its file half-way) and before the player's client
  realm starts, it loads the RTX client module (`require("nlrtxclient")`, `gmsv_nlrtxclient_win64.dll`) and calls
  `NativeLoaderLeftovers.Remove()`. The module checks again (its own path, this folder's `gmod.exe`, the loader
  absent, no other game of the folder, the RTX package in the loader's journal) and runs the loader's own uninstall;
  see [loader/client/README.md](../../../../../loader/client/README.md). Without the module, or when it answers
  "not needed", nothing happens.
- **After a removal** ("removed", or "partly removed" when something stayed): the console settings RTX sessions
  changed are set back to the player's own values with `RunConsoleCommand` (the module plans them as the loader does
  at a start without RTX); the console gets English lines with the counts, the archive folders and, for a partial
  removal, what stayed; once the player makes their first own move in the game (a single-player game, or a listen
  server's host), Garry's Mod's chat shows one translated line: RTX Remix was removed because its loader is gone,
  restart to finish. The translations are read from `nativeloader/i18n_data.lua` before the removal (the language:
  `nativeloader_language` if set, else `gmod_language`).
- **A refusal** (another Garry's Mod of the folder runs, another deployment holds `native-loader/lock`, the journal
  cannot be read) is only logged; nothing changed, and the next local game tries again.
- **What the client's window learns** ([ADR 0235](../../../../../docs/decisions/0235-a-window-when-rtx-is-left-without-its-loader.md)).
  Every outcome of such a start is written to `data/nativeloader_companion/leftovers_state.json` as
  `{outcome, error, at}` (`removed`, `partly removed`, `refused`, `not needed`, `no module` when the module did not
  load, `failed` when its call raised): the client autorun
  [`nativeloader_leftovers_popup.lua`](../client/nativeloader_leftovers_popup.lua.md) shows its long window unless the
  outcome is a removal. After a removal the player also gets the short window ("RTX Remix was removed from this game":
  restart to finish; to use RTX again, put `winmm.dll` back and subscribe; OK), at the same moment as the chat line.
  The removal took the client's copy of the add-on, so the window's source
  ([`nativeloader/leftovers_window.lua`](../../nativeloader/leftovers_window.lua.md), read when this file loads) and its
  text go to the player as Lua: `Player:SendLua` takes at most 254 characters, so the JSON of both is sent as
  hexadecimal in lines of 200 digits (`NLLW={}`, then `NLLW[#NLLW+1]='...'`), and a last line decodes it, compiles the
  source (`CompileString`) and calls `Show`.

Side effects: loads one native module in such a start; through it, deletes and moves the files the loader deployed
(never one the player changed) and rewrites `native-loader/session_cvars.json`; sets console variables; writes
`data/nativeloader_companion/leftovers_state.json`; sends the short window's Lua to the local player. Tests:
[`tools/tests/test_leftovers_lua.py`](../../../../../tools/tests/test_leftovers_lua.py.md).
