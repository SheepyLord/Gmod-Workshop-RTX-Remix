# test_cleanup_drain.py

Checks the RTX fixes' sixteenth native patch,
[cleanup-drain](../../packages/fixes/licenses/oversized-skinning/cleanup-drain/README.md) (ADR 0262): the texture
cleanup `PerformTextureCleanup` (behind the map-exit hook, the Lua global `RTX_CleanupMapTextures` and the console
command `rtx_flush_textures`) has the engine guard run the render calls the main thread has queued before it uncaches
every material, and skips the purge when nobody can make sure. It also keeps the checks of ADR 0261's surfaces that
`test_texture_cleanup_flush.py` had (removed with the Lua logic it tested): the engine guard's Lua fields and the PoC
driver [queue_check_session.py](../qa/queue_check_session.py.md), with ADR 0262's midgame kinds.

```powershell
cd tools; python -m unittest discover -s tests -p test_cleanup_drain.py -v
```

- `CleanupDrainPatchTests`:
  - `test_complete_files_are_the_patch_applied`: `cleanup-drain.patch` touches exactly `source/cleanup_drain.h`,
    `source/module.cpp` and `tests/cleanup_drain_test.cpp`; `module.cpp` is lua-guards' copy with the patch applied
    (no folder between holds it), the two new files the patch's added lines (no earlier folder holds them);
    `tools/ci/pins.json` builds the module with the patch last, right after lua-guards; the folder's README names it the
    sixteenth native patch and the recorded `patched_tree.source`.
  - `test_the_cleanup_asks_the_drain_first`: in `PerformTextureCleanup` the module-closing and map-exit-switch returns
    come first, then `DrainQueuedRenderCalls()`, then `Starting cleanup`, the VRAM report, `ClearMapState` and
    `UncacheAllMaterials`; a refusal prints `Purge skipped: queued render calls could not be run first (%s)` and
    returns false; `Ran %llu queued render calls before the purge` when calls ran; `Flush(true)` stays without the
    comment that said it drained queued work.
  - `test_every_caller_reaches_the_uncache_only_through_the_cleanup`: `module.cpp` calls `UncacheAllMaterials` and
    `ClearMapState` once, and `PerformTextureCleanup` only from `FlushTexturesCommand` and `CleanupMapTextures_Lua`.
  - `test_the_drain_asks_both_engine_guard_copies_for_the_engine_guards_export`: the drain takes the material system's
    thread mode, resolves the export from `gmcl_` then `gmsv_nlengineguard_win64.dll`, passes both to
    `CleanupDrain::Decide` and catches everything; the header's export name is one `engine_guard/queue_check.cpp`
    exports (`nl_engine_guard_queue_flush_v1`), with the same parameter types; the header includes only `<cstddef>`,
    `<cstdint>` and `<cstring>`; the engine guard names ADR 0262 at the export.
  - `test_the_lua_hook_calls_the_cleanup_alone`: `cl_rtx.lua`'s `RTXTextureCleanup_MapExit` calls
    `pcall(RTX_CleanupMapTextures)` and no longer names `nlengineguard`, `RunQueuedRenderCalls` or `mat_queue_mode`.
- `CleanupDrainRegression` (Windows with the VS 2022 Build Tools): every patch folder's `source/` and `tests/` in
  `pins.json`'s order, later over earlier, copied to a scratch folder under `out\tmp`; `cleanup_drain_test.cpp`
  compiled with `/W4 /WX /UNDEBUG` and run; it must print `PASS cleanup drain:`.
- `SurfaceTests`: `engine_guard/module.cpp` publishes `RunQueuedRenderCalls`, `queue_flush` and `target_check`; the
  driver counts the console lines (`count_lines`: the engine guard's, the cleanup's `cleanup_flushed`,
  `cleanup_skipped` (the module's `Purge skipped` line, not ADR 0261's hook line), `cleanup_started`,
  `cleanup_uncached`, the stale and midgame client lines) and the log lines (`count_log`); `plan_runs` plans `stale`,
  `stale-net`, `midgame` and `midgame-console`; `run_arguments` writes each midgame run's client Lua with its
  `NLQ_MODE` into the evidence folder and, for `midgame-console`, sends `nlqueue_touch;rtx_flush_textures` and the
  marker before `disconnect`; [queue_stale_client.lua](../qa/queue_stale_client.lua.md) and
  [queue_midgame_client.lua](../qa/queue_midgame_client.lua.md) print their lines (the midgame one defines
  `nlqueue_touch` in both modes and, in mode `lua`, sets the variables before it calls the cleanup; its setters line
  ends with the setter calls made and the stale one's names its materials, both in the form the driver reads).
- `JudgeTests`: the driver's verdict per kind (`judge`): each kind passes with what it must show and fails, with a
  reason, without it (a crash exit, a new dump, a missing console, the stale order, each stale and midgame count, a
  cleanup that ran fewer calls than the setters made or uncached before it ran them; a `Ran` line elsewhere in the
  console does not pass a stale run);
  `midgame_after` counts the cleanup's lines after the setters and before the run's end line, reads the setter calls
  and the first `Ran` line's count and tells a cleanup that uncached before it ran the calls; `stale_after` does the
  same after the stale restores, for a normal run, a `-nl_queue_check_no_flush` run and a refused cleanup;
  `stale_before_cleanup`;
  `new_dumps` counts only `crashes/*.dmp` written since the run started (in a scratch folder under `out\tmp`).

Exit code 0 when every test passes. Side effects: scratch folders under `out\tmp` (removed); the QA driver is imported,
not run.
