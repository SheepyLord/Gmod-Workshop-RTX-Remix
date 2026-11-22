// The run check (ADR 0254): engine-like call lists (each call's object in the arena, its element right after it) run
// through Run::step as CallQueued's loop would, with what the field's crashes found written over them during the run:
// elements put back, changed calls skipped, a call never run twice, links that leave the arena ended, calls appended
// during the run followed, nothing changed when nothing was written over; and the rewritten dispatch itself, executed
// as machine code: the engine's loop with it runs the list through step and the original bytes come back.
#include "nl_test.h"
#include "guard.h"
#include "run_check.h"

#include <windows.h>

#include <cstdlib>
#include <cstring>
#include <new>
#include <thread>
#include <vector>

namespace qc = nl::engine_guard::queue_check;
namespace rc = nl::engine_guard::run_check;

namespace {
std::uintptr_t address(const void* pointer) { return reinterpret_cast<std::uintptr_t>(pointer); }

struct Fn;
using Action = void (*)(Fn* self);
std::vector<int> g_order;  // the ids of the calls run, in order

// A queued call laid out as the engine's: IRefCounted's two, a virtual destructor, operator() in slot 3; 32 bytes,
// like the material system's CMemberFunctor0.
struct Fn {
  virtual int AddRef() { return 1; }
  virtual int Release() { return 1; }
  virtual ~Fn() = default;
  virtual void operator()() {
    g_order.push_back(id);
    if (action) action(this);
  }
  Action action = nullptr;
  int id = 0;
  std::uintptr_t tail = 0x7a11;  // the call's last bytes, just before its element
  Fn(int i, Action a) : action(a), id(i) {}
};
static_assert(sizeof(Fn) == 32, "the engine's smallest functor");

// A queued context's call list as GMod lays it out: {head, tail, next free byte}, then the arena, where the engine
// puts each call's object and then its element {next, object}.
struct EngineList {
  std::vector<std::uintptr_t> words;
  qc::List list;
  std::vector<std::uintptr_t> elements;
  explicit EngineList(std::size_t bytes = 4096) : words(3 + bytes / 8) {
    list.header = words.data();
    list.arena_begin = address(words.data() + 3);
    list.arena_end = list.arena_begin + bytes;
    words[2] = list.arena_begin;
  }
  std::uintptr_t bump(std::size_t size) {
    const std::uintptr_t at = words[2];
    words[2] += size;
    REQUIRE(words[2] <= list.arena_end);
    return at;
  }
  std::uintptr_t link(std::uintptr_t object) {
    const std::uintptr_t e = bump(qc::kElement);
    auto* element = reinterpret_cast<std::uintptr_t*>(e);
    element[0] = 0;
    element[1] = object;
    if (words[1])
      reinterpret_cast<std::uintptr_t*>(words[1])[0] = e;
    else
      words[0] = e;
    words[1] = e;
    elements.push_back(e);
    return e;
  }
  // Appends a call as the engine does: its object in the arena, its element after it. Returns the element.
  std::uintptr_t push(int id, Action action = nullptr) {
    Fn* fn = new (reinterpret_cast<void*>(bump(sizeof(Fn)))) Fn(id, action);
    return link(address(fn));
  }
  std::uintptr_t* element(std::size_t index) { return reinterpret_cast<std::uintptr_t*>(elements.at(index)); }
  Fn* call(std::size_t index) { return reinterpret_cast<Fn*>(element(index)[1]); }
};

// The engine's CallQueued loop: the head, then each element's next after its call.
void engine_run(rc::Run& run, const qc::List& list) {
  for (auto* e = reinterpret_cast<std::uintptr_t*>(list.header[0]); e; e = reinterpret_cast<std::uintptr_t*>(e[0]))
    run.step(e);
}

qc::Why judge(void*, std::uintptr_t object) { return qc::judge_memory(object); }

// What the field's crashes found in the element: a heap block whose first word is another heap block.
struct Junk {
  std::uintptr_t* block = nullptr;
  Junk() {
    block = static_cast<std::uintptr_t*>(std::calloc(8, sizeof(std::uintptr_t)));
    block[0] = address(std::calloc(8, sizeof(std::uintptr_t)));
  }
  ~Junk() {
    std::free(reinterpret_cast<void*>(block[0]));
    std::free(block);
  }
};

// The state the calls' actions reach.
EngineList* g_list = nullptr;
rc::Run* g_run = nullptr;
Junk* g_junk = nullptr;

rc::Run& watched(rc::Run& run, EngineList& list) {
  run.begin(&list.list, 1, &judge, nullptr, GetCurrentThreadId());
  REQUIRE(run.see());
  REQUIRE(run.watching());
  g_list = &list;
  g_run = &run;
  g_order.clear();
  return run;
}

std::vector<int> ids(std::initializer_list<int> list) { return std::vector<int>(list); }
}  // namespace

