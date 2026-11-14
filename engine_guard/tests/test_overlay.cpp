// The load overlay (R24, ADR 0134): its pure parts (the game file paths and Lua chunk names it shows, the elapsed
// time, UTF-8 clipping, the tally of Lua files behind its summary), its state across start() and finish() in this
// process (no game window: the window thread runs and makes no window), and the module's realm contract. The window
// itself is checked in a game (PoC). ADR 0214 and 0215: the phase after the engine's load (settling()), the estimate
// (expect()) and the words of its line and of the activity line; the menu-only contract of the new functions.
#include "load_overlay.h"
#include "nl_test.h"

#include <windows.h>

#include <cstdint>
#include <filesystem>
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
  overlay::expect(30, overlay::Confidence::good);  // no load: ignored
  overlay::settling();
  overlay::Labels labels;
  labels.file = std::string(100, 'x');  // clipped, not refused
  overlay::start("Loading gm_construct", labels);
  overlay::heading("Joining a server");
  overlay::status("Starting Lua");
  Sleep(30);
  const auto summary = overlay::finish();
  CHECK(summary.seconds > 0);
  CHECK(summary.seconds < 30);
  CHECK(summary.loading == summary.seconds);  // never settling(): the whole wait was the engine's load
  CHECK(summary.lua.empty());                // no window, no samples
  CHECK(overlay::finish().seconds == 0);     // a second finish() has nothing left
  overlay::start("Loading gm_flatgrass", {});  // a second load reuses the thread
  overlay::start("Loading gm_flatgrass", {});  // as does a restart without finish()
  CHECK(overlay::finish().seconds >= 0);
}

TEST_CASE("load overlay: the engine's load, then the wait until the game settles (ADR 0214, 0215)") {
  namespace overlay = nl::engine_guard::overlay;
  overlay::start("Loading gm_construct", {});
  overlay::expect(0, overlay::Confidence::none);      // no estimate yet
  overlay::expect(40, overlay::Confidence::rough);    // the machine's loads
  overlay::expect(32.5, overlay::Confidence::good);   // this map's loads
  overlay::expect(1e9, overlay::Confidence::good);    // nonsense: no estimate rather than one
  Sleep(40);
  overlay::settling();
  Sleep(40);
  overlay::settling();  // the first call counts
  overlay::expect(12, overlay::Confidence::good);
  const auto summary = overlay::finish();
  CHECK(summary.loading > 0);
  CHECK(summary.loading < summary.seconds);
  CHECK(summary.seconds - summary.loading >= 0.015);  // GetTickCount64 steps by about 16 ms
  double sampled = 0;
  for (const double seconds : summary.activity) sampled += seconds;
  CHECK(sampled >= 0);  // the window thread may have sampled this thread meanwhile; never negative
  CHECK(overlay::finish().loading == 0);
}

TEST_CASE("load overlay: the estimate's words") {
  namespace overlay = nl::engine_guard::overlay;
  using overlay::Confidence;
  const overlay::Labels english;
  CHECK(overlay::eta_text(0, 0, Confidence::good, english) == english.learning);
  CHECK(overlay::eta_text(0, 30000, Confidence::none, english) == english.learning);
  CHECK(overlay::eta_text(5000, 30000, Confidence::good, english) == "about 25 s left");
  CHECK(overlay::eta_text(0, 200000, Confidence::good, english) == "about 4 min left");
  CHECK(overlay::eta_text(5000, 30000, Confidence::rough, english) == "about 25 s left (rough estimate)");
  CHECK(overlay::eta_text(0, 200000, Confidence::rough, english) == "about 4 min left (rough estimate)");
  CHECK(overlay::eta_text(30000, 30000, Confidence::good, english) == english.longer);
  CHECK(overlay::eta_text(90000, 30000, Confidence::rough, english) == english.longer);
  overlay::Labels translated;
  translated.seconds_left = "\xE6\xAE\x8B\xE3\x82\x8A\xE7\xB4\x84 %s \xE7\xA7\x92";  // "残り約 %s 秒"
  translated.minutes_left = "%d min";                                              // broken: the English
  CHECK(overlay::eta_text(5000, 30000, Confidence::good, translated) == "\xE6\xAE\x8B\xE3\x82\x8A\xE7\xB4\x84 25 \xE7\xA7\x92");
  CHECK(overlay::eta_text(0, 200000, Confidence::good, translated) == "about 4 min left");
}

namespace {
// A 32-bit top-down bitmap to draw a frame into; pixels read back as 0xRRGGBB.
struct Picture {
  int width, height;
  HDC dc = nullptr;
  HBITMAP bitmap = nullptr;
  HGDIOBJ old = nullptr;
  std::uint32_t* bits = nullptr;
  Picture(int w, int h) : width(w), height(h) {
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = w;
    info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    dc = CreateCompatibleDC(nullptr);
    void* memory = nullptr;
    bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &memory, nullptr, 0);
    bits = static_cast<std::uint32_t*>(memory);
    old = SelectObject(dc, bitmap);
  }
  ~Picture() {
    SelectObject(dc, old);
    DeleteObject(bitmap);
    DeleteDC(dc);
  }
  std::uint32_t at(int x, int y) const { return bits[y * width + x] & 0xFFFFFF; }
  // Kept beside the test executable for a person to look at (scratch, out\build).
  void save(const std::filesystem::path& path) const {
    BITMAPFILEHEADER file{};
    BITMAPINFOHEADER header{};
    header.biSize = sizeof(header);
    header.biWidth = width;
    header.biHeight = -height;
    header.biPlanes = 1;
    header.biBitCount = 32;
    header.biCompression = BI_RGB;
    const DWORD bytes = static_cast<DWORD>(width * height * 4);
    file.bfType = 0x4D42;
    file.bfOffBits = sizeof(file) + sizeof(header);
    file.bfSize = file.bfOffBits + bytes;
    std::ofstream out(path, std::ios::binary);
    out.write(reinterpret_cast<const char*>(&file), sizeof(file));
    out.write(reinterpret_cast<const char*>(&header), sizeof(header));
    out.write(reinterpret_cast<const char*>(bits), bytes);
  }
};
}  // namespace

