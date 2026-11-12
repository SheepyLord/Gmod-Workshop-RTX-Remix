#include "catalog.h"
#include "former_rtx.h"
#include "gma_fixture.h"
#include "nl/config.h"
#include "nl/deploy.h"
#include "nl/discovery.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/planner.h"
#include "nl/sha256.h"
#include "nl/core.h"
#include "nl_test.h"

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {
namespace fs = std::filesystem;
using nl::client::kPackage;

constexpr std::string_view kAddon = "garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua";
constexpr std::string_view kBinary = "garrysmod/lua/bin/gmcl_fixture_win64.dll";
constexpr std::string_view kMod = "rtx-remix/mods/fixture/mod.usda";

void write(const fs::path& path, std::string_view bytes) {
  fs::create_directories(path.parent_path());
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  if (!stream) throw std::runtime_error("cannot write former RTX fixture");
}
std::string read(const fs::path& root, std::string_view relative) {
  return nl::fs::read_file(nl::fs::join(root, relative), std::size_t{1} << 20);
}
bool has(const fs::path& root, std::string_view relative) { return nl::fs::stat(nl::fs::join(root, relative)).exists; }
nl::journal::File original(std::string path, std::string package, std::string_view bytes) {
  return {std::move(path), std::move(package), nl::sha256::of(bytes), bytes.size(), 0, false};
}
std::string kept(std::string_view path) { return std::string(nl::journal::kOriginals) + "/" + std::string(path); }
bool mentions(const std::vector<std::string>& notes, std::string_view part) {
  for (const auto& note : notes) {
    if (note.find(part) != std::string::npos) return true;
  }
  return false;
}
}  // namespace

TEST_CASE("former RTX: only the RTX package's originals below its add-on and lua/bin paths (ADR 0188)") {
  using nl::client::former_rtx;
  CHECK(former_rtx(original(std::string(kAddon), std::string(kPackage), "x")));
  CHECK(former_rtx(original(std::string(kBinary), std::string(kPackage), "x")));
  CHECK(former_rtx(original("GarrysMod/Addons/NativeLoader/lua/autorun/a.lua", std::string(kPackage), "x")));
  CHECK(!former_rtx(original(std::string(kMod), std::string(kPackage), "x")));               // Remix mods are put back
  CHECK(!former_rtx(original("garrysmod/data/nativeloader_ui/a.txt", std::string(kPackage), "x")));
  CHECK(!former_rtx(original(std::string(kAddon), "modern-house-rtx", "x")));               // another package's
  CHECK(!former_rtx(original("garrysmod/addons/../../x.lua", std::string(kPackage), "x")));  // not a safe path
  CHECK(!former_rtx(original("garrysmod/lua/binary/x.dll", std::string(kPackage), "x")));
}

TEST_CASE("former RTX: kept copies move to backup/former-rtx with an index; the rest stays") {
  const auto dir = nl::test::scratch_dir("former_rtx_move");
  const auto root = dir / "game";
  nl::journal::Journal journal;
  const std::string other = "garrysmod/addons/house/lua/autorun/house.lua";
  const std::string resized = "garrysmod/addons/remixbinary/lua/autorun/sv_rtx.lua";
  const std::string missing = "garrysmod/addons/remixbinary/lua/autorun/sh_rtx.lua";
  journal.originals = {original(std::string(kAddon), std::string(kPackage), "old cl_rtx"),
                       original(std::string(kBinary), std::string(kPackage), "MZ old module"),
                       original(std::string(kMod), std::string(kPackage), "#usda old"),
                       original(other, "modern-house-rtx", "old house"),
                       original(resized, std::string(kPackage), "recorded size"),
                       original(missing, std::string(kPackage), "gone")};
  for (const auto& [path, bytes] : std::map<std::string, std::string>{{std::string(kAddon), "old cl_rtx"},
                                                                       {std::string(kBinary), "MZ old module"},
                                                                       {std::string(kMod), "#usda old"},
                                                                       {other, "old house"},
                                                                       {resized, "a different file"}}) {
    write(nl::fs::join(root, kept(path)), bytes);
  }
  const auto result = nl::client::archive_former_rtx(root, journal, "20261111T235959Z");
  CHECK(result.moved == 2);
  CHECK(result.folder == "native-loader/backup/former-rtx/20261111T235959Z");
  CHECK(read(root, result.folder + "/" + std::string(kAddon)) == "old cl_rtx");
  CHECK(read(root, result.folder + "/" + std::string(kBinary)) == "MZ old module");
  CHECK(!has(root, kept(kAddon)));
  CHECK(!has(root, kept(kBinary)));
  CHECK(read(root, kept(kMod)) == "#usda old");      // a Remix mod: put back as before
  CHECK(read(root, kept(other)) == "old house");     // another package's original
  CHECK(read(root, kept(resized)) == "a different file");  // not what the journal recorded
  CHECK(mentions(result.notes, kept(resized)));
  CHECK(!mentions(result.notes, missing));           // nothing to move, nothing to say
  const auto index = nl::json::parse(read(root, result.folder + "/index.json"));
  REQUIRE(index.find("files") != nullptr);
  const auto& files = index.find("files")->as_array("files");
  REQUIRE(files.size() == 2);
  CHECK(files[0].find("path")->as_string("path") == kAddon);
  CHECK(files[0].find("sha256")->as_string("sha256") == nl::sha256::of("old cl_rtx"));
  CHECK(index.find("why")->as_string("why").find("ADR 0188") != std::string::npos);
  // Done once: a later RTX start finds nothing left to move and makes no folder.
  const auto again = nl::client::archive_former_rtx(root, journal, "20261112T000000Z");
  CHECK(again.moved == 0);
  CHECK(again.folder.empty());
  CHECK(!has(root, "native-loader/backup/former-rtx/20261112T000000Z"));
  // A taken folder name gets a suffix.
  write(nl::fs::join(root, kept(kAddon)), "old cl_rtx");
  const auto third = nl::client::archive_former_rtx(root, journal, "20261111T235959Z");
  CHECK(third.moved == 1);
  CHECK(third.folder == "native-loader/backup/former-rtx/20261111T235959Z-2");
  fs::remove_all(dir);
}

