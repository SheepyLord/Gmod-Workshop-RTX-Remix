// Queued render calls checked before the material system leaves threaded rendering (ADR 0247).
#include "queue_check.h"

#include "guard.h"  // find(): byte patterns with wildcards

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <mutex>
#include <vector>

namespace nl::engine_guard::queue_check {

const char* describe(Why why) noexcept {
  switch (why) {
    case Why::live:
      return "live";
    case Why::null_object:
      return "the element names no object";
    case Why::unreadable:
      return "its object's memory cannot be read";
    case Why::first_word_not_in_module:
      return "its object's first word (the vtable) is outside every loaded module: the object was freed and its "
             "memory reused";
    case Why::first_word_not_constant:
      return "its object's first word points into a module, but not into read-only data";
    case Why::call_not_code:
      return "its vtable's call slot does not point into a module's code";
    case Why::test:
      return "the test call (-nl_queue_check_test)";
  }
  return "?";
}

namespace {

// The arena of a call list: GMod's appenders refuse an element past 16 MB (cmp rax, 1000000h).
constexpr std::uintptr_t kArena = 0x1000000;

struct Sections {
  const IMAGE_SECTION_HEADER* first = nullptr;
  unsigned count = 0;
};

bool read_sections(const std::uint8_t* image, Sections& out) noexcept {
  if (!image) return false;
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 0x10000) return false;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return false;
  out.first = IMAGE_FIRST_SECTION(nt);
  out.count = nt->FileHeader.NumberOfSections;
  return true;
}

// The section holding [rva, rva + size), or nullptr.
const IMAGE_SECTION_HEADER* section_at(const Sections& s, std::uintptr_t rva, std::size_t size) noexcept {
  for (unsigned i = 0; i < s.count; ++i) {
    const auto& h = s.first[i];
    const std::uintptr_t begin = h.VirtualAddress;
    const std::uintptr_t end = begin + h.Misc.VirtualSize;
    if (rva >= begin && rva < end && size <= end - rva) return &h;
  }
  return nullptr;
}

bool is_code(const IMAGE_SECTION_HEADER* h) noexcept { return h && (h->Characteristics & IMAGE_SCN_MEM_EXECUTE); }

bool is_constant(const IMAGE_SECTION_HEADER* h) noexcept {
  return h && (h->Characteristics & IMAGE_SCN_MEM_READ) &&
         !(h->Characteristics & (IMAGE_SCN_MEM_WRITE | IMAGE_SCN_MEM_EXECUTE));
}

// A function's code in the mapped image: from `address` (relative to loaded_base) up to its padding (int3 int3) or
// kReach bytes, never past its section. nullptr when `address` is not in the image's code.
const std::uint8_t* function_code(const std::uint8_t* image, std::uintptr_t loaded_base, const Sections& s,
                                  std::uintptr_t address, std::size_t& size, std::uintptr_t& rva) noexcept {
  size = 0;
  rva = 0;
  if (address < loaded_base) return nullptr;
  rva = address - loaded_base;
  const auto* h = section_at(s, rva, 1);
  if (!is_code(h)) return nullptr;
  const std::uintptr_t end = h->VirtualAddress + h->Misc.VirtualSize;
  std::size_t n = static_cast<std::size_t>(std::min<std::uintptr_t>(kReach, end - rva));
  const std::uint8_t* code = image + rva;
  for (std::size_t i = 0; i + 1 < n; ++i) {
    if (code[i] == 0xCC && code[i + 1] == 0xCC) {
      n = i;
      break;
    }
  }
  size = n;
  return code;
}

// The offset in `code` of a `lea r64, [rip + disp32]` whose target is a string in the image's read-only data
// containing `text`, or SIZE_MAX.
std::size_t lea_to(const std::uint8_t* code, std::size_t size, std::uintptr_t rva, const std::uint8_t* image,
                   const Sections& s, std::string_view text) noexcept {
  for (std::size_t i = 0; i + 7 <= size; ++i) {
    if ((code[i] != 0x48 && code[i] != 0x4C) || code[i + 1] != 0x8D || (code[i + 2] & 0xC7) != 0x05) continue;
    std::int32_t displacement = 0;
    std::memcpy(&displacement, code + i + 3, 4);
    const std::int64_t target = static_cast<std::int64_t>(rva + i + 7) + displacement;
    if (target <= 0) continue;
    const auto target_rva = static_cast<std::uintptr_t>(target);
    const auto* h = section_at(s, target_rva, 1);
    if (!is_constant(h)) continue;
    const std::uintptr_t end = h->VirtualAddress + h->Misc.VirtualSize;
    const auto* at = reinterpret_cast<const char*>(image + target_rva);
    const std::size_t length = strnlen(at, static_cast<std::size_t>(std::min<std::uintptr_t>(end - target_rva, 256)));
    if (std::string_view(at, length).find(text) != std::string_view::npos) return i;
  }
  return SIZE_MAX;
}

// The target of the `call rel32` (E8) at code[at], as an RVA.
std::uintptr_t call_target(const std::uint8_t* code, std::uintptr_t rva, std::size_t at) noexcept {
  std::int32_t relative = 0;
  std::memcpy(&relative, code + at + 1, 4);
  return static_cast<std::uintptr_t>(static_cast<std::int64_t>(rva + at + 5) + relative);
}

std::uint32_t u32(const std::uint8_t* p) noexcept {
  std::uint32_t value = 0;
  std::memcpy(&value, p, 4);
  return value;
}

// ForceSingleThreaded's loop over the queued contexts: mov dl,1; imul rcx,rax,<stride>; add rcx,<first context>;
// add rcx,rdi; call <EndQueue>; inc ebx; cmp ebx,<count>; jb
const std::vector<int>& force_loop() {
  static const std::vector<int> pattern = {0xB2, 0x01, 0x48, 0x69, 0xC8, -1,   -1,   -1, -1, 0x48,
                                           0x81, 0xC1, -1,   -1,   -1,   -1,   0x48, 0x03, 0xCF, 0xE8,
                                           -1,   -1,   -1,   -1,   0xFF, 0xC3, 0x83, 0xFB, -1,   0x72};
  return pattern;
}

// EndQueue(bool call): test dl,dl; je; xor edx,edx; call <CallQueued>
const std::vector<int>& end_queue_call() {
  static const std::vector<int> pattern = {0x84, 0xD2, 0x74, -1, 0x33, 0xD2, 0xE8, -1, -1, -1, -1};
  return pattern;
}

// CallQueued's loop and the list's reset: mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h]; mov rbx,[rbx];
// test rbx,rbx; jne; lea rax,[rdi+list+18h]; mov [rdi+list+8],r12; mov [rdi+list+10h],rax; mov [rdi+list],r12
const std::vector<int>& runner() {
  static const std::vector<int> pattern = {
      0x48, 0x8B, 0x4B, 0x08, 0x48, 0x8B, 0x01, 0xFF, 0x50, 0x18, 0x48, 0x8B, 0x1B, 0x48, 0x85, 0xDB,
      0x75, -1,   0x48, 0x8D, 0x87, -1,   -1,   -1,   -1,   0x4C, 0x89, 0xA7, -1,   -1,   -1,   -1,
      0x48, 0x89, 0x87, -1,   -1,   -1,   -1,   0x4C, 0x89, 0xA7, -1,   -1,   -1,   -1};
  return pattern;
}

Layout failed(Layout layout, const char* why) {
  layout.reason = why;
  return layout;
}
}  // namespace

