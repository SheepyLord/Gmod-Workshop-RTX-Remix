# 0264: Hide the debug windows and stay in debug mode

- Status: Accepted 2026-11-24 (the user's request: "Also address a QoL for mmd motion player debug, allow user to hide
  all the debug menu (motion and camera) but keep in debug mode, so user can take screenshot or move.").
- Package only: the Advanced MMD Animation Player, the package's `character-motion-importer` part
  (`mmd_vmd_npc/lua/mmd_vmd_npc/cl_menu.lua`, `sh_core.lua`'s catalogs, the tool's panel
  `lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua`). No `winmm.dll` change.

## Context

Debug mode is the motion debug window (`MMDVMDNPC.DebugFrame`, "Raw Animation Debug": the bone and flex lists, the
timeline, the preview's buttons) and, when its Camera preview box is ticked, the camera debug panel
(`MMDVMDNPC.CameraDebugPanel`). The debug window is a Derma popup (`MakePopup`): while it is on screen it holds the mouse
and the keyboard, so the player can neither look around nor walk, and both windows are in every screenshot. Closing it
ends debug mode: the client tells the server (`mmdvmd_debug_close`), which drops the held expression and puts the
target back in its reference pose. There was no way to keep the pose shown and have the screen to oneself.

## Decision

1. **A Hide windows button** in the debug window's button strip (beside Next) hides both windows: `SetVisible(false)`,
   not closed, nothing sent to the server. Debug mode stays as it is: the held pose and expression, the frame shown, a
   preview that plays (its timer keeps stepping), the camera preview. A hidden popup holds neither the mouse nor the
   keyboard, so the player moves, looks around and takes screenshots.
2. **What shows them again**, where they were:
   - the context menu's key (`OnContextMenuOpen`, C by default), the usual "give me the mouse" key in Sandbox;
   - the player's own key, `mmd_vmd_npc_debug_panels_key` (none by default; set in the tool's Advanced tab beside Debug
     Selected Motion, as the camera's and the HUD's keys are), which also hides them; not while a text field has the
     keyboard, the chat is open or the game's menu is up;
   - the console command `mmdvmd_debug_panels` (`0` hides, `1` shows, nothing toggles);
   - opening debug mode again from the tool, the motion window or the console (`MMDVMDNPC.ShowDebugMenu`). The debug
     window's own steps (its buttons, the timeline, a playing preview) still go through `MMDVMDNPC.OpenDebugMenu` and
     leave the windows hidden.
   The debug window takes the mouse and keyboard again when shown (`MakePopup`); the camera panel is a plain window
   beside it, as before.
3. **The player is told how to get them back**: a notice for six seconds when they hide, and the button's tooltip, name
   the key (the player's own if set, else the context menu's as bound, else the console command).
4. **Texts in all nine catalogs** of the add-on (en, zh, zh-tw, ja, ko, fr, ru, ar, es).

## Consequences

- A debug pose can be framed from any side and captured without the windows; the HUD is the player's own choice as
  before (the add-on's HUD hiding is for camera motion).
- A screenshot taken at once includes the notice; it is gone after six seconds.
- Derma does not run a hidden panel's `Think`, so the debug window's bone and flex lists wait while it is hidden and
  catch up when it is shown (the pose itself follows every answer, as during a timeline drag).
- Tests: `test_motion_tab.py`'s `debug_windows` scenario under LuaJIT, and `mmd_player_session.py --debug-windows` in the
  PoC (the mouse back to the game while hidden, debug mode and the pose unchanged on the server, screenshots).
