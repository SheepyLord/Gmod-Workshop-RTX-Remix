// The engine guard's detour of materialsystem.dll's $fallbackmaterial read (ADR 0130).
#include "guard.h"
#include <windows.h>
#include <atomic>
#include <cstring>
#include <mutex>

namespace nl::engine_guard {
namespace {
const std::vector<int> kPattern = {
    0x4C, 0x8D, 0x05, -1, -1, -1, -1,    // lea r8,[rip+""]
    0x49, 0x8B, 0xCD,                    // mov rcx,r13 (the key values)
    0x48, 0x8D, 0x15, -1, -1, -1, -1,    // lea rdx,[rip+"$fallbackmaterial"]
    0xE8, -1, -1, -1, -1,                // call KeyValues::GetString
    0x8B, 0x7C, 0x24, 0x40,              // mov edi,[rsp+40h]
    0x44, 0x8B, 0x64, 0x24, 0x44,        // mov r12d,[rsp+44h]
    0x80, 0x38, 0x00,                    // cmp byte ptr [rax],0
    0x0F, 0x84,                          // je <the loop's start>
};
// The loop's warnings: mov rax,[r14]; mov rcx,r14; call [rax] (r14's GetName), at rva 0xfbb7 and 0xfc0c.
const std::vector<int> kGetNameCall = {0x49, 0x8B, 0x06, 0x49, 0x8B, 0xCE, 0xFF, 0x10};
constexpr char kEmpty[] = "";

std::mutex g_install;
Status g_status;                       // installed, reason, site (under g_install)
std::atomic<unsigned> g_cut{0};
std::atomic<unsigned> g_messages{0};
std::mutex g_names;
std::string g_last_material, g_last_fallback;
GetString g_real = nullptr;            // KeyValues::GetString, set before the call site changes
// The other copy's counts, when its stub was there first (the client and the server module are two
// images in one process; the call site reaches only one of them).
using OwnerCounts = unsigned (*)(char* material, unsigned material_size, char* fallback, unsigned fallback_size);
OwnerCounts g_owner_counts = nullptr;  // under g_install

using Msg = void (*)(const char*, ...);
Msg tier0_msg() {
  static const Msg fn = [] {
    const HMODULE tier0 = GetModuleHandleW(L"tier0.dll");
    return tier0 ? reinterpret_cast<Msg>(GetProcAddress(tier0, "Msg")) : nullptr;
  }();
  return fn;
}

// The material's name from its first virtual function (IMaterial::GetName), as the loop's own warnings
// read it. No C++ objects here: a fault in a foreign object costs only the name.
const char* material_name(void* material) noexcept {
  __try {
    auto** vtable = *reinterpret_cast<void***>(material);
    const auto get_name = reinterpret_cast<const char* (*)(void*)>(vtable[0]);
    return get_name(material);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return nullptr;
  }
}

void note(const char* own, const char* fallback, Verdict verdict) {
  g_cut.fetch_add(1, std::memory_order_relaxed);
  {
    std::lock_guard<std::mutex> lock(g_names);
    g_last_material = own ? own : "";
    g_last_fallback = fallback ? fallback : "";
  }
  if (g_messages.fetch_add(1, std::memory_order_relaxed) >= 16) return;
  if (const Msg msg = tier0_msg()) {
    msg("[NativeLoader] Material %s: its fallback material %s %s; the material is used without it, so the "
        "game does not stop loading (engine guard, ADR 0130).\n",
        own ? own : "?", fallback ? fallback : "?",
        verdict == Verdict::self ? "is itself" : "leads into a cycle");
  }
}

// The pattern's matches in one executable section, under SEH: an image another tool changed or mapped
// oddly can fault, and C++ catch does not see an access violation.
int scan_guarded(const std::uint8_t* data, std::size_t size, const std::vector<int>& pattern,
                 std::size_t* hits, int capacity) noexcept {
  int count = 0;
  __try {
    const std::size_t length = pattern.size();
    for (std::size_t at = 0; at + length <= size && count < capacity; ++at) {
      bool match = true;
      for (std::size_t i = 0; i < length; ++i) {
        if (pattern[i] >= 0 && data[at + i] != static_cast<std::uint8_t>(pattern[i])) {
          match = false;
          break;
        }
      }
      if (match) hits[count++] = at;
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return -1;
  }
  return count;
}

// Our stub at `address`? Read under SEH: a call site changed by someone else may lead anywhere.
bool stub_at(std::uintptr_t address) noexcept {
  std::uint8_t code[15]{};
  __try {
    std::memcpy(code, reinterpret_cast<const void*>(address), sizeof(code));
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
  return is_stub(code);
}

void copy_text(char* to, unsigned size, const std::string& from) {
  if (!to || !size) return;
  const std::size_t n = from.size() < size - 1 ? from.size() : size - 1;
  std::memcpy(to, from.data(), n);
  to[n] = '\0';
}

// Committed, readable memory within reach of a rel32 from `target`.
void* allocate_near(std::uintptr_t target) {
  SYSTEM_INFO info{};
  GetSystemInfo(&info);
  const std::uintptr_t granularity = info.dwAllocationGranularity;
  constexpr std::uintptr_t kReach = 0x7FF00000;
  for (std::uintptr_t distance = granularity; distance < kReach; distance += granularity) {
    for (const bool below : {true, false}) {
      if (below && target < distance + granularity) continue;
      std::uintptr_t address = below ? target - distance : target + distance;
      address &= ~(granularity - 1);
      MEMORY_BASIC_INFORMATION region{};
      if (!VirtualQuery(reinterpret_cast<void*>(address), &region, sizeof(region))) continue;
      if (region.State != MEM_FREE) continue;
      if (void* memory = VirtualAlloc(reinterpret_cast<void*>(address), 4096, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE))
        return memory;
    }
  }
  return nullptr;
}

Status fail(std::string reason) {
  g_status.installed = false;
  g_status.reason = std::move(reason);
  return g_status;
}
}  // namespace

// The stub jumps here with the call site's arguments and the material in r9.
extern "C" const char* nl_engine_guard_hook(void* key_values, const char* key, const char* default_value,
                                            void* material) noexcept {
  thread_local Tracker tracker;
  return filter(g_real, key_values, key, default_value, material, tracker, GetTickCount64());
}

// What the other copy of this module reads from the copy that owns the detour.
extern "C" __declspec(dllexport) unsigned nl_engine_guard_cut_v1(char* material, unsigned material_size,
                                                                   char* fallback, unsigned fallback_size) noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_names);
    copy_text(material, material_size, g_last_material);
    copy_text(fallback, fallback_size, g_last_fallback);
  } catch (...) {
  }
  return g_cut.load(std::memory_order_relaxed);
}

