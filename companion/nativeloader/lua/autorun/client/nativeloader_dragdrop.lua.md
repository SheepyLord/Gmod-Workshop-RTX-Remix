# nativeloader_dragdrop.lua

RTX-only client fix (R25) for a spawn-menu icon that stays painted on the screen for the rest of a session.

**The cause.** GMod's drag and drop (`lua/includes/extensions/client/panel/dragdrop.lua`) ends a drag only when the
dragged panel receives the mouse release (`DragMouseRelease`); its own check that ends a drag once no mouse button is
held is commented out. When the spawn menu closes while an icon is held (Q released before the mouse button, or a click
on an icon that moved the mouse 20 pixels first), the release goes to the game, the drag never ends, and GMod's
`DrawOverlay` hook `DragNDropPaint` keeps painting the icon (a 128-pixel content icon, with the NPC-weapon badge for a
weapon) at the last cursor position. The user saw an "M249 SAW" card in the middle of the left half of the screen.
Clicking any spawn-menu icon once ends such a drag in a running game (`DragMousePress` stops a drag in progress).

**The fix.** A `Think` hook (`nativeloader_stuck_drag`) does nothing unless a drag, or a press that may become one
(`dragndrop.m_DragWatch`), is in progress. It ends it when either:

- no cursor is visible (`vgui.CursorVisible()` is false): nothing can receive the release any more; or
- the dragged panel or one of its parents is hidden and the drag's mouse button is not held, for two frames in a
  row (the spawn menu can hide the panel a drag comes from in the frame the game delivers its drop).

A right-drag waiting on its drop menu (`m_DropMenu`) is left alone. A drag is ended as GMod ends one,
`dragndrop.StopDragging()` (the receiver's `DragHoverEnd`, each panel's `OnStopDragging`, `dragndrop.Clear()`); a
pending press only gets `dragndrop.Clear()`. Either way the panel that captured the mouse lets it go
(`MouseCapture(false)`). If another add-on's `OnStopDragging` or `DragHoverEnd` fails, the error is reported once and
`dragndrop.Clear()` still runs, so the hook never meets the same drag again.

Inputs: GMod's `dragndrop` table, `vgui.CursorVisible`, `input.IsMouseDown`, `FrameNumber`. Outputs: none besides ending the stuck
drag. No files, convars, network or server changes; no process exit code. Tested by
[`tools/tests/stuck_drag_harness.lua`](../../../../../tools/tests/stuck_drag_harness.lua.md).

Only in this machine's RTX starts ([ADR 0206](../../../../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md)): its first line of code returns when `NativeLoaderRTXStart()`, set by `!!!!nativeloader_engine_guard.lua`, says the loader did not activate RTX (a start through an off switch, a removed loader, files a loader left behind).
