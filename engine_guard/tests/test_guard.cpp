// The engine guard's decisions, its pattern against the real materialsystem.dll when one is installed,
// and the watchdog's stack scan and report (ADR 0130).
#include "guard.h"
#include "nl_test.h"
#include "watchdog.h"
#include <windows.h>
#include <cstring>
#include <string>
#include <vector>

namespace g = nl::engine_guard;
namespace w = nl::engine_guard::watchdog;
namespace {
// The call site's bytes as GMod build 26439081 has them (materialsystem.dll rva 0xfb42).
const std::vector<std::uint8_t> kRealSite = {
    0x4c, 0x8d, 0x05, 0x41, 0x50, 0x0a, 0x00, 0x49, 0x8b, 0xcd, 0x48, 0x8d, 0x15, 0x9d, 0x5e, 0x0a, 0x00, 0xe8, 0x78, 0x35,
    0x06, 0x00, 0x8b, 0x7c, 0x24, 0x40, 0x44, 0x8b, 0x64, 0x24, 0x44, 0x80, 0x38, 0x00, 0x0f, 0x84, 0xe6, 0xfd, 0xff, 0xff};

// A material as the engine's loop sees it: GetName is its first virtual function.
struct FakeMaterial {
  virtual const char* GetName() const { return name; }
  const char* name;
  explicit FakeMaterial(const char* n) : name(n) {}
};

// Key values standing in for KeyValues: the fallback each "VMT" names.
struct FakeKeys {
  const char* fallback;
};
const char* fake_get_string(void* key_values, const char* key, const char* default_value) {
  if (std::strcmp(key, "$fallbackmaterial") != 0) return default_value;
  return static_cast<FakeKeys*>(key_values)->fallback;
}
}  // namespace

TEST_CASE("engine guard: the pattern finds the real call site once, wildcards covering displacements") {
  std::vector<std::uint8_t> code(4096, 0xCC);
  std::memcpy(code.data() + 1000, kRealSite.data(), kRealSite.size());
  const auto hits = g::find(code.data(), code.size(), g::call_site_pattern());
  REQUIRE(hits.size() == 1);
  CHECK(hits[0] == 1000);
  CHECK(code[hits[0] + g::kCallOffset] == 0xE8);
  CHECK(code[hits[0] + g::kKeyLeaOffset] == 0x48);
  // Other displacements still match; another register or compare does not.
  code[1000 + 3] = 0x11;
  code[1000 + 18] = 0x22;
  CHECK(g::find(code.data(), code.size(), g::call_site_pattern()).size() == 1);
  code[1000 + 9] = 0xCE;  // mov rcx,r14 instead of r13
  CHECK(g::find(code.data(), code.size(), g::call_site_pattern()).empty());
  code[1000 + 9] = 0xCD;
  std::memcpy(code.data() + 3000, kRealSite.data(), kRealSite.size());
  CHECK(g::find(code.data(), code.size(), g::call_site_pattern()).size() == 2);  // install() then refuses
}

TEST_CASE("engine guard: names compare as the engine finds materials") {
  CHECK(g::normalize("Materials\\Particle\\Warp5_Explosion.VMT") == "particle/warp5_explosion");
  CHECK(g::normalize("/particle/warp5_explosion") == "particle/warp5_explosion");
  CHECK(g::same_material("particle/warp5_explosion", "materials/particle/warp5_explosion.vmt"));
  CHECK(!g::same_material("particle/warp5_explosion", "particle/warp5_explosion2"));
  CHECK(!g::same_material("", ""));
}