const std::vector<int>& call_site_pattern() { return kPattern; }
const std::vector<int>& get_name_call_pattern() { return kGetNameCall; }

std::vector<std::size_t> find(const std::uint8_t* data, std::size_t size, const std::vector<int>& pattern,
                              std::size_t limit) {
  std::vector<std::size_t> hits;
  if (pattern.empty() || size < pattern.size()) return hits;
  for (std::size_t at = 0; at + pattern.size() <= size && hits.size() < limit; ++at) {
    bool match = true;
    for (std::size_t i = 0; i < pattern.size(); ++i) {
      if (pattern[i] >= 0 && data[at + i] != static_cast<std::uint8_t>(pattern[i])) {
        match = false;
        break;
      }
    }
    if (match) hits.push_back(at);
  }
  return hits;
}

std::string normalize(std::string_view name) {
  std::string out(name);
  for (auto& c : out) {
    if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    if (c == '\\') c = '/';
  }
  while (!out.empty() && out.front() == '/') out.erase(out.begin());
  constexpr std::string_view kFolder = "materials/";
  if (out.rfind(kFolder, 0) == 0) out.erase(0, kFolder.size());
  constexpr std::string_view kExtension = ".vmt";
  if (out.size() >= kExtension.size() && out.compare(out.size() - kExtension.size(), kExtension.size(), kExtension) == 0)
    out.erase(out.size() - kExtension.size());
  return out;
}

bool same_material(std::string_view a, std::string_view b) {
  return !a.empty() && !b.empty() && normalize(a) == normalize(b);
}

