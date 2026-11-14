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

Side effects: loads one native module in such a start; through it, deletes and moves the files the loader deployed
(never one the player changed) and rewrites `native-loader/session_cvars.json`; sets console variables. Tests:
[`tools/tests/test_leftovers_lua.py`](../../../../../tools/tests/test_leftovers_lua.py.md).