TEST_CASE("engine guard: a fallback to itself is never followed; a cycle stops after sixteen hops") {
  g::Tracker tracker;
  const int a = 0, b = 0;
  CHECK(g::decide(tracker, &a, "particle/warp5_explosion", "particle/warp5_explosion", 1000) == g::Verdict::self);
  // A cycle through other materials (b, c, b, c...): sixteen followed, the seventeenth cut, even when each
  // hop takes most of the window (a slow disk).
  std::uint64_t now = 1000;
  for (unsigned hop = 1; hop <= g::kMaxHops; ++hop, now += g::kWindowMs - 1)
    CHECK(g::decide(tracker, &a, "x/a", hop % 2 ? "x/b" : "x/c", now) == g::Verdict::follow);
  CHECK(g::decide(tracker, &a, "x/a", "x/b", now) == g::Verdict::too_many);
  // Another material, or the same one after a pause, starts again.
  CHECK(g::decide(tracker, &b, "x/z", "x/y", now + 1) == g::Verdict::follow);
  g::Tracker later;
  CHECK(g::decide(later, &a, "x/a", "x/b", 1000) == g::Verdict::follow);
  CHECK(g::decide(later, &a, "x/a", "x/b", 1000 + g::kWindowMs + 1) == g::Verdict::follow);
  CHECK(later.hops == 1);
}

TEST_CASE("engine guard: an empty fallback ends a chain, so separate initializations never add up") {
  g::Tracker tracker;
  const int a = 0;
  for (int init = 0; init < 40; ++init) {  // the same material initialized again and again, one hop each
    CHECK(g::decide(tracker, &a, "x/a", "x/a_dx8", 1000 + init) == g::Verdict::follow);
    CHECK(g::decide(tracker, &a, "x/a", "", 1000 + init) == g::Verdict::follow);  // x/a_dx8 has none
  }
  CHECK(tracker.material == nullptr);
}

TEST_CASE("engine guard: the filter answers an empty fallback only where the loop would cycle") {
  FakeMaterial warp("particle/warp5_explosion");
  FakeMaterial ordinary("models/props/crate");
  FakeKeys self{"particle/warp5_explosion"};
  FakeKeys other{"models/props/crate_dx80"};
  FakeKeys none{""};
  g::Tracker tracker;
  CHECK(std::string(g::filter(fake_get_string, &self, "$fallbackmaterial", "", &warp, tracker, 10)).empty());
  CHECK(std::string(g::filter(fake_get_string, &other, "$fallbackmaterial", "", &ordinary, tracker, 20)) ==
        "models/props/crate_dx80");
  CHECK(std::string(g::filter(fake_get_string, &none, "$fallbackmaterial", "", &ordinary, tracker, 30)).empty());
  // Another key goes straight through, even with a value that names the material.
  CHECK(std::string(g::filter(fake_get_string, &self, "$basetexture", "particle/warp5_explosion", &warp, tracker, 40)) ==
        "particle/warp5_explosion");
  // Without a material (never in the loop) the value is returned as it is.
  CHECK(std::string(g::filter(fake_get_string, &self, "$fallbackmaterial", "", nullptr, tracker, 50)) ==
        "particle/warp5_explosion");
  // A two-material cycle, a -> b -> a, stops when it comes back to the material.
  FakeMaterial a("cycle/a");
  FakeKeys to_b{"cycle/b"}, to_a{"cycle/a"};
  g::Tracker cycle;
  CHECK(std::string(g::filter(fake_get_string, &to_b, "$fallbackmaterial", "", &a, cycle, 100)) == "cycle/b");
  CHECK(std::string(g::filter(fake_get_string, &to_a, "$fallbackmaterial", "", &a, cycle, 101)).empty());
  CHECK(g::status().cut >= 2);
}

TEST_CASE("engine guard: the stub moves the material into the fourth argument and jumps to the hook") {
  const auto bytes = g::stub(0x1122334455667788ull);
  const std::vector<std::uint8_t> expected = {0x4D, 0x89, 0xF1, 0x48, 0xB8, 0x88, 0x77, 0x66, 0x55,
                                              0x44, 0x33, 0x22, 0x11, 0xFF, 0xE0};
  CHECK(bytes == expected);
  CHECK(g::is_stub(bytes.data()));
  std::vector<std::uint8_t> other(bytes);
  other[2] = 0xF2;
  CHECK(!g::is_stub(other.data()));
}

