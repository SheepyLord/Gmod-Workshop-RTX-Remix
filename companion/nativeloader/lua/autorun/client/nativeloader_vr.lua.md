# nativeloader_vr.lua

V2/M adds the fifteen framework settings to the page and reusable BuildOptions for its VR panel: comfort,
dominant hand, HUD, gloves/climbing/melee. Calibrate emits `height_calibrate` to L while active;
OpenBindings calls the native binding UI only during running VR. No console-variable declarations changed.
The sole native.Events reader forwards events through NLVR.Emit("native_event", event), so the UI can own
keyboard results without stealing quit/dashboard events. UILabels marks the add-on's phrases in the companion
catalog. New phrases in all six languages are reproducible with companion/i18n/vr_ui_catalog.py.
The status text includes the UI's exact native keyboard failure detail without failing the running VR session.

The page requires runtime wire API 3, which adds explicit focus-loss and wait-error counters.
An older runtime receives the existing update/restart explanation. The Lua API is still version 1.

Review follow-up: lifecycle polling is an active-session PreRender hook gated by RealTime;
it runs with SP paused. Off removes the hook, preserving no idle polling. Native nil/error
results are read and stable errors logged once; ten failed polls stop with the reason. SDK-ready
installs the producer without waiting for traced output. Recentre VR/nl_vr_recenter requests a
fresh yaw/standing-XY anchor on the next new pose. Controller turning/movement remain V2.

V1's VR category/page in the RTX Remix tab, and `nl_vr_start` / `nl_vr_exit`. Client only. At initial load it
registers its menu builder, commands and three archived **VR-owned** settings. No module, OpenVR, add-on, frame
hook or timer loads before a request. Opening the page does not require the module; **Check status** explicitly
requires it and calls the API-v1 `Probe`, which must not load OpenVR. Start alone calls `Start`.
Checks the native binary's presence first: GMod otherwise logs a script error from require's Lua fallback even
when pcall catches it. A missing package gets just the page's translated help and its English console line.

Usage: open RTX Remix > VR > VR settings, or use the commands in a local game. For integration tests,
`nl_vr_start <timeline-name>` passes a logical name to the module's fixed data root. The launcher
can select its environment-only test root; no Lua argument may select a path.
`NativeLoaderVR.Start(options)` also passes the integration driver's `timeline`/`no_submit` options through. It
owns `scale` and `render_scale`. All native functions are the work plan's `nlvr` API. The page polls state
and events every 0.1 s only during a session; includes `nlvr/client.lua` after `Info().sdk_ready`, before the
runtime's first frame. This producer bootstraps that first frame. Stop removes the view immediately and
keeps only its render-based state poll until the module acknowledges off (SDK unloaded), then removes the poll hook and
shutdown hook. An unfinished start can be cancelled. Failed includes/initialization/frame
callbacks also clean up. Shutdown/hot reload stop the session.

Inputs: `native-loader/status.json` (`DATA`, schema 1), module probe/info/state/events, local player/listen-host
status, `g_VR.active`/`vrmod.IsPlayerInVR`, the translation module, `nl_vr_scale` (40 units/m), `nl_vr_fov` (145,
tested on the Index at 16:9), `nl_vr_render_scale` (1.00, matching the native default/recommended size). Tier `low` or known positive VRAM below 12288 MiB warns without
blocking and caps the start scale at 0.50. Unknown/invalid memory does not imply a low-memory GPU.

