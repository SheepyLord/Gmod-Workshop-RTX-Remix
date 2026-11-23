// The run check (ADR 0254): engine-like call lists (each call's object in the arena, its element right after it) run
// through Run::step as CallQueued's loop would, with what the field's crashes found written over them during the run:
// elements put back, changed calls skipped, a call never run twice, links that leave the arena ended, calls appended
// during the run followed, nothing changed when nothing was written over; and the rewritten dispatch itself, executed
// as machine code: the engine's loop with it runs the list through step and the original bytes come back. ADR 0261:
// the target judge asked right before each call (seen elements and strangers), a gone target skipped, counted and
// recorded, the notify told at the event (before later calls run), a variable an earlier call of the same run
// destroyed caught at its own call (with a fake judge and with the real one on fake memory), and the queued context's
// flush executed as machine code (Lock, CallQueued, Unlock through stand-ins), its run going through step.
#include "nl_test.h"
#include "guard.h"
#include "run_check.h"
#include "target_check.h"
#include "queue_check.h"

#include <windows.h>

#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <cstring>
#include <new>
#include <thread>
#include <vector>

namespace qc = nl::engine_guard::queue_check;
namespace rc = nl::engine_guard::run_check;
namespace tc = nl::engine_guard::target_check;

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

namespace {
// ADR 0261: the target judge as a fake. Calls whose object is in g_gone_objects are on a material variable that is
// gone; every other call is not judged.
std::vector<std::uintptr_t> g_gone_objects;
int g_judged = 0;
tc::Verdict fake_target(void*, std::uintptr_t object, tc::Finding& finding) {
  ++g_judged;
  finding.functor_table = *reinterpret_cast<const std::uintptr_t*>(object);
  for (const std::uintptr_t gone : g_gone_objects)
    if (gone == object) {
      finding.variable = 0x5eed;
      return tc::Verdict::not_in_parameters;
    }
  return tc::Verdict::not_judged;
}

// What the notify saw, and when: the calls run by then.
struct Told {
  rc::Event event;
  std::size_t ran_by_then;
  std::uintptr_t element;
  tc::Verdict verdict;
};
std::vector<Told> g_told;
void notify(void*, const rc::Record& record) {
  g_told.push_back({record.event, g_order.size(), record.element, record.target.verdict});
}

rc::Hooks fake_hooks() {
  rc::Hooks hooks;
  hooks.target = &fake_target;
  hooks.notify = &notify;
  return hooks;
}

rc::Run& watched_with(rc::Run& run, EngineList& list, const rc::Hooks& hooks) {
  run.begin(&list.list, 1, &judge, nullptr, GetCurrentThreadId(), &rc::call_object, hooks);
  REQUIRE(run.see());
  g_list = &list;
  g_run = &run;
  g_order.clear();
  g_told.clear();
  g_judged = 0;
  return run;
}
}  // namespace

