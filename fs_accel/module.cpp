// The load accelerator as a GMod binary module (R26, ADR 0140): gmcl_nlfsaccel_win64.dll and gmsv_nlfsaccel_win64.dll
// from one source. In RTX starts the companion's menu script requires the gmsv_ copy at menu start, and the load
// accelerator's add-on requires it from its first autorun, in the server and the client realm. The first copy to call
// Install() hooks filesystem_stdio.dll for the process; the other finds the hooks and reports them.
//
// Lua: nlfsaccel.Install() -> installed, reason; nlfsaccel.Status() -> table; nlfsaccel.SetEnabled(on);
// nlfsaccel.SetVerify(on); nlfsaccel.FindInAddon(pattern, title) -> files, dirs | nil, reason;
// nlfsaccel.Invalidate(); nlfsaccel.CountFind(served); nlfsaccel.Settled().
// E (ADR 0242), in the copy that installed the hooks (the menu realm's): nlfsaccel.PrefetchRecord(on);
// nlfsaccel.PrefetchSave(map, [last]) -> true, files, bytes | nil, reason; nlfsaccel.Prefetch([map], [budget MiB]) -> true, map |
// nil, reason; nlfsaccel.PrefetchStatus() -> table.
#include "fs_accel.h"

#include <GarrysMod/Lua/Interface.h>

#include <windows.h>

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
  set_number(LUA, "links", c.links.load());
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
  set_number(LUA, "index_build_ms", static_cast<double>(index().last_build_ms()));
  LUA->PushBool(c.settled.load() != 0);
  LUA->SetField(-2, "settled");
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

// nlfsaccel.Settled(): a map has loaded with the hooks in; the start-up marker may come off.
LUA_FUNCTION_STATIC(Settled) {
  nl::fs_accel::settle();
  return 0;
}

LUA_FUNCTION_STATIC(Invalidate) {
  index().invalidate();
  return 0;
}

// ---- E: a load's reads recorded, and read ahead for the next load (ADR 0242) ----------------------------------------

constexpr std::uint64_t kListBudget = 8ull << 30;  // what a list may name at most

// The recorder lives with the hooks: only the copy that installed them records (the menu realm's).
bool owns_hooks(std::string* why) {
  const auto result = nl::fs_accel::install_status();
  if (result.installed && !result.by_other) return true;
  if (why) *why = result.installed ? "the hooks are the module's other copy's" : "the file lookup hooks are not installed";
  return false;
}

std::wstring prefetch_folder() {
  const std::wstring garrysmod = nl::fs_accel::garrysmod_folder();
  return garrysmod.empty() ? std::wstring() : garrysmod + L"\\data\\nativeloader\\prefetch\\";
}

