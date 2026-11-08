// The engine guard as a GMod binary module (R23, ADR 0130): gmcl_nlengineguard_win64.dll and
// gmsv_nlengineguard_win64.dll from the same source. The companion requires it from an autorun that
// sorts before every add-on's; the first realm to load it installs the detour for the whole process.
// Lua: nlengineguard.installed, nlengineguard.reason, nlengineguard.Status() -> table,
// nlengineguard.StartupDone([seconds]) -> recovered, nlengineguard.SetMessage(title, body) (the first call
// counts; the companion removes it from the table after its call).
#include "guard.h"
#include "watchdog.h"
#include <GarrysMod/Lua/Interface.h>

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

// nlengineguard.SetMessage(title, body): the player's message in their language; body has %s for the file.
LUA_FUNCTION_STATIC(SetMessage) {
  const char* title = LUA->IsType(1, GarrysMod::Lua::Type::String) ? LUA->GetString(1) : "";
  const char* body = LUA->IsType(2, GarrysMod::Lua::Type::String) ? LUA->GetString(2) : "";
  nl::engine_guard::watchdog::set_message(title ? title : "", body ? body : "");
  return 0;
}
}  // namespace

#ifndef NL_ENGINE_GUARD_REALM
#define NL_ENGINE_GUARD_REALM "client"
#endif

GMOD_MODULE_OPEN() {
  const auto status = nl::engine_guard::install();
  nl::engine_guard::watchdog::start(NL_ENGINE_GUARD_REALM);
  LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
  LUA->CreateTable();
  LUA->PushBool(status.installed);
  LUA->SetField(-2, "installed");
  LUA->PushString(status.reason.c_str());
  LUA->SetField(-2, "reason");
  LUA->PushCFunction(Status);
  LUA->SetField(-2, "Status");
  LUA->PushCFunction(StartupDone);
  LUA->SetField(-2, "StartupDone");
  LUA->PushCFunction(SetMessage);
  LUA->SetField(-2, "SetMessage");
  LUA->SetField(-2, "nlengineguard");
  LUA->Pop();
  return 0;
}

GMOD_MODULE_CLOSE() { return 0; }
