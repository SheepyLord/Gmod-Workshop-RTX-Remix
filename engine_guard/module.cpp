// The engine guard as a GMod binary module (R23, ADR 0130): gmcl_nlengineguard_win64.dll and
// gmsv_nlengineguard_win64.dll from the same source. The companion requires it from an autorun that
// sorts before every add-on's; the first realm to load it installs the detour for the whole process.
// Lua: nlengineguard.installed, nlengineguard.reason, nlengineguard.Status() -> table,
// nlengineguard.StartupDone([seconds]) -> recovered, nlengineguard.SetMessage(title, body) (the first call
// counts; the companion removes it from the table after its call).
// R24 (ADR 0134): in the menu realm (the companion's menu script requires the gmsv_ copy there at menu start) it
// installs the guard and drives the load overlay instead: nlengineguard.LoadStart(heading, {lua=, file=}),
// LoadHeading(text), LoadStatus(text), LoadEnd() -> {seconds=, lua={{name=, seconds=}, ...}}. No watchdog runs
// there, and the client and server realms, where any server's Lua runs, have no overlay functions: the menu realm is
// the engine's own menu state (lua_shared's interface), never the MENU_DLL global, which any Lua can set, and only the
// gmsv_ copy (the one the menu loads) has the overlay functions at all (NL_ENGINE_GUARD_MENU).
// R28 (ADR 0142): every realm's load also switches off Windows Error Reporting's snapshot of this process
// (crash_report.h); nlengineguard.crash_snapshots_off and .crash_snapshots say how that went.
// ADR 0190: every realm's load also caps material colours above 1 for Remix (colour_cap.h, Remix starts only);
// nlengineguard.colour_cap says how that went, nlengineguard.ColourCap([enabled]) -> enabled, capped switches it
// for a comparison and counts the calls it capped.
// ADR 0214 and 0215 (menu realm only, like the rest of the overlay): LoadSettling() keeps the overlay up after the
// engine's load until the game runs steadily, LoadExpect(seconds, confidence) gives it the estimated end of the wait,
// LoadTimes() -> text and LoadTimesSave(text) -> saved read and replace the history the estimate is learned from
// (garrysmod/data/nativeloader/load_times.txt). LoadStart's labels gain the activity line's and the estimate's words.
// ADR 0226 (GitHub issue 3; the gmcl_ copy, in an RTX start): the client realm's load takes GMod's `poster` command
// over for the process, and RTX renders the poster in tiles of the window's size (poster.h); nlengineguard.poster says
// how that went, nlengineguard.PosterStatus() -> {state=, ...} or nil reads the runtime's poster (read only), and a
// Think hook (nlengineguard_poster) prints the poster's console lines from the main thread.
// ADR 0247: every realm's load also checks the material system's queued render calls before the game leaves threaded
// rendering (queue_check.h, Remix starts only); nlengineguard.queue_check says how that went and
// nlengineguard.QueueCheck() -> checks, dropped counts the checks and the stale calls they dropped (read only).
#include "colour_cap.h"
#include "crash_report.h"
#include "guard.h"
#include "load_overlay.h"
#include "poster.h"
#include "queue_check.h"
#include "watchdog.h"
#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/LuaInterface.h>
#include <GarrysMod/Lua/LuaShared.h>
#include <windows.h>
#include <string>

#ifndef NL_ENGINE_GUARD_MENU
#define NL_ENGINE_GUARD_MENU 0
#endif