TEST_CASE("former RTX: nothing moves while another deployer holds native-loader/lock") {
  const auto dir = nl::test::scratch_dir("former_rtx_lock");
  const auto root = dir / "game";
  nl::journal::Journal journal;
  journal.originals = {original(std::string(kAddon), std::string(kPackage), "old cl_rtx")};
  write(nl::fs::join(root, kept(kAddon)), "old cl_rtx");
  write(nl::fs::join(root, "native-loader/lock"), "");
  const HANDLE held = CreateFileW(nl::fs::long_path(nl::fs::join(root, "native-loader/lock")).c_str(),
                                  GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  REQUIRE(held != INVALID_HANDLE_VALUE);
  const auto blocked = nl::client::archive_former_rtx(root, journal, "20261111T000000Z");
  CloseHandle(held);
  CHECK(blocked.moved == 0);
  CHECK(mentions(blocked.notes, "native-loader/lock"));
  CHECK(read(root, kept(kAddon)) == "old cl_rtx");
  CHECK(!has(root, "native-loader/backup/former-rtx"));
  CHECK(nl::client::archive_former_rtx(root, journal, "20261111T000001Z").moved == 1);
  fs::remove_all(dir);
}

TEST_CASE("former RTX: after the archive, uninstalling the package leaves its add-on and lua/bin paths empty") {
  // The field on 2026-11-11: the RTX package had been deployed over an earlier RTX deployment, kept as originals;
  // its removal put that back, and remixbinary's Lua then failed without the runtime.
  const auto dir = nl::test::scratch_dir("former_rtx_uninstall");
  const auto root = dir / "game";
  write(root / "bin/win64/gmod.exe", "");
  fs::create_directories(root / "garrysmod/cfg");
  write(nl::fs::join(root, kAddon), "old cl_rtx");
  write(nl::fs::join(root, kBinary), "MZ old module");
  write(nl::fs::join(root, kMod), "#usda old");
  const std::map<std::string, std::string> files{{"native/root/" + std::string(kAddon), "new cl_rtx"},
                                                 {"native/root/" + std::string(kBinary), "MZ new module"},
                                                 {"native/root/" + std::string(kMod), "#usda new"}};
  std::string listed;
  for (const auto& [name, bytes] : files) {
    listed += (listed.empty() ? "\"" : ", \"") + name + "\": {\"size\": " + std::to_string(bytes.size()) +
              ", \"sha256\": \"" + nl::sha256::of(bytes) + "\"}";
  }
  nl::test::FixtureArchive archive;
  archive.files.push_back({"native/manifest.json",
                           "{\"schema\": 1, \"id\": \"" + std::string(kPackage) + "\", \"version\": \"1.0.0\", "
                           "\"kinds\": [\"lua-addon\", \"lua-binary-module\", \"root-files\"], \"root_files\": ["
                           "{\"path\": \"garrysmod/addons/remixbinary\"}, {\"path\": \"" + std::string(kBinary) + "\"}, "
                           "{\"path\": \"rtx-remix/mods/fixture\"}], \"files\": {" + listed + "}}"});
  for (const auto& [name, bytes] : files) archive.files.push_back({name, bytes});
  write(root / "rtx.gma", nl::test::build_gma(archive));
  write(root / "native-loader/config.json", R"({"schema": 1, "allow": {"local": ["rtx.gma"]}})");
  nl::deploy::Options options;
  options.allow_running_game = true;
  const auto config = nl::config::load(root);
  const auto deployed = nl::deploy::apply(
      root, nl::planner::consider(nl::discovery::discover(config, nl::discovery::environment_for(root, root / "no-steam"))),
      config, *nl::manifest::parse_version(nl::version()), options);
  REQUIRE(deployed.outcome == "deployed");
  CHECK(read(root, kAddon) == "new cl_rtx");
  const auto journal = nl::journal::load(root);
  REQUIRE(journal.has_value());
  REQUIRE(journal->originals.size() == 3);

  const auto archived = nl::client::archive_former_rtx(root, *journal, "20261111T000000Z");
  CHECK(archived.moved == 2);
  const auto removed = nl::deploy::uninstall(root, options);
  REQUIRE(removed.ok());
  CHECK(!has(root, kAddon));    // not put back: no remixbinary without the runtime
  CHECK(!has(root, kBinary));
  CHECK(read(root, kMod) == "#usda old");  // a Remix mod's original is put back as before (ADR 0035)
  CHECK(mentions(removed.notes, "is gone or changed, so the loader no longer puts it back"));
  CHECK(read(root, archived.folder + "/" + std::string(kAddon)) == "old cl_rtx");  // kept, never deleted
  CHECK(read(root, archived.folder + "/" + std::string(kBinary)) == "MZ old module");
  CHECK(!has(root, "native-loader/state.json"));
  fs::remove_all(dir);
}

namespace {
// The fixture RTX package (remixbinary Lua, a lua/bin module, a Remix mod) from a local archive, deployed by the
// real deployer into `root`.
nl::deploy::Report deploy_fixture(const fs::path& root, const std::map<std::string, std::string>& files) {
  std::string listed;
  for (const auto& [name, bytes] : files) {
    listed += (listed.empty() ? "\"" : ", \"") + name + "\": {\"size\": " + std::to_string(bytes.size()) +
              ", \"sha256\": \"" + nl::sha256::of(bytes) + "\"}";
  }
  nl::test::FixtureArchive archive;
  archive.files.push_back({"native/manifest.json",
                           "{\"schema\": 1, \"id\": \"" + std::string(kPackage) + "\", \"version\": \"1.0.0\", "
                           "\"kinds\": [\"lua-addon\", \"lua-binary-module\", \"root-files\"], \"root_files\": ["
                           "{\"path\": \"garrysmod/addons/remixbinary\"}, {\"path\": \"" + std::string(kBinary) + "\"}, "
                           "{\"path\": \"rtx-remix/mods/fixture\"}], \"files\": {" + listed + "}}"});
  for (const auto& [name, bytes] : files) archive.files.push_back({name, bytes});
  write(root / "rtx.gma", nl::test::build_gma(archive));
  write(root / "native-loader/config.json", R"({"schema": 1, "allow": {"local": ["rtx.gma"]}})");
  nl::deploy::Options options;
  options.allow_running_game = true;
  const auto config = nl::config::load(root);
  return nl::deploy::apply(
      root, nl::planner::consider(nl::discovery::discover(config, nl::discovery::environment_for(root, root / "no-steam"))),
      config, *nl::manifest::parse_version(nl::version()), options);
}
nl::journal::File placed(const fs::path& root, std::string path, std::string package, bool adopted) {
  const auto bytes = read(root, path);
  return {path, std::move(package), nl::sha256::of(bytes), bytes.size(), nl::fs::stat(nl::fs::join(root, path)).mtime,
          adopted};
}
const nl::journal::File* record(const nl::journal::Journal& journal, std::string_view path) {
  for (const auto& file : journal.current->files) {
    if (file.path == path) return &file;
  }
  return nullptr;
}
}  // namespace

TEST_CASE("former RTX: adopted files leave the game at the end of a session; the rest stays (ADR 0188)") {
  const auto dir = nl::test::scratch_dir("former_rtx_adopted");
  const auto root = dir / "game";
  const std::string touched = "garrysmod/addons/remixbinary/lua/autorun/sv_rtx.lua";
  const std::string owned = "garrysmod/addons/remixbinary/lua/autorun/sh_rtx.lua";
  const std::string house = "garrysmod/addons/house/lua/autorun/house.lua";
  fs::create_directories(root / "native-loader");  // the loader's folder, where its lock is
  for (const auto& path : {std::string(kAddon), std::string(kBinary), std::string(kMod), touched, owned, house}) {
    write(nl::fs::join(root, path), "bytes of " + path);
  }
  nl::journal::Journal journal;
  journal.current = nl::journal::Generation{};
  journal.current->files = {placed(root, std::string(kAddon), std::string(kPackage), true),
                            placed(root, std::string(kBinary), std::string(kPackage), true),
                            placed(root, std::string(kMod), std::string(kPackage), true),       // a Remix mod: stays
                            placed(root, touched, std::string(kPackage), true),
                            placed(root, owned, std::string(kPackage), false),                 // the loader's own
                            placed(root, house, "modern-house-rtx", true)};                    // another package's
  journal.current->files[3].mtime += 1;  // changed since the loader found it
  auto pending = journal;
  pending.pending = nl::journal::Pending{};
  CHECK(nl::client::release_adopted(root, pending, "20261111T000000Z-adopted").moved == 0);  // never mid-transaction
  const auto result = nl::client::release_adopted(root, journal, "20261111T000000Z-adopted");
  CHECK(result.moved == 2);
  CHECK(result.folder == "native-loader/backup/former-rtx/20261111T000000Z-adopted");
  CHECK(!has(root, kAddon));
  CHECK(!has(root, kBinary));
  CHECK(read(root, result.folder + "/" + std::string(kAddon)) == "bytes of " + std::string(kAddon));
  for (const auto& path : {std::string(kMod), touched, owned, house}) CHECK(has(root, path));
  CHECK(mentions(result.notes, touched));
  const auto index = nl::json::parse(read(root, result.folder + "/index.json"));
  CHECK(index.find("files")->as_array("files")[0].find("was")->as_string("was") == "adopted");
  CHECK(nl::client::release_adopted(root, journal, "20261111T000001Z-adopted").moved == 0);  // once
  fs::remove_all(dir);
}

TEST_CASE("former RTX: an earlier copy, adopted or kept as an original, is gone after the uninstall") {
  // The field on 2026-11-11: most of the earlier RTX files were byte for byte the package's (adopted, never deleted),
  // the rest older (originals, put back).
  const auto dir = nl::test::scratch_dir("former_rtx_field");
  const auto root = dir / "game";
  write(root / "bin/win64/gmod.exe", "");
  fs::create_directories(root / "garrysmod/cfg");
  const std::map<std::string, std::string> files{{"native/root/" + std::string(kAddon), "cl_rtx as shipped"},
                                                 {"native/root/" + std::string(kBinary), "MZ new module"},
                                                 {"native/root/" + std::string(kMod), "#usda new"}};
  write(nl::fs::join(root, kAddon), "cl_rtx as shipped");  // identical: adopted
  write(nl::fs::join(root, kBinary), "MZ old module");      // older: an original
  REQUIRE(deploy_fixture(root, files).outcome == "deployed");
  auto journal = nl::journal::load(root);
  REQUIRE(journal.has_value());
  REQUIRE(record(*journal, kAddon) != nullptr);
  CHECK(record(*journal, kAddon)->adopted);
  REQUIRE(journal->originals.size() == 1);

  // An RTX start, then the end of its session.
  CHECK(nl::client::archive_former_rtx(root, *journal, "20261111T000000Z").moved == 1);
  CHECK(nl::client::release_adopted(root, *journal, "20261111T000001Z-adopted").moved == 1);
  // The next start places the package's own copy where the adopted one was.
  REQUIRE(deploy_fixture(root, files).outcome == "deployed");
  journal = nl::journal::load(root);
  REQUIRE(journal.has_value());
  REQUIRE(record(*journal, kAddon) != nullptr);
  CHECK(!record(*journal, kAddon)->adopted);
  CHECK(read(root, kAddon) == "cl_rtx as shipped");
  CHECK(nl::client::release_adopted(root, *journal, "20261111T000002Z-adopted").moved == 0);

  nl::deploy::Options options;
  options.allow_running_game = true;
  REQUIRE(nl::deploy::uninstall(root, options).ok());
  CHECK(!has(root, kAddon));
  CHECK(!has(root, kBinary));
  CHECK(!has(root, kMod));
  // Folders the loader did not make stay, empty: GMod finds no Lua in them.
  bool any = false;
  if (fs::exists(root / "garrysmod/addons/remixbinary")) {
    for (const auto& item : fs::recursive_directory_iterator(root / "garrysmod/addons/remixbinary")) any = any || item.is_regular_file();
  }
  CHECK(!any);
  CHECK(read(root, "native-loader/backup/former-rtx/20261111T000000Z/" + std::string(kBinary)) == "MZ old module");
  CHECK(read(root, "native-loader/backup/former-rtx/20261111T000001Z-adopted/" + std::string(kAddon)) == "cl_rtx as shipped");
  fs::remove_all(dir);
}

TEST_CASE("former RTX: no other game of a scratch folder runs; the release waits for one that does") {
  const auto dir = nl::test::scratch_dir("former_rtx_running");
  CHECK(!nl::client::another_game_running(dir / "game"));  // no gmod.exe runs from a scratch folder
  fs::remove_all(dir);
}
