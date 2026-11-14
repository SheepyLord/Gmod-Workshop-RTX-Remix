// The load overlay's activity line (ADR 0214): modules by name, an image's code ranges from its headers (this test
// executable's own, and headers that cannot be read), LuaJIT-style executable memory, the classification of one
// sample of the main thread from fake ranges and stacks, the spawn menu's chunk names and the two-second smoothing.
// The sampling of a game's main thread itself is checked in a game.
#include "load_activity.h"
#include "nl_test.h"

#include <windows.h>

#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <vector>

namespace {
using nl::engine_guard::overlay::Activity;
using nl::engine_guard::overlay::Kind;
using nl::engine_guard::overlay::Range;

// Stand-ins: Remix's code, LuaJIT's, the file system's and the engine's.
std::vector<Range> fake_ranges() {
  return {
      {0x10000, 0x20000, Kind::remix},
      {0x30000, 0x40000, Kind::scripts},
      {0x50000, 0x60000, Kind::files},
      {0x70000, 0x80000, Kind::game},
  };
}

std::vector<std::uint8_t> stack_of(std::initializer_list<std::uintptr_t> values) {
  std::vector<std::uint8_t> bytes(values.size() * sizeof(std::uintptr_t));
  std::size_t at = 0;
  for (const auto value : values) {
    std::memcpy(bytes.data() + at, &value, sizeof(value));
    at += sizeof(value);
  }
  return bytes;
}

Activity classify(Kind where, const std::vector<std::uint8_t>& stack, const char* lua = "") {
  const auto ranges = fake_ranges();
  return nl::engine_guard::overlay::classify(where, stack.data(), stack.size(), ranges, lua);
}

__declspec(noinline) int marker_function(int value) { return value * 3 + 1; }
int g_marker_data = 7;
}  // namespace

TEST_CASE("load activity: modules by name, any case") {
  using nl::engine_guard::overlay::module_kind;
  CHECK(module_kind(L"D3D9.dll", true) == Kind::remix);
  CHECK(module_kind(L"d3d9.dll", false) == Kind::game);  // not the Remix runtime: the game's drawing
  CHECK(module_kind(L"lua_shared.dll", false) == Kind::scripts);
  CHECK(module_kind(L"FileSystem_Stdio.dll", false) == Kind::files);
  CHECK(module_kind(L"resources.dll", false) == Kind::files);
  CHECK(module_kind(L"gmsv_nlfsaccel_win64.dll", false) == Kind::files);
  CHECK(module_kind(L"nvoglv64.dll", false) == Kind::remix);
  CHECK(module_kind(L"vulkan-1.dll", false) == Kind::remix);
  CHECK(module_kind(L"NRD.dll", false) == Kind::remix);
  CHECK(module_kind(L"engine.dll", false) == Kind::game);
  CHECK(module_kind(L"client.dll", false) == Kind::game);
  CHECK(module_kind(L"ntdll.dll", false) == Kind::other);
  CHECK(module_kind(L"tier0.dll", false) == Kind::other);
  CHECK(module_kind(L"", false) == Kind::other);
}

TEST_CASE("load activity: an image's code ranges come from its headers") {
  using nl::engine_guard::overlay::code_ranges;
  using nl::engine_guard::overlay::kind_at;
  const auto ranges = code_ranges(GetModuleHandleW(nullptr), Kind::game);
  REQUIRE(!ranges.empty());
  CHECK(marker_function(2) == 7);
  CHECK(kind_at(ranges, reinterpret_cast<std::uintptr_t>(&marker_function)) == Kind::game);
  CHECK(kind_at(ranges, reinterpret_cast<std::uintptr_t>(&g_marker_data)) == Kind::other);  // data is not code
  CHECK(kind_at(ranges, 0) == Kind::other);
  CHECK(code_ranges(nullptr, Kind::game).empty());
  const std::uint8_t junk[512] = {};
  CHECK(code_ranges(junk, Kind::game).empty());
  // "MZ" with its NT header offset in memory that is reserved, not committed: refused under SEH, not a crash.
  auto* block = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, 0x10000, MEM_RESERVE, PAGE_NOACCESS));
  REQUIRE(block != nullptr);
  REQUIRE(VirtualAlloc(block, 0x1000, MEM_COMMIT, PAGE_READWRITE) != nullptr);
  auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(block);
  dos->e_magic = IMAGE_DOS_SIGNATURE;
  dos->e_lfanew = 0x8000;
  CHECK(code_ranges(block, Kind::game).empty());
  VirtualFree(block, 0, MEM_RELEASE);
}

TEST_CASE("load activity: this process's known modules") {
  using nl::engine_guard::overlay::kind_at;
  const auto ranges = nl::engine_guard::overlay::process_ranges();
  // The executable is the game's (gmod.exe in a game); nothing of LuaJIT or Remix is loaded in a test.
  CHECK(kind_at(ranges, reinterpret_cast<std::uintptr_t>(&marker_function)) == Kind::game);
  for (const auto& range : ranges) {
    CHECK(range.begin < range.end);
    CHECK(range.kind != Kind::other);
  }
}

