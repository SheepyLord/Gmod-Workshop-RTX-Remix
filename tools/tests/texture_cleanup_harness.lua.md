# texture_cleanup_harness.lua

LuaJIT harness for the RTX fixes' map-exit cleanup hook (`RTXTextureCleanup_MapExit` in the packaged
`packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua`, ADR 0261). Invoked by
[test_texture_cleanup_flush.py](test_texture_cleanup_flush.py.md):
`luajit texture_cleanup_harness.lua <cl_rtx.lua> <scenario>`.

It cuts the hook's own text out of the file (from its `hook.Add("ShutDown", "RTXTextureCleanup_MapExit", ...` to the
first `end)` line after it) and runs it with stand-ins: `hook.Add` keeps the function, `print` and `ErrorNoHalt` keep
their lines, `GetConVar("mat_queue_mode")` answers 2 (queued) or, in the `-single` scenarios, 0, `RTX_CleanupMapTextures`
records that it ran, and `nlengineguard.RunQueuedRenderCalls` answers as the scenario says. Then it calls the hook and checks what ran, in which order, and what was printed.

| Scenario | The engine guard | Expected |
|---|---|---|
| `no-guard` | absent, `mat_queue_mode` 2 | fails closed: no cleanup; `[RTX Texture Cleanup] Map-exit purge skipped: the engine guard cannot run the queued render calls first and queued rendering is on (mat_queue_mode 2)` |
| `no-function` | a table without `RunQueuedRenderCalls`, `mat_queue_mode` 2 | the same |
| `no-guard-single`, `no-function-single` | as above, `mat_queue_mode` 0 | the cleanup runs (nothing is queued), no skip line |
| `nothing-queued` | `true, 0, ...` | the flush, then the cleanup; no count line |
| `flushed` | `true, 12, ...` | the flush, the line `[RTX Texture Cleanup] Ran 12 queued render calls before the purge`, then the cleanup |
| `refused` | `false, 0, "the queue flush is off: test"` | the flush only; `[RTX Texture Cleanup] Map-exit purge skipped: ...` with the reason |
| `refused-silent` | `false` and nothing else | the flush only; the skip line ends `(no reason given)` |
| `error` | raises `boom` | the flush only; the skip line with the error |

Prints `PASS <scenario>` and exits 0, or raises an assertion error. No side effects.
