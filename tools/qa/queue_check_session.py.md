# queue_check_session.py

RTX sessions on the PoC for the engine guard's queue check
([ADR 0247](../../docs/decisions/0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md)) and
run check ([ADR 0254](../../docs/decisions/0254-queued-render-calls-checked-again-while-the-game-runs-them.md)): before
the game leaves threaded rendering (`disconnect`, and every `map`) the check unlinks queued render calls whose object
is gone, and while the game then runs them it puts back elements written over and skips calls whose object changed.
A **test** session is launched with `-nl_queue_check_test`, so every check first queues one call whose object is gone
(its first word a heap address, as in the field's crashes) and must drop it, and with the run check a pair of calls
whose first writes over the second's element during the run, which must be put back and the second run: the level
change and the disconnect go through both paths in the real game. A **plain** session changes level and disconnects
the same way without it, and should drop and put back nothing. A **busy** session crowds the second map with
[`queue_busy_server.lua`](queue_busy_server.lua.md) (props, ragdolls, fighting NPCs, explosions and decals) for
`--busy-seconds` before the disconnect, as the field's crashes came after long, crowded sessions: any put back or skip
it logs is a real one, with the calls that ran before it.

The **stale** sessions (ADR 0261) reproduce what the field's crashes really were: material variables set at `ShutDown`
([`queue_stale_client.lua`](queue_stale_client.lua.md), sent with `poc_session.py run --lua` once the second map is
up) wait in the queued list while the RTX fixes' map-exit cleanup uncaches every material. The Lua wraps the fixes' own
`ShutDown` hook, so its setters are queued right before that hook's body runs (hook order is not otherwise
guaranteed). It is sent after the level change, so a stale run exercises the final `disconnect`, not the level change.
A **stale** run starts normally: the fixes' cleanup runs the queued calls first through the engine guard's flush (the
fixes' native module asks for it since ADR 0262; the hook did before), so the disconnect must not crash and the console
must have `[RTX Texture Cleanup] Ran <n> queued render calls before the purge`. A **stale-net** run adds
`--extra=-nl_queue_check_no_flush` (the flush runs nothing and says it succeeded), so the calls are still queued when
the game leaves threaded rendering: the run check must skip those whose variable is gone, say so in the console
(`Skipped <n> queued render call(s) on a material variable that was already gone`) and log each as it happens.

The **midgame** sessions (ADR 0262) use the same cleanup in the middle of a game, where the render thread runs the list
at the end of the frame and nothing else watches it: [`queue_midgame_client.lua`](queue_midgame_client.lua.md) sets
variables of five file-based materials and the cleanup runs in the same frame. A **midgame** run calls the Lua global
`RTX_CleanupMapTextures()` from the client Lua's timer, three seconds after it is sent (mode `lua`). A
**midgame-console** run (mode `console`) has the driver send `nlqueue_touch;rtx_flush_textures` as one console line,
then `echo nlqueue midgame console sent`, before the run's own `disconnect`: the setters are queued and the console
command's cleanup runs in one pass of the command buffer. Before ADR 0262 both closed the game with 0xC0000005 a moment
later; now the cleanup must run the queued calls first and then uncache.

```powershell
# from a worktree with a Release loader build (tools\build.ps1 -Config Release); the package from build_package.py
py -3 -I tools\qa\queue_check_session.py --evidence <main checkout>\out\queue-check\run1 --package out\dist\<package>.gma
py -3 -I tools\qa\queue_check_session.py --evidence <same folder> --rollback   # after an interrupted series
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's or the main checkout's `out` |
| `--package` | The local RTX package to install (`.gma`) |
| `--kinds` | `test`, `plain`, `busy`, `stale`, `stale-net`, `midgame` and/or `midgame-console` (default `test plain`, in the order given) |
| `--repeat` | Runs of each kind (default 1) |
| `--map`, `--then-map` | The first map and the level change's (default gm_construct, then gm_flatgrass) |
| `--settle` | Seconds in the second map before the disconnect (default 20) |
| `--busy-seconds` | A busy run's seconds in the second map, crowded, before the disconnect (default 240) |
| `--width`, `--height` | The window (default 1600x900) |
| `--timeout`, `--hang-grace` | Map start deadline (900 s: a fresh deployment unpacks the package) and `poc_session.py`'s hang grace (180 s) |
| `--lock-timeout` | How long to wait for `out\r10\poc.lock` (4 hours) |
| `--keep-copies` | Keep the PoC's moved originals and the snapshot's copies after a verified restore |
| `--rollback` | Restore the PoC from an interrupted series' evidence |

## What it does

1. Takes the main checkout's `out\r10\poc.lock` (the VR driver's `ExclusiveLock`, task `queue and run check (engine
   guard, ADR 0247, ADR 0254)`), refuses to start while a PoC game runs, records the hashes of every `user.conf` (they must not change),
   writes `plan.json`, snapshots the install ([`field_snapshot.py`](../field_snapshot.py.md) `snapshot
   --manifests-from` the field install) and moves the PoC's loader state, add-ons, data, settings, Lua modules, Remix
   mods, logs and captures and the bootstrap into `originals\` ([vr_session.py](../vr_session.py.md)'s `preserve`).
2. [`poc_session.py`](../poc_session.py.md) `install` with `--allow-local` and `--remix on`, then per run a `run` with
   `--addons` from `--map`, `--change-map <then-map>`, no screenshots and `--before-quit-console disconnect` before the
   normal quit; a test run adds `--extra=-nl_queue_check_test`; a busy run copies `queue_busy_server.lua` to the PoC's
   `garrysmod\data\nlqueue\busy.txt`, sends `engine_no_focus_sleep 0` and the `lua_run` that runs it once the second
   map is up, and stays there `--busy-seconds`; a stale run adds `--lua` with `queue_stale_client.lua`, and a
   stale-net run also `--extra=-nl_queue_check_no_flush`; a midgame run adds `--lua` with its own copy of
   `queue_midgame_client.lua` in the evidence folder (`<run>-client.lua`, `NLQ_MODE = "lua"` or `"console"` first),
   and a midgame-console run also the two console lines above as `--before-quit-console` before `disconnect`.
3. After each run, even one that crashed: the PoC's new crash dumps (`crashes\`) and the loader's new session folders
   (`native-loader\logs\sessions\`, each changed in the run) copied to `<run>\crash\` before the restore removes them
   (`kept` in the record), and the run's own new dumps counted apart (`new_dumps`: `crashes\*.dmp` written since the
   run started; a first start gathers older dumps into a session folder, which is not a crash of this run); the `poc_session.py` record's exit, quit, map change and crash reports; the console lines
   counted from the run's `console.log` (`count_lines`: `installed`, `run_installed`, `run_off`, `test_armed`,
   `test_pair_armed`, `test_dropped`, `test_put_back`, `dropped`, `put_back`, `not_walked`, `stopped`, a busy run's
   `busy_started` and `busy_report`; ADR 0261's `flush_installed`, `flush_off`, `target_installed`, `target_off`,
   `no_flush_armed`, `gone`, the fixes' cleanup's `cleanup_flushed`, `cleanup_skipped`, `cleanup_started` and
   `cleanup_uncached`, a stale run's `stale_armed` and `stale_queued`, and ADR 0262's midgame lines `midgame_armed`,
   `midgame_queued`, `midgame_returned` and `midgame_sent`); the PoC's `garrysmod\data\native-loader\render-queue-check.log` copied to
   `<run>\` with its lines counted (`count_log`: the walks before a run, `log_checks`; the watched runs that wrote
   events, `log_runs`, each with a header at its first event and a summary at its end, `log_run_ends`; the events,
   `log_run_events`, those on a material variable that was gone, `log_gone_events`, and the test pair's,
   `log_test_events`; the flushes, `log_flushes`). The log is removed before each run, so each copy is that run's.
   For the stale kinds also whether `[nlqueue] stale: queued restores` comes before a `[RTX Texture Cleanup]` line
   in the console (`stale_order`), and the cleanup right after the restores (`stale_after`; a `Ran <n>` line anywhere
   in the console is not enough, since the level change's cleanup prints one too): the materials the restores line
   counts (`stale_materials`), the cleanup's `Ran <n> queued render calls before the purge` and `Source material cache
   fully uncached` lines after that line (`stale_ran_after`, `stale_uncached_after`), the `<n>` of the first `Ran`
   line (`stale_first_ran_calls`) and whether it comes before the first uncache line (`stale_ran_then_uncached`).
   For the midgame kinds the same two lines after the first `[nlqueue] midgame: queued setters` line, in the
   rest of the console (`midgame_ran_after`, `midgame_uncached_after`) and before the run's own end line, the Lua
   global's `returned` line or the console run's marker (`midgame_ran_before_end`, `midgame_uncached_before_end`), so
   the disconnect's cleanup does not count for the mid-game one (`midgame_after`); the setter calls the client says it
   made (`midgame_setter_calls`), the `<n>` of the first `Ran` line before the end line (`midgame_first_ran_calls`)
   and whether it comes before the uncache line (`midgame_ran_then_uncached`).
   Then the run is judged against what its kind must show (`verdict` PASS or FAIL, `reasons`):

   | Kind | Must show |
   |---|---|
   | every kind | exit 0 (or no exit code after a normal quit), no crash, no new dump |
   | `test` | `test_dropped` >= 1 and `test_put_back` >= 1 |
   | `plain`, `busy` | `dropped`, `put_back` and `gone` all 0 |
   | `stale` | `stale_queued` >= 1, `cleanup_flushed` >= 1, `cleanup_skipped` 0, `gone` 0, the stale order; after the restores: `stale_ran_after` >= 1, `stale_uncached_after` >= 1, `stale_first_ran_calls` at least two for each of `stale_materials` (a texture setter and its release), and that `Ran` line before the uncache |
   | `stale-net` | `stale_queued` >= 1, `stale_uncached_after` >= 1 (the cleanup uncached with the restores still queued), `gone` >= 1, `log_gone_events` >= 1, the stale order |
   | `midgame`, `midgame-console` | `midgame_queued` >= 1; the four `midgame_*_after` and `*_before_end` counts >= 1; `midgame_setter_calls` >= 1 and `midgame_first_ran_calls` at least that many; that `Ran` line before the uncache; `midgame_returned` >= 1 (midgame) or `midgame_sent` >= 1 (midgame-console); `dropped`, `put_back`, `gone` and `cleanup_skipped` 0 |

   A count of calls the cleanup ran first that reaches the setters' own is a necessary sign, not a proof, that the
   setters were among them: other calls of the frame are in the same list. The proof is the run itself, which crashed
   every time before ADR 0262.

   All of it goes to `results.json`.
4. Restores the PoC (vr_session's `restore`: the originals back, the snapshot's rollback verified clean), checks the
   `user.conf` hashes, deletes the bulk copies unless `--keep-copies`, and prints one line per run: PASS or FAIL with
   the reasons, crashed or not, the exit, then the counts above (the flush's and the target check's install lines, the
   hook's flushed and skipped lines, the gone line, the log's flushes and gone events, `new dumps N`, the files kept,
   a stale run's two lines with its materials and the calls the cleanup after them ran first, and a midgame run's
   mode, setter calls and counts); then `<p> of <n> runs passed` and the failed runs' names.

## The engine guard's lines

Console (`[NativeLoader] ...`, from `engine_guard/queue_check.cpp`, once per install or per run; `[RTX Texture
Cleanup] ...` from the RTX fixes' native module, `PerformTextureCleanup`, since ADR 0262):

```text
[NativeLoader] Queued render calls can be run before the RTX fixes' map-exit cleanup (engine guard, ADR 0261).
[NativeLoader] The queue flush is off: <why> (engine guard, ADR 0261).
[NativeLoader] Queued calls on a material variable that is gone are skipped (engine guard, ADR 0261).
[NativeLoader] The target check is off: <why> (engine guard, ADR 0261).
[NativeLoader] Queue flush test: the flush runs nothing and says it succeeded (-nl_queue_check_no_flush).
[NativeLoader] Skipped <n> queued render call(s) on a material variable that was already gone (engine guard, ADR 0261). Details: garrysmod/data/native-loader/render-queue-check.log
[RTX Texture Cleanup] Ran <n> queued render calls before the purge
[RTX Texture Cleanup] Purge skipped: queued render calls could not be run first (<why>)
[RTX Texture Cleanup] Starting cleanup (<reason>)
[RTX Texture Cleanup] Source material cache fully uncached
```

Log (`garrysmod/data/native-loader/render-queue-check.log`; a watched run's lines are written as each event happens, at
most 32 events per run, the rest counted in its summary; the routine `flush <n>:` line only for a process's first 64
flushes; modules named from the bases captured before the material system's lock, else `the image at 0x...`):

```text
<utc> check <n> before the game left threaded rendering: list 0 <c> calls, list 1 <c> calls; <d> dropped
<utc> flush <n> before the queued context's flush: ...
<utc> check <n> while the game ran the queued calls (each event as it happened):
  list <l>, call <p> of <c> (element +0x...): its call's material variable is gone (destroyed while the call waited): skipped
    when checked: next 0x..., object 0x... (materialsystem.dll .?AV?$CMemberFunctor1@PEAVCMaterialVar@@...)
    material variable 0x... (the functor's word at +0x18, ...): <why>
    found: the variable's first word 0x... (CMaterialVar's 0x...), its material 0x..., whose first word 0x... (CMaterial's 0x...), parameters 0x0, 0 of them
    run just before it, newest first: list <l> call <p> <class>; ...
<utc> check <n> run ended: <r> calls run, <b> put back, <s> skipped (<g> on a material variable that was gone), <e> lists ended early[; <k> events not written]
<utc> flush <n>: list <l> held <c> calls; watched; ran <r> queued render call(s) through the queued context's flush[; <q> call(s) queued again by the flush]
```

## Side effects, requirements, exit codes

Writes the PoC (restored at the end), the evidence folder and the lock. Needs Windows, a Release loader build in this
checkout and a free PoC. Exit 0 when the series ran, the PoC was restored and every run passed; 1 when a run failed
(after the restore; `results.json` and the printed lines say why), or when an exception (a refused step, a failed
restore) ended it, which leaves the evidence for `--rollback`.
