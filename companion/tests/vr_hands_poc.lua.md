# vr_hands_poc.lua

Test-only fixture prepended by [vr_hands_poc.py](vr_hands_poc.py.md) inside the generated probe,
after its local CONFIG. Never deployed as add-on Lua. Finds a vertical map brush wall, sets the
camera 0.65 m from it and asks the wrapper's temporary host-only command to position the player.
Tracks the production c_arms entities for read-only matrix/skin/body receipts. Optional legacy
mode supplies curls at the native timeline's times because V1 cannot parse skeleton actions.

PreRender changes only ghost/dominant settings and the test player's model at timeline phases.
It waits for a non-nil TestState during asynchronous real SDK startup, including the second cycle.
`handsTestRecord(label)` returns plain matrix/debug evidence, target/shown coordinates, measured
head-wrist distances in metres, actual manipulated thumb angles and the dominant mapping for the probe transport;
`handsTestStop()` removes the test hook, restores wrapped functions and queued setting strings,
and emits a small `hands-cleanup` receipt with created and still-live model counts.
No game files, SDK settings or targets are written; durable output belongs to the standard driver.
Errors propagate to the probe/session; no standalone command or exit code.
