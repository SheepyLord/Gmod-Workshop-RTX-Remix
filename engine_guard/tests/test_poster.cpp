// GMod's poster command under RTX (ADR 0226): the command found in a module as client.dll builds it, its arguments
// read from a CCommand, its callback swapped and given back, the engine's reading of the arguments and the engine's
// file names.
#include "poster.h"
#include "nl_test.h"

#include <windows.h>

#include <cstddef>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace poster = nl::engine_guard::poster;

namespace {

// A ConCommand as GMod's client.dll lays it out (ConCommand::ConCommand's stores).
struct FakeCommand {
  void* vtable;
  void* next;
  bool registered;
  const char* name;
  const char* help;
  int flags;
  poster::Callback callback;
  void* completion;
  std::uint8_t kind;
};
static_assert(offsetof(FakeCommand, name) == poster::kNameOffset);
static_assert(offsetof(FakeCommand, help) == poster::kHelpOffset);
static_assert(offsetof(FakeCommand, callback) == poster::kCallbackOffset);
static_assert(offsetof(FakeCommand, kind) == poster::kKindOffset);

// A CCommand (tier1/convar.h of Source SDK 2013): the count, the argument string, the tokens, the pointers.
struct FakeArgs {
  int argc;
  int argv0_size;
  char args[512];
  char tokens[512];
  const char* argv[64];
};
static_assert(offsetof(FakeArgs, argv) == poster::kArgvOffset);
static_assert(offsetof(FakeArgs, args) == poster::kTextOffset);

int g_calls = 0;
void engine_callback(const void*) { ++g_calls; }
void our_hook(const void*) {}

// In this executable's writable data, like the engine's static command objects.
FakeCommand g_command;
FakeCommand g_second;

void reset(FakeCommand& command) {
  std::memset(&command, 0, sizeof(command));
  command.name = poster::kName;
  command.help = poster::kHelp;
  command.callback = engine_callback;
  command.kind = poster::kKindArguments;
}

// Built in place: the pointers point into this object's own buffers, as the engine's do.
void tokens(FakeArgs& result, const std::vector<std::string>& words) {
  std::memset(&result, 0, sizeof(result));
  std::size_t at = 0;
  for (const auto& word : words) {
    result.argv[result.argc++] = result.tokens + at;
    std::memcpy(result.tokens + at, word.c_str(), word.size() + 1);
    at += word.size() + 1;
  }
}

}  // namespace

TEST_CASE("poster: the command is found as client.dll builds it") {
  reset(g_command);
  std::memset(&g_second, 0, sizeof(g_second));
  const auto found = poster::find(GetModuleHandleW(nullptr));
  CHECK(found.reason.empty());
  CHECK(found.object == reinterpret_cast<std::uintptr_t>(&g_command));
  CHECK(found.callback == &engine_callback);
  // Only a callback that takes the arguments: not an interface, not the old kind without arguments.
  g_command.kind = poster::kKindArguments | poster::kKindInterface;
  CHECK(poster::find(GetModuleHandleW(nullptr)).object == 0);
  g_command.kind = 0;
  CHECK(poster::find(GetModuleHandleW(nullptr)).reason == "client.dll's poster command was not found");
  // A callback outside the module's code, or another name, is not the command.
  reset(g_command);
  g_command.callback = reinterpret_cast<poster::Callback>(&g_second);
  CHECK(poster::find(GetModuleHandleW(nullptr)).object == 0);
  reset(g_command);
  g_command.name = "posters";
  CHECK(poster::find(GetModuleHandleW(nullptr)).object == 0);
  // Two such objects: nothing is taken.
  reset(g_command);
  reset(g_second);
  CHECK(poster::find(GetModuleHandleW(nullptr)).reason == "client.dll has more than one poster command");
  std::memset(&g_second, 0, sizeof(g_second));
  // A module without the help text, or none.
  CHECK(poster::find(GetModuleHandleW(L"kernel32.dll")).reason == "client.dll has no poster command's help text");
  CHECK(poster::find(nullptr).reason == "client.dll is not loaded");
}