// The map of the last list saved (written beside the lists by the module: the menu realm cannot write files).
std::string last_map(const std::wstring& folder) {
  const HANDLE file = CreateFileW((folder + L"last.txt").c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
                                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return {};
  char text[80]{};
  DWORD got = 0;
  const BOOL ok = ReadFile(file, text, sizeof(text) - 1, &got, nullptr);
  CloseHandle(file);
  if (!ok) return {};
  std::string map(text, got);
  while (!map.empty() && (map.back() == '\n' || map.back() == '\r' || map.back() == ' ')) map.pop_back();
  return nl::fs_accel::prefetch::list_name(map).empty() ? std::string() : map;
}

void write_last(const std::wstring& folder, const std::string& map) {
  const HANDLE file = CreateFileW((folder + L"last.txt").c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  const std::string text = map + "\n";
  DWORD written = 0;
  WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr);
  CloseHandle(file);
}

// nlfsaccel.PrefetchRecord(on): true begins a record of what the next load reads (cleared); false drops it.
LUA_FUNCTION_STATIC(PrefetchRecord) {
  std::string why;
  if (!owns_hooks(&why)) {
    LUA->PushBool(false);
    LUA->PushString(why.c_str());
    return 2;
  }
  if (LUA->GetBool(1)) {
    nl::fs_accel::prefetch::record_start();
  } else {
    nl::fs_accel::prefetch::record_stop();
  }
  LUA->PushBool(true);
  return 1;
}

// nlfsaccel.PrefetchSave(map, [last]): ends the record and saves it as that map's list; with last (default true) it is
// also the list the next menu start reads ahead -> true, files, bytes | nil, reason.
LUA_FUNCTION_STATIC(PrefetchSave) {
  const std::string map = string_arg(LUA, 1);
  const bool last = !LUA->IsType(2, GarrysMod::Lua::Type::Bool) || LUA->GetBool(2);
  const std::wstring name = nl::fs_accel::prefetch::list_name(map);
  const std::wstring folder = prefetch_folder();
  std::string why;
  const bool owner = owns_hooks(&why);
  nl::fs_accel::prefetch::record_stop();
  if (!owner || name.empty() || folder.empty()) {
    LUA->PushNil();
    LUA->PushString(name.empty() ? "no map name a list may have" : folder.empty() ? "no garrysmod folder" : why.c_str());
    return 2;
  }
  std::vector<nl::fs_accel::prefetch::Entry> entries;
  bool saved = false;
  std::uint64_t blocks = 0;
  try {
    entries = nl::fs_accel::prefetch::record_list(kListBudget);
    for (const auto& entry : entries) {
      for (const auto& range : entry.ranges) blocks += range.count;
    }
    CreateDirectoryW(folder.substr(0, folder.size() - 1).c_str(), nullptr);
    if (entries.empty()) {
      why = "the load read nothing to list";
    } else {
      saved = nl::fs_accel::prefetch::save_list(folder + name, entries, &why);
    }
  } catch (...) {
    why = "out of memory";
  }
  if (!saved) {
    LUA->PushNil();
    LUA->PushString(why.c_str());
    return 2;
  }
  if (last) write_last(folder, map);
  LUA->PushBool(true);
  LUA->PushNumber(static_cast<double>(entries.size()));
  LUA->PushNumber(static_cast<double>(blocks << nl::fs_accel::prefetch::kBlockShift));
  return 3;
}

// nlfsaccel.Prefetch([map], [budget MiB]): reads ahead what that map's list names (no map: the last list saved), at
// most the budget (default: a quarter of the memory, at most 4 GiB) -> true, map | nil, reason.
LUA_FUNCTION_STATIC(Prefetch) {
  std::string map = string_arg(LUA, 1);
  const double megabytes = LUA->IsType(2, GarrysMod::Lua::Type::Number) ? LUA->GetNumber(2) : 0;
  const std::wstring folder = prefetch_folder();
  std::string why;
  if (!owns_hooks(&why) || folder.empty()) {
    LUA->PushNil();
    LUA->PushString(folder.empty() ? "no garrysmod folder" : why.c_str());
    return 2;
  }
  if (map.empty()) map = last_map(folder);
  const std::wstring name = nl::fs_accel::prefetch::list_name(map);
  if (name.empty()) {
    LUA->PushNil();
    LUA->PushString("no list");
    return 2;
  }
  const std::uint64_t budget = megabytes > 0 ? static_cast<std::uint64_t>(megabytes * 1048576.0) : 0;
  bool started = false;
  try {
    started = nl::fs_accel::prefetch::start(folder + name, budget, &why);
  } catch (...) {
    why = "out of memory";
  }
  if (!started) {
    LUA->PushNil();
    LUA->PushString(why.c_str());
    return 2;
  }
  LUA->PushBool(true);
  LUA->PushString(map.c_str());
  return 2;
}

LUA_FUNCTION_STATIC(PrefetchStatus) {
  const auto status = nl::fs_accel::prefetch::status();
  LUA->CreateTable();
  LUA->PushBool(status.recording);
  LUA->SetField(-2, "recording");
  set_number(LUA, "record_files", static_cast<double>(status.record_files));
  set_number(LUA, "record_bytes", static_cast<double>(status.record_blocks << nl::fs_accel::prefetch::kBlockShift));
  LUA->PushBool(status.running);
  LUA->SetField(-2, "running");
  set_number(LUA, "files", static_cast<double>(status.files));
  set_number(LUA, "bytes", static_cast<double>(status.bytes));
  set_number(LUA, "skipped", static_cast<double>(status.skipped));
  set_number(LUA, "seconds", status.seconds);
  LUA->PushString(status.list.c_str());
  LUA->SetField(-2, "list");
  return 1;
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
  LUA->PushCFunction(Settled);
  LUA->SetField(-2, "Settled");
  LUA->PushCFunction(PrefetchRecord);
  LUA->SetField(-2, "PrefetchRecord");
  LUA->PushCFunction(PrefetchSave);
  LUA->SetField(-2, "PrefetchSave");
  LUA->PushCFunction(Prefetch);
  LUA->SetField(-2, "Prefetch");
  LUA->PushCFunction(PrefetchStatus);
  LUA->SetField(-2, "PrefetchStatus");
  LUA->SetField(-2, "nlfsaccel");
  LUA->Pop();
  return 0;
}

GMOD_MODULE_CLOSE() { return 0; }
