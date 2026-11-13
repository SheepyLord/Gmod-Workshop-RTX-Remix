# vr_move_motion_server.lua

Private server instrumentation injected alongside the existing admin-console fixture. Records every
FinishMove origin, velocity, mode, game tick/time and same-process SysTime in eight-row console
batches, below Source's line bound. `nlvr_motion_done` flushes and removes its hook/command. No
extra network messages compete with FOLLOW, so instrumentation does not alter its cadence.
No file, Steam or production state changes. Errors remain visible to the standard test driver.
