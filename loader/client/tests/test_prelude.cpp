// ADR 0246: the client prelude hook (prelude.h), against a stand-in for the engine's Lua states: an object whose first
// field is its vtable, in this test executable's data, each slot a function of the executable's code.
#include "prelude.h"
#include "nl_test.h"

#include <GarrysMod/Lua/LuaInterface.h>
#include <windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {
namespace prelude = nl::client::prelude;
constexpr std::size_t kSlots = 128;
static_assert(prelude::kRunStringExSlot < kSlots);
// client.dll starts a client realm with call [vtable+0x308] (RESEARCH.md, ADR 0246).
static_assert(prelude::kFindAndRunScriptSlot * sizeof(void*) == 0x308);

// Each slot records its index: a call through the vendored header's ILuaInterface lands in the slot the compiler gives
// that method.
std::size_t last_slot = kSlots;
template <std::size_t N>
std::uintptr_t recorder(void*, std::uintptr_t, std::uintptr_t, std::uintptr_t) {
  last_slot = N;
  return 0;
}
template <std::size_t... I>
void fill(std::array<void*, kSlots>& table, std::index_sequence<I...>) {
  ((table[I] = reinterpret_cast<void*>(&recorder<I>)), ...);
}
// Writable data of this executable, not its code: where the engine's vtable is in lua_shared.dll (read-only there).
std::array<void*, kSlots> header_table{};
std::array<void*, kSlots> hooked_table{};
struct State {
  void** vtable;
};

// The engine's FindAndRunScript as the stand-in has it: records the call and its arguments.
struct Call {
  void* state;
  std::string filename;
  bool run, show;
  std::string source;
  bool no_returns;
};
std::vector<std::string> events;
std::vector<Call> calls;
bool engine_answer = true;
bool engine_find_and_run(void* state, const char* filename, bool run, bool show, const char* source, bool no_returns) {
  events.push_back("engine " + std::string(filename ? filename : "?"));
  calls.push_back({state, filename ? filename : "", run, show, source ? source : "", no_returns});
  return engine_answer;
}
std::vector<void*> runner_states;
bool runner_answer = true;
bool runner(void* state) noexcept {
  events.push_back("prelude");
  runner_states.push_back(state);
  return runner_answer;
}
bool other_runner(void* state) noexcept {
  events.push_back("other prelude");
  runner_states.push_back(state);
  return true;
}
const void* self_module() { return GetModuleHandleW(nullptr); }
}  // namespace

TEST_CASE("client prelude: the vtable slots are the vendored header's (ADR 0246)") {
  fill(header_table, std::make_index_sequence<kSlots>{});
  State state{header_table.data()};
  auto* lua = reinterpret_cast<GarrysMod::Lua::ILuaInterface*>(&state);
  last_slot = kSlots;
  lua->IsClient();
  CHECK(last_slot == prelude::kIsClientSlot);
  last_slot = kSlots;
  lua->FindAndRunScript("includes/init.lua", true, true, "", true);
  CHECK(last_slot == prelude::kFindAndRunScriptSlot);
  last_slot = kSlots;
  lua->RunStringEx("@lua/x.lua", "", "return", true, true, true, true);
  CHECK(last_slot == prelude::kRunStringExSlot);
}

TEST_CASE("client prelude: which calls start a realm, which catalog keys are prelude scripts") {
  CHECK(prelude::starts_realm("includes/init.lua", true));
  CHECK(!prelude::starts_realm("includes/init.lua", false));
  CHECK(!prelude::starts_realm("includes/init_menu.lua", true));
  CHECK(!prelude::starts_realm("lua/includes/init.lua", true));
  CHECK(!prelude::starts_realm("derma/init.lua", true));
  CHECK(!prelude::starts_realm(nullptr, true));
  CHECK(prelude::is_prelude_script("nativeloader/nativeloader/prelude/dxlevel.lua"));
  CHECK(!prelude::is_prelude_script("nativeloader/nativeloader/prelude/sub/dxlevel.lua"));
  CHECK(!prelude::is_prelude_script("nativeloader/nativeloader/prelude/.lua"));
  CHECK(!prelude::is_prelude_script("nativeloader/nativeloader/prelude/dxlevel.txt"));
  CHECK(!prelude::is_prelude_script("nativeloader/nativeloader/menu/multiplayer_notice.lua"));
  CHECK(!prelude::is_prelude_script("remixbinary/nativeloader/prelude/dxlevel.lua"));
  CHECK(!prelude::is_prelude_script("nativeloader/autorun/_nativeloader_guard.lua"));
}