namespace {
void push_status(GarrysMod::Lua::ILuaBase* LUA, const nl::engine_guard::Status& status) {
  LUA->CreateTable();
  LUA->PushBool(status.installed);
  LUA->SetField(-2, "installed");
  LUA->PushString(status.reason.c_str());
  LUA->SetField(-2, "reason");
  LUA->PushNumber(static_cast<double>(status.site_rva));
  LUA->SetField(-2, "site");
  LUA->PushNumber(static_cast<double>(status.cut));
  LUA->SetField(-2, "cut");
  LUA->PushString(status.last_material.c_str());
  LUA->SetField(-2, "last_material");
  LUA->PushString(status.last_fallback.c_str());
  LUA->SetField(-2, "last_fallback");
}

LUA_FUNCTION_STATIC(Status) {
  push_status(LUA, nl::engine_guard::status());
  return 1;
}

// nlengineguard.StartupDone() -> recovered: start-up reached the game; the watchdog stands down. True when
// this start was reported as stalled and went on after all. StartupDone(seconds): the gamemode has loaded;
// the watch ends at the latest that many seconds later (returns false).
LUA_FUNCTION_STATIC(StartupDone) {
  if (LUA->IsType(1, GarrysMod::Lua::Type::Number)) {
    const double seconds = LUA->GetNumber(1);
    if (seconds > 0 && seconds < 3600) {
      nl::engine_guard::watchdog::finish_after(static_cast<std::uint64_t>(seconds * 1000));
      LUA->PushBool(false);
      return 1;
    }
  }
  LUA->PushBool(nl::engine_guard::watchdog::done());
  return 1;
}

// nlengineguard.ColourCap([enabled]) -> enabled, capped: material colours above 1 capped at 1 for Remix (ADR 0190).
// A boolean switches it for the process (both copies share it); capped counts the colour calls it changed.
LUA_FUNCTION_STATIC(ColourCap) {
  namespace cap = nl::engine_guard::colour_cap;
  const auto status = LUA->IsType(1, GarrysMod::Lua::Type::Bool) ? cap::set_enabled(LUA->GetBool(1)) : cap::status();
  LUA->PushBool(status.enabled);
  LUA->PushNumber(static_cast<double>(status.capped));
  return 2;
}

// nlengineguard.QueueCheck() -> checks, dropped: the checks of the queued render calls made before the game left
// threaded rendering, and the stale calls they dropped (ADR 0247). Read only, every realm.
LUA_FUNCTION_STATIC(QueueCheck) {
  const auto status = nl::engine_guard::queue_check::status();
  LUA->PushNumber(static_cast<double>(status.checks));
  LUA->PushNumber(static_cast<double>(status.dropped));
  return 2;
}

// nlengineguard.SetMessage(title, body): the player's message in their language; body has %s for the file.
LUA_FUNCTION_STATIC(SetMessage) {
  const char* title = LUA->IsType(1, GarrysMod::Lua::Type::String) ? LUA->GetString(1) : "";
  const char* body = LUA->IsType(2, GarrysMod::Lua::Type::String) ? LUA->GetString(2) : "";
  nl::engine_guard::watchdog::set_message(title ? title : "", body ? body : "");
  return 0;
}

#if NL_ENGINE_GUARD_MENU
std::string text_arg(GarrysMod::Lua::ILuaBase* LUA, int index) {
  if (!LUA->IsType(index, GarrysMod::Lua::Type::String)) return {};
  unsigned length = 0;
  const char* text = LUA->GetString(index, &length);
  return text ? std::string(text, length) : std::string();
}

std::string field(GarrysMod::Lua::ILuaBase* LUA, int table, const char* name, const char* fallback) {
  if (!LUA->IsType(table, GarrysMod::Lua::Type::Table)) return fallback;
  LUA->GetField(table, name);
  std::string value = LUA->IsType(-1, GarrysMod::Lua::Type::String) ? std::string(LUA->GetString(-1)) : std::string(fallback);
  LUA->Pop();
  return value;
}

// Menu realm only. nlengineguard.LoadStart(heading, labels): the loading panel activated. labels: the window's words
// in the player's language (lua, file; ADR 0214: remix, scripts, spawnmenu, files; ADR 0215: secondsLeft,
// minutesLeft, secondsRough, minutesRough, longer, learning); a missing one keeps its English.
LUA_FUNCTION_STATIC(LoadStart) {
  nl::engine_guard::overlay::Labels labels;
  const nl::engine_guard::overlay::Labels english;
  labels.lua = field(LUA, 2, "lua", english.lua.c_str());
  labels.file = field(LUA, 2, "file", english.file.c_str());
  labels.remix = field(LUA, 2, "remix", english.remix.c_str());
  labels.scripts = field(LUA, 2, "scripts", english.scripts.c_str());
  labels.spawnmenu = field(LUA, 2, "spawnmenu", english.spawnmenu.c_str());
  labels.files = field(LUA, 2, "files", english.files.c_str());
  labels.seconds_left = field(LUA, 2, "secondsLeft", english.seconds_left.c_str());
  labels.minutes_left = field(LUA, 2, "minutesLeft", english.minutes_left.c_str());
  labels.seconds_rough = field(LUA, 2, "secondsRough", english.seconds_rough.c_str());
  labels.minutes_rough = field(LUA, 2, "minutesRough", english.minutes_rough.c_str());
  labels.longer = field(LUA, 2, "longer", english.longer.c_str());
  labels.learning = field(LUA, 2, "learning", english.learning.c_str());
  nl::engine_guard::overlay::start(text_arg(LUA, 1), labels);
  return 0;
}

// nlengineguard.LoadExpect(seconds, confidence): the whole wait should last `seconds` from LoadStart; confidence 2
// good, 1 rough, 0 none (no estimate: the window says the load is timed for the next one). ADR 0215.
LUA_FUNCTION_STATIC(LoadExpect) {
  const double seconds = LUA->IsType(1, GarrysMod::Lua::Type::Number) ? LUA->GetNumber(1) : 0.0;
  const double level = LUA->IsType(2, GarrysMod::Lua::Type::Number) ? LUA->GetNumber(2) : 0.0;
  using nl::engine_guard::overlay::Confidence;
  const Confidence confidence = level >= 2 ? Confidence::good : level >= 1 ? Confidence::rough : Confidence::none;
  nl::engine_guard::overlay::expect(seconds, confidence);
  return 0;
}

// nlengineguard.LoadSettling(): the engine's load ended; the window stays until LoadEnd() (ADR 0214).
LUA_FUNCTION_STATIC(LoadSettling) {
  nl::engine_guard::overlay::settling();
  return 0;
}

// nlengineguard.LoadTimes() -> text or nil: garrysmod/data/nativeloader/load_times.txt (ADR 0215).
LUA_FUNCTION_STATIC(LoadTimes) {
  const auto text = nl::engine_guard::overlay::history();
  if (!text) {
    LUA->PushNil();
    return 1;
  }
  LUA->PushString(text->data(), static_cast<unsigned>(text->size()));
  return 1;
}

// nlengineguard.LoadTimesSave(text) -> saved: replaces that file (at most 64 KiB, no NUL); the menu realm cannot
// write files itself.
LUA_FUNCTION_STATIC(LoadTimesSave) {
  if (!LUA->IsType(1, GarrysMod::Lua::Type::String)) {
    LUA->PushBool(false);
    return 1;
  }
  unsigned length = 0;
  const char* text = LUA->GetString(1, &length);
  LUA->PushBool(text && nl::engine_guard::overlay::save_history(std::string_view(text, length)));
  return 1;
}

LUA_FUNCTION_STATIC(LoadHeading) {
  nl::engine_guard::overlay::heading(text_arg(LUA, 1));
  return 0;
}

LUA_FUNCTION_STATIC(LoadStatus) {
  nl::engine_guard::overlay::status(text_arg(LUA, 1));
  return 0;
}

// nlengineguard.LoadEnd() -> {seconds = n, loading = n, lua = {{name = "lua/x.lua", seconds = n}, ...},
// activity = {remix = n, scripts = n, spawnmenu = n, files = n}}: the whole wait, the engine's load (to
// LoadSettling), the Lua files seen running longest and the seconds the main thread was seen in each activity.
LUA_FUNCTION_STATIC(LoadEnd) {
  using nl::engine_guard::overlay::Activity;
  const auto summary = nl::engine_guard::overlay::finish();
  LUA->CreateTable();
  LUA->PushNumber(summary.seconds);
  LUA->SetField(-2, "seconds");
  LUA->PushNumber(summary.loading);
  LUA->SetField(-2, "loading");
  LUA->CreateTable();
  double index = 0;
  for (const auto& [name, seconds] : summary.lua) {
    LUA->PushNumber(++index);
    LUA->CreateTable();
    LUA->PushString(name.c_str());
    LUA->SetField(-2, "name");
    LUA->PushNumber(seconds);
    LUA->SetField(-2, "seconds");
    LUA->SetTable(-3);
  }
  LUA->SetField(-2, "lua");
  LUA->CreateTable();
  const std::pair<Activity, const char*> activities[] = {
      {Activity::remix, "remix"}, {Activity::scripts, "scripts"}, {Activity::spawnmenu, "spawnmenu"}, {Activity::files, "files"}};
  for (const auto& [activity, name] : activities) {
    LUA->PushNumber(summary.activity[static_cast<std::size_t>(activity)]);
    LUA->SetField(-2, name);
  }
  LUA->SetField(-2, "activity");
  return 1;
}

// The engine's own menu state, from lua_shared's interface: a client or server realm cannot pass for it.
bool menu_realm(GarrysMod::Lua::ILuaBase* LUA) {
  const auto library = GetModuleHandleW(L"lua_shared.dll");
  using Factory = void*(__cdecl*)(const char*, int*);
  const auto factory = library ? reinterpret_cast<Factory>(GetProcAddress(library, "CreateInterface")) : nullptr;
  auto* shared = factory ? static_cast<GarrysMod::Lua::ILuaShared*>(factory(GMOD_LUASHARED_INTERFACE, nullptr)) : nullptr;
  auto* state = shared ? shared->GetLuaInterface(GarrysMod::Lua::State::MENU) : nullptr;
  return state && static_cast<GarrysMod::Lua::ILuaBase*>(state) == LUA;
}
#else
bool menu_realm(GarrysMod::Lua::ILuaBase*) { return false; }  // gmcl_: never the menu's

// nlengineguard.PosterStatus() -> {state = "idle"|"starting"|"rendering"|"writing"|"done"|"failed", generation =,
// error =, why =, width =, height =, columns =, rows =, done =, frame =, frames =, path =}, or nil without the
// runtime's poster (ADR 0226). Read only: the companion's sky holds its clock while a poster renders. Any client Lua,
// a server's included, can call it: path is "screenshots/<name>.png", never the absolute path the runtime writes,
// and why names the poster the same way (poster::view; review finding 18).
LUA_FUNCTION_STATIC(PosterStatus) {
  namespace poster = nl::engine_guard::poster;
  const auto status = poster::view(poster::runtime());
  if (!status) {
    LUA->PushNil();
    return 1;
  }
  LUA->CreateTable();
  LUA->PushString(status->state);
  LUA->SetField(-2, "state");
  const std::pair<const char*, double> numbers[] = {
      {"generation", status->generation}, {"error", status->error}, {"width", status->width}, {"height", status->height},
      {"columns", status->columns}, {"rows", status->rows}, {"done", status->done}, {"frame", status->frame},
      {"frames", status->frames}};
  for (const auto& [name, value] : numbers) {
    LUA->PushNumber(value);
    LUA->SetField(-2, name);
  }
  LUA->PushString(status->why.c_str());
  LUA->SetField(-2, "why");
  LUA->PushString(status->path.c_str());
  LUA->SetField(-2, "path");
  return 1;
}

// The client realm's Think hook "nlengineguard_poster": the console's lines about the poster the command started, from
// the main thread (poster.h's poll).
LUA_FUNCTION_STATIC(PosterThink) {
  nl::engine_guard::poster::poll();
  return 0;
}

void add_poster_hook(GarrysMod::Lua::ILuaBase* LUA) {
  LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
  LUA->GetField(-1, "hook");
  if (LUA->IsType(-1, GarrysMod::Lua::Type::Table)) {
    LUA->GetField(-1, "Add");
    if (LUA->IsType(-1, GarrysMod::Lua::Type::Function)) {
      LUA->PushString("Think");
      LUA->PushString("nlengineguard_poster");
      LUA->PushCFunction(PosterThink);
      if (LUA->PCall(3, 0, 0) != 0) LUA->Pop();  // the error message
    } else {
      LUA->Pop();
    }
  }
  LUA->Pop(2);
}
#endif
}  // namespace

