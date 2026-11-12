// The colour cap (ADR 0190): the engine's conversion and the cap, the four functions found in an installed game's
// shaderapidx9.dll, no change outside a Remix start, and the module's contract (every realm installs it).
#include "colour_cap.h"
#include "nl_test.h"

#include <windows.h>

#include <cmath>
#include <cstring>
#include <fstream>
#include <limits>
#include <sstream>
#include <string>

namespace cap = nl::engine_guard::colour_cap;

TEST_CASE("colour cap: the engine's conversion wraps above 1, the cap does not") {
  // What shaderapidx9.dll sends Remix for a component (cvttss2si of value * 255, its low byte).
  CHECK(cap::engine_byte(1.0f) == 255);
  CHECK(cap::engine_byte(0.8f) == 204);
  CHECK(cap::engine_byte(0.5f) == 127);
  CHECK(cap::engine_byte(0.0f) == 0);
  CHECK(cap::engine_byte(1.2f) == 50);   // 306: 1.2 reaches Remix as 0.20
  CHECK(cap::engine_byte(1.3f) == 75);   // gm_construct's tree cards, $color2 [1.3 1.4 1.5]
  CHECK(cap::engine_byte(1.4f) == 101);
  CHECK(cap::engine_byte(1.5f) == 126);  // 382: 1.5 reaches Remix as 0.49
  CHECK(cap::engine_byte(1.8f) == 203);  // wrecked_boxcar_gate's $color2
  CHECK(cap::engine_byte(2.0f) == 254);
  CHECK(cap::engine_byte(-0.1f) == 231);  // -25
  // Capped first, every component within [0, 1] reaches the engine as it is, and above 1 is 1.
  for (const float value : {0.0f, 0.1f, 0.25f, 0.5f, 0.8f, 0.999f, 1.0f}) CHECK(cap::cap(value) == value);
  CHECK(cap::cap(1.0001f) == 1.0f);
  CHECK(cap::cap(1.5f) == 1.0f);
  CHECK(cap::cap(1000.0f) == 1.0f);
  CHECK(cap::cap(std::numeric_limits<float>::infinity()) == 1.0f);
  CHECK(cap::cap(-0.1f) == 0.0f);
  CHECK(cap::cap(std::numeric_limits<float>::quiet_NaN()) == 0.0f);  // the engine's conversion also gives 0
  CHECK(cap::engine_byte(std::numeric_limits<float>::quiet_NaN()) == 0);
  for (const float value : {1.2f, 1.3f, 1.5f, 1.8f, 2.0f, 7.0f}) CHECK(cap::engine_byte(cap::cap(value)) == 255);
}

TEST_CASE("colour cap: nothing changes outside a Remix start") {
  if (GetModuleHandleW(L"d3d9.dll")) return;  // never in this test process
  const auto status = cap::install();
  CHECK(!status.installed);
  CHECK(status.reason == "not a Remix start");
  CHECK(!cap::status().enabled);
  CHECK(!cap::set_enabled(true).enabled);
}

TEST_CASE("colour cap: the four functions are found once in an installed game's shaderapidx9.dll") {
  wchar_t path[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"NL_SHADERAPI_DLL", path, MAX_PATH))
    wcscpy_s(path, L"H:\\SteamLibrary\\steamapps\\common\\GarrysMod_PoC\\bin\\win64\\shaderapidx9.dll");
  if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) return;  // no game on this machine (CI)
  // Mapped as an image (sections where they load) but not relocated: the slots hold preferred-base addresses.
  const HMODULE mapped = LoadLibraryExW(path, nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE);
  REQUIRE(mapped != nullptr);
  const auto* base = reinterpret_cast<const std::uint8_t*>(reinterpret_cast<std::uintptr_t>(mapped) & ~std::uintptr_t{3});
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + reinterpret_cast<const IMAGE_DOS_HEADER*>(base)->e_lfanew);
  const std::uintptr_t preferred = nt->OptionalHeader.ImageBase;
  const std::size_t at = cap::find_slots(base, preferred);
  CHECK(at != SIZE_MAX);
  if (at != SIZE_MAX) {
    // Each slot is its own function of the expected kind (the scan already required it; named here).
    const cap::Kind kinds[] = {cap::Kind::colour3f, cap::Kind::colour3fv, cap::Kind::colour4f, cap::Kind::colour4fv};
    struct Context {
      const std::uint8_t* base;
      std::uintptr_t preferred;
    } context{base, preferred};
    const auto read = [](const void* c, std::uintptr_t address, float* value) -> bool {
      const auto* ctx = static_cast<const Context*>(c);
      std::memcpy(value, ctx->base + (address - ctx->preferred), 4);
      return true;
    };
    for (int i = 0; i < 4; ++i) {
      std::uintptr_t pointer = 0;
      std::memcpy(&pointer, base + at + 8 * i, 8);
      CHECK(cap::classify(base + (pointer - preferred), cap::kReach, pointer, read, &context) == kinds[i]);
    }
    // The slot before and after are other functions.
    std::uintptr_t before = 0, after = 0;
    std::memcpy(&before, base + at - 8, 8);
    std::memcpy(&after, base + at + 32, 8);
    CHECK(cap::classify(base + (before - preferred), cap::kReach, before, read, &context) == cap::Kind::none);
    CHECK(cap::classify(base + (after - preferred), cap::kReach, after, read, &context) == cap::Kind::none);
  }
  FreeLibrary(mapped);
}

TEST_CASE("colour cap: the module installs it in every realm and publishes how it went") {
  std::ifstream file(NL_ENGINE_GUARD_MODULE_SOURCE);
  REQUIRE(file.good());
  std::stringstream read;
  read << file.rdbuf();
  const std::string text = read.str();
  const auto open = text.find("GMOD_MODULE_OPEN()");
  REQUIRE(open != std::string::npos);
  const auto call = text.find("colour_cap::install()", open);
  const auto menu = text.find("if (menu) {", open);
  REQUIRE(call != std::string::npos);
  REQUIRE(menu != std::string::npos);
  CHECK(call < menu);
  const auto reason = text.find("SetField(-2, \"colour_cap\")", open);
  const auto function = text.find("SetField(-2, \"ColourCap\")", open);
  CHECK(reason != std::string::npos && reason < menu);
  CHECK(function != std::string::npos && function < menu);
}
