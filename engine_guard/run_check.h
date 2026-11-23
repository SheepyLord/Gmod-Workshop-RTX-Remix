// Queued render calls checked again while the game runs them (ADR 0254), after the queue check (ADR 0247).
//
// The queue check walks both queued contexts' call lists before IMaterialSystem::AllowThreading(false) and drops calls
// whose object is already gone. ADR 0254 read a field crash of 2026-11-22 as a second kind: that check had passed every
// call, and the 660th element of context 1 then held a pointer to freed heap memory, which looked like an element
// written over while ForceSingleThreaded ran the list. ADR 0261 found the real cause: the element was intact, its
// call's target was gone (a queued CMaterialVar setter whose variable the RTX fixes' map-exit cleanup had destroyed;
// target_check.h). The run check stays as a guard against elements written over, and now also judges each call's
// target right before it runs:
//
// - After its walk it keeps what every element looked like: its two words (the next element, the call's object), the
//   object's first words and the 16 bytes before the element (where the engine lays the call's own object).
// - While the engine runs the lists (AllowThreading(false), or the queued context's own flush that the engine guard
//   calls before the fixes' cleanup; main thread only, the render thread idle), CallQueued's per-call dispatch
//   (mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h]) is rewritten in memory to call step() with the element: an
//   element whose words changed is put back as the check saw it, a call whose object changed is skipped, an element
//   run a second time in one pass is skipped and ends its list, and every link the engine follows next leads to a real
//   element or nowhere. Right before a call runs, the target judge (ADR 0261) may skip it: a call on a material
//   variable that is no longer a variable of its material. Unchanged calls run as before. The dispatch is put back
//   when the engine's function returns.
// - Each event goes to the caller's notify as it happens (the game writes it to the queue check's log then, so a run
//   that crashes still leaves its log), with the calls that ran just before (their classes).
#pragma once

#include "queue_check.h"
#include "target_check.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace nl::engine_guard::run_check {

inline constexpr std::size_t kObjectWords = 4;  // an object's first words, kept and compared
inline constexpr std::size_t kMaxRecords = 16;  // events recorded per run (every one is counted)
inline constexpr std::size_t kRecent = 8;       // the calls run just before an event, kept with it
inline constexpr std::size_t kMaxStrangers = 4096;  // elements the check never saw, followed per run at most

// The ten bytes of CallQueued's loop that call an element's object: mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h].
inline constexpr std::size_t kDispatchSize = 10;
inline constexpr std::array<std::uint8_t, kDispatchSize> kDispatch = {0x48, 0x8B, 0x4B, 0x08, 0x48,
                                                                        0x8B, 0x01, 0xFF, 0x50, 0x18};

// What they become while a run is watched: mov rcx,rbx; call [rip+disp32] (the slot holds step's address); nop.
// Empty when the slot is out of a rel32's reach from the site.
std::vector<std::uint8_t> dispatch_patch(std::uintptr_t site, std::uintptr_t slot);

// One element as the check saw it, before the engine ran the lists.
struct Entry {
  std::uintptr_t element = 0;
  std::uintptr_t next = 0;    // the element's two words then
  std::uintptr_t object = 0;
  std::uintptr_t words[kObjectWords] = {};  // the object's first words then (words[0] its vtable)
  std::uintptr_t before[2] = {};            // the 16 bytes before the element then
  std::uint32_t position = 0;               // its place in its list, 0 first
  std::uint8_t list = 0;
  std::uint8_t words_read = 0;  // how many of words[] could be read
  bool before_read = false;     // the 16 bytes lie in the arena and were read
  bool ran = false;             // step() reached it in this run
};

enum class Event : std::uint8_t {
  put_back,        // the element's words changed after the check: put back as the check saw them
  object_changed,  // the call's object, or the bytes before its element, changed after the check: skipped
  ran_twice,       // the element was reached a second time in one run: skipped, its list ends there
  stranger,        // an element the check never saw, whose object is not live: skipped
  next_put_back,   // the call changed its own element's link: put back
  ended,           // a link led out of its list's arena: the list ends there
  target_gone,     // the call's material variable is gone (ADR 0261): skipped
};
const char* describe(Event event) noexcept;

// A call run, as the records name the ones just before an event.
struct Recent {
  std::uint32_t list = 0;
  std::uint32_t position = 0;
  std::uintptr_t table = 0;  // its object's vtable
};

