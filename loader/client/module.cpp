#include "catalog.h"
#include "bootstrap_data.h"
#include "addon_list.h"
#include "former_rtx.h"
#include "leftovers.h"
#include "steam_switch.h"
#include "poll.h"
#include "nl/fs.h"
#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/LuaInterface.h>
#include <GarrysMod/Lua/LuaShared.h>
#include <windows.h>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>

namespace {
using GarrysMod::Lua::ILuaBase;
using GarrysMod::Lua::ILuaInterface;
using GarrysMod::Lua::ILuaShared;
namespace Type = GarrysMod::Lua::Type;
std::optional<nl::client::Catalog> catalog;
ILuaShared* shared = nullptr;
ILuaBase* menu = nullptr;
ILuaBase* server = nullptr;  // ADR 0206: the engine's server state that required this module, for NativeLoaderLeftovers
ILuaInterface* client = nullptr;
std::string status = "not initialized";
std::filesystem::path verified_root;  // the game folder of the verified RTX start (ADR 0188)
std::string rtx_item;                 // the Workshop item the verified RTX package came from, or empty (ADR 0189)
bool listed_by_us = false;            // this session wrote rtx_item into GMod's add-on list (ADR 0189)
nl::client::PollGate gate;
constexpr const char* kHook = "NativeLoader.VerifiedRTXClient";
constexpr const char* kRegistry = "NativeLoader.VerifiedRTXClient.Identity";
constexpr const char* kAttempts = "NativeLoader.VerifiedRTXClient.Attempts";
constexpr const char* kApi = "__NATIVELOADER_CLIENT_API";
// R24: the companion's menu scripts (its lua/nativeloader/menu/*.lua, verified like every other script) run once in
// the menu realm, so what the menu shows, such as the multiplayer notice, changes with the package, not the loader.
// While they run, __NATIVELOADER_MENU_API.read gives them the companion's own verified files and nothing else.
constexpr std::string_view kMenuScripts = "nativeloader/nativeloader/menu/";
constexpr std::string_view kMenuReadable = "nativeloader/";
constexpr const char* kMenuApi = "__NATIVELOADER_MENU_API";

// Menu realm only: that state is ours.
bool boolean(ILuaBase* lua, const char* key) {
  lua->GetField(GarrysMod::Lua::INDEX_GLOBAL, key);
  const bool value = lua->IsType(-1, Type::Bool) && lua->GetBool(-1);
  lua->Pop();
  return value;
}
// Client realm: server Lua may have set metamethods on _G (a __newindex could take the API), so
// every access there is raw. Pushes table[key].
void raw_get(ILuaBase* lua, int table, const char* key) {
  lua->PushSpecial(table);
  lua->PushString(key);
  lua->RawGet(-2);
  lua->Remove(-2);
}
// table[key] = the value on top of the stack, which is popped.
void raw_set(ILuaBase* lua, int table, const char* key) {
  lua->PushSpecial(table);
  lua->Insert(-2);
  lua->PushString(key);
  lua->Insert(-2);
  lua->RawSet(-3);
  lua->Pop();
}
bool raw_bool(ILuaBase* lua, const char* key) {
  raw_get(lua, GarrysMod::Lua::SPECIAL_GLOB, key);
  const bool value = lua->IsType(-1, Type::Bool) && lua->GetBool(-1);
  lua->Pop();
  return value;
}
void done(ILuaBase* lua) {
  lua->PushString(catalog->identity.c_str());
  raw_set(lua, GarrysMod::Lua::SPECIAL_REG, kRegistry);
}
bool is_done(ILuaBase* lua) {
  raw_get(lua, GarrysMod::Lua::SPECIAL_REG, kRegistry);
  unsigned length = 0;
  const char* text = lua->IsType(-1, Type::String) ? lua->GetString(-1, &length) : nullptr;
  const bool result = text && std::string_view(text, length) == std::string_view(catalog->identity);
  lua->Pop();
  return result;
}
unsigned attempts(ILuaBase* lua) {
  raw_get(lua, GarrysMod::Lua::SPECIAL_REG, kAttempts);
  const double value = lua->IsType(-1, Type::Number) ? lua->GetNumber(-1) : 0;
  lua->Pop();
  if (!(value >= 1)) return 0;
  return value >= nl::client::kMaxClientAttempts ? nl::client::kMaxClientAttempts : static_cast<unsigned>(value);
}
LUA_FUNCTION_STATIC(Read) {
  if (!catalog || LUA != client || !LUA->IsType(1, Type::String)) {
    LUA->PushNil(); LUA->PushString("RTX payload read is unavailable in this realm"); return 2;
  }
  unsigned length = 0;
  const auto* name = LUA->GetString(1, &length);
  const auto found = catalog->scripts.find(std::string(name, length));
  if (found == catalog->scripts.end()) {
    LUA->PushNil(); LUA->PushString("File is outside the verified RTX client payload"); return 2;
  }
  LUA->PushString(found->second.text.data(), static_cast<unsigned>(found->second.text.size()));
  return 1;
}
LUA_FUNCTION_STATIC(List) {
  if (!catalog || LUA != client) { LUA->PushNil(); return 1; }
  LUA->CreateTable();
  unsigned index = 0;
  for (const auto& [name, script] : catalog->scripts) {
    (void)script;
    LUA->PushNumber(++index); LUA->PushString(name.c_str()); LUA->RawSet(-3);
  }
  return 1;
}
LUA_FUNCTION_STATIC(Finish) {
  if (!catalog || LUA != client) return 0;
  status = LUA->IsType(3, Type::String) ? LUA->GetString(3) : "client payload completed";
  done(client);
  return 0;
}
// Menu realm only: a verified file of the companion add-on, by its catalog key ("nativeloader/<path under lua/>").
LUA_FUNCTION_STATIC(MenuRead) {
  if (!catalog || LUA != menu || !LUA->IsType(1, Type::String)) {
    LUA->PushNil(); LUA->PushString("RTX menu read is unavailable in this realm"); return 2;
  }
  unsigned length = 0;
  const auto* name = LUA->GetString(1, &length);
  const std::string key(name, length);
  const auto found = key.starts_with(kMenuReadable) ? catalog->scripts.find(key) : catalog->scripts.end();
  if (found == catalog->scripts.end()) {
    LUA->PushNil(); LUA->PushString("File is outside the verified companion"); return 2;
  }
  LUA->PushString(found->second.text.data(), static_cast<unsigned>(found->second.text.size()));
  return 1;
}
// ADR 0189: the companion's menu script turns RTX off when the player disables its item in GMod's add-on list, by
// writing the item into garrysmod/cfg/addonnomount.txt, the list the installed loaders read, and takes its own entry
// out again if the player enables the item before the game restarts (argument false). Only the verified RTX package's
// Workshop item, never an id from Lua; menu realm only. Returns "added", "already listed", "removed", "not listed" or
// "kept" (an entry this session did not write stays), or nil and why.
LUA_FUNCTION_STATIC(MenuAddonList) {
  if (!catalog || LUA != menu || !LUA->IsType(1, Type::Bool)) {
    LUA->PushNil(); LUA->PushString("RTX add-on list change is unavailable in this realm"); return 2;
  }
  if (rtx_item.empty()) {
    LUA->PushNil(); LUA->PushString("the RTX package does not come from a Workshop item"); return 2;
  }
  const bool off = LUA->GetBool(1);
  const char* result = "kept";
  std::string problem;
  try {
    if (off) {
      const auto change = nl::client::add_to_addon_list(verified_root, rtx_item);
      if (change == nl::client::ListChange::added) listed_by_us = true;
      result = change == nl::client::ListChange::added ? "added" : "already listed";
    } else if (listed_by_us) {
      const auto change = nl::client::remove_from_addon_list(verified_root, rtx_item);
      listed_by_us = false;
      result = change == nl::client::ListChange::removed ? "removed" : "not listed";
    }
  } catch (const std::exception& error) {
    problem = error.what();
  }
  if (!problem.empty()) {
    LUA->PushNil(); LUA->PushString(problem.c_str()); return 2;
  }
  LUA->PushString(result);
  return 1;
}
// ADR 0189: the signed-in Steam account's own switch for the verified RTX item, from Steam's per-account list
// (steam_switch.h): "disabled", "enabled", "not listed", or nil and why. Menu realm only; reads, never writes.
LUA_FUNCTION_STATIC(MenuSteamState) {
  if (!catalog || LUA != menu) {
    LUA->PushNil(); LUA->PushString("RTX Steam state is unavailable in this realm"); return 2;
  }
  if (rtx_item.empty()) {
    LUA->PushNil(); LUA->PushString("the RTX package does not come from a Workshop item"); return 2;
  }
  std::optional<nl::client::SteamItem> state;
  try {
    state = nl::client::signed_in_steam_item(rtx_item);
  } catch (...) {
    state.reset();
  }
  if (!state) {
    LUA->PushNil(); LUA->PushString("Steam's list of the signed-in account cannot be read"); return 2;
  }
  LUA->PushString(*state == nl::client::SteamItem::disabled ? "disabled"
                  : *state == nl::client::SteamItem::enabled ? "enabled" : "not listed");
  return 1;
}
// The Workshop item a generation's RTX package came from (its archive's folder), or empty for another source.
std::string workshop_item(const nl::journal::Generation& generation) {
  for (const auto& package : generation.packages) {
    if (package.id != nl::client::kPackage || package.source != "workshop") continue;
    const auto item = nl::fs::utf8(nl::fs::join({}, package.location).parent_path().filename());
    if (!item.empty() && item.size() <= 20 &&
        item.find_first_not_of("0123456789") == std::string::npos) return item;
  }
  return {};
}
// Runs the companion's menu scripts once, in catalog (name) order; each one's errors are printed by the game and end
// only that script. Returns how many ran without an error.
unsigned run_menu_scripts(ILuaBase* lua) {
  auto* state = shared ? shared->GetLuaInterface(GarrysMod::Lua::State::MENU) : nullptr;
  if (!catalog || !state || static_cast<ILuaBase*>(state) != lua) return 0;
  lua->CreateTable();
  lua->PushCFunction(MenuRead); lua->SetField(-2, "read");
  lua->PushString(catalog->identity.c_str()); lua->SetField(-2, "identity");
  lua->PushCFunction(MenuAddonList); lua->SetField(-2, "rtx_addon_list");
  lua->PushCFunction(MenuSteamState); lua->SetField(-2, "rtx_steam_state");
  lua->PushString(rtx_item.c_str()); lua->SetField(-2, "rtx_item");
  lua->SetField(GarrysMod::Lua::INDEX_GLOBAL, kMenuApi);
  unsigned ran = 0;
  for (const auto& [name, script] : catalog->scripts) {
    if (!name.starts_with(kMenuScripts) || !name.ends_with(".lua") || name.find('/', kMenuScripts.size()) != std::string::npos) continue;
    const std::string chunk = "@" + name;
    if (state->RunStringEx(chunk.c_str(), "", script.text.c_str(), true, true, true, true)) ++ran;
  }
  lua->PushNil();
  lua->SetField(GarrysMod::Lua::INDEX_GLOBAL, kMenuApi);
  return ran;
}
LUA_FUNCTION_STATIC(Status) {
  LUA->CreateTable();
  LUA->PushString(status.c_str()); LUA->SetField(-2, "status");
  LUA->PushBool(catalog.has_value()); LUA->SetField(-2, "verified");
  LUA->PushNumber(catalog ? static_cast<double>(catalog->scripts.size()) : 0); LUA->SetField(-2, "scripts");
  return 1;
}
// Runs on the client realm, called protected there by Poll: an error raised in that state outside
// a protected call would end the process. No C++ object with a destructor lives in this frame.
LUA_FUNCTION_STATIC(InitializeClient) {
  if (!catalog || LUA != client) return 0;
  if (!raw_bool(LUA, "CLIENT_DLL") || raw_bool(LUA, "SERVER") || is_done(LUA)) return 0;
  raw_get(LUA, GarrysMod::Lua::SPECIAL_GLOB, "GAMEMODE");
  const bool ready = LUA->IsType(-1, Type::Table);
  LUA->Pop();
  if (!ready) return 0;
  // The initializer declines while the local player is not valid; a realm that never gets one is
  // given up instead of being compiled again on every poll.
  const unsigned attempt = attempts(LUA) + 1;
  if (!nl::client::attempt_allowed(attempt)) {
    status = "the client realm never became ready for the verified RTX payload";
    done(LUA);
    return 0;
  }
  LUA->PushNumber(attempt);
  raw_set(LUA, GarrysMod::Lua::SPECIAL_REG, kAttempts);
  LUA->CreateTable();
  LUA->PushString("read"); LUA->PushCFunction(Read); LUA->RawSet(-3);
  LUA->PushString("list"); LUA->PushCFunction(List); LUA->RawSet(-3);
  LUA->PushString("finish"); LUA->PushCFunction(Finish); LUA->RawSet(-3);
  LUA->PushString("identity"); LUA->PushString(catalog->identity.c_str()); LUA->RawSet(-3);
  raw_set(LUA, GarrysMod::Lua::SPECIAL_GLOB, kApi);
  const bool ok = client->RunStringEx("@nativeloader/verified-client-bootstrap", "", kClientBootstrap.data(), true, false, true, true);
  LUA->PushNil();
  raw_set(LUA, GarrysMod::Lua::SPECIAL_GLOB, kApi);
  if (!ok) { status = "verified client bootstrap failed"; done(LUA); }
  return 0;
}
LUA_FUNCTION_STATIC(Poll) {
  if (LUA != menu || !catalog || !shared || !gate.due(GetTickCount64())) return 0;
  client = shared->GetLuaInterface(GarrysMod::Lua::State::CLIENT);
  if (!client) return 0;
  const int top = client->Top();
  client->PushCFunction(InitializeClient);
  if (client->PCall(0, 0, 0) != 0) status = "verified client bootstrap step failed";
  client->Pop(client->Top() - top);
  return 0;
}
std::filesystem::path module_path(HMODULE module) {
  std::wstring buffer(32768, L'\0');
  const auto size = GetModuleFileNameW(module, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (!size || size >= buffer.size()) throw std::runtime_error("Cannot resolve RTX client module path");
  buffer.resize(size);
  return std::filesystem::path(buffer).lexically_normal();
}
bool same_path(const std::filesystem::path& a, const std::filesystem::path& b) {
  const auto x = a.lexically_normal().wstring(), y = b.lexically_normal().wstring();
  return CompareStringOrdinal(x.c_str(), static_cast<int>(x.size()), y.c_str(), static_cast<int>(y.size()), TRUE) == CSTR_EQUAL;
}
ILuaShared* lua_shared() {
  const auto library = GetModuleHandleW(L"lua_shared.dll");
  using Factory = void* (__cdecl*)(const char*, int*);
  const auto factory = library ? reinterpret_cast<Factory>(GetProcAddress(library, "CreateInterface")) : nullptr;
  return factory ? static_cast<ILuaShared*>(factory(GMOD_LUASHARED_INTERFACE, nullptr)) : nullptr;
}
// The engine's own menu state. MENU_DLL alone is not enough: any realm's Lua can set that global, and a server
// realm (a listen server's add-ons) that required this module would take over `menu` and, when it closed, the
// catalog with it (R24 review).
bool is_menu_state(ILuaBase* lua) {
  auto* found = lua_shared();
  auto* state = found ? found->GetLuaInterface(GarrysMod::Lua::State::MENU) : nullptr;
  return state && static_cast<ILuaBase*>(state) == lua;
}
bool is_server_state(ILuaBase* lua) {
  auto* found = lua_shared();
  auto* state = found ? found->GetLuaInterface(GarrysMod::Lua::State::SERVER) : nullptr;
  return state && static_cast<ILuaBase*>(state) == lua;
}
// ADR 0206: the game folder of a Garry's Mod client that loaded this module from its deployed path, or nullopt and why.
// A dedicated server (srcds.exe) or another folder's game is not one.
std::optional<std::filesystem::path> client_root(std::string& why) {
  try {
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&server), &self)) throw std::runtime_error("cannot identify the RTX client module");
    const auto file = module_path(self);
    auto root = file;
    for (unsigned i = 0; i < 4; ++i) root = root.parent_path();
    if (!same_path(file, nl::fs::join(root, nl::client::kModule))) throw std::runtime_error("the RTX client module is outside its deployed path");
    if (!same_path(module_path(nullptr), nl::fs::join(root, "bin/win64/gmod.exe"))) throw std::runtime_error("this is not the Garry's Mod of the module's folder");
    return root;
  } catch (const std::exception& error) {
    why = error.what();
    return std::nullopt;
  }
}
std::string utc_stamp();
// NativeLoaderLeftovers.Check(): true when RTX a removed loader left is to be removed from this game (leftovers.h),
// else false and why. Reads only.
LUA_FUNCTION_STATIC(LeftoversCheck) {
  std::string why = "unavailable in this realm";
  if (LUA == server) {
    why.clear();
    if (const auto root = client_root(why)) why = nl::client::leftovers_refusal(*root);
  }
  LUA->PushBool(why.empty());
  LUA->PushString(why.c_str());
  return 2;
}
// NativeLoaderLeftovers.Remove(): removes it (nl::client::remove_leftovers) and returns what happened as a table:
// outcome, deleted, restored, former, aside, former_folder, aside_folder, error, notes = {text...} and
// restore = {{name, value}...}, the console settings for the caller to put back.
LUA_FUNCTION_STATIC(LeftoversRemove) {
  nl::client::Removed result;
  if (LUA != server) {
    result.outcome = "not needed";
    result.error = "unavailable in this realm";
  } else if (const auto root = client_root(result.error)) {
    try {
      result = nl::client::remove_leftovers(*root, utc_stamp(), GetCurrentProcessId());
    } catch (const std::exception& error) {
      result.outcome = "refused";
      result.error = error.what();
    }
  } else {
    result.outcome = "not needed";
  }
  LUA->CreateTable();
  LUA->PushString(result.outcome.c_str()); LUA->SetField(-2, "outcome");
  LUA->PushNumber(static_cast<double>(result.deleted)); LUA->SetField(-2, "deleted");
  LUA->PushNumber(static_cast<double>(result.restored)); LUA->SetField(-2, "restored");
  LUA->PushNumber(static_cast<double>(result.former)); LUA->SetField(-2, "former");
  LUA->PushNumber(static_cast<double>(result.aside)); LUA->SetField(-2, "aside");
  LUA->PushString(result.former_folder.c_str()); LUA->SetField(-2, "former_folder");
  LUA->PushString(result.aside_folder.c_str()); LUA->SetField(-2, "aside_folder");
  LUA->PushString(result.error.c_str()); LUA->SetField(-2, "error");
  LUA->CreateTable();
  for (std::size_t i = 0; i < result.notes.size(); ++i) {
    LUA->PushNumber(static_cast<double>(i + 1)); LUA->PushString(result.notes[i].c_str()); LUA->RawSet(-3);
  }
  LUA->SetField(-2, "notes");
  LUA->CreateTable();
  for (std::size_t i = 0; i < result.restore.size(); ++i) {
    LUA->PushNumber(static_cast<double>(i + 1));
    LUA->CreateTable();
    LUA->PushNumber(1); LUA->PushString(result.restore[i].first.c_str()); LUA->RawSet(-3);
    LUA->PushNumber(2); LUA->PushString(result.restore[i].second.c_str()); LUA->RawSet(-3);
    LUA->RawSet(-3);
  }
  LUA->SetField(-2, "restore");
  return 1;
}
// The server realm's part: NativeLoaderLeftovers, set raw (add-ons' Lua may have set metamethods on _G).
void expose_leftovers(ILuaBase* lua) {
  server = lua;
  lua->CreateTable();
  lua->PushString("Check"); lua->PushCFunction(LeftoversCheck); lua->RawSet(-3);
  lua->PushString("Remove"); lua->PushCFunction(LeftoversRemove); lua->RawSet(-3);
  raw_set(lua, GarrysMod::Lua::SPECIAL_GLOB, "NativeLoaderLeftovers");
}
std::string utc_stamp() {
  SYSTEMTIME now{};
  GetSystemTime(&now);
  char stamp[32];
  std::snprintf(stamp, sizeof stamp, "%04u%02u%02uT%02u%02u%02uZ", now.wYear, now.wMonth, now.wDay, now.wHour,
                now.wMinute, now.wSecond);
  return stamp;
}
// ADR 0188: in a verified RTX start, the files the RTX package displaced at its add-on and lua/bin paths go to
// native-loader/backup/former-rtx, so that uninstalling the package does not put an earlier RTX installation back.
// Never stops the module: what it did or left is added to the status line.
std::string archive_former_rtx(const std::filesystem::path& root, const nl::journal::Journal& journal) {
  try {
    const auto result = nl::client::archive_former_rtx(root, journal, utc_stamp());
    std::string text;
    if (result.moved) text += "; former RTX files kept at " + result.folder + ": " + std::to_string(result.moved);
    if (!result.notes.empty()) {
      text += "; former RTX files left: " + std::to_string(result.notes.size()) + " (" + result.notes.front() + ")";
    }
    return text;
  } catch (const std::exception& error) {
    return std::string("; former RTX files not archived: ") + error.what();
  }
}
// ADR 0188: when the menu state closes with the game and no client realm is left, the RTX package's adopted former
// files (an earlier copy of its own add-on and lua/bin files, which the loader never deletes) go to
// native-loader/backup/former-rtx as well; the next start places the package's own copies, which an uninstall
// removes. Only for the game folder verified at the start; never throws.
void release_adopted_files() noexcept {
  try {
    if (!catalog || verified_root.empty()) return;
    if (shared && shared->GetLuaInterface(GarrysMod::Lua::State::CLIENT)) return;  // a game may still read them
    if (nl::client::another_game_running(verified_root)) return;                   // -multirun: so may another
    const auto journal = nl::journal::load(verified_root);
    if (!journal || !journal->current || journal->pending) return;
    nl::client::release_adopted(verified_root, *journal, utc_stamp() + "-adopted");
  } catch (...) {
  }
}
void hook(ILuaBase* lua, bool add) {
  const int top = lua->Top();
  lua->GetField(GarrysMod::Lua::INDEX_GLOBAL, "hook");
  lua->GetField(-1, add ? "Add" : "Remove");
  lua->PushString("Think"); lua->PushString(kHook);
  if (add) lua->PushCFunction(Poll);
  const int result = lua->PCall(add ? 3 : 2, 0, 0);
  lua->Pop(lua->Top() - top);
  if (result != 0) throw std::runtime_error("Menu Think hook is unavailable");
}
}