Layout find_layout(const std::uint8_t* image, std::uintptr_t loaded_base, const std::uintptr_t* vtable,
                   std::size_t slots) noexcept {
  Layout out;
  try {
    Sections s;
    if (!vtable || !read_sections(image, s)) return failed(out, "materialsystem.dll's headers could not be read");
    std::size_t allows = 0, locks = 0, unlocks = 0, disabled = 0, allow_size = 0;
    const std::uint8_t* allow_code = nullptr;
    std::uintptr_t allow_rva = 0;
    for (std::size_t i = 0; i < std::min(slots, kMaxSlots); ++i) {
      std::size_t size = 0;
      std::uintptr_t rva = 0;
      const auto* code = function_code(image, loaded_base, s, vtable[i], size, rva);
      if (!code) continue;  // a slot another module changed: never one of ours
      const std::size_t at = lea_to(code, size, rva, image, s, "Queued Material System: DISABLED!");
      if (at != SIZE_MAX && lea_to(code, size, rva, image, s, "Queued Material System: ENABLED!") != SIZE_MAX) {
        ++allows;
        out.allow_slot = i;
        allow_code = code;
        allow_size = size;
        allow_rva = rva;
        disabled = at;
      }
      if (lea_to(code, size, rva, image, s, "CMaterialSystem::Lock:") != SIZE_MAX) {
        ++locks;
        out.lock_slot = i;
      }
      if (lea_to(code, size, rva, image, s, "CMaterialSystem::Unlock:") != SIZE_MAX) {
        ++unlocks;
        out.unlock_slot = i;
      }
    }
    if (allows != 1) return failed(out, "AllowThreading was not found once in the material system's vtable");
    if (locks != 1 || unlocks != 1)
      return failed(out, "Lock and Unlock were not found once in the material system's vtable");
    // AllowThreading(false): lea rcx,"...DISABLED!"; call [rip+DevMsg]; mov rcx,<this>; call ForceSingleThreaded
    const std::size_t d = disabled;
    if (d + 21 > allow_size || allow_code[d + 7] != 0xFF || allow_code[d + 8] != 0x15 || allow_code[d + 13] != 0x48 ||
        allow_code[d + 14] != 0x8B || (allow_code[d + 15] & 0xF8) != 0xC8 || allow_code[d + 16] != 0xE8)
      return failed(out, "AllowThreading does not call ForceSingleThreaded after its message");
    out.force_rva = call_target(allow_code, allow_rva, d + 16);
    std::size_t size = 0;
    std::uintptr_t rva = 0;
    const auto* force = function_code(image, 0, s, out.force_rva, size, rva);
    if (!force) return failed(out, "ForceSingleThreaded is not in materialsystem.dll's code");
    const auto loops = nl::engine_guard::find(force, size, force_loop(), 2);
    if (loops.size() != 1) return failed(out, "ForceSingleThreaded's loop over the queued contexts was not found once");
    const std::size_t loop = loops[0];
    out.stride = u32(force + loop + 5);
    out.contexts = u32(force + loop + 12);
    out.end_queue_rva = call_target(force, rva, loop + 19);
    out.count = force[loop + 28];
    const auto* end_queue = function_code(image, 0, s, out.end_queue_rva, size, rva);
    if (!end_queue) return failed(out, "EndQueue is not in materialsystem.dll's code");
    const auto calls = nl::engine_guard::find(end_queue, std::min<std::size_t>(size, 0x40), end_queue_call(), 2);
    if (calls.size() != 1) return failed(out, "EndQueue's call of CallQueued was not found once");
    out.call_queued_rva = call_target(end_queue, rva, calls[0] + 6);
    const auto* call_queued = function_code(image, 0, s, out.call_queued_rva, size, rva);
    if (!call_queued) return failed(out, "CallQueued is not in materialsystem.dll's code");
    const auto runs = nl::engine_guard::find(call_queued, size, runner(), 2);
    if (runs.size() != 1) return failed(out, "CallQueued's loop was not found once");
    const std::size_t run = runs[0];
    const std::uint32_t arena = u32(call_queued + run + 21), tail = u32(call_queued + run + 28);
    const std::uint32_t next = u32(call_queued + run + 35), head = u32(call_queued + run + 42);
    if (tail != head + 8 || next != head + 16 || arena != head + kListHeader)
      return failed(out, "CallQueued's list is not {head, tail, next free byte} before its arena");
    out.list = head;
    if (out.count < 1 || out.count > kMaxLists) return failed(out, "an unexpected number of queued contexts");
    if (std::uint64_t{out.list} + kListHeader + kArena > out.stride)
      return failed(out, "a queued context is smaller than its call list");
    return out;
  } catch (...) {
    return failed(out, "the material system's code could not be read");
  }
}

