// End to end (ADR 0130), in a process of its own: the guard finds the call site in a stand-in
// materialsystem.dll (fake_materialsystem.cpp), rewrites it to its stub, and the stand-in's own code then
// gets "" for a fallback that names the material itself and the fallback for any other.
#include "guard.h"
#include "nl_test.h"
#include <windows.h>
#include <cstdint>
#include <cstring>
#include <string>

namespace g = nl::engine_guard;
namespace {
// A material as the engine's loop sees it: GetName is its first virtual function.
struct Material {
  virtual const char* GetName() const { return name; }
  const char* name;
  explicit Material(const char* n) : name(n) {}
};
struct Keys {
  const char* fallback;  // what the stand-in GetString returns
};
using Initialize = const char* (*)(void* key_values, void* material);

struct StandIn {
  HMODULE module = nullptr;
  const std::uint8_t* code = nullptr;
};
const StandIn& stand_in() {
  static const StandIn loaded = [] {
    StandIn s;
    s.module = LoadLibraryW(L"materialsystem.dll");  // the stand-in beside this test
    if (!s.module) return s;
    using Code = const void* (*)();
    const auto code = reinterpret_cast<Code>(GetProcAddress(s.module, "nl_fake_initialize_code"));
    s.code = code ? static_cast<const std::uint8_t*>(code()) : nullptr;
    return s;
  }();
  return loaded;
}
const char* initialize(Keys& keys, Material& material) {
  return reinterpret_cast<Initialize>(const_cast<std::uint8_t*>(stand_in().code))(&keys, &material);
}
}  // namespace

TEST_CASE("engine guard end to end: the stand-in loop gets no fallback to itself once detoured") {
  REQUIRE(stand_in().module != nullptr);
  REQUIRE(stand_in().code != nullptr);
  Material self("models/test/self"), other("models/test/other");
  Keys to_self{"models/test/self"}, to_other{"models/test/other_dx8"};
  // Before: the call site returns what GetString returns, so the engine would follow it forever.
  CHECK(std::string(initialize(to_self, self)) == "models/test/self");

  const auto status = g::install();
  REQUIRE(status.installed);
  CHECK(status.reason == "installed");
  const auto base = reinterpret_cast<std::uintptr_t>(stand_in().module);
  CHECK(status.site_rva == reinterpret_cast<std::uintptr_t>(stand_in().code) + 0x23 - base);
  // The call now leads out of the image, to the stub within a call's reach.
  std::int32_t relative = 0;
  std::memcpy(&relative, stand_in().code + 0x24, 4);
  const auto target = reinterpret_cast<std::uintptr_t>(stand_in().code) + 0x28 + relative;
  CHECK(g::is_stub(reinterpret_cast<const std::uint8_t*>(target)));

  CHECK(std::string(initialize(to_self, self)).empty());
  CHECK(std::string(initialize(to_other, other)) == "models/test/other_dx8");
  CHECK(std::string(initialize(to_other, other)) == "models/test/other_dx8");
  const auto after = g::status();
  CHECK(after.cut == 1);
  CHECK(after.last_material == "models/test/self");
  CHECK(after.last_fallback == "models/test/self");

  // Installing again changes nothing.
  CHECK(g::install().installed);
  CHECK(std::string(initialize(to_self, self)).empty());
  CHECK(g::status().cut == 2);
}