TEST_CASE("run check: a call whose material variable is gone is skipped and told when it happens (ADR 0261)") {
  {  // seen elements: the third call's target is gone
    EngineList list;
    for (int i = 1; i <= 4; ++i) list.push(i);
    g_gone_objects = {list.element(2)[1]};
    rc::Run run;
    engine_run(watched_with(run, list, fake_hooks()), list.list);
    CHECK(g_order == ids({1, 2, 4}));
    CHECK(g_judged == 4);  // every call judged right before it would run
    CHECK(run.totals().run == 3);
    CHECK(run.totals().skipped == 1);
    CHECK(run.totals().gone == 1);
    CHECK(run.totals().put_back == 0);
    REQUIRE(run.recorded() == 1);
    const rc::Record& r = run.records()[0];
    CHECK(r.event == rc::Event::target_gone);
    CHECK(r.position == 2);
    CHECK(r.element == list.elements[2]);
    CHECK(r.target.verdict == tc::Verdict::not_in_parameters);
    CHECK(r.target.variable == 0x5eed);
    CHECK(r.target.functor_table == *reinterpret_cast<const std::uintptr_t*>(list.call(2)));
    REQUIRE(r.recent_count == 2);
    CHECK(r.recent[0].position == 1);
    // Told at the event, before the fourth call ran: a run that crashed after it would still have said it.
    REQUIRE(g_told.size() == 1);
    CHECK(g_told[0].event == rc::Event::target_gone);
    CHECK(g_told[0].ran_by_then == 2);
    CHECK(g_told[0].verdict == tc::Verdict::not_in_parameters);
    CHECK(std::strlen(rc::describe(rc::Event::target_gone)) > 10);
    run.end();
  }
  {  // a stranger (appended by the last call during the run) whose target is gone: skipped as well
    EngineList list;
    list.push(1);
    list.push(2, [](Fn*) {
      const std::uintptr_t e = g_list->push(9);
      g_gone_objects = {reinterpret_cast<std::uintptr_t*>(e)[1]};
    });
    rc::Run run;
    g_gone_objects.clear();
    engine_run(watched_with(run, list, fake_hooks()), list.list);
    CHECK(g_order == ids({1, 2}));
    CHECK(run.totals().strangers == 1);
    CHECK(run.totals().gone == 1);
    REQUIRE(run.recorded() == 1);
    CHECK(run.records()[0].event == rc::Event::target_gone);
    CHECK(run.records()[0].position == UINT32_MAX);
    run.end();
  }
  {  // a variable an earlier call of the same run destroyed: caught at its own call
    EngineList list;
    list.push(1);
    list.push(2, [](Fn*) { g_gone_objects = {g_list->element(3)[1]}; });  // the cleanup, as a queued call
    list.push(3);
    list.push(4);
    list.push(5);
    rc::Run run;
    g_gone_objects.clear();
    engine_run(watched_with(run, list, fake_hooks()), list.list);
    CHECK(g_order == ids({1, 2, 3, 5}));
    CHECK(run.totals().gone == 1);
    REQUIRE(g_told.size() == 1);
    CHECK(g_told[0].ran_by_then == 3);
    run.end();
  }
  {  // no target judge: every call runs as before; events past the record limit are still told, up to theirs
    EngineList list(8192);
    for (int i = 0; i < 40; ++i) list.push(i);
    g_gone_objects.clear();
    for (std::size_t k = 0; k < 40; ++k) g_gone_objects.push_back(list.element(k)[1]);
    rc::Hooks hooks = fake_hooks();
    hooks.target = nullptr;
    rc::Run plain;
    engine_run(watched_with(plain, list, hooks), list.list);
    CHECK(g_order.size() == 40);
    CHECK(plain.totals().gone == 0);
    plain.end();
    EngineList again(8192);
    for (int i = 0; i < 40; ++i) again.push(i);
    g_gone_objects.clear();
    for (std::size_t k = 0; k < 40; ++k) g_gone_objects.push_back(again.element(k)[1]);
    rc::Run all;
    engine_run(watched_with(all, again, fake_hooks()), again.list);
    CHECK(g_order.empty());
    CHECK(all.totals().gone == 40);
    CHECK(all.recorded() == rc::kMaxRecords);
    CHECK(g_told.size() == 40);  // every event told, beyond the records kept
    all.end();
  }
  g_gone_objects.clear();
}

namespace {
// The real target judge on fake memory: the designated calls keep a material variable at +24 (Fn::tail); the second
// call's action uncaches the material as CMaterial::CleanUpShaderParams does (array and count 0).
struct Material {
  alignas(8) std::uint8_t variable[0x48] = {};
  alignas(8) std::uint8_t material[0x48] = {};
  std::uintptr_t params[1] = {};
};
const std::uintptr_t kVarTable[1] = {};
const std::uintptr_t kMatTable[1] = {};
Material* g_material = nullptr;
tc::Judge* g_real = nullptr;
std::vector<std::uintptr_t> g_designated;
tc::Verdict real_target(void*, std::uintptr_t object, tc::Finding& finding) {
  for (const std::uintptr_t d : g_designated)
    if (d == object) return tc::judge(*g_real, object, finding);
  return tc::Verdict::not_judged;
}
void put_word(std::uint8_t* at, std::uintptr_t value) { std::memcpy(at, &value, sizeof(value)); }
}  // namespace