Verdict decide(Tracker& tracker, const void* material, std::string_view own_name, std::string_view fallback,
               std::uint64_t now_ms) {
  if (fallback.empty()) {  // the material's chain ended
    if (tracker.material == material) tracker.material = nullptr;
    return Verdict::follow;
  }
  if (same_material(own_name, fallback)) return Verdict::self;
  if (tracker.material == material && now_ms - tracker.tick <= kWindowMs) {
    ++tracker.hops;
  } else {
    tracker.material = material;
    tracker.hops = 1;
  }
  tracker.tick = now_ms;
  return tracker.hops > kMaxHops ? Verdict::too_many : Verdict::follow;
}

const char* filter(GetString get, void* key_values, const char* key, const char* default_value, void* material,
                   Tracker& tracker, std::uint64_t now_ms) {
  const char* value = get(key_values, key, default_value);
  if (!value || !material || !key || std::strcmp(key, kKey.data()) != 0) return value;
  if (!*value) {
    decide(tracker, material, {}, {}, now_ms);
    return value;
  }
  try {
    const char* own = material_name(material);
    const Verdict verdict = decide(tracker, material, own ? own : "", value, now_ms);
    if (verdict == Verdict::follow) return value;
    note(own, value, verdict);
    return kEmpty;
  } catch (...) {
    return value;  // never cost the engine more than the guard's own failure
  }
}

std::vector<std::uint8_t> stub(std::uintptr_t hook) {
  std::vector<std::uint8_t> bytes = {0x4D, 0x89, 0xF1, 0x48, 0xB8};  // mov r9,r14; mov rax,imm64
  for (int i = 0; i < 8; ++i) bytes.push_back(static_cast<std::uint8_t>(hook >> (8 * i)));
  bytes.push_back(0xFF);  // jmp rax
  bytes.push_back(0xE0);
  return bytes;
}

bool is_stub(const std::uint8_t* code) {
  return code[0] == 0x4D && code[1] == 0x89 && code[2] == 0xF1 && code[3] == 0x48 && code[4] == 0xB8 &&
         code[13] == 0xFF && code[14] == 0xE0;
}

