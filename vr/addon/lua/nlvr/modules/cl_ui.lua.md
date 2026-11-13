# cl_ui.lua: VR menus and panels

Active-session composition of panels, pointer and overlay laser. Off-hand B toggles the wrist menu; logical roles mirror with dominant hand. `NLVR.Emit("ui_toggle", name)` toggles wrist_menu/spawn/context/flat/settings. Native events come from the page's sole Events reader. `NLVR.Debug.ui` contains panel handles/sizes, laser UV, last click, drag, keyboard and window-source state. The framework owns subscriptions, the GUIMousePressed hook and the attack-suppression mover. Stop releases input/keyboard, restores borrowed panels and destroys overlays. No files, idle hooks or engine settings are written.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

A mover at -1000 clears synthetic mouse deltas during UI interaction before movement's mouse turning;
the later mover suppresses both primary/secondary attacks for a claimed trigger. Off installs neither mover.
# Follow-up

The UI debug inventory includes the fallback keyboard's owned overlay, while it is open.

Q review reuses Debug.ui.panels, cached panel/keyboard rows and laser data across frames after the reviewed M follow-up; no debug hierarchy is rebuilt each frame.


Review correction: after deferred panel actions, return immediately if wrist Exit synchronously stopped the core and removed Debug.ui.
