#include "catalog.h"
#include "former_rtx.h"
#include "gma_fixture.h"
#include "leftovers.h"
#include "nl/config.h"
#include "nl/core.h"
#include "nl/deploy.h"
#include "nl/discovery.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/planner.h"
#include "nl/session.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <windows.h>
#include <tlhelp32.h>

#include <filesystem>
#include <fstream>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>

// ADR 0206: RTX a removed loader left in the game, removed from inside the game by the RTX client module.
namespace {
namespace fs = std::filesystem;
using nl::client::kPackage;

constexpr std::string_view kAddon = "garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua";
constexpr std::string_view kShared = "garrysmod/addons/remixbinary/lua/autorun/sh_rtx.lua";
constexpr std::string_view kOlder = "garrysmod/addons/remixbinary/lua/autorun/sv_rtx.lua";
constexpr std::string_view kModule = "garrysmod/lua/bin/gmsv_fixture_win64.dll";
constexpr std::string_view kMod = "rtx-remix/mods/fixture/mod.usda";

void write(const fs::path& path, std::string_view bytes) {
  fs::create_directories(path.parent_path());
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  if (!stream) throw std::runtime_error("cannot write leftovers fixture");
}
std::string read(const fs::path& root, std::string_view relative) {
  return nl::fs::read_file(nl::fs::join(root, relative), std::size_t{64} << 20);
}
bool has(const fs::path& root, std::string_view relative) { return nl::fs::stat(nl::fs::join(root, relative)).exists; }

// A real binary module's bytes (Windows' own version.dll), so that the test can hold it the way a game holds a loaded
// module: mapped as an image, which Windows does not delete but lets be renamed.
std::string module_bytes() {
  wchar_t system[MAX_PATH];
  const UINT size = GetSystemDirectoryW(system, MAX_PATH);
  if (!size || size >= MAX_PATH) throw std::runtime_error("no system folder");
  return nl::fs::read_file(fs::path(system) / L"version.dll", std::size_t{16} << 20);
}

// The fixture RTX package (two remixbinary Lua files, a lua/bin module, a Remix mod) with session variables, from a
// local archive, deployed by the real deployer.
nl::deploy::Report deploy_fixture(const fs::path& root, const std::map<std::string, std::string>& files) {
  std::string listed;
  for (const auto& [name, bytes] : files) {
    listed += (listed.empty() ? "\"" : ", \"") + name + "\": {\"size\": " + std::to_string(bytes.size()) +
              ", \"sha256\": \"" + nl::sha256::of(bytes) + "\"}";
  }
  nl::test::FixtureArchive archive;
  archive.files.push_back({"native/manifest.json",
                           "{\"schema\": 1, \"id\": \"" + std::string(kPackage) + "\", \"version\": \"1.0.0\", "
                           "\"kinds\": [\"lua-addon\", \"lua-binary-module\", \"root-files\"], \"requires_remix\": true, "
                           "\"session_cvars\": {\"r_3dsky\": \"0\", \"mat_specular\": \"0\"}, \"root_files\": ["
                           "{\"path\": \"garrysmod/addons/remixbinary\"}, {\"path\": \"" + std::string(kModule) + "\"}, "
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

std::map<std::string, std::string> package_files() {
  return {{"native/root/" + std::string(kAddon), "cl_rtx as shipped"},
          {"native/root/" + std::string(kShared), "sh_rtx as shipped"},
          {"native/root/" + std::string(kOlder), "sv_rtx as shipped"},
          {"native/root/" + std::string(kModule), module_bytes()},
          {"native/root/" + std::string(kMod), "#usda new"}};
}

// A game folder that had an earlier RTX installation (one file byte for byte the package's, one older) and a Remix mod
// of the player's at the package's path, then the RTX package deployed over it, and the record of an RTX session.
fs::path game_with_rtx(const fs::path& dir) {
  const auto root = dir / "game";
  write(root / "bin/win64/gmod.exe", "");
  write(nl::fs::join(root, kShared), "sh_rtx as shipped");  // identical: adopted
  write(nl::fs::join(root, kOlder), "sv_rtx older");        // older: kept as an original
  write(nl::fs::join(root, kMod), "#usda the player's");     // the player's: kept, put back at the uninstall
  if (deploy_fixture(root, package_files()).outcome != "deployed") throw std::runtime_error("fixture not deployed");
  // An RTX session recorded the player's values; config.cfg still holds the session's r_3dsky and the player's own
  // mat_specular.
  nl::session::Record record;
  record.values = {{"r_3dsky", "1"}, {"mat_specular", "1"}};
  record.session_values = {{"r_3dsky", "0"}, {"mat_specular", "0"}};
  write(nl::fs::join(root, nl::session::kRecordPath), nl::session::serialize(record));
  write(nl::fs::join(root, nl::session::kConfigCfg), "r_3dsky \"0\"\nmat_specular \"1\"\n");
  return root;
}
bool mentions(const std::vector<std::string>& notes, std::string_view part) {
  for (const auto& note : notes) {
    if (note.find(part) != std::string::npos) return true;
  }
  return false;
}

// A program that runs a while without a window, under the name of a game folder's gmod.exe: Windows' ping.exe.
void make_game(const fs::path& root) {
  wchar_t system[MAX_PATH];
  const UINT size = GetSystemDirectoryW(system, MAX_PATH);
  if (!size || size >= MAX_PATH) throw std::runtime_error("no system folder");
  fs::create_directories(root / "bin/win64");
  fs::copy_file(fs::path(system) / L"PING.EXE", root / "bin/win64/gmod.exe", fs::copy_options::overwrite_existing);
}
bool start(std::wstring command, PROCESS_INFORMATION& process) {
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  process = {};
  return CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup,
                        &process) != FALSE;
}
void stop(PROCESS_INFORMATION& process) {
  if (process.hProcess) {
    TerminateProcess(process.hProcess, 0);
    WaitForSingleObject(process.hProcess, 5000);
    CloseHandle(process.hProcess);
  }
  if (process.hThread) CloseHandle(process.hThread);
  process = {};
}
// Ends every process whose image is `exe` (the orphaned one, which this test holds no handle to).
void stop_all(const fs::path& exe) {
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) {
    if (lstrcmpiW(entry.szExeFile, L"gmod.exe") != 0) continue;
    const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE, FALSE, entry.th32ProcessID);
    if (!process) continue;
    wchar_t path[32768];
    DWORD size = static_cast<DWORD>(std::size(path));
    if (QueryFullProcessImageNameW(process, 0, path, &size) &&
        fs::path(std::wstring(path, size)).lexically_normal() == fs::absolute(exe).lexically_normal()) {
      TerminateProcess(process, 0);
      WaitForSingleObject(process, 5000);
    }
    CloseHandle(process);
  }
  CloseHandle(snapshot);
}
}  // namespace

