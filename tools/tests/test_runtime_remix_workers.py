"""The geometry workers sleep when idle (runtime patch 0105; S1 of the second load speed-up plan, ADR 0243).

The low-latency mode of the runtime's WorkerThreadPool, which D3D9Rtx's two geometry workers use, let an idle worker
poll and yield without end: two cores busy from the first draw to the end of the game. With 0105 an idle worker polls
for kWorkerSpinWindow (1 ms) after its last task, then sleeps until a task is counted or the pool stops.

Compiles and runs the helper's unit test from the committed patch (MSVC, as the runtime builds it); compiles a harness
against `src/util/util_threadpool.h` as the fork's base commit and the runtime patches make it, read from a local
clone of the fork (skipped without one), and runs the real pool: tasks run, idle workers use no CPU, a task scheduled
to sleeping workers runs at once, the pool stops with sleeping or polling workers; the same harness without 0105 shows
the idle workers polling. Checks the pool's wiring in the patch and that its high-latency mode is untouched."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import runtime_patch_text as patches  # noqa: E402

REPO = patches.REPO
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
HAVE_MSVC = os.name == 'nt' and VS.is_dir()
NUMBER = 105
POOL = 'src/util/util_threadpool.h'
IDLE = 'src/util/util_worker_idle.h'
IDLE_TEST = 'tests/rtx/unit/test_worker_idle.cpp'
UTIL = 'src/util/'


def patch_text() -> str:
    return patches.read(patches.one_patch(NUMBER))


def main_checkout() -> Path:
    common = subprocess.run(['git', '-C', str(REPO), 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                            capture_output=True, text=True)
    if common.returncode == 0 and common.stdout.strip():
        return Path(common.stdout.strip()).parent
    return REPO


def runtime_clone():
    """(a git folder of the runtime fork holding base.json's commit, the commit), or None: NL_RUNTIME_CLONE, the main
    checkout's runtime worktree (out/worktrees/r17/out/runtime-src) or dxvk-remix-gmod beside the main checkout. Only
    read."""
    commit = json.loads((REPO / 'runtime' / 'base.json').read_text(encoding='utf-8'))['commit']
    main = main_checkout()
    candidates = [os.environ.get('NL_RUNTIME_CLONE', ''), str(main / 'out' / 'worktrees' / 'r17' / 'out' / 'runtime-src'),
                  str(main.parent / 'dxvk-remix-gmod')]
    for candidate in filter(None, candidates):
        path = Path(candidate)
        if (path / '.git').exists() and subprocess.run(
                ['git', '-C', str(path), 'cat-file', '-e', f'{commit}^{{commit}}'], capture_output=True).returncode == 0:
            return path, commit
    return None


def base_headers(clone: Path, commit: str) -> dict:
    """{path: text} of every header under src/util at the fork's base commit."""
    names = subprocess.run(['git', '-C', str(clone), 'ls-tree', '-r', '--name-only', commit, '--', UTIL],
                           capture_output=True, text=True, check=True).stdout.split('\n')
    names = [name for name in names if name.endswith('.h')]
    batch = subprocess.run(['git', '-C', str(clone), 'cat-file', '--batch'], capture_output=True, check=True,
                           input=''.join(f'{commit}:{name}\n' for name in names).encode('utf-8')).stdout
    files, at = {}, 0
    for name in names:
        end = batch.index(b'\n', at)
        size = int(batch[at:end].split(b' ')[2])
        files[name] = batch[end + 1:end + 1 + size].decode('utf-8')
        at = end + 1 + size + 1
    return files


def patched_headers(clone: Path, commit: str, upto: int) -> dict:
    """src/util's headers as the base commit and the runtime patches numbered up to `upto` make them."""
    files = base_headers(clone, commit)
    for path in patches.patch_paths():
        if int(path.name[:4]) > upto:
            break
        text = patches.read(path)
        if f'diff --git a/{UTIL}' not in text:
            continue
        for name, block in patches.file_blocks(text).items():
            if not (name.startswith(UTIL) and name.endswith('.h')):
                continue
            head = block.split('@@', 1)[0]
            if 'deleted file mode' in head:
                files.pop(name, None)
            else:
                files[name] = patches.apply(None if 'new file mode' in head else files[name], block, name)
    return files


HARNESS = r'''// The geometry workers' pool (util_threadpool.h, low-latency mode with work stealing, as D3D9Rtx::GeometryProcessor)
// with runtime patch 0105: tasks run, idle workers sleep instead of polling, a task scheduled to sleeping workers runs
// at once, and the pool stops with sleeping or polling workers. Built against src/util as the fork's base commit and
// the runtime patches make it; the two functions the runtime links from util_env.cpp and thread.cpp are stand-ins.
#include "util_string.h"
#include "util_threadpool.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <memory>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {
  std::mutex g_namesMutex;
  std::vector<std::pair<std::string, DWORD>> g_names;
}

namespace dxvk {
  namespace env {
    // The pool names each worker "<name>(<index>)" on the worker's own thread: the harness keeps its thread id.
    void setThreadName(const std::string& name) {
      std::lock_guard<std::mutex> lock(g_namesMutex);
      g_names.emplace_back(name, GetCurrentThreadId());
    }
  }

  uint32_t thread::hardware_concurrency() {
    return std::max(2u, std::thread::hardware_concurrency());
  }
}

// The high-latency pools (the ray tracing pipelines', the asset exporter's) still compile; they are not run here.
void highLatencyPoolsCompile() {
  dxvk::WorkerThreadPool<64, true, false> pipelines(2, "pipelines");
  pipelines.Schedule([] { return 1; }).get();
  dxvk::WorkerThreadPool<64, false, false> exports(1, "exports");
  exports.Schedule([] { }).get();
}

namespace {
  using Clock = std::chrono::steady_clock;
  using std::chrono::milliseconds;
  using std::chrono::microseconds;
  // As D3D9Rtx::GeometryProcessor (kMaxConcurrentDraws there; the queues' size does not matter here).
  using Pool = dxvk::WorkerThreadPool<1024>;

  int g_checks = 0;
  int g_failures = 0;

  void check(bool condition, const char* what, int line) {
    ++g_checks;
    if (!condition) {
      ++g_failures;
      std::printf("FAIL line %d: %s\n", line, what);
      std::fflush(stdout);
    }
  }
#define CHECK(condition) check((condition), #condition, __LINE__)

  // A task that never runs would leave Future::get() polling for good: the watchdog ends the process instead.
  std::atomic<int64_t> g_deadline { 0 };
  const char* volatile g_phase = "start";

  void arm(const char* phase, milliseconds limit) {
    g_phase = phase;
    g_deadline = (Clock::now() + limit).time_since_epoch().count();
  }

  void watchdog() {
    while (true) {
      std::this_thread::sleep_for(milliseconds(50));
      const int64_t deadline = g_deadline.load();
      if (deadline != 0 && Clock::now().time_since_epoch().count() > deadline) {
        std::printf("FAIL watchdog: %s did not finish\n", g_phase);
        std::fflush(stdout);
        ExitProcess(3);
      }
    }
  }

  // CPU time (user and kernel, milliseconds) of the workers named "<name>(<index>)".
  double workersCpuMs(const std::string& name) {
    std::vector<DWORD> ids;
    {
      std::lock_guard<std::mutex> lock(g_namesMutex);
      for (const auto& entry : g_names) {
        if (entry.first.rfind(name + "(", 0) == 0) {
          ids.push_back(entry.second);
        }
      }
    }
    double total = 0.0;
    for (DWORD id : ids) {
      HANDLE thread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, FALSE, id);
      if (thread == nullptr) {
        continue;
      }
      FILETIME created, exited, kernel, user;
      if (GetThreadTimes(thread, &created, &exited, &kernel, &user)) {
        const auto ticks = [](const FILETIME& t) {
          return static_cast<double>((static_cast<uint64_t>(t.dwHighDateTime) << 32) | t.dwLowDateTime);
        };
        total += (ticks(kernel) + ticks(user)) / 10000.0;
      }
      CloseHandle(thread);
    }
    return total;
  }

  size_t workersNamed(const std::string& name) {
    std::lock_guard<std::mutex> lock(g_namesMutex);
    return static_cast<size_t>(std::count_if(g_names.begin(), g_names.end(), [&](const auto& entry) {
      return entry.first.rfind(name + "(", 0) == 0;
    }));
  }

  void testTasksRun() {
    arm("tasks run", milliseconds(30000));
    Pool pool(2, "run");
    std::atomic<uint64_t> sum { 0 };
    uint64_t expected = 0;
    for (int round = 0; round < 20; ++round) {
      std::vector<dxvk::Future<uint64_t>> futures;
      for (uint64_t i = 0; i < 1000; ++i) {
        futures.push_back(pool.Schedule([i, &sum] { sum += i; return i * 3; }));
        expected += i;
      }
      bool valid = true;
      bool right = true;
      for (uint64_t i = 0; i < futures.size(); ++i) {
        valid = valid && futures[i].valid();
        right = right && futures[i].get() == i * 3;
      }
      CHECK(valid);
      CHECK(right);
    }
    CHECK(sum == expected);
    CHECK(workersNamed("run") == 2);
  }

  void testIdleWorkersSleep() {
    arm("idle workers sleep", milliseconds(30000));
    Pool pool(2, "idle");
    for (int i = 0; i < 100; ++i) {
      pool.Schedule([] { return 1; }).get();
    }
    // Long past the spin window (kWorkerSpinWindow, 1 ms): both workers sleep. Polling, each would take most of a
    // core over the half second measured.
    std::this_thread::sleep_for(milliseconds(100));
    const double before = workersCpuMs("idle");
    std::this_thread::sleep_for(milliseconds(500));
    const double used = workersCpuMs("idle") - before;
    std::printf("idle workers: %.1f ms of CPU in 500 ms\n", used);
    CHECK(workersNamed("idle") == 2);
    CHECK(used < 50.0);
  }

  void testATaskWakesSleepingWorkers() {
    arm("a task wakes sleeping workers", milliseconds(60000));
    Pool pool(2, "wake");
    std::vector<double> latencies;
    for (int i = 0; i < 200; ++i) {
      // Past the window: every task below meets two sleeping workers.
      std::this_thread::sleep_for(milliseconds(4));
      const Clock::time_point scheduled = Clock::now();
      const Clock::time_point ran = pool.Schedule([] { return Clock::now(); }).get();
      latencies.push_back(std::chrono::duration<double, std::micro>(ran - scheduled).count());
    }
    std::sort(latencies.begin(), latencies.end());
    const double median = latencies[latencies.size() / 2];
    const double worst = latencies.back();
    std::printf("a task to sleeping workers ran after %.0f us (median), %.0f us (slowest of %zu)\n", median, worst,
                latencies.size());
    CHECK(median < 5000.0);
    CHECK(worst < 250000.0);
  }

  void testNoTaskIsLeftAtTheWindowsEdge() {
    arm("tasks at the window's edge", milliseconds(60000));
    // Tasks after pauses on both sides of the window, the scheduler not waiting for them: it often counts a task just
    // as a worker goes to sleep. Every task runs.
    Pool pool(2, "edge");
    std::mt19937 random(105);
    std::uniform_int_distribution<int> pause(0, 2500);
    std::vector<dxvk::Future<int>> futures;
    for (int i = 0; i < 1500; ++i) {
      const Clock::time_point until = Clock::now() + microseconds(pause(random));
      while (Clock::now() < until) {
      }
      futures.push_back(pool.Schedule([i] { return i; }));
    }
    bool right = true;
    for (int i = 0; i < static_cast<int>(futures.size()); ++i) {
      right = right && futures[i].valid() && futures[i].get() == i;
    }
    CHECK(right);
  }

  void testThePoolStops() {
    arm("the pool stops with sleeping workers", milliseconds(10000));
    {
      auto pool = std::make_unique<Pool>(2, "stop-sleeping");
      pool->Schedule([] { return 1; }).get();
      std::this_thread::sleep_for(milliseconds(50));
      const Clock::time_point start = Clock::now();
      pool.reset();
      CHECK(Clock::now() - start < milliseconds(1000));
    }
    arm("the pool stops with polling workers", milliseconds(10000));
    {
      auto pool = std::make_unique<Pool>(2, "stop-polling");
      pool->Schedule([] { return 1; }).get();
      const Clock::time_point start = Clock::now();
      pool.reset();
      CHECK(Clock::now() - start < milliseconds(1000));
    }
    arm("a pool with four sleeping workers stops", milliseconds(10000));
    {
      auto pool = std::make_unique<Pool>(4, "stop-four");
      std::this_thread::sleep_for(milliseconds(50));
      pool.reset();
    }
  }
}

int main() {
  std::thread(watchdog).detach();
  testTasksRun();
  testIdleWorkersSleep();
  testATaskWakesSleepingWorkers();
  testNoTaskIsLeftAtTheWindowsEdge();
  testThePoolStops();
  g_deadline = 0;

  if (g_failures != 0) {
    std::printf("FAIL remix workers: %d of %d checks\n", g_failures, g_checks);
    return 1;
  }
  std::printf("PASS remix workers: %d checks\n", g_checks);
  return 0;
}
'''

# The runtime's own flags for d3d9 and util (compile_commands.json of its Release build): C++17, warnings at level 2
# as errors, NOMINMAX and the constexpr mutex switch.
POOL_SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W2 /WX /utf-8 -DNOMINMAX -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR /I src/util pool.cpp /Fepool.exe /Fopool.obj
if ($LASTEXITCODE) { exit 100 }
& ./pool.exe
exit $LASTEXITCODE
'''

IDLE_SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_worker_idle.cpp /Feidle.exe /Foidle.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./idle.exe
exit $LASTEXITCODE
'''


def run_script(script: str, root: Path) -> subprocess.CompletedProcess:
    path = root / 'run.ps1'
    path.write_text(script, encoding='utf-8')
    return subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(path),
                           '-Repo', str(REPO), '-Scratch', str(root)],
                          capture_output=True, text=True, timeout=600)


