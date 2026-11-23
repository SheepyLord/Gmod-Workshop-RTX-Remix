# The crash at disconnect after playing: queued render calls run before the map-exit cleanup (2026-11-23)

The user's request of 2026-11-23:

> The game still face a fast termination crash after some playing on disconnect. Please investigate this issue,
> launch Opus 5.5 sub agents to resolve it and validate its work and write documentations.

Claude (the main session) investigated, found the cause, reproduced it on the PoC, ran the PoC validation and reviewed
the work. An Opus 5.5 subagent implemented the fix; a second Opus 5.5 subagent reviewed it independently; a third wrote
these documents. On the branch `queue-flush` (worktree `out\worktrees\qflush`, from `main` at `e9dd7042`). Package
only: the engine guard (`engine_guard/`, `gmcl_`/`gmsv_nlengineguard_win64.dll` in the fixes part) and the RTX fixes'
`cl_rtx.lua`. No loader (`winmm.dll`) change. Decision:
[ADR 0261](../decisions/0261-queued-render-calls-run-before-the-map-exit-cleanup.md); facts with offsets:
[RESEARCH.md](../RESEARCH.md), "The crash at disconnect: queued material-variable setters on destroyed variables".

## What it was

In short: when a map ends, the RTX fixes' `ShutDown` hook empties the material cache (`UncacheAllMaterials`), which
destroys every file-based material's variables at once. Material changes made a moment before (the companion puts
imported characters' eye and hair materials back at `ShutDown`) wait in the queued render list, each holding its raw
variable pointer. The engine runs them at `AllowThreading(false)`, a moment later, on freed memory.

- **Three more field crashes after ADR 0254 was published**: 2026-11-22 05:17 UTC, 2026-11-23 05:57 UTC and 06:39 UTC,
  after sessions of 75, 9 and 41 minutes, all exit 0xC0000409 at `disconnect`. All three went `Host_Disconnect` >
  the guard's `AllowThreading` wrapper > `ForceSingleThreaded` > `EndQueue` > `CallQueued` > the run check's step >
  the queued functor: the run check had run the call, and nothing about it had changed.
- **The functor was intact, its target gone.** The calls were `CMemberFunctor1<CMaterialVar*, ...>` setters: an
  `int` setter on 2026-11-22 (a jump to address 0 through the destroyed variable's first word, a heap link) and a
  texture setter on 2026-11-23 twice (`CMaterialVar::CleanUpData` read address 0: the destroyed variable's texture was
  NULL). In queued rendering, `IMaterial:SetTexture`, `SetInt` ... on the main thread queue such a functor with the raw
  variable pointer; nothing keeps the variable alive.
- **The destroyer.** The fixes' binary module's `RTX_CleanupMapTextures` (upstream since 2026-08-08) does
  `materials->Flush(true)`, then `UncacheAllMaterials()`. Its comment says `Flush` drains the queued work; it does
  not: `IMaterialSystem::Flush` flushes only the thread's render context, and the calls the main thread recorded stay
  queued.
- **Reproduced on the PoC** with the published package `0.0.0-dev.20261123002706+24c6839a` (`out/stale-repro`): a
  client `ShutDown` hook that sets file-based materials' variables as the companion does crashed the game at
  `disconnect` 4 of 4 times with the field's dump (the hook is armed in the session's second map, so the level change
  before it is not part of the reproduction). With the fixes' cleanup off (`rtx_flush_textures_on_map_exit 0`) the same session was
  clean 2 of 2; with one `render.CapturePixels()` before the cleanup (a screen read-back makes the queued context run
  its list) it was clean 2 of 2. Materials made with `CreateMaterial` only, or no Lua at all, did not crash.

## Why the two earlier fixes missed it

- **ADR 0247 (2026-11-19)** judged each queued call's object, which for these calls is the functor in the context's
  own arena: a live object of a loaded image. It passed, rightly. The dead thing was the functor's argument.
