// Material colours above 1 capped for Remix: shaderapidx9.dll's four float colour functions wrapped (ADR 0190).
#include "colour_cap.h"

#include <windows.h>

#include <atomic>
#include <cstring>
#include <mutex>

namespace nl::engine_guard::colour_cap {

std::uint8_t engine_byte(float value) noexcept {
  // cvttss2si (truncation; out of range or NaN gives 0x80000000), then the low byte.
  const float scaled = value * 255.0f;
  const std::int32_t whole =
      (scaled == scaled && scaled > -2147483648.0f && scaled < 2147483648.0f) ? static_cast<std::int32_t>(scaled)
                                                                              : INT32_MIN;
  return static_cast<std::uint8_t>(static_cast<std::uint32_t>(whole) & 0xFF);
}

namespace {
bool rex(std::uint8_t byte) { return byte >= 0x40 && byte <= 0x4F; }

// An SSE instruction F3 [REX] 0F <op> at `at`: the offset of its ModRM byte, or 0 when there is none.
std::size_t sse(const std::uint8_t* code, std::size_t size, std::size_t at, std::uint8_t op) {
  if (at + 4 > size || code[at] != 0xF3) return 0;
  std::size_t i = at + 1;
  if (rex(code[i])) ++i;
  if (i + 2 >= size || code[i] != 0x0F || code[i + 1] != op) return 0;
  return i + 2;
}
}  // namespace

Kind classify(const std::uint8_t* code, std::size_t size, std::uintptr_t address, ReadFloat constant,
              const void* context) noexcept {
  if (!code) return Kind::none;
  if (size > kReach) size = kReach;
  // The function ends at its first `ret; int3` (the padding before the next one).
  for (std::size_t i = 0; i + 1 < size; ++i) {
    if (code[i] == 0xC3 && code[i + 1] == 0xCC) {
      size = i + 1;
      break;
    }
  }
  bool scale = false, three = false, through_pointer = false, fourth_through_pointer = false, from_stack = false;
  bool sets_factor = false;
  unsigned conversions = 0;
  for (std::size_t at = 0; at < size; ++at) {
    if (const std::size_t m = sse(code, size, at, 0x10)) {  // movss xmm, m32
      const std::uint8_t modrm = code[m];
      if ((modrm & 0xC7) == 0x05 && m + 5 <= size) {  // [rip + disp32]
        std::int32_t displacement = 0;
        std::memcpy(&displacement, code + m + 1, 4);
        float value = 0;
        const std::uintptr_t target =
            address + (m + 5) + static_cast<std::uintptr_t>(static_cast<std::intptr_t>(displacement));
        if (constant && constant(context, target, &value) && value == 255.0f) scale = true;
      } else if ((modrm & 0xC7) == 0x02) {  // [rdx]
        through_pointer = true;
      } else if ((modrm & 0xC7) == 0x42 && m + 1 < size) {  // [rdx + disp8]
        through_pointer = true;
        if (code[m + 1] == 0x0C) fourth_through_pointer = true;
      } else if ((modrm & 0xC7) == 0x44 && m + 1 < size && code[m + 1] == 0x24) {  // [rsp + disp8]
        from_stack = true;
      }
    }
    if (sse(code, size, at, 0x2C)) ++conversions;  // cvttss2si r32, xmm
    // or r32, 0xFF000000: the 3-component functions set alpha themselves.
    {
      std::size_t i = at;
      if (rex(code[i]) && i + 1 < size) ++i;
      if (i + 6 <= size && code[i] == 0x81 && (code[i + 1] & 0xF8) == 0xC8 && code[i + 2] == 0 && code[i + 3] == 0 &&
          code[i + 4] == 0 && code[i + 5] == 0xFF)
        three = true;
      if (i == at && i + 5 <= size && code[i] == 0x0D && code[i + 1] == 0 && code[i + 2] == 0 && code[i + 3] == 0 &&
          code[i + 4] == 0xFF)
        three = true;
    }
    // mov edx, D3DRS_TEXTUREFACTOR, then call [rax + SetRenderState] within 16 bytes.
    constexpr auto kState = static_cast<std::uint8_t>(kTextureFactor);
    constexpr auto kCallLow = static_cast<std::uint8_t>(kSetRenderStateOffset & 0xFF);
    constexpr auto kCallHigh = static_cast<std::uint8_t>((kSetRenderStateOffset >> 8) & 0xFF);
    if (at + 5 <= size && code[at] == 0xBA && code[at + 1] == kState && code[at + 2] == 0 && code[at + 3] == 0 &&
        code[at + 4] == 0) {
      for (std::size_t c = at + 5; c + 6 <= size && c < at + 21; ++c) {
        if (code[c] == 0xFF && code[c + 1] == 0x90 && code[c + 2] == kCallLow && code[c + 3] == kCallHigh &&
            code[c + 4] == 0 && code[c + 5] == 0) {
          sets_factor = true;
          break;
        }
      }
    }
  }
  if (!scale || !sets_factor) return Kind::none;
  if (three && conversions >= 3) {
    if (through_pointer) return Kind::colour3fv;
    if (!from_stack) return Kind::colour3f;
    return Kind::none;
  }
  if (!three && conversions >= 4) {
    if (through_pointer && fourth_through_pointer) return Kind::colour4fv;
    if (!through_pointer && from_stack) return Kind::colour4f;
  }
  return Kind::none;
}

namespace {
struct Image {
  const std::uint8_t* data;
  std::uintptr_t loaded_base;
  std::uintptr_t size;
};

bool image_float(const void* context, std::uintptr_t address, float* value) {
  const auto* image = static_cast<const Image*>(context);
  if (address < image->loaded_base || address + 4 > image->loaded_base + image->size) return false;
  std::memcpy(value, image->data + (address - image->loaded_base), 4);
  return true;
}

constexpr Kind kOrder[kSlots] = {Kind::colour3f, Kind::colour3fv, Kind::colour4f, Kind::colour4fv};
}  // namespace

std::size_t find_slots(const std::uint8_t* image, std::uintptr_t loaded_base) noexcept {
  if (!image) return SIZE_MAX;
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) return SIZE_MAX;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return SIZE_MAX;
  const Image context{image, loaded_base, nt->OptionalHeader.SizeOfImage};
  const auto* sections = IMAGE_FIRST_SECTION(nt);
  const unsigned count = nt->FileHeader.NumberOfSections;
  auto in_code = [&](std::uintptr_t pointer) -> bool {
    if (pointer < loaded_base) return false;
    const std::uintptr_t rva = pointer - loaded_base;
    for (unsigned s = 0; s < count; ++s) {
      if ((sections[s].Characteristics & IMAGE_SCN_MEM_EXECUTE) && rva >= sections[s].VirtualAddress &&
          rva < sections[s].VirtualAddress + sections[s].Misc.VirtualSize)
        return true;
    }
    return false;
  };
  auto code_size = [&](std::uintptr_t rva) -> std::size_t {
    for (unsigned s = 0; s < count; ++s) {
      const std::uintptr_t start = sections[s].VirtualAddress, end = start + sections[s].Misc.VirtualSize;
      if (rva >= start && rva < end) return static_cast<std::size_t>(end - rva);
    }
    return 0;
  };
  std::size_t found = SIZE_MAX;
  unsigned runs = 0;
  for (unsigned s = 0; s < count; ++s) {
    const auto& section = sections[s];
    // Vtables are in read-only initialized data.
    if ((section.Characteristics & (IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_WRITE)) ||
        !(section.Characteristics & IMAGE_SCN_CNT_INITIALIZED_DATA))
      continue;
    const std::uintptr_t start = (section.VirtualAddress + 7) & ~std::uintptr_t{7};
    const std::uintptr_t end = section.VirtualAddress + section.Misc.VirtualSize;
    for (std::uintptr_t at = start; at + kSlots * 8 <= end; at += 8) {
      std::uintptr_t pointers[kSlots];
      std::memcpy(pointers, image + at, sizeof(pointers));
      bool match = true;
      for (std::size_t i = 0; i < kSlots && match; ++i) {
        if (!in_code(pointers[i])) {
          match = false;
          break;
        }
        for (std::size_t j = 0; j < i; ++j) match = match && pointers[j] != pointers[i];
        if (!match) break;
        const std::uintptr_t rva = pointers[i] - loaded_base;
        if (classify(image + rva, code_size(rva), pointers[i], &image_float, &context) != kOrder[i]) match = false;
      }
      if (match) {
        found = at;
        ++runs;
      }
    }
  }
  return runs == 1 ? found : SIZE_MAX;
}

