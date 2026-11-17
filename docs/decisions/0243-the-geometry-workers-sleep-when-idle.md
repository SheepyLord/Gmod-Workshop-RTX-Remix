# 0243: The geometry workers sleep when idle

- Status: Accepted 2026-11-17 (the user's request to do the second load speed-up plan's remaining items; this is its
  item S1)
- Decided by: the agents, from the plan's measurement (`out/load-speedup-2/PLAN.md` of the main checkout, section 2.2
  and S1); runtime patch `0105-The-geometry-workers-sleep-when-idle-instead-of-poll.patch`
  ([runtime/README.md](../../runtime/README.md)); no loader or package code change.
- Report: [remix-workers-report.md](../handover/remix-workers-report.md).

## Context

The runtime's geometry workers hash each draw's vertices and indices, compute its bounding box and skin it on the CPU
(`D3D9Rtx::computeHash`, `computeAxisAlignedBoundingBox`, `processSkinning`), off the game's thread; DXVK's command
thread takes the results when it commits the draw. They are a `WorkerThreadPool<kMaxConcurrentDraws>` (`d3d9_rtx.h:220`),
two threads by default (`rtx.numGeometryProcessingThreads`), which takes the pool's default `LowLatency = true`
(`util_threadpool.h:286`). In that mode an idle worker never waits: it polls its own queue, tries to steal from the
others and calls `std::this_thread::yield()`, again and again. The plan measured the user's field game: both
`geometry-processing` threads at 100 % of a core each from about 12 s after the start to the end of the session, in
the main menu too, where 74 % of their samples were in `ZwDelayExecution`. On a computer with six or eight cores that
is a quarter or a third of the processor taken from the game, its loads and the driver, and power and heat at all
times. Only the geometry workers use the mode: the ray tracing pipelines' pool (`dxvk_raytracing.cpp:103`) and the
asset exporter's (`rtx_asset_exporter.h:73`) are high-latency pools, which wait on a condition variable.

## Decision

1. **A low-latency worker polls for `kWorkerSpinWindow` (1 ms) after its last task, then sleeps.** A task it runs or
   steals starts the window again; within it the worker polls and yields as before, so the draws of a frame meet
   awake workers. Past it the worker sleeps on a condition variable (the pool's `dxvk::mutex` and
   `dxvk::condition_variable`) until `m_numTasks > 0 || m_stopWork`, the high-latency mode's own predicate. A worker
   woken without finding a task sleeps again at once: the window counts from its last task.
2. **`Schedule` wakes a sleeper only when one sleeps.** After the push and the task count's increment it reads an
   atomic count of sleepers; at zero it does nothing more (no lock, no system call), otherwise it notifies one sleeper
   under the mutex, or all of them in a pool whose workers cannot steal.
3. **No wake-up is lost.** A worker counts itself as a sleeper and then, under the mutex, tests the predicate before it
   waits; `Schedule` increments the task count and then reads the sleeper count, both sequentially consistent. Either
   the worker's test sees the task, or `Schedule` sees the sleeper, and its notify under the mutex reaches the worker,
   which holds that mutex from its test until it waits.
4. **The destructor wakes every sleeper** after setting the stop flag, under the same mutex.
5. **The window is 1 ms,** a constant (no option): long against waking a sleeping thread (14 µs median, 66 µs at most
   on this machine), so a pause between draws that ends in a wake-up grows by a few percent at most and a shorter
   pause never meets a sleeper; short against a frame (4 to 16 ms at 60 to 240 frames a second, 11 ms at 90 Hz in
   VR), so the workers sleep between the frames' draws and in menus. Time, not a count of rounds: a yield's length
   depends on what else the machine runs.
6. **Nothing else changes.** The high-latency mode, the other pools, the queues, the futures and `Result::get`'s own
   polling are as before. The code follows the fork's rules: the logic in a self-contained header of its own
   (`src/util/util_worker_idle.h`), a few marked lines in `util_threadpool.h`, an entry in `docs/fork-touchpoints.md`,
   a unit test (`tests/rtx/unit/test_worker_idle.cpp`), no AI co-author trailer.

## Consequences

- The two cores the workers held are free whenever no draw comes for a millisecond: in menus, between the frames'
  draws, and while a map loads. In the PoC (report): the main menu 2 x 99 % of a core -> 0; gm_construct at 4K, where
  the game waits for the GPU, 2 x 99 % -> 2 x 40 %; at 1280x720 and 200 frames a second, where draws come all the
  time, 2 x 99 % -> 2 x 91 %.
- A draw that comes after such a pause waits for a worker to wake: tens of microseconds, once per pause. The
  command thread usually reaches the draw later than that; the frame-time A/B shows no slower frames (at 4K the
  median 2.6 % shorter and fewer stalls, at 1280x720 the same). In VR on the Index (45 pairs a second) the workers
  drop to 2 x 24 % and the pair rate stays (44.6 against 44.6 a second); DXVK's command thread there spends about
  0.2 ms more CPU per pair, polling while a woken worker starts, which did not show in the pair rate.
- An upstream merge that touches `util_threadpool.h` meets the patch's few lines; the header and the test are the
  fork's own files.
- The Release gate compiles the helper's unit test from the patch, and, with a local clone of the fork, compiles the
  real pool from the base commit and the patches and runs it: idle workers use no CPU, a task wakes them, none is
  lost at the window's edge, the pool stops with sleeping workers
  ([test_runtime_remix_workers.py](../../tools/tests/test_runtime_remix_workers.py.md)).
- Found on the way, left as it was: the high-latency mode notifies before it increments the task count
  (`util_threadpool.h:379-390` before the patch), so a worker woken in between can test its predicate too early and
  wait again until the next task; the two pools that use it are not on a frame's path.

## Alternatives considered

- **The existing high-latency mode for the geometry workers** (`LowLatency = false`): every `Schedule`, 2,000 to
  9,000 a frame, would take the mutex and notify, and each worker would sleep as soon as its queue drained in the
  middle of a frame; and its notify-before-count order can leave a draw's task waiting for the next one.
- **Timed waits** (sleeping 1 ms at a time, or `Sleep(0)` back-off): a timed sleeper wakes a thousand times a second
  for nothing and meets a new task up to a timer period late (1 to 15.6 ms on Windows); a notified sleeper wakes when
  the task comes.
- **One geometry worker** (`rtx.numGeometryProcessingThreads 1`): halves the polling, keeps it, and costs throughput
  in busy scenes.
- **A window option:** no measurement asks for another value; a constant keeps the change small.
