# V4 adapter tests

Run through unittest discovery or the Release gate. Pure layout/calibration tests
check physical action swapping, mirrored locations, retained declared world hand
rotations, involution, and separation from camera/eye fields. No game, SDK, SteamVR,
filesystem override or external service is used. Exit 0 on success.

V8: `test_prepared_probe_keeps_the_room_yaw_and_clears_physical_input` prepares the real probe for the weapons, reload
and tools roles and runs the adapter's Think hook under LuaJIT: it must not turn the room and must register one mover
that clears movement, buttons and mouse. It fails against V4's adapter.
