# stuck_drag_harness.lua

Runs the companion's stuck-drag fix (`companion/nativeloader/lua/autorun/client/nativeloader_dragdrop.lua`, R25)
against a mocked GMod drag and drop: `dragndrop` with `Clear` and `StopDragging` as GMod's, `FrameNumber`, a panel tree (world, spawn
menu, canvas, icon) with `IsVisible`, `GetParent` and `MouseCapture`, `vgui.CursorVisible` and `input.IsMouseDown`.
Arguments: the Lua file, a scenario. Each scenario runs the `Think` hook and compares the calls it made:

| Scenario | Expected |
|---|---|
| `idle` | nothing dragged: no call, the cursor's state is not even read |
| `hidden_cursor` | the spawn menu closed with the icon held: `StopDragging`, the icon lets the mouse go; a second run does nothing |
| `visible` | a drag inside the open spawn menu, button up or held: nothing |
| `hidden_panel` | the cursor still visible, the spawn menu hidden, the button up: ended after two frames, not before |
| `hidden_then_drop` | the source panel hidden in the frame GMod drops the icon: the drop stands, nothing is cancelled |
| `stop_error` | another add-on's `OnStopDragging` fails: reported once, `dragndrop` still cleared and the mouse let go |
| `hidden_panel_held` | the spawn menu hidden, the button still held: nothing (GMod may still drop it) |
| `drop_menu` | a right-drag's drop menu is open, even with no cursor: nothing |
| `watch` | a press not yet a drag when the menu closed: `Clear` and the mouse let go |
| `removed_panel` | the dragged panel was removed, cursor visible: nothing (GMod paints no invalid panel) |

Prints `PASS <scenario>`; any difference is a Lua assertion (nonzero exit). Writes no files and launches no game.
Run by [`test_stuck_drag.py`](test_stuck_drag.py.md).
