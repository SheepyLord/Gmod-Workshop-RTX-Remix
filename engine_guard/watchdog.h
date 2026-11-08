#pragma once
// The start-up watchdog (R23, ADR 0130): names what keeps a realm's Lua start-up from finishing. Each
// copy of the module (client, server) watches its own realm from the module's load until the
// companion calls StartupDone() at that realm's Initialize. Every few seconds it samples the main
// thread, briefly suspended: the module and offset it runs in, and the Lua chunk names on its stack
// (copied into a buffer allocated beforehand, so no lock the main thread may hold is needed). When the
// topmost chunk name has not changed for kStallMs, it writes garrysmod/data/native-loader/startup-stall.json
// and shows the player one message naming the file; the companion repeats it at the next start.
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace nl::engine_guard::watchdog {

inline constexpr std::uint32_t kSampleMs = 3000;
inline constexpr std::uint32_t kStallMs = 90000;
// Without StartupDone() (an error before Initialize), the watch still ends this long after it began.
inline constexpr std::uint64_t kGiveUpMs = 15 * 60 * 1000;

// Starts the watch for the calling (main) thread of `realm` ("client", "server"); a second call while
// it runs does nothing. The two copies of the module each watch their own realm's start; at most one
// message is shown per process.
void start(std::string_view realm) noexcept;
// The realm's start-up is over: the watch ends. True when this start was reported as stalled and then
// went on after all (the companion then removes the report: no notice for it at the next start).
bool done() noexcept;
// The gamemode has loaded: the watch ends at the latest `ms` from now (the first call counts), so a failing
// Initialize hook elsewhere cannot stretch it over a long map load, while a stall in an Initialize hook
// (longer than kStallMs) is still reported.
void finish_after(std::uint64_t ms) noexcept;
// The player's message, translated by the companion: title and a body with %s for the file. Only the
// first call counts.
void set_message(std::string_view title, std::string_view body) noexcept;

// Pure parts, for tests: Lua chunk names ("@lua/x.lua", "lua/x.lua", "addons/.../x.lua") in a block of
// memory, nearest first, without duplicates, at most `limit`.
std::vector<std::string> lua_names(const std::uint8_t* data, std::size_t size, std::size_t limit);
// The report's JSON text.
struct Sample {
  std::string where;                // module+offset, or "outside any module"
  std::vector<std::string> names;   // Lua chunk names on the stack, nearest first
};
std::string report_json(std::string_view utc, std::string_view realm, std::uint64_t stalled_ms,
                        const std::vector<Sample>& samples, unsigned guard_cut);
std::string json_string(std::string_view text);

}  // namespace nl::engine_guard::watchdog
