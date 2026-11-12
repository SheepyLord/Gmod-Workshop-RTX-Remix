#pragma once
// Steam's per-account switch for a Workshop item (ADR 0189). Steam's own Workshop pages can switch a subscribed item
// off for one account ("Set 1 item(s) to disabled locally" in its workshop log): GMod then hides the item, but Steam
// keeps it installed and subscribed, so the installed loaders still deploy it. Steam records the switch at once in the
// account's own list, <Steam>\userdata\<account>\ugc\4000_subscriptions.vdf ("subscribedfiles", one block per item
// with "publishedfileid" and "disabled_locally").
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string_view>

namespace nl::client {
enum class SteamItem { not_listed, enabled, disabled };

// The item's state in the list's text; nullopt if the text is not Steam's list (no "subscribedfiles" block).
std::optional<SteamItem> steam_item(std::string_view subscriptions_vdf, std::string_view item);

// The same from the list of `account` (a 32-bit account id) below `steam_root`; nullopt if it cannot be read.
std::optional<SteamItem> steam_item_in(const std::filesystem::path& steam_root, std::uint32_t account,
                                       std::string_view item);

// The same for the account signed in to Steam on this computer: Steam's folder and the account from the registry
// (HKCU\Software\Valve\Steam: SteamPath; ActiveProcess\ActiveUser, which Steam writes at each login). advapi32 is
// loaded at run time, so this library adds no import. nullopt when either is missing or the list cannot be read.
std::optional<SteamItem> signed_in_steam_item(std::string_view item);
}
