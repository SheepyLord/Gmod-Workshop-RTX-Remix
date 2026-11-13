# vr_move_motion_probe.lua

Private `--case locomotion` probe. Wraps actual CalcView and batches per-rendered-frame camera,
LocalPlayer:GetPos(), core C.Feet, optional GetNetworkOrigin, mode, SysTime/CurTime and FOLLOW
debug state. Physical head stays still. Clears physical keyboard/mouse only through an owned test
mover. At timeline 11.2 s it resets the private fixture and enables its flight test; cleanup removes
both the wrapper and server fixture. No production movement setting or game file is changed.
Use through the shared-lock snapshot driver; exceptions fail its normal Lua-error acceptance.
Optional FROM/OFFSET values append this probe after the existing movement/head sequence in the
single final Index run. Its wrapper composes with the head probe and restores in reverse order.

Optional M_FLIGHT_AT schedules the focused two-second-sprint fixture; original callers keep 11.2 seconds.

Motor samples now observe actual RenderScene arguments once per frame without mutating the CalcView registry or hook functions. Cleanup removes the observer; motor/roll/smoothness bounds and the native-wall timeline are unchanged.
