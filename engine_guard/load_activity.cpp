// What the main thread is doing while a map loads (ADR 0214): see load_activity.h.
#include "load_activity.h"
#include <windows.h>
#include <algorithm>
#include <cctype>
#include <cstring>
#include <string>

namespace nl::engine_guard::overlay {
namespace {

struct Known {
  const wchar_t* name;
  Kind kind;
};

// The modules the activity line knows. Remix: the runtime's own libraries (packages/runtime) and the Vulkan loader and
// drivers it runs on (in a Remix start nothing else of the game uses Vulkan). Files: the engine's file system, its
// image decoder (FreeImage: PNG icons) and the load accelerator's hooks on the file system. Scripts: LuaJIT. Game: the
// engine's own code; a thread found in it is not waiting for anyone listed.
constexpr Known kKnown[] = {
    {L"nrd.dll", Kind::remix},
    {L"nrc_vulkan.dll", Kind::remix},
    {L"nvlowlatencyvk.dll", Kind::remix},
    {L"nvngx_dlss.dll", Kind::remix},
    {L"nvngx_dlssd.dll", Kind::remix},
    {L"nvngx_dlssg.dll", Kind::remix},
    {L"nvngx_dlssnr.dll", Kind::remix},
    {L"libxess.dll", Kind::remix},
    {L"amd_fidelityfx_vk.dll", Kind::remix},
    {L"rtxio.dll", Kind::remix},
    {L"vulkan-1.dll", Kind::remix},
    {L"nvoglv64.dll", Kind::remix},
    {L"nvgpucomp64.dll", Kind::remix},
    {L"amdvlk64.dll", Kind::remix},
    {L"igvk64.dll", Kind::remix},
    {L"filesystem_stdio.dll", Kind::files},
    {L"resources.dll", Kind::files},
    {L"gmcl_nlfsaccel_win64.dll", Kind::files},
    {L"gmsv_nlfsaccel_win64.dll", Kind::files},
    {L"lua_shared.dll", Kind::scripts},
    {L"engine.dll", Kind::game},
    {L"client.dll", Kind::game},
    {L"server.dll", Kind::game},
    {L"materialsystem.dll", Kind::game},
    {L"shaderapidx9.dll", Kind::game},
    {L"studiorender.dll", Kind::game},
    {L"datacache.dll", Kind::game},
    {L"vphysics.dll", Kind::game},
    {L"vgui2.dll", Kind::game},
    {L"vguimatsurface.dll", Kind::game},
    {L"stdshader_dx9.dll", Kind::game},
    {L"game_shader_generic_garrysmod.dll", Kind::game},
    {L"menusystem.dll", Kind::game},
    {L"gameui.dll", Kind::game},
    {L"html_chromium.dll", Kind::game},
    {L"inputsystem.dll", Kind::game},
    {L"soundsystem.dll", Kind::game},
    {L"gmod_audio.dll", Kind::game},
    {L"scenefilecache.dll", Kind::game},
    {L"soundemittersystem.dll", Kind::game},
    {L"launcher.dll", Kind::game},
    {L"mdllib.dll", Kind::game},
};

std::wstring lower(std::wstring_view text) {
  std::wstring out(text);
  for (auto& c : out)
    if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
  return out;
}

constexpr unsigned kMaxSections = 96;
struct Sections {
  unsigned count = 0;
  std::uint32_t rva[kMaxSections];
  std::uint32_t size[kMaxSections];
};

// The image's executable sections, read from its headers under SEH (a module could be unmapped meanwhile; nothing
// here needs unwinding).
bool read_sections(const std::uint8_t* image, Sections& out) noexcept {
  __try {
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 0x10000) return false;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64) return false;
    const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(nt);
    const unsigned count = nt->FileHeader.NumberOfSections;
    for (unsigned i = 0; i < count && out.count < kMaxSections; ++i) {
      if (!(section[i].Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
      const std::uint32_t size = section[i].Misc.VirtualSize ? section[i].Misc.VirtualSize : section[i].SizeOfRawData;
      if (!size) continue;
      out.rva[out.count] = section[i].VirtualAddress;
      out.size[out.count] = size;
      ++out.count;
    }
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// The nearest value on the stack that is code of a known module: for a thread waiting in Windows or a C runtime, the
// module that called it. Stops at the first known one (a game module's frame is the caller then, not a deeper one).
Kind nearest_caller(const std::uint8_t* stack, std::size_t size, const std::vector<Range>& ranges) {
  const std::size_t end = std::min(size, kCallerScan) / sizeof(std::uintptr_t) * sizeof(std::uintptr_t);
  for (std::size_t at = 0; at < end; at += sizeof(std::uintptr_t)) {
    std::uintptr_t value = 0;
    std::memcpy(&value, stack + at, sizeof(value));
    const Kind kind = kind_at(ranges, value);
    if (kind != Kind::other) return kind;
  }
  return Kind::other;
}

// A return into LuaJIT within the scanned stack: the game's code was called from Lua (Material(), file.Find(), ...).
bool called_from_lua(const std::uint8_t* stack, std::size_t size, const std::vector<Range>& ranges) {
  const std::size_t end = std::min(size, kCallerScan) / sizeof(std::uintptr_t) * sizeof(std::uintptr_t);
  for (std::size_t at = 0; at < end; at += sizeof(std::uintptr_t)) {
    std::uintptr_t value = 0;
    std::memcpy(&value, stack + at, sizeof(value));
    if (kind_at(ranges, value) == Kind::scripts) return true;
  }
  return false;
}

}  // namespace

Kind module_kind(std::wstring_view name, bool remix_d3d9) {
  const std::wstring key = lower(name);
  if (key == L"d3d9.dll") return remix_d3d9 ? Kind::remix : Kind::game;
  for (const auto& known : kKnown)
    if (key == known.name) return known.kind;
  return Kind::other;
}

std::vector<Range> code_ranges(const void* image, Kind kind) {
  std::vector<Range> ranges;
  if (!image) return ranges;
  Sections sections;
  const auto* base = static_cast<const std::uint8_t*>(image);
  if (!read_sections(base, sections)) return ranges;
  for (unsigned i = 0; i < sections.count; ++i) {
    Range range;
    range.begin = reinterpret_cast<std::uintptr_t>(base) + sections.rva[i];
    range.end = range.begin + sections.size[i];
    range.kind = kind;
    ranges.push_back(range);
  }
  return ranges;
}

Kind kind_at(const std::vector<Range>& ranges, std::uintptr_t address) {
  for (const auto& range : ranges)
    if (address >= range.begin && address < range.end) return range.kind;
  return Kind::other;
}

bool jit_code(std::uintptr_t address) {
  MEMORY_BASIC_INFORMATION info{};
  if (!address || VirtualQuery(reinterpret_cast<LPCVOID>(address), &info, sizeof(info)) != sizeof(info)) return false;
  if (info.State != MEM_COMMIT || info.Type != MEM_PRIVATE) return false;
  const DWORD protect = info.Protect & 0xFF;
  return protect == PAGE_EXECUTE || protect == PAGE_EXECUTE_READ || protect == PAGE_EXECUTE_READWRITE ||
         protect == PAGE_EXECUTE_WRITECOPY;
}

std::vector<Range> process_ranges() {
  std::vector<Range> ranges;
  try {
    const HMODULE d3d9 = GetModuleHandleW(L"d3d9.dll");
    const bool remix = d3d9 && GetProcAddress(d3d9, "remixapi_InitializeLibrary");
    if (d3d9) {
      const auto found = code_ranges(d3d9, module_kind(L"d3d9.dll", remix));
      ranges.insert(ranges.end(), found.begin(), found.end());
    }
    for (const auto& known : kKnown) {
      const HMODULE module = GetModuleHandleW(known.name);
      if (!module) continue;
      const auto found = code_ranges(module, known.kind);
      ranges.insert(ranges.end(), found.begin(), found.end());
    }
    // The executable (gmod.exe): the bottom of the main thread's stack, the game's own.
    const auto exe = code_ranges(GetModuleHandleW(nullptr), Kind::game);
    ranges.insert(ranges.end(), exe.begin(), exe.end());
  } catch (...) {
  }
  return ranges;
}

bool spawn_menu_file(std::string_view lua) {
  std::string name(lua);
  std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return name.find("spawnmenu") != std::string::npos || name.find("spawn_menu") != std::string::npos;
}

Activity classify(Kind where, const std::uint8_t* stack, std::size_t size, const std::vector<Range>& ranges,
                  std::string_view lua) {
  Kind kind = where;
  if (!stack) size = 0;
  if (kind == Kind::other) {
    // Waiting in Windows, a C runtime or tier0: for whom.
    kind = nearest_caller(stack, size, ranges);
  } else if (kind == Kind::game && called_from_lua(stack, size, ranges)) {
    kind = Kind::scripts;
  }
  Activity activity = Activity::none;
  switch (kind) {
    case Kind::remix:
      activity = Activity::remix;
      break;
    case Kind::files:
      activity = Activity::files;
      break;
    case Kind::scripts:
      activity = Activity::scripts;
      break;
    default:
      // The game's own code with a Lua file being run further down: that file's work.
      activity = lua.empty() ? Activity::none : Activity::scripts;
      break;
  }
  if (activity == Activity::scripts && spawn_menu_file(lua)) activity = Activity::spawnmenu;
  return activity;
}

void Recent::add(Activity activity) {
  samples_[next_] = activity;
  next_ = (next_ + 1) % kRecentSamples;
  if (filled_ < kRecentSamples) ++filled_;
}

Activity Recent::shown() const {
  constexpr std::size_t kinds = static_cast<std::size_t>(Activity::count);
  std::size_t counts[kinds] = {};
  std::size_t newest[kinds] = {};  // how many samples ago it was last seen
  for (std::size_t age = 0; age < filled_; ++age) {
    const std::size_t index = (next_ + kRecentSamples - 1 - age) % kRecentSamples;
    const auto activity = static_cast<std::size_t>(samples_[index]);
    if (activity >= kinds) continue;
    if (counts[activity]++ == 0) newest[activity] = age;
  }
  std::size_t best = 0, best_count = 0, best_age = 0;
  for (std::size_t activity = 1; activity < kinds; ++activity) {
    if (counts[activity] < kShownAtLeast) continue;
    if (counts[activity] > best_count || (counts[activity] == best_count && newest[activity] < best_age)) {
      best = activity;
      best_count = counts[activity];
      best_age = newest[activity];
    }
  }
  return static_cast<Activity>(best);
}

void Recent::clear() {
  next_ = 0;
  filled_ = 0;
}

}  // namespace nl::engine_guard::overlay
