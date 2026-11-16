# leftovers_popup_harness.lua

LuaJIT harness for [ADR 0235](../../docs/decisions/0235-a-window-when-rtx-is-left-without-its-loader.md): runs the
companion's real `autorun/client/nativeloader_leftovers_popup.lua` and `nativeloader/leftovers_window.lua` in a mocked
client realm: the data folder, the game folder (`BASE_PATH`: `bin/win64/winmm.dll` and the loader's journal
`native-loader/state.json`), the translations, timers, `gui.OpenURL`, `SetClipboardText` and a VGUI stand-in from
[`leftovers_test_lib.lua`](leftovers_test_lib.lua.md). The clock is fixed; the journal lists the RTX package's files in
each place and another package's beside them.

```powershell
luajit tools\tests\leftovers_popup_harness.lua <repository root> <scenario>
```

| Scenario | Checks |
|---|---|
| `rtx`, `loader` | an RTX start, or `winmm.dll` in the game folder: no hook at all |
| `remote` | on another machine's server: no window |
| `removed`, `partly` | the server removed the package (a fresh state): no window (the server shows its own) |
| `dismissed` | after Don't show this again: no window |
| `refused`, `host`, `french` | the window (single-player, a listen server's host, French): the title, the explanation, the server's reason, the recommendation, the package's add-on folders sorted (`!advanced_material_editor, nativeloader, remixbinary`), modules, Remix mods and data folders from the journal and none of the other package's, the last step, four buttons |
| `stale`, `no-state` | a state from another game (an hour old) or none: the window, without a reason |
| `click` | Open the release page opens the latest release and keeps the window; Copy these steps puts the steps and the page on the clipboard and says Copied; Don't show this again writes `dismissed` and closes |
| `no-journal` | without the journal: the main folders by name and the uninstall steps on GitHub, no lists |
| `window-paths` | the window writes nothing outside `nativeloader_companion/` (`..`, another folder) and opens nothing that is not `https://` |

Prints `PASS <scenario>` and exits 0, or stops with the failed check. Run by
[`test_leftovers_popup.py`](test_leftovers_popup.py.md). No side effects.