const std::uintptr_t* find_vtable(const std::uint8_t* image, std::uintptr_t loaded_base,
                                  std::string_view rtti_name) noexcept {
  try {
    Sections s;
    if (rtti_name.empty() || !read_sections(image, s)) return nullptr;
    std::string needle(rtti_name);
    needle.push_back('\0');
    // The type descriptor {vtable pointer, spare, name}: the name and its NUL, 16 bytes in.
    std::uintptr_t descriptor = 0;
    unsigned descriptors = 0;
    for (unsigned i = 0; i < s.count; ++i) {
      const auto& h = s.first[i];
      if (h.Characteristics & IMAGE_SCN_MEM_EXECUTE) continue;
      const std::size_t size = std::min<std::size_t>(h.Misc.VirtualSize, h.SizeOfRawData);
      const std::string_view data(reinterpret_cast<const char*>(image + h.VirtualAddress), size);
      for (std::size_t at = data.find(needle); at != std::string_view::npos; at = data.find(needle, at + 1)) {
        if (at < 16) continue;
        descriptor = h.VirtualAddress + at - 16;
        ++descriptors;
      }
    }
    if (descriptors != 1) return nullptr;
    // The complete object locator of the most derived class: {1, offset 0, cd offset, descriptor, hierarchy, self}.
    std::uintptr_t locator = 0;
    unsigned locators = 0;
    for (unsigned i = 0; i < s.count; ++i) {
      const auto& h = s.first[i];
      if (!is_constant(&h)) continue;
      const std::size_t size = std::min<std::size_t>(h.Misc.VirtualSize, h.SizeOfRawData);
      for (std::size_t at = 0; at + 24 <= size; at += 4) {
        const std::uint8_t* p = image + h.VirtualAddress + at;
        if (u32(p) == 1 && u32(p + 4) == 0 && u32(p + 12) == descriptor && u32(p + 20) == h.VirtualAddress + at) {
          locator = h.VirtualAddress + at;
          ++locators;
        }
      }
    }
    if (locators != 1) return nullptr;
    // The vtable follows the pointer to that locator.
    const std::uint64_t wanted = loaded_base + locator;
    const std::uintptr_t* found = nullptr;
    unsigned vtables = 0;
    for (unsigned i = 0; i < s.count; ++i) {
      const auto& h = s.first[i];
      if (!is_constant(&h)) continue;
      const std::size_t size = std::min<std::size_t>(h.Misc.VirtualSize, h.SizeOfRawData);
      for (std::size_t at = 0; at + 16 <= size; at += 8) {
        std::uint64_t value = 0;
        std::memcpy(&value, image + h.VirtualAddress + at, 8);
        if (value == wanted) {
          found = reinterpret_cast<const std::uintptr_t*>(image + h.VirtualAddress + at + 8);
          ++vtables;
        }
      }
    }
    return vtables == 1 ? found : nullptr;
  } catch (...) {
    return nullptr;
  }
}

