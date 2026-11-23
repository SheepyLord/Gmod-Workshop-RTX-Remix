# test_texture_cleanup_flush.py

Unit tests (ADR 0261) for the RTX fixes' map-exit cleanup running the queued render calls first, and for the Lua
surface and PoC driver around it.

```powershell
cd tools; python -m unittest tests.test_texture_cleanup_flush
```

- `CleanupHookTests` (skipped without LuaJIT): the packaged `cl_rtx.lua`'s `RTXTextureCleanup_MapExit` hook under
  [texture_cleanup_harness.lua](texture_cleanup_harness.lua.md): without the engine guard (or without its
  `RunQueuedRenderCalls`) the hook fails closed, running the cleanup only with `mat_queue_mode` 0 and otherwise
  skipping it with one line; with it the flush runs first and the cleanup after it, with one count line when calls
  ran; when the flush returns false (with or without a reason) or raises, the cleanup is skipped and one line says
  why.
- `SurfaceTests`: the hook calls `nlengineguard.RunQueuedRenderCalls` under `pcall` before `RTX_CleanupMapTextures`;
  `engine_guard/module.cpp` publishes `queue_flush`, `target_check` and `RunQueuedRenderCalls`;
  [queue_check_session.py](../qa/queue_check_session.py.md) counts the new console lines (`count_lines`) and log lines
  (`count_log`) in the formats the engine guard and the hook print, and plans `stale` and `stale-net` runs (the
  latter with `-nl_queue_check_no_flush`); [queue_stale_client.lua](../qa/queue_stale_client.lua.md) wraps the fixes'
  own `ShutDown` hook (or falls back to its own) and prints both of its lines.
- `JudgeTests`: the driver's verdict per kind (`judge`): each kind passes with what it must show and fails, with a
  reason, without it (a crash exit, a new dump, a missing console, the stale restores not before the cleanup);
  `stale_before_cleanup` on console text; `new_dumps` counts only `crashes/*.dmp` written since the run started (in a
  scratch folder under `out\tmp`).

Exit code 0 when every test passes. No side effects (the driver is imported, not run).