TEST_CASE("engine guard: install refuses cleanly without materialsystem.dll") {
  if (GetModuleHandleW(L"materialsystem.dll")) return;  // never in this test process
  const auto status = g::install();
  CHECK(!status.installed);
  CHECK(status.reason.find("materialsystem.dll") != std::string::npos);
}

TEST_CASE("engine guard: the pattern occurs once in an installed game's materialsystem.dll") {
  wchar_t path[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"NL_MATERIALSYSTEM_DLL", path, MAX_PATH))
    wcscpy_s(path, L"H:\\SteamLibrary\\steamapps\\common\\GarrysMod_PoC\\bin\\win64\\materialsystem.dll");
  if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) return;  // no game on this machine (CI)
  const HMODULE mapped = LoadLibraryExW(path, nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE);
  REQUIRE(mapped != nullptr);
  auto* base = reinterpret_cast<std::uint8_t*>(reinterpret_cast<std::uintptr_t>(mapped) & ~std::uintptr_t{3});
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + reinterpret_cast<IMAGE_DOS_HEADER*>(base)->e_lfanew);
  const auto* section = IMAGE_FIRST_SECTION(nt);
  std::size_t count = 0;
  std::uint8_t* site = nullptr;
  for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section) {
    if (!(section->Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
    for (const auto at : g::find(base + section->VirtualAddress, section->Misc.VirtualSize, g::call_site_pattern(), 4)) {
      ++count;
      site = base + section->VirtualAddress + at;
    }
  }
  CHECK(count == 1);
  if (site) {
    // r14 is the material: the loop calls its GetName within reach after the call.
    CHECK(g::find(site + g::kCallOffset, g::kGetNameReach, g::get_name_call_pattern(), 4).size() == 2);
    std::int32_t displacement = 0;
    std::memcpy(&displacement, site + g::kKeyLeaOffset + 3, 4);
    CHECK(std::strcmp(reinterpret_cast<const char*>(site + g::kKeyLeaOffset + 7 + displacement), "$fallbackmaterial") == 0);
  }
  FreeLibrary(mapped);
}

TEST_CASE("watchdog: Lua chunk names on a stack, nearest first, without duplicates") {
  std::string stack;
  stack += std::string(16, '\0') + "@lua/autorun/sh_arc9_autorun.lua" + std::string(8, '\0');
  stack += "xx arc9/shared/sh_csgo_effects.lua\x01" + std::string(4, '\0');
  stack += "@lua/autorun/sh_arc9_autorun.lua" + std::string(4, '\0');  // a duplicate
  stack += "materials/particle/warp5_explosion.vmt" + std::string(4, '\0');  // not Lua
  stack += "file.luac" + std::string(4, '\0') + "a.lua" + std::string(4, '\0');  // compiled, no folder
  const auto names = w::lua_names(reinterpret_cast<const std::uint8_t*>(stack.data()), stack.size(), 8);
  REQUIRE(names.size() == 2);
  CHECK(names[0] == "@lua/autorun/sh_arc9_autorun.lua");
  CHECK(names[1] == "arc9/shared/sh_csgo_effects.lua");
  CHECK(w::lua_names(reinterpret_cast<const std::uint8_t*>(stack.data()), stack.size(), 1).size() == 1);
}

TEST_CASE("watchdog: the report's JSON text has its fields and escaped names") {
  std::vector<w::Sample> samples(1);
  samples[0].where = "materialsystem.dll+0xfb53";
  samples[0].names = {"@lua/autorun/a\"b.lua", "x\\y.lua"};
  const auto json = w::report_json("2026-11-08T12:00:00Z", "server", 95000, samples, 3);
  CHECK(json.find("\"realm\":\"server\"") != std::string::npos);
  CHECK(json.find("\"stalled_seconds\":95") != std::string::npos);
  CHECK(json.find("\"guard_cut\":3") != std::string::npos);
  CHECK(json.find("a\\\"b.lua") != std::string::npos);
  CHECK(json.find("x\\\\y.lua") != std::string::npos);
  CHECK(w::json_string(std::string("a\x01")) == "\"a\\u0001\"");
}