TEST_CASE("run check: a list nobody writes over runs as the engine runs it") {
  EngineList list;
  for (int i = 1; i <= 5; ++i) list.push(i);
  const auto before = list.words;
  rc::Run run;
  engine_run(watched(run, list), list.list);
  CHECK(g_order == ids({1, 2, 3, 4, 5}));
  CHECK(run.totals().run == 5);
  CHECK(run.totals().put_back == 0);
  CHECK(run.totals().skipped == 0);
  CHECK(run.totals().ended == 0);
  CHECK(run.recorded() == 0);
  CHECK(run.length(0) == 5);
  CHECK(list.words == before);  // nothing in the arena changed
  run.end();
}

TEST_CASE("run check: an element written over during the run is put back and its call runs") {
  Junk junk;
  g_junk = &junk;
  EngineList list;
  list.push(1);
  // The second call writes over the fourth's element with what the field's crash of 2026-11-22 found there.
  list.push(2, [](Fn*) {
    auto* victim = g_list->element(3);
    victim[0] = address(g_junk->block);
    victim[1] = address(g_junk->block);
  });
  list.push(3);
  const std::uintptr_t victim = list.push(4);
  list.push(5);
  const std::uintptr_t victim_object = list.element(3)[1];
  rc::Run run;
  engine_run(watched(run, list), list.list);
  CHECK(g_order == ids({1, 2, 3, 4, 5}));
  CHECK(run.totals().put_back == 1);
  CHECK(run.totals().skipped == 0);
  REQUIRE(run.recorded() == 1);
  const rc::Record& r = run.records()[0];
  CHECK(r.event == rc::Event::put_back);
  CHECK(r.list == 0);
  CHECK(r.position == 3);
  CHECK(r.length == 5);
  CHECK(r.element == victim);
  CHECK(r.offset == victim - list.list.arena_begin);
  CHECK(r.was[1] == victim_object);
  CHECK(r.now[0] == address(junk.block));
  CHECK(r.now[1] == address(junk.block));
  // The calls that ran just before it, newest first: the third, then the second that wrote over it.
  REQUIRE(r.recent_count == 3);
  CHECK(r.recent[0].position == 2);
  CHECK(r.recent[1].position == 1);
  CHECK(r.recent[0].table == *reinterpret_cast<const std::uintptr_t*>(list.call(0)));
  // The element holds the check's words again.
  CHECK(list.element(3)[1] == victim_object);
  CHECK(list.element(3)[0] == list.elements[4]);
  run.end();
  g_junk = nullptr;
}

TEST_CASE("run check: a call whose object changed during the run is skipped, the rest runs") {
  Junk junk;
  g_junk = &junk;
  {  // its vtable written over
    EngineList list;
    list.push(1, [](Fn*) { *reinterpret_cast<std::uintptr_t*>(g_list->call(2)) = address(g_junk->block); });
    list.push(2);
    list.push(3);
    list.push(4);
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1, 2, 4}));
    CHECK(run.totals().skipped == 1);
    REQUIRE(run.recorded() == 1);
    CHECK(run.records()[0].event == rc::Event::object_changed);
    CHECK(run.records()[0].position == 2);
    CHECK(run.records()[0].words == 4);
    CHECK(run.records()[0].words_now[0] == address(junk.block));
    run.end();
  }
  {  // the 16 bytes before its element (the end of its object, as the engine lays it out) written over
    EngineList list;
    list.push(1, [](Fn*) { g_list->call(2)->tail = 0xdead; });
    list.push(2);
    list.push(3);
    list.push(4);
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1, 2, 4}));
    CHECK(run.totals().skipped == 1);
    REQUIRE(run.recorded() == 1);
    CHECK(run.records()[0].before_read);
    CHECK(run.records()[0].before_now[1] == 0xdead);
    run.end();
  }
  g_junk = nullptr;
}

