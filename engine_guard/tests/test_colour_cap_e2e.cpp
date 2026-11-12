// End to end (ADR 0190), in a process of its own: a stand-in shaderapidx9.dll (fake_shaderapi.cpp/.asm) whose four
// colour functions wrap above 1 as the game's do, and a stand-in Remix d3d9.dll. Called through the API's vtable,
// as the shaders call them, they send the device a wrapped texture factor before the colour cap is installed and a
// capped one after; values within [0, 1] are the same either way. Also: the switch, idempotence, and a function
// whose code differs from the shape is not taken.
#include "colour_cap.h"
#include "nl_test.h"

#include <windows.h>

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace cap = nl::engine_guard::colour_cap;
namespace {
using Colour3f = void (*)(void*, float, float, float);
using Colour3fv = void (*)(void*, const float*);
using Colour4f = void (*)(void*, float, float, float, float);
using Colour4fv = void (*)(void*, const float*);

struct StandIn {
  HMODULE shaderapi = nullptr;
  void* api = nullptr;
  void* const* vtable = nullptr;
  std::uint32_t (*factor)() = nullptr;
  std::uint32_t (*state)() = nullptr;
  const void* (*code)(int) = nullptr;  // what a slot held at load
};
const StandIn& stand_in() {
  static const StandIn loaded = [] {
    StandIn s;
    const std::wstring folder = NL_COLOUR_FAKES_DIR;
    s.shaderapi = LoadLibraryW((folder + L"\\shaderapidx9.dll").c_str());
    if (!s.shaderapi) return s;
    s.api = reinterpret_cast<void* (*)()>(GetProcAddress(s.shaderapi, "nl_fake_api"))();
    s.vtable = reinterpret_cast<void* const* (*)()>(GetProcAddress(s.shaderapi, "nl_fake_vtable"))();
    s.factor = reinterpret_cast<std::uint32_t (*)()>(GetProcAddress(s.shaderapi, "nl_fake_factor"));
    s.state = reinterpret_cast<std::uint32_t (*)()>(GetProcAddress(s.shaderapi, "nl_fake_state"));
    s.code = reinterpret_cast<const void* (*)(int)>(GetProcAddress(s.shaderapi, "nl_fake_code"));
    return s;
  }();
  return loaded;
}

// A virtual call: the slot is read from the object's vtable at the call, as the game's shaders do.
void* slot(int index) { return (*static_cast<void* const* const*>(stand_in().api))[index]; }
std::uint32_t colour3f(float r, float g, float b) {
  reinterpret_cast<Colour3f>(slot(2))(stand_in().api, r, g, b);
  return stand_in().factor();
}
std::uint32_t colour3fv(const float* rgb) {
  reinterpret_cast<Colour3fv>(slot(3))(stand_in().api, rgb);
  return stand_in().factor();
}
std::uint32_t colour4f(float r, float g, float b, float a) {
  reinterpret_cast<Colour4f>(slot(4))(stand_in().api, r, g, b, a);
  return stand_in().factor();
}
std::uint32_t colour4fv(const float* rgba) {
  reinterpret_cast<Colour4fv>(slot(5))(stand_in().api, rgba);
  return stand_in().factor();
}
std::uint32_t argb(std::uint32_t a, std::uint32_t r, std::uint32_t g, std::uint32_t b) {
  return (a << 24) | (r << 16) | (g << 8) | b;
}

bool any_float(const void*, std::uintptr_t, float* value) {
  *value = 255.0f;
  return true;
}
bool other_float(const void*, std::uintptr_t, float* value) {
  *value = 256.0f;
  return true;
}
}  // namespace

