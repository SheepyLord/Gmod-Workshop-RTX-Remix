#pragma once
// Former RTX files (ADR 0188). When the RTX package is first deployed over files already at its add-on and
// garrysmod/lua/bin paths (an earlier RTX deployment whose journal was lost, a classic install), the loader keeps them
// in one of two ways, and an uninstall leaves both in the game: a file that differs from the package's becomes an
// original, put back when the package goes (ADR 0035); a file byte for byte the package's is adopted, which the
// loader never moves or deletes. Without the runtime that Lua then fails at once (remixbinary's require of
// RTXFixesBinary, the field on 2026-11-11). This module moves both into native-loader/backup/former-rtx/<stamp>/, which
// no loader puts back or deletes: originals in an RTX start, adopted files at the end of an RTX session, so that the
// next start places the package's own copy, which an uninstall removes.
#include "nl/journal.h"
#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace nl::client {
inline constexpr std::string_view kFormerRtx = "native-loader/backup/former-rtx";

// A file of the RTX package (gmod-rtx-remix) below garrysmod/addons/ or garrysmod/lua/bin/: code a game without RTX
// would run. Files of other packages, and Remix mods or data, are left as the loader keeps them.
bool former_rtx(const journal::File& file);

struct Archived {
  std::size_t moved = 0;
  std::string folder;              // relative to the game root; empty if nothing was moved
  std::vector<std::string> notes;  // what stayed where it was, and why
};

// Moves the kept copy (native-loader/backup/originals/<path>) of every former RTX original whose size is still the
// recorded one into kFormerRtx/<stamp>/<path>, beside an index.json naming them, while holding the deployer's lock
// (native-loader/lock); nothing moves while another deployer holds it. `stamp` is the folder's name (UTC time,
// "20261111T235959Z"; a free "-<n>" suffix is added if it is taken). Files are renamed within the volume, never
// copied or deleted; one that cannot be moved stays where it is, with a note. Never writes the journal.
Archived archive_former_rtx(const std::filesystem::path& root, const journal::Journal& journal, std::string_view stamp);

// The same for the current generation's adopted former RTX files, from their place in the game: each one whose size
// and time are still the recorded ones. The next deployment finds the path empty and installs the package's copy as
// the loader's own (deploy.cpp, Act::install). Only when the game no longer reads them: the end of a session.
Archived release_adopted(const std::filesystem::path& root, const journal::Journal& journal, std::string_view stamp);

// ADR 0206: where the RTX package's own files go that a running game holds open when RTX is removed from inside it
// (leftovers.h): Windows refuses to delete a loaded binary module but lets it be renamed.
inline constexpr std::string_view kInUse = "native-loader/backup/in-use";

// Moves each of the RTX package's `files` that is still at its place, unchanged (the recorded size and time), into
// kInUse/<stamp>/<path> under the deployer's lock, beside an index.json; the rest stays, with a note. Renamed within
// the volume, never copied or deleted; never writes the journal.
Archived set_aside_in_use(const std::filesystem::path& root, const std::vector<journal::File>& files,
                          std::string_view stamp);

// Whether a gmod.exe of this game folder other than this process runs (-multirun): its Lua may still read the files.
bool another_game_running(const std::filesystem::path& root);
}
