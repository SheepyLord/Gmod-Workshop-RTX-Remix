#include "disk_space.h"
#include "nl/fs.h"
#include "nl_test.h"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <string>
#include <string_view>

namespace {
nl::journal::File file(std::string path, std::string package, std::uint64_t size) {
  nl::journal::File f;
  f.path = std::move(path);
  f.package = std::move(package);
  f.size = size;
  return f;
}
nl::journal::Package package(std::string id, std::string payload) {
  nl::journal::Package p;
  p.id = std::move(id);
  p.payload = std::move(payload);
  return p;
}
std::string module_source() { return nl::fs::read_file(NL_CLIENT_MODULE_SOURCE, std::size_t{1} << 20); }
// The function that starts at `signature`, up to its closing brace in the first column.
std::string body(const std::string& text, std::string_view signature) {
  const auto begin = text.find(signature);
  if (begin == std::string::npos) return {};
  const auto end = text.find("\n}", begin + signature.size());
  return text.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
}
}  // namespace

TEST_CASE("disk space: a package's payload folder and its other files are summed apart (ADR 0260)") {
  nl::journal::Generation generation;
  generation.packages = {package("gmod-rtx-remix", "native-loader/packages/gmod-rtx-remix/1.0_5"), package("map-pack", ""),
                         package("gmod-rtx-remix", "elsewhere")};  // an id listed twice counts once, as first listed
  generation.files = {
      file("native-loader/packages/gmod-rtx-remix/1.0_5/runtime/d3d9.dll", "gmod-rtx-remix", 1000),
      file("Native-Loader/Packages/GMOD-rtx-remix/1.0_5/config/a.conf", "gmod-rtx-remix", 10),  // Windows' case rules
      file("native-loader/packages/gmod-rtx-remix/1.0_50/x.dll", "gmod-rtx-remix", 7),          // a sibling, not the payload
      file("garrysmod/addons/nativeloader/lua/a.lua", "gmod-rtx-remix", 100),
      file("rtx-remix/mods/map/a.dds", "map-pack", 5000),
      file("rtx-remix/mods/other/b.dds", "not-deployed", 9),  // a package the generation does not list
  };
  const auto out = nl::client::package_footprints(generation);
  REQUIRE(out.size() == 2);
  CHECK(out[0].id == "gmod-rtx-remix");
  CHECK(out[0].payload == 1010);
  CHECK(out[0].files == 107);
  CHECK(out[1].id == "map-pack");
  CHECK(out[1].payload == 0);
  CHECK(out[1].files == 5000);
  CHECK(nl::client::package_footprints(nl::journal::Generation{}).empty());
}

TEST_CASE("disk space: sizes saturate instead of wrapping around") {
  nl::journal::Generation generation;
  generation.packages = {package("big", "native-loader/packages/big/1_1")};
  const auto max = std::numeric_limits<std::uint64_t>::max();
  generation.files = {file("native-loader/packages/big/1_1/a", "big", max), file("native-loader/packages/big/1_1/b", "big", 5),
                      file("rtx-remix/mods/big/c", "big", max), file("rtx-remix/mods/big/d", "big", max)};
  const auto out = nl::client::package_footprints(generation);
  REQUIRE(out.size() == 1);
  CHECK(out[0].payload == max);
  CHECK(out[0].files == max);
}

TEST_CASE("disk space: the drive's free space is Windows' answer for the game folder") {
  const auto space = nl::client::drive_space(std::filesystem::current_path());
  REQUIRE(space.has_value());
  CHECK(space->total > 0);
  CHECK(space->available <= space->total);
  REQUIRE(space->drive.size() == 2);
  CHECK(space->drive[1] == ':');
  // A volume that does not exist: no answer, never a made-up one.
  CHECK(!nl::client::drive_space(L"\\\\?\\Volume{00000000-0000-0000-0000-000000000000}\\").has_value());
}

TEST_CASE("client module: disk_space answers in the menu realm only, from the verified game folder (ADR 0260)") {
  const auto text = module_source();
  const auto api = body(text, "LUA_FUNCTION_STATIC(MenuDiskSpace)");
  REQUIRE(!api.empty());
  CHECK(api.find("LUA != menu") != std::string::npos);
  CHECK(api.find("drive_space(verified_root)") != std::string::npos);
  CHECK(api.find("footprints") != std::string::npos);
  // Offered with the other menu helpers, and the sizes are taken from the committed generation before the scripts run.
  const auto run = body(text, "unsigned run_menu_scripts(ILuaBase* lua)");
  REQUIRE(!run.empty());
  CHECK(run.find("PushCFunction(MenuDiskSpace); lua->SetField(-2, \"disk_space\")") != std::string::npos);
  const auto sizes = text.find("footprints = nl::client::package_footprints(*journal->current);");
  const auto call = text.find("run_menu_scripts(LUA)");
  REQUIRE(sizes != std::string::npos);
  REQUIRE(call != std::string::npos);
  CHECK(sizes < call);
}