TEST_CASE("leftovers: this game's own helpers are not another game; an unrelated one of the folder is") {
  // The PoC on 2026-11-13: the game's Chromium helpers are gmod.exe processes of the same folder, started by it, and
  // the first in-game removal refused because of them.
  const auto dir = nl::test::scratch_dir("leftovers_another_game");
  const auto root = dir / "game";
  make_game(root);
  const auto exe = root / "bin/win64/gmod.exe";
  CHECK(!nl::client::another_game(root));
  PROCESS_INFORMATION helper{};
  REQUIRE(start(L"\"" + exe.wstring() + L"\" -n 30 127.0.0.1", helper));
  CHECK(!nl::client::another_game(root));  // started by this process: a helper of this game
  stop(helper);
  // Started through a cmd.exe that ends at once: its parent is gone, so it does not descend from this process.
  PROCESS_INFORMATION shell{};
  REQUIRE(start(L"cmd.exe /d /c start \"\" /b \"" + exe.wstring() + L"\" -n 30 127.0.0.1", shell));
  WaitForSingleObject(shell.hProcess, 10000);
  stop(shell);
  bool seen = false;
  for (unsigned i = 0; i < 50 && !seen; ++i) {
    seen = nl::client::another_game(root);
    if (!seen) Sleep(100);
  }
  CHECK(seen);
  stop_all(exe);
  CHECK(!nl::client::another_game(root));
  fs::remove_all(dir);
}

TEST_CASE("leftovers: the loader counts as installed while its bootstrap is in the game folder") {
  const auto dir = nl::test::scratch_dir("leftovers_installed");
  const auto root = dir / "game";
  write(root / "bin/win64/gmod.exe", "");
  CHECK(!nl::client::loader_installed(root));  // this test's winmm.dll, if any, is Windows' own
  write(root / "bin/win64/winmm.dll", "MZ bootstrap");
  CHECK(nl::client::loader_installed(root));
  CHECK(nl::client::leftovers_refusal(root).find("installed") != std::string::npos);
  fs::remove_all(dir);
}

TEST_CASE("leftovers: nothing to remove without the loader's journal or without the RTX package in it") {
  const auto dir = nl::test::scratch_dir("leftovers_refusal");
  const auto root = dir / "game";
  write(root / "bin/win64/gmod.exe", "");
  CHECK(nl::client::leftovers_refusal(root).find("state.json") != std::string::npos);
  const auto result = nl::client::remove_leftovers(root, "20261113T000000Z", GetCurrentProcessId());
  CHECK(result.outcome == "not needed");
  CHECK(!has(root, "native-loader"));
  nl::journal::Journal other;
  other.current = nl::journal::Generation{};
  nl::journal::Package house;
  house.id = "modern-house-rtx";
  house.version = "1.0.0";
  house.manifest_sha256 = nl::sha256::of("house manifest");
  house.source = "workshop";
  house.location = "workshop/3829275998/house.gma";
  other.current->packages.push_back(house);
  fs::create_directories(root / "native-loader");
  nl::journal::save(nl::fs::win32(), root, other);
  CHECK(nl::client::leftovers_refusal(root) == "the RTX package is not deployed here");
  CHECK(nl::client::remove_leftovers(root, "20261113T000000Z", GetCurrentProcessId()).outcome == "not needed");
  CHECK(has(root, "native-loader/state.json"));  // another package's journal stays as it is
  fs::remove_all(dir);
}

