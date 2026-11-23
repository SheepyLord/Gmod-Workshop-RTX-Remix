# The texture cleanup runs the queued render calls first, whoever calls it

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[cleanup-drain.patch](cleanup-drain.patch) is the sixteenth native patch, after [lua-guards](../lua-guards/README.md);
[pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`) builds the module with it last and records the patched
native tree the sixteen give (`fixes.patched_tree.source` `c5f7ad05...`; `public` and `premake5.lua` unchanged). The
complete changed file is [module.cpp](source/module.cpp); the new ones [cleanup_drain.h](source/cleanup_drain.h) and the
regression [cleanup_drain_test.cpp](tests/cleanup_drain_test.cpp), as the work tree has them (CRLF). The build applies
only the patch's `source/` part. Made in a scratch `git clone --shared` of the user's fork clone, under the worktree's
`out`, with the fifteen earlier patches applied (their `source/` tree gave `14a120ec...`, the recorded one); nothing was
committed to the fork or pushed. The native loader's decision is ADR 0262.

## Why

`PerformTextureCleanup` (upstream since 2026-08-08) uncaches every material: `IMaterialSystem::UncacheAllMaterials`
destroys the variables of every file-based material at once, on the calling thread. In queued rendering a
material-variable setter made on the main thread (`IMaterial:SetTexture`, `SetInt` ... from Lua) does not write the
variable: it waits in the list the main thread records, holding the raw variable pointer, and nothing keeps the
variable alive. An uncache with such setters still queued leaves them pointing at freed memory.

- **At map exit** (the field's crashes at `disconnect`, exit 0xC0000409) `AllowThreading(false)` ran them a moment
  later. The native loader's ADR 0261 had the fixes' `ShutDown` hook `RTXTextureCleanup_MapExit` ask the engine guard
  to run the queued calls first (`nlengineguard.RunQueuedRenderCalls()`).
- **In the middle of a game** two more callers reach the same function, and nothing protected them: the console
  command `rtx_flush_textures` (`FlushTexturesCommand`) and the Lua global `RTX_CleanupMapTextures`
  (`CleanupMapTextures_Lua`), which any client Lua can call, a server's too. There the render thread runs the list at
  the end of the frame. On the PoC (the published package with ADR 0261 in it), file-based materials' variables set
  and `RTX_CleanupMapTextures()` called in one Lua chunk closed the game with exit 0xC0000005 a moment later: the
  render thread's `CallQueued` ran a setter on a destroyed variable, the field's fault in a normal frame. A Lua console
  command that sets variables followed by `rtx_flush_textures` in one console line does the same (one pass of the
  command buffer).
- The comment above `materials->Flush(true)` said it drained queued material work. It does not:
  `IMaterialSystem::Flush` flushes only the calling thread's render context; the calls the main thread has recorded
  stay in its list.

So the cleanup itself runs the queued calls first, whoever calls it.

## The change

[cleanup_drain.h](source/cleanup_drain.h) (standard C++ only) decides whether the cleanup may run:

- the material system is single-threaded (`materials && materials->GetThreadMode() == MATERIAL_SINGLE_THREADED`):
  nothing is ever queued; it may run and no flush is asked;
- otherwise it asks the native loader's engine guard to run the calls this thread has queued, through its export
  `nl_engine_guard_queue_flush_v1` (`int (std::uint64_t* calls, char* why, std::size_t size)`: -1 this copy did not
  install its queue check, 1 what the thread had queued has run, 0 it could not make sure, with the reason in `why`),
  one entry per copy of the engine guard in the order to ask, null for a copy that is not loaded or lacks the export.
  The first copy that answers 0 or 1 decides (its count and reason kept; a reason it did not end is cut at 255
  characters; an empty one gets a text of its own); when none answers the cleanup may not run ("the engine guard's
  queue flush is not available");
- it returns whether the cleanup may run, whether a flush was asked, the calls that ran and the reason. Nothing in it
  allocates or throws.

[module.cpp](source/module.cpp): `DrainQueuedRenderCalls()` resolves the export from `gmcl_nlengineguard_win64.dll`
and `gmsv_nlengineguard_win64.dll` (`GetModuleHandleW`, `GetProcAddress`; both copies can be in the process and only
the one that installed answers) and passes them to the header; it catches everything. `PerformTextureCleanup` calls it
right after its two early returns (the module closing; `rtx_flush_textures_on_map_exit` off for the map-exit caller)
and before `Starting cleanup`, the VRAM report, `ClearMapState` and `UncacheAllMaterials`:

```text
[RTX Texture Cleanup] Purge skipped: queued render calls could not be run first (<why>)
[RTX Texture Cleanup] Ran <n> queued render calls before the purge
```

A refusal prints only the first line and returns `false` (the textures stay in memory until a later cleanup can run); the second
line is printed when calls ran. The `Flush(true)` call stays, with a comment that says what it does. Both callers keep
calling `PerformTextureCleanup` alone; the Lua hook in `cl_rtx.lua` is again only the `pcall` of the global.

## Tests

[cleanup_drain_test.cpp](tests/cleanup_drain_test.cpp) compiles alone with MSVC
(`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX`): single-threaded (no copy asked); the first
copy answers 1 with a count; the first answers -1 and the second 1; the first answers 0 (refused with its reason, the
second not asked); both -1; none loaded; a null between; the largest count; an empty reason for either answer; a
reason without its NUL.

The loader's Release gate ([test_cleanup_drain.py](../../../../../tools/tests/test_cleanup_drain.py.md)) compiles and
runs it on the header as the sixteen patches leave it, checks the folder's files against the patch and the patch's
place in `pins.json`, that `PerformTextureCleanup` asks the drain before it starts, that both callers reach the uncache
only through it, that the export name and signature are the ones `engine_guard/queue_check.cpp` exports, and that the
fixes' Lua hook no longer asks the engine guard itself.

Validated build: 5,658,112 bytes, SHA-256 `b0391bf290dbdae617174f656250184502d4c53c0b6a37d73eed1641696eee48`
(`build_modules.ps1 -Only fixes` with the user's fork clone, under a `subst` alias of the worktree's `out`,
garrysmod_common `a854f23`, premake 5.0.0-beta2; the patched tree matched). Run in the game on the native loader's
test install, in the package built from it: the mid-game cleanup through the Lua global and through the console command
(both crashed every time before), the map-exit cleanup with setters queued right before it, and the same with the
flush switched off; the native loader's handover report
[cleanup-drain-report.md](../../../../../docs/handover/cleanup-drain-report.md) has the runs.
