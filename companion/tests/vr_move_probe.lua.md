# vr_move_probe.lua

Appended by `vr_move_session.py` to the standard driver's generated Lua. Uses that chunk's local
emit/capture/phase controller. Records named movement milestones from native timeline time:
room walking, hand/head direction, sprint/jump, turns/mouse, physical/toggle crouch (also combined), seating,
calibration, trigger-speed noclip and wall stop; or blink/shift, ledge, invalid target and full fade.
Records go through bounded console JSON to the evidence folder; picture requests go through the
native capture API. Test-only server stage commands set up/reset fixtures. Saves/restores all
changed archived variables before standard teardown/setting comparisons, and removes its hook.
An owned test mover clears physical keyboard/mouse input before L applies timeline input;
the deliberate mouse-delta sample runs afterward. Combined mode offsets the teleport sequence
after all movement samples, with a head-pivot reset and no change to production interfaces.
Milestones sample after L's owned `before_overlay_paint` updater, so pose and crouch/debug values
belong to the same frame even when an image capture stalls. Full-fade capture follows the server's
completed blink, keeping a diagnostic read-back from delaying the movement it is measuring.
No Lua files written into the game and no production scripts changed by the probe. An exception
is a real driver failure; no standalone process exit code.

The one-shot 100-count mouse injection waits for CommandNumber()>0, so a dummy prediction command cannot consume the witness. The -2.2-degree criterion is unchanged.
