# Remix's geometry workers sleep when idle (report)

Claude, 2026-11-17, on the branch `remix-workers` (worktree `out\worktrees\rwk`): runtime patch 0105 (fork branch
`claude/remix-workers`, commit `0165da89b` on 0104's `8cd421cd8`) and the runtime part's `d3d9.dll` built from it, a
gate test and a PoC measurement driver. No loader (`winmm.dll`), Lua or other part changes. Decision:
[ADR 0243](../decisions/0243-the-geometry-workers-sleep-when-idle.md).

## The request

The user asked on 2026-11-17 for the second load speed-up plan's remaining items (`out/load-speedup-2/PLAN.md` of the
main checkout). This is its item S1, "Remix's geometry workers wait instead of spinning": in the user's field game the
two `geometry-processing` threads used 100 % of a core each from about 12 s after the start to the end of the session,
also idle in the main menu (74 % of their samples in `ZwDelayExecution`). The plan asked for a frame-time A/B at 4K
and in VR, since the mode exists for latency.

## The cause

`D3D9Rtx::GeometryProcessor` (`d3d9_rtx.h:220`) is a `WorkerThreadPool<kMaxConcurrentDraws>`, which takes the pool's
default `LowLatency = true` (`util_threadpool.h:286`). In that mode an idle worker loops over its own queue, tries to
steal from the other workers' and calls `std::this_thread::yield()`, with no wait of any kind. The workers hash each
ray-traced draw's geometry, compute its bounding box and skin it on the CPU; DXVK's command thread takes the results
when it commits the draw. The pool appears at the first draw Remix hashes (3.3-6.6 s after the start in the PoC, in
the main menu) and lives as long as the device. The other two pools (ray tracing pipelines, asset exports) are
high-latency pools that wait on a condition variable. Facts with file and line: [RESEARCH.md](../RESEARCH.md), "The
geometry workers' idle loop".

## What changed

