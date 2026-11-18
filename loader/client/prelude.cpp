#include "prelude.h"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <initializer_list>
#include <optional>
#include <vector>

namespace nl::client::prelude {
namespace {
// ILuaInterface::FindAndRunScript(filename, run, showErrors, stringToRun, noReturns) with the state first: on x64 a
// member function and this free function take their arguments the same way.
using FindAndRun = bool (*)(void* state, const char* filename, bool run, bool showErrors, const char* stringToRun,
                            bool noReturns);
std::atomic<FindAndRun> original{nullptr};
std::atomic<Runner> current{nullptr};
std::atomic<unsigned> count{0};

bool hook(void* state, const char* filename, bool run, bool showErrors, const char* stringToRun, bool noReturns) {
  const auto runner = current.load();
  if (runner && starts_realm(filename, run) && runner(state)) count.fetch_add(1);
  return original.load()(state, filename, run, showErrors, stringToRun, noReturns);
}

struct Section {
  std::uintptr_t begin = 0, end = 0;
  bool code = false;
};
struct Image {
  std::uintptr_t begin = 0, end = 0;
  std::vector<Section> sections;  // the readable ones, as mapped
};
// A loaded module's extent and sections, from its own PE headers.
std::optional<Image> image_of(const void* module) {
  const auto base = reinterpret_cast<std::uintptr_t>(module);
  const auto* dos = static_cast<const IMAGE_DOS_HEADER*>(module);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) return std::nullopt;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + static_cast<std::uintptr_t>(dos->e_lfanew));
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return std::nullopt;
  Image image{base, base + nt->OptionalHeader.SizeOfImage, {}};
  const auto* section = IMAGE_FIRST_SECTION(nt);
  for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section) {
    if (!(section->Characteristics & IMAGE_SCN_MEM_READ)) continue;
    const auto begin = base + section->VirtualAddress;
    const auto size = section->Misc.VirtualSize ? section->Misc.VirtualSize : section->SizeOfRawData;
    const auto end = std::min<std::uintptr_t>(begin + size, image.end);
    if (begin < end) image.sections.push_back({begin, end, (section->Characteristics & IMAGE_SCN_MEM_EXECUTE) != 0});
  }
  return image;
}
bool in_code(const Image& image, std::uintptr_t first, std::uintptr_t last) {
  return std::any_of(image.sections.begin(), image.sections.end(),
                     [&](const Section& s) { return s.code && first >= s.begin && last <= s.end; });
}
bool touches_code(const Image& image, std::uintptr_t first, std::uintptr_t last) {
  return std::any_of(image.sections.begin(), image.sections.end(),
                     [&](const Section& s) { return s.code && first < s.end && last > s.begin; });
}
}  // namespace

bool starts_realm(const char* filename, bool run) noexcept {
  return run && filename && std::strcmp(filename, kInit.data()) == 0;
}

bool is_prelude_script(std::string_view key) noexcept {
  if (!key.starts_with(kScripts) || !key.ends_with(".lua")) return false;
  const auto name = key.substr(kScripts.size());
  return name.size() > 4 && name.find('/') == std::string_view::npos;
}

bool calls_through_slot(std::span<const unsigned char> code, std::uintptr_t code_address,
                        std::uintptr_t string_address) noexcept {
  constexpr std::uint32_t offset = kFindAndRunScriptSlot * sizeof(void*);
  for (std::size_t i = 0; i + 7 <= code.size(); ++i) {
    if (code[i] != 0x48 || code[i + 1] != 0x8D || code[i + 2] != 0x15) continue;  // lea rdx, [rip+disp32]
    std::int32_t disp = 0;
    std::memcpy(&disp, code.data() + i + 3, sizeof disp);
    if (code_address + i + 7 + static_cast<std::intptr_t>(disp) != string_address) continue;
    const auto stop = std::min(code.size(), i + 7 + 64);
    for (std::size_t j = i + 7; j + 6 <= stop; ++j) {
      // call qword ptr [reg+disp32]: FF, then mod 10, reg 010 (/2), any base but rsp (a SIB byte would follow).
      if (code[j] != 0xFF || (code[j + 1] & 0xF8) != 0x90 || (code[j + 1] & 7) == 4) continue;
      std::uint32_t target = 0;
      std::memcpy(&target, code.data() + j + 2, sizeof target);
      if (target == offset) return true;
    }
  }
  return false;
}

std::string confirm_engine_call(const void* client) noexcept {
  try {
    if (!client) return "client.dll is not loaded";
    const auto image = image_of(client);
    if (!image) return "client.dll is not a 64-bit image";
    constexpr std::string_view name{"includes/init.lua\0", 18};
    std::vector<std::uintptr_t> strings;
    for (const auto& section : image->sections) {
      if (section.code) continue;
      const std::string_view bytes(reinterpret_cast<const char*>(section.begin), section.end - section.begin);
      for (auto at = bytes.find(name); at != std::string_view::npos; at = bytes.find(name, at + 1)) {
        if (at == 0 || bytes[at - 1] == '\0') strings.push_back(section.begin + at);
      }
    }
    if (strings.empty()) return "client.dll does not name includes/init.lua";
    for (const auto& section : image->sections) {
      if (!section.code) continue;
      const std::span code(reinterpret_cast<const unsigned char*>(section.begin), section.end - section.begin);
      for (const auto address : strings) {
        if (calls_through_slot(code, section.begin, address)) return {};
      }
    }
    return "client.dll does not start a realm through the FindAndRunScript slot";
  } catch (...) {
    return "client.dll could not be read";
  }
}

std::string install(const void* state, const void* module, Runner runner) noexcept {
  try {
    if (!state || !module || !runner) return "no Lua state, module or runner";
    const auto image = image_of(module);
    if (!image) return "the Lua module is not a 64-bit image";
    auto* const* table = *static_cast<void* const* const*>(state);
    const auto first = reinterpret_cast<std::uintptr_t>(table);
    const auto last = reinterpret_cast<std::uintptr_t>(table + kRunStringExSlot + 1);
    if (first < image->begin || last > image->end || touches_code(*image, first, last))
      return "the Lua interface's vtable is not in the Lua module's data";
    const auto ours = reinterpret_cast<void*>(&hook);
    for (const auto slot : {kIsClientSlot, kFindAndRunScriptSlot, kRunStringExSlot}) {
      const auto target = reinterpret_cast<std::uintptr_t>(table[slot]);
      if (slot == kFindAndRunScriptSlot && table[slot] == ours) continue;
      if (!in_code(*image, target, target + 1)) return "a slot of the Lua interface's vtable is not the Lua module's code";
    }
    current.store(runner);
    if (table[kFindAndRunScriptSlot] == ours) return {};  // hooked by an earlier menu state: only the runner changes
    auto** slot = const_cast<void**>(&table[kFindAndRunScriptSlot]);
    DWORD protection = 0;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &protection)) {
      current.store(nullptr);
      return "the Lua interface's vtable cannot be written";
    }
    original.store(reinterpret_cast<FindAndRun>(*slot));
    InterlockedExchangePointer(slot, ours);
    DWORD ignored = 0;
    VirtualProtect(slot, sizeof(void*), protection, &ignored);
    return {};
  } catch (...) {
    return "the client prelude could not be installed";
  }
}

bool installed() noexcept { return original.load() != nullptr; }
unsigned runs() noexcept { return count.load(); }
}  // namespace nl::client::prelude
