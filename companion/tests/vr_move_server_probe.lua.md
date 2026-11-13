# vr_move_server_probe.lua

Test-only admin-console server fixture, injected through the existing acknowledged console transport
by `vr_move_session.py` while owning the PoC/VR locks. Runs only in the private PoC session. Registers
`nlvr_L_stage` for local single-player/listen host: reset, existing-noclip test, the stock spawn-area BSP wall,
mantle ledge, low ceiling, sample and cleanup. Never grants privileges in production code.
Uses stock hunter prop models; every prop is owned and removed on clear/cleanup.
Selects open map ground by standing-hull sweeps before distance/teleport tests; the stock spawn
corridor is too short for those tests. The wall sample starts at x=984 facing its x=1024 BSP wall,
then returns to the open fixture to check that blocked room input does not replay.
Logs move data, velocity, crouch/ground state and L's authoritative movement state at 5 Hz as console JSON.
Cleanup removes its hook and command. No file writes, no Steam settings, no outside process access.
Exceptions remain visible as Lua failures to the standard driver.