- **Runtime patch `0105-The-geometry-workers-sleep-when-idle-instead-of-poll.patch`**
  ([runtime/README.md](../../runtime/README.md)):
  - `src/util/util_worker_idle.h` (new, the standard library only): `kWorkerSpinWindow` (1 ms); `WorkerSpin`, one
    worker's rounds without a task (the window starts at the first such round, a task ends it, a worker woken without
    a task keeps its old window and sleeps again at once); `WorkerSleep<Mutex, Condition>`: `sleep(ready)` counts the
    worker as a sleeper, then waits under the mutex on `ready`; `wake(all)` reads the count and, only when a worker
    sleeps, notifies one (or all) under the mutex; `stop()` notifies all.
  - `src/util/util_threadpool.h`: `processWork` restarts the window after a task it ran or stole, yields within the
    window as before and then sleeps on `m_numTasks > 0 || m_stopWork` (the high-latency mode's own predicate);
    `Schedule` calls `wake(!WorkStealing)` after the push and `++m_numTasks`; the destructor calls `stop()` after the
    stop flag; an `IdleSleep` member (`Nop` in high-latency pools). Every added line is in an `if constexpr
    (LowLatency)` step or a declaration; the high-latency lines are untouched.
  - Why no wake-up is lost: the worker increments the sleeper count, then tests the task count under the mutex;
    `Schedule` increments the task count, then reads the sleeper count; all four are sequentially consistent, so
    either the test sees the task or `Schedule` sees the sleeper, and a notify under the mutex cannot fall between a
    sleeper's test and its wait.
  - `tests/rtx/unit/test_worker_idle.cpp` (156 checks, std only), both `meson.build` lists, and an entry in the fork's
    `docs/fork-touchpoints.md` (the fork's rule for an upstream file). No AI co-author trailer (the fork's rule).
- **The runtime part:** `packages/runtime/files/d3d9.dll` rebuilt by `runtime\build_runtime.ps1` (0001-0105):
  479,886,336 bytes, SHA-256 `541806a9fa1f00504c2a24ea0e0f707a0a051bf12108b9355ef8f6735a64262c` (70,854,432 bytes xz);
  `runtime/base.json`'s `packaged` record.
- **The gate:** [test_runtime_remix_workers.py](../../tools/tests/test_runtime_remix_workers.py.md).
- **The PoC driver:** [tools/qa/remix_workers_session.py](../../tools/qa/remix_workers_session.py.md).

## The window

`kWorkerSpinWindow` is 1 ms. Waking a sleeping worker costs 14 µs (median of 200, at most 66 µs) on this machine, so a
pause between draws that ends in a wake-up grows by a few percent at most, and a pause shorter than the window never
meets a sleeper: the draws of a frame keep the latency they had. A frame is 4 to 16 ms (11 ms at 90 Hz in VR), so the
workers sleep between the frames' draws when the game waits for the GPU, and whenever no draw comes at all. The
measurements below bear both out: at 4K (GPU-bound, 12 ms frames) the workers sleep 60 % of the time, in VR (45 pairs
a second) 75 %, at 1280x720 (CPU-bound, 4.9 ms frames, draws more often than every millisecond for most of the frame)
8 %, and no frame got slower in any of them. A shorter window would free more of a CPU-bound frame at the price of more wake-ups inside it; not needed for
the plan's aim, not measured.

## Verified

- **The gate's test** ([test_runtime_remix_workers.py](../../tools/tests/test_runtime_remix_workers.py.md)): the
  helper's unit test from the patch (`PASS worker idle: 156 checks`); the real `util_threadpool.h` rebuilt from the
  fork's base commit and patches 0001-0105 and run with the runtime's flags: 20,000 tasks right, the idle workers 0.0 ms
  of CPU in 500 ms, a task to two sleeping workers 14 µs (median of 200), 1,500 tasks at the window's edge, stops with
  sleeping or polling workers (`PASS remix workers: 49 checks`); against patches 0001-0104 the same harness fails only
  the idle check, the workers using 1,031 ms of CPU in the 500 ms. The full Release gate: see below.
- **The runtime's unit suite** (`meson test --suite dxvk` in the fork tree after the build): 63 of 65 pass, among them
  `test_worker_idle` and upstream's `util_threadpool` (8 workers, 2,000 tasks, cancellations; 22 s).
  `test_remix_api_version` fails in the build folder with 0xC0000139, Windows loading System32's `d3d9.dll` first, and
  passes beside the built DLL; `test_remix_categories` cannot load `d3d9.dll` in its process, as before.
- **The PoC** ([remix_workers_session.py](../../tools/qa/remix_workers_session.py.md), evidence in this worktree's
  `out\remix-workers\poc-ab2`): package A is the published `0.0.0-dev.20261117062035+0e16daa5` (`d3d9.dll`
  `f88d381d...`, patches 0001-0104), B this branch's build (`541806a9...`); they differ only in `d3d9.dll` and the
  manifest (checked entry by entry). Every session loaded the intended DLL (its SHA-256 from the game's modules), quit
  normally and put the PoC's `config.json` and the video settings back. Sessions alternated A B B A (and A B B A A B
  at 4K) after a warm-up with A; the machine was 8-22 % busy before each session (a 16-core Ryzen 9 9950X3D, an
  RTX 5090), once with a `cl.exe` of another task running (menu-B2). The `geometry-processing` threads, in percent of
  one core each:

  | Where | A: before (0104) | B: with 0105 |
  |---|---|---|
  | Main menu at start, 30 s (1280x720) | 99.5 + 99.8, 99.4 + 99.7 | 0.0 + 0.0, 0.0 + 0.0 |
  | Main menu after a map, 30 s | 99.2 + 99.0, 99.6 + 99.5 | 0.0 + 0.0, 0.0 + 0.0 |
  | gm_construct, 1280x720, 60 s | 99.3 + 99.3, 99.4 + 99.6 | 91.2 + 91.5, 91.1 + 91.4 |
  | gm_construct, 3840x2160, 60 s | 98.5 + 98.7, 99.5 + 99.5, 99.7 + 99.6 | 40.3 + 40.3, 39.5 + 39.7, 40.4 + 40.5 |

  The whole game process in the main menu: 255-267 % of a core before, 59-67 % with 0105. At 4K: 384-391 % before,
  260-264 % with 0105 (215 % in the one session whose DLSS frame generation pacer thread stayed idle). At 1280x720 the
  process total hardly moves (502-508 % against 491-500 %): the game's own threads use what the workers leave.
- **Frame times** (every frame for 60 s in a `PostRender` hook, fixed camera, no HUD, `fps_max 0`):

  | | A: before | B: with 0105 |
  |---|---|---|
  | 1280x720, median / p99 (ms) | 4.82 / 8.67, 4.78 / 7.75 | 4.86 / 7.82, 4.77 / 8.16 |
  | 1280x720, frames a second | 197.4, 206.5 | 202.9, 205.0 |
  | 3840x2160, median / p99 (ms) | 12.66 / 27.3, 12.16 / 20.5, 12.55 / 17.6 | 12.10 / 15.0, 12.06 / 14.8, 12.25 / 15.1 |
  | 3840x2160, mean (ms) | 13.30, 12.33, 12.66 | 12.14, 12.10, 12.26 |
  | 3840x2160, frames over twice the median | 61, 25, 9 | 1, 4, 0 |

  No frame got slower: at 1280x720 the two are within the sessions' spread; at 4K the median is 2.6 % lower and the
  99th percentile 15 ms against 18-27 ms with 0105, with fewer stalls (two A sessions also had one frame of 1.2-1.4 s,
  B none above 70 ms). Three sessions each are few, so read the 4K gain as "not slower", the stalls as a likely gain:
  two threads yielding in a loop compete with the game's, DXVK's and the driver's threads for cores.
- **VR** on the Valve Index (`tools/vr_session.py --seconds 60`, live, unattended, the same two packages, twelve runs in
  the order A B B A, B A A B, B A A B; each run takes and releases both locks, installs the package into a snapshotted
  PoC and verifies its rollback; evidence in this worktree's `out\remix-workers\vr`, where the scripts that read the
  game's threads during each run's steady window, `vr_thread_sampler.py` and `vr_analyse.py`, also stay, uncommitted).
  Every run quit normally and its rollback verified clean (the depot check, the registry, the protected files). SteamVR was not running and the first run started it at 01:38; it was left running, as the
  VR rules say. The PoC renders at the half rate the Index allows at 90 Hz, 45 pairs a second, GPU-bound (22 ms):

  | Per run, steady window of about 52 s | A: before (6 runs) | B: with 0105 (6 runs) |
  |---|---|---|
  | `geometry-processing` threads, % of a core each | 98.8-100.2 | 23.1-25.5 |
  | Pairs a second (cap 45) | 44.34-45.00, mean 44.63 | 43.40-45.00, mean 44.55 |
  | Reprojected, % | 50.1-51.1, mean 50.7 | 50.1-52.8, mean 50.9 |
  | Dropped | 0 | 0 |
  | GPU per pair (ms) | 22.16-22.47, mean 22.33 | 21.61-22.80, mean 22.12 |
  | The render thread's CPU per pair (ms) | 4.38-4.65, mean 4.52 | 4.53-5.17, mean 4.73 |
  | `dxvk-cs`, % of a core | 18.4-19.5 | 19.7-22.5 |

  The pair rate is the same within the runs' spread (B's lowest, 43.4, was its first run; its others 44.4-45.0). DXVK's
  command thread uses about 0.2 ms more CPU per pair with 0105 (5 % more), most likely polling a result in
  `Result::get` while a woken worker starts: in VR the command thread follows the game closely, so it meets a task
  just scheduled after a pause more often than in flat play, where its CPU did not change (27-30 % at 4K either way).
  It did not show in the pair rate or the reprojection.