namespace {
// Readable committed memory at [address, address + size).
bool readable(std::uintptr_t address, std::size_t size) noexcept {
  while (size) {
    MEMORY_BASIC_INFORMATION m{};
    if (!VirtualQuery(reinterpret_cast<const void*>(address), &m, sizeof(m))) return false;
    if (m.State != MEM_COMMIT || (m.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
    if (!(m.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE |
                       PAGE_EXECUTE_WRITECOPY)))
      return false;
    const std::uintptr_t end = reinterpret_cast<std::uintptr_t>(m.BaseAddress) + m.RegionSize;
    if (end <= address) return false;
    const std::size_t here = static_cast<std::size_t>(std::min<std::uintptr_t>(size, end - address));
    size -= here;
    address += here;
  }
  return true;
}

// The characteristics of the loaded image's section holding [address, address + size), or 0 when no image's section
// holds it. VirtualQuery and the image's own headers: no loader lock.
DWORD image_section(std::uintptr_t address, std::size_t size) noexcept {
  MEMORY_BASIC_INFORMATION m{};
  if (!VirtualQuery(reinterpret_cast<const void*>(address), &m, sizeof(m))) return 0;
  if (m.Type != MEM_IMAGE || m.State != MEM_COMMIT || !m.AllocationBase) return 0;
  const auto* base = static_cast<const std::uint8_t*>(m.AllocationBase);
  Sections s;
  if (!read_sections(base, s)) return 0;
  const auto* h = section_at(s, address - reinterpret_cast<std::uintptr_t>(base), size);
  return h ? h->Characteristics : 0;
}

// The walk's first pass, reading only: every element inside the arena, no cycle, the tail its last element.
bool walkable(const List& list, std::uintptr_t& length) noexcept {
  length = 0;
  if (!list.header || list.arena_end <= list.arena_begin || list.arena_end - list.arena_begin < kElement) return false;
  const std::uintptr_t limit = (list.arena_end - list.arena_begin) / kElement;
  const std::uintptr_t head = list.header[0], tail = list.header[1];
  std::uintptr_t last = 0;
  for (std::uintptr_t e = head; e; e = *reinterpret_cast<const std::uintptr_t*>(e)) {
    if (e < list.arena_begin || e > list.arena_end - kElement || ++length > limit) return false;
    last = e;
  }
  return head ? tail == last : tail == 0;
}
}  // namespace

Why judge_memory(std::uintptr_t object) noexcept {
  if (!object) return Why::null_object;
  if (!readable(object, 8)) return Why::unreadable;
  const std::uintptr_t table = *reinterpret_cast<const std::uintptr_t*>(object);
  const DWORD data = image_section(table, 8 * (kCallSlot + 1));
  if (!data) return Why::first_word_not_in_module;
  if ((data & (IMAGE_SCN_MEM_WRITE | IMAGE_SCN_MEM_EXECUTE)) || !(data & IMAGE_SCN_MEM_READ))
    return Why::first_word_not_constant;
  const std::uintptr_t call = reinterpret_cast<const std::uintptr_t*>(table)[kCallSlot];
  if (!(image_section(call, 1) & IMAGE_SCN_MEM_EXECUTE)) return Why::call_not_code;
  return Why::live;
}

Report clean(const List* lists, std::size_t count, Judge judge, void* judge_context) noexcept {
  Report report{};
  if (!lists || !judge) return report;
  count = std::min(count, kMaxLists);
  report.lists = static_cast<std::uint32_t>(count);
  for (std::size_t index = 0; index < count; ++index) {
    const List& list = lists[index];
    std::uintptr_t length = 0;
    if (!walkable(list, length)) {
      report.broken |= 1u << index;
      continue;
    }
    report.calls[index] = static_cast<std::uint32_t>(std::min<std::uintptr_t>(length, UINT32_MAX));
    std::uintptr_t head = list.header[0], tail = list.header[1], previous = 0, previous_table = 0;
    std::uint32_t waiting = report.recorded;  // drops of this list still waiting for the live call after them
    std::uint32_t position = 0;
    for (std::uintptr_t e = list.header[0]; e; ++position) {
      auto* element = reinterpret_cast<std::uintptr_t*>(e);
      const std::uintptr_t next = element[0], object = element[1];
      const Why why = judge(judge_context, object);
      if (why == Why::live) {
        const std::uintptr_t table = *reinterpret_cast<const std::uintptr_t*>(object);
        for (std::uint32_t d = waiting; d < report.recorded; ++d) report.drops[d].after = table;
        waiting = report.recorded;
        previous_table = table;
        previous = e;
      } else {
        if (previous)
          reinterpret_cast<std::uintptr_t*>(previous)[0] = next;
        else
          head = next;
        if (tail == e) tail = previous;
        ++report.dropped;
        if (report.recorded < kMaxDrops) {
          Drop& drop = report.drops[report.recorded++];
          drop.list = static_cast<std::uint32_t>(index);
          drop.position = position;
          drop.length = report.calls[index];
          drop.offset = e - list.arena_begin;
          drop.object = object;
          drop.why = why;
          drop.before = previous_table;
          for (unsigned w = 0; w < 4 && object && readable(object + 8 * w, 8); ++w) {
            drop.words[w] = reinterpret_cast<const std::uintptr_t*>(object)[w];
            drop.words_read = w + 1;
          }
        }
      }
      e = next;
    }
    list.header[0] = head;
    list.header[1] = tail;
  }
  return report;
}

bool append(const List& list, std::uintptr_t object) noexcept {
  std::uintptr_t length = 0;
  if (!walkable(list, length)) return false;
  const std::uintptr_t at = (list.header[2] + 7) & ~std::uintptr_t{7};
  if (at < list.arena_begin || at > list.arena_end - kElement) return false;
  auto* element = reinterpret_cast<std::uintptr_t*>(at);
  element[0] = 0;
  element[1] = object;
  list.header[2] = at + kElement;
  if (list.header[1])
    reinterpret_cast<std::uintptr_t*>(list.header[1])[0] = at;
  else
    list.header[0] = at;
  list.header[1] = at;
  return true;
}

namespace {
// The class name behind a vtable in a loaded image: the complete object locator before it, its type descriptor's
// name. Under SEH, into a buffer (no unwinding here).
bool rtti_name_raw(std::uintptr_t vtable, char* out, std::size_t size) noexcept {
  out[0] = 0;
  __try {
    MEMORY_BASIC_INFORMATION m{};
    if (vtable < 8 || !VirtualQuery(reinterpret_cast<const void*>(vtable - 8), &m, sizeof(m)) || m.Type != MEM_IMAGE)
      return false;
    const auto base = reinterpret_cast<std::uintptr_t>(m.AllocationBase);
    const std::uintptr_t locator = *reinterpret_cast<const std::uintptr_t*>(vtable - 8);
    MEMORY_BASIC_INFORMATION l{};
    if (!VirtualQuery(reinterpret_cast<const void*>(locator), &l, sizeof(l)) || l.AllocationBase != m.AllocationBase)
      return false;
    const auto* col = reinterpret_cast<const std::uint32_t*>(locator);
    if (col[0] != 1 || col[5] != locator - base) return false;
    const auto* text = reinterpret_cast<const char*>(base + col[3] + 16);
    std::size_t i = 0;
    for (; i + 1 < size && text[i]; ++i) out[i] = text[i];
    out[i] = 0;
    return i > 0;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    out[0] = 0;
    return false;
  }
}
}  // namespace

std::string rtti_name(std::uintptr_t vtable) noexcept {
  char name[192];
  if (!rtti_name_raw(vtable, name, sizeof(name))) return {};
  try {
    return name;
  } catch (...) {
    return {};
  }
}

namespace {
using AllowThreading = bool (*)(void* self, bool allow, int service_thread);
using LockFn = void* (*)(void* self);
using UnlockFn = void (*)(void* self, void* lock);

// Set before the slot changes and never after.
AllowThreading g_allow = nullptr;
LockFn g_lock = nullptr;
UnlockFn g_unlock = nullptr;
void* g_object = nullptr;
Layout g_layout;
bool g_test = false;
// The test call's object: its first word is a heap address, as a freed and reused object's would be.
std::uintptr_t g_test_object[4] = {};

std::atomic<bool> g_owns{false};  // this copy changed the slot
std::atomic<std::uint64_t> g_checks{0};
std::atomic<std::uint64_t> g_dropped{0};

std::mutex g_install;
Status g_status;  // under g_install
// The other copy's counts, when it installed first (the client and the server module are two images in one process;
// the slot points into only one of them).
using Owner = int (*)(std::uint64_t* checks, std::uint64_t* dropped, int* test);
Owner g_owner = nullptr;  // under g_install

using Msg = void (*)(const char*, ...);
void say(const char* text) {
  const HMODULE tier0 = GetModuleHandleW(L"tier0.dll");
  const auto msg = tier0 ? reinterpret_cast<Msg>(GetProcAddress(tier0, "Msg")) : nullptr;
  if (msg) msg("%s", text);
}

// The live vtables seen in one check: most calls share a handful.
struct Seen {
  std::uintptr_t tables[64];
  std::size_t count;
};

Why judge_in_game(void* context, std::uintptr_t object) {
  if (object && object == reinterpret_cast<std::uintptr_t>(&g_test_object)) return Why::test;
  auto* seen = static_cast<Seen*>(context);
  if (!object) return Why::null_object;
  if (!readable(object, 8)) return Why::unreadable;
  const std::uintptr_t table = *reinterpret_cast<const std::uintptr_t*>(object);
  for (std::size_t i = 0; i < seen->count; ++i)
    if (seen->tables[i] == table) return Why::live;
  const Why why = judge_memory(object);
  if (why == Why::live && seen->count < 64) seen->tables[seen->count++] = table;
  return why;
}

// The walk under SEH: another thread may free memory a call's object pointed at between the check and the read.
// Returns false when it stopped on such a fault (the lists keep every unlink done before it, each complete).
bool clean_guarded(const List* lists, std::size_t count, std::size_t test_list, Report* report) noexcept {
  Seen seen{};
  __try {
    if (test_list < count) append(lists[test_list], reinterpret_cast<std::uintptr_t>(&g_test_object));
    *report = clean(lists, count, &judge_in_game, &seen);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

std::string narrow(const wchar_t* text) {
  char out[MAX_PATH * 3]{};
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out, sizeof(out), nullptr, nullptr);
  return out;
}

std::string module_name(std::uintptr_t address) {
  MEMORY_BASIC_INFORMATION m{};
  if (!VirtualQuery(reinterpret_cast<const void*>(address), &m, sizeof(m)) || m.Type != MEM_IMAGE) return {};
  wchar_t path[MAX_PATH]{};
  if (!GetModuleFileNameW(static_cast<HMODULE>(m.AllocationBase), path, MAX_PATH)) return {};
  const wchar_t* name = std::wcsrchr(path, L'\\');
  return narrow(name ? name + 1 : path);
}

std::string hex(std::uintptr_t value) {
  char text[24];
  std::snprintf(text, sizeof(text), "0x%llx", static_cast<unsigned long long>(value));
  return text;
}

// A queued call's class, from its vtable: the module and the RTTI name.
std::string describe_table(std::uintptr_t table) {
  if (!table) return "none";
  std::string out = module_name(table);
  if (out.empty()) out = hex(table);
  const std::string name = rtti_name(table);
  if (!name.empty()) out += " " + name.substr(0, 160);
  return out;
}

// What memory an address lies in: the kind, and the allocation it belongs to.
std::string describe_memory(std::uintptr_t address) {
  MEMORY_BASIC_INFORMATION m{};
  if (!VirtualQuery(reinterpret_cast<const void*>(address), &m, sizeof(m))) return "not in the address space";
  if (m.State == MEM_FREE) return "unmapped";
  const char* kind = m.Type == MEM_IMAGE ? "image" : m.Type == MEM_MAPPED ? "mapped" : "private";
  const auto base = reinterpret_cast<std::uintptr_t>(m.AllocationBase);
  std::uintptr_t size = 0;
  for (std::uintptr_t at = base, steps = 0; steps < 4096; ++steps) {
    MEMORY_BASIC_INFORMATION r{};
    if (!VirtualQuery(reinterpret_cast<const void*>(at), &r, sizeof(r)) || r.AllocationBase != m.AllocationBase) break;
    size += r.RegionSize;
    at = reinterpret_cast<std::uintptr_t>(r.BaseAddress) + r.RegionSize;
  }
  char text[160];
  std::snprintf(text, sizeof(text), "%s memory, an allocation of %llu KiB at %s", kind,
                static_cast<unsigned long long>(size / 1024), hex(base).c_str());
  std::string out = text;
  if (m.Type == MEM_IMAGE) out += " (" + module_name(address) + ")";
  return out;
}

std::wstring log_path() {
  wchar_t exe[MAX_PATH]{};
  if (!GetModuleFileNameW(nullptr, exe, MAX_PATH)) return {};
  std::wstring root(exe);
  for (int i = 0; i < 3; ++i) {  // ...\bin\win64\gmod.exe -> the game root
    const auto slash = root.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return {};
    root.erase(slash);
  }
  const std::wstring folder = root + L"\\garrysmod\\data\\native-loader";
  CreateDirectoryW(folder.c_str(), nullptr);
  return folder + L"\\render-queue-check.log";
}

// Appends to the log, which keeps its last 128 KiB once it passes 256 KiB.
void write_log(const std::string& text) {
  const auto path = log_path();
  if (path.empty()) return;
  WIN32_FILE_ATTRIBUTE_DATA attributes{};
  if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &attributes) && attributes.nFileSizeHigh == 0 &&
      attributes.nFileSizeLow > 256 * 1024) {
    const HANDLE in = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (in != INVALID_HANDLE_VALUE) {
      std::string keep(128 * 1024, '\0');
      LARGE_INTEGER offset{};
      offset.QuadPart = static_cast<LONGLONG>(attributes.nFileSizeLow) - static_cast<LONGLONG>(keep.size());
      DWORD read = 0;
      const bool ok = SetFilePointerEx(in, offset, nullptr, FILE_BEGIN) &&
                      ReadFile(in, keep.data(), static_cast<DWORD>(keep.size()), &read, nullptr);
      CloseHandle(in);
      keep.resize(ok ? read : 0);
      const auto line = keep.find('\n');
      keep.erase(0, line == std::string::npos ? keep.size() : line + 1);
      const HANDLE out = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (out != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(out, keep.data(), static_cast<DWORD>(keep.size()), &written, nullptr);
        CloseHandle(out);
      }
    }
  }
  const HANDLE file =
      CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr);
  CloseHandle(file);
}

