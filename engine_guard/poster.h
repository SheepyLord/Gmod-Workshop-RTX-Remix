#pragma once
// GMod's `poster` command in RTX starts (ADR 0226, GitHub issue 3). client.dll's ConCommand "poster" only sets a
// multiplier; the view renderer then draws the poster's tiles through sheared projections and reads back the
// raster image. RTX Remix's camera manager rejects sheared projections, so under RTX none of it is path traced.
// In the client realm of an RTX start the module takes the command over for the process: its callback asks the
// runtime (d3d9.dll's rtxposter_* exports, rtxposter_api.h) to render the poster itself, in tiles of the window's
// own size; the client realm's Think hook prints in the console how it goes (poll). Without the runtime's poster (a
// start without RTX, an older runtime) nothing is changed.
#include "rtxposter_api.h"

#include <cstddef>
#include <cstdint>
#include <ctime>
#include <optional>
#include <string>
#include <vector>

namespace nl::engine_guard::poster {

// A ConCommand of Source SDK 2013 x64, as GMod's client.dll builds it (ConCommand::ConCommand stores the name at 24,
// the help string at 32, the callback at 48, and in the byte at 64 bit 0 for a completion callback, bit 1 for a
// callback that takes the arguments and bit 2 for a callback interface).
inline constexpr std::size_t kNameOffset = 24, kHelpOffset = 32, kCallbackOffset = 48, kKindOffset = 64;
inline constexpr std::uint8_t kKindArguments = 0x2, kKindInterface = 0x4;
// A CCommand: the argument count at 0, the arguments' text in the object's own buffers from 8, and the pointers to
// them from 1032 (the engine's poster callback reads argv[1] at 0x410).
inline constexpr std::size_t kArgcOffset = 0, kTextOffset = 8, kArgvOffset = 1032;
inline constexpr int kMaxArgs = 64;
inline constexpr char kName[] = "poster";
inline constexpr char kHelp[] =
    "[multiplier] [bSaveEach] - Renders a poster X times size of your game's resolution and saves it in your "
    "screenshots/ folder";

// FnCommandCallback_t: void (*)(const CCommand&).
using Callback = void (*)(const void* command);

struct Command {
  std::uintptr_t object = 0;    // the ConCommand
  Callback callback = nullptr;  // the callback it had
  std::string reason;           // why it was not found
};

// The ConCommand "poster" of a loaded module (client.dll): its help text exactly once in a read-only section, then
// exactly one object in a writable section that points at it from kHelpOffset, whose name is "poster", whose
// callback lies in an executable section of the module and is of the kind that takes the arguments. Read under SEH.
Command find(const void* module) noexcept;

// A CCommand's arguments: the count 1 to 64, every pointer inside the object's text and every string ending there;
// the first is the command's name as typed. False, and nothing in `out`, otherwise.
bool arguments(const void* command, std::vector<std::string>& out) noexcept;

// Puts `hook` in the command's callback when it is still the callback it had, and puts that back while `hook` is
// still there. One interlocked exchange each.
bool install(const Command& command, Callback hook) noexcept;
bool restore(const Command& command, Callback hook) noexcept;

// What the command's arguments ask for, read as the engine reads them: the multiplier is atof's whole part, the
// tiles are saved when the second argument starts with '1'. Without a multiplier the engine's own callback prints
// its usage; below 1 the engine's message; above the runtime's 16 a message of the module's.
struct Plan {
  enum class Kind { usage, silly, too_large, render } kind = Kind::usage;
  int multiplier = 0;
  bool tiles = false;
};
Plan plan(const std::vector<std::string>& args);

// The engine's name for a poster at `now`: poster-yy-mm-dd HH-MM-SS, and " 2", " 3" ... after it for the second and
// later one in that second (`taken` says whether a name's .png exists).
std::wstring poster_name(const std::tm& now, bool (*taken)(const std::wstring& name));

// The runtime's poster: d3d9.dll's exports when they are there and of this API version, else all null.
struct Runtime {
  rtxposter_StartFn start = nullptr;
  rtxposter_CancelFn cancel = nullptr;
  rtxposter_GetStatusFn status = nullptr;
  bool ready() const { return start && cancel && status; }
};
Runtime runtime();

// The state's name in Lua: idle, starting, rendering, writing, done or failed.
const char* state_name(std::uint32_t state);

std::string utf8(const wchar_t* text);

// What Lua and the console see of a poster's file (review finding 18): "screenshots/<name>" for a file in a folder
// named screenshots (the command's own, <garrysmod>\screenshots), otherwise the file's name alone. Never a drive, a
// share, the folders above it or a backslash: any client Lua, a server's included, can read PosterStatus(), and an
// absolute path names the player's folders, often their Windows account.
std::string shown_name(const wchar_t* path);
// The runtime's English reason with the poster's absolute path, and its folder, put as shown_name puts them.
std::string shown_reason(const char* why, const wchar_t* path);

// nlengineguard.PosterStatus()'s fields, read from the runtime: what any client Lua may see of the poster.
struct View {
  const char* state = "idle";
  std::uint32_t generation = 0, width = 0, height = 0, columns = 0, rows = 0, done = 0, frame = 0, frames = 0;
  std::int32_t error = 0;
  std::string why;   // shown_reason
  std::string path;  // shown_name, never absolute
};
// The runtime's poster status as Lua gets it; nothing without the runtime's poster, or when its status call refuses.
std::optional<View> view(const Runtime& runtime);

// The client realm of an RTX start: takes GMod's poster command over for the process (this module is pinned). Once
// done it stays; a later call says so. Never throws.
struct Status {
  bool installed = false;
  std::string reason;
};
Status take_command() noexcept;

// The main thread, every frame (the client realm's Think hook): prints in the console what changed for the poster the
// command started last (its size and tiles, "Saving poster to ...", "Saved poster to ...", or why it was not made).
// The game's console is drawn by the main thread, so nothing is printed from another one.
void poll() noexcept;

}  // namespace nl::engine_guard::poster
