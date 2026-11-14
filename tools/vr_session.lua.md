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

V2/F inventories nlvr.* hooks, the client NLVR global and receiver as well as the existing page hooks. All fifteen new settings join the restoration inventory. Samples include plain NLVR.Debug and dominant-hand values. Server lifecycle logs supply actual active state, owned hook count, permanent receiver and accepted/dropped sync counters in the same console evidence. GMod blocks lua_run requested from client Lua, so the probe never attempts that call or adds a cross-realm test receiver.

Integration: wraps Capture to emit a bounded overlay-roles record mapping handles to NLVR overlay keys and native metadata for each request; restores the wrapper at Exit. This also labels feature fixtures that request their own captures.

Flat controls emit a flat-window interval summary at the requested duration, request the final
screenshot, then hold the fixed camera another three seconds before cleanup. The timed window
therefore excludes screenshot/cleanup work and the image precedes camera-hook removal.

After S, setting baselines also include all four archived V4 scaffold options.

Each manifest also records semantic kind (wrist/panel/window/keyboard/marker/comfort), declared source extent and actual window aspect. Handles remain decimal strings to avoid uint64 precision loss.


Review correction: capture manifests rebuild from currently live logical handles each capture, rather than retaining destroyed handles or querying nil handles. Retired roles can safely reappear with new native IDs.


Samples read the live wrist role, rather than the most recently created possibly retired handle. Capture manifests rebuild from live handles at every request.


Q3 dispatch uses a private tested capture queue. Semantic inventories are recorded at actual dispatch; visible targets wait through two frames after creation. Stop rejects undelivered captures. No game/native product or SDK settings are changed.


Inventory includes wanted logical overlays without native handles. expected_roles derives from wanted roles and the configured wrist HUD even if its module never allocated a handle; capture dispatch retains these requirements.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

The one-second flat-selector settlement is shared by look, native test_quit and the second Stop. Native quit resumes the game UI before waiting so flat rendering can refresh the cache.


The paused test_quit branch enforces its25-second native deadline even after the page reports off.

V8: scripted sessions (neither `look` nor `live_poses`) hold the requested fixture yaw once per VR start
(`hold_fixture_yaw`, from the PreRender hook): as soon as the core has a play-space yaw, a priority -30 mover on the
move module clears physical mouse X/Y before the move module (priority 0) can turn the room with it, and the room is
turned so the camera faces `CONFIG.camera`'s yaw; a `fixture-yaw` record notes the turn. Desktop mouse input had moved
the room 0.484 degrees (22 counts at `m_yaw` 0.022) in `quality-sim-03`, past the 0.5-degree neutral check. The hold
sits outside the CreateMove block that the moving drivers replace.
