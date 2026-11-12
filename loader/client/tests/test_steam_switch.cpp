#include "steam_switch.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {
namespace fs = std::filesystem;
using nl::client::SteamItem;

// The layout Steam writes (userdata\<account>\ugc\4000_subscriptions.vdf, 2026-11-11), with made-up items.
constexpr std::string_view kList =
    "\"subscribedfiles\"\n{\n\t\"appid\"\t\t\"4000\"\n\t\"time_last_updated\"\t\t\"1794436932\"\n"
    "\t\"0\"\n\t{\n\t\t\"publishedfileid\"\t\t\"3829070317\"\n\t\t\"time_subscribed\"\t\t\"1794448367\"\n"
    "\t\t\"disabled_locally\"\t\t\"0\"\n\t}\n"
    "\t\"1\"\n\t{\n\t\t\"publishedfileid\"\t\t\"3837235419\"\n\t\t\"time_subscribed\"\t\t\"1794381988\"\n"
    "\t\t\"disabled_locally\"\t\t\"1\"\n\t}\n"
    "\t\"2\"\n\t{\n\t\t\"publishedfileid\"\t\t\"222\"\n\t\t\"time_subscribed\"\t\t\"1\"\n\t}\n}\n";

void write(const fs::path& path, std::string_view bytes) {
  fs::create_directories(path.parent_path());
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  if (!stream) throw std::runtime_error("cannot write Steam list fixture");
}
}  // namespace

TEST_CASE("Steam switch: an item of the account's list is enabled, switched off or not listed (ADR 0189)") {
  using nl::client::steam_item;
  CHECK(steam_item(kList, "3829070317") == SteamItem::enabled);
  CHECK(steam_item(kList, "3837235419") == SteamItem::disabled);
  CHECK(steam_item(kList, "222") == SteamItem::enabled);  // no disabled_locally: on
  CHECK(steam_item(kList, "4000") == SteamItem::not_listed);  // "appid" is no item
  CHECK(steam_item(kList, "1") == SteamItem::not_listed);
  CHECK(steam_item(R"("subscribedfiles" { })", "3829070317") == SteamItem::not_listed);
  // Not Steam's list: no verdict.
  CHECK(!steam_item(R"("something" { "0" { "publishedfileid" "3829070317" } })", "3829070317").has_value());
  CHECK(!steam_item("\"subscribedfiles\" { broken", "3829070317").has_value());
  CHECK(!steam_item("", "3829070317").has_value());
}

TEST_CASE("Steam switch: the list is the account's own file below Steam's folder") {
  const auto dir = nl::test::scratch_dir("steam_switch_files");
  const auto steam = dir / "steam";
  write(steam / "userdata" / "12345678" / "ugc" / "4000_subscriptions.vdf", kList);
  CHECK(nl::client::steam_item_in(steam, 12345678, "3837235419") == SteamItem::disabled);
  CHECK(nl::client::steam_item_in(steam, 12345678, "3829070317") == SteamItem::enabled);
  CHECK(!nl::client::steam_item_in(steam, 23456789, "3829070317").has_value());  // another account: no list here
  CHECK(!nl::client::steam_item_in(steam, 0, "3829070317").has_value());         // nobody signed in
  CHECK(!nl::client::steam_item_in({}, 12345678, "3829070317").has_value());
  fs::remove_all(dir);
}