TEST_CASE("poster: the callback is swapped once and given back") {
  reset(g_command);
  const auto found = poster::find(GetModuleHandleW(nullptr));
  REQUIRE(found.object != 0);
  CHECK(poster::install(found, our_hook));
  CHECK(g_command.callback == &our_hook);
  CHECK(!poster::install(found, our_hook));  // not the engine's any more
  CHECK(poster::restore(found, our_hook));
  CHECK(g_command.callback == &engine_callback);
  CHECK(!poster::restore(found, our_hook));  // ours is not there
  // Someone else's callback in between is left alone.
  CHECK(poster::install(found, our_hook));
  g_command.callback = engine_callback;
  CHECK(!poster::restore(found, our_hook));
  CHECK(g_command.callback == &engine_callback);
}

TEST_CASE("poster: the arguments are read from a CCommand") {
  std::vector<std::string> out;
  static FakeArgs args, typed, both, other, none, many, outside, unterminated;
  tokens(args, {"poster", "2", "1"});
  CHECK(poster::arguments(&args, out));
  CHECK(out == std::vector<std::string>({"poster", "2", "1"}));
  tokens(typed, {"POSTER", "4"});
  CHECK(poster::arguments(&typed, out));
  CHECK(out.size() == 2);
  // Pointers into the argument string count too (the engine's own buffer).
  tokens(both, {"poster"});
  std::memcpy(both.args, "3", 2);
  both.argv[both.argc++] = both.args;
  CHECK(poster::arguments(&both, out));
  CHECK(!out.empty() && out.back() == "3");
  // What a CCommand never holds.
  tokens(other, {"screenshot"});
  CHECK(!poster::arguments(&other, out));
  CHECK(out.empty());
  tokens(none, {});
  CHECK(!poster::arguments(&none, out));
  tokens(many, {"poster"});
  many.argc = 65;
  CHECK(!poster::arguments(&many, out));
  tokens(outside, {"poster", "2"});
  static const char elsewhere[] = "2";
  outside.argv[1] = elsewhere;
  CHECK(!poster::arguments(&outside, out));
  tokens(unterminated, {"poster"});
  std::memset(unterminated.tokens, 'x', sizeof(unterminated.tokens));
  unterminated.argv[0] = unterminated.tokens + sizeof(unterminated.tokens) - 3;
  CHECK(!poster::arguments(&unterminated, out));
  CHECK(!poster::arguments(nullptr, out));
}

TEST_CASE("poster: the arguments mean what the engine reads") {
  using Kind = poster::Plan::Kind;
  CHECK(poster::plan({"poster"}).kind == Kind::usage);
  auto two = poster::plan({"poster", "2"});
  CHECK(two.kind == Kind::render);
  CHECK(two.multiplier == 2);
  CHECK(!two.tiles);
  CHECK(poster::plan({"poster", "2", "1"}).tiles);
  CHECK(poster::plan({"poster", "2", "10"}).tiles);  // argv[2][0] == '1'
  CHECK(!poster::plan({"poster", "2", "0"}).tiles);
  CHECK(poster::plan({"poster", "2.9"}).multiplier == 2);  // (int)atof
  CHECK(poster::plan({"poster", "16"}).kind == Kind::render);
  CHECK(poster::plan({"poster", "17"}).kind == Kind::too_large);
  CHECK(poster::plan({"poster", "1e12"}).kind == Kind::too_large);
  auto silly = poster::plan({"poster", "0"});
  CHECK(silly.kind == Kind::silly);
  CHECK(silly.multiplier == 0);
  CHECK(poster::plan({"poster", "abc"}).kind == Kind::silly);
  CHECK(poster::plan({"poster", "-3"}).multiplier == -3);
}

namespace {
int g_taken = 0;
bool first_taken(const std::wstring&) { return g_taken-- > 0; }
}  // namespace