Outputs: translated page, English console errors including the exact native error. `NativeLoaderVR` exposes
`state`, `detail`, `reason`, last `probe`/`info`, `Start`, `Stop`, `CheckStatus`, `GPUWarning(status)` and
`StatusText()`. No file/config writes. Module/runtime errors get actionable translated help; native error names
and Vulkan extension names remain exact. `Info`'s headset `model`, `refresh`, `eye_width`/`eye_height` and runtime
`rtxvr_Status` fields are displayed. Detail fields confirmed by Claude's VR-D interface review: `devices.left/right`
(tracked booleans), `compositor_gpu_ms`, `compositor_cpu_ms`, `presents`, `reprojected`, `dropped` (cumulative).
Missing measurements display `?`, never fabricated zeroes. Exit statuses are Lua return values, no process exit.
When the FPS cap is below the measured refresh rate, the translated status says exactly what fps_max command
to type in the game console. Lua never changes that blocked engine command.
Slider titles always use a full-width help line: GUI Scaler enlarges fonts after the page builder runs but
leaves Source's fixed slider-label width, so even short English labels would otherwise be cut off at 4K.
The label's refresh checks every ancestor's visibility: Panel:IsVisible alone ignores hidden parents, so a
cached page under a closed spawn menu must not keep reading loader status. The offline idle case covers that.

Offline coverage: [test_vr.py](../../../../tests/test_vr.py.md). Integration details and evidence are in
[VR-V1-E-report.md](../../../../../docs/handover/VR-V1-E-report.md).

V2/F adds one dormant block creating the fifteen archived V2/V3 settings with help and ranges. The add-on reads them only at Start and owns/removes callbacks while active. Height uses the engine range 0..2.2, with the disjoint 0 or 1.2..2.2 rule normalized by the core; no engine setting is written. Page layout and translated phrases are unchanged.
# Task M follow-up

Marks the fallback keyboard's title and action labels for the existing companion translation namespace.

Integration: help explains session ai_serverragdolls and calibration requiring another Start; StatusText displays the restart notice only for Move.calibration.restart. Catalog text is generated by companion/i18n/vr_integration_catalog.py.
V4/S adds four archived declarations and a Weapons group: physical reload, foregrip and ammo counter (default 1, 0..1), and gun pitch (default 0, -45..45 degrees). Three check boxes and one slider each have a help line; the slider follows the page's full-width title/empty-label style. Nine phrases in six languages are reproduced by companion/i18n/vr_weapons_catalog.py. No new dormant polling or native loading.


Review correction: VR help directs the player to turn on Keep corpses in the game options for grabbable NPC bodies. VR never changes or restores ai_serverragdolls; all six catalogs carry this text.


Numeric settings sliders suppress redundant numeric echoes from their scratch/text controls, preserving the player's original convar spelling until an actual numeric edit.

Single-player only ([ADR 0197](../../../../../docs/decisions/0197-vr-is-single-player-only.md)): Start refuses every game that is not single-player, the listen-server host included, with "VR works in single-player games only. Start a single-player game to use VR."; the console help says the same.

V6 ([ADR 0199](../../../../../docs/decisions/0199-vr-auto-quality-ladder.md)): Start needs runtime API 4 and renders at the ladder step Auto begins from, or the step `nl_vr_quality` pins (`VR.StartStep()`, which loads the add-on's ladder only once VR is requested; `VR.LoaderStatus` exports the status reader). `nl_vr_render_scale` is a ceiling on every step and takes effect at once. The options gain a Quality group (Auto or one of seven steps), shown on the page and in the headset's settings panel; while VR runs the page shows the step, its reason and the measured rate and GPU time against the target and budget, all translated.

V8 ([ADR 0205](../../../../../docs/decisions/0205-frame-generation-in-vr-is-motion-smoothing.md)): the client setting
`nl_vr_frame_generation` (1, the default: Auto holds half the refresh and SteamVR's Motion Smoothing makes the other
frames; 0: VR renders every frame) and its **Frame generation** checkbox under Quality, whose help says Remix's DLSS
frame generation only adds frames to the desktop window and so stays off in VR. The Auto help now names the rate that
switch sets. While VR runs the status says what SteamVR does, from `NLVR.Debug.perf`: Motion Smoothing making frames
now (yes/no), off in SteamVR (with where to turn it on: SteamVR > Settings > Video > Motion Smoothing), not available on
this GPU, or the switch off. Physical interaction gains a help line for turning a held object with the wrist, two-hand
holds and freezing with the trigger ([ADR 0204](../../../../../docs/decisions/0204-the-holding-hands-trigger-freezes.md)).
All new text is in the six companion catalogs.