## The PoC lock

The first series (`out\remix-workers\poc-ab1`) held `out\r10\poc.lock` for the whole series, by exclusive create
(`vr_session.ExclusiveLock`). The coordinating session reported that its field run's lock had been replaced and that the
two runs overlapped from about 00:53 to 00:57 local. The records show the field run's game exiting at 00:55:01
(`out/load-speedup-2/runs/r3-b1-mh-gc/run.json` in the main checkout), its lock released at 00:55:02, the series waiting
for it from 00:53:06 and taking it at 00:55:02, its first game starting at 00:55:09. As asked, the series was stopped,
its warm-up (the only session it had measured, from 00:55) discarded, the PoC put back (the game quit after the field's
settings, `config.json` and the video settings restored, the lock removed as its own), and the driver changed to one
lock hold per session with a gap after each (its own `SessionLock`: exclusive create, a poll every second, never
deleting or overwriting another owner's file, removing only its own pid and token). The series reported above
(`poc-ab2`) ran that way, interleaved with the field runs; `vr_session.py` holds both locks for one run each.

## What is left

- **The Release gate** passed on `fdf6b791` (`tools\test.ps1 -Config Release` with `NL_FIXES_CLONE`, 6.4 min): the
  conventions, 35 of 35 CTests, 2,118 Python tests in `tools` (one skipped, not this one: its seven tests ran, with the
  fork's clone), 29 in `tools\gmapack` and 26 in `tools\steam`.
- **Not checked in the field install** (the user's game is not touched); it takes the runtime with the next package.
- **In a CPU-bound map the workers still poll most of the time** (91 % each at 1280x720 and 200 frames a second):
  draws come more often than every millisecond there. A shorter window would free more of it at the price of a wake-up
  inside a frame; it was not measured, and the plan's aim (menus, loads, the GPU-bound frame) is met.
- **The high-latency mode's order** (notify, then count; RESEARCH.md) is upstream's and left as it was: a worker woken in
  between waits for the next task. The two pools using it are off the frame's path.
- **An upstream merge** that changes `util_threadpool.h` meets 0105's few lines; `util_worker_idle.h` and the unit test
  are the fork's own.

## Published

Merged into `load-speedup-3` (`2ef7ee21`) and with it into `main` as `ff2343ef`, after the full Release gate passed on
the merged state, and pushed (`cf8d7137..ff2343ef`). The merge's hook uploaded item 3829070317 as
**`0.0.0-dev.20261117102000+a8e6cb04`** (content digest `52682d8a...`); its change note carries this change's
changelog section with round 3's. The field game takes the new `d3d9.dll` at its next start; the workers' idle sleep
has not been run in the field.
