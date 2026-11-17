# remix_workers_session.py

Measures the RTX runtime's geometry workers in the PoC for runtime patch 0105
([ADR 0243](../../docs/decisions/0243-the-geometry-workers-sleep-when-idle.md),
[report](../../docs/handover/remix-workers-report.md)): for two packages that differ only in `d3d9.dll`, sessions in
turn, each recording the CPU time of the `geometry-processing(N)` threads and of the game's other threads, and the
frame times in a map.

```powershell
py -3 -I tools\qa\remix_workers_session.py --evidence out\remix-workers\poc-ab --warmup `
    --package A=out\remix-workers\pkg-a\<before>.gma --package B=out\remix-workers\pkg-b\<after>.gma
```

## What it does

1. Refuses an evidence folder that is not new; records the plan and the packages' SHA-256.
2. **One session per lock hold:** before each session it takes `out\r10\poc.lock` of the main checkout by exclusive
   create only (`open(..., 'x')`, the owner JSON with its pid and a random token); while another owner's file exists it
   polls every second, up to `--lock-timeout` (3 h) per session, and never deletes, overwrites or takes over that file,
   however old it looks. After the session it removes the lock only if the file still holds its own pid and token,
   then waits `--gap` seconds (10) so a peer waiting for the lock (another lab, a field run) takes it first.
3. Under each hold: refuses to start while a game runs in the PoC; keeps the PoC's `native-loader\config.json` and
   GMod's video settings (`HKCU\Software\Valve\Source\garrysmod\Settings`, which every GMod install shares) as they
   are now (the first session's copies are saved as `config.json.before` and `video-settings-before.json`); writes
   `config.json` as kept with only `allow.local` naming the session's package (the loader deploys it at the start);
   runs the session; puts `config.json` back byte for byte and every changed video setting back before the lock goes
   (`restoration.json`, one entry per session), also after an error.
4. The plan: `--warmup` (one map session with the first package, deploying it and warming the caches; reported, not
   counted), then `--menu-runs` rounds and `--map-runs` rounds, each round one session per package, in the order A B,
   then B A (ABBA).
   - **A menu session** (`--menu-width` x `--menu-height`, 1280x720): starts at the main menu, waits up to
     `--menu-wait` (60 s) for the geometry workers to exist, `--menu-settle` (15 s), measures `--menu-seconds` (30 s):
     `menu_start`; then `map gm_construct` and the map part below; then `disconnect` and the same wait and measurement
     in the main menu: `menu_after_map`.
   - **A map session** (`--map-width` x `--map-height`, 3840x2160): `+map gm_construct` on the command line, then the
     map part.
   - **The map part:** after the map's `Clientside Lua startup!` and 5 s of quiet console, `engine_no_focus_sleep 0`,
     `fps_max 0`, no HUD or view model, the camera pinned at the queued-draws lab's view (823, -657, -40, facing west);
     then a client probe waits `--settle` seconds (60) and times every frame for `--seconds` (60) in a `PostRender`
     hook, printing `NL_RW_START`, `NL_RW_END` and `NL_RW_FPS {frames, seconds, fps, mean_ms, median_ms, p90_ms,
     p99_ms, p999_ms, max_ms, over_2x_median}`. The CPU times are read when the console log shows `NL_RW_START` and
     `NL_RW_END` (polled every 0.1 s): `map`.
   - Every measurement: each thread's user and kernel time (`Toolhelp32` thread list, `GetThreadTimes`, names from
     `GetThreadDescription`) in percent of one core over the measured seconds, grouped by name; the
     `geometry-processing(N)` threads and their total; the game process (`GetProcessTimes`); the whole machine's busy
     share (`GetSystemTimes`); the 12 busiest threads. Before each session the machine's busy share over 3 s and any
     other game, compiler or SteamVR process are recorded.
   - Each session ends as `poc_session.py run` ends one: HUD cvars set back, the field's `config.cfg` executed and
     written back to Steam Cloud (`settings_back`), `quit`, a bounded exit wait; crash prompts are declined (never
     answered Yes); the loaded `d3d9.dll` (from the process's modules) and its SHA-256 are recorded.

## Inputs and outputs

- Inputs: the packages (`.gma`), the PoC with the loader installed (`native-loader\config.json` present).
- Outputs below `--evidence` (a new folder under this repository's `out`): `plan.json` (with the packages' SHA-256),
  `results.json`, one folder per session (`record.json`, `console.log`, `loader.log`, `remix-dxvk.log`, crash
  reports if any), `config.json.before`, `video-settings-before.json`, `restoration.json`.

## Side effects

Starts the game in the PoC, whose loader deploys the packages there (left deployed: the restored `config.json` decides
the next start). Writes GMod's settings back to Steam Cloud as `poc_session.py` does. Never touches the field install.

## Exit codes

0 when every session completed; 1 when one failed (its record has `failed`); an exception when the lock timed out, a
game was running or the evidence folder was not new. An interrupted series leaves at most its current session's
changes: end the game with a console `quit` after the field's settings, put `config.json` and the video settings back
from the session's copies, and remove the lock only if it holds the series' pid and token.