TEST_CASE("run check: the real target judge skips a setter whose material an earlier call uncached") {
  Material m;
  put_word(m.variable, address(kVarTable));
  put_word(m.variable + 0x31, address(m.material));
  put_word(m.material, address(kMatTable));
  m.material[0x32] = 1;
  m.params[0] = address(m.variable);
  put_word(m.material + 0x38, address(m.params));
  g_material = &m;
  tc::Judge judge_real;
  judge_real.variable_table = address(kVarTable);
  judge_real.material_table = address(kMatTable);
  judge_real.owner = 0x31;
  judge_real.count = 0x32;
  judge_real.params = 0x38;
  judge_real.resolver = nullptr;
  g_real = &judge_real;
  EngineList list;
  list.push(1);
  list.push(2, [](Fn*) {  // UncacheAllMaterials: the material lists no variable any more
    put_word(g_material->material + 0x38, 0);
    g_material->material[0x32] = 0;
  });
  list.push(3);
  // The first and the third call are setters on the variable (their class keeps it at +24).
  list.call(0)->tail = address(m.variable);
  list.call(2)->tail = address(m.variable);
  judge_real.classes.add(*reinterpret_cast<const std::uintptr_t*>(list.call(0)), 24);
  g_designated = {list.element(0)[1], list.element(2)[1]};
  rc::Hooks hooks;
  hooks.target = &real_target;
  hooks.notify = &notify;
  rc::Run run;
  engine_run(watched_with(run, list, hooks), list.list);
  CHECK(g_order == ids({1, 2}));
  CHECK(run.totals().gone == 1);
  REQUIRE(run.recorded() == 1);
  CHECK(run.records()[0].target.verdict == tc::Verdict::no_parameters);
  CHECK(run.records()[0].target.variable == address(m.variable));
  CHECK(run.records()[0].target.owner == address(m.material));
  run.end();
  g_designated.clear();
  g_real = nullptr;
  g_material = nullptr;
}

namespace {
// The queued context's flush (ADR 0261) in machine code, in a page of its own, as materialsystem.dll has it: Lock and
// Unlock through the material system's vtable (C++ stand-ins below), CallQueued between them. The stand-in CallQueued
// runs the context's list (its head the context's first word, its tail the second) with the engine's dispatch, then
// empties it. CallQueued at 0:
//   push rbx; push rsi; sub rsp,28h; mov rsi,rcx; mov rbx,[rsi]; test rbx,rbx; je done;
//   loop: mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h]; mov rbx,[rbx]; test rbx,rbx; jne loop;
//   done: mov qword ptr [rsi],0; mov qword ptr [rsi+8],0; add rsp,28h; pop rsi; pop rbx; ret
const std::uint8_t kCallQueued[] = {0x53, 0x56, 0x48, 0x83, 0xEC, 0x28, 0x48, 0x8B, 0xF1, 0x48, 0x8B, 0x1E, 0x48,
                                    0x85, 0xDB, 0x74, 0x12, 0x48, 0x8B, 0x4B, 0x08, 0x48, 0x8B, 0x01, 0xFF, 0x50,
                                    0x18, 0x48, 0x8B, 0x1B, 0x48, 0x85, 0xDB, 0x75, 0xEE, 0x48, 0xC7, 0x06, 0x00,
                                    0x00, 0x00, 0x00, 0x48, 0xC7, 0x46, 0x08, 0x00, 0x00, 0x00, 0x00, 0x48, 0x83,
                                    0xC4, 0x28, 0x5E, 0x5B, 0xC3};
constexpr std::size_t kCallQueuedDispatch = 17;
constexpr std::size_t kFlushAt = 0x80;
constexpr std::uint32_t kSystem = 0x40;  // the context's material system pointer

// The flush at kFlushAt: mov [rsp+8],rbx; push rdi; sub rsp,20h; mov rdi,rcx; mov rcx,[rdi+40h]; mov rax,[rcx];
// call [rax+10h] (Lock); xor edx,edx; mov rcx,rdi; mov rbx,rax; call CallQueued; mov rcx,[rdi+40h]; mov rdx,rbx;
// mov r8,[rcx]; call [r8+18h] (Unlock); mov rbx,[rsp+30h]; add rsp,20h; pop rdi; ret
std::vector<std::uint8_t> flush_bytes() {
  std::vector<std::uint8_t> code = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xF9,
                                    0x48, 0x8B, 0x8F, kSystem, 0, 0, 0, 0x48, 0x8B, 0x01, 0xFF, 0x90, 0x10, 0, 0, 0,
                                    0x33, 0xD2, 0x48, 0x8B, 0xCF, 0x48, 0x8B, 0xD8, 0xE8};
  const std::int32_t relative = -static_cast<std::int32_t>(kFlushAt + code.size() + 4);
  for (int i = 0; i < 4; ++i) code.push_back(static_cast<std::uint8_t>(static_cast<std::uint32_t>(relative) >> (8 * i)));
  code.insert(code.end(), {0x48, 0x8B, 0x8F, kSystem, 0, 0, 0, 0x48, 0x8B, 0xD3, 0x4C, 0x8B, 0x01, 0x41, 0xFF, 0x90,
                           0x18, 0, 0, 0, 0x48, 0x8B, 0x5C, 0x24, 0x30, 0x48, 0x83, 0xC4, 0x20, 0x5F, 0xC3});
  return code;
}

