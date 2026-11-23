# The texture cleanup runs the queued render calls itself: the `rtx_flush_textures` console command (2026-11-23)

The follow-up of [disconnect-uncache-report.md](disconnect-uncache-report.md) (ADR 0261). After that fix was published
the main session asked the user:

> Fix the same fault in the rtx_flush_textures console command too?

The user answered, 2026-11-23:

> Yes, fix it

Claude (the main session) reproduced the fault on the PoC and validated the fix. An Opus 5.5 subagent implemented it;
a second Opus 5.5 subagent reviewed it independently; a third wrote these documents. On the branch `cleanup-drain`
(worktree `out\worktrees\qflush`, from `main` at `61196800`). Package only: the RTX fixes' binary module
(`gmcl_RTXFixesBinary_win64.dll`, the fixes' sixteenth native patch), the fixes' `cl_rtx.lua` and a comment in the
engine guard. No loader (`winmm.dll`) change. Decision:
[ADR 0262](../decisions/0262-the-texture-cleanup-runs-the-queued-render-calls-itself.md); facts:
[RESEARCH.md](../RESEARCH.md), "The same fault in the middle of a game: the cleanup's console command and Lua global".

## What was left

ADR 0261 had the fixes' `ShutDown` hook ask the engine guard to run the queued render calls before it called
`RTX_CleanupMapTextures`. The native function behind it, `PerformTextureCleanup`, still uncached every material with
whatever was queued, and two more callers reach it: the console command `rtx_flush_textures` and the Lua global
`RTX_CleanupMapTextures` itself, which any client Lua can call at any time. In the middle of a game the render thread
runs the list at the end of the frame (`ThreadExecuteQueuedContext` > `EndQueue` > `CallQueued`), unwatched: setters
queued before the uncache ran on destroyed material variables. ADR 0261 named this as not covered.

## The reproduction

On the PoC with the published package `0.0.0-dev.20261123195551+1732099f` (ADR 0261 in it); evidence
`out/midgame-repro`:

- **The Lua global**, called right after setting five file-based materials' variables in the same Lua chunk: crash 3
  of 3, exit 0xC0000005. The runtime's dump: the render thread in `CallQueued` < `EndQueue` <
  `ThreadExecuteQueuedContext`, an execute fault at a heap address, the variable in `rcx`.
- **The console command**: crash 2 of 2 once the setters are queued in the same pass of the command buffer (a Lua
  console command, then `rtx_flush_textures`, in one console line). `lua_run_cl ...;rtx_flush_textures` did not
  reproduce it, because `lua_run_cl` runs its code later, after the cleanup. A command typed alone runs at the start of
  a frame, when the list is nearly empty, so a player typing it by hand is unlikely to hit the fault.

## What was built

- **The cleanup drains first, whoever calls it.** `PerformTextureCleanup`, right after its two early returns and
  before anything else, asks the engine guard's exported flush `nl_engine_guard_queue_flush_v1` (ADR 0261's flush: the
  walk, the watched run, the net) in the client copy and then the server copy of the engine guard; only the copy that
  installed answers 0 or 1, and the first such answer decides. A single-threaded material system queues nothing and
  needs no flush. When no copy can make sure the purge is skipped and the function returns false:
  `[RTX Texture Cleanup] Purge skipped: queued render calls could not be run first (<why>)`; when calls ran:
  `[RTX Texture Cleanup] Ran <n> queued render calls before the purge`.
