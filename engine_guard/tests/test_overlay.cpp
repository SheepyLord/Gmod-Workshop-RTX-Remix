// The load overlay (R24, ADR 0134): its pure parts (the game file paths and Lua chunk names it shows, the elapsed
// time, UTF-8 clipping, the tally of Lua files behind its summary), its state across start() and finish() in this
// process (no game window: the window thread runs and makes no window), and the module's realm contract. The window
// itself is checked in a game (PoC).
#include "load_overlay.h"
#include "nl_test.h"

#include <windows.h>

#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {
std::vector<std::uint8_t> bytes(const std::string& text) { return std::vector<std::uint8_t>(text.begin(), text.end()); }
}  // namespace

TEST_CASE("load overlay: game file paths on a stack, cut to the game-relative part") {
  using nl::engine_guard::overlay::resource_paths;
  std::string block;
  block += std::string(16, '\0') + "materials/particle/warp5_explosion.vmt" + std::string(8, '\0');
  block += "h:\\steamlibrary\\steamapps\\common\\garrysmod_poc\\garrysmod\\addons\\x\\materials\\models\\gun.vtf";
  block += std::string(4, '\0') + "maps/*.bsp" + std::string(4, '\0');  // a search pattern: skipped
  block += "models/weapons/c_m249.mdl" + std::string(3, '\0');
  block += "materials/particle/warp5_explosion.vmt" + std::string(2, '\0');  // a duplicate
  block += "notes.txt" + std::string(2, '\0') + "a.vmt";                     // not a game path; too short
  const auto data = bytes(block);
  const auto paths = resource_paths(data.data(), data.size(), 8);
  REQUIRE(paths.size() == 3);
  CHECK(paths[0] == "materials/particle/warp5_explosion.vmt");
  CHECK(paths[1] == "materials/models/gun.vtf");  // the first game folder decides, not a later "models/"
  CHECK(paths[2] == "models/weapons/c_m249.mdl");
  CHECK(resource_paths(data.data(), data.size(), 1).size() == 1);
  // An extension that goes on is not one: ".vmtx", "x.mdl2".
  const auto other = bytes("materials/a/b.vmtx" + std::string(2, '\0') + "models/a/b.mdl2");
  CHECK(resource_paths(other.data(), other.size(), 4).empty());
}

TEST_CASE("load overlay: Lua chunk names as shown") {
  using nl::engine_guard::overlay::lua_display;
  CHECK(lua_display("@lua/autorun/sh_arc9_autorun.lua") == "lua/autorun/sh_arc9_autorun.lua");
  CHECK(lua_display("addons/x/lua/y.lua") == "addons/x/lua/y.lua");
  CHECK(lua_display("h:\\steam\\common\\GarrysMod\\garrysmod\\addons\\rtx_agent\\lua\\a.lua") == "addons/rtx_agent/lua/a.lua");
}

TEST_CASE("load overlay: elapsed time") {
  using nl::engine_guard::overlay::elapsed_text;
  CHECK(elapsed_text(0) == "0:00");
  CHECK(elapsed_text(7999) == "0:07");
  CHECK(elapsed_text(65000) == "1:05");
  CHECK(elapsed_text(750000) == "12:30");
  CHECK(elapsed_text(3723000) == "1:02:03");
}

TEST_CASE("load overlay: the tally keeps the longest Lua files, bounded") {
  nl::engine_guard::overlay::Tally tally;
  for (int i = 0; i < 5; ++i) tally.add("lua/arc9/shared/sh_atts.lua");
  for (int i = 0; i < 3; ++i) tally.add("lua/autorun/b.lua");
  for (int i = 0; i < 3; ++i) tally.add("lua/autorun/a.lua");
  tally.add("lua/autorun/c.lua");
  const auto top = tally.top(3);
  REQUIRE(top.size() == 3);
  CHECK(top[0].first == "lua/arc9/shared/sh_atts.lua");
  CHECK(top[0].second == 5);
  CHECK(top[1].first == "lua/autorun/a.lua");  // a tie goes by name
  CHECK(top[2].first == "lua/autorun/b.lua");
  nl::engine_guard::overlay::Tally full;
  for (std::size_t i = 0; i < nl::engine_guard::overlay::kTallyLimit + 50; ++i) full.add("f" + std::to_string(i));
  full.add("f0");
  CHECK(full.top(nl::engine_guard::overlay::kTallyLimit + 100).size() == nl::engine_guard::overlay::kTallyLimit);
  CHECK(full.top(1)[0].first == "f0");
  tally.clear();
  CHECK(tally.top(3).empty());
}

TEST_CASE("load overlay: text is clipped at a UTF-8 character boundary") {
  using nl::engine_guard::overlay::clipped;
  CHECK(clipped("Loading gm_construct", 7) == "Loading");
  CHECK(clipped("short", 40) == "short");
  const std::string kana = "\xE3\x83\xAD\xE3\x83\xBC\xE3\x83\x89";  // three 3-byte characters
  CHECK(clipped(kana, 9) == kana);
  CHECK(clipped(kana, 8) == kana.substr(0, 6));  // not the first two bytes of the third character
  CHECK(clipped(kana, 4) == kana.substr(0, 3));
  CHECK(clipped(kana, 2).empty());
}

TEST_CASE("load overlay: start and finish in a process without a game window") {
  namespace overlay = nl::engine_guard::overlay;
  CHECK(overlay::finish().seconds == 0);  // finish() before any start()
  overlay::Labels labels;
  labels.file = std::string(100, 'x');  // clipped, not refused
  overlay::start("Loading gm_construct", labels);
  overlay::heading("Joining a server");
  overlay::status("Starting Lua");
  Sleep(30);
  const auto summary = overlay::finish();
  CHECK(summary.seconds > 0);
  CHECK(summary.seconds < 30);
  CHECK(summary.lua.empty());                // no window, no samples
  CHECK(overlay::finish().seconds == 0);     // a second finish() has nothing left
  overlay::start("Loading gm_flatgrass", {});  // a second load reuses the thread
  overlay::start("Loading gm_flatgrass", {});  // as does a restart without finish()
  CHECK(overlay::finish().seconds >= 0);
}

TEST_CASE("engine guard module: the overlay is the engine's menu state's alone (R24 review)") {
  std::ifstream file(NL_ENGINE_GUARD_MODULE_SOURCE);
  REQUIRE(file.good());
  std::stringstream read;
  read << file.rdbuf();
  const std::string text = read.str();
  // MENU_DLL is a global any Lua can set: the realm comes from lua_shared's own menu state.
  CHECK(text.find("GetField(-1, \"MENU_DLL\")") == std::string::npos);
  CHECK(text.find("GetLuaInterface(GarrysMod::Lua::State::MENU)") != std::string::npos);
  // Only the gmsv_ copy (the menu's) has the overlay's functions at all.
  const auto guarded = text.find("#if NL_ENGINE_GUARD_MENU\n    LUA->PushCFunction(LoadStart);");
  CHECK(guarded != std::string::npos);
}