#ifndef NL_ENGINE_GUARD_REALM
#define NL_ENGINE_GUARD_REALM "client"
#endif

GMOD_MODULE_OPEN() {
  const auto status = nl::engine_guard::install();
  const auto snapshots = nl::engine_guard::crash_report::disable_snapshots();
  const auto colours = nl::engine_guard::colour_cap::install();
  const auto queue = nl::engine_guard::queue_check::install();
  const bool menu = menu_realm(LUA);
  if (!menu) nl::engine_guard::watchdog::start(NL_ENGINE_GUARD_REALM);
#if !NL_ENGINE_GUARD_MENU
  nl::engine_guard::poster::Status poster;
#endif
  LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
  LUA->CreateTable();
  LUA->PushBool(status.installed);
  LUA->SetField(-2, "installed");
  LUA->PushString(status.reason.c_str());
  LUA->SetField(-2, "reason");
  LUA->PushCFunction(Status);
  LUA->SetField(-2, "Status");
  LUA->PushBool(snapshots.applied);
  LUA->SetField(-2, "crash_snapshots_off");
  LUA->PushString(snapshots.reason.c_str());
  LUA->SetField(-2, "crash_snapshots");
  LUA->PushString(colours.reason.c_str());
  LUA->SetField(-2, "colour_cap");
  LUA->PushCFunction(ColourCap);
  LUA->SetField(-2, "ColourCap");
  LUA->PushString(queue.reason.c_str());
  LUA->SetField(-2, "queue_check");
  LUA->PushCFunction(QueueCheck);
  LUA->SetField(-2, "QueueCheck");
  if (menu) {
#if NL_ENGINE_GUARD_MENU
    LUA->PushCFunction(LoadStart);
    LUA->SetField(-2, "LoadStart");
    LUA->PushCFunction(LoadHeading);
    LUA->SetField(-2, "LoadHeading");
    LUA->PushCFunction(LoadStatus);
    LUA->SetField(-2, "LoadStatus");
    LUA->PushCFunction(LoadExpect);
    LUA->SetField(-2, "LoadExpect");
    LUA->PushCFunction(LoadSettling);
    LUA->SetField(-2, "LoadSettling");
    LUA->PushCFunction(LoadEnd);
    LUA->SetField(-2, "LoadEnd");
    LUA->PushCFunction(LoadTimes);
    LUA->SetField(-2, "LoadTimes");
    LUA->PushCFunction(LoadTimesSave);
    LUA->SetField(-2, "LoadTimesSave");
#endif
  } else {
    LUA->PushCFunction(StartupDone);
    LUA->SetField(-2, "StartupDone");
    LUA->PushCFunction(SetMessage);
    LUA->SetField(-2, "SetMessage");
#if !NL_ENGINE_GUARD_MENU
    // The client realm (ADR 0226): GMod's poster command, when this start's runtime renders posters.
    poster = nl::engine_guard::poster::take_command();
    LUA->PushString(poster.reason.c_str());
    LUA->SetField(-2, "poster");
    LUA->PushCFunction(PosterStatus);
    LUA->SetField(-2, "PosterStatus");
#endif
  }
  LUA->SetField(-2, "nlengineguard");
  LUA->Pop();
#if !NL_ENGINE_GUARD_MENU
  if (poster.installed) add_poster_hook(LUA);
#endif
  return 0;
}

GMOD_MODULE_CLOSE() { return 0; }
