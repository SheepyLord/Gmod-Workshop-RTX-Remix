# 0262: The texture cleanup runs the queued render calls itself

- Status: Accepted 2026-11-23. After ADR 0261 was published the main session asked the user "Fix the same fault in the
  rtx_flush_textures console command too?", and the user answered "Yes, fix it". Extends
  [ADR 0261](0261-queued-render-calls-run-before-the-map-exit-cleanup.md) and supersedes its decision 2 (the fixes'
  `ShutDown` hook asking for the flush itself, with its `mat_queue_mode` fallback); ADR 0261's other decisions stay.
- Package only: the RTX fixes' binary module `gmcl_RTXFixesBinary_win64.dll` (the fixes' sixteenth native patch,
  [cleanup-drain](../../packages/fixes/licenses/oversized-skinning/cleanup-drain/README.md)), the fixes' Lua
  ([cl_rtx.lua](../../packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua.md), the hook
  `RTXTextureCleanup_MapExit`) and a comment in the engine guard ([queue_check.h](../../engine_guard/queue_check.h)).
  No `winmm.dll` change: the user rejected loader changes (2026-11-17).

## Context

ADR 0261 made the map exit safe from Lua: the fixes' `ShutDown` hook had the engine guard run the queued render calls
before it called `RTX_CleanupMapTextures`. The native function behind that global, `PerformTextureCleanup` (the fixes'
`source/module.cpp`), still uncached every material with whatever was queued, and it has two more callers:

- the console command `rtx_flush_textures` (`FlushTexturesCommand`);
- the Lua global `RTX_CleanupMapTextures` itself (`CleanupMapTextures_Lua`), which any client Lua can call at any
  time, a server's Lua sent to the client too.