TEST_CASE("poster: files are named as the engine names its own") {
  std::tm when{};
  when.tm_year = 126;  // 2026
  when.tm_mon = 10;
  when.tm_mday = 15;
  when.tm_hour = 1;
  when.tm_min = 2;
  when.tm_sec = 3;
  CHECK(poster::poster_name(when, nullptr) == L"poster-26-11-15 01-02-03");
  g_taken = 0;
  CHECK(poster::poster_name(when, first_taken) == L"poster-26-11-15 01-02-03");
  g_taken = 2;  // that name and " 2" exist
  CHECK(poster::poster_name(when, first_taken) == L"poster-26-11-15 01-02-03 3");
  CHECK(std::string(poster::state_name(RTXPOSTER_STATE_RENDERING)) == "rendering");
  CHECK(std::string(poster::state_name(99)) == "idle");
  CHECK(poster::utf8(L"screenshots/poster-26-11-15 01-02-03.png") == "screenshots/poster-26-11-15 01-02-03.png");
  // No runtime in this process: nothing is taken over.
  CHECK(!poster::runtime().ready());
  const auto status = poster::take_command();
  CHECK(!status.installed);
  CHECK(status.reason == "the RTX runtime has no poster");
}

namespace {
// A stand-in runtime whose status names the poster by the absolute path the module asked it to write, as the real one
// does (<garrysmod>\screenshots\<name>.png).
const wchar_t* g_status_path = L"";
const char* g_status_why = "";
std::uint32_t g_status_state = RTXPOSTER_STATE_DONE;
int g_status_result = RTXPOSTER_OK;
int fake_start(const rtxposter_Request*) { return RTXPOSTER_OK; }
void fake_cancel() {}
int fake_status(rtxposter_Status* status) {
  if (!status || status->structSize != sizeof(*status)) return RTXPOSTER_E_ARGUMENT;
  if (g_status_result != RTXPOSTER_OK) return g_status_result;
  *status = {};
  status->structSize = sizeof(*status);
  status->state = g_status_state;
  status->generation = 3;
  status->lastError = g_status_state == RTXPOSTER_STATE_FAILED ? RTXPOSTER_E_WRITE : RTXPOSTER_OK;
  status->width = 2560;
  status->height = 1440;
  status->columns = 3;
  status->rows = 3;
  status->tilesDone = 9;
  status->frame = 64;
  status->framesPerTile = 64;
  strncpy_s(status->lastErrorText, g_status_why, _TRUNCATE);
  wcsncpy_s(status->path, g_status_path, _TRUNCATE);
  return RTXPOSTER_OK;
}
// A drive-rooted path ("C:\", "C:/"), a share or any backslash: what names the player's folders.
bool names_folders(const std::string& text) {
  for (std::size_t i = 0; i + 2 < text.size(); ++i) {
    const unsigned char c = static_cast<unsigned char>(text[i]);
    if (((c | 0x20) >= 'a' && (c | 0x20) <= 'z') && text[i + 1] == ':' && (text[i + 2] == '\\' || text[i + 2] == '/')) return true;
  }
  return text.find('\\') != std::string::npos || text.find("//") != std::string::npos;
}
}  // namespace

