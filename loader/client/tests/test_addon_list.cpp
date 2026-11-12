#include "addon_list.h"
#include "catalog.h"
#include "gma_fixture.h"
#include "nl/config.h"
#include "nl/core.h"
#include "nl/deploy.h"
#include "nl/discovery.h"
#include "nl/fs.h"
#include "nl/journal.h"
#include "nl/manifest.h"
#include "nl/planner.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <functional>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {
namespace fs = std::filesystem;
using nl::client::ListChange;
constexpr std::string_view kItem = "3829070317";
// The field's own file, as GMod wrote it on 2026-01-14 (LF line ends).
constexpr std::string_view kGmodList = "\"addonnomount\"\n{\n\t\"1\"\t\t\"1310909460\"\n\t\"2\"\t\t\"1846733342\"\n}\n";

void write(const fs::path& path, std::string_view bytes) {
  fs::create_directories(path.parent_path());
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  if (!stream) throw std::runtime_error("cannot write add-on list fixture");
}
std::string list_text(const fs::path& root) {
  return nl::fs::read_file(nl::fs::join(root, nl::client::kAddonList), std::size_t{1} << 20);
}
bool throws(const std::function<void()>& call) {
  try {
    call();
  } catch (const std::exception&) {
    return true;
  }
  return false;
}
}  // namespace

TEST_CASE("add-on list: GMod's file keeps every byte; the loader reads the RTX item from it (ADR 0189)") {
  const auto dir = nl::test::scratch_dir("addon_list_gmod");
  const auto root = dir / "game";
  write(nl::fs::join(root, nl::client::kAddonList), kGmodList);
  CHECK(nl::client::add_to_addon_list(root, kItem) == ListChange::added);
  CHECK(list_text(root) == std::string(kGmodList.substr(0, kGmodList.size() - 2)) + "\t\"3\"\t\t\"3829070317\"\n}\n");
  CHECK((nl::discovery::read_addonnomount(root) == std::set<std::string>{"1310909460", "1846733342", std::string(kItem)}));
  CHECK(nl::client::add_to_addon_list(root, kItem) == ListChange::already_listed);
  CHECK(nl::client::remove_from_addon_list(root, kItem) == ListChange::removed);
  CHECK(list_text(root) == kGmodList);  // back to GMod's bytes
  CHECK(nl::client::remove_from_addon_list(root, kItem) == ListChange::not_listed);
  fs::remove_all(dir);
}

TEST_CASE("add-on list: a missing list is made in GMod's layout; one written on one line still reads") {
  const auto dir = nl::test::scratch_dir("addon_list_layouts");
  const auto root = dir / "game";
  fs::create_directories(root / "garrysmod" / "cfg");
  CHECK(nl::client::add_to_addon_list(root, kItem) == ListChange::added);
  CHECK(list_text(root) == "\"addonnomount\"\n{\n\t\"1\"\t\t\"3829070317\"\n}\n");
  CHECK(nl::client::remove_from_addon_list(root, kItem) == ListChange::removed);
  CHECK(list_text(root) == "\"addonnomount\"\n{\n}\n");
  CHECK(nl::discovery::read_addonnomount(root).empty());

  write(nl::fs::join(root, nl::client::kAddonList), R"("addonnomount" { "1" "123" })");  // as a test fixture writes it
  CHECK(nl::client::add_to_addon_list(root, kItem) == ListChange::added);
  CHECK((nl::discovery::read_addonnomount(root) == std::set<std::string>{"123", std::string(kItem)}));
  CHECK(nl::client::remove_from_addon_list(root, kItem) == ListChange::removed);
  CHECK((nl::discovery::read_addonnomount(root) == std::set<std::string>{"123"}));
  fs::remove_all(dir);
}

TEST_CASE("add-on list: anything but GMod's list, and anything but a Workshop id, is refused unchanged") {
  const auto dir = nl::test::scratch_dir("addon_list_refused");
  const auto root = dir / "game";
  for (const std::string_view other : {std::string_view(R"("something" { "1" "2" })"),
                                       std::string_view(R"("addonnomount" { "1" "2" } "more" { })"),
                                       std::string_view(R"("addonnomount" { "1" { "2" "3" } })"),
                                       std::string_view("\"addonnomount\" { broken")}) {
    write(nl::fs::join(root, nl::client::kAddonList), other);
    CHECK(throws([&] { nl::client::add_to_addon_list(root, kItem); }));
    CHECK(list_text(root) == other);
  }
  write(nl::fs::join(root, nl::client::kAddonList), kGmodList);
  for (const std::string_view id : {std::string_view(""), std::string_view("12a"), std::string_view("\"1\""),
                                    std::string_view("123456789012345678901")}) {
    CHECK(throws([&] { nl::client::add_to_addon_list(root, id); }));
    CHECK(throws([&] { nl::client::remove_from_addon_list(root, id); }));
  }
  CHECK(list_text(root) == kGmodList);
  fs::remove_all(dir);
}