In the middle of a game nothing protected these. `UncacheAllMaterials` destroys every file-based material's variables
on the main thread; material-variable setters queued earlier in the frame (Lua's `SetTexture`, `SetInt` ...) keep their
raw variable pointers; at the end of the frame the **render thread** runs the list (`ThreadExecuteQueuedContext` >
`EndQueue` > `CallQueued`), with no watch of the engine guard (ADR 0254's run check watches only `AllowThreading(false)`
and the flush). ADR 0261 named this as not covered.

Reproduced on the PoC with the published package `0.0.0-dev.20261123195551+1732099f` (ADR 0261 in it; evidence
`out/midgame-repro`):

- **The Lua global**, called in the same Lua chunk right after setting five file-based materials' variables: the cleanup
  ran and returned true, and the game closed with exit 0xC0000005 a moment later, 3 of 3. The runtime's dump: the render
  thread in `CallQueued` < `EndQueue` < `ThreadExecuteQueuedContext`, an execute fault at a heap address, the variable
  in `rcx`: the field's fault of ADR 0261, in a normal frame.
- **The console command**, 2 of 2, once the setters are queued in the same pass of the command buffer: a Lua console
  command that sets the variables, then `rtx_flush_textures`, in one console line. `lua_run_cl <code>;rtx_flush_textures`
  did not reproduce it, since `lua_run_cl` runs its code later, after the cleanup. A command typed alone runs at the
  start of a frame, when the list is nearly empty, so a player typing it by hand is unlikely to hit the fault; a bind or
  an add-on that runs Lua and then the command in one line can.

## Decision

1. **The cleanup runs the queued render calls itself, whoever calls it.** The fixes' sixteenth native patch
   `cleanup-drain`: `PerformTextureCleanup`, right after its two early returns (the module closing;
   `rtx_flush_textures_on_map_exit` off, for calls through the Lua global) and before anything else (`Starting cleanup`, the VRAM
   report, `ClearMapState`, `UncacheAllMaterials`), asks the engine guard's exported flush
   `nl_engine_guard_queue_flush_v1` (ADR 0261's flush: the walk, the watched run, the net), in the client copy and then
   the server copy of the engine guard. Both can be in the process; only the copy that installed answers 0 or 1, the
   other -1. The first answer of 0 or 1 decides. A single-threaded material system (`GetThreadMode()`) queues nothing
   and needs no flush. When no copy can make sure, the purge is skipped with one console line and the function returns
   false (the textures stay in memory until a later cleanup can run); when calls ran, one line gives their count:

   ```text
   [RTX Texture Cleanup] Purge skipped: queued render calls could not be run first (<why>)
   [RTX Texture Cleanup] Ran <n> queued render calls before the purge
   ```

   The decision itself is in a header of standard C++ only (`cleanup_drain.h`: no allocation, no exception), tested
   alone; `DrainQueuedRenderCalls()` in `module.cpp` resolves the export with `GetModuleHandleW` and `GetProcAddress`
   and catches everything. The last frame's list, which the render thread may still be running, needs nothing new:
   `UncacheAllMaterials` takes the material system's lock itself, and that lock waits for the render thread
   ([RESEARCH.md](../RESEARCH.md), "The same fault in the middle of a game"). Under that lock the engine flushes only
   the hardware context, which is why this frame's list was left; after the drain neither list holds a call queued
   before the cleanup.
2. **The Lua hook calls the cleanup alone again.** `RTXTextureCleanup_MapExit` is the `pcall` of
   `RTX_CleanupMapTextures` and its two outcomes, as before ADR 0261. This supersedes ADR 0261's decision 2: the hook's
   own `RunQueuedRenderCalls()` and its `mat_queue_mode` fallback are gone, since the module now refuses to purge when it
   cannot be sure. The hook's LuaJIT harness test (`test_texture_cleanup_flush.py` with its harness) is replaced by
   [`test_cleanup_drain.py`](../../tools/tests/test_cleanup_drain.py.md).
3. **The export is a contract.** `nl_engine_guard_queue_flush_v1`'s name, its signature
   (`int (std::uint64_t* calls, char* why, std::size_t size)`) and its answers (-1 this copy did not install, 1 what the
   thread had queued has run, 0 it could not make sure, with the reason) are relied on by the fixes' module; the engine
   guard's source says so.
4. **QA in the real game.** `tools/qa/queue_check_session.py` gains the kinds `midgame` (the Lua global) and
   `midgame-console` (the console command in one pass of the command buffer) with
   [`queue_midgame_client.lua`](../../tools/qa/queue_midgame_client.lua.md); a run passes only with no crash and the
   cleanup's "Ran <n>" line, counting at least the setters' calls, and then its "fully uncached" line after the
   setters. The `stale` kind is judged the same way on the cleanup right after its restores (a "Ran" line somewhere in
   the console, such as the level change's, no longer passes it).

## Consequences

- The console command `rtx_flush_textures` and any Lua that calls `RTX_CleanupMapTextures` in the middle of a game no
  longer leave queued setters on destroyed material variables for the render thread. The map exit keeps ADR 0261's
  protection, now from the module instead of the hook.
- Without the engine guard (or with its flush off after a game update), queued rendering on, every purge is skipped
  with its line, at the map exit as before and now also for the command and the global. When the line says "the engine
  guard's queue flush is not available", no copy of the engine guard installed its queue check; the Lua field
  `nlengineguard.queue_check` says why.
- On the PoC, with the package built from the branch, the mid-game cleanup ran clean 6 of 6 (the Lua global 3, the
  console command 3), where the package before crashed 5 of 5; the map-exit kinds passed as before.
- Not covered: other code that keeps `IMaterialVar` pointers across an uncache in the middle of a game is as it was (the
  engine's own restore callbacks are for that; the command's own help still says the reload "may hitch"); the render thread's own
  runs in normal frames are still not watched (for this cleanup they no longer need to be). A player on a package before
  this one avoids the mid-game fault by not using `rtx_flush_textures` in a bind or line after Lua commands.
