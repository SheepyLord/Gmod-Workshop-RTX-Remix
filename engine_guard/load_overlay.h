#pragma once
// The map-load overlay (R24, ADR 0134). Garry's Mod's loading screen says only "Loading resources" or "Starting Lua",
// and during a blocking phase such as the Lua start the engine does not repaint it at all. While a map loads, a small
// window of this module's own, drawn by its own thread over the game's window, says what the game is doing: the time
// so far, the stock status, the Lua file running and the game file being read, sampled from the main thread's stack
// four times a second as the watchdog samples it. At the end it gives the load's length and the Lua files that took
// longest. The companion's menu script drives it from the menu's loading state.
// ADR 0214: it stays after the engine's load ends ("Ready to play!") until the game runs steadily (settling()), and
// says in plain words what the main thread is doing (load_activity.h). ADR 0215: it counts down to the end of the wait
// the menu script expects (expect(), load_eta.h) and moves a bar.
#include "load_activity.h"
#include "load_eta.h"
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::engine_guard::overlay {

inline constexpr std::uint32_t kSampleMs = 250;
inline constexpr std::uint32_t kShowAfterMs = 1500;  // a short load shows nothing
inline constexpr std::size_t kTallyLimit = 512;
// After settling() the window hides by itself this long later, whatever the menu script does (ADR 0214).
inline constexpr std::uint64_t kSettleLimitMs = 180000;

// The window's words, in the player's language (the menu script's catalog); each one missing keeps its English.
struct Labels {
  std::string lua = "Lua";    // "Lua: lua/autorun/x.lua"
  std::string file = "File";  // "File: materials/x.vmt"
  // What the main thread is doing (ADR 0214).
  std::string remix = "RTX Remix is preparing the scene";
  std::string scripts = "Running add-on scripts";
  std::string spawnmenu = "Building the spawn menu";
  std::string files = "Loading game files";
  // The estimate (ADR 0215): one "%s" each, the number.
  std::string seconds_left = "about %s s left";
  std::string minutes_left = "about %s min left";
  std::string seconds_rough = "about %s s left (rough estimate)";
  std::string minutes_rough = "about %s min left (rough estimate)";
  std::string longer = "Taking longer than usual";
  std::string learning = "No estimate yet: this load is timed for the next one";
};
// The loading panel activated (called on the main thread): `heading` is the first line.
void start(std::string_view heading, const Labels& labels) noexcept;
// A better first line once the map is known ("Loading gm_construct").
void heading(std::string_view text) noexcept;
// The stock status line ("Loading resources", "Starting Lua").
void status(std::string_view text) noexcept;
// The whole wait is expected to last `seconds` from start(): the window counts down to it and moves its bar from
// where it stands. Confidence none (or no seconds): the window says the load is being timed for the next one.
void expect(double seconds, Confidence confidence) noexcept;
// The engine's load ended but the game is not playing steadily yet: the window stays until finish(), at most
// kSettleLimitMs.
void settling() noexcept;
struct Summary {
  double seconds = 0;  // the whole wait, start() to finish()
  double loading = 0;  // start() to settling() (the whole wait without it)
  std::vector<std::pair<std::string, double>> lua;  // the Lua files seen running longest, longest first (at most 3)
  double activity[static_cast<std::size_t>(Activity::count)] = {};  // seconds the main thread was seen in each
};
// The loading panel deactivated, or the game settled: the window hides; returns what the wait took.
Summary finish() noexcept;

// The history the menu script learns its estimate from (ADR 0215): garrysmod/data/nativeloader/load_times.txt.
std::optional<std::string> history() noexcept;
bool save_history(std::string_view text) noexcept;

// One picture of the window: its rows (the heading and the time so far, the estimate, the stock status, the activity,
// the Lua file, the game file), the bar beside the estimate and whether the wait has run past it.
inline constexpr int kRows = 6;
struct Frame {
  std::wstring rows[kRows];
  bool bar = false;
  bool late = false;
  double fraction = 0;
};
// Paints `frame` into `dc` (an HDC) of `width` x `height`: the window thread into its buffer, a test into a bitmap
// (fonts are cached for one thread at a time).
void draw(void* dc, int width, int height, const Frame& frame) noexcept;

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
// The estimate's words for the window's second line: the time left, "Taking longer than usual" past the end, the
// learning line without an estimate.
std::string eta_text(std::uint64_t now_ms, std::uint64_t end_ms, Confidence confidence, const Labels& labels);
// The activity line's words ("" for none).
const std::string& activity_text(Activity activity, const Labels& labels);
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