std::vector<char> g_lock_order;
void* const kLockToken = reinterpret_cast<void*>(0x10C4);
void* fake_lock(void*) {
  g_lock_order.push_back('L');
  return kLockToken;
}
// The engine's flush inside a render block queues one call after its Unlock (the block's matching end): the
// stand-in does that when g_requeue names a list.
const qc::List* g_requeue = nullptr;
std::uintptr_t g_requeue_object = 0;
void fake_unlock(void*, void* token) {
  g_lock_order.push_back(token == kLockToken ? 'U' : '?');
  if (g_requeue) qc::append(*g_requeue, g_requeue_object);
  g_requeue = nullptr;
}
const void* const kSystemTable[4] = {nullptr, nullptr, reinterpret_cast<const void*>(&fake_lock),
                                     reinterpret_cast<const void*>(&fake_unlock)};
struct FakeSystem {
  const void* const* vtable = kSystemTable;
};
struct FakeContext {
  std::uintptr_t head = 0;
  std::uintptr_t unused[7] = {};
  FakeSystem* system = nullptr;  // at +0x40
};
static_assert(offsetof(FakeContext, system) == kSystem, "the flush reads it there");

rc::Run* g_page_run = nullptr;
void page_step(std::uintptr_t* element) noexcept { g_page_run->step(element); }
}  // namespace