TEST_CASE("client prelude: only where sure; a refusal changes nothing") {
  fill(hooked_table, std::make_index_sequence<kSlots>{});
  State state{hooked_table.data()};
  const auto before = hooked_table;
  CHECK(!prelude::install(nullptr, self_module(), runner).empty());
  CHECK(!prelude::install(&state, nullptr, runner).empty());
  CHECK(!prelude::install(&state, self_module(), nullptr).empty());
  // Not an image: a buffer of this test.
  std::array<unsigned char, 4096> buffer{};
  CHECK(!prelude::install(&state, buffer.data(), runner).empty());
  // A vtable outside the module's image (the heap).
  auto heap = std::make_unique<std::array<void*, kSlots>>(hooked_table);
  State outside{heap->data()};
  CHECK(prelude::install(&outside, self_module(), runner).find("vtable") != std::string::npos);
  // A slot that is not the module's code: FindAndRunScript, then IsClient, then RunStringEx pointing at data.
  for (const auto slot : {prelude::kFindAndRunScriptSlot, prelude::kIsClientSlot, prelude::kRunStringExSlot}) {
    const auto kept = hooked_table[slot];
    hooked_table[slot] = &buffer;
    CHECK(prelude::install(&state, self_module(), runner).find("slot") != std::string::npos);
    hooked_table[slot] = kept;
  }
  CHECK(hooked_table == before);
  CHECK(!prelude::installed());
}

TEST_CASE("client prelude: the runner goes first at a realm's start, and the engine's call goes on unchanged") {
  fill(hooked_table, std::make_index_sequence<kSlots>{});
  hooked_table[prelude::kFindAndRunScriptSlot] = reinterpret_cast<void*>(&engine_find_and_run);
  State state{hooked_table.data()};
  auto* lua = reinterpret_cast<GarrysMod::Lua::ILuaInterface*>(&state);
  REQUIRE(prelude::install(&state, self_module(), runner).empty());
  CHECK(prelude::installed());
  CHECK(hooked_table[prelude::kFindAndRunScriptSlot] != reinterpret_cast<void*>(&engine_find_and_run));
  // Only that slot changed.
  for (std::size_t i = 0; i < kSlots; ++i) {
    if (i != prelude::kFindAndRunScriptSlot) CHECK(hooked_table[i] == reinterpret_cast<void*>(header_table[i]));
  }
  events.clear(); calls.clear(); runner_states.clear();
  const unsigned runs = prelude::runs();
  engine_answer = true;
  CHECK(lua->FindAndRunScript("includes/init.lua", true, false, "!UNKNOWN", true));
  REQUIRE(events.size() == 2);
  CHECK(events[0] == "prelude");
  CHECK(events[1] == "engine includes/init.lua");
  REQUIRE(runner_states.size() == 1);
  CHECK(runner_states[0] == &state);
  REQUIRE(calls.size() == 1);
  CHECK(calls[0].state == &state);
  CHECK(calls[0].run);
  CHECK(!calls[0].show);
  CHECK(calls[0].source == "!UNKNOWN");
  CHECK(calls[0].no_returns);
  CHECK(prelude::runs() == runs + 1);
  // The engine's answer comes back as it is.
  engine_answer = false;
  CHECK(!lua->FindAndRunScript("includes/init.lua", true, true, "", false));
  CHECK(calls.back().no_returns == false);
  engine_answer = true;
  // Other scripts, and a call that does not run its file, reach the engine alone.
  events.clear();
  CHECK(lua->FindAndRunScript("derma/init.lua", true, true, "", true));
  CHECK(lua->FindAndRunScript("includes/init.lua", false, true, "", true));
  REQUIRE(events.size() == 2);
  CHECK(events[0] == "engine derma/init.lua");
  CHECK(events[1] == "engine includes/init.lua");
  // A runner that ran nothing (another realm) is not counted.
  runner_answer = false;
  const unsigned before = prelude::runs();
  lua->FindAndRunScript("includes/init.lua", true, true, "", true);
  CHECK(prelude::runs() == before);
  runner_answer = true;
  // Installing again (another menu state) keeps one hook and only replaces the runner: one prelude, one engine call.
  REQUIRE(prelude::install(&state, self_module(), other_runner).empty());
  events.clear();
  lua->FindAndRunScript("includes/init.lua", true, true, "", true);
  REQUIRE(events.size() == 2);
  CHECK(events[0] == "other prelude");
  CHECK(events[1] == "engine includes/init.lua");
  REQUIRE(prelude::install(&state, self_module(), runner).empty());
}

