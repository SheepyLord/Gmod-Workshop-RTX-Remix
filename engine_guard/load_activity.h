#pragma once
// What the main thread is doing while a map loads, in plain words (ADR 0214): the load overlay's activity line. Each
// sample of the main thread (its instruction pointer and the copy of its stack the overlay takes anyway) is put in one
// of a few classes by the module its code belongs to: Remix (the runtime's d3d9.dll, its libraries and the Vulkan
// driver), Lua (lua_shared.dll, or code LuaJIT compiled), the game's file system and image decoder, or the game's own
// code. A thread waiting in Windows, a C runtime or tier0 is classed by its nearest known caller on the stack. The
// line shows the class seen most in the last two seconds. Module ranges come from the modules' own headers, read on
// the main thread at the load's start, so the window thread never takes the loader lock.
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

namespace nl::engine_guard::overlay {

// The kind of code at an address: `other` is any module not listed (Windows, the C runtimes, tier0) or no module.
enum class Kind : std::uint8_t { other, game, remix, scripts, files };
// What the activity line says; `count` is the number of activities.
enum class Activity : std::uint8_t { none, remix, scripts, spawnmenu, files, count };

struct Range {
  std::uintptr_t begin = 0;
  std::uintptr_t end = 0;  // exclusive
  Kind kind = Kind::other;
};

inline constexpr std::size_t kCallerScan = 4096;  // stack bytes above the stack pointer searched for a known caller
inline constexpr std::size_t kRecentSamples = 8;  // two seconds of the overlay's 250 ms samples
inline constexpr std::size_t kShownAtLeast = 2;   // samples of an activity among them before the line names it

// The class of a module by its file name (any case). "d3d9.dll" is Remix's only when `remix_d3d9` (its export
// remixapi_InitializeLibrary), else the game's.
Kind module_kind(std::wstring_view name, bool remix_d3d9);
// The executable sections of a mapped image as ranges of `kind`; none for a bad or unreadable header (read under SEH).
std::vector<Range> code_ranges(const void* image, Kind kind);
// The kind of the code at `address`: other when no range holds it.
Kind kind_at(const std::vector<Range>& ranges, std::uintptr_t address);
// True for executable memory that is no module's (LuaJIT's compiled code); VirtualQuery, no loader lock.
bool jit_code(std::uintptr_t address);
// The ranges of this process's known modules (the listed ones that are loaded, and the executable as the game's).
std::vector<Range> process_ranges();

// One sample's activity. `where` is the kind of the code at the instruction pointer (scripts for LuaJIT's compiled
// code), `stack` the copy taken from the stack pointer up, `lua` the nearest Lua chunk name found on it ("" for none).
Activity classify(Kind where, const std::uint8_t* stack, std::size_t size, const std::vector<Range>& ranges,
                  std::string_view lua);
// A chunk name of the spawn menu's: sandbox's spawnmenu folder, Extended Spawnmenu, any "spawnmenu" in the name.
bool spawn_menu_file(std::string_view lua);

// The activity the line shows: the one seen most among the last kRecentSamples samples, at least kShownAtLeast times
// (a tie goes to the newer one); none when no activity was seen that often.
class Recent {
 public:
  void add(Activity activity);
  Activity shown() const;
  void clear();

 private:
  Activity samples_[kRecentSamples]{};
  std::size_t next_ = 0;
  std::size_t filled_ = 0;
};

}  // namespace nl::engine_guard::overlay