TEST_CASE("run check: the queued context's flush, executed, runs the list through step between Lock and Unlock") {
  auto* code = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
  REQUIRE(code != nullptr);
  std::memset(code, 0xCC, 4096);
  std::memcpy(code, kCallQueued, sizeof(kCallQueued));
  const auto flush = flush_bytes();
  std::memcpy(code + kFlushAt, flush.data(), flush.size());
  CHECK(std::memcmp(code + kCallQueuedDispatch, rc::kDispatch.data(), rc::kDispatchSize) == 0);
  FlushInstructionCache(GetCurrentProcess(), code, 4096);
  using Flush = void (*)(void* context);
  const auto run_flush = reinterpret_cast<Flush>(code + kFlushAt);
  FakeSystem system;
  FakeContext context;
  context.system = &system;
  {  // as the engine's: every call once, between Lock and Unlock, and the list emptied
    EngineList list;
    for (int i = 1; i <= 3; ++i) list.push(i);
    context.head = list.words[0];
    g_order.clear();
    g_lock_order.clear();
    run_flush(&context);
    CHECK(g_order == ids({1, 2, 3}));
    CHECK(context.head == 0);
    CHECK(g_lock_order == std::vector<char>({'L', 'U'}));
  }
  // The dispatch rewritten as the engine guard does for a flush: the run goes through step, which asks the target
  // judge; the second call uncaches the fourth's material.
  std::uint8_t* const site = code + kCallQueuedDispatch;
  void* const slot = nl::engine_guard::allocate_near(address(site));
  REQUIRE(slot != nullptr);
  void (*const entry)(std::uintptr_t*) noexcept = &page_step;
  std::memcpy(slot, &entry, sizeof(entry));
  const auto patch = rc::dispatch_patch(address(site), address(slot));
  REQUIRE(patch.size() == rc::kDispatchSize);
  std::memcpy(site, patch.data(), patch.size());
  FlushInstructionCache(GetCurrentProcess(), site, patch.size());
  {
    EngineList list;
    list.push(1);
    list.push(2, [](Fn*) { g_gone_objects = {g_list->element(3)[1]}; });
    list.push(3);
    list.push(4);
    list.push(5);
    g_gone_objects.clear();
    rc::Run run;
    watched_with(run, list, fake_hooks());
    g_page_run = &run;
    g_lock_order.clear();
    context.head = list.words[0];
    run_flush(&context);
    CHECK(g_order == ids({1, 2, 3, 5}));
    CHECK(run.totals().run == 4);
    CHECK(run.totals().gone == 1);
    CHECK(context.head == 0);
    CHECK(g_lock_order == std::vector<char>({'L', 'U'}));
    REQUIRE(g_told.size() == 1);
    CHECK(g_told[0].ran_by_then == 3);
    run.end();
    g_page_run = nullptr;
  }
  std::memcpy(site, rc::kDispatch.data(), rc::kDispatchSize);  // put back
  CHECK(std::memcmp(code, kCallQueued, sizeof(kCallQueued)) == 0);
  g_gone_objects.clear();
  VirtualFree(slot, 0, MEM_RELEASE);
  VirtualFree(code, 0, MEM_RELEASE);
}

namespace {
// The flush's own logic (queue_check::flush, ADR 0261) on stand-ins: a material system object whose one queued context
// holds its call list at its start (as the machine-code CallQueued reads it), Lock returning that context while
// g_recording, the machine-code flush as the context's flush.
void* g_seam_context = nullptr;
bool g_recording = true;
void* seam_lock(void*) { return g_recording ? g_seam_context : reinterpret_cast<void*>(0x5eed0); }
void seam_unlock(void*, void*) {}

std::string read_text(const std::filesystem::path& path) {
  std::ifstream file(path, std::ios::binary);
  std::stringstream text;
  text << file.rdbuf();
  return text.str();
}
}  // namespace

