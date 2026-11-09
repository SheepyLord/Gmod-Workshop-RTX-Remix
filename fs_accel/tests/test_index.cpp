// B: the per-add-on find index against a table laid out as GMod's Addon::FileSystem (built here with the same C++
// standard library, so the node layouts are the real ones): directories and files per add-on, markers, a title shared
// by two add-ons, a mount that owns nothing, wildcards, the top level, a rebuild after a change, a broken table.
#include "fs_accel.h"
#include "nl_test.h"

#include <list>
#include <map>
#include <string>

namespace {
// The value of an entry node: at node + 0x40.
struct FakeEntry {
  std::string name;   // +0x40
  std::string dir;    // +0x60
  std::uint64_t size = 0;    // +0x80
  std::uint64_t offset = 0;  // +0x88
  const void* owner = nullptr;  // +0x90
  std::uint8_t flag = 0;        // +0x98: 1 for a directory marker
};
// The value of an add-on list node: at node + 0x10.
struct FakeAddon {
  std::string gma;    // +0x10
  std::string title;  // +0x30
  const void* filter = nullptr;  // +0x50
};
// Addon::FileSystem: its vtable, the directory map (+0x08), the add-on list (+0x18).
struct FakeTable {
  const void* vtable = nullptr;
  std::map<std::string, std::map<std::string, FakeEntry>> dirs;
  std::list<FakeAddon> addons;
};
static_assert(offsetof(FakeTable, dirs) == 0x08 && offsetof(FakeTable, addons) == 0x18);
static_assert(offsetof(FakeEntry, owner) == 0x50 && offsetof(FakeEntry, flag) == 0x58);
static_assert(offsetof(FakeAddon, title) == 0x20 && offsetof(FakeAddon, filter) == 0x40);

struct Owner {
  int id;
};

void add_file(FakeTable& table, const Owner& owner, const std::string& path) {
  const auto slash = path.rfind('/');
  const std::string dir = path.substr(0, slash);
  FakeEntry entry;
  entry.name = path.substr(slash + 1);
  entry.dir = dir + "/";
  entry.owner = &owner;
  table.dirs[dir][entry.name] = entry;
  // Every directory on the way holds a marker of the add-on.
  for (std::string d = dir;;) {
    FakeEntry marker;
    marker.owner = &owner;
    marker.flag = 1;
    table.dirs[d]["c:/workshop/" + std::to_string(owner.id) + ".gma"] = marker;
    const auto up = d.rfind('/');
    if (up == std::string::npos) break;
    d = d.substr(0, up);
  }
}

std::string joined(const std::vector<std::string>& items) {
  std::string out;
  for (const auto& item : items) out += (out.empty() ? "" : ",") + item;
  return out;
}
}  // namespace

TEST_CASE("fs_accel index: file.Find(pattern, title) from the add-on table") {
  const Owner alpha{1}, beta{2}, gamma{3}, empty{4};
  FakeTable table;
  add_file(table, alpha, "lua/autorun/alpha.lua");
  add_file(table, alpha, "lua/alpha/core.lua");
  add_file(table, alpha, "materials/models/alpha/skin.vmt");
  add_file(table, alpha, "materials/models/alpha/skin.vtf");
  add_file(table, beta, "lua/autorun/beta.lua");
  add_file(table, beta, "sound/beta/hit.wav");
  add_file(table, gamma, "lua/autorun/gamma.lua");
  add_file(table, gamma, "materials/gamma.vmt");
  table.addons.push_back({"c:/workshop/1.gma", "Alpha", &alpha});
  table.addons.push_back({"c:/workshop/2.gma", "Shared Title", &beta});
  table.addons.push_back({"c:/workshop/3.gma", "Shared Title", &gamma});
  table.addons.push_back({"c:/workshop/4.gma", "Alpha", &empty});  // mounted again: owns nothing
  nl::fs_accel::AddonIndex index;
  nl::fs_accel::TableAddress address{&table};
  nl::fs_accel::FindResult result;
  std::string reason;

  REQUIRE(index.find(address, "*", "Alpha", result, &reason));
  CHECK(joined(result.files).empty());
  CHECK(joined(result.dirs) == "lua,materials");
  REQUIRE(index.find(address, "lua/*", "Alpha", result, &reason));
  CHECK(joined(result.dirs) == "alpha,autorun");
  CHECK(result.files.empty());
  REQUIRE(index.find(address, "lua/autorun/*.lua", "Alpha", result, &reason));
  CHECK(joined(result.files) == "alpha.lua");
  CHECK(result.dirs.empty());
  REQUIRE(index.find(address, "materials/models/alpha/*.vtf", "Alpha", result, &reason));
  CHECK(joined(result.files) == "skin.vtf");
  REQUIRE(index.find(address, "MATERIALS\\Models\\*", "Alpha", result, &reason));  // case and slashes as GMod's
  CHECK(joined(result.dirs) == "alpha");
  REQUIRE(index.find(address, "materials", "Alpha", result, &reason));  // no wildcard: the name itself
  CHECK(joined(result.dirs) == "materials");
  REQUIRE(index.find(address, "nothing/*", "Alpha", result, &reason));
  CHECK(result.files.empty() && result.dirs.empty());

  // Two add-ons with one title: both answer, as GMod walks every list node with that title, and a name comes once.
  REQUIRE(index.find(address, "lua/autorun/*", "Shared Title", result, &reason));
  CHECK(joined(result.files) == "beta.lua,gamma.lua");
  REQUIRE(index.find(address, "*", "Shared Title", result, &reason));
  CHECK(joined(result.dirs) == "lua,materials,sound");
  CHECK(index.builds() == 1);

  // A wildcard in the folder part: left to GMod.
  CHECK(!index.find(address, "lua/?utorun/*", "Alpha", result, &reason));
  CHECK(!index.find(address, "*/autorun/*.lua", "Alpha", result, &reason));

  // Not an add-on's title: left to GMod.
  CHECK(!index.find(address, "*", "GAME", result, &reason));
  CHECK(!index.find(address, "*", "alpha", result, &reason));  // titles compare exactly

  // A new mount changes the table: the index is built again.
  const Owner delta{5};
  add_file(table, delta, "lua/autorun/delta.lua");
  table.addons.push_back({"c:/workshop/5.gma", "Delta", &delta});
  REQUIRE(index.find(address, "lua/autorun/*", "Delta", result, &reason));
  CHECK(joined(result.files) == "delta.lua");
  CHECK(index.builds() == 2);
}

TEST_CASE("fs_accel index: a table that does not hold together is refused") {
  const Owner alpha{1};
  FakeTable table;
  add_file(table, alpha, "lua/autorun/alpha.lua");
  table.addons.push_back({"c:/workshop/1.gma", "Alpha", &alpha});
  // The directory map's size says one more than it holds (its size field at +0x10).
  auto* size = reinterpret_cast<std::uint64_t*>(reinterpret_cast<std::uint8_t*>(&table) + 0x10);
  const std::uint64_t real = *size;
  *size = real + 1;
  nl::fs_accel::AddonIndex index;
  nl::fs_accel::TableAddress address{&table};
  nl::fs_accel::FindResult result;
  std::string reason;
  CHECK(!index.find(address, "*", "Alpha", result, &reason));
  CHECK(!reason.empty());
  *size = real;
  CHECK(index.find(address, "*", "Alpha", result, &reason));
}
