# vr_session.lua

In look mode the preview is text only. No NL_SHOT is requested, so neither a missing Pillow
installation nor a desktop capture failure can shorten the look. The SysTime limit and
nl_vr_demo_done own normal completion; they stop VR and wait for off before NL_SHOT_DONE.
SteamVR stopping on its own does not set lookEnding. Completion before the first baseline
sample also works: an absent before table is treated as empty while saved probe variables restore.

The explicit first_camera_mismatch test shifts published metadata for five seconds while leaving
the real view alone, then restores normal publication. It records both boundaries and requires
initial skipped cameras rather than allowing an unmatched first output. Normal runs omit it.

Flat controls temporarily own the CalcView hook table, then restore its previous table. GMod stops
at the first returned view in undefined hook order; an exclusive fixture guarantees the requested
90 degree projection. Samples record the fixture call count and projection. Automated
CreateMove also holds the requested angles and clears input; manual look mode keeps user input.
The flat-before screenshot is taken while the fixture is active. Flat-after is dispatched beside
cleanup and can show the restored camera instead; use flat-before for projection/image comparisons.

The probe records gmod_mcore_test and startup installation stages. A synchronous probe-ready
record is separate from PreRender samples. Expected runtime failures can occur after frames
start; their exact text is checked and SDK/flat cleanup finishes before success is reported.
Automated runs pin CreateMove angles and clear movement/buttons so external input cannot change
the fixture before play-space yaw is latched. The neutral capture checks that yaw. Manual --look
keeps ordinary input available. Probe cleanup removes the test input hook.

The second review records mat_queue_mode's declared default and requested session mode. A
no-scene/resume run requests a deferred capture during the pause; it must reach traced output
after resumption. The driver checks every requested capture for both eyes, centre/depth,
mirror, overlay and timing files. An Exit-while-paused run does not request this deferred capture.

Review follow-up: PreRender drives this controller while SP is paused. --test-quit opens the
escape menu and records CurTime before/after the native wall-clock quit. Capture and timeline
arguments are names under the launcher-selected native data root. Start uses the real page
function. Seven negative assertions precede Start: removed path keys, capture escapes and the
removed serial mode. Historical comparison packages use their retained probe/source.
The before/after baseline waits for the queued clear/noon fixture convars to latch, avoiding
a cold PreRender callback sampling their old values before the console dispatch runs.

Long JSON records travel in numbered base64 packets of 1600 characters: Source truncates
console lines at 4095 bytes. The driver requires every chunk and rejects truncated/duplicate
evidence. Smaller records retain the plain NLVR_Q JSON format.

Manual preview (`CONFIG.look`) waits for the user's Start/Exit page actions without scripted
poses. `nl_vr_demo_done` or the configured timeout requests Stop, waits for acknowledged off,
then ends the driver's screenshot loop. An exit-paused fixture holds RenderScene suppression
through Stop and releases it before the flat-after screenshot. Native overlay diagnostics are
read directly from SteamVR when available; no visibility/transform value is fabricated.
CONFIG.camera supplies the baseline position/angles and near barrel; the player is held at that
floor by the driver fixture. Saved sky hour/follow-map settings are restored by the probe.
The variable dump compares Source convars. Separate live GetUpscalingState snapshots compare
upscaler/frame-generation selectors/support flags when ready; file-only GetConfigVariable is
not live evidence. Every sample retains the production status text, including the FPS-cap warning.

Client Lua acceptance probe injected by `vr_session.py` with a JSON CONFIG prefix. Uses the real
`nl_vr_start` / `nl_vr_exit` page commands, native Info/TestState/Capture, a deterministic flat
camera and fixed clear/noon sky. Exports samples, phases, frame-interval statistics, actual HUD
values, convars, hook/timer inventory and final checks as `NLVR_Q` JSON console lines. Desktop
shots use the standard driver's `NL_SHOT` handshake. Runtime captures go only into CONFIG's
repository out/ folder. Optional scene pause suppresses RenderScene for five wall-clock seconds;
optional active shutdown leaves VR running for the driver's ordinary quit.

Starts/exits twice, checks native off acknowledgement, restores diagnostic wrappers and saved
Lua convars, and removes its own hooks. It never writes engine convars (fps_max is supplied by
the driver on the launch command line), user.conf, SteamVR settings or game data. It removes
the loader update/guide frames visually without changing reminder preferences. The server
fixture changes the test player's health, armour and weapon ammo for an observable wrist update.
The test registers a session-local server command from the physical console for that fixture;
client Lua does not attempt the blocked lua_run command. A client-only barrel supplies known
near geometry, and a magenta desktop-only HUD witness makes the 2D/eye boundary visible.
Use only through the driver; success/failure are in emitted JSON, not a process exit code.