namespace {
using Colour3f = void (*)(void*, float, float, float);
using Colour3fv = void (*)(void*, const float*);
using Colour4f = void (*)(void*, float, float, float, float);
using Colour4fv = void (*)(void*, const float*);

// The engine's own functions, set before any slot changes and never after.
Colour3f g_3f = nullptr;
Colour3fv g_3fv = nullptr;
Colour4f g_4f = nullptr;
Colour4fv g_4fv = nullptr;
std::atomic<bool> g_enabled{true};
std::atomic<bool> g_owns{false};  // this copy switched the slots
std::atomic<std::uint64_t> g_capped{0};

std::mutex g_install;
Status g_status;  // under g_install
// The other copy's switch and counts, when it installed first (the client and the server module are two images
// in one process; the slots point into only one of them).
using Owner = int (*)(int set, std::uint64_t* capped, std::uintptr_t* slots_rva);
Owner g_owner = nullptr;  // under g_install

bool outside(float value) { return !(value >= 0.0f && value <= 1.0f); }

void note() { g_capped.fetch_add(1, std::memory_order_relaxed); }

void hook_3f(void* self, float r, float g, float b) {
  if (g_enabled.load(std::memory_order_relaxed) && (outside(r) || outside(g) || outside(b))) {
    note();
    r = cap(r);
    g = cap(g);
    b = cap(b);
  }
  g_3f(self, r, g, b);
}

void hook_3fv(void* self, const float* colour) {
  if (colour && g_enabled.load(std::memory_order_relaxed) &&
      (outside(colour[0]) || outside(colour[1]) || outside(colour[2]))) {
    note();
    const float capped[3] = {cap(colour[0]), cap(colour[1]), cap(colour[2])};
    g_3fv(self, capped);
    return;
  }
  g_3fv(self, colour);
}

void hook_4f(void* self, float r, float g, float b, float a) {
  if (g_enabled.load(std::memory_order_relaxed) && (outside(r) || outside(g) || outside(b) || outside(a))) {
    note();
    r = cap(r);
    g = cap(g);
    b = cap(b);
    a = cap(a);
  }
  g_4f(self, r, g, b, a);
}

void hook_4fv(void* self, const float* colour) {
  if (colour && g_enabled.load(std::memory_order_relaxed) &&
      (outside(colour[0]) || outside(colour[1]) || outside(colour[2]) || outside(colour[3]))) {
    note();
    const float capped[4] = {cap(colour[0]), cap(colour[1]), cap(colour[2]), cap(colour[3])};
    g_4fv(self, capped);
    return;
  }
  g_4fv(self, colour);
}

using Msg = void (*)(const char*, ...);
void say(const char* text) {
  const HMODULE tier0 = GetModuleHandleW(L"tier0.dll");
  const auto msg = tier0 ? reinterpret_cast<Msg>(GetProcAddress(tier0, "Msg")) : nullptr;
  if (msg) msg("%s", text);
}

std::size_t find_guarded(const std::uint8_t* image) noexcept {
  __try {
    return find_slots(image, reinterpret_cast<std::uintptr_t>(image));
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return SIZE_MAX - 1;
  }
}

Status fail(std::string reason) {
  g_status.installed = false;
  g_status.reason = std::move(reason);
  return g_status;
}

// The other copy of this module (gmcl_ or gmsv_), when it is loaded and owns the slots.
Owner other_copy() {
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&hook_3f), &self);
  for (const wchar_t* name : {L"gmcl_nlengineguard_win64.dll", L"gmsv_nlengineguard_win64.dll"}) {
    const HMODULE module = GetModuleHandleW(name);
    if (!module || module == self) continue;
    const auto owner = reinterpret_cast<Owner>(GetProcAddress(module, "nl_engine_guard_colour_cap_v1"));
    if (owner && owner(-1, nullptr, nullptr) >= 0) return owner;
  }
  return nullptr;
}

