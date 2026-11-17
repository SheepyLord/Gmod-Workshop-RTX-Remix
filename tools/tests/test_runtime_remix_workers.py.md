# test_runtime_remix_workers.py

Checks runtime patch `0105-The-geometry-workers-sleep-when-idle-instead-of-poll.patch`
([runtime/README.md](../../runtime/README.md), [ADR 0243](../../docs/decisions/0243-the-geometry-workers-sleep-when-idle.md)):
an idle worker of the runtime's low-latency `WorkerThreadPool` (the two geometry workers) polls for
`kWorkerSpinWindow` (1 ms) after its last task, then sleeps until a task is counted or the pool stops, instead of
polling and yielding without end (two cores busy from the first draw to the end of the game).

```powershell
cd tools; python -m unittest tests.test_runtime_remix_workers
```

| Test | Checks |
|---|---|
| the helper's unit test from the patch | writes `src/util/util_worker_idle.h` and `tests/rtx/unit/test_worker_idle.cpp` as the committed patch creates them into `out\tmp`, compiles them with MSVC (`/std:c++17 /W4 /WX`) and runs them: `PASS worker idle: N checks` (the window from the first empty round to 1 ms, kept by a woken worker, restarted by a task; a sleeper wakes for a counted task and at a stop; a pool shaped like the runtime's sleeps when idle, no longer polls, wakes for each task, loses no task scheduled at the window's edge; workers that cannot steal all wake; stops with sleeping or polling workers). Skipped without the VS 2022 Build Tools |
| the real pool sleeps when idle and wakes for a task | rebuilds the headers of `src/util` as the fork's base commit (`runtime/base.json`) and patches 0001-0105 make them, reading the base from a local clone of the fork (below); checks in the whole `util_threadpool.h` that `Schedule` wakes after the push and the task count's increment and the destructor after the stop flag and before the joins; compiles a harness with the runtime's flags (`/std:c++17 /W2 /WX`, `NOMINMAX`) against it, with stand-ins for `env::setThreadName` (which records each worker's thread) and `thread::hardware_concurrency`, and runs the real pool as the geometry workers use it: 20,000 tasks with their results; the idle workers' CPU time (`GetThreadTimes`) over 500 ms below 50 ms; 200 tasks each scheduled to two sleeping workers, median latency under 5 ms and none over 250 ms (printed); 1,500 tasks after pauses of 0-2.5 ms all run; pools with two or four sleeping workers, and with polling ones, stop within a second. A watchdog ends the harness if a task never runs. The high-latency pools (`<64, true, false>`, `<64, false, false>`) are compiled, not run. Skipped without the Build Tools or a clone |
| without 0105 idle workers poll | the same harness against the headers of patches 0001-0104: only the idle check fails, the two workers using more than 100 ms of CPU in the 500 ms (about 1,000 ms measured on 2026-11-17) |
| the helper is self-contained and waits without losing a wake-up | the header includes `<atomic> <chrono> <cstdint> <mutex>` only; the window is 1,000 microseconds; `sleep` takes the lock, counts itself, waits on its predicate, uncounts itself, in that order; the count starts at zero; `wake` reads the count without a lock and notifies (one, or all) under it; `stop` notifies all under it |
| the pool wakes after counting and sleeps on its count | the patch's hunks of `util_threadpool.h`: the include, the `IdleSleep` type and member; `m_idleSleep.wake(!WorkStealing)` right after `++m_numTasks;`; a task or a stolen one restarts the window; the worker yields within it, then sleeps on `m_numTasks > 0 \|\| m_stopWork.load()`; the destructor's `stop()` after the high-latency notify |
| the high-latency mode is untouched | the patch removes only the old one-line `if`, the steal block's own `workStolen` and its yield; no line naming `m_condOnAdd`, `m_taskMutex`, `TaskMutex` or `OnAddCondition` is added; each of the three new steps is `if constexpr (LowLatency)` |
| the patch lists its files and the fork touchpoint | the patch changes exactly `util_threadpool.h`, `util_worker_idle.h`, both `meson.build` files, the unit test and `docs/fork-touchpoints.md` (the fork's rule: an entry for the upstream file); meson lists the header and `test_worker_idle`; the commit carries no AI co-author trailer (the fork's rule) |

**The fork's clone** (read only, `git ls-tree` and `git cat-file` of `src/util` at the base commit): `NL_RUNTIME_CLONE`,
else the main checkout's runtime worktree `out\worktrees\r17\out\runtime-src`, else `dxvk-remix-gmod` beside the main
checkout, else `E:\Modding_Backup\dxvk-remix-gmod`; the first that holds the base commit.

Writes only scratch folders under `out\tmp`, removed afterwards. Exit 0 when every test passes. About 25 seconds.
