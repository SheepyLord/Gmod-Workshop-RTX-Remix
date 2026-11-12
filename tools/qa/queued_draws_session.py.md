# queued_draws_session.py

RTX sessions on the PoC for the RTX fixes' queued-draws patch
([ADR 0192](../../docs/decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md)): a stress session that
creates and removes props, gibs, client models and doors in view, which crashed the game with the fixes before the
patch, and a still scene for before/after captures of prop lighting. It runs each package given, holds the PoC lock
for the whole series, and restores the PoC at the end.

```powershell
# from a worktree with a Release loader build (tools\build.ps1 -Config Release); packages built with build_package.py
py -3 -I tools\qa\queued_draws_session.py --evidence <main checkout>\out\queued-draws\run1 `
    --before out\queued-draws\packages\before.gma --after out\queued-draws\packages\after.gma --seconds 600
py -3 -I tools\qa\queued_draws_session.py --evidence <same folder> --rollback   # after an interrupted series
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's or the main checkout's `out` |
| `--before`, `--after` | The local packages (`.gma`) to run, in that order; either may be left out |
| `--modes` | `lighting` and/or `stress` (default both, lighting first) |
| `--seconds` | Stress duration per run (default 600) |
| `--repeat` | Stress runs per package (default 1) |
| `--shots` | Seconds between stress checkpoint screenshots (default 60) |
| `--per-frame` | Client models (`ClientsideModel`) created and removed per frame (default 0). Eight a frame ended both packages' sessions after 204-237 s in an engine `Error()`, `CUtlMultiList overflow! (exhausted index range)` (exit `0xC0000409`, a fail-fast in `engine.dll` from a Lua call), about 120,000 client models in: an engine limit, not the fixes' crash |
| `--console-churn` | Stress: up to this many characters of console text a frame, `NLQD_PAD` lines (default 400; 0 none). The crashed VR sessions printed long base64 packets, and the heap blocks next to the freed entity held that text; `poc_session.py` re-reads the whole log four times a second, so keep it modest |
| `--settle` | Lighting: seconds before the first capture (default 20) |
| `--distance`, `--camera` | The scene's distance from the camera (220 units) and the camera, `x,y,z,pitch,yaw,roll` (default gm_construct's VR fixture eye, `823,-657,-40`, 8 degrees down, facing west) |
| `--queue-mode` | The session's `mat_queue_mode` (default 2: queued rendering, the game's default on a multi-core machine) |
| `--fps-max` | The session's `fps_max` (default 0, uncapped, as `vr_session.py` runs): the main thread then reaches the next frame's deletions while the render thread is still drawing the last frame |
| `--load` | Stress: frozen citizen ragdolls behind the scene (default 24). With `r_forcehwskin 0` studiorender skins them on the CPU, on the render thread, so each frame's queued draws take longer, as the crashed VR sessions' skinned hands made them |
| `--width`, `--height` | The window (default 1600x900) |
| `--timeout`, `--hang-grace` | Map start deadline (900 s: a fresh deployment unpacks the package) and `poc_session.py`'s hang grace (180 s) |
| `--lock-timeout` | How long to wait for `out\r10\poc.lock` (4 hours) |
| `--keep-copies` | Keep the PoC's moved originals and the snapshot's copies after a verified restore |
| `--rollback` | Restore the PoC from an interrupted series' evidence |

## What it does

1. Takes the main checkout's `out\r10\poc.lock` (the VR driver's `ExclusiveLock`, task `queued-draws crash repro
   (fixes)`), refuses to start while a PoC game runs, records the hashes of every `user.conf` (they must not change),
   writes `plan.json` (runs, options, package hashes) and snapshots the install
   ([`field_snapshot.py`](../field_snapshot.py.md) `snapshot --manifests-from` the field install), then moves the
   PoC's loader state, add-ons, data, settings, Lua modules, Remix mods, logs and captures and the bootstrap into
   `originals\` ([vr_session.py](../vr_session.py.md)'s `preserve`).
2. Per package: [`poc_session.py`](../poc_session.py.md) `install` (the first) or `config` with `--allow-local` and
   `--remix on`; then per mode a `run` on gm_construct with `--addons`, `-insecure`, `+mat_queue_mode`, `+fps_max`,
   `engine_no_focus_sleep 0` (an unfocused window would sleep between frames; `poc_session.py` restores the field's
   settings at the quit), the player in noclip at the camera, the server script ([queued_draws_server.lua](queued_draws_server.lua.md)) as `lua_run`
   console lines, `--camera`, `--hide-hud`, the probe ([queued_draws_probe.lua](queued_draws_probe.lua.md)) with its
   settings and `--lua-shots` (the run's length plus 120 s). Both scripts are written into the run's folder as sent.
3. After each run: the `poc_session.py` record's exit, quit, failure, crash reports and declined crash prompts, the
   Windows Error Reporting dumps written since the run started that no earlier run of the series took
   (`H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\_debug_tools\hangdumps\wer`, read only, copied into
   `<run>\wer\`; after an abnormal exit it waits 20 s first, since WER finishes a dump after the process is gone),
   and whether it crashed, in `results.json`.
4. Restores the PoC (vr_session's `restore`: the originals back, the snapshot's rollback verified clean), checks the
   `user.conf` hashes, deletes the bulk copies unless `--keep-copies`, and prints one line per run.

The crash's own signature is read from a dump with the tools in the crash evidence (`dump_ip0.py`, `sym.py`; see
[RESEARCH.md](../../docs/RESEARCH.md), "The fixes' crash on the queued render thread"): return address
`gmcl_RTXFixesBinary_win64.dll+0x41605b` for the module before the patch.

## Side effects, requirements, exit codes

Writes the PoC (restored at the end), the evidence folder and the lock. Reads the WER folder. Needs Windows, a
Release loader build in this checkout, Pillow (screenshots) and a free PoC. Exit 0 when the series ran and the PoC
was restored, whether or not a run crashed (`results.json` says); an exception (a refused step, a failed restore)
ends it with Python's exit 1 and leaves the evidence for `--rollback`.
