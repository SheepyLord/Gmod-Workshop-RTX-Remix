# nativeloader_vr.lua

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