TEST_CASE("run check: the flush's outcome on stand-ins (nothing queued, flushed, queued again, refused, test option)") {
  if (GetModuleHandleW(L"d3d9.dll")) return;  // never in this test process
  auto* code = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
  REQUIRE(code != nullptr);
  std::memset(code, 0xCC, 4096);
  std::memcpy(code, kCallQueued, sizeof(kCallQueued));
  const auto flush = flush_bytes();
  std::memcpy(code + kFlushAt, flush.data(), flush.size());
  FlushInstructionCache(GetCurrentProcess(), code, 4096);
  // The material system object: its context at +0x1000, the list's header at the context's start, the arena after it.
  const std::size_t size = 0x1000 + qc::kListHeader + 0x1000000 + 0x1000;
  auto* system = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
  REQUIRE(system != nullptr);
  auto* context = reinterpret_cast<FakeContext*>(system + 0x1000);
  FakeSystem fake_system;
  context->system = &fake_system;
  g_seam_context = context;
  qc::List list;
  list.header = reinterpret_cast<std::uintptr_t*>(context);
  list.arena_begin = address(context) + qc::kListHeader;
  list.arena_end = list.arena_begin + 0x1000000;
  list.header[2] = address(context) + 0x100;  // elements after the system pointer at +0x40
  std::vector<Fn*> calls;
  auto queue = [&](int id) {
    calls.push_back(new Fn(id, nullptr));
    REQUIRE(qc::append(list, address(calls.back())));
  };
  const auto folder = nl::test::scratch_dir("queue_flush");
  const auto log = folder / "render-queue-check.log";
  qc::StandIns stand_ins;
  stand_ins.system = system;
  stand_ins.layout.contexts = 0x1000;
  stand_ins.layout.stride = 0x2000000;
  stand_ins.layout.count = 1;
  stand_ins.layout.list = 0;
  stand_ins.lock = &seam_lock;
  stand_ins.unlock = &seam_unlock;
  stand_ins.flush = reinterpret_cast<void (*)(void*)>(code + kFlushAt);
  stand_ins.log = log.wstring();
  qc::use_for_test(stand_ins);
  {  // not recording into a queued context: nothing run, ok
    g_recording = false;
    g_lock_order.clear();
    const qc::FlushResult result = qc::flush();
    CHECK(result.ok);
    CHECK(result.calls == 0);
    CHECK(result.why.find("nothing queued") != std::string::npos);
    CHECK(g_lock_order.empty());
    g_recording = true;
  }
  {  // three calls queued: run through the context's flush, between its Lock and Unlock
    for (int i = 1; i <= 3; ++i) queue(i);
    g_order.clear();
    g_lock_order.clear();
    const qc::FlushResult result = qc::flush();
    CHECK(result.ok);
    CHECK(result.calls == 3);
    CHECK(g_order == ids({1, 2, 3}));
    CHECK(g_lock_order == std::vector<char>({'L', 'U'}));
    CHECK(result.why.find("ran 3 queued render call(s)") != std::string::npos);
    CHECK(result.why.find("queued again") == std::string::npos);
    CHECK(context->head == 0);
  }
  {  // the flush queues one call after itself (inside a render block): still ok, and said
    queue(4);
    queue(5);
    calls.push_back(new Fn(6, nullptr));
    g_requeue = &list;
    g_requeue_object = address(calls.back());
    g_order.clear();
    const qc::FlushResult result = qc::flush();
    CHECK(result.ok);
    CHECK(result.calls == 2);
    CHECK(g_order == ids({4, 5}));
    CHECK(result.why.find("; 1 call(s) queued again by the flush") != std::string::npos);
    CHECK(context->head != 0);
    g_order.clear();
    CHECK(qc::flush().ok);  // the next flush runs it
    CHECK(g_order == ids({6}));
  }
  {  // another thread is refused; nothing runs
    queue(7);
    qc::FlushResult result;
    std::thread other([&] { result = qc::flush(); });
    other.join();
    CHECK(!result.ok);
    CHECK(result.why.find("main thread") != std::string::npos);
    g_order.clear();
    CHECK(qc::flush().ok);
    CHECK(g_order == ids({7}));
  }
  // The log: the nothing-queued flush had its own number (1, no line); the real ones are 2, 3, 4 and 5.
  std::string text = read_text(log);
  CHECK(text.find(" flush 1:") == std::string::npos);
  CHECK(text.find(" flush 2: list 0 held 3 calls; not watched; ran 3 queued render call(s)") != std::string::npos);
  CHECK(text.find(" flush 3: list 0 held 2 calls") != std::string::npos);
  CHECK(text.find("1 call(s) queued again by the flush") != std::string::npos);
  // Routine lines for the first 64 flushes of a process only.
  for (int i = 0; i < 70; ++i) CHECK(qc::flush().ok);
  text = read_text(log);
  CHECK(text.find(" flush 64:") != std::string::npos);
  CHECK(text.find(" flush 65:") == std::string::npos);
  {  // the test option: ok, nothing run
    stand_ins.no_flush = true;
    qc::use_for_test(stand_ins);
    queue(8);
    g_order.clear();
    const qc::FlushResult result = qc::flush();
    CHECK(result.ok);
    CHECK(result.calls == 0);
    CHECK(result.why.find("-nl_queue_check_no_flush") != std::string::npos);
    CHECK(g_order.empty());
  }
  qc::reset_for_test();
  CHECK(!qc::flush().ok);  // not installed again
  for (Fn* fn : calls) delete fn;
  VirtualFree(system, 0, MEM_RELEASE);
  VirtualFree(code, 0, MEM_RELEASE);
  std::error_code ignored;
  std::filesystem::remove_all(folder, ignored);
}
