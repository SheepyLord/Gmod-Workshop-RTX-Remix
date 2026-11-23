#include "disk_space.h"

#include "nl/fs.h"
#include "nl/paths.h"

#include <windows.h>

#include <limits>
#include <map>

namespace nl::client {
namespace {
std::uint64_t add(std::uint64_t a, std::uint64_t b) {
  return a > std::numeric_limits<std::uint64_t>::max() - b ? std::numeric_limits<std::uint64_t>::max() : a + b;
}
}  // namespace

std::vector<PackageFootprint> package_footprints(const nl::journal::Generation& generation) {
  std::vector<PackageFootprint> out;
  std::map<std::string, std::size_t> index;     // id -> position in out
  std::map<std::string, std::string> payloads;  // id -> payload folder (relative to the root), or empty
  for (const auto& package : generation.packages) {
    if (index.count(package.id)) continue;
    index.emplace(package.id, out.size());
    payloads.emplace(package.id, package.payload);
    out.push_back({package.id, 0, 0});
  }
  for (const auto& file : generation.files) {
    const auto it = index.find(file.package);
    if (it == index.end()) continue;
    PackageFootprint& footprint = out[it->second];
    const std::string& payload = payloads[file.package];
    if (!payload.empty() && nl::paths::within(file.path, payload)) {
      footprint.payload = add(footprint.payload, file.size);
    } else {
      footprint.files = add(footprint.files, file.size);
    }
  }
  return out;
}

std::optional<DriveSpace> drive_space(const std::filesystem::path& root) {
  std::error_code error;
  std::filesystem::path absolute = std::filesystem::absolute(root, error);
  if (error) return std::nullopt;
  std::wstring dir = absolute.native();
  if (dir.empty()) return std::nullopt;
  if (dir.back() != L'\\' && dir.back() != L'/') dir += L'\\';
  ULARGE_INTEGER available{}, total{};
  if (!GetDiskFreeSpaceExW(dir.c_str(), &available, &total, nullptr)) return std::nullopt;
  return DriveSpace{available.QuadPart, total.QuadPart, nl::fs::utf8(absolute.root_name())};
}

}  // namespace nl::client
