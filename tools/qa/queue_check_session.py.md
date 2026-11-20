# queue_check_session.py

RTX sessions on the PoC for the engine guard's queue check
([ADR 0247](../../docs/decisions/0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md)): before
the game leaves threaded rendering (`disconnect`, and every `map`) the check unlinks queued render calls whose object
is gone. A **test** session is launched with `-nl_queue_check_test`, so every check first queues one call whose object
is gone (its first word a heap address, as in the field's crashes) and must drop it: the level change and the
disconnect go through the drop path in the real game. A **plain** session changes level and disconnects the same way
without it, and should drop nothing.

```powershell
# from a worktree with a Release loader build (tools\build.ps1 -Config Release); the package from build_package.py
py -3 -I tools\qa\queue_check_session.py --evidence <main checkout>\out\queue-check\run1 --package out\dist\<package>.gma
py -3 -I tools\qa\queue_check_session.py --evidence <same folder> --rollback   # after an interrupted series
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's or the main checkout's `out` |
| `--package` | The local RTX package to install (`.gma`) |
| `--kinds` | `test` and/or `plain` (default both, in that order) |
| `--repeat` | Runs of each kind (default 1) |
| `--map`, `--then-map` | The first map and the level change's (default gm_construct, then gm_flatgrass) |
| `--settle` | Seconds in each map (default 20) |
| `--width`, `--height` | The window (default 1600x900) |
| `--timeout`, `--hang-grace` | Map start deadline (900 s: a fresh deployment unpacks the package) and `poc_session.py`'s hang grace (180 s) |
| `--lock-timeout` | How long to wait for `out\r10\poc.lock` (4 hours) |
| `--keep-copies` | Keep the PoC's moved originals and the snapshot's copies after a verified restore |
| `--rollback` | Restore the PoC from an interrupted series' evidence |

## What it does

1. Takes the main checkout's `out\r10\poc.lock` (the VR driver's `ExclusiveLock`, task `queue check (engine guard, ADR
   0247)`), refuses to start while a PoC game runs, records the hashes of every `user.conf` (they must not change),
   writes `plan.json`, snapshots the install ([`field_snapshot.py`](../field_snapshot.py.md) `snapshot
   --manifests-from` the field install) and moves the PoC's loader state, add-ons, data, settings, Lua modules, Remix
   mods, logs and captures and the bootstrap into `originals\` ([vr_session.py](../vr_session.py.md)'s `preserve`).
2. [`poc_session.py`](../poc_session.py.md) `install` with `--allow-local` and `--remix on`, then per run a `run` with
   `--addons` from `--map`, `--change-map <then-map>`, no screenshots and `--before-quit-console disconnect` before the
   normal quit; a test run adds `--extra=-nl_queue_check_test`.
3. After each run: the `poc_session.py` record's exit, quit, map change and crash reports; the engine guard's console
   lines counted from the run's `console.log` (`installed`, `test_armed`, `test_dropped`, `dropped`, `not_walked`,
   `stopped`); the PoC's `garrysmod\data\native-loader\render-queue-check.log` copied to `<run>\` with its checks
   counted (the log is removed before each run, so each copy is that run's), in `results.json`.
4. Restores the PoC (vr_session's `restore`: the originals back, the snapshot's rollback verified clean), checks the
   `user.conf` hashes, deletes the bulk copies unless `--keep-copies`, and prints one line per run.

## Side effects, requirements, exit codes

Writes the PoC (restored at the end), the evidence folder and the lock. Needs Windows, a Release loader build in this
checkout and a free PoC. Exit 0 when the series ran and the PoC was restored, whether or not a run crashed
(`results.json` says); an exception (a refused step, a failed restore) ends it with Python's exit 1 and leaves the
evidence for `--rollback`.
