#include "steam_switch.h"
#include "nl/fs.h"
#include "nl/vdf.h"
#include <windows.h>
#include <string>

namespace nl::client {
namespace {
constexpr std::size_t kMaxBytes = std::size_t{4} << 20;

// A registry value of HKCU\Software\Valve\Steam\<key>, through advapi32 loaded from the system folder at run time
// (the bootstrap links this library and keeps a KERNEL32-only import table, as discovery.cpp does).
bool registry_value(const wchar_t* key, const wchar_t* name, DWORD flags, void* buffer, DWORD size) {
  wchar_t system[MAX_PATH]{};
  const UINT length = GetSystemDirectoryW(system, MAX_PATH);
  if (!length || length >= MAX_PATH) return false;
  const HMODULE library = LoadLibraryW((std::filesystem::path(system) / L"advapi32.dll").c_str());
  if (!library) return false;
  const auto get_value = reinterpret_cast<decltype(&RegGetValueW)>(GetProcAddress(library, "RegGetValueW"));
  const LSTATUS result = get_value ? get_value(HKEY_CURRENT_USER, key, name, flags, nullptr, buffer, &size) : ERROR_PROC_NOT_FOUND;
  FreeLibrary(library);
  return result == ERROR_SUCCESS;
}
}  // namespace

std::optional<SteamItem> steam_item(std::string_view subscriptions_vdf, std::string_view item) {
  vdf::Node top;
  try {
    top = vdf::parse(subscriptions_vdf);
  } catch (const vdf::Error&) {
    return std::nullopt;
  }
  const vdf::Node* list = top.find("subscribedfiles");
  if (!list || !list->block) return std::nullopt;
  for (const auto& [key, entry] : list->children) {
    if (!entry.block) continue;  // "appid", "time_last_updated"
    const vdf::Node* id = entry.find("publishedfileid");
    if (!id || id->block || id->value != item) continue;
    const vdf::Node* off = entry.find("disabled_locally");
    return off && !off->block && off->value == "1" ? SteamItem::disabled : SteamItem::enabled;
  }
  return SteamItem::not_listed;
}

std::optional<SteamItem> steam_item_in(const std::filesystem::path& steam_root, std::uint32_t account,
                                       std::string_view item) {
  if (account == 0 || steam_root.empty()) return std::nullopt;
  try {
    const auto file = steam_root / L"userdata" / std::to_wstring(account) / L"ugc" / L"4000_subscriptions.vdf";
    const auto found = fs::stat(file);
    if (!found.exists || found.directory || found.link) return std::nullopt;
    return steam_item(fs::read_file(file, kMaxBytes), item);
  } catch (const std::exception&) {
    return std::nullopt;
  }
}

std::optional<SteamItem> signed_in_steam_item(std::string_view item) {
  wchar_t path[1024]{};
  if (!registry_value(L"Software\\Valve\\Steam", L"SteamPath", RRF_RT_REG_SZ, path, sizeof(path))) return std::nullopt;
  DWORD account = 0;
  if (!registry_value(L"Software\\Valve\\Steam\\ActiveProcess", L"ActiveUser", RRF_RT_REG_DWORD, &account, sizeof(account))) {
    return std::nullopt;
  }
  return steam_item_in(std::filesystem::path(path), account, item);
}
}  // namespace nl::client