TEST_CASE("colour cap end to end: wrapped before, capped after, unchanged within [0, 1]") {
  REQUIRE(stand_in().shaderapi != nullptr);
  REQUIRE(stand_in().api != nullptr);
  REQUIRE(stand_in().code != nullptr);
  for (int i = 0; i < 8; ++i) REQUIRE(slot(i) == stand_in().code(i));
  const float tree[3] = {1.3f, 1.4f, 1.5f}, within[4] = {0.25f, 0.5f, 0.75f, 1.0f}, over[4] = {0.8f, 1.5f, 0.2f, 1.2f};

  // Before: the stand-in wraps as the game does.
  CHECK(colour3f(1.5f, 1.5f, 1.5f) == argb(0xFF, 126, 126, 126));
  CHECK(stand_in().state() == cap::kTextureFactor);
  CHECK(colour3fv(tree) == argb(0xFF, 75, 101, 126));
  CHECK(colour4f(1.5f, 0.5f, 0.5f, 1.0f) == argb(255, 126, 127, 127));
  CHECK(colour4fv(over) == argb(50, 204, 126, 51));
  const std::uint32_t within_before = colour4fv(within);
  CHECK(within_before == argb(255, 63, 127, 191));
  CHECK(colour3f(0.8f, 0.5f, 0.0f) == argb(0xFF, 204, 127, 0));

  // Not a Remix start: nothing changes.
  const auto refused = cap::install();
  CHECK(!refused.installed);
  CHECK(refused.reason == "not a Remix start");
  CHECK(colour3f(1.5f, 1.5f, 1.5f) == argb(0xFF, 126, 126, 126));

  const HMODULE d3d9 = LoadLibraryW((std::wstring(NL_COLOUR_FAKES_DIR) + L"\\d3d9.dll").c_str());
  REQUIRE(d3d9 != nullptr);
  const auto status = cap::install();
  REQUIRE(status.installed);
  CHECK(status.reason == "installed");
  CHECK(status.enabled);
  const auto base = reinterpret_cast<std::uintptr_t>(stand_in().shaderapi);
  CHECK(status.slots_rva == reinterpret_cast<std::uintptr_t>(stand_in().vtable) + 2 * 8 - base);
  // The four slots lead out of the stand-in now; the other slots are as they were.
  for (int i = 2; i < 6; ++i) CHECK(slot(i) != stand_in().code(i));
  for (const int i : {0, 1, 6, 7}) CHECK(slot(i) == stand_in().code(i));

  // After: above 1 is 1 (and below 0 is 0); within [0, 1] the same bytes as before.
  CHECK(colour3f(1.5f, 1.5f, 1.5f) == argb(0xFF, 255, 255, 255));
  CHECK(stand_in().state() == cap::kTextureFactor);
  CHECK(colour3fv(tree) == argb(0xFF, 255, 255, 255));
  CHECK(colour4f(1.5f, 0.5f, 0.5f, 1.0f) == argb(255, 255, 127, 127));
  CHECK(colour4fv(over) == argb(255, 204, 255, 51));
  CHECK(colour4f(-0.5f, 2.0f, 0.5f, 0.5f) == argb(127, 0, 255, 127));
  const std::uint64_t capped = cap::status().capped;
  CHECK(capped == 5);
  CHECK(colour4fv(within) == within_before);
  CHECK(colour3f(0.8f, 0.5f, 0.0f) == argb(0xFF, 204, 127, 0));
  CHECK(cap::status().capped == capped);  // within [0, 1]: not counted
  CHECK(tree[0] == 1.3f && over[1] == 1.5f);  // the caller's colour is never written

  // The switch, for a comparison in one session.
  CHECK(!cap::set_enabled(false).enabled);
  CHECK(colour3f(1.5f, 1.5f, 1.5f) == argb(0xFF, 126, 126, 126));
  CHECK(cap::set_enabled(true).enabled);
  CHECK(colour3f(1.5f, 1.5f, 1.5f) == argb(0xFF, 255, 255, 255));

  // Installing again changes nothing.
  const auto again = cap::install();
  CHECK(again.installed);
  CHECK(again.slots_rva == status.slots_rva);
  CHECK(colour3fv(tree) == argb(0xFF, 255, 255, 255));
}

TEST_CASE("colour cap end to end: a function of another shape is not one of the four") {
  REQUIRE(stand_in().shaderapi != nullptr);
  // The stand-in's own Color3fv, copied: its code as it is, then changed in one place at a time.
  const auto* code = static_cast<const std::uint8_t*>(stand_in().code(3));
  std::vector<std::uint8_t> copy(code, code + cap::kReach);
  CHECK(cap::classify(copy.data(), copy.size(), 0, any_float, nullptr) == cap::Kind::colour3fv);
  CHECK(cap::classify(copy.data(), copy.size(), 0, other_float, nullptr) == cap::Kind::none);  // not * 255
  auto change = [&](const std::vector<std::uint8_t>& from, const std::vector<std::uint8_t>& to) {
    std::vector<std::uint8_t> changed(copy);
    for (std::size_t i = 0; i + from.size() <= changed.size(); ++i) {
      if (std::memcmp(changed.data() + i, from.data(), from.size()) == 0) {
        std::memcpy(changed.data() + i, to.data(), to.size());
        return cap::classify(changed.data(), changed.size(), 0, any_float, nullptr);
      }
    }
    return cap::Kind::colour3fv;  // not found: the test below fails
  };
  CHECK(change({0xBA, 0x3C, 0, 0, 0}, {0xBA, 0x3D, 0, 0, 0}) == cap::Kind::none);  // another render state
  CHECK(change({0xFF, 0x90, 0xC8, 0x01}, {0xFF, 0x90, 0xD0, 0x01}) == cap::Kind::none);  // another device call
  CHECK(change({0x81, 0xCB, 0, 0, 0, 0xFF}, {0x81, 0xCB, 0, 0, 0, 0x7F}) == cap::Kind::none);  // alpha not FF
  // Color3f, Color4f and Color4fv are told apart.
  const auto* three = static_cast<const std::uint8_t*>(stand_in().code(2));
  const auto* four = static_cast<const std::uint8_t*>(stand_in().code(4));
  const auto* four_v = static_cast<const std::uint8_t*>(stand_in().code(5));
  CHECK(cap::classify(three, cap::kReach, 0, any_float, nullptr) == cap::Kind::colour3f);
  CHECK(cap::classify(four, cap::kReach, 0, any_float, nullptr) == cap::Kind::colour4f);
  CHECK(cap::classify(four_v, cap::kReach, 0, any_float, nullptr) == cap::Kind::colour4fv);
  CHECK(cap::classify(nullptr, 0, 0, any_float, nullptr) == cap::Kind::none);
}