TEST_CASE("load overlay: the window's picture, with the bar and the estimate (ADR 0214, 0215)") {
  namespace overlay = nl::engine_guard::overlay;
  // A 1080p game window: 30-pixel lines, the window 6.5 lines tall and half the game's width.
  Picture picture(960, 195);
  REQUIRE(picture.bits != nullptr);
  overlay::Frame frame;
  frame.rows[0] = L"Loading gm_construct   0:31";
  frame.rows[1] = L"about 25 s left";
  frame.rows[2] = L"The map has loaded; the game is starting";
  frame.rows[3] = L"RTX Remix is preparing the scene";
  frame.rows[4] = L"Lua: addons/x/lua/autorun/client/some_long_folder_name/another_one/the_file.lua";
  frame.rows[5] = L"File: materials/models/x.vtf";
  frame.bar = true;
  frame.fraction = 0.5;
  overlay::draw(picture.dc, picture.width, picture.height, frame);
  GdiFlush();
  const auto folder = nl::test::scratch_dir("load_overlay_picture");
  picture.save(folder / "estimate.bmp");
  // line 30, pad 15: the estimate's row from y 37, its bar 10 pixels tall from y 47 and 372 wide from x 15.
  constexpr std::uint32_t kBackground = 0x16212E, kEdge = 0x468ED0, kFill = 0x468ED0, kTrack = 0x2C3E54, kLate = 0xD6A240;
  CHECK(picture.at(0, 0) == kEdge);
  CHECK(picture.at(5, 100) == kBackground);
  CHECK(picture.at(20, 52) == kFill);       // done: the first half
  CHECK(picture.at(380, 52) == kTrack);     // to do
  CHECK(picture.at(200, 44) == kBackground);  // above the bar
  int text = 0;
  for (int x = 15; x < 400; ++x)
    for (int y = 7; y < 37; ++y) text += picture.at(x, y) != kBackground;
  CHECK(text > 200);  // the heading is drawn
  // Past the estimate: the bar turns amber.
  frame.late = true;
  frame.fraction = 0.98;
  frame.rows[1] = L"Taking longer than usual";
  overlay::draw(picture.dc, picture.width, picture.height, frame);
  GdiFlush();
  picture.save(folder / "late.bmp");
  CHECK(picture.at(20, 52) == kLate);
  CHECK(picture.at(370, 52) == kLate);   // 98 % of 372 pixels: to x 379
  CHECK(picture.at(384, 52) == kTrack);
  // No estimate: no bar, the learning line in its place; Japanese through Windows' font linking.
  frame = overlay::Frame{};
  frame.rows[0] = L"gm_construct \x3092\x8AAD\x307F\x8FBC\x307F\x4E2D   0:03";
  frame.rows[1] = L"\x307E\x3060\x898B\x7A4D\x3082\x308A\x306F\x3042\x308A\x307E\x305B\x3093";
  frame.rows[3] = L"RTX Remix \x304C\x30B7\x30FC\x30F3\x3092\x6E96\x5099\x3057\x3066\x3044\x307E\x3059";
  overlay::draw(picture.dc, picture.width, picture.height, frame);
  GdiFlush();
  picture.save(folder / "learning-ja.bmp");
  CHECK(picture.at(380, 52) != kTrack);
  int glyphs = 0;
  for (int x = 15; x < 400; ++x)
    for (int y = 37; y < 67; ++y) glyphs += picture.at(x, y) != kBackground;
  CHECK(glyphs > 100);
  // Nothing to draw into: nothing happens.
  overlay::draw(nullptr, 100, 100, frame);
  overlay::draw(picture.dc, 0, 0, frame);
}

TEST_CASE("load overlay: the activity line's words") {
  namespace overlay = nl::engine_guard::overlay;
  overlay::Labels labels;
  labels.remix = "R";
  labels.scripts = "S";
  labels.spawnmenu = "M";
  labels.files = "F";
  CHECK(overlay::activity_text(overlay::Activity::remix, labels) == "R");
  CHECK(overlay::activity_text(overlay::Activity::scripts, labels) == "S");
  CHECK(overlay::activity_text(overlay::Activity::spawnmenu, labels) == "M");
  CHECK(overlay::activity_text(overlay::Activity::files, labels) == "F");
  CHECK(overlay::activity_text(overlay::Activity::none, labels).empty());
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
  // ADR 0214 and 0215: the new functions are inside that block too, the history's writer above all.
  const auto block_end = text.find("#endif", guarded);
  REQUIRE(block_end != std::string::npos);
  for (const char* name : {"LoadExpect", "LoadSettling", "LoadTimes", "LoadTimesSave", "LoadEnd"}) {
    const auto at = text.find(std::string("LUA->PushCFunction(") + name + ");");
    CHECK(at != std::string::npos);
    CHECK(at > guarded && at < block_end);
  }
}