std::string utc_now() {
  SYSTEMTIME now{};
  GetSystemTime(&now);
  char text[32];
  std::snprintf(text, sizeof(text), "%04u-%02u-%02uT%02u:%02u:%02uZ", now.wYear, now.wMonth, now.wDay, now.wHour,
                now.wMinute, now.wSecond);
  return text;
}

// Says what a check dropped (or could not walk): the console once per check, the log with the details.
void record(const Report& report, bool walked, std::uint64_t check) {
  try {
    std::uint32_t tests = 0;
    for (std::uint32_t i = 0; i < report.recorded; ++i)
      if (report.drops[i].why == Why::test) ++tests;
    const std::uint32_t real = report.dropped - std::min(tests, report.dropped);
    std::string text = utc_now() + " check " + std::to_string(check) + " before the game left threaded rendering:";
    for (std::uint32_t i = 0; i < report.lists; ++i)
      text += (i ? ", " : " ") + std::string("list ") + std::to_string(i) +
              ((report.broken >> i) & 1 ? " not walked" : " " + std::to_string(report.calls[i]) + " calls");
    text += "; " + std::to_string(report.dropped) + " dropped" + (walked ? "" : "; the walk stopped on a fault") + "\n";
    for (std::uint32_t i = 0; i < report.recorded; ++i) {
      const Drop& d = report.drops[i];
      text += "  list " + std::to_string(d.list) + ", call " + std::to_string(d.position + 1) + " of " +
              std::to_string(d.length) + " (element +" + hex(d.offset) + "): object " + hex(d.object) + ", " +
              describe(d.why) + "\n";
      if (d.object) text += "    object memory: " + describe_memory(d.object) + "\n";
      if (d.words_read) {
        text += "    first words:";
        for (std::uint32_t w = 0; w < d.words_read; ++w) text += " " + hex(d.words[w]);
        if (d.words[0]) text += " (the first in " + describe_memory(d.words[0]) + ")";
        text += "\n";
      }
      text += "    queued before it: " + describe_table(d.before) + "\n";
      text += "    queued after it: " + describe_table(d.after) + "\n";
    }
    if (report.dropped > report.recorded)
      text += "  and " + std::to_string(report.dropped - report.recorded) + " more dropped\n";
    write_log(text);
    if (real) {
      say(("[NativeLoader] Dropped " + std::to_string(real) +
           " queued render call(s) whose object was already gone, before the game left threaded rendering (engine "
           "guard, ADR 0247). Details: garrysmod/data/native-loader/render-queue-check.log\n")
              .c_str());
    }
    if (tests) say("[NativeLoader] Queue check test: the test call was dropped (engine guard, ADR 0247).\n");
    if (report.broken)
      say("[NativeLoader] The queue check could not walk a render call list and left it as it was (engine guard, "
          "ADR 0247).\n");
    if (!walked) say("[NativeLoader] The queue check stopped on a fault while reading a queued call (ADR 0247).\n");
  } catch (...) {
  }
}