def run_pool_harness(headers: dict) -> subprocess.CompletedProcess:
    scratch = REPO / 'out' / 'tmp'
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='remix-workers-', dir=scratch) as directory:
        root = Path(directory)
        for name, text in headers.items():
            file = root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text, encoding='utf-8', newline='\n')
        (root / 'pool.cpp').write_text(HARNESS, encoding='utf-8', newline='\n')
        return run_script(POOL_SCRIPT, root)


class RemixWorkersTests(unittest.TestCase):
    @unittest.skipUnless(HAVE_MSVC, 'MSVC x64 Build Tools unavailable')
    def test_the_helpers_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='worker-idle-', dir=scratch) as directory:
            root = Path(directory)
            for path in (IDLE, IDLE_TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(patches.postimage(patch, path), encoding='utf-8')
            result = run_script(IDLE_SCRIPT, root)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS worker idle: \d+ checks')

    @unittest.skipUnless(HAVE_MSVC, 'MSVC x64 Build Tools unavailable')
    def test_the_real_pool_sleeps_when_idle_and_wakes_for_a_task(self):
        found = runtime_clone()
        if found is None:
            self.skipTest('no local clone of the runtime fork with base.json\'s commit (NL_RUNTIME_CLONE)')
        headers = patched_headers(*found, upto=NUMBER)
        pool = headers[POOL]
        self.assertIn('#include "util_worker_idle.h"', pool)
        # In the whole header: Schedule wakes a sleeper after the push and the task count's increment, the destructor
        # after the stop flag and before the joins.
        schedule = pool.split('    Future<R> Schedule(F&& f) {', 1)[1].split('\n    }\n', 1)[0]
        self.assertLess(schedule.index('m_workerTasks[thread]->push(std::move(taskId));'), schedule.index('++m_numTasks;'))
        self.assertLess(schedule.index('++m_numTasks;'), schedule.index('m_idleSleep.wake(!WorkStealing);'))
        stop = pool.split('    ~WorkerThreadPool() {', 1)[1].split('\n    }\n', 1)[0]
        self.assertLess(stop.index('m_stopWork = true;'), stop.index('m_idleSleep.stop();'))
        self.assertLess(stop.index('m_idleSleep.stop();'), stop.index('worker.join();'))
        result = run_pool_harness(headers)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r'PASS remix workers: \d+ checks')
        self.assertRegex(result.stdout, r'idle workers: \d+\.\d ms of CPU in 500 ms')

    @unittest.skipUnless(HAVE_MSVC, 'MSVC x64 Build Tools unavailable')
    def test_without_0105_idle_workers_poll(self):
        # The same harness against the pool before the patch: only the idle check fails, the workers taking most of a
        # core each while nothing is scheduled.
        found = runtime_clone()
        if found is None:
            self.skipTest('no local clone of the runtime fork with base.json\'s commit (NL_RUNTIME_CLONE)')
        headers = patched_headers(*found, upto=NUMBER - 1)
        self.assertNotIn('util_worker_idle.h', headers[POOL])
        result = run_pool_harness(headers)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(re.findall(r'^FAIL line \d+: (.+)$', result.stdout, re.M), ['used < 50.0'])
        used = float(re.search(r'idle workers: (\d+\.\d) ms of CPU in 500 ms', result.stdout).group(1))
        self.assertGreater(used, 100.0)

    def test_the_helper_is_self_contained_and_waits_without_losing_a_wake_up(self):
        helper = patches.postimage(patch_text(), IDLE)
        # The gate compiles it with the standard library only.
        self.assertEqual(re.findall(r'#include <([^>]+)>', helper), ['atomic', 'chrono', 'cstdint', 'mutex'])
        self.assertNotIn('#include "', helper)
        self.assertIn('inline constexpr std::chrono::microseconds kWorkerSpinWindow { 1000 };', helper)
        # A sleeper counts itself under the lock before it tests for work; the count starts at zero.
        sleep = helper.split('void sleep(const Ready& ready) {', 1)[1].split('\n    }', 1)[0]
        self.assertEqual([line.strip() for line in sleep.strip().split('\n')],
                         ['std::unique_lock<Mutex> lock(m_mutex);', 'm_sleepers.fetch_add(1);',
                          'm_condition.wait(lock, ready);', 'm_sleepers.fetch_sub(1);'])
        self.assertIn('std::atomic<uint32_t> m_sleepers { 0 };', helper)
        # wake reads the count with no lock and notifies under the lock; stop always notifies every sleeper.
        wake = helper.split('void wake(bool all) {', 1)[1].split('\n    }\n', 1)[0]
        self.assertLess(wake.index('if (m_sleepers.load() == 0) {'), wake.index('std::lock_guard<Mutex> lock(m_mutex);'))
        self.assertLess(wake.index('std::lock_guard<Mutex> lock(m_mutex);'), wake.index('m_condition.notify_one();'))
        self.assertIn('m_condition.notify_all();', wake)
        stop = helper.split('void stop() {', 1)[1].split('\n    }', 1)[0]
        self.assertEqual([line.strip() for line in stop.strip().split('\n')],
                         ['std::lock_guard<Mutex> lock(m_mutex);', 'm_condition.notify_all();'])

    def test_the_pool_wakes_after_counting_and_sleeps_on_its_count(self):
        patch = patch_text()
        block = patches.file_block(patch, POOL)
        added = patches.added_lines(patch, POOL)
        self.assertIn('#include "util_worker_idle.h"', added)
        self.assertIn('using IdleSleep = std::conditional_t<LowLatency, WorkerSleep<dxvk::mutex, dxvk::condition_variable>, Nop>;',
                      added)
        self.assertIn('IdleSleep m_idleSleep;', added)
        # Schedule: the wake right after the task count's increment (a context line of its hunk; the push before it is
        # checked in the whole header by the test with the fork's clone).
        self.assertIn('\n' + ' ' * 9 + '++m_numTasks;\n+\n+' + ' ' * 8 + '// NV-DXVK start: a sleeping low-latency worker '
                      'wakes, only once the task is queued and counted (GMod)\n+' + ' ' * 8 + 'if constexpr (LowLatency) {\n+'
                      + ' ' * 10 + 'm_idleSleep.wake(!WorkStealing);\n', block)
        # processWork: a task or a stolen one restarts the window; the worker yields within it, then sleeps on the
        # pool's own count and stop flag (the high-latency mode's predicate).
        self.assertEqual(added.count('spin.worked();'), 2)
        self.assertIn('\n+' + ' ' * 10 + '} else if (spin.keepPolling()) {\n+' + ' ' * 12 + '// If nothing to steal, yield '
                      'this thread\n ' + ' ' * 12 + 'std::this_thread::yield();\n+' + ' ' * 10 + '} else {\n+' + ' ' * 12
                      + 'm_idleSleep.sleep([this] {\n+' + ' ' * 14 + 'return m_numTasks > 0 || m_stopWork.load();\n', block)
        # The destructor wakes the sleepers after the high-latency mode's notify and before the joins.
        self.assertIn('\n ' + ' ' * 8 + 'm_condOnAdd.notify_all();\n ' + ' ' * 6 + '}\n+' + ' ' * 6 + '// NV-DXVK start: '
                      'sleeping low-latency workers wake and see the stop (GMod)\n+' + ' ' * 6 + 'if constexpr (LowLatency) {\n+'
                      + ' ' * 8 + 'm_idleSleep.stop();\n', block)

    def test_the_high_latency_mode_is_untouched(self):
        patch = patch_text()
        removed = patches.removed_lines(patch, POOL).split('\n')
        self.assertEqual([line.strip() for line in removed if line.strip()],
                         ['if (executeTask(workerId))', 'bool workStolen = false;', '// If nothing to steal, yield this thread',
                          'if (!workStolen && LowLatency) {'])
        added = patches.added_lines(patch, POOL)
        for name in ('m_condOnAdd', 'm_taskMutex', 'TaskMutex', 'OnAddCondition'):
            self.assertNotIn(name, added)
        # Every addition to the pool is a low-latency step or the shared declarations it needs.
        self.assertEqual(added.count('if constexpr (LowLatency) {'), 3)

    def test_the_patch_lists_its_files_and_the_fork_touchpoint(self):
        patch = patch_text()
        self.assertEqual(sorted(patches.file_blocks(patch)), sorted([
            'docs/fork-touchpoints.md', 'src/util/meson.build', POOL, IDLE, 'tests/rtx/unit/meson.build', IDLE_TEST]))
        self.assertIn("'util_worker_idle.h',", patches.added_lines(patch, 'src/util/meson.build'))
        self.assertIn("executable('test_worker_idle', files('test_worker_idle.cpp'),",
                      patches.added_lines(patch, 'tests/rtx/unit/meson.build'))
        self.assertIn('## Workstream - idle geometry workers sleep (GMod native loader runtime patch 0105',
                      patches.added_lines(patch, 'docs/fork-touchpoints.md'))
        # The fork's rule: no AI co-author trailer in a runtime commit.
        self.assertNotIn('Co-Authored-By', patch.split('\n---\n', 1)[0])


if __name__ == '__main__':
    unittest.main()