- **The hook calls the cleanup alone again.** `RTXTextureCleanup_MapExit` is the `pcall` of the global and its two
  outcomes; its own flush and `mat_queue_mode` fallback (ADR 0261's decision 2) are gone.
- **The export is a contract.** The engine guard's source says that the export's name and signature are relied on by
  the fixes' module.

| Part | What it does | Where |
|---|---|---|
| `CleanupDrain::Decide` | Decides whether the cleanup may run from the thread mode and the copies' answers; no allocation, no exception | `packages/fixes/licenses/oversized-skinning/cleanup-drain/source/cleanup_drain.h` |
| `DrainQueuedRenderCalls` | Resolves the export in `gmcl_` and `gmsv_nlengineguard_win64.dll`, catches everything | `.../cleanup-drain/source/module.cpp` |
| `PerformTextureCleanup` | Drains before the uncache; skips the purge with one line when it cannot | `.../cleanup-drain/source/module.cpp` |
| `RTXTextureCleanup_MapExit` | The `pcall` of the cleanup alone | `packages/fixes/.../cl_rtx.lua` |
| `midgame`, `midgame-console` | PoC kinds that reproduce the mid-game fault, each run judged PASS or FAIL | `tools/qa/queue_check_session.py`, `queue_midgame_client.lua` |

The built module: 5,658,112 bytes, SHA-256 `b0391bf290dbdae617174f656250184502d4c53c0b6a37d73eed1641696eee48`, built
with `tools/ci/build_modules.ps1 -Only fixes` from the user's fork clone under a `subst` alias of the worktree's `out`
(garrysmod_common `a854f23`, premake 5.0.0-beta2), the sixteen patches of `tools/ci/pins.json` applied; the patched
native tree matched the recorded `fixes.patched_tree.source` `c5f7ad05...` (`public` and `premake5.lua` unchanged).
Nothing was committed to the fork or pushed.

## What it does not cover

- Other code that keeps `IMaterialVar` pointers across an uncache in the middle of a game is as it was (the engine's
  own restore callbacks are for that; the command's help still says the reload "may hitch").
- The render thread's own runs in normal frames are still not watched; for this cleanup they no longer need to be.
- A player on a package before this one can avoid the mid-game fault by not using `rtx_flush_textures` in a bind or a
  console line after Lua commands.

## Checked

- **The drain's regression** (`cleanup_drain_test.cpp`, compiled alone with MSVC `/W4 /WX /UNDEBUG`): single-threaded,
  the first copy answering 1, -1 then 1, 0 (refused, the second not asked), both -1, none loaded, a null between, the
  largest count, empty reasons, a reason without its NUL. The implementer's README records the module build above;
  the module was not run in a game before the PoC series.
- **`test_cleanup_drain.py`** (see [TESTING.md](../TESTING.md), "The cleanup's own drain (ADR 0262)"): the patch
  folder against the patch and `pins.json`, the drain's place in `PerformTextureCleanup`, both callers only through it,
  the export's name and signature against the engine guard's, the hook calling the cleanup alone, the regression
  compiled and run, the QA driver's plans, counts and verdicts.
- **PoC, the package built from the branch** (`tools/qa/queue_check_session.py`, evidence `out/cdrain-poc` of the main
  checkout; each run starts gm_construct, changes to gm_flatgrass, where the client Lua is sent, disconnects and quits):
  - First series, 8 of 8 PASS, every run exit 0 with no new dump:
    - `midgame` twice (the Lua global; it crashed 3 of 3 before): after the setters' line the console has "Ran 27
      queued render calls before the purge", "Starting cleanup (client Lua ShutDown)", "Source material cache fully
      uncached" and "RTX_CleanupMapTextures returned true true"; the game plays on and its `disconnect` runs 220 more
      calls before that cleanup.
    - `midgame-console` twice (`nlqueue_touch;rtx_flush_textures` in one console line; it crashed 2 of 2 before): "Ran
      25 queued render calls before the purge", "Starting cleanup (manual console command)", the uncache line, then
      the marker.
    - `stale` twice (ADR 0261's map-exit case, now through the module): the restores of 29 materials, then "Ran 274
      queued render calls before the purge" and the uncache.
    - `stale-net` twice (`-nl_queue_check_no_flush`, so the cleanup uncaches with the restores still queued): the run
      check skipped 10 calls on variables that were gone, each logged as it happened.
  - Second series, after the review, with the driver's stricter verdicts (below), 7 of 7 PASS, every run exit 0 with
    no new dump: `midgame` (10 setter calls, then "Ran 27", then the uncache), `midgame-console` (10 setter calls, "Ran
    25", the uncache), `stale` (29 materials, "Ran 274", the uncache), `stale-net` (the uncache with the restores still
    queued, 10 calls skipped and logged), `test` (ADR 0254's test pair: 4 drops, 4 put back), `plain`, and `busy` (two
    minutes of a crowded map, up to 700 props, 72 ragdolls and 24 NPCs: nothing dropped, put back or skipped).
  - Together: the mid-game cleanup 6 of 6 clean (the Lua global 3, the console command 3), where the package before
    crashed 5 of 5; the map-exit kinds and ADR 0247's and 0254's kinds as before.
- **The gate** (`tools\test.ps1 -Config Release`, the tree replay with the fork clone): the conventions, the Release
  build with 35 of 35 native tests, and 29, 26 and 2,227 Python tests: "All checks passed". A first run failed one
  test (`test_inputs`, the packages' index): the note beside `cl_rtx.lua` had been reworded after it was indexed;
  imported again, and the whole gate run again on the final tree.

## Files

- `packages/fixes/licenses/oversized-skinning/cleanup-drain/` (new): `cleanup-drain.patch`, `README.md`,
  `source/cleanup_drain.h`, `source/module.cpp`, `tests/cleanup_drain_test.cpp`.
- `packages/fixes/modules/gmcl_RTXFixesBinary_win64.dll` (rebuilt), `packages/fixes/files.json`,
  `packages/fixes/README.md`, `packages/fixes/licenses/oversized-skinning/lua-guards/README.md`;
  `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua` and its `.md`.
- `tools/ci/pins.json` (`fixes.patches`, `fixes.patched_tree`), `tools/ci/README.md`, `tools/ci/build_modules.ps1.md`.
- `engine_guard/queue_check.h`, `queue_check.cpp`, `README.md` (the export named a contract).
- Tests: [test_cleanup_drain.py](../../tools/tests/test_cleanup_drain.py.md) (new; `test_texture_cleanup_flush.py`
  and `texture_cleanup_harness.lua` removed), `test_lua_guards.py` and its `.md`.
- QA: [queue_check_session.py](../../tools/qa/queue_check_session.py.md) (the `midgame` and `midgame-console` kinds),
  [queue_midgame_client.lua](../../tools/qa/queue_midgame_client.lua.md) (new), `queue_stale_client.lua.md`.
- Docs: ADR 0262 and its row, a status line in ADR 0261, CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS,
  AGENTS.md, the links in [disconnect-uncache-report.md](disconnect-uncache-report.md), this report and its line in
  the handover index.

## Published

(filled in by the main session after the runs)

## The independent review

Verdict: nothing wrong found in the native path, the bookkeeping or the Lua hook; ship once it has run in a game (the
PoC series above). What it asked for, and what was done:

- **The `stale` verdict could pass on another cleanup's line** (a "Ran" line anywhere in the console counted, and the
  level change's cleanup prints one). Done: the driver now judges the cleanup right after the restores' line
  (`stale_after`): its "Ran <n>" line, with `<n>` at least two calls for each material restored, before its uncache
  line.
- **The `midgame` verdict could not tell whether the setters were among the calls run.** Done: the client prints the
  setter calls it made, and the first "Ran <n>" line after them must count at least as many and come before the uncache
  line. This is a necessary sign, not a proof (other calls of the frame are in the same list); the proof is the run,
  which crashed every time before.
- **Without a material system pointer** (`materials` null in the fixes' module) the drain does not count the game as
  single-threaded, so with no engine guard answering the whole cleanup is skipped, where before it still cleared the
  pipeline's map state and asked Remix for its purge. Left as it is: the module cannot work without that pointer, there
  is no uncache to protect then, and with the engine guard answering nothing changes. Not worth another native build.
- **A refusal with no copy installed says only "the engine guard's queue flush is not available".** Left as it is: the
  export gives no reason with -1. The start-up console then has no "Queued render calls are checked" line, and the Lua
  field `nlengineguard.queue_check` says why the queue check did not install. (A copy that installed with its flush off
  answers 0 with that reason, which the purge line prints.)
- **Wording**: "until the next map" for a skipped purge is now "until a later cleanup can run"; an absolute local path
  in `tools/ci/README.md`'s build example is now a placeholder.

## Notes and open questions

1. **The companion's `ShutDown` restores** (ADR 0261's note 3) are still pointless for materials about to be uncached;
   leaving them out when the fixes' cleanup will run would remove the most common source of such setters.
2. **A refusal in the real game** (no engine guard, or its flush off after a game update, with queued rendering on) is
   covered only by the regression: every purge is then skipped with its line, the console command's too.
3. **The last frame's list was never at risk.** The reviewer supposed the uncache could race the render thread's run of
   the last frame's list. It could not: `UncacheAllMaterials` takes the material system's lock itself, and that lock
   waits for the render job (read in the machine code, RESEARCH has it). Only this frame's list was left, because under
   that lock the engine flushes the hardware context, not the queued one.