TEST_CASE("load activity: LuaJIT's code is executable memory of no module") {
  using nl::engine_guard::overlay::jit_code;
  auto* page = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
  REQUIRE(page != nullptr);
  CHECK(!jit_code(reinterpret_cast<std::uintptr_t>(page)));
  DWORD old = 0;
  REQUIRE(VirtualProtect(page, 0x1000, PAGE_EXECUTE_READ, &old));
  CHECK(jit_code(reinterpret_cast<std::uintptr_t>(page) + 16));
  int local = 0;
  CHECK(!jit_code(reinterpret_cast<std::uintptr_t>(&local)));            // the stack
  CHECK(!jit_code(reinterpret_cast<std::uintptr_t>(&marker_function)));  // a module's code
  CHECK(!jit_code(0));
  VirtualFree(page, 0, MEM_RELEASE);
}

TEST_CASE("load activity: one sample classed by where the main thread runs") {
  const auto none = stack_of({});
  CHECK(classify(Kind::remix, none) == Activity::remix);
  CHECK(classify(Kind::files, none) == Activity::files);
  CHECK(classify(Kind::scripts, none) == Activity::scripts);
  CHECK(classify(Kind::scripts, none, "gamemodes/sandbox/gamemode/spawnmenu/spawnmenu.lua") == Activity::spawnmenu);
  CHECK(classify(Kind::game, none) == Activity::none);
  // The game's code with a Lua file being run further down: that file's work.
  CHECK(classify(Kind::game, none, "lua/autorun/client/x.lua") == Activity::scripts);
  CHECK(classify(Kind::other, none) == Activity::none);
}

TEST_CASE("load activity: a waiting thread is classed by its nearest known caller") {
  // In Windows (or a C runtime) called by Remix, with values of no known module before it.
  CHECK(classify(Kind::other, stack_of({0x99999, 0x1234, 0x15000, 0x75000})) == Activity::remix);
  CHECK(classify(Kind::other, stack_of({0x55010})) == Activity::files);
  CHECK(classify(Kind::other, stack_of({0x35000})) == Activity::scripts);
  // The engine called it (its frame limiter's sleep): the first known caller decides, a deeper Remix value does not.
  CHECK(classify(Kind::other, stack_of({0x75000, 0x15000})) == Activity::none);
  // A caller beyond the scanned part of the stack is not seen.
  std::vector<std::uintptr_t> deep(nl::engine_guard::overlay::kCallerScan / sizeof(std::uintptr_t), 0x99999);
  deep.push_back(0x15000);
  std::vector<std::uint8_t> bytes(deep.size() * sizeof(std::uintptr_t));
  std::memcpy(bytes.data(), deep.data(), bytes.size());
  CHECK(classify(Kind::other, bytes) == Activity::none);
  // A null stack is no caller.
  const auto ranges = fake_ranges();
  CHECK(nl::engine_guard::overlay::classify(Kind::other, nullptr, 64, ranges, "") == Activity::none);
}

TEST_CASE("load activity: the game's code called from Lua is Lua's work") {
  CHECK(classify(Kind::game, stack_of({0x75000, 0x72000, 0x35000})) == Activity::scripts);
  CHECK(classify(Kind::game, stack_of({0x75000, 0x35000}), "lua/autorun/rb655_extended_spawnmenu.lua") ==
        Activity::spawnmenu);
  CHECK(classify(Kind::game, stack_of({0x75000, 0x15000})) == Activity::none);
}

TEST_CASE("load activity: the spawn menu's files") {
  using nl::engine_guard::overlay::spawn_menu_file;
  CHECK(spawn_menu_file("gamemodes/sandbox/gamemode/spawnmenu/creationmenu/content/content.lua"));
  CHECK(spawn_menu_file("addons/x/lua/autorun/rb655_extended_spawnmenu.lua"));
  CHECK(spawn_menu_file("lua/autorun/client/My_Spawn_Menu_Tab.lua"));
  CHECK(!spawn_menu_file("lua/autorun/sh_arc9_autorun.lua"));
  CHECK(!spawn_menu_file(""));
}

TEST_CASE("load activity: the line shows what the last two seconds were mostly") {
  nl::engine_guard::overlay::Recent recent;
  CHECK(recent.shown() == Activity::none);
  recent.add(Activity::scripts);
  CHECK(recent.shown() == Activity::none);  // one sample is not enough
  recent.add(Activity::scripts);
  CHECK(recent.shown() == Activity::scripts);
  for (int i = 0; i < 3; ++i) recent.add(Activity::remix);
  CHECK(recent.shown() == Activity::remix);  // three against two
  recent.add(Activity::scripts);
  CHECK(recent.shown() == Activity::scripts);  // three each: the newer
  // Six samples of nothing: of the last eight one is Remix's and one Lua's, neither often enough.
  for (int i = 0; i < 6; ++i) recent.add(Activity::none);
  CHECK(recent.shown() == Activity::none);
  recent.clear();
  recent.add(Activity::files);
  recent.add(Activity::none);
  recent.add(Activity::files);
  CHECK(recent.shown() == Activity::files);  // nothing in between does not hide it
  recent.clear();
  CHECK(recent.shown() == Activity::none);
}
