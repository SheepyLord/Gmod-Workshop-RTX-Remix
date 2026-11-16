# test_leftovers_popup.py

[ADR 0235](../../docs/decisions/0235-a-window-when-rtx-is-left-without-its-loader.md): the window that tells a player
RTX Remix is left in the game without its loader
([`nativeloader_leftovers_popup.lua`](../../companion/nativeloader/lua/autorun/client/nativeloader_leftovers_popup.lua.md),
[`leftovers_window.lua`](../../companion/nativeloader/lua/nativeloader/leftovers_window.lua.md)).

```powershell
cd tools; python -m unittest tests.test_leftovers_popup
```

| Test | Checks |
|---|---|
| it returns in an RTX start and with the loader before anything else | the autorun's first statements: realm and once, then `NativeLoaderRTXStart()`; the `winmm.dll` check before any hook or include |
| the window needs nothing else of the add-on | the window module has no `include`, `require`, `AddCSLuaFile`, translation call or RTX-start check, and returns `{ Show = Show }` (the server sends its source to a client whose copy is gone) |
| the guard knows both files as the package's own | `_nativeloader_guard.lua` lists them |
| the scenarios | [`leftovers_popup_harness.lua`](leftovers_popup_harness.lua.md): nothing in an RTX start, with the loader, on another machine's server, after the server's removal or after Don't show this again; the window with the reason and the journal's lists, for a host, in French, without a fresh state, its buttons, without the journal, and the window's limits on files and pages (skipped without LuaJIT) |

The server's side (the state it writes, the short window it sends) is in
[`test_leftovers_lua.py`](test_leftovers_lua.py.md). Exit 0 when every test passes.