TEST_CASE("add-on list: a link on the way is refused") {
  const auto dir = nl::test::scratch_dir("addon_list_link");
  const auto root = dir / "game";
  const auto elsewhere = dir / "elsewhere";
  fs::create_directories(elsewhere);
  fs::create_directories(root / "garrysmod");
  std::error_code ec;
  fs::create_directory_symlink(elsewhere, root / "garrysmod" / "cfg", ec);
  if (!ec) {
    CHECK(throws([&] { nl::client::add_to_addon_list(root, kItem); }));
    CHECK(!fs::exists(elsewhere / "addonnomount.txt"));
    fs::remove(root / "garrysmod" / "cfg");
  }
  fs::remove_all(dir);
}

TEST_CASE("add-on list: the RTX item in the list removes the package at the next start; out of it, it comes back") {
  // What loader 0.16.0 does with the entry, through the deployer and discovery it shares with this build.
  const auto dir = nl::test::scratch_dir("addon_list_deploy");
  const auto steamapps = dir / "lib" / "steamapps";
  const auto root = steamapps / "common" / "game";
  write(root / "bin" / "win64" / "gmod.exe", "");
  fs::create_directories(root / "garrysmod" / "cfg");
  const std::string mod = "native/root/rtx-remix/mods/fixture/mod.usda";
  nl::test::FixtureArchive archive;
  archive.files.push_back({"native/manifest.json",
                           "{\"schema\": 1, \"id\": \"" + std::string(nl::client::kPackage) + "\", \"version\": \"1.0.0\", "
                           "\"kinds\": [\"root-files\"], \"root_files\": [{\"path\": \"rtx-remix/mods/fixture\"}], "
                           "\"files\": {\"" + mod + "\": {\"size\": 9, \"sha256\": \"" + nl::sha256::of("#usda new") + "\"}}}"});
  archive.files.push_back({mod, "#usda new"});
  write(steamapps / "workshop" / "content" / "4000" / std::string(kItem) / "rtx.gma", nl::test::build_gma(archive));
  write(steamapps / "workshop" / "appworkshop_4000.acf",
        "\"AppWorkshop\" { \"appid\" \"4000\" \"WorkshopItemsInstalled\" { \"3829070317\" { \"size\" \"1\" } } "
        "\"WorkshopItemDetails\" { \"3829070317\" { \"subscribedby\" \"12345678\" } } }");
  write(root / "native-loader" / "config.json", R"({"schema": 1, "allow": {"workshop": ["3829070317"], "subscribed_content": false}})");
  const auto start = [&] {
    nl::deploy::Options options;
    options.allow_running_game = true;
    const auto config = nl::config::load(root);
    return nl::deploy::apply(
        root, nl::planner::consider(nl::discovery::discover(config, nl::discovery::environment_for(root, dir / "no-steam"))),
        config, *nl::manifest::parse_version(nl::version()), options);
  };
  const auto packages = [&] {
    const auto journal = nl::journal::load(root);
    return journal && journal->current ? journal->current->packages.size() : std::size_t{0};
  };
  REQUIRE(start().outcome == "deployed");
  CHECK(packages() == 1);
  CHECK(fs::exists(root / "rtx-remix" / "mods" / "fixture" / "mod.usda"));

  REQUIRE(nl::client::add_to_addon_list(root, kItem) == ListChange::added);
  const auto off = start();
  REQUIRE(off.outcome == "deployed");
  CHECK(packages() == 0);
  CHECK(!fs::exists(root / "rtx-remix" / "mods" / "fixture" / "mod.usda"));
  bool said = false;
  for (const auto& skipped : off.skipped) said = said || skipped.reason.find("disabled in GMod's addon list") != std::string::npos;
  CHECK(said);

  REQUIRE(nl::client::remove_from_addon_list(root, kItem) == ListChange::removed);
  REQUIRE(start().outcome == "deployed");
  CHECK(packages() == 1);
  CHECK(fs::exists(root / "rtx-remix" / "mods" / "fixture" / "mod.usda"));
  fs::remove_all(dir);
}
