# cl_ui_input.lua

Follow-up: a working flat window uses `nlvr.WindowInput` for position/buttons/wheel, without desktop
cursor changes or client VGUI injection. Painted panels retain the dispatcher below. The Aa half of
the flat toolbar requests SteamVR text; native results drain bounded Unicode characters then Enter
into the window. A failed ShowKeyboard opens the owned US fallback keyboard under the target.
Its per-key edits use the same normal field callbacks as native results, with UTF-8 caret positions;
flat characters/keys use WindowInput. Parent close/Exit cancels text, overlays and held input. The
fallback is laser-operated without creating/focusing another VGUI root. The original CLIENT-only
input limitation below describes the initial report and is superseded by this native path.

The working window source returns a third Cursor value. It uses input.SetCursorPos alone, with ordinary
mouse presses/releases: client InternalCursorMoved recentres GameUI's cursor and misses the HTML menu.
Painted client VGUI keeps its existing dispatcher. MouseOwned covers cursor warps and 50 ms after restoration;
the ui module clears synthetic command mouse deltas before L's turn mover. This prevents cursor positioning
from rotating the play space.
This is not a claim that CLIENT input drives MENU/HTML. Corrected live probes keep the menu visible before
each press and show that a native/MENU input extension is still required. The report retains that failed
acceptance. Painted client VGUI input is proved independently.

Text focus checks the engine TextEntry class and IsMultiline (other panels expose native methods too).
Keyboard results call OnTextChanged and OnEnter where appropriate, use a UTF-8 character caret, and tolerate
callbacks closing/removing their own field. The ui mover clears both primary and secondary attacks.
Focus changes wait for the previous native keyboard's closed event before opening another, so a delayed
close cannot cancel the new field. Numeric fields reject invalid/nonfinite text. Mirroring retains the old
physical trigger's claim until release. Native keyboard failures have an exact detail in debug/page status
and an eight-second translated-context notice on the painted panel.

Laser-to-pixel conversion, per-frame claims, trigger capture and scroll repeat through engine VGUI cursor/press/release/wheel dispatch. Capture survives a ray miss. Save the desktop cursor on entering interaction, retain the virtual cursor through hover/drag, then restore on leaving the panel, closing or Stop; errors restore it too. Restoring between press and release would itself move captured sliders. Context-world clicks outside the canvas still use the hand ray and claim the trigger. The ui mover removes claimed IN_ATTACK. SteamVR keyboard opens on text-entry focus, with native_event delivered by the page's sole reader; late events after close are ignored. Inputs: context, panel adapter and native keyboard API. Outputs: VGUI events and plain debug values. No file/setting writes; no process exit codes. Tests: companion/tests/vr_ui_test.py.

Painted cursor dispatch binds the canvas-local CursorPos route after InternalCursorMoved, and again after a mouse press can change the hovered control. No desktop focus is required for the active Derma drag to follow its controller. Capture/release and window input semantics are unchanged.

Background mouse capture can omit OnCursorMoved despite accepting the press. The input router observes that callback on the actual pressed widget during InternalCursorMoved; only if absent and controller pixels changed does it deliver the original stock callback with canvas-local coordinates. It never sets widget values, never duplicates an observed native move, restores the observed method, and leaves native window/keyboard paths alone.
