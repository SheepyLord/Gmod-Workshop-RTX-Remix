# test_stuck_drag.py

Unit test (R25) for the companion's end to a stuck spawn-menu drag
(`companion/nativeloader/lua/autorun/client/nativeloader_dragdrop.lua`): runs
[`stuck_drag_harness.lua`](stuck_drag_harness.lua.md) with LuaJIT once per scenario (`idle`, `hidden_cursor`,
`visible`, `hidden_panel`, `hidden_then_drop`, `stop_error`, `hidden_panel_held`, `drop_menu`, `watch`,
`removed_panel`) and requires `PASS <scenario>`.

Usage: `python -m unittest discover -s tools/tests -p test_stuck_drag.py` (also part of `tools\test.ps1`). Skipped when
LuaJIT is not installed (`luajit` on PATH or `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`). No files written; exit
code as unittest's.