GMOD_MODULE_OPEN() {
  if (!boolean(LUA, "MENU_DLL") || !is_menu_state(LUA)) {
    // ADR 0206: in the engine's server state (a local game), only the clean-up of RTX a removed loader left.
    if (is_server_state(LUA)) expose_leftovers(LUA);
    return 0;
  }
  if (menu == LUA && catalog) return 0;
  try {
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(&catalog), &self)) throw std::runtime_error("Cannot identify RTX client bootstrap");
    const auto file = module_path(self);
    auto root = file;
    for (unsigned i = 0; i < 4; ++i) root = root.parent_path();
    if (!same_path(file, nl::fs::join(root, nl::client::kModule))) throw std::runtime_error("RTX bootstrap is outside its deployed path");
    const auto journal = nl::journal::load(root);
    if (!journal || !journal->current || journal->pending) throw std::runtime_error("There is no committed RTX deployment");
    auto snapshot = nl::client::prepare(root, nl::config::load(root), *journal->current);
    const auto runtime = GetModuleHandleW(L"d3d9.dll");
    if (!runtime || !same_path(module_path(runtime), nl::fs::join(root, snapshot.runtime)))
      throw std::runtime_error("The owned RTX runtime is not active");
    shared = lua_shared();
    if (!shared) throw std::runtime_error("The Lua shared interface is unavailable");
    // The owned environments keep api.read and the other callbacks reachable for the client
    // realm's lifetime, longer than the menu's require reference: never unload this code.
    HMODULE pinned = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                            reinterpret_cast<LPCWSTR>(&catalog), &pinned)) throw std::runtime_error("Cannot keep the RTX client bootstrap loaded");
    catalog = std::move(snapshot);
    menu = LUA;
    verified_root = root;
    rtx_item = workshop_item(*journal->current);
    listed_by_us = false;
    status = "verified; waiting for the client realm";
    status += archive_former_rtx(root, *journal);
    hook(LUA, true);
    status += "; menu scripts " + std::to_string(run_menu_scripts(LUA));
  } catch (const std::exception& error) {
    status = error.what(); catalog.reset(); shared = nullptr; menu = nullptr;
  }
  LUA->CreateTable(); LUA->PushCFunction(Status); LUA->SetField(-2, "Status");
  LUA->SetField(GarrysMod::Lua::INDEX_GLOBAL, "NativeLoaderRTXClient");
  LUA->GetField(GarrysMod::Lua::INDEX_GLOBAL, "MsgN");
  if (LUA->IsType(-1, Type::Function)) {
    LUA->PushString(("[NativeLoader RTX menu] " + status).c_str());
    if (LUA->PCall(1, 0, 0) != 0) LUA->Pop();
  } else LUA->Pop();
  return 0;
}
GMOD_MODULE_CLOSE() {
  if (server == LUA) server = nullptr;
  if (menu == LUA) {
    try { hook(LUA, false); } catch (...) { }
    release_adopted_files();
    menu = nullptr; client = nullptr; shared = nullptr; catalog.reset(); verified_root.clear(); rtx_item.clear();
  }
  return 0;
}