- **ADR 0254 (2026-11-21)** read the dump of 2026-11-22 01:50 UTC wrongly. At the fault `rcx` held a heap address
  whose first word was another heap address, and ADR 0254 took `rcx` for the queued functor; since GMod never puts a
  functor on the heap, it concluded the element had been written over during the run and built a check that puts
  written-over elements back. `rcx` was the functor's target, the material variable, loaded by the functor's own call
  from +0x18. Nothing was ever written over, so the run check ran the call as it should have. Its log was written only
  after the run, so a run that crashed left none: the field never had one. The element at arena +0x2938 is position
  219 of its list (48 bytes per call), not the 660th.
- Both looked at the call; neither looked at what the call acts on.

## What was built

- **The queued context's own flush.** At install the engine guard finds the one slot of `CMatQueuedRenderContext`'s
  vtable whose code is `Lock; CallQueued(this, 0); Unlock` with nothing called between `CallQueued` and `Unlock` (the
  routine the engine itself calls when a frame's list grows too large), near the function's start, with the `Lock`,
  `Unlock` and `CallQueued` ADR 0247's layout found; exactly one, or the flush stays off with the reason. `flush()`
  (main thread only) runs the main thread's queued calls through it with ADR 0247's walk and ADR 0254's watched run.
  Lua, client and server realms: `nlengineguard.RunQueuedRenderCalls() -> ok, calls, why`; `ok` means the flush ran
  (inside a render block the engine's flush queues one call of its own around it).
- **The fixes' hook calls it first.** `RTXTextureCleanup_MapExit` calls `RunQueuedRenderCalls()` under `pcall` before
  `RTX_CleanupMapTextures`; when it fails, or the engine guard is absent while `mat_queue_mode` is not 0, the cleanup
  is skipped and one console line says why.
- **The target check, the net** (`engine_guard/target_check.*`). While queued calls run under the guard's watch, a
  call on a material variable is skipped and logged unless the variable is still one of its material: its first word
  `CMaterialVar`'s vtable, its owner's `CMaterial`'s, and the owner's parameter array listing it. The offsets come from
  the getters' exact code (slots 24, 40, 41), cross-checked against `CleanUpShaderParams`' two stores; the owner's
  offset counts as proven only once some variable's owner has been a `CMaterial` (until then a variable whose owner is
  no `CMaterial` runs). A variable owned by another material class (`CMaterialSubRect`) or by none is not judged and
  runs. Every setter shape is judged, the string setter's included.
- **The log as it happens.** Each event of a watched run goes to `render-queue-check.log` when it happens; at most 32
  events per run, and the routine flush line for the first 64 flushes of a process. Nothing it does while the list runs
  takes the loader lock.

| Part | What it does | Where |
|---|---|---|
| `find_flush`, `flush` | Finds the queued context's flush; runs the main thread's queued calls through it, watched | `engine_guard/queue_check.*` |
| `RunQueuedRenderCalls` | Lua's way to ask for the flush (client and server realms); `ok, calls, why` | `engine_guard/module.cpp` |
| `RTXTextureCleanup_MapExit` | The flush first; the cleanup skipped when it cannot be sure | `packages/fixes/.../cl_rtx.lua` |
| `target_check::judge` | Skips a call on a material variable that is no longer one of its material | `engine_guard/target_check.*`, `run_check.*` |
| The log | Each event written when it happens; capped | `engine_guard/queue_check.cpp` |
| `-nl_queue_check_no_flush` | Tests: the flush runs nothing and reports success, so the net is exercised | `engine_guard/queue_check.cpp` |
| `stale`, `stale-net` | PoC kinds that reproduce the field's fault, each run judged PASS or FAIL | `tools/qa/queue_check_session.py`, `queue_stale_client.lua` |

No texture reference is lost when a texture setter is skipped: the engine takes a reference when it queues the setter
and queues the matching release right behind it; the skipped setter would have taken the variable's own reference.

A player on an older package can avoid the crash with `rtx_flush_textures_on_map_exit 0` in the console (the cleanup
skipped; texture memory stays in use until the next map).

## What it does not cover

- The fixes' console command `rtx_flush_textures` runs the same uncache in the middle of a game; the render thread then
  runs the list unwatched. The same class of fault; it needs a change in the fixes' native module.
- The render thread's own runs of the lists in normal frames are not watched.
- Variables of other material classes are not judged.
- The field's own sessions (imported characters spawned, then `disconnect`) were not replayed: the reproduction is a
  hook that sets variables as the companion does, on the PoC with the field's exact fault and once in the field
  install after the publish (below).

## Checked

- **Unit tests** of the first build (CTest `nl_engine_guard_tests`): 78 cases, 0 failed: `test_target_check.cpp`
  (new), the flush and the target judge in `test_queue_check.cpp` and `test_run_check.cpp` (see
  [TESTING.md](../TESTING.md), "The queue flush and the target check (ADR 0261)").
- **PoC** (the first build of the fix, package `0.0.0-dev.20261123190843+a7fdc101` built on the branch; evidence
  `out/qflush-poc/run1`; `tools/qa/queue_check_session.py --kinds stale stale-net test plain`):
  - `stale-1`: exit 0; the flush ran 234 and then 274 queued calls before the two cleanups (the level change and the
    disconnect), the cleanup ran ("Source material cache fully uncached"), nothing skipped.
  - `stale-net-1` (`-nl_queue_check_no_flush`): exit 0; the run check skipped 10 calls on variables that were gone and
    logged each: texture setters ("its material lists no variable any more (uncached)") and integer setters ("the
    material variable's first word is not CMaterialVar's vtable"), the field's two fault kinds.
  - `test-1`: exit 0; 4 drops and 4 put back (the test call and pair at two flushes and two checks).
  - `plain-1`: exit 0; nothing dropped or skipped.
- **The independent review** (the second Opus 5.5 subagent, on the first build) found no crash, hang or deadlock in the
  native path and confirmed the PoC evidence; it asked for the hardening that the final build has: the flush accepted
  only near its function's start, `ok` meaning that the flush ran, variables of other material classes left alone, the
  owner's offset proven before it can condemn a call, the count and array offsets cross-checked, the string setter
  judged, the hook failing closed without the engine guard, the log's caps, no loader lock while the list runs, and a
  QA driver that judges each run.
- **Final series** (the hardened build, package `0.0.0-dev.20261123193426+a7fdc101` built on the branch; evidence
  `out/qflush-poc/run2`; `--kinds stale stale-net test plain busy --repeat 2 --busy-seconds 120`): **10 of 10 runs
  passed**, no new crash dump in any.
  - `stale-1`, `stale-2`: exit 0. The Lua's setters were queued right before the fixes' hook body (the order that
    crashed); the flush ran 234 queued calls before the level change's cleanup and 274 before the disconnect's (a
    plain session's disconnect has 220); the cleanup ran both times; nothing skipped.
  - `stale-net-1`, `stale-net-2` (`-nl_queue_check_no_flush`): exit 0. At the disconnect's `AllowThreading(false)` the
    run check ran 1,102 calls and skipped 10 on variables that were gone: 5 texture setters ("its material lists no
    variable any more (uncached)") and 5 integer setters ("the material variable's first word is not CMaterialVar's
    vtable"), each written to the log as it happened, the summary line after them.
  - `test-1`, `test-2`: exit 0; 4 drops and 4 put back each (the test call and pair at two flushes and two checks).
  - `plain-1`, `plain-2`: exit 0; 234 and 220 calls flushed, nothing dropped, put back or skipped.
  - `busy-1`, `busy-2` (the crowded second map for 120 s): exit 0; 234 and 220 calls flushed, nothing dropped or
    skipped.
- **Unit tests of the final build**: `nl_engine_guard_tests` 80 cases, 0 failed; `test_texture_cleanup_flush.py` 11
  tests (the hook's 9 scenarios under LuaJIT among them).
- **The gate**: see Published.

## Files

- `engine_guard/queue_check.h`, `queue_check.cpp` (the flush, the log as it happens, the target check's install),
  `run_check.h`, `run_check.cpp` (the target judge's hook), `target_check.h`, `target_check.cpp` (new), `module.cpp`,
  `CMakeLists.txt`, `README.md`; `engine_guard/tests/test_target_check.cpp` (new), `test_queue_check.cpp`,
  `test_run_check.cpp`.
- `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua` and its `.md`;
  `packages/fixes/modules/gmcl_nlengineguard_win64.dll`, `gmsv_nlengineguard_win64.dll` (rebuilt),
  `packages/fixes/files.json`, `tools/ci/pins.json`.
- Tests: `test_texture_cleanup_flush.py` and `texture_cleanup_harness.lua` (new) (replaced by
  [test_cleanup_drain.py](../../tools/tests/test_cleanup_drain.py.md) in the follow-up, ADR 0262).
- QA: [queue_check_session.py](../../tools/qa/queue_check_session.py.md) (the `stale` and `stale-net` kinds, crash
  evidence kept, PASS or FAIL per run), [queue_stale_client.lua](../../tools/qa/queue_stale_client.lua.md) (new).
- Docs: ADR 0261 and its row, one status line each in ADR 0247 and ADR 0254, CHANGELOG, ROADMAP, RESEARCH, TESTING,
  COMPONENTS, AGENTS.md, this report and its line in the handover index.

## Published

`tools\test.ps1 -Config Release` passed on the branch (`NL_FIXES_CLONE` set; 35 native tests; 2,223, 29 and 26 Python
tests; "All checks passed"). `origin/main` had not moved from `e9dd7042`, so `main` was fast-forwarded to `0fcfb021`
and pushed. The merge's hook built the package here and uploaded item 3829070317 as
**0.0.0-dev.20261123195551+1732099f** (2,325,200,160 bytes, SHA-256
`ed93333aee593ecafd49477e9933b4b2c9bbb4182f0e8b71614dc210691b33ff`, content digest `fa5372df...`, the digest of the
package the final PoC series ran) at 2026-11-23 19:56 UTC, with one change note: the version line and this round's
changelog entry (ADR 0222). The push's hook found the same inputs and uploaded nothing.

**The field install, after the publish** (the user's standing permission to run the field game for tests; no game
was running; `poc_session.py --root <field install> --allow-steam-managed`, `run --workshop --addons --no-window --map
gm_construct --before-quit-console disconnect`, under `out\r10\poc.lock`; evidence `out\qflush-field`; only this
session's part of the console log was read; nothing spawned, nothing installed by hand):

- `f1-download`: the start still ran the package of the day before (`...002706+24c6839a`); Steam fetched the new item
  during it. A plain session: map, `disconnect`, a normal quit, exit 0.
- `f2-stale`: the loader deployed `0.0.0-dev.20261123195551+1732099f` (229 changes). The engine guard said all four of
  its lines (the flush and the target check installed in the field's `materialsystem.dll`). With
  `queue_stale_client.lua` armed right before the fixes' cleanup hook, the `disconnect` printed "queued restores for 29
  materials at ShutDown", then "[RTX Texture Cleanup] Ran 288 queued render calls before the purge" and "Source
  material cache fully uncached"; a normal quit, exit 0, no Lua error, no new crash dump. The field's
  `render-queue-check.log` now exists, with that flush's line (288 calls, watched, nothing skipped).

## Notes and open questions

1. **The console command `rtx_flush_textures`** uncaches in the middle of a game. With setters queued in that frame
   the render thread runs them on destroyed variables, unwatched. Not seen in the field; it needs the fixes' native
   module to change.
   Done in the follow-up: [cleanup-drain-report.md](cleanup-drain-report.md) (ADR 0262).
2. **Should the fixes' native module drain properly itself?** `PerformTextureCleanup`'s `Flush(true)` does not run the
   main thread's queued calls, contrary to its comment. Running the queued context's flush there (or taking the
   material system's lock and leaving threaded rendering first) would fix the map-exit cleanup and the console command
   at the source; this round kept to the engine guard and the Lua hook.
   Done in the follow-up: the cleanup asks the engine guard's exported flush itself,
   [cleanup-drain-report.md](cleanup-drain-report.md) (ADR 0262).
3. **The companion's `ShutDown` restores** (the eye whites' `$basetexture`, solid hair's `$flags` and
   `$allowalphatocoverage`) are harmless now, since the flush runs them before the uncache, but pointless for materials
   about to be uncached. Leaving them out when the fixes' cleanup will run would remove the most common source of these
   setters.
4. ADR 0254's put-back mechanism stays. It has not been seen to act in the field; it costs a few comparisons per call
   at each map exit.