// Before the engine leaves threaded rendering: the lock (the render thread finishes the frame it was given and the
// hardware context becomes this thread's), the walk, the unlock.
void check(void* self) {
  const auto base = reinterpret_cast<std::uintptr_t>(self);
  void* const lock = g_lock(self);
  List lists[kMaxLists]{};
  std::size_t current = SIZE_MAX;
  for (std::uint32_t i = 0; i < g_layout.count; ++i) {
    const std::uintptr_t context = base + g_layout.contexts + std::uintptr_t{i} * g_layout.stride;
    if (reinterpret_cast<void*>(context) == lock) current = i;
    lists[i].header = reinterpret_cast<std::uintptr_t*>(context + g_layout.list);
    lists[i].arena_begin = context + g_layout.list + kListHeader;
    lists[i].arena_end = lists[i].arena_begin + kArena;
  }
  Report report{};
  bool walked = true;
  // Only when this thread was recording into a queued context: then Lock waited for the render thread's frame, and
  // nothing runs a list while the walk reads it.
  if (current != SIZE_MAX) walked = clean_guarded(lists, g_layout.count, g_test ? current : SIZE_MAX, &report);
  g_unlock(self, lock);
  const std::uint64_t number = g_checks.fetch_add(1) + 1;
  g_dropped.fetch_add(report.dropped);
  if (report.dropped || report.broken || !walked) record(report, walked, number);
}

