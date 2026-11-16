# leftovers_window.lua

[ADR 0235](../../../../docs/decisions/0235-a-window-when-rtx-is-left-without-its-loader.md): the window that tells a
player RTX Remix is left in the game without its loader. Client only. One window, two forms, from a spec whose text is
already in the player's language:

- **The long form**, shown by [`nativeloader_leftovers_popup.lua`](../autorun/client/nativeloader_leftovers_popup.lua.md)
  while the package's files are still in the game: the explanation, a recommended section and a by-hand section, and
  four buttons.
- **The short form**, sent by the server's [`nativeloader_leftovers.lua`](../autorun/server/nativeloader_leftovers.lua.md)
  after it removed the package: two paragraphs and OK.

```lua
local window = include("nativeloader/leftovers_window.lua")
window.Show({
    title = "...",
    paragraphs = { "...", "..." },
    sections = { { heading = "...", lines = { "...", "..." } } },
    buttons = {
        { text = "...", url = "https://..." },                       -- opens the page; the window stays
        { text = "...", copy = "...", copied = "..." },              -- puts the text on the clipboard
        { text = "...", dismiss = "nativeloader_companion/x.txt" },  -- remembers, then closes
        { text = "...", close = true },                              -- closes
    },
})
```

- **Self-contained.** No `include`, `require` or translation: the server reads this file before it removes the
  package and sends its source to the client as Lua, because the client's own copy is gone by then.
- **Look.** A dark rounded `DFrame` with the green accent (`118, 185, 0`) along the top, 760 px wide for the long
  form and 560 px for the short one, at most 660 and 300 px tall and never larger than the screen less 40 px. The
  height follows the text (the labels' heights and margins, the title and the buttons): a wrapped label has its height
  only after its own layout, so the window fits itself on every frame of its first second, after DFrame's own `Think`
  (dragging). The short form has no empty band above its button; the long one scrolls. Sizes scale by `ScrH() / 1080`
  (at least 0.65), as the companion's windows are at 4K. Tahoma fonts made with `extended = true`, so Russian and CJK
  text draws. The title wraps; the text scrolls; the buttons sit left to right at the bottom. `MakePopup` gives it the
  mouse. A second `Show` replaces the window (`NativeLoaderLeftoversWindow`).
- **Buttons.** `url` opens only an `https://` page (`gui.OpenURL`). `copy` calls `SetClipboardText` and, with
  `copied`, relabels the button. `dismiss` writes `dismissed` to that file in the data folder, only under
  `nativeloader_companion/` and never with `..`, then closes. Any other button closes.

Tested by [`tools/tests/test_leftovers_popup.py`](../../../../tools/tests/test_leftovers_popup.py.md) (and, as the
server sends it, [`test_leftovers_lua.py`](../../../../tools/tests/test_leftovers_lua.py.md)).