TEST_CASE("leftovers: with the loader gone, the RTX package leaves the game from inside it, held module included") {
  const auto dir = nl::test::scratch_dir("leftovers_remove");
  const auto root = game_with_rtx(dir);
  REQUIRE(nl::client::leftovers_refusal(root).empty());
  const auto journal = nl::journal::load(root);
  REQUIRE(journal.has_value());
  REQUIRE(journal->originals.size() == 2);  // the older sv_rtx.lua and the player's mod

  // The game holds the module: mapped as an image, like a binary module Lua loaded.
  const auto module = nl::fs::join(root, kModule);
  const HMODULE held = LoadLibraryExW(nl::fs::long_path(module).c_str(), nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE);
  REQUIRE(held != nullptr);
  CHECK(!DeleteFileW(nl::fs::long_path(module).c_str()));  // what the uninstall meets

  const auto result = nl::client::remove_leftovers(root, "20261113T000000Z", GetCurrentProcessId());
  FreeLibrary(held);
  CHECK(result.outcome == "removed");
  CHECK(result.error.empty());
  // Nothing of the package is left at its paths, and the loader's journal is gone, as after nlctl uninstall.
  for (const auto path : {kAddon, kShared, kOlder, kModule}) CHECK(!has(root, path));
  CHECK(!has(root, "native-loader/state.json"));
  CHECK(!has(root, "native-loader/lock"));
  // The player's own Remix mod is put back (ADR 0035); the earlier RTX installation is archived, not put back
  // (ADR 0188): its older file as an original, its identical one as adopted.
  CHECK(read(root, kMod) == "#usda the player's");
  CHECK(result.restored == 1);
  CHECK(result.former == 2);
  CHECK(read(root, "native-loader/backup/former-rtx/20261113T000000Z/" + std::string(kOlder)) == "sv_rtx older");
  CHECK(read(root, "native-loader/backup/former-rtx/20261113T000000Z-adopted/" + std::string(kShared)) == "sh_rtx as shipped");
  // The held module could not be deleted: it was moved aside, with an index, and the uninstall finished.
  CHECK(result.aside == 1);
  CHECK(result.aside_folder == "native-loader/backup/in-use/20261113T000000Z");
  CHECK(read(root, result.aside_folder + "/" + std::string(kModule)) == module_bytes());
  const auto index = nl::json::parse(read(root, result.aside_folder + "/index.json"));
  CHECK(index.find("files")->as_array("files")[0].find("was")->as_string("was") == "in use");
  CHECK(index.find("why")->as_string("why").find("ADR 0206") != std::string::npos);
  CHECK(result.deleted >= 3);
  // The console setting the RTX session changed and the player did not is put back by the caller; the record says so.
  REQUIRE(result.restore.size() == 1);
  CHECK(result.restore[0].first == "r_3dsky");
  CHECK(result.restore[0].second == "1");
  const auto record = nl::session::parse_record(read(root, nl::session::kRecordPath));
  CHECK(record.restore_issued);
  // Done: a second call finds nothing to do.
  CHECK(nl::client::remove_leftovers(root, "20261113T000001Z", GetCurrentProcessId()).outcome == "not needed");
  fs::remove_all(dir);
}

TEST_CASE("leftovers: another deployment holding the lock leaves the game as it was") {
  const auto dir = nl::test::scratch_dir("leftovers_lock");
  const auto root = game_with_rtx(dir);
  const HANDLE lock = CreateFileW(nl::fs::long_path(nl::fs::join(root, "native-loader/lock")).c_str(),
                                  GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  REQUIRE(lock != INVALID_HANDLE_VALUE);
  const auto result = nl::client::remove_leftovers(root, "20261113T000000Z", GetCurrentProcessId());
  CloseHandle(lock);
  CHECK(result.outcome == "refused");
  CHECK(result.error.find("another deployment") != std::string::npos);
  CHECK(mentions(result.notes, "native-loader/lock"));
  for (const auto path : {kAddon, kShared, kOlder, kModule}) CHECK(has(root, path));
  CHECK(has(root, "native-loader/state.json"));
  CHECK(!has(root, "native-loader/backup/former-rtx"));
  CHECK(result.restore.empty());
  CHECK(!nl::session::parse_record(read(root, nl::session::kRecordPath)).restore_issued);
  // Once the lock is free, the next local game removes it.
  CHECK(nl::client::remove_leftovers(root, "20261113T000001Z", GetCurrentProcessId()).outcome == "removed");
  fs::remove_all(dir);
}
