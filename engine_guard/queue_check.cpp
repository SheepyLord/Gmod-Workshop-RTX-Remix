// Queued render calls checked before the material system leaves threaded rendering (ADR 0247), watched while the
// game runs them (ADR 0254), and run before the RTX fixes' map-exit cleanup (ADR 0261). See queue_check.h.
#include "queue_check.h"

#include "guard.h"  // find(): byte patterns with wildcards; allocate_near()
#include "run_check.h"
#include "target_check.h"

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
    // The pattern starts with the loop's dispatch: mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h] (ADR 0254).
    out.dispatch_rva = out.call_queued_rva + run;
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
// The queued context's flush up to its Unlock: mov rcx,[rdi+ms]; mov rax,[rcx]; call [rax+Lock]; xor edx,edx;
// mov rcx,rdi; mov rbx,rax; call CallQueued; mov rcx,[rdi+ms]; mov rdx,rbx (then one of the two Unlock calls below).
const std::vector<int>& flush_body() {
  static const std::vector<int> pattern = {0x48, 0x8B, 0x8F, -1,   -1,   -1,   -1,   0x48, 0x8B, 0x01, 0xFF, 0x90, -1,
                                           -1,   -1,   -1,   0x33, 0xD2, 0x48, 0x8B, 0xCF, 0x48, 0x8B, 0xD8, 0xE8, -1,
                                           -1,   -1,   -1,   0x48, 0x8B, 0x8F, -1,   -1,   -1,   -1,   0x48, 0x8B, 0xD3};
  return pattern;
}
constexpr std::size_t kFlushLockLoad = 3, kFlushLock = 12, kFlushCall = 24, kFlushUnlockLoad = 32, kFlushTail = 39;

// The Unlock call right after it, nothing between: mov r8,[rcx]; call [r8+Unlock] or mov rax,[rcx]; call [rax+Unlock].
// The displacement's offset in the tail, or SIZE_MAX.
std::size_t unlock_call(const std::uint8_t* code, std::size_t size, std::size_t at) noexcept {
  static const std::uint8_t r8[] = {0x4C, 0x8B, 0x01, 0x41, 0xFF, 0x90};
  static const std::uint8_t rax[] = {0x48, 0x8B, 0x01, 0xFF, 0x90};
  if (at + sizeof(r8) + 4 <= size && std::memcmp(code + at, r8, sizeof(r8)) == 0) return at + sizeof(r8);
  if (at + sizeof(rax) + 4 <= size && std::memcmp(code + at, rax, sizeof(rax)) == 0) return at + sizeof(rax);
  return SIZE_MAX;
}

FlushSlot flush_failed(const char* why) {
  FlushSlot out;
  out.reason = why;
  return out;
}
}  // namespace