TEST_CASE("poster: Lua and the console see screenshots/<name>.png, never the player's folders (review finding 18)") {
  const wchar_t* path = L"C:\\Users\\Someone\\Steam\\steamapps\\common\\GarrysMod\\garrysmod\\screenshots\\poster-26-11-16 01-02-03.png";
  CHECK(poster::shown_name(path) == "screenshots/poster-26-11-16 01-02-03.png");
  CHECK(poster::shown_name(L"D:/Games/garrysmod/Screenshots/poster.png") == "screenshots/poster.png");
  CHECK(poster::shown_name(L"C:\\Users\\J\xFCrgen\\garrysmod\\screenshots\\poster \xE9.png") == "screenshots/poster \xC3\xA9.png");
  // Anywhere else only the file's name: no share, drive or folder.
  CHECK(poster::shown_name(L"\\\\server\\share\\poster.png") == "poster.png");
  CHECK(poster::shown_name(L"C:\\Users\\Someone\\poster.png") == "poster.png");
  CHECK(poster::shown_name(L"C:poster.png") == "poster.png");
  CHECK(poster::shown_name(L"poster.png") == "poster.png");
  CHECK(poster::shown_name(L"C:\\Users\\Someone\\screenshots\\").empty());
  CHECK(poster::shown_name(L"").empty());
  CHECK(poster::shown_name(nullptr).empty());
  // The runtime's reasons name the poster the same way (today's reasons hold no path; a later one may).
  CHECK(poster::shown_reason("rename: Access is denied.: \"C:\\Users\\Someone\\Steam\\steamapps\\common\\GarrysMod\\garrysmod"
                             "\\screenshots\\poster-26-11-16 01-02-03.png.part\"", path) ==
        "rename: Access is denied.: \"screenshots/poster-26-11-16 01-02-03.png.part\"");
  CHECK(poster::shown_reason("C:\\Users\\Someone\\Steam\\steamapps\\common\\GarrysMod\\garrysmod\\screenshots is full", path) ==
        "screenshots is full");
  CHECK(poster::shown_reason("the view moved; hold still while a poster renders", path) ==
        "the view moved; hold still while a poster renders");
  CHECK(poster::shown_reason(nullptr, path).empty());
  CHECK(poster::shown_reason("cancelled", nullptr) == "cancelled");

  // PosterStatus()'s fields from a stand-in runtime whose status holds that absolute path.
  const poster::Runtime runtime{fake_start, fake_cancel, fake_status};
  g_status_path = path;
  g_status_why = "";
  g_status_state = RTXPOSTER_STATE_DONE;
  g_status_result = RTXPOSTER_OK;
  auto view = poster::view(runtime);
  REQUIRE(view.has_value());
  CHECK(std::string(view->state) == "done");
  CHECK(view->path == "screenshots/poster-26-11-16 01-02-03.png");
  CHECK(view->why.empty());
  CHECK(view->generation == 3 && view->error == RTXPOSTER_OK);
  CHECK(view->width == 2560 && view->height == 1440 && view->columns == 3 && view->rows == 3);
  CHECK(view->done == 9 && view->frame == 64 && view->frames == 64);
  CHECK(!names_folders(view->path));
  g_status_state = RTXPOSTER_STATE_FAILED;
  g_status_why = "could not open C:\\Users\\Someone\\Steam\\steamapps\\common\\GarrysMod\\garrysmod\\screenshots"
                 "\\poster-26-11-16 01-02-03.png.part";
  view = poster::view(runtime);
  REQUIRE(view.has_value());
  CHECK(std::string(view->state) == "failed");
  CHECK(view->error == RTXPOSTER_E_WRITE);
  CHECK(view->why == "could not open screenshots/poster-26-11-16 01-02-03.png.part");
  CHECK(!names_folders(view->path) && !names_folders(view->why));
  // The check itself sees what it must.
  CHECK(names_folders(poster::utf8(path)));
  CHECK(names_folders("\\\\server\\share\\poster.png"));
  CHECK(!names_folders("rename: Access is denied."));
  // Without the runtime's poster, or when its status call refuses: nothing (PosterStatus() is nil).
  CHECK(!poster::view(poster::Runtime{}).has_value());
  g_status_result = RTXPOSTER_E_ARGUMENT;
  CHECK(!poster::view(runtime).has_value());
  g_status_result = RTXPOSTER_OK;
}

TEST_CASE("poster: the module's PosterStatus pushes the view, never the runtime's path") {
  std::ifstream file(NL_ENGINE_GUARD_MODULE_SOURCE);
  REQUIRE(file.good());
  std::stringstream read;
  read << file.rdbuf();
  const std::string text = read.str();
  const auto begin = text.find("LUA_FUNCTION_STATIC(PosterStatus)");
  REQUIRE(begin != std::string::npos);
  const auto end = text.find("LUA_FUNCTION_STATIC(", begin + 1);
  REQUIRE(end != std::string::npos);
  const std::string body = text.substr(begin, end - begin);
  CHECK(body.find("poster::view(poster::runtime())") != std::string::npos);
  CHECK(body.find("status->path") != std::string::npos);
  CHECK(body.find("status->why") != std::string::npos);
  CHECK(body.find("status.path") == std::string::npos);
  CHECK(body.find("lastErrorText") == std::string::npos);
  CHECK(body.find("utf8(") == std::string::npos);
}
