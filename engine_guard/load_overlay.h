#pragma once
// The map-load overlay (R24, ADR 0134). Garry's Mod's loading screen says only "Loading resources" or
// "Starting Lua", and during a blocking phase such as the Lua start the engine does not repaint it at all. While
// a map loads, a small window of this module's own, drawn by its own thread over the game's window, says what the
// game is doing: the time so far, the stock status, the Lua file running and the game file being read, sampled
// from the main thread's stack four times a second as the watchdog samples it. At the end it gives the load's
// length and the Lua files that took longest. The companion's menu script drives it from the menu's loading state.
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::engine_guard::overlay {

inline constexpr std::uint32_t kSampleMs = 250;
inline constexpr std::uint32_t kShowAfterMs = 1500;  // a short load shows nothing
inline constexpr std::size_t kTallyLimit = 512;

struct Labels {
  std::string lua = "Lua";    // "Lua: lua/autorun/x.lua"
  std::string file = "File";  // "File: materials/x.vmt"
};
// The loading panel activated (called on the main thread): `heading` is the first line.
void start(std::string_view heading, const Labels& labels) noexcept;
// A better first line once the map is known ("Loading gm_construct").
void heading(std::string_view text) noexcept;
// The stock status line ("Loading resources", "Starting Lua").
void status(std::string_view text) noexcept;
struct Summary {
  double seconds = 0;
  std::vector<std::pair<std::string, double>> lua;  // the Lua files seen running longest, longest first (at most 3)
};
// The loading panel deactivated: the window hides; returns what the load took.
Summary finish() noexcept;

// Pure parts, for tests.
// Paths of game files ("materials/x.vmt", "models/x.mdl", "maps/x.bsp", "sound/x.wav", ...) in a block of memory,
// nearest first, without duplicates or wildcards, at most `limit`; an absolute path is cut to its game-relative part.
std::vector<std::string> resource_paths(const std::uint8_t* data, std::size_t size, std::size_t limit);
// A Lua chunk name as shown: "@lua/x.lua" -> "lua/x.lua", "addons/a/lua/x.lua" kept.
std::string lua_display(std::string_view name);
// "0:07", "1:05", "12:30", "1:02:03".
std::string elapsed_text(std::uint64_t ms);
// At most `limit` bytes of UTF-8 text, never cut inside a character.
std::string clipped(std::string_view text, std::size_t limit);
// A count per name, bounded to kTallyLimit names; top(n) returns the n largest, ties by name.
class Tally {
 public:
  void add(const std::string& name);
  std::vector<std::pair<std::string, std::uint64_t>> top(std::size_t n) const;
  void clear() { counts_.clear(); }

 private:
  std::vector<std::pair<std::string, std::uint64_t>> counts_;
};

}  // namespace nl::engine_guard::overlay
