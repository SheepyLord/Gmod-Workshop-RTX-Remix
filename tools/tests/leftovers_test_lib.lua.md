# leftovers_test_lib.lua

Shared by [`leftovers_harness.lua`](leftovers_harness.lua.md) and
[`leftovers_popup_harness.lua`](leftovers_popup_harness.lua.md) (ADR 0235). Loaded with `dofile`; returns a table:

- `encode(value)` and `decode(text)`: JSON as Garry's Mod's `util.TableToJSON` and `util.JSONToTable` write and read it,
  for the companion's tables (strings, numbers, booleans, arrays, objects with sorted keys; `\uXXXX` escapes decoded
  to UTF-8). `decode` returns `nil` for text that is not JSON.
- `fakeVgui()`: a `vgui` stand-in and a record. `vgui.Create` and `panel:Add` make panels that keep their class,
  `text`, `font`, `dock`, `children`, `valid` (`Remove`) and `popup` (`MakePopup`); every other method is accepted and
  ignored. `record.frames` lists the windows made, `record.texts(panel)` every label's text under a panel, top to
  bottom, and `record.buttons(panel)` its buttons, whose `DoClick` a test can call.

No side effects. Pure Lua for LuaJIT.
