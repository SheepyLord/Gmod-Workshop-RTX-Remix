#include "poll.h"
#include "nl/fs.h"
#include "nl_test.h"

#include <cstddef>
#include <string>
#include <string_view>

namespace {
std::string module_source() { return nl::fs::read_file(NL_CLIENT_MODULE_SOURCE, std::size_t{1} << 20); }

// The function that starts at `signature`, up to its closing brace in the first column.
std::string body(const std::string& text, std::string_view signature) {
  const auto begin = text.find(signature);
  if (begin == std::string::npos) return {};
  const auto end = text.find("\n}", begin + signature.size());
  return text.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
}
}

TEST_CASE("client poll: checks are throttled and a realm gets a bounded number of attempts") {
  nl::client::PollGate gate;
  CHECK(gate.due(1000));
  CHECK(!gate.due(1000));
  CHECK(!gate.due(1000 + nl::client::kPollIntervalMs - 1));
  CHECK(gate.due(1000 + nl::client::kPollIntervalMs));
  CHECK(!nl::client::attempt_allowed(0));
  CHECK(nl::client::attempt_allowed(1));
  CHECK(nl::client::attempt_allowed(nl::client::kMaxClientAttempts));
  CHECK(!nl::client::attempt_allowed(nl::client::kMaxClientAttempts + 1));
  // About two minutes of a realm without a valid local player, then the module gives up.
  static_assert(nl::client::kMaxClientAttempts * nl::client::kPollIntervalMs == 120000);
}

TEST_CASE("client module: the client realm is reached only raw and inside a protected call") {
  const auto text = module_source();
  // Server Lua can set metamethods on the client's _G: no field access through them, and the
  // temporary API is never published with SetField.
  CHECK(text.find("client->GetField(") == std::string::npos);
  CHECK(text.find("client->SetField(") == std::string::npos);
  CHECK(text.find("SetField(GarrysMod::Lua::INDEX_GLOBAL, \"__NATIVELOADER_CLIENT_API\")") == std::string::npos);
  const auto initialize = body(text, "LUA_FUNCTION_STATIC(InitializeClient)");
  REQUIRE(!initialize.empty());
  CHECK(initialize.find("GetField(") == std::string::npos);
  CHECK(initialize.find("SetField(") == std::string::npos);
  CHECK(initialize.find("raw_set(LUA, GarrysMod::Lua::SPECIAL_GLOB, kApi)") != std::string::npos);
  CHECK(initialize.find("RunStringEx(") != std::string::npos);
  CHECK(initialize.find("attempt_allowed(") != std::string::npos);
  // Poll touches the client realm only to push and protect-call the initializing step.
  const auto poll = body(text, "LUA_FUNCTION_STATIC(Poll)");
  REQUIRE(!poll.empty());
  CHECK(poll.find("client->PushCFunction(InitializeClient)") != std::string::npos);
  CHECK(poll.find("client->PCall(0, 0, 0)") != std::string::npos);
  CHECK(poll.find("RunStringEx(") == std::string::npos);
  CHECK(poll.find("gate.due(") != std::string::npos);
}

TEST_CASE("client module: the helper pins itself before handing out callbacks") {
  const auto text = module_source();
  const auto pin = text.find("GET_MODULE_HANDLE_EX_FLAG_PIN");
  const auto hook = text.find("hook(LUA, true);");
  REQUIRE(pin != std::string::npos);
  REQUIRE(hook != std::string::npos);
  CHECK(pin < hook);
}

TEST_CASE("client module: menu scripts are the companion's own verified files, run once with a narrow API (R24)") {
  const auto text = module_source();
  CHECK(text.find("kMenuScripts = \"nativeloader/nativeloader/menu/\"") != std::string::npos);
  CHECK(text.find("kMenuReadable = \"nativeloader/\"") != std::string::npos);
  // The read callback answers only in the menu realm, only for the companion's catalog entries.
  const auto read = body(text, "LUA_FUNCTION_STATIC(MenuRead)");
  REQUIRE(!read.empty());
  CHECK(read.find("LUA != menu") != std::string::npos);
  CHECK(read.find("key.starts_with(kMenuReadable)") != std::string::npos);
  CHECK(read.find("catalog->scripts.find(key)") != std::string::npos);
  // Only direct children of the menu folder run, and the API is gone once they have.
  const auto run = body(text, "unsigned run_menu_scripts(ILuaBase* lua)");
  REQUIRE(!run.empty());
  CHECK(run.find("name.starts_with(kMenuScripts)") != std::string::npos);
  CHECK(run.find("name.find('/', kMenuScripts.size()) != std::string::npos") != std::string::npos);
  const auto ran = run.find("RunStringEx(");
  const auto cleared = run.rfind("lua->PushNil();");
  REQUIRE(ran != std::string::npos);
  REQUIRE(cleared != std::string::npos);
  CHECK(ran < cleared);
  CHECK(run.find("SetField(GarrysMod::Lua::INDEX_GLOBAL, kMenuApi)", cleared) != std::string::npos);
  // They run once, after the module is pinned and verified, never from the client realm's poll.
  const auto pin = text.find("GET_MODULE_HANDLE_EX_FLAG_PIN");
  const auto call = text.find("run_menu_scripts(LUA)");
  REQUIRE(call != std::string::npos);
  CHECK(pin < call);
  CHECK(body(text, "LUA_FUNCTION_STATIC(Poll)").find("run_menu_scripts") == std::string::npos);
}