TEST_CASE("run check: a call that changes its own link is put back, a call is never run twice") {
  {  // the link out of the arena
    EngineList list;
    list.push(1);
    list.push(2, [](Fn*) { g_list->element(1)[0] = address(&g_order); });
    list.push(3);
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1, 2, 3}));
    CHECK(run.totals().put_back == 1);
    REQUIRE(run.recorded() == 1);
    CHECK(run.records()[0].event == rc::Event::next_put_back);
    run.end();
  }
  {  // a nested run of the same list from its head: no call runs twice and the outer run goes on
    EngineList list;
    list.push(1);
    list.push(2);
    list.push(3, [](Fn*) { engine_run(*g_run, g_list->list); });
    list.push(4);
    list.push(5);
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1, 2, 3, 4, 5}));
    CHECK(run.totals().run == 5);
    CHECK(run.totals().skipped == 1);
    CHECK(run.totals().ended == 1);
    REQUIRE(run.recorded() >= 1);
    CHECK(run.records()[0].event == rc::Event::ran_twice);
    CHECK(run.records()[0].position == 0);
    run.end();
  }
  {  // a link leading back to a call already run: it ends there instead of running anything twice
    EngineList list;
    list.push(1);
    list.push(2);
    list.push(3, [](Fn*) { g_list->element(4)[0] = g_list->elements[1]; });
    list.push(4);
    list.push(5);
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1, 2, 3, 4, 5}));
    CHECK(run.totals().put_back == 1);  // the fifth element's link, put back before the engine followed it
    run.end();
  }
}

TEST_CASE("run check: calls appended during the run are followed, strangers judged, stray links ended") {
  {  // the last call appends one: it runs
    EngineList list;
    list.push(1);
    list.push(2, [](Fn*) { g_list->push(9); });
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1, 2, 9}));
    CHECK(run.totals().strangers == 1);
    CHECK(run.totals().run == 3);
    CHECK(run.totals().put_back == 0);
    run.end();
  }
  {  // an appended element whose object is not live, with a link out of the arena: skipped, the list ends there
    Junk junk;
    g_junk = &junk;
    EngineList list;
    list.push(1, [](Fn*) {
      const std::uintptr_t e = g_list->link(address(g_junk->block));
      reinterpret_cast<std::uintptr_t*>(e)[0] = address(g_junk->block);
    });
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1}));
    CHECK(run.totals().strangers == 1);
    CHECK(run.totals().skipped == 1);
    CHECK(run.totals().ended == 1);
    REQUIRE(run.recorded() == 2);
    CHECK(run.records()[0].event == rc::Event::stranger);
    CHECK(run.records()[0].position == UINT32_MAX);
    CHECK(run.records()[1].event == rc::Event::ended);
    run.end();
    g_junk = nullptr;
  }
  {  // a list the check could not keep (its tail is not its last call): every call is a stranger, live ones run
    EngineList list;
    list.push(1);
    list.push(2);
    list.push(3);
    list.words[1] = list.elements[0];
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order == ids({1, 2, 3}));
    CHECK(run.length(0) == 0);
    CHECK(run.totals().strangers == 3);
    run.end();
  }
}

TEST_CASE("run check: events past the record limit are counted, other threads and idle runs only call") {
  Junk junk;
  g_junk = &junk;
  {
    EngineList list(8192);
    const Action every_other = [](Fn*) {
      for (std::size_t k = 1; k < g_list->elements.size(); k += 2) g_list->element(k)[1] = address(g_junk->block);
    };
    for (int i = 0; i < 40; ++i) list.push(i, i == 0 ? every_other : nullptr);
    rc::Run run;
    engine_run(watched(run, list), list.list);
    CHECK(g_order.size() == 40);
    CHECK(run.totals().put_back == 20);
    CHECK(run.recorded() == rc::kMaxRecords);
    run.end();
  }
  {  // not watching: step is the engine's dispatch
    EngineList list;
    list.push(1);
    list.push(2);
    rc::Run run;
    g_order.clear();
    engine_run(run, list.list);
    CHECK(g_order == ids({1, 2}));
    CHECK(run.totals().run == 0);
  }
  {  // another thread's step only calls
    EngineList list;
    list.push(1);
    list.push(2);
    rc::Run run;
    watched(run, list);
    std::thread other([&] { run.step(list.element(0)); });
    other.join();
    CHECK(g_order == ids({1}));
    CHECK(run.totals().run == 0);
    engine_run(run, list.list);  // this thread's run still runs each call once
    CHECK(g_order == ids({1, 1, 2}));
    CHECK(run.totals().run == 2);
    run.end();
  }
  g_junk = nullptr;
}

