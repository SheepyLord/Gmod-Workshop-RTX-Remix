#pragma once
// The load overlay's estimate (ADR 0215). The companion's menu script learns how long a map load takes from the loads
// before and tells the overlay when the wait should end; the overlay's own thread counts down to it and moves a bar,
// since the main thread, which runs Lua, is blocked for most of a load. The script keeps its history in
// garrysmod/data/nativeloader/load_times.txt, which this module reads and writes for it: the menu realm cannot write
// files (RESEARCH, R26).
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace nl::engine_guard::overlay {

// How sure the estimate is: none (no load to learn from yet), rough (other maps, or loads that disagree), good.
enum class Confidence : std::uint8_t { none, rough, good };

inline constexpr std::size_t kHistoryLimit = 64 * 1024;  // the history file's largest size, read or written
inline constexpr double kBarCap = 0.97;                  // where the bar stands when the estimate runs out
inline constexpr double kBarLimit = 0.995;               // past the estimate it creeps toward this, never full

// `format` with its one "%s" replaced by `value`; `fallback` (English, one "%s") when `format` has none or several, so
// a translation can never make a printf-style format of its own.
std::string fill_value(std::string_view format, std::string_view fallback, std::string_view value);

// How a remaining time is said: whole seconds below 90 s (from 20 s rounded up to five), else whole minutes (up).
struct Remaining {
  bool minutes = false;
  unsigned value = 0;
};
Remaining remaining(std::uint64_t ms);

// The bar at `now_ms`: from `anchor` (the fraction shown when the estimate last changed, at `anchor_ms`) linearly to
// kBarCap at `end_ms`; past `end_ms` it creeps from kBarCap toward kBarLimit. Never below `anchor`.
double bar_fraction(double anchor, std::uint64_t anchor_ms, std::uint64_t now_ms, std::uint64_t end_ms);

// The game's garrysmod folder, found up from this process's executable (<root>\bin\win64\gmod.exe); empty if none.
std::wstring garrysmod_folder();
// <garrysmod>\data\nativeloader\load_times.txt; empty for an empty folder.
std::wstring history_path(const std::wstring& garrysmod);
// The file's text, or nothing when it is missing, unreadable or larger than kHistoryLimit.
std::optional<std::string> read_history(const std::wstring& path);
// Writes `text` (at most kHistoryLimit bytes, no NUL) to a temporary file beside `path` and moves it over `path`, so
// a reader never sees half a file; makes the folder when it is missing. False when anything fails.
bool write_history(const std::wstring& path, std::string_view text);

}  // namespace nl::engine_guard::overlay