TEST_CASE("client module: only the engine's own menu state takes the menu's part (R24 review)") {
  const auto text = module_source();
  // Any realm's Lua can set MENU_DLL; a server realm that passed for the menu would take over `menu` and, when it
  // closed, end the catalog for the session.
  const auto state = body(text, "bool is_menu_state(ILuaBase* lua)");
  REQUIRE(!state.empty());
  CHECK(state.find("GetLuaInterface(GarrysMod::Lua::State::MENU)") != std::string::npos);
  CHECK(state.find("== lua") != std::string::npos);
  const auto open = body(text, "GMOD_MODULE_OPEN()");
  REQUIRE(!open.empty());
  const auto check = open.find("!is_menu_state(LUA)) return 0;");
  REQUIRE(check != std::string::npos);
  CHECK(check < open.find("menu = LUA;"));
}

TEST_CASE("client module: former RTX files are archived only in a verified RTX start, before its callbacks (ADR 0188)") {
  const auto text = module_source();
  const auto verified = text.find("catalog = std::move(snapshot);");
  const auto archive = text.find("status += archive_former_rtx(root, *journal);");
  const auto hook = text.find("hook(LUA, true);");
  REQUIRE(verified != std::string::npos);
  REQUIRE(archive != std::string::npos);
  REQUIRE(hook != std::string::npos);
  CHECK(verified < archive);
  CHECK(archive < hook);
  // Whatever the archive meets, the module goes on: it only adds to the status line.
  const auto helper = body(text, "std::string archive_former_rtx(");
  REQUIRE(!helper.empty());
  CHECK(helper.find("catch (const std::exception& error)") != std::string::npos);
}

TEST_CASE("client module: adopted former RTX files move only when the menu state closes without a client realm (ADR 0188)") {
  const auto text = module_source();
  const auto close = body(text, "GMOD_MODULE_CLOSE()");
  REQUIRE(!close.empty());
  CHECK(close.find("release_adopted_files();") != std::string::npos);
  const auto release = body(text, "void release_adopted_files() noexcept");
  REQUIRE(!release.empty());
  CHECK(release.find("GetLuaInterface(GarrysMod::Lua::State::CLIENT)") != std::string::npos);
  CHECK(release.find("verified_root.empty()") != std::string::npos);
  CHECK(release.find("another_game_running(verified_root)") != std::string::npos);
  CHECK(release.find("journal->pending") != std::string::npos);
  CHECK(release.find("catch (...)") != std::string::npos);
}

TEST_CASE("client module: the add-on list changes only the verified RTX item, from the menu realm (ADR 0189)") {
  const auto text = module_source();
  const auto list = body(text, "LUA_FUNCTION_STATIC(MenuAddonList)");
  REQUIRE(!list.empty());
  CHECK(list.find("LUA != menu") != std::string::npos);
  CHECK(list.find("GetString(") == std::string::npos);  // no id or path from Lua
  CHECK(list.find("add_to_addon_list(verified_root, rtx_item)") != std::string::npos);
  CHECK(list.find("remove_from_addon_list(verified_root, rtx_item)") != std::string::npos);
  CHECK(list.find("listed_by_us") != std::string::npos);  // only its own entry is taken out again
  CHECK(list.find("catch (const std::exception& error)") != std::string::npos);
  const auto item = body(text, "std::string workshop_item(const nl::journal::Generation& generation)");
  REQUIRE(!item.empty());
  CHECK(item.find("package.source != \"workshop\"") != std::string::npos);
  const auto run = body(text, "unsigned run_menu_scripts(ILuaBase* lua)");
  CHECK(run.find("lua->PushCFunction(MenuAddonList); lua->SetField(-2, \"rtx_addon_list\");") != std::string::npos);
}

TEST_CASE("client module: Steam's switch is read for the verified RTX item only, from the menu realm (ADR 0189)") {
  const auto text = module_source();
  const auto state = body(text, "LUA_FUNCTION_STATIC(MenuSteamState)");
  REQUIRE(!state.empty());
  CHECK(state.find("LUA != menu") != std::string::npos);
  CHECK(state.find("GetString(") == std::string::npos);  // no id from Lua
  CHECK(state.find("signed_in_steam_item(rtx_item)") != std::string::npos);
  CHECK(state.find("catch (...)") != std::string::npos);
  const auto run = body(text, "unsigned run_menu_scripts(ILuaBase* lua)");
  CHECK(run.find("lua->PushCFunction(MenuSteamState); lua->SetField(-2, \"rtx_steam_state\");") != std::string::npos);
}
