// The load accelerator as a GMod binary module (R26, ADR 0140): gmcl_nlfsaccel_win64.dll and gmsv_nlfsaccel_win64.dll
// from one source. In RTX starts the companion's menu script requires the gmsv_ copy at menu start, and the load
// accelerator's add-on requires it from its first autorun, in the server and the client realm. The first copy to call
// Install() hooks filesystem_stdio.dll for the process; the other finds the hooks and reports them.
//
// Lua: nlfsaccel.Install() -> installed, reason; nlfsaccel.Status() -> table; nlfsaccel.SetEnabled(on);
// nlfsaccel.SetVerify(on); nlfsaccel.FindInAddon(pattern, title) -> files, dirs | nil, reason;
// nlfsaccel.Invalidate(); nlfsaccel.CountFind(served).
#include "fs_accel.h"

#include <GarrysMod/Lua/Interface.h>

#include <string>

namespace {
using nl::fs_accel::counters;

nl::fs_accel::AddonIndex& index() {
  static auto* value = new nl::fs_accel::AddonIndex();  // per copy of the module (per image), never freed
  return *value;
}

nl::fs_accel::TableAddress& table() {
  static nl::fs_accel::TableAddress value;
  return value;
}

std::string table_reason;
bool table_located = false;

std::string string_arg(GarrysMod::Lua::ILuaBase* LUA, int index) {
  if (!LUA->IsType(index, GarrysMod::Lua::Type::String)) return {};
  unsigned length = 0;
  const char* text = LUA->GetString(index, &length);
  return text ? std::string(text, length) : std::string();
}

void push_list(GarrysMod::Lua::ILuaBase* LUA, const std::vector<std::string>& items) {
  LUA->CreateTable();
  double position = 0;
  for (const auto& item : items) {
    LUA->PushNumber(++position);
    LUA->PushString(item.c_str(), static_cast<unsigned>(item.size()));
    LUA->SetTable(-3);
  }
}

void set_number(GarrysMod::Lua::ILuaBase* LUA, const char* name, double value) {
  LUA->PushNumber(value);
  LUA->SetField(-2, name);
}

LUA_FUNCTION_STATIC(Install) {
  const auto result = nl::fs_accel::install();
  LUA->PushBool(result.installed);
  LUA->PushString(result.reason.c_str());
  return 2;
}

LUA_FUNCTION_STATIC(Status) {
  const auto result = nl::fs_accel::install_status();
  auto& c = counters();
  LUA->CreateTable();
  LUA->PushBool(result.installed);
  LUA->SetField(-2, "installed");
  LUA->PushBool(result.by_other);
  LUA->SetField(-2, "by_other");
  LUA->PushString(result.reason.c_str());
  LUA->SetField(-2, "reason");
  LUA->PushBool(c.enabled.load() != 0);
  LUA->SetField(-2, "enabled");
  set_number(LUA, "roots", c.roots.load());
  set_number(LUA, "calls", static_cast<double>(c.calls.load()));
  set_number(LUA, "answered", static_cast<double>(c.answered.load()));
  set_number(LUA, "passed", static_cast<double>(c.passed.load()));
  set_number(LUA, "listed", static_cast<double>(c.listed.load()));
  set_number(LUA, "dropped", static_cast<double>(c.dropped.load()));
  set_number(LUA, "disagreements", static_cast<double>(c.disagreements.load()));
  set_number(LUA, "finds_served", static_cast<double>(c.finds_served.load()));
  set_number(LUA, "finds_passed", static_cast<double>(c.finds_passed.load()));
  set_number(LUA, "index_builds", static_cast<double>(index().builds()));
  set_number(LUA, "index_entries", static_cast<double>(index().entries()));
  LUA->PushString(table_reason.c_str());
  LUA->SetField(-2, "index_reason");
  return 1;
}

LUA_FUNCTION_STATIC(SetEnabled) {
  nl::fs_accel::set_enabled(LUA->GetBool(1));
  return 0;
}

LUA_FUNCTION_STATIC(SetVerify) {
  nl::fs_accel::set_verify(LUA->GetBool(1));
  return 0;
}

// nlfsaccel.FindInAddon(pattern, title) -> files, dirs (sorted by name, as file.Find's default) | nil, reason
LUA_FUNCTION_STATIC(FindInAddon) {
  const std::string pattern = string_arg(LUA, 1);
  const std::string title = string_arg(LUA, 2);
  std::string reason;
  if (!table_located) {
    table_located = nl::fs_accel::AddonIndex::locate(table(), &table_reason);
    if (!table_located) {
      LUA->PushNil();
      LUA->PushString(table_reason.c_str());
      return 2;
    }
  }
  nl::fs_accel::FindResult result;
  bool found = false;
  try {
    found = !title.empty() && index().find(table(), pattern, title, result, &reason);
  } catch (...) {
    reason = "out of memory";
  }
  if (!found) {
    LUA->PushNil();
    LUA->PushString(reason.c_str());
    return 2;
  }
  push_list(LUA, result.files);
  push_list(LUA, result.dirs);
  return 2;
}

LUA_FUNCTION_STATIC(Invalidate) {
  index().invalidate();
  return 0;
}

// nlfsaccel.CountFind(served): the add-on's file.Find wrapper reports each call it decided.
LUA_FUNCTION_STATIC(CountFind) {
  if (LUA->GetBool(1)) {
    counters().finds_served.fetch_add(1, std::memory_order_relaxed);
  } else {
    counters().finds_passed.fetch_add(1, std::memory_order_relaxed);
  }
  return 0;
}
}  // namespace

GMOD_MODULE_OPEN() {
  LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
  LUA->CreateTable();
  LUA->PushString("1");
  LUA->SetField(-2, "version");
  LUA->PushCFunction(Install);
  LUA->SetField(-2, "Install");
  LUA->PushCFunction(Status);
  LUA->SetField(-2, "Status");
  LUA->PushCFunction(SetEnabled);
  LUA->SetField(-2, "SetEnabled");
  LUA->PushCFunction(SetVerify);
  LUA->SetField(-2, "SetVerify");
  LUA->PushCFunction(FindInAddon);
  LUA->SetField(-2, "FindInAddon");
  LUA->PushCFunction(Invalidate);
  LUA->SetField(-2, "Invalidate");
  LUA->PushCFunction(CountFind);
  LUA->SetField(-2, "CountFind");
  LUA->SetField(-2, "nlfsaccel");
  LUA->Pop();
  return 0;
}

GMOD_MODULE_CLOSE() { return 0; }