FlushSlot find_flush(const std::uint8_t* image, std::uintptr_t loaded_base, const std::uintptr_t* vtable,
                     std::size_t slots, const Layout& layout) noexcept {
  try {
    Sections s;
    if (!vtable || !read_sections(image, s)) return flush_failed("materialsystem.dll's headers could not be read");
    if (!layout.found() || layout.lock_slot == SIZE_MAX || layout.unlock_slot == SIZE_MAX || !layout.call_queued_rva)
      return flush_failed("the material system's layout was not found");
    std::size_t found = 0, slot = SIZE_MAX;
    for (std::size_t i = 0; i < std::min(slots, kMaxSlots); ++i) {
      std::size_t size = 0;
      std::uintptr_t rva = 0;
      const auto* code = function_code(image, loaded_base, s, vtable[i], size, rva);
      if (!code) continue;
      for (const std::size_t at : nl::engine_guard::find(code, size, flush_body(), 8)) {
        // Only in the slot's own function: the window can run on into the next function (no padding between
        // them in this game), where a look-alike behind an unrelated method must not count.
        if (at > kFlushStart) continue;
        const std::size_t unlock = unlock_call(code, size, at + kFlushTail);
        if (unlock == SIZE_MAX) continue;
        if (u32(code + at + kFlushLock) != layout.lock_slot * 8 || u32(code + unlock) != layout.unlock_slot * 8) continue;
        if (u32(code + at + kFlushLockLoad) != u32(code + at + kFlushUnlockLoad)) continue;
        if (call_target(code, rva, at + kFlushCall) != layout.call_queued_rva) continue;
        ++found;
        slot = i;
      }
    }
    if (found == 0) return flush_failed("the queued context's flush (Lock, CallQueued, Unlock) was not found in its vtable");
    if (found > 1) return flush_failed("the queued context's flush was found more than once in its vtable");
    FlushSlot out;
    out.slot = slot;
    return out;
  } catch (...) {
    return flush_failed("the queued context's code could not be read");
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

bool rtti_name_into(std::uintptr_t vtable, char* out, std::size_t size) noexcept {
  if (!out || size < 2) return false;
  return rtti_name_raw(vtable, out, size);
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

// The run check (ADR 0254). Set at install and never after, except g_run, which only the main thread touches inside
// AllowThreading(false).
bool g_run_ready = false;                  // the dispatch was found as the engine's and its slot is in reach
std::uint8_t* g_dispatch = nullptr;        // CallQueued's per-call dispatch in the loaded materialsystem.dll
std::vector<std::uint8_t> g_dispatch_patch;  // its bytes while a run is watched
run_check::Run g_run;
std::atomic<std::uint64_t> g_runs{0}, g_put_back{0}, g_skipped{0}, g_ended{0};

// ADR 0261. Set at install and never after, except g_target's class cache, which only the main thread touches inside
// a watched run.
using FlushFn = void (*)(void* context);
FlushFn g_flush_fn = nullptr;            // the queued context's flush (find_flush)
bool g_flush_ready = false;
std::string g_flush_reason = "not installed";
bool g_no_flush = false;                 // -nl_queue_check_no_flush
unsigned long g_main_thread = 0;         // the thread that installed (the game's main thread)
bool g_target_ready = false;
target_check::Judge g_target;
std::atomic<std::uint64_t> g_flushes{0}, g_gone{0};

// The test pair (-nl_queue_check_test with the run check ready): laid out as the engine's functors. The first writes
// over the second's element while the engine runs the list, with what the field's crashes found there (a pointer to
// a heap block whose first word is another heap block, whose call slot is 0); the run check must put it back.
struct TestCall {
  virtual int AddRef() { return 1; }
  virtual int Release() { return 1; }
  virtual ~TestCall() = default;
  virtual void Run() = 0;
};
std::uintptr_t g_test_victim_element = 0;
std::uintptr_t g_test_junk = 0;  // the heap block the first call writes into the second's element
std::atomic<int> g_test_writer_runs{0}, g_test_victim_runs{0};
struct TestWriter final : TestCall {
  void Run() override {
    ++g_test_writer_runs;
    if (!g_test_victim_element || !g_test_junk) return;
    auto* element = reinterpret_cast<std::uintptr_t*>(g_test_victim_element);
    element[0] = g_test_junk;
    element[1] = g_test_junk;
  }
};
struct TestVictim final : TestCall {
  void Run() override { ++g_test_victim_runs; }
};
TestWriter g_test_writer;
TestVictim g_test_victim;

std::mutex g_install;
Status g_status;  // under g_install
// The other copy's counts, when it installed first (the client and the server module are two images in one process;
// the slot points into only one of them).
using Owner = int (*)(std::uint64_t* checks, std::uint64_t* dropped, int* test);
Owner g_owner = nullptr;  // under g_install
using RunOwner = int (*)(std::uint64_t* runs, std::uint64_t* put_back, std::uint64_t* skipped, std::uint64_t* ended);
RunOwner g_run_owner = nullptr;  // under g_install
// ADR 0261: the other copy's flush and its counts.
using FlushOwner = int (*)(std::uint64_t* calls, char* why, std::size_t size);
FlushOwner g_flush_owner = nullptr;  // under g_install
using FlushStatusOwner = int (*)(std::uint64_t* flushes, std::uint64_t* gone, int* target, int* no_flush);
FlushStatusOwner g_flush_status_owner = nullptr;  // under g_install

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

// The run check's judge of an element it never saw: the plain one, no cache.
Why judge_memory_any(void*, std::uintptr_t object) { return judge_memory(object); }

// The walk under SEH: another thread may free memory a call's object pointed at between the check and the read.
// Returns false when it stopped on such a fault (the lists keep every unlink done before it, each complete). In a test
// session the stale test call goes to the end of the list being recorded first, and with the run check the test pair
// after it.
bool clean_guarded(const List* lists, std::size_t count, std::size_t test_list, bool test_pair,
                   Report* report) noexcept {
  Seen seen{};
  __try {
    if (test_list < count) {
      append(lists[test_list], reinterpret_cast<std::uintptr_t>(&g_test_object));
      if (test_pair && append(lists[test_list], reinterpret_cast<std::uintptr_t>(&g_test_writer)) &&
          append(lists[test_list], reinterpret_cast<std::uintptr_t>(&g_test_victim)))
        g_test_victim_element = lists[test_list].header[1];
    }
    *report = clean(lists, count, &judge_in_game, &seen);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// The run check's entry: CallQueued's rewritten dispatch calls it with the element (rcx = rbx). The x64 convention has
// the element in rcx as the engine's own call had the object there; every other register is the engine's again on
// return, as after any call.
__declspec(noinline) void run_step(std::uintptr_t* element) noexcept { g_run.step(element); }

// Rewrites `size` bytes of code (another thread never runs them meanwhile: the caller makes sure).
bool write_code(std::uint8_t* at, const std::uint8_t* bytes, std::size_t size) noexcept {
  DWORD old = 0;
  if (!VirtualProtect(at, size, PAGE_EXECUTE_READWRITE, &old)) return false;
  std::memcpy(at, bytes, size);
  DWORD ignored = 0;
  VirtualProtect(at, size, old, &ignored);
  FlushInstructionCache(GetCurrentProcess(), at, size);
  return true;
}

// The dispatch rewritten for one AllowThreading(false), only while it still holds the engine's bytes.
bool patch_dispatch() noexcept {
  if (!g_run_ready || g_dispatch_patch.size() != run_check::kDispatchSize) return false;
  if (std::memcmp(g_dispatch, run_check::kDispatch.data(), run_check::kDispatchSize) != 0) return false;
  return write_code(g_dispatch, g_dispatch_patch.data(), run_check::kDispatchSize);
}

// And put back, unless something else changed it meanwhile.
void unpatch_dispatch() noexcept {
  if (std::memcmp(g_dispatch, g_dispatch_patch.data(), run_check::kDispatchSize) == 0)
    write_code(g_dispatch, run_check::kDispatch.data(), run_check::kDispatchSize);
}

// The modules the log names, by base, captured where the loader lock may be taken (at install, and at each check
// before the material system's lock): the log is also written while the engine runs the lists with that lock held,
// where GetModuleFileNameW (the loader lock) could wait on a thread that waits on the material system (ADR 0261).
struct Known {
  std::uintptr_t base;
  const char* name;
};
Known g_known[8] = {};  // main thread only
std::size_t g_known_count = 0;
std::wstring g_log_path;  // captured with them (or given by use_for_test)

void capture_modules() noexcept {
  static const wchar_t* const wide[] = {L"materialsystem.dll", L"studiorender.dll", L"engine.dll", L"client.dll",
                                        L"shaderapidx9.dll"};
  static const char* const names[] = {"materialsystem.dll", "studiorender.dll", "engine.dll", "client.dll",
                                      "shaderapidx9.dll"};
  std::size_t count = 0;
  for (std::size_t i = 0; i < 5; ++i)
    if (const HMODULE module = GetModuleHandleW(wide[i]))
      g_known[count++] = {reinterpret_cast<std::uintptr_t>(module), names[i]};
  HMODULE self = nullptr;
  if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         reinterpret_cast<LPCWSTR>(&capture_modules), &self))
    g_known[count++] = {reinterpret_cast<std::uintptr_t>(self), "nlengineguard"};
  g_known_count = count;
  if (!g_log_path.empty()) return;
  try {
    wchar_t exe[MAX_PATH]{};
    if (!GetModuleFileNameW(nullptr, exe, MAX_PATH)) return;
    std::wstring root(exe);
    for (int i = 0; i < 3; ++i) {  // ...\bin\win64\gmod.exe -> the game root
      const auto slash = root.find_last_of(L"\\/");
      if (slash == std::wstring::npos) return;
      root.erase(slash);
    }
    g_log_path = root + L"\\garrysmod\\data\\native-loader\\render-queue-check.log";
  } catch (...) {
  }
}

// The module an address lies in, from the captured bases; else the image's base address ("" outside any image).
std::string module_name(std::uintptr_t address) {
  MEMORY_BASIC_INFORMATION m{};
  if (!VirtualQuery(reinterpret_cast<const void*>(address), &m, sizeof(m)) || m.Type != MEM_IMAGE) return {};
  const auto base = reinterpret_cast<std::uintptr_t>(m.AllocationBase);
  for (std::size_t i = 0; i < g_known_count; ++i)
    if (g_known[i].base == base) return g_known[i].name;
  char text[48];
  std::snprintf(text, sizeof(text), "the image at 0x%llx", static_cast<unsigned long long>(base));
  return text;
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

// The log's path, captured by capture_modules (no loader lock here); its folder is made when missing.
std::wstring log_path() {
  if (g_log_path.empty()) return {};
  const auto slash = g_log_path.find_last_of(L"\\/");
  if (slash != std::wstring::npos) CreateDirectoryW(g_log_path.substr(0, slash).c_str(), nullptr);
  return g_log_path;
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

// What ran the lists: the engine leaving threaded rendering (AllowThreading(false)), or the queued context's flush that
// Lua asked for before the RTX fixes' cleanup (ADR 0261). Checks and flushes are numbered apart.
enum class Kind { leave, flush };
const char* label(Kind kind) { return kind == Kind::leave ? "check" : "flush"; }

// Says what a check dropped (or could not walk): the console once per check, the log with the details.
void record(const Report& report, bool walked, Kind kind, std::uint64_t number) {
  try {
    std::uint32_t tests = 0;
    for (std::uint32_t i = 0; i < report.recorded; ++i)
      if (report.drops[i].why == Why::test) ++tests;
    const std::uint32_t real = report.dropped - std::min(tests, report.dropped);
    std::string text = utc_now() + " " + label(kind) + " " + std::to_string(number) +
                       (kind == Kind::leave ? " before the game left threaded rendering:"
                                            : " before the queued context's flush:");
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
           " queued render call(s) whose object was already gone, before the game ran them (engine guard, ADR 0247). "
           "Details: garrysmod/data/native-loader/render-queue-check.log\n")
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

// A call's place in the run's records: "list 1, call 660 of 1234 (element +0x2938)".
std::string place(const run_check::Record& r) {
  if (r.list == UINT32_MAX) return "an element outside every list's arena (" + hex(r.element) + ")";
  std::string text = "list " + std::to_string(r.list) + ", ";
  text += r.position == UINT32_MAX ? std::string("an element the check never saw")
                                   : "call " + std::to_string(r.position + 1) + " of " + std::to_string(r.length);
  return text + " (element +" + hex(r.offset) + ")";
}

std::string words_text(const std::uintptr_t* words, std::uint32_t count) {
  std::string text;
  for (std::uint32_t i = 0; i < count; ++i) text += (i ? " " : "") + hex(words[i]);
  return text.empty() ? std::string("none read") : text;
}

// One event of a watched run, as the log says it.
std::string record_text(const run_check::Record& r) {
  std::string text = "  " + place(r) + ": " + run_check::describe(r.event) +
                     (g_test_victim_element && r.element == g_test_victim_element ? " (the test call)" : "") + "\n";
  if (r.position != UINT32_MAX) {
    text += "    when checked: next " + hex(r.was[0]) + ", object " + hex(r.was[1]);
    if (r.words) text += " (" + describe_table(r.words_was[0]) + ")";
    text += "\n";
  }
  if (r.list != UINT32_MAX && r.event != run_check::Event::target_gone) {
    text += "    as the run found it: next " + hex(r.now[0]) + ", object " + hex(r.now[1]);
    if (r.now[1] && r.now[1] != r.was[1]) text += " (in " + describe_memory(r.now[1]) + ")";
    text += "\n";
  }
  if (r.event == run_check::Event::object_changed) {
    text += "    the object's first words when checked: " + words_text(r.words_was, r.words) +
            "; now: " + words_text(r.words_now, r.words) + "\n";
    if (r.before_read)
      text += "    the 16 bytes before the element when checked: " + words_text(r.before_was, 2) +
              "; now: " + words_text(r.before_now, 2) + "\n";
  }
  if (r.event == run_check::Event::target_gone) {
    const target_check::Finding& f = r.target;
    text += "    material variable " + hex(f.variable) + " (the functor's word at +" + hex(f.offset) + ", " +
            describe_table(f.functor_table) + "): " + target_check::describe(f.verdict) + "\n";
    text += "    found: the variable's first word " + hex(f.variable_table) + " (CMaterialVar's " +
            hex(g_target.variable_table) + "), its material " + hex(f.owner) + ", whose first word " +
            hex(f.owner_table) + " (CMaterial's " + hex(g_target.material_table) + "), parameters " +
            hex(f.parameters) + ", " + std::to_string(f.count) + " of them\n";
  }
  if (r.recent_count) {
    text += "    run just before it, newest first:";
    for (std::uint32_t c = 0; c < r.recent_count; ++c) {
      const run_check::Recent& recent = r.recent[c];
      text += (c ? "; " : " ") + std::string("list ") + std::to_string(recent.list) + " " +
              (recent.position == UINT32_MAX ? std::string("unseen call")
                                             : "call " + std::to_string(recent.position + 1)) +
              " " + describe_table(recent.table);
    }
    text += "\n";
  }
  return text;
}

// The watched run's log (main thread only): a header line at its first event, each event when it happens (a run that
// crashes keeps what it wrote), a summary line at its end (record_run).
// At most kLogEvents events are written per run, so a run cannot rotate its own header out of the log (the rest are
// counted in its summary line).
constexpr std::uint64_t kLogEvents = 32;
struct RunLog {
  Kind kind = Kind::leave;
  std::uint64_t number = 0;
  std::uint64_t written = 0;  // events written
  std::uint64_t told = 0;     // events the run check told
};
RunLog g_run_log;

void notify_event(void*, const run_check::Record& r) {
  ++g_run_log.told;
  if (g_run_log.written >= kLogEvents) return;
  try {
    std::string text;
    if (!g_run_log.written)
      text = utc_now() + " " + label(g_run_log.kind) + " " + std::to_string(g_run_log.number) +
             " while the game ran the queued calls (each event as it happened):\n";
    text += record_text(r);
    ++g_run_log.written;
    write_log(text);
  } catch (...) {
  }
}

// The target judge the run check asks right before each call (ADR 0261).
target_check::Verdict judge_target(void*, std::uintptr_t object, target_check::Finding& finding) {
  return target_check::judge(g_target, object, finding);
}

run_check::Hooks run_hooks() {
  run_check::Hooks hooks;
  if (g_target_ready) hooks.target = &judge_target;
  hooks.notify = &notify_event;
  return hooks;
}

// Says how a watched run ended: the log's summary line when it wrote events, the console once. The test pair's own
// event is told apart; `victim_ran`: its second call ran in this run.
void record_run(Kind kind, std::uint64_t number, bool victim_ran) {
  try {
    const run_check::Totals& totals = g_run.totals();
    std::uint64_t test_events = 0;
    bool test_put_back = false;
    for (std::uint32_t i = 0; i < g_run.recorded(); ++i) {
      const run_check::Record& r = g_run.records()[i];
      if (g_test_victim_element && r.element == g_test_victim_element) {
        ++test_events;
        if (r.event == run_check::Event::put_back) test_put_back = true;
      }
    }
    const std::uint64_t events = totals.put_back + totals.skipped + totals.ended;
    if (g_test && test_put_back && victim_ran)
      say("[NativeLoader] Queue check test: the run check put back the test call written over during the run (engine "
          "guard, ADR 0254).\n");
    if (!events) return;
    std::string text = utc_now() + " " + label(kind) + " " + std::to_string(number) + " run ended: " +
                       std::to_string(totals.run) + " calls run, " + std::to_string(totals.put_back) + " put back, " +
                       std::to_string(totals.skipped) + " skipped (" + std::to_string(totals.gone) +
                       " on a material variable that was gone), " + std::to_string(totals.ended) +
                       " lists ended early";
    if (totals.strangers) text += ", " + std::to_string(totals.strangers) + " calls it had not seen";
    const std::uint64_t unwritten = std::max(events, g_run_log.told) - g_run_log.written;
    if (unwritten) text += "; " + std::to_string(unwritten) + " events not written";
    write_log(text + "\n");
    const std::uint64_t other = events - std::min(events, totals.gone);
    if (other > test_events)
      say(("[NativeLoader] Put back " + std::to_string(totals.put_back) + " and skipped " +
           std::to_string(totals.skipped - std::min(totals.skipped, totals.gone)) +
           " queued render call(s) written over while the game ran them (engine guard, ADR 0254). Details: "
           "garrysmod/data/native-loader/render-queue-check.log\n")
              .c_str());
    if (totals.gone)
      say(("[NativeLoader] Skipped " + std::to_string(totals.gone) +
           " queued render call(s) on a material variable that was already gone (engine guard, ADR 0261). Details: "
           "garrysmod/data/native-loader/render-queue-check.log\n")
              .c_str());
  } catch (...) {
  }
}

// The calls a list holds now (0 when it cannot be walked), under SEH.
std::uint32_t count_guarded(const List& list) noexcept {
  std::uintptr_t length = 0;
  __try {
    if (!walkable(list, length)) length = 0;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    length = 0;
  }
  return static_cast<std::uint32_t>(std::min<std::uintptr_t>(length, UINT32_MAX));
}

constexpr std::uint64_t kLogFlushes = 64;  // flushes per process whose routine line the log gets

// What the check found before a run.
struct Prepared {
  bool watch = false;           // the run is to be watched (the run check kept the lists)
  std::size_t current = SIZE_MAX;  // the queued context this thread records into, or SIZE_MAX
  void* context = nullptr;      // that context
  List list{};                  // its call list
  std::uint32_t queued = 0;     // its calls after the walk
  std::uint64_t number = 0;     // the check's or the flush's number
};

// Before the engine runs the lists: the lock (the render thread finishes the frame it was given and the hardware
// context becomes this thread's), the walk, with the run check ready what every element looks like now, the unlock.
std::atomic<std::uint64_t> g_flush_calls{0};  // flushes asked for (each its own number in the log)
Prepared check(void* self, Kind kind) {
  Prepared out;
  const auto base = reinterpret_cast<std::uintptr_t>(self);
  capture_modules();  // before the material system's lock: it may take the loader lock
  void* const lock = g_lock(self);
  List lists[kMaxLists]{};
  for (std::uint32_t i = 0; i < g_layout.count; ++i) {
    const std::uintptr_t context = base + g_layout.contexts + std::uintptr_t{i} * g_layout.stride;
    if (reinterpret_cast<void*>(context) == lock) out.current = i;
    lists[i].header = reinterpret_cast<std::uintptr_t*>(context + g_layout.list);
    lists[i].arena_begin = context + g_layout.list + kListHeader;
    lists[i].arena_end = lists[i].arena_begin + kArena;
  }
  Report report{};
  bool walked = true;
  // Only when this thread was recording into a queued context: then Lock waited for the render thread's frame, and
  // nothing runs a list while the walk reads it.
  if (out.current != SIZE_MAX) {
    out.context = lock;
    out.list = lists[out.current];
    walked = clean_guarded(lists, g_layout.count, g_test ? out.current : SIZE_MAX, g_test && g_run_ready, &report);
    out.queued = count_guarded(out.list);
    if (walked && g_run_ready) {
      g_run.begin(lists, g_layout.count, &judge_memory_any, nullptr, GetCurrentThreadId(), &run_check::call_object,
                  run_hooks());
      out.watch = g_run.see();
    }
  }
  g_unlock(self, lock);
  out.number = kind == Kind::leave ? g_checks.fetch_add(1) + 1 : g_flush_calls.fetch_add(1) + 1;
  g_dropped.fetch_add(report.dropped);
  if (report.dropped || report.broken || !walked) record(report, walked, kind, out.number);
  return out;
}

// The engine's function (AllowThreading, or the queued context's flush), its runs of the lists watched when the check
// kept them: the render thread is idle until the engine's function returns (Lock waited for its frame, and only this
// thread hands it another). True when the run was watched.
bool g_watching = false;  // main thread only
template <class Engine>
bool run_watched(const Prepared& prepared, Kind kind, Engine&& engine) {
  if (!prepared.watch || !patch_dispatch()) {
    g_run.end();
    engine();
    return false;
  }
  g_run_log = RunLog{kind, prepared.number, 0, 0};
  const int victim_runs = g_test_victim_runs.load();
  g_watching = true;
  engine();
  g_watching = false;
  unpatch_dispatch();
  g_run.end();
  g_runs.fetch_add(1);
  g_put_back.fetch_add(g_run.totals().put_back);
  g_skipped.fetch_add(g_run.totals().skipped);
  g_ended.fetch_add(g_run.totals().ended);
  g_gone.fetch_add(g_run.totals().gone);
  record_run(kind, prepared.number, g_test_victim_runs.load() > victim_runs);
  return true;
}

// AllowThreading(false): the check, then the engine's own function. A call of it from inside a watched run (never
// seen) gets the engine's function alone, so the run being watched keeps what its check saw.
bool hook_allow(void* self, bool allow, int service_thread) {
  if (allow || self != g_object || g_watching) return g_allow(self, allow, service_thread);
  const Prepared prepared = check(self, Kind::leave);
  bool result = false;
  run_watched(prepared, Kind::leave, [&] { result = g_allow(self, allow, service_thread); });
  return result;
}

// The flush (ADR 0261) in the copy that installed: the same check and watched run as AllowThreading(false), with the
// queued context's own flush (Lock; CallQueued(this, 0); Unlock) as the engine's function.
FlushResult flush_here() {
  FlushResult out;
  if (!g_flush_ready) {
    out.why = "the queue flush is off: " + g_flush_reason;
    return out;
  }
  if (GetCurrentThreadId() != g_main_thread) {
    out.why = "not called on the game's main thread";
    return out;
  }
  if (g_watching) {
    out.why = "called while the queued calls run";
    return out;
  }
  if (g_no_flush) {
    out.ok = true;
    out.why = "the test option -nl_queue_check_no_flush: nothing was run";
    return out;
  }
  const Prepared prepared = check(g_object, Kind::flush);
  if (prepared.current == SIZE_MAX) {
    g_run.end();
    out.ok = true;
    out.why = "nothing queued: this thread does not record into a queued context";
    return out;
  }
  g_flushes.fetch_add(1);
  void* const context = prepared.context;
  const bool watched = run_watched(prepared, Kind::flush, [context] { g_flush_fn(context); });
  const run_check::Totals totals = watched ? g_run.totals() : run_check::Totals{};
  out.calls = watched ? totals.run : prepared.queued;
  // The context's flush ran what was queued before it. Inside a render block it queues one call of its own after
  // itself (the matching end of the block), so the list need not be empty now: that is said, not refused.
  out.ok = true;
  out.why = "ran " + std::to_string(out.calls) + " queued render call(s) through the queued context's flush";
  if (totals.skipped)
    out.why += "; skipped " + std::to_string(totals.skipped) + " (" + std::to_string(totals.gone) +
               " on a material variable that was gone)";
  const std::uint32_t again = count_guarded(prepared.list);
  if (again) out.why += "; " + std::to_string(again) + " call(s) queued again by the flush";
  // The routine line for the first kLogFlushes flushes of a process only: any client Lua can call the flush every
  // frame, and the log must not rotate crash evidence away. Events and summaries are always written.
  if (prepared.number <= kLogFlushes)
    write_log(utc_now() + " flush " + std::to_string(prepared.number) + ": list " + std::to_string(prepared.current) +
              " held " + std::to_string(prepared.queued) + " calls; " + (watched ? "watched; " : "not watched; ") +
              out.why + "\n");
  return out;
}

Status fail(std::string reason) {
  g_status.installed = false;
  g_status.reason = std::move(reason);
  if (g_status.flush_reason.empty()) g_status.flush_reason = "the queue check is not installed";
  if (g_status.target_reason.empty()) g_status.target_reason = "the queue check is not installed";
  return g_status;
}

// The other copy of this module (gmcl_ or gmsv_), when it is loaded and owns the slot; its run check's counts too, when
// it has them (a copy built before ADR 0254 has not).
Owner other_copy(RunOwner& run_owner) {
  run_owner = nullptr;
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&hook_allow), &self);
  for (const wchar_t* name : {L"gmcl_nlengineguard_win64.dll", L"gmsv_nlengineguard_win64.dll"}) {
    const HMODULE module = GetModuleHandleW(name);
    if (!module || module == self) continue;
    const auto owner = reinterpret_cast<Owner>(GetProcAddress(module, "nl_engine_guard_queue_check_v1"));
    if (owner && owner(nullptr, nullptr, nullptr) >= 0) {
      run_owner = reinterpret_cast<RunOwner>(GetProcAddress(module, "nl_engine_guard_run_check_v1"));
      // ADR 0261: its flush and its counts, when it has them.
      g_flush_owner = reinterpret_cast<FlushOwner>(GetProcAddress(module, "nl_engine_guard_queue_flush_v1"));
      g_flush_status_owner =
          reinterpret_cast<FlushStatusOwner>(GetProcAddress(module, "nl_engine_guard_queue_flush_status_v1"));
      return owner;
    }
  }
  return nullptr;
}

// The run check (ADR 0254): CallQueued's dispatch must hold the engine's bytes, and a slot holding run_step's address
// must lie within a rel32 of it. Otherwise only the walk before the run stays (ADR 0247).
void prepare_run_check(const std::uint8_t* image, const Layout& layout) {
  g_status.run_check = false;
  if (!layout.dispatch_rva) {
    g_status.run_reason = "CallQueued's dispatch was not found";
    return;
  }
  auto* const dispatch = const_cast<std::uint8_t*>(image) + layout.dispatch_rva;
  if (std::memcmp(dispatch, run_check::kDispatch.data(), run_check::kDispatchSize) != 0) {
    g_status.run_reason = "CallQueued's dispatch is not the engine's (another module changed it)";
    return;
  }
  void* const page = allocate_near(reinterpret_cast<std::uintptr_t>(dispatch));
  if (!page) {
    g_status.run_reason = "no memory within reach of materialsystem.dll for the run check";
    return;
  }
  void (*const entry)(std::uintptr_t*) noexcept = &run_step;
  std::memcpy(page, &entry, sizeof(entry));
  DWORD old = 0;
  VirtualProtect(page, 4096, PAGE_READONLY, &old);
  auto bytes = run_check::dispatch_patch(reinterpret_cast<std::uintptr_t>(dispatch), reinterpret_cast<std::uintptr_t>(page));
  if (bytes.size() != run_check::kDispatchSize) {
    VirtualFree(page, 0, MEM_RELEASE);
    g_status.run_reason = "the run check's slot is out of a call's reach";
    return;
  }
  g_dispatch = dispatch;
  g_dispatch_patch = std::move(bytes);
  g_run_ready = true;
  g_status.run_check = true;
  g_status.run_reason = "installed";
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

__declspec(noinline) void flush_into(const std::uint8_t* image, std::uintptr_t base, const std::uintptr_t* vtable,
                                     std::size_t slots, const Layout& layout, FlushSlot& out) noexcept {
  out = find_flush(image, base, vtable, slots, layout);
}

// find_flush on the loaded image, under SEH.
bool flush_guarded(const std::uint8_t* image, std::uintptr_t base, const std::uintptr_t* vtable, std::size_t slots,
                   const Layout& layout, FlushSlot& out) noexcept {
  __try {
    flush_into(image, base, vtable, slots, layout, out);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

__declspec(noinline) void target_into(const std::uint8_t* image, std::uintptr_t base,
                                      target_check::Layout& out) noexcept {
  out = target_check::find_layout(image, base);
}

// target_check::find_layout on the loaded image, under SEH.
bool target_guarded(const std::uint8_t* image, std::uintptr_t base, target_check::Layout& out) noexcept {
  __try {
    target_into(image, base, out);
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

// The queued context's flush (ADR 0261): found in the live context's vtable (the class the install checked by RTTI),
// which must be materialsystem.dll's read-only data. Otherwise the flush is off and says why.
void prepare_flush(const std::uint8_t* image, std::uintptr_t base, const Layout& layout, void* object) {
  g_status.queue_flush = false;
  const HMODULE module = reinterpret_cast<HMODULE>(const_cast<std::uint8_t*>(image));
  const std::uintptr_t context = reinterpret_cast<std::uintptr_t>(object) + layout.contexts;
  const auto* const vtable = *reinterpret_cast<const std::uintptr_t* const*>(context);
  MEMORY_BASIC_INFORMATION m{};
  if (!VirtualQuery(vtable, &m, sizeof(m)) || m.AllocationBase != module ||
      (image_section(reinterpret_cast<std::uintptr_t>(vtable), 8) & IMAGE_SCN_MEM_WRITE)) {
    g_flush_reason = "the queued context's vtable is not materialsystem.dll's";
  } else {
    FlushSlot slot;
    if (!flush_guarded(image, base, vtable, vtable_slots(vtable), layout, slot))
      g_flush_reason = "the queued context's code could not be read";
    else if (!slot.found())
      g_flush_reason = slot.reason;
    else {
      g_flush_fn = reinterpret_cast<FlushFn>(vtable[slot.slot]);
      g_flush_ready = true;
      g_flush_reason = "installed";
    }
  }
  g_status.queue_flush = g_flush_ready;
  g_status.flush_reason = g_flush_reason;
}

// The target check (ADR 0261) lives in the run check's step: without the run check it is off.
void prepare_target(const std::uint8_t* image, std::uintptr_t base) {
  g_status.target_check = false;
  if (!g_run_ready) {
    g_status.target_reason = "the run check is off";
    return;
  }
  target_check::Layout layout;
  if (!target_guarded(image, base, layout)) {
    g_status.target_reason = "materialsystem.dll's code could not be read";
    return;
  }
  if (!layout.found()) {
    g_status.target_reason = layout.reason;
    return;
  }
  g_target.use(layout);
  g_target_ready = true;
  g_status.target_check = true;
  g_status.target_reason = "installed";
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
  RunOwner run_owner = nullptr;
  if (const Owner owner = other_copy(run_owner)) {
    g_owner = owner;
    g_run_owner = run_owner;
    int test = 0;
    owner(nullptr, nullptr, &test);
    g_status.installed = true;
    g_status.test = test != 0;
    g_status.reason = "installed by the other copy of this module";
    g_status.run_check = run_owner && run_owner(nullptr, nullptr, nullptr, nullptr) > 0;
    g_status.run_reason = g_status.run_check ? "installed by the other copy of this module"
                                             : "not in the other copy of this module";
    // ADR 0261: the flush is forwarded to the copy that installed; its target check is its own.
    int target = 0, no_flush = 0;
    const int flush = g_flush_status_owner ? g_flush_status_owner(nullptr, nullptr, &target, &no_flush) : -1;
    g_status.queue_flush = g_flush_owner && flush > 0;
    g_status.flush_reason = g_status.queue_flush ? "installed by the other copy of this module"
                                                 : "not in the other copy of this module";
    g_status.target_check = flush >= 0 && target != 0;
    g_status.target_reason = g_status.target_check ? "installed by the other copy of this module"
                                                   : "not in the other copy of this module";
    g_status.no_flush = no_flush != 0;
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
  g_main_thread = GetCurrentThreadId();
  capture_modules();
  prepare_run_check(image, layout);
  prepare_flush(image, base, layout, object);
  prepare_target(image, base);
  g_no_flush = launched_with(L"-nl_queue_check_no_flush");
  g_status.no_flush = g_no_flush;
  if (launched_with(L"-nl_queue_check_test")) {
    void* const block = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 64);
    g_test_object[0] = reinterpret_cast<std::uintptr_t>(block);
    g_test = block != nullptr;
    // What the test pair's first call writes into the second's element: a heap block whose first word is another,
    // zeroed one, so a call through it would go to address 0, as in the field's crash of 2026-11-19.
    auto* const junk = static_cast<std::uintptr_t*>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 64));
    void* const inner = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 64);
    if (junk && inner) {
      junk[0] = reinterpret_cast<std::uintptr_t>(inner);
      g_test_junk = reinterpret_cast<std::uintptr_t>(junk);
    }
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
  if (g_run_ready)
    say("[NativeLoader] Queued render calls are also checked while the game runs them (engine guard, ADR 0254).\n");
  else
    say(("[NativeLoader] The run check is off: " + g_status.run_reason + " (engine guard, ADR 0254).\n").c_str());
  if (g_test) say("[NativeLoader] Queue check test: each check first queues one call whose object is gone.\n");
  if (g_test && g_run_ready && g_test_junk)
    say("[NativeLoader] Queue check test: each check also queues a pair of calls, the first writing over the second's "
        "element.\n");
  if (g_flush_ready)
    say("[NativeLoader] Queued render calls can be run before the RTX fixes' map-exit cleanup (engine guard, ADR "
        "0261).\n");
  else
    say(("[NativeLoader] The queue flush is off: " + g_flush_reason + " (engine guard, ADR 0261).\n").c_str());
  if (g_target_ready)
    say("[NativeLoader] Queued calls on a material variable that is gone are skipped (engine guard, ADR 0261).\n");
  else
    say(("[NativeLoader] The target check is off: " + g_status.target_reason + " (engine guard, ADR 0261).\n").c_str());
  if (g_no_flush)
    say("[NativeLoader] Queue flush test: the flush runs nothing and says it succeeded (-nl_queue_check_no_flush).\n");
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
    if (g_run_owner) g_run_owner(&out.runs, &out.put_back, &out.skipped, &out.ended);
    if (g_flush_status_owner) g_flush_status_owner(&out.flushes, &out.gone, nullptr, nullptr);
  } else {
    out.checks = g_checks.load();
    out.dropped = g_dropped.load();
    out.test = g_test;
    out.runs = g_runs.load();
    out.put_back = g_put_back.load();
    out.skipped = g_skipped.load();
    out.ended = g_ended.load();
    out.flushes = g_flushes.load();
    out.gone = g_gone.load();
  }
  return out;
}

// The flush in the copy that installed, never throwing.
FlushResult flush_safe() noexcept {
  try {
    return flush_here();
  } catch (...) {
    FlushResult out;
    out.why = "the queue flush failed";
    return out;
  }
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

// And its run check's counts (ADR 0254): -1 when this copy did not install, 0 when its run check is off, 1 when on.
extern "C" __declspec(dllexport) int nl_engine_guard_run_check_v1(std::uint64_t* runs, std::uint64_t* put_back,
                                                                   std::uint64_t* skipped,
                                                                   std::uint64_t* ended) noexcept {
  if (!g_owns.load()) return -1;
  if (runs) *runs = g_runs.load();
  if (put_back) *put_back = g_put_back.load();
  if (skipped) *skipped = g_skipped.load();
  if (ended) *ended = g_ended.load();
  return g_run_ready ? 1 : 0;
}

// ADR 0261: the flush, run in the copy that installed for the other copy. -1 when this copy did not install, 1 when
// what this thread had queued has run, 0 when it could not make sure; `why` gets a NUL-terminated reason.
extern "C" __declspec(dllexport) int nl_engine_guard_queue_flush_v1(std::uint64_t* calls, char* why,
                                                                     std::size_t size) noexcept {
  if (!g_owns.load()) return -1;
  const FlushResult result = flush_safe();
  if (calls) *calls = result.calls;
  if (why && size) {
    const std::size_t n = std::min(size - 1, result.why.size());
    std::memcpy(why, result.why.data(), n);
    why[n] = 0;
  }
  return result.ok ? 1 : 0;
}

// And its counts: -1 when this copy did not install, 0 when its flush is off, 1 when on.
extern "C" __declspec(dllexport) int nl_engine_guard_queue_flush_status_v1(std::uint64_t* flushes,
                                                                            std::uint64_t* gone, int* target,
                                                                            int* no_flush) noexcept {
  if (!g_owns.load()) return -1;
  if (flushes) *flushes = g_flushes.load();
  if (gone) *gone = g_gone.load();
  if (target) *target = g_target_ready ? 1 : 0;
  if (no_flush) *no_flush = g_no_flush ? 1 : 0;
  return g_flush_ready ? 1 : 0;
}

FlushResult flush() noexcept {
  try {
    FlushOwner owner = nullptr;
    bool forwarded = false;
    std::string reason;
    {
      std::lock_guard<std::mutex> lock(g_install);
      forwarded = g_owner != nullptr;
      owner = g_flush_owner;
      reason = g_status.reason;
    }
    if (forwarded) {
      FlushResult out;
      if (!owner) {
        out.why = "the queue flush is not in the other copy of this module";
        return out;
      }
      char why[256] = {};
      const int result = owner(&out.calls, why, sizeof(why));
      out.ok = result == 1;
      out.why = result < 0 ? std::string("the other copy of this module did not install the queue check") : why;
      return out;
    }
    if (!g_owns.load()) {
      FlushResult out;
      out.why = "the queue check is not installed: " + (reason.empty() ? std::string("not yet") : reason);
      return out;
    }
    return flush_safe();
  } catch (...) {
    FlushResult out;
    out.why = "the queue flush failed";
    return out;
  }
}

void use_for_test(const StandIns& stand_ins) noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_install);
    g_layout = stand_ins.layout;
    g_object = stand_ins.system;
    g_lock = stand_ins.lock;
    g_unlock = stand_ins.unlock;
    g_flush_fn = stand_ins.flush;
    g_flush_ready = stand_ins.flush != nullptr;
    g_flush_reason = g_flush_ready ? "installed" : "no flush given";
    g_no_flush = stand_ins.no_flush;
    g_main_thread = GetCurrentThreadId();
    g_log_path = stand_ins.log;
    g_owns.store(true);
  } catch (...) {
  }
}

void reset_for_test() noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_install);
    g_owns.store(false);
    g_flush_ready = false;
    g_flush_fn = nullptr;
    g_flush_reason = "not installed";
    g_no_flush = false;
    g_object = nullptr;
    g_lock = nullptr;
    g_unlock = nullptr;
    g_layout = Layout{};
    g_main_thread = 0;
    g_log_path.clear();
  } catch (...) {
  }
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
