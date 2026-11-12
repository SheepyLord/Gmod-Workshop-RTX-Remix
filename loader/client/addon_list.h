#pragma once
// GMod's former list of disabled Workshop add-ons, garrysmod/cfg/addonnomount.txt (ADR 0189). GMod now keeps a
// disabled add-on in Steam (per account: ISteamUGC's "disabled locally"), and no longer writes this file, but the
// installed loaders (0.16.0 and earlier) read only this file as "disabled in GMod's addon list". When the player
// disables the RTX package's item in GMod's list, the RTX client module writes it here, so the next start removes RTX.
#include <filesystem>
#include <string_view>

namespace nl::client {
inline constexpr std::string_view kAddonList = "garrysmod/cfg/addonnomount.txt";

enum class ListChange { added, already_listed, removed, not_listed };

// Adds the Workshop item `id` (digits only) to the list. Every byte already in the file stays: a new "<n>" "<id>" entry
// goes before the block's closing brace, numbered after the highest number used; a missing file is created in GMod's
// own layout. Written atomically. Throws std::runtime_error (fs::Error, vdf::Error) for a path through a link, an id
// that is not a Workshop id, or a file that is not GMod's list (one "addonnomount" block and nothing else).
ListChange add_to_addon_list(const std::filesystem::path& root, std::string_view id);

// Removes every entry whose value is `id`, keeping the other lines byte for byte (a list written on one line is
// written again in GMod's layout). Throws as add_to_addon_list.
ListChange remove_from_addon_list(const std::filesystem::path& root, std::string_view id);
}