Status install_locked() {
  if (g_status.installed || g_owner) return g_status;
  // Only where the Remix runtime is the game's d3d9.dll.
  const HMODULE d3d9 = GetModuleHandleW(L"d3d9.dll");
  if (!d3d9 || !GetProcAddress(d3d9, "remixapi_InitializeLibrary")) return fail("not a Remix start");
  if (const Owner owner = other_copy()) {
    g_owner = owner;
    std::uintptr_t rva = 0;
    owner(-1, nullptr, &rva);
    g_status.installed = true;
    g_status.slots_rva = rva;
    g_status.reason = "installed by the other copy of this module";
    return g_status;
  }
  const HMODULE shaderapi = GetModuleHandleW(L"shaderapidx9.dll");
  if (!shaderapi) return fail("shaderapidx9.dll is not loaded");
  auto* base = reinterpret_cast<std::uint8_t*>(shaderapi);
  const std::size_t at = find_guarded(base);
  if (at == SIZE_MAX - 1) return fail("shaderapidx9.dll could not be read");
  if (at == SIZE_MAX)
    return fail("shaderapidx9.dll's colour functions were not found once (another game build, or changed by another module)");
  // This module stays loaded for the process's lifetime: the slots point into it.
  HMODULE self = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                          reinterpret_cast<LPCWSTR>(&hook_3f), &self))
    return fail("this module could not be pinned");
  auto* slots = reinterpret_cast<void**>(base + at);
  g_3f = reinterpret_cast<Colour3f>(slots[0]);
  g_3fv = reinterpret_cast<Colour3fv>(slots[1]);
  g_4f = reinterpret_cast<Colour4f>(slots[2]);
  g_4fv = reinterpret_cast<Colour4fv>(slots[3]);
  void* const hooks[kSlots] = {reinterpret_cast<void*>(&hook_3f), reinterpret_cast<void*>(&hook_3fv),
                               reinterpret_cast<void*>(&hook_4f), reinterpret_cast<void*>(&hook_4fv)};
  DWORD old = 0;
  if (!VirtualProtect(slots, kSlots * sizeof(void*), PAGE_READWRITE, &old))
    return fail("shaderapidx9.dll's vtable could not be made writable");
  // Each slot is one aligned pointer: another thread calls either the engine's function or the wrapper.
  for (std::size_t i = 0; i < kSlots; ++i) InterlockedExchangePointer(&slots[i], hooks[i]);
  VirtualProtect(slots, kSlots * sizeof(void*), old, &old);
  g_owns.store(true);
  g_status.installed = true;
  g_status.slots_rva = at;
  g_status.reason = "installed";
  say("[NativeLoader] Material colours above 1 are capped at 1 for Remix ($color2, $color; engine guard, ADR 0190).\n");
  return g_status;
}