struct Record {
  Event event = Event::put_back;
  std::uint32_t list = 0;      // UINT32_MAX: outside every list's arena
  std::uint32_t position = 0;  // as the check saw it (UINT32_MAX: an element it never saw)
  std::uint32_t length = 0;    // the list's calls when the check saw it
  std::uintptr_t element = 0;
  std::uintptr_t offset = 0;   // the element's offset in its arena
  std::uintptr_t was[2] = {};  // the element's words when the check saw them (next, object)
  std::uintptr_t now[2] = {};  // and as the run found them
  std::uintptr_t words_was[kObjectWords] = {};  // the call's object's first words then
  std::uintptr_t words_now[kObjectWords] = {};  // and now (object_changed)
  std::uint32_t words = 0;                      // words_was/words_now filled
  std::uintptr_t before_was[2] = {};            // the 16 bytes before the element then
  std::uintptr_t before_now[2] = {};            // and now
  bool before_read = false;
  Recent recent[kRecent];  // the calls run just before it, newest first
  std::uint32_t recent_count = 0;
  target_check::Finding target;  // target_gone: what the target judge found
};

struct Totals {
  std::uint64_t run = 0;        // calls run through step()
  std::uint64_t put_back = 0;   // elements whose words were put back (put_back and next_put_back)
  std::uint64_t skipped = 0;    // calls not run (object_changed, ran_twice, stranger)
  std::uint64_t ended = 0;      // lists ended early (ended, and ran_twice's end)
  std::uint64_t strangers = 0;  // elements the check never saw, followed
  std::uint64_t gone = 0;       // calls skipped because their material variable was gone (also in skipped; ADR 0261)
};

// Decides a stranger's object, as the queue check's judge does.
using Judge = queue_check::Judge;
// Calls an object as the engine does: slot 3 of its vtable, the object as `this`. Tests give a recorder.
using Caller = void (*)(std::uintptr_t object);
void call_object(std::uintptr_t object);

// ADR 0261: judges a call's target right before it runs (a gone verdict skips it). The game's wraps
// target_check::judge; tests give fakes.
using TargetJudge = target_check::Verdict (*)(void* context, std::uintptr_t object, target_check::Finding& finding);
// Told each event as it happens (after its record is filled). Must not throw.
using Notify = void (*)(void* context, const Record& record);
inline constexpr std::size_t kMaxNotified = 256;  // events told per run at most (every one is counted)

struct Hooks {
  TargetJudge target = nullptr;
  void* target_context = nullptr;
  Notify notify = nullptr;
  void* notify_context = nullptr;
};

// One watched run over the queued contexts' lists. Main thread only (the thread that began it); step() on any other
// thread, or with nothing begun, just calls the element's object as the engine would.
class Run {
 public:
  // Starts watching these lists; `thread` is the one whose CallQueued will reach step().
  void begin(const queue_check::List* lists, std::size_t count, Judge judge, void* judge_context, unsigned long thread,
             Caller caller = &call_object, const Hooks& hooks = {});
  // Keeps every element of the lists as they are now (after the walk). A list that cannot be walked is not kept: its
  // elements are judged as strangers. False (nothing watched) when the memory could not be read or kept.
  bool see() noexcept;
  // CallQueued's loop body while the dispatch is rewritten: runs or skips the element's call (the target judge asked
  // right before it would run) and leaves the element's next word leading to a real element or nowhere.
  void step(std::uintptr_t* element) noexcept;
  // Stops watching; the totals and records stay until the next begin().
  void end() noexcept;

  bool watching() const noexcept { return watching_; }
  const Totals& totals() const noexcept { return totals_; }
  const Record* records() const noexcept { return records_; }
  std::uint32_t recorded() const noexcept { return recorded_; }
  std::uint32_t length(std::size_t list) const noexcept { return list < kLists ? lengths_[list] : 0; }

 private:
  static constexpr std::size_t kLists = queue_check::kMaxLists;
  int list_of(std::uintptr_t element) const noexcept;
  Entry* find(std::uintptr_t element) noexcept;
  bool plausible(int list, std::uintptr_t next) const noexcept;
  bool unchanged(const Entry& entry, std::uintptr_t* words_now, std::uint32_t& words) const noexcept;
  void note(Event event, int list, const Entry* entry, std::uintptr_t element, const std::uintptr_t* words_now,
            std::uint32_t words, const target_check::Finding* target = nullptr) noexcept;
  void ran(int list, std::uint32_t position, std::uintptr_t object) noexcept;
  // Runs the call unless the target judge finds its target gone (then notes and counts it). True when it ran.
  bool run(int list, const Entry* entry, std::uintptr_t element, std::uint32_t position, std::uintptr_t object,
           std::uintptr_t table) noexcept;

  queue_check::List lists_[kLists] = {};
  std::size_t count_ = 0;
  Judge judge_ = nullptr;
  void* judge_context_ = nullptr;
  Caller caller_ = &call_object;
  Hooks hooks_{};
  std::uint32_t notified_ = 0;
  unsigned long thread_ = 0;
  bool watching_ = false;
  std::vector<Entry> entries_;  // sorted by element
  std::uint32_t lengths_[kLists] = {};
  Totals totals_{};
  Record records_[kMaxRecords];
  std::uint32_t recorded_ = 0;
  Recent recent_[kRecent];
  std::uint32_t recent_next_ = 0;
  std::uint32_t recent_count_ = 0;
};

}  // namespace nl::engine_guard::run_check
