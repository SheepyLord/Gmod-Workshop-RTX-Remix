#pragma once
// RTX a removed loader left in the game (ADR 0206). The loader removes the RTX package at the first start after it
// goes (an unsubscribe), but only a start that runs the loader does: when the player deletes bin\win64\winmm.dll before
// that start, or instead of unsubscribing, everything the loader deployed stays, and Garry's Mod mounts the package's
// add-on folders as ordinary add-ons: the RTX Remix tab and the RTX fixes' Lua run in a game without the runtime (the
// user's report of 2026-11-13). The RTX package's own client module is still in garrysmod/lua/bin then, and the
// companion's server Lua loads it in a local game: from there it runs the loader's own uninstall (what nlctl uninstall
// runs), so the next start is plain Garry's Mod, as the player's README promises.
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::client {
// The loader's bootstrap, relative to the game root.
inline constexpr std::string_view kBootstrapFile = "bin/win64/winmm.dll";

// Whether the native loader is installed in this game folder: bin\win64\winmm.dll is there (a start through an off
// switch still has it), or this process loaded its winmm.dll from there. True when it cannot tell.
bool loader_installed(const std::filesystem::path& root);

// Whether a Garry's Mod of this folder (bin\win64\gmod.exe) other than this game runs. This game's own Chromium
// helpers are gmod.exe processes of the same folder too; they do not count: their parents lead to this process and
// none was created before it. True when it cannot tell.
bool another_game(const std::filesystem::path& root);

// Why remove_leftovers does not apply to this game folder, or empty when it does: the loader is not installed, and
// its journal (native-loader/state.json) records the RTX package (gmod-rtx-remix) as deployed.
std::string leftovers_refusal(const std::filesystem::path& root);

struct Removed {
  // "not needed" (leftovers_refusal, in `error`), "refused" (another Garry's Mod of the folder runs, another deployment
  // holds the lock, a journal that cannot be read: nothing was changed), "removed" (nothing the loader placed is left in
  // the game, the journal is gone) or "partly removed" (something stayed; `notes` say what).
  std::string outcome;
  std::size_t deleted = 0;   // files the uninstall deleted
  std::size_t restored = 0;  // the player's own files it put back
  std::size_t former = 0;    // an earlier RTX installation's files moved to native-loader/backup/former-rtx
  std::size_t aside = 0;     // files the game held open, moved to native-loader/backup/in-use
  std::string former_folder;  // where `former` went (the originals' folder; the adopted ones' ends in "-adopted")
  std::string aside_folder;   // where `aside` went
  // The console settings RTX sessions changed, with the player's own values to put back now (the loader does it at a
  // start without RTX, ADR 0010): the module cannot set them, the companion's Lua runs them.
  std::vector<std::pair<std::string, std::string>> restore;
  std::vector<std::string> notes;
  std::string error;
};

// Removes what the loader deployed, as nlctl uninstall does, from inside the game this process runs from `root`:
// leftovers_refusal must be empty, and no other Garry's Mod of the folder may run (another_game). In order: an
// interrupted deployment is undone; the RTX package's former files (ADR 0188's originals and adopted files at its
// add-on and lua/bin paths) go to the former-rtx archive, so nothing of an earlier RTX installation is put back;
// deploy::uninstall runs without its own check for a running game (it would count this game's helpers; another_game has
// checked); what it could not delete because this game holds it open
// moves to kInUse/<stamp> and a second uninstall finishes; then the record of the console settings is marked as put
// back (native-loader/session_cvars.json, as the loader marks it). `stamp` names the archive folders (UTC time).
Removed remove_leftovers(const std::filesystem::path& root, std::string_view stamp, std::uint32_t own_process);
}  // namespace nl::client