namespace {
// A stand-in for client.dll's code at a made-up address: `lea rdx, [rip+disp32]` naming `string_address` at `at`, then
// `call` bytes `gap` bytes after it.
std::vector<unsigned char> engine_code(std::uintptr_t code_address, std::uintptr_t string_address, std::size_t at,
                                       std::vector<unsigned char> call, std::size_t gap, unsigned char lea_register = 0x15) {
  std::vector<unsigned char> code(256, 0x90);
  code[at] = 0x48; code[at + 1] = 0x8D; code[at + 2] = lea_register;
  const auto disp = static_cast<std::int32_t>(static_cast<std::intptr_t>(string_address) -
                                              static_cast<std::intptr_t>(code_address + at + 7));
  std::memcpy(code.data() + at + 3, &disp, sizeof disp);
  std::copy(call.begin(), call.end(), code.begin() + static_cast<std::ptrdiff_t>(at + 7 + gap));
  return code;
}
}  // namespace

TEST_CASE("client prelude: client.dll's call that starts a realm is found, and nothing else passes for it") {
  const std::uintptr_t base = 0x180000000, text = 0x180001000, name = 0x18064ba20;
  // client.dll build 26229091: lea rdx, "includes/init.lua"; mov r9b,1; mov [rsp+28h],1; movzx r8d,r9b;
  // mov [rsp+20h],rbx; call qword ptr [rax+308h]: the call 18 bytes after the lea's end.
  const std::vector<unsigned char> rax{0xFF, 0x90, 0x08, 0x03, 0x00, 0x00};
  auto code = engine_code(text, name, 0x10, rax, 18);
  CHECK(prelude::calls_through_slot(code, text, name));
  // Another base register (rcx; r9 with its REX byte) is the same call.
  CHECK(prelude::calls_through_slot(engine_code(text, name, 0x10, {0xFF, 0x91, 0x08, 0x03, 0x00, 0x00}, 0), text, name));
  CHECK(prelude::calls_through_slot(engine_code(text, name, 0x10, {0x41, 0xFF, 0x91, 0x08, 0x03, 0x00, 0x00}, 4), text, name));
  // Not it: another slot, a call too far after the lea, another string, the name in another register, a SIB form.
  CHECK(!prelude::calls_through_slot(engine_code(text, name, 0x10, {0xFF, 0x90, 0x10, 0x03, 0x00, 0x00}, 18), text, name));
  CHECK(!prelude::calls_through_slot(engine_code(text, name, 0x10, rax, 70), text, name));
  CHECK(!prelude::calls_through_slot(code, text, name + 16));
  CHECK(!prelude::calls_through_slot(engine_code(text, name, 0x10, rax, 18, 0x0D), text, name));
  CHECK(!prelude::calls_through_slot(engine_code(text, name, 0x10, {0xFF, 0x94, 0x24, 0x08, 0x03, 0x00, 0x00}, 18), text, name));
  // Code that ends inside the instruction is read no further than its end.
  code.resize(0x10 + 7 + 18 + 3);
  CHECK(!prelude::calls_through_slot(code, text, name));
  CHECK(!prelude::calls_through_slot({}, text, name));
  (void)base;
}

TEST_CASE("client prelude: confirming the engine's call refuses what is not client.dll") {
  CHECK(prelude::confirm_engine_call(nullptr) == "client.dll is not loaded");
  std::array<unsigned char, 4096> buffer{};
  CHECK(prelude::confirm_engine_call(buffer.data()) == "client.dll is not a 64-bit image");
  // A real client.dll, where the environment names one (NL_CLIENT_DLL): mapped as an image, never run.
  wchar_t path[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"NL_CLIENT_DLL", path, MAX_PATH)) return;
  const auto handle = LoadLibraryExW(path, nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE);
  REQUIRE(handle != nullptr);
  const auto* mapped = reinterpret_cast<const void*>(reinterpret_cast<std::uintptr_t>(handle) & ~std::uintptr_t{3});
  CHECK(prelude::confirm_engine_call(mapped).empty());
  FreeLibrary(handle);
}