Status install() noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_install);
    if (g_status.installed) return g_status;
    const HMODULE module = GetModuleHandleW(L"materialsystem.dll");
    if (!module) return fail("materialsystem.dll is not loaded");
    auto* base = reinterpret_cast<std::uint8_t*>(module);
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return fail("materialsystem.dll has no DOS header");
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC)
      return fail("materialsystem.dll is not a 64-bit image");
    const std::uintptr_t image_end = reinterpret_cast<std::uintptr_t>(base) + nt->OptionalHeader.SizeOfImage;
    std::vector<std::uint8_t*> sites;
    const IMAGE_SECTION_HEADER* site_section = nullptr;
    const auto* section = IMAGE_FIRST_SECTION(nt);
    for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section) {
      if (!(section->Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
      std::uint8_t* data = base + section->VirtualAddress;
      std::size_t hits[2]{};
      const int count = scan_guarded(data, section->Misc.VirtualSize, kPattern, hits, 2);
      if (count < 0) return fail("materialsystem.dll could not be read");
      for (int h = 0; h < count; ++h) {
        sites.push_back(data + hits[h]);
        site_section = section;
      }
    }
    if (sites.size() != 1)
      return fail(sites.empty() ? "the fallback call site is not in this materialsystem.dll (another game build)"
                                : "the fallback call site occurs more than once in this materialsystem.dll");
    std::uint8_t* site = sites.front();
    // r14 must be the material: the loop calls its GetName shortly after the call site.
    {
      const std::uint8_t* section_end = base + site_section->VirtualAddress + site_section->Misc.VirtualSize;
      const std::uint8_t* from = site + kCallOffset;
      const std::size_t reach = static_cast<std::size_t>(section_end - from) < kGetNameReach
                                    ? static_cast<std::size_t>(section_end - from)
                                    : kGetNameReach;
      std::size_t hit = 0;
      if (scan_guarded(from, reach, kGetNameCall, &hit, 1) != 1)
        return fail("the call site's loop does not call the material's GetName (another game build)");
    }
    std::int32_t displacement = 0;
    std::memcpy(&displacement, site + kKeyLeaOffset + 3, 4);
    const auto* key = reinterpret_cast<const char*>(site + kKeyLeaOffset + 7 + displacement);
    if (reinterpret_cast<std::uintptr_t>(key) < reinterpret_cast<std::uintptr_t>(base) ||
        reinterpret_cast<std::uintptr_t>(key) + kKey.size() >= image_end ||
        std::memcmp(key, kKey.data(), kKey.size() + 1) != 0)
      return fail("the matching call site does not read $fallbackmaterial");
    std::uint8_t* call = site + kCallOffset;
    g_status.site_rva = static_cast<std::uintptr_t>(call - base);
    std::int32_t relative = 0;
    std::memcpy(&relative, call + 1, 4);
    const std::uintptr_t target = reinterpret_cast<std::uintptr_t>(call + 5) + relative;
    if (stub_at(target)) {
      std::uintptr_t owner_hook = 0;
      std::memcpy(&owner_hook, reinterpret_cast<const void*>(target + 5), sizeof(owner_hook));
      HMODULE owner = nullptr;
      if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                             reinterpret_cast<LPCWSTR>(owner_hook), &owner))
        g_owner_counts = reinterpret_cast<OwnerCounts>(GetProcAddress(owner, "nl_engine_guard_cut_v1"));
      g_status.installed = true;
      g_status.reason = "installed by the other copy of this module";
      return g_status;
    }
    if (target < reinterpret_cast<std::uintptr_t>(base) || target >= image_end)
      return fail("the call site already points outside materialsystem.dll");
    if ((reinterpret_cast<std::uintptr_t>(call + 1) & 3) != 0)
      return fail("the call's displacement is not aligned for one atomic write (another game build)");
    // This module stays loaded for the process's lifetime: the stub jumps into it.
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                            reinterpret_cast<LPCWSTR>(&nl_engine_guard_hook), &self))
      return fail("this module could not be pinned");
    g_real = reinterpret_cast<GetString>(target);
    void* memory = allocate_near(reinterpret_cast<std::uintptr_t>(call));
    if (!memory) return fail("no memory within reach of materialsystem.dll for the stub");
    const auto bytes = stub(reinterpret_cast<std::uintptr_t>(&nl_engine_guard_hook));
    std::memcpy(memory, bytes.data(), bytes.size());
    DWORD old = 0;
    if (!VirtualProtect(memory, 4096, PAGE_EXECUTE_READ, &old)) {
      VirtualFree(memory, 0, MEM_RELEASE);
      return fail("the stub could not be made executable");
    }
    FlushInstructionCache(GetCurrentProcess(), memory, bytes.size());
    const auto distance = static_cast<std::int64_t>(reinterpret_cast<std::uintptr_t>(memory)) -
                          static_cast<std::int64_t>(reinterpret_cast<std::uintptr_t>(call + 5));
    if (distance < INT32_MIN || distance > INT32_MAX) {
      VirtualFree(memory, 0, MEM_RELEASE);
      return fail("the stub is out of a call's reach");
    }
    const auto new_relative = static_cast<std::int32_t>(distance);
    if (!VirtualProtect(call + 1, 4, PAGE_EXECUTE_READWRITE, &old)) {
      VirtualFree(memory, 0, MEM_RELEASE);
      return fail("the call site could not be made writable");
    }
    // One aligned store (rva 0xfb54 is aligned), so another thread never runs half of it; checked above.
    InterlockedExchange(reinterpret_cast<volatile LONG*>(call + 1), static_cast<LONG>(new_relative));
    VirtualProtect(call + 1, 4, old, &old);
    FlushInstructionCache(GetCurrentProcess(), call, 5);
    g_status.installed = true;
    g_status.reason = "installed";
    return g_status;
  } catch (...) {
    Status failed;
    failed.reason = "the engine guard failed while installing";
    return failed;
  }
}

Status status() noexcept {
  Status out;
  try {
    OwnerCounts owner = nullptr;
    {
      std::lock_guard<std::mutex> lock(g_install);
      out = g_status;
      owner = g_owner_counts;
    }
    if (owner) {
      char material[256]{}, fallback[256]{};
      out.cut = owner(material, sizeof(material), fallback, sizeof(fallback));
      out.last_material = material;
      out.last_fallback = fallback;
      return out;
    }
    out.cut = g_cut.load(std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(g_names);
    out.last_material = g_last_material;
    out.last_fallback = g_last_fallback;
  } catch (...) {
  }
  return out;
}

}  // namespace nl::engine_guard
