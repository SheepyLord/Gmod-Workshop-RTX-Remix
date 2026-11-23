// Queued render calls checked before the material system leaves threaded rendering (ADR 0247).
//
// GMod's material system runs threaded: the main thread records render calls into one of two queued contexts while
// a render thread runs the other. When the game disconnects (the `disconnect` command, and every `map`, which
// disconnects first), Host_Disconnect closes the client side (its Lua state and binary modules) and then calls
// IMaterialSystem::AllowThreading(false), whose ForceSingleThreaded runs what both contexts still hold on the main
// thread. In field games (seven crashes, 2026-11-14 to 2026-11-19, each in a start that had just deployed new RTX
// content) that run reached a call whose object had been freed and its memory reused: its first word, the vtable,
// was another heap address, the game called through it (address 0, or garbage) and GMod's crash handler failed after
// it (exit 0xC0000409). The freed objects lay in GMod's own allocator (tier0's 64 KB blocks), never in the Windows
// heap this package's own queued calls (Model Hotloader, RTX Water) come from.
//
// The check wraps AllowThreading's vtable slot. Before the engine leaves threaded rendering it takes the material
// system's lock (so the render thread has finished the frame it was given), walks both contexts' call lists and
// unlinks every call whose object is not a live object of a loaded module: its first word must point into a loaded
// image's read-only data, and that vtable's call slot (3, the one the engine calls) into a loaded image's code. Live
// calls run as before. What was dropped is said in the game's console and in
// garrysmod/data/native-loader/render-queue-check.log, with the classes of the calls queued around it.
//
// Found by machine code, never by address, and only where sure (find_layout), in Remix starts only, like the colour
// cap. With the launch option -nl_queue_check_test each check first appends one call whose object is such a stale
// one to the list being recorded, so a test session goes through the drop path in the real game.
//
// The run check (run_check.h, ADR 0254) then watches the engine run the lists: after the walk it keeps every element,
// and while AllowThreading(false) runs, CallQueued's per-call dispatch goes through it, so an element written over
// during the run is put back and a call whose object changed is skipped. In a test session each check also appends
// a pair of calls, the first writing over the second's element as the field's crashes found it.
//
// ADR 0261 found what the field's crashes really were: not an element written over, but a queued CMaterialVar setter
// whose variable IMaterialSystem::UncacheAllMaterials had destroyed (the RTX fixes' map-exit cleanup calls it from the
// client's ShutDown hook, with the main thread's calls still queued). So:
// - flush() runs the calls this thread has queued now, before the cleanup: the engine's own flush of a queued context
//   (CMatQueuedRenderContext's one vtable slot that is Lock; CallQueued(this, 0); Unlock and calls nothing between
//   CallQueued and Unlock; find_flush), through the same check, walk and watched run as AllowThreading(false). Main
//   thread only; the copy of this module that did not install forwards it to the one that did
//   (nl_engine_guard_queue_flush_v1). Lua: nlengineguard.RunQueuedRenderCalls(). With the launch option
//   -nl_queue_check_no_flush (tests) it runs nothing and says it succeeded.
// - The run check judges each call's target right before it runs (target_check.h): a call on a material variable that
//   is no longer a variable of its material is skipped and logged.
// - The run check's events are written to the log as they happen, not after the run (at most 32 per run; the routine
//   flush line for a process's first 64 flushes), with module names from bases captured outside the material system's
//   lock (nothing written during the engine's run takes the loader lock).
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace nl::engine_guard::queue_check {

inline constexpr std::size_t kReach = 0x400;      // a function's code is read up to its padding (int3 int3), this far at most
inline constexpr std::size_t kMaxSlots = 512;     // CMaterialSystem's vtable is read this far at most
inline constexpr std::size_t kElement = 16;       // a call list's element: {next, object}
inline constexpr std::size_t kListHeader = 0x18;  // a call list: {head, tail, next free byte}, then its arena
inline constexpr std::size_t kCallSlot = 3;       // the slot the engine calls: call [vtable + 0x18]
inline constexpr std::size_t kMaxLists = 4;
inline constexpr std::size_t kMaxDrops = 8;  // drops recorded per check (every stale call found is dropped)

// Where GMod's material system keeps its queued calls, as its code says (find_layout).
struct Layout {
  std::size_t allow_slot = SIZE_MAX;   // IMaterialSystem::AllowThreading: refers to "Queued Material System: ENABLED!"
                                       // and "...DISABLED!"
  std::size_t lock_slot = SIZE_MAX;    // IMaterialSystem::Lock: "*CMaterialSystem::Lock: %0.2fms"
  std::size_t unlock_slot = SIZE_MAX;  // IMaterialSystem::Unlock: "*CMaterialSystem::Unlock: %0.2fms"
  std::uintptr_t force_rva = 0;        // ForceSingleThreaded: called by AllowThreading right after "DISABLED!"
  std::uintptr_t end_queue_rva = 0;    // the queued context's EndQueue: ForceSingleThreaded's loop calls it per context
  std::uintptr_t call_queued_rva = 0;  // the call list's CallQueued: EndQueue(true) calls it
  std::uintptr_t dispatch_rva = 0;     // CallQueued's per-call dispatch, the run check's site (ADR 0254)
  std::uint32_t contexts = 0;          // the first queued context, from the material system object
  std::uint32_t stride = 0;            // from one queued context to the next
  std::uint32_t count = 0;             // queued contexts ForceSingleThreaded ends
  std::uint32_t list = 0;              // the call list in a queued context
  std::string reason;                  // empty when every part was found exactly once
  bool found() const noexcept { return reason.empty(); }
};

// The layout in a mapped image of materialsystem.dll (sections at their virtual addresses). `vtable` points at
// CMaterialSystem's vtable in that mapping; its slots hold addresses relative to `loaded_base` (the image's own
// address when the system loaded it, its preferred base when it is only mapped as a file); `slots` may be read.
Layout find_layout(const std::uint8_t* image, std::uintptr_t loaded_base, const std::uintptr_t* vtable,
                   std::size_t slots) noexcept;

// The vtable (offset 0 in the object) of the class with that MSVC RTTI name (".?AVCMaterialSystem@@") in a mapped
// image, as find_layout wants it; nullptr unless there is exactly one.
const std::uintptr_t* find_vtable(const std::uint8_t* image, std::uintptr_t loaded_base,
                                  std::string_view rtti_name) noexcept;

// Why a queued call is dropped (live: it is kept).
enum class Why : std::uint8_t {
  live,
  null_object,               // the element names no object
  unreadable,                // the object's memory cannot be read
  first_word_not_in_module,  // its first word (the vtable) points outside every loaded image: freed memory reused
  first_word_not_constant,   // it points into an image, but not into read-only data
  call_not_code,             // the vtable's call slot does not point into an image's code
  test,                      // the test call (-nl_queue_check_test)
};
const char* describe(Why why) noexcept;

// Decides one call's object (its address, the element's second word). judge_memory() is the game's: it reads the
// object and the images' section headers through VirtualQuery and never takes the loader lock. Tests give fakes.
using Judge = Why (*)(void* context, std::uintptr_t object);
Why judge_memory(std::uintptr_t object) noexcept;

// One call list as the walk sees it.
struct List {
  std::uintptr_t* header = nullptr;  // {head, tail, next free byte}
  std::uintptr_t arena_begin = 0;    // where its elements may lie: [arena_begin, arena_end - kElement]
  std::uintptr_t arena_end = 0;
};

struct Drop {
  std::uint32_t list = 0;      // which context
  std::uint32_t position = 0;  // the call's place in its list, 0 first
  std::uint32_t length = 0;    // the list's calls before the check
  std::uintptr_t offset = 0;   // the element's offset in its arena
  std::uintptr_t object = 0;
  std::uintptr_t words[4] = {};  // the object's first words, as far as they could be read
  std::uint32_t words_read = 0;
  Why why = Why::live;
  std::uintptr_t before = 0;  // the vtables of the live calls queued just before and after it (0: none)
  std::uintptr_t after = 0;
};

struct Report {
  std::uint32_t lists = 0;
  std::uint32_t calls[kMaxLists] = {};  // each list's calls before the check
  std::uint32_t dropped = 0;            // calls unlinked from all lists
  std::uint32_t recorded = 0;           // drops[] filled (at most kMaxDrops)
  Drop drops[kMaxDrops];
  std::uint32_t broken = 0;  // bit i: list i could not be walked (an element outside its arena, a cycle, a tail that
                             // is not its last call); it is left as it was
};

// Walks each list and unlinks the calls the judge does not find live, keeping the others in order (head and tail
// follow). A list that cannot be walked is left as it is. Never throws; the game's check runs it under SEH.
Report clean(const List* lists, std::size_t count, Judge judge, void* judge_context) noexcept;

// Appends a call to a list as the engine's own appenders do: 16 bytes from its arena (the next free byte, rounded up
// to 8), linked at the tail. False when the arena is full or the list cannot be walked. The test call's way in.
bool append(const List& list, std::uintptr_t object) noexcept;

// A class's MSVC RTTI name (".?AV...@@") from a vtable in a loaded image, or "" (read under SEH).
std::string rtti_name(std::uintptr_t vtable) noexcept;
// The same into a buffer, without allocating; false (and "") when there is none.
bool rtti_name_into(std::uintptr_t vtable, char* out, std::size_t size) noexcept;

// The queued context's flush (ADR 0261): in CMatQueuedRenderContext's vtable (`vtable`, `slots` readable, in a mapped
// image as for find_layout), the one slot whose code is
//   mov rcx,[rdi+ms]; mov rax,[rcx]; call [rax+Lock]; xor edx,edx; mov rcx,rdi; mov rbx,rax; call CallQueued;
//   mov rcx,[rdi+ms]; mov rdx,rbx; mov r8|rax,[rcx]; call [r8|rax+Unlock]
// with Lock and Unlock the material system's slots times 8, CallQueued the layout's and both loads of the material
// system's pointer the same: nothing is called between CallQueued and Unlock. Found exactly once, or not at all.
// The flush's Lock must start this close to its function's start (the build of 2026-11: +0x35); a match further in
// may lie in the next function, which follows without padding.
inline constexpr std::size_t kFlushStart = 0x60;
struct FlushSlot {
  std::size_t slot = SIZE_MAX;
  std::string reason;  // empty when found exactly once
  bool found() const noexcept { return reason.empty(); }
};
FlushSlot find_flush(const std::uint8_t* image, std::uintptr_t loaded_base, const std::uintptr_t* vtable,
                     std::size_t slots, const Layout& layout) noexcept;

struct Status {
  bool installed = false;
  std::string reason;         // "installed", "installed by the other copy of this module", or why not
  std::uint64_t checks = 0;   // AllowThreading(false) calls checked
  std::uint64_t dropped = 0;  // calls dropped
  bool test = false;          // -nl_queue_check_test
  // The run check (ADR 0254): the calls watched again while the game runs them.
  bool run_check = false;
  std::string run_reason;        // "installed", "installed by the other copy of this module", or why not
  std::uint64_t runs = 0;        // runs watched
  std::uint64_t put_back = 0;    // elements put back as the check saw them
  std::uint64_t skipped = 0;     // calls not run
  std::uint64_t ended = 0;       // lists ended early
  // ADR 0261: the queued context's flush and the target check.
  bool queue_flush = false;
  std::string flush_reason;      // "installed", "installed by the other copy of this module", or why not
  bool target_check = false;
  std::string target_reason;     // "installed", "installed by the other copy of this module", or why not
  std::uint64_t flushes = 0;     // flushes that ran the queued context's flush
  std::uint64_t gone = 0;        // calls skipped because their material variable was gone (also in skipped)
  bool no_flush = false;         // -nl_queue_check_no_flush
};

// What flush() did. ok: what this thread had queued has run (the context's flush ran, this thread does not record into
// a queued context, or the test option said so). Inside a render block the engine's flush queues one call of its own
// after itself; `why` then says how many are queued again.
struct FlushResult {
  bool ok = false;
  std::uint64_t calls = 0;  // calls run through the flush
  std::string why;
};

// Runs the calls this thread has queued through the queued context's own flush, watched as the engine's run at
// AllowThreading(false) is (ADR 0261). Main thread only. Never throws.
FlushResult flush() noexcept;

// Tests only (ADR 0261): the flush's own logic without a game. use_for_test makes this copy's flush() use stand-ins as
// if install() had found them (the run check off): the material system object, the layout of its queued contexts,
// Lock, Unlock and the context's flush, the calling thread as the main thread, and `log` as the log's path;
// reset_for_test undoes it. The module never calls them.
struct StandIns {
  void* system = nullptr;
  Layout layout;
  void* (*lock)(void* system) = nullptr;
  void (*unlock)(void* system, void* lock) = nullptr;
  void (*flush)(void* context) = nullptr;
  bool no_flush = false;
  std::wstring log;
};
void use_for_test(const StandIns& stand_ins) noexcept;
void reset_for_test() noexcept;

// Wraps AllowThreading's slot of the loaded materialsystem.dll. Idempotent, also across the client and the server copy
// of this module; pins this module first (the slot points into it for the process's lifetime). Does nothing without
// the Remix runtime as d3d9.dll. Never throws.
Status install() noexcept;
Status status() noexcept;

}  // namespace nl::engine_guard::queue_check