bool hook_allow(void* self, bool allow, int service_thread) {
  if (!allow && self == g_object) check(self);
  return g_allow(self, allow, service_thread);
}

Status fail(std::string reason) {
  g_status.installed = false;
  g_status.reason = std::move(reason);
  return g_status;
}

// The other copy of this module (gmcl_ or gmsv_), when it is loaded and owns the slot.
Owner other_copy() {
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&hook_allow), &self);
  for (const wchar_t* name : {L"gmcl_nlengineguard_win64.dll", L"gmsv_nlengineguard_win64.dll"}) {
    const HMODULE module = GetModuleHandleW(name);
    if (!module || module == self) continue;
    const auto owner = reinterpret_cast<Owner>(GetProcAddress(module, "nl_engine_guard_queue_check_v1"));
    if (owner && owner(nullptr, nullptr, nullptr) >= 0) return owner;
  }
  return nullptr;
}

__declspec(noinline) void layout_into(const std::uint8_t* image, std::uintptr_t base, const std::uintptr_t* vtable,
                                      std::size_t slots, Layout& out) noexcept {
  out = find_layout(image, base, vtable, slots);
}

// find_layout on the loaded image, under SEH (its sections are read within their bounds; this is the backstop).
bool layout_guarded(const std::uint8_t* image, std::uintptr_t base, const std::uintptr_t* vtable, std::size_t slots,
                    Layout& out) noexcept {
  __try {
    layout_into(image, base, vtable, slots, out);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// How many of the vtable's slots point at code in some loaded image (another module's hook included): its length.
std::size_t vtable_slots(const std::uintptr_t* vtable) noexcept {
  std::size_t slots = 0;
  while (slots < kMaxSlots && readable(reinterpret_cast<std::uintptr_t>(vtable + slots), 8) &&
         (image_section(vtable[slots], 1) & IMAGE_SCN_MEM_EXECUTE))
    ++slots;
  return slots;
}

bool launched_with(const wchar_t* option) {
  const wchar_t* line = GetCommandLineW();
  if (!line) return false;
  const std::size_t length = std::wcslen(option);
  for (const wchar_t* at = std::wcsstr(line, option); at; at = std::wcsstr(at + 1, option)) {
    const bool starts = at == line || at[-1] == L' ' || at[-1] == L'\t';
    const bool ends = at[length] == 0 || at[length] == L' ' || at[length] == L'\t';
    if (starts && ends) return true;
  }
  return false;
}

Status install_locked() {
  if (g_status.installed || g_owner) return g_status;
  // Only where the Remix runtime is the game's d3d9.dll.
  const HMODULE d3d9 = GetModuleHandleW(L"d3d9.dll");
  if (!d3d9 || !GetProcAddress(d3d9, "remixapi_InitializeLibrary")) return fail("not a Remix start");
  if (const Owner owner = other_copy()) {
    g_owner = owner;
    int test = 0;
    owner(nullptr, nullptr, &test);
    g_status.installed = true;
    g_status.test = test != 0;
    g_status.reason = "installed by the other copy of this module";
    return g_status;
  }
  const HMODULE module = GetModuleHandleW(L"materialsystem.dll");
  if (!module) return fail("materialsystem.dll is not loaded");
  using CreateInterface = void* (*)(const char*, int*);
  const auto create = reinterpret_cast<CreateInterface>(GetProcAddress(module, "CreateInterface"));
  void* const object = create ? create("VMaterialSystem080", nullptr) : nullptr;
  if (!object) return fail("the material system (VMaterialSystem080) was not found");
  const auto* image = reinterpret_cast<const std::uint8_t*>(module);
  const auto base = reinterpret_cast<std::uintptr_t>(module);
  auto* const vtable = *reinterpret_cast<std::uintptr_t**>(object);
  MEMORY_BASIC_INFORMATION m{};
  if (!VirtualQuery(vtable, &m, sizeof(m)) || m.AllocationBase != module ||
      (image_section(reinterpret_cast<std::uintptr_t>(vtable), 8) & IMAGE_SCN_MEM_WRITE))
    return fail("the material system's vtable is not materialsystem.dll's");
  if (rtti_name(reinterpret_cast<std::uintptr_t>(vtable)) != ".?AVCMaterialSystem@@")
    return fail("the material system object is not a CMaterialSystem");
  Layout layout;
  if (!layout_guarded(image, base, vtable, vtable_slots(vtable), layout))
    return fail("materialsystem.dll's code could not be read");
  if (!layout.found()) return fail(layout.reason);
  // The queued contexts must be where ForceSingleThreaded's loop says: CMatQueuedRenderContext objects.
  for (std::uint32_t i = 0; i < layout.count; ++i) {
    const std::uintptr_t context =
        reinterpret_cast<std::uintptr_t>(object) + layout.contexts + std::uintptr_t{i} * layout.stride;
    if (!readable(context, 8) ||
        rtti_name(*reinterpret_cast<const std::uintptr_t*>(context)) != ".?AVCMatQueuedRenderContext@@")
      return fail("the queued contexts are not where ForceSingleThreaded's loop says");
  }
  // This module stays loaded for the process's lifetime: the slot points into it.
  HMODULE self = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                          reinterpret_cast<LPCWSTR>(&hook_allow), &self))
    return fail("this module could not be pinned");
  g_allow = reinterpret_cast<AllowThreading>(vtable[layout.allow_slot]);
  g_lock = reinterpret_cast<LockFn>(vtable[layout.lock_slot]);
  g_unlock = reinterpret_cast<UnlockFn>(vtable[layout.unlock_slot]);
  g_layout = layout;
  g_object = object;
  if (launched_with(L"-nl_queue_check_test")) {
    void* const block = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 64);
    g_test_object[0] = reinterpret_cast<std::uintptr_t>(block);
    g_test = block != nullptr;
  }
  DWORD old = 0;
  if (!VirtualProtect(&vtable[layout.allow_slot], sizeof(void*), PAGE_READWRITE, &old))
    return fail("materialsystem.dll's vtable could not be made writable");
  // One aligned pointer: the main thread, the only caller, calls either the engine's function or the wrapper.
  InterlockedExchangePointer(reinterpret_cast<void**>(&vtable[layout.allow_slot]), reinterpret_cast<void*>(&hook_allow));
  VirtualProtect(&vtable[layout.allow_slot], sizeof(void*), old, &old);
  g_owns.store(true);
  g_status.installed = true;
  g_status.test = g_test;
  g_status.reason = "installed";
  say("[NativeLoader] Queued render calls are checked before the game leaves threaded rendering (engine guard, ADR "
      "0247).\n");
  if (g_test) say("[NativeLoader] Queue check test: each check first queues one call whose object is gone.\n");
  return g_status;
}

Status fill(Status out) {
  if (g_owner) {
    std::uint64_t checks = 0, dropped = 0;
    int test = 0;
    g_owner(&checks, &dropped, &test);
    out.checks = checks;
    out.dropped = dropped;
    out.test = test != 0;
  } else {
    out.checks = g_checks.load();
    out.dropped = g_dropped.load();
    out.test = g_test;
  }
  return out;
}
}  // namespace

// What the other copy of this module reads from the copy that owns the slot. -1 when this copy did not install.
extern "C" __declspec(dllexport) int nl_engine_guard_queue_check_v1(std::uint64_t* checks, std::uint64_t* dropped,
                                                                     int* test) noexcept {
  if (!g_owns.load()) return -1;
  if (checks) *checks = g_checks.load();
  if (dropped) *dropped = g_dropped.load();
  if (test) *test = g_test ? 1 : 0;
  return 1;
}

Status install() noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_install);
    return fill(install_locked());
  } catch (...) {
    Status failed_status;
    failed_status.reason = "the queue check failed while installing";
    return failed_status;
  }
}

Status status() noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_install);
    return fill(g_status);
  } catch (...) {
    return {};
  }
}

}  // namespace nl::engine_guard::queue_check
