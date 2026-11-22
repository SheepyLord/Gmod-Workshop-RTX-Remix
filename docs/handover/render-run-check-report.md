# The crash at disconnect that the check did not catch: report

By Claude, 2026-11-21, on the branch `render-run-check`; package only (the engine guard). Decision:
[ADR 0254](../decisions/0254-queued-render-calls-checked-again-while-the-game-runs-them.md), extending
[ADR 0247](../decisions/0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md). Facts and
offsets: [RESEARCH.md](../RESEARCH.md), "The crash at disconnect that the check did not catch".

## What the user reported

"Disconnecting from a map / server still causes fast termination crash, when a session is long / with lots of things
spawned." The dialog: "Garry's Mod closed unexpectedly", exit 0xC0000409 (fail-fast termination), and the loader's
evidence folder of 2026-11-22 01:50 UTC. The game had run 1 h 37 min, in the package published that evening
(`0.0.0-dev.20261122004027+d17b0fb8`, ADR 0247's check included).

## What it was

- **The same path and the same call.** GMod's dump: `disconnect` > `AllowThreading(false)` > `ForceSingleThreaded` >
  `EndQueue(true)` on context 1 > `CallQueued`, failing at the 660th call of the list being recorded: element +0x2938
  of context 1's arena, exactly the element of the 2026-11-19 crash. Its object pointer led into a 256 KB heap block
  whose first word was another address in it (a free list's link), so the call went through stale bytes.
- **ADR 0247's check had run and passed everything.** The runtime's crash dump keeps the main thread's whole stack.
  Below the engine's frames lies the check's own working array of the live classes it saw, 14 of them, with its count
  (14) right after, and the material system's `Unlock` frame where the check calls it: the walk ran over both lists,
  found every call live and dropped none (so it wrote no log). The 14 classes are all GMod's own queued calls (material
  and texture reference counts, material variables, render-context calls, and studiorender's `DestroyDecalList`).
- **So the list was written over during the run.** GMod never puts a queued call on the heap: every append site in
  materialsystem.dll, studiorender.dll, engine.dll and client.dll takes the call's object from the context's own arena
  and puts its element right after it (read from their code; the constructor points the queue's allocator at the list's
  own next-free-byte word). An element whose object is a heap address was therefore written over after the check,
  while `ForceSingleThreaded` ran the 659 calls before it. The stack just below `CallQueued` holds the frames of an
  allocation in tier0 from one of those calls. Which code writes there, and why only after long, crowded sessions, the
  dumps cannot say: neither keeps the arena.

## What was built

- `engine_guard/run_check.h`, `run_check.cpp`: what the check saw of every element (`Run::see`: its next and object
  words, the object's first four words, the 16 bytes before the element), the step that replaces the engine's per-call
  dispatch while a run is watched (`Run::step`), the records of what it found with the eight calls run before each, the
  dispatch's bytes and their rewrite (`dispatch_patch`).
- `engine_guard/queue_check.cpp`: `find_layout` also returns `CallQueued`'s dispatch (the start of the pattern ADR
  0247 finds once); at install the dispatch must hold the engine's ten bytes and a read-only slot within reach
  (`allocate_near`, now shared from `guard.cpp`) holds the step; `hook_allow` keeps the elements after its walk (still
  under the lock), rewrites the dispatch, calls the engine's `AllowThreading`, puts the bytes back and logs what the step
  found. A nested `AllowThreading(false)` inside a watched run gets the engine's function alone. In a test session
  (`-nl_queue_check_test`) each check also queues a pair of the module's own calls, the first writing over the second's
  element as the field found it. `nlengineguard.run_check` (how the install went) and `QueueCheck()`'s four new counts
  (runs, put back, skipped, ended) in `module.cpp`.
- `engine_guard/tests/test_run_check.cpp` (seven tests) and the dispatch's bytes in `test_queue_check.cpp`'s layout
  test on the installed game's `materialsystem.dll`.
- `tools/qa/queue_check_session.py`: the run check's console lines and log records counted; a busy kind that crowds
  the second map with `tools/qa/queue_busy_server.lua` (props, ragdolls, fighting NPCs, explosions, decals) before the
  disconnect.
- The fixes part's `gmcl_` and `gmsv_nlengineguard_win64.dll`, rebuilt and recorded (`repo_builds.py refresh`).

## Tests

- **Unit tests** (CTest `nl_engine_guard_tests`, 66 cases, all pass): the seven run-check tests on engine-like lists
  (nothing changed when nothing is written over; the field's case put back and run; changed objects skipped; a call's
  own link put back; no call run twice in a nested run or through a link leading back; appended calls followed,
  strangers judged, stray links ended; a list it could not keep; the record limit; other threads and idle runs) and
  the rewritten dispatch executed as machine code (the engine's loop in a page of its own, patched to a slot from
  `allocate_near`, the field's case put back, the original bytes restored). The layout test found the dispatch in the
  installed game at +0x31040 with the engine's exact bytes.
- **PoC** (`tools/qa/queue_check_session.py`, under `out\r10\poc.lock`; evidence `out\run-check\run1` in the main
  checkout; the branch's package; RTX on with the package's add-ons, `gm_construct`, `map gm_flatgrass`, then
  `disconnect` and quit):
  - **Test session** (`-nl_queue_check_test`, the package's first start): exit 0 after 80 s, no Lua error. The run
    check installed from the menu (console). At the level change the walk dropped the stale test call (1,615 calls),
    and while the game ran the list the step put back the test pair's victim, whose element the call before it had
    written over with a heap block's address, and ran it: 1,614 calls run, 1 put back. At `disconnect` the same with
    1,017 calls. The log names the call run just before the put-back one (the test's writer), then GMod's own.
  - **Plain session**: exit 0 after 61 s; nothing dropped, put back or skipped, no log written.
  - **Busy session** (`queue_busy_server.lua` in gm_flatgrass for 240 s before `disconnect`): exit 0 after 298 s, no
    Lua error; at its last count, 30 s before the disconnect, the map held 1,388 entities (1,300 props spawned, 113
    ragdolls, 24 NPCs fighting, 630 explosions so far, bullets and blood decals every second). Nothing dropped, put
    back or skipped: the PoC did not reproduce the field's writer, as the series of 2026-11-15 did not reproduce the
    earlier crash.
  - Afterwards the PoC was restored and verified clean (`restoration.json`), its `user.conf` unchanged.
- **The gate** (`tools\test.ps1 -Config Release` in `out\worktrees\rck`, `NL_FIXES_CLONE` set): CTest 35 of 35 passed;
  of the 2,184 Python tests one failed, `test_vr_review_docs`' rule that a branch only adds rows to the shared
  decision index (this branch had also noted "extended by 0254" in ADR 0247's row). The row went back as it was (the
  note stays in ADR 0247's own status line) and `tools\test.ps1 -SkipNative` then passed.
- **The build that went out.** After the series two small changes were made: a nested `AllowThreading(false)` during
  a watched run now gets the engine's function alone (never seen; it would have reset the run's records), and the
  test's console line counts only its own run's victim. The unit tests passed again with them. The PoC could not run
  the series again: another session's long PoC game (a map remaster's look at 4K) started as this series released the
  lock, and it was left alone.

## Not covered

- The writer itself. If a field game meets it again, the log names the calls run just before the put-back or skipped
  call; that is the next fix's lead. If the writes come from heap bookkeeping gone wrong, a later step of the
  disconnect may still fail elsewhere.
- The render thread's own runs of the lists in normal frames, and the material system's other runners: the dispatch
  is rewritten only for the length of `AllowThreading(false)`.
- An object written over with bytes that look the same in its first 32.

## Published

Under the standing permission (AGENTS.md rule 5: `main` pushed and item 3829070317 updated once `tools\test.ps1`
passes; the gate's results above). Fast-forwarded `main` from `11e21cf0` to `f1629dc9` (the branch's three commits);
the merge's hook built the package here and uploaded item 3829070317 as **`0.0.0-dev.20261122030548+82015679`**: content digest
`314d5a31...`, the same as the branch's final local build, with one change note carrying the new changelog section.
The field game deploys it at its next start; if a run check event is ever logged there, its record in
`garrysmod/data/native-loader/render-queue-check.log` names the calls run just before it.