Status fill(Status out) {
  if (g_owner) {
    std::uint64_t capped = 0;
    out.enabled = g_owner(-1, &capped, nullptr) == 1;
    out.capped = capped;
  } else {
    out.enabled = out.installed && g_enabled.load(std::memory_order_relaxed);
    out.capped = g_capped.load(std::memory_order_relaxed);
  }
  return out;
}
}  // namespace

// What the other copy of this module reads from (and switches in) the copy that owns the slots. set: -1 reads,
// 0 turns capping off, 1 on. Returns -1 when this copy did not install, else whether it caps now.
extern "C" __declspec(dllexport) int nl_engine_guard_colour_cap_v1(int set, std::uint64_t* capped,
                                                                    std::uintptr_t* slots_rva) noexcept {
  if (!g_owns.load()) return -1;
  if (set == 0 || set == 1) g_enabled.store(set == 1, std::memory_order_relaxed);
  if (capped) *capped = g_capped.load(std::memory_order_relaxed);
  if (slots_rva) {
    try {
      std::lock_guard<std::mutex> lock(g_install);
      *slots_rva = g_status.slots_rva;
    } catch (...) {
    }
  }
  return g_enabled.load(std::memory_order_relaxed) ? 1 : 0;
}

Status install() noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_install);
    return fill(install_locked());
  } catch (...) {
    Status failed;
    failed.reason = "the colour cap failed while installing";
    return failed;
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

Status set_enabled(bool enabled) noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_install);
    if (g_owner)
      g_owner(enabled ? 1 : 0, nullptr, nullptr);
    else if (g_status.installed)
      g_enabled.store(enabled, std::memory_order_relaxed);
    return fill(g_status);
  } catch (...) {
    return {};
  }
}

}  // namespace nl::engine_guard::colour_cap