namespace {
// The engine's CallQueued loop in machine code, its dispatch at kRunnerDispatch as in materialsystem.dll:
// push rbx; sub rsp,20h; mov rbx,rcx; test rbx,rbx; je done;
// loop: mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h]; mov rbx,[rbx]; test rbx,rbx; jne loop;
// done: add rsp,20h; pop rbx; ret
const std::uint8_t kRunner[] = {0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x85, 0xDB, 0x74, 0x12,
                                0x48, 0x8B, 0x4B, 0x08, 0x48, 0x8B, 0x01, 0xFF, 0x50, 0x18, 0x48, 0x8B, 0x1B,
                                0x48, 0x85, 0xDB, 0x75, 0xEE, 0x48, 0x83, 0xC4, 0x20, 0x5B, 0xC3};
constexpr std::size_t kRunnerDispatch = 13;

rc::Run* g_slot_run = nullptr;
void slot_step(std::uintptr_t* element) noexcept { g_slot_run->step(element); }
}  // namespace

TEST_CASE("run check: the rewritten dispatch, executed, runs the engine's loop through step and comes back") {
  CHECK(std::memcmp(kRunner + kRunnerDispatch, rc::kDispatch.data(), rc::kDispatchSize) == 0);
  // The patch's bytes: mov rcx,rbx; call [rip+disp32]; nop, the displacement from the end of the call.
  const auto bytes = rc::dispatch_patch(0x10000, 0x10000 + 9 + 0x1234);
  REQUIRE(bytes.size() == rc::kDispatchSize);
  const std::uint8_t expected[] = {0x48, 0x8B, 0xCB, 0xFF, 0x15, 0x34, 0x12, 0x00, 0x00, 0x90};
  CHECK(std::memcmp(bytes.data(), expected, sizeof(expected)) == 0);
  CHECK(rc::dispatch_patch(0x10000, 0x10000 + 9 - 0x40).size() == rc::kDispatchSize);  // a slot below
  CHECK(rc::dispatch_patch(0x10000, 0x10000 + 0x100000000ull).empty());              // out of reach

  auto* code = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
  REQUIRE(code != nullptr);
  std::memcpy(code, kRunner, sizeof(kRunner));
  FlushInstructionCache(GetCurrentProcess(), code, sizeof(kRunner));
  using Runner = void (*)(std::uintptr_t head);
  const auto runner = reinterpret_cast<Runner>(code);
  std::uint8_t* const site = code + kRunnerDispatch;

  {  // as the engine's: every call once
    EngineList list;
    for (int i = 1; i <= 3; ++i) list.push(i);
    g_order.clear();
    runner(list.words[0]);
    CHECK(g_order == ids({1, 2, 3}));
  }
  void* const slot = nl::engine_guard::allocate_near(address(site));
  REQUIRE(slot != nullptr);
  void (*const entry)(std::uintptr_t*) noexcept = &slot_step;
  std::memcpy(slot, &entry, sizeof(entry));
  const auto patch = rc::dispatch_patch(address(site), address(slot));
  REQUIRE(patch.size() == rc::kDispatchSize);
  std::memcpy(site, patch.data(), patch.size());
  FlushInstructionCache(GetCurrentProcess(), site, patch.size());
  {  // rewritten, with the field's case: the run goes through step, which puts the element back
    Junk junk;
    g_junk = &junk;
    EngineList list;
    list.push(1, [](Fn*) {
      auto* victim = g_list->element(2);
      victim[0] = address(g_junk->block);
      victim[1] = address(g_junk->block);
    });
    list.push(2);
    list.push(3);
    list.push(4);
    rc::Run run;
    watched(run, list);
    g_slot_run = &run;
    runner(list.words[0]);
    CHECK(g_order == ids({1, 2, 3, 4}));
    CHECK(run.totals().run == 4);
    CHECK(run.totals().put_back == 1);
    run.end();
    // Idle (no run watched), the rewritten loop still runs each call as the engine's would.
    g_order.clear();
    EngineList again;
    again.push(7);
    again.push(8);
    runner(again.words[0]);
    CHECK(g_order == ids({7, 8}));
    g_slot_run = nullptr;
    g_junk = nullptr;
  }
  std::memcpy(site, rc::kDispatch.data(), rc::kDispatchSize);  // put back
  CHECK(std::memcmp(code, kRunner, sizeof(kRunner)) == 0);
  VirtualFree(slot, 0, MEM_RELEASE);
  VirtualFree(code, 0, MEM_RELEASE);
}
