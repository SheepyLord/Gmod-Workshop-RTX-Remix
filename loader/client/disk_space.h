#pragma once
// ADR 0260: the free space of the game's drive and what each deployed package holds, for the companion's menu notice
// about disk space (lua/nativeloader/menu/disk_space.lua). The loader (winmm.dll) checks the space before it unpacks
// an update and keeps the deployed versions when there is too little; this only lets the package say so, and warn
// before it happens.
#include "nl/journal.h"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace nl::client {

// One deployed package: what its payload folder holds (unpacked whole for every new version) and what its other files
// hold (unpacked again when they change).
struct PackageFootprint {
  std::string id;
  std::uint64_t payload = 0;
  std::uint64_t files = 0;
};

// Per package of the generation, in the generation's order (each id once); files of a package the generation does not
// list are left out. Sums saturate.
std::vector<PackageFootprint> package_footprints(const nl::journal::Generation& generation);

struct DriveSpace {
  std::uint64_t available = 0;  // free for this user, as the loader reads it before it unpacks
  std::uint64_t total = 0;      // the whole volume
  std::string drive;            // the root's drive, such as "H:" (UTF-8), or empty
};

// The space of the volume that holds `root` (GetDiskFreeSpaceExW, as the loader measures it); nullopt when Windows
// cannot tell.
std::optional<DriveSpace> drive_space(const std::filesystem::path& root);

}  // namespace nl::client
