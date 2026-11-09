// A: the paths the cache answers for, its verdicts against the real file system on generated trees, the hook bodies
// (answered without the next function; passed through; writes drop a folder), and the watcher.
#include "fs_accel.h"
#include "nl_test.h"

#include <windows.h>

#include <chrono>
#include <fstream>
#include <thread>

namespace {
using nl::fs_accel::LooseCache;
using nl::fs_accel::PathBuffer;
using nl::fs_accel::Verdict;

void touch(const std::filesystem::path& file) {
  std::filesystem::create_directories(file.parent_path());
  std::ofstream(file) << "x";
}

// garrysmod\addons\{alpha, beta, mmdhl_gamma}, a top-level file, no workshop folder.
std::filesystem::path make_tree(const char* name) {
  const auto root = nl::test::scratch_dir(name);
  const auto gm = root / "garrysmod";
  touch(gm / "addons" / "alpha" / "materials" / "models" / "gun.vmt");
  touch(gm / "addons" / "alpha" / "lua" / "autorun" / "alpha.lua");
  touch(gm / "addons" / "alpha" / "readme.txt");
  touch(gm / "addons" / "Beta" / "lua" / "beta" / "Init.lua");
  touch(gm / "addons" / "mmdhl_gamma" / "models" / "x.mdl");
  touch(gm / "addons" / "loose.gma");
  return gm;
}

std::string narrow(const std::wstring& text) {
  std::string out;
  for (const wchar_t c : text) out.push_back(static_cast<char>(c));
  return out;
}

Verdict verdict_of(LooseCache& cache, const std::string& path) {
  PathBuffer buffer;
  if (!nl::fs_accel::normalize(std::string_view(path), buffer)) return Verdict::Pass;
  return cache.lookup(buffer.view());
}

// What Windows says about a path: 0 when it exists, else the error.
DWORD windows_error(const std::string& path) {
  WIN32_FILE_ATTRIBUTE_DATA data{};
  if (GetFileAttributesExA(path.c_str(), GetFileExInfoStandard, &data)) return 0;
  return GetLastError();
}
}  // namespace

TEST_CASE("fs_accel paths: what may be answered") {
  PathBuffer out;
  REQUIRE(nl::fs_accel::normalize(std::string_view("H:/Steam/GarrysMod/garrysmod/addons/X/Materials/a.VMT"), out));
  CHECK(out.view() == "h:\\steam\\garrysmod\\garrysmod\\addons\\x\\materials\\a.vmt");
  CHECK(nl::fs_accel::normalize(std::wstring_view(L"C:\\a\\b.txt"), out));
  CHECK(out.view() == "c:\\a\\b.txt");
  const char* refused[] = {
      "\\\\?\\C:\\a\\b.txt", "\\\\server\\share\\a.txt", "a\\relative.txt", "C:relative.txt", "C:\\a\\..\\b.txt",
      "C:\\a\\.\\b.txt",     "C:\\a\\\\b.txt",          "C:\\a\\b\\",        "C:\\a\\b.txt:stream", "C:\\a\\*.txt",
      "C:\\a\\b?.txt",       "C:\\a\\b.txt.",          "C:\\a\\b.txt ",     "C:\\a\\PROGRA~1\\b.txt", "C:\\a\\con.txt",
      "C:\\a\\COM1",         "C:\\a\\lpt9.log",        "C:\\a\\nul",        "C:\\a\\b<c.txt",
  };
  for (const char* path : refused) {
    if (nl::fs_accel::normalize(std::string_view(path), out)) {
      std::fprintf(stderr, "  accepted: %s\n", path);
      CHECK(false);
    }
  }
  CHECK(!nl::fs_accel::normalize(std::wstring_view(L"C:\\a\\caf\u00e9.txt"), out));  // not ASCII
  CHECK(!nl::fs_accel::normalize(std::string_view("C:\\a\\caf\xc3\xa9.txt"), out));
  CHECK(!nl::fs_accel::normalize(std::string_view(std::string(300, 'a')), out));  // too long
  CHECK(nl::fs_accel::normalize(std::string_view("C:\\a\\comet.txt"), out));         // not a device
  CHECK(nl::fs_accel::normalize(std::string_view("C:\\a\\com10.txt"), out));
  CHECK(nl::fs_accel::normalize(std::string_view("C:\\a\\x~y.txt"), out));
}

TEST_CASE("fs_accel wildcards: GMod's '*' and '?'") {
  using nl::fs_accel::wildcard_match;
  CHECK(wildcard_match("*", "anything"));
  CHECK(wildcard_match("*", ""));
  CHECK(wildcard_match("*.lua", "init.lua"));
  CHECK(!wildcard_match("*.lua", "init.lua.bak"));
  CHECK(wildcard_match("a?c", "abc"));
  CHECK(!wildcard_match("a?c", "ac"));
  CHECK(wildcard_match("*a*b*", "xxaxxbxx"));
  CHECK(!wildcard_match("materials", "materialsx"));
  CHECK(wildcard_match("", ""));
  CHECK(!wildcard_match("", "x"));
}

TEST_CASE("fs_accel cache: verdicts agree with Windows on a generated tree") {
  const auto gm = make_tree("fs_accel_verdicts");
  LooseCache cache;
  nl::fs_accel::Counters counters;
  std::string reason;
  REQUIRE(cache.init(gm.wstring(), &counters, &reason));
  // alpha, beta and the missing workshop folder; never mmdhl_gamma.
  const auto keys = cache.keys();
  CHECK(keys.size() == 3);
  CHECK(std::find(keys.begin(), keys.end(), "addons\\mmdhl_gamma") == keys.end());
  CHECK(std::find(keys.begin(), keys.end(), "workshop") != keys.end());
  const std::string base = narrow(gm.wstring());
  const char* relative[] = {
      "addons\\alpha\\materials\\models\\gun.vmt",  // exists
      "addons\\ALPHA\\Materials\\Models\\GUN.vmt",  // exists, other case
      "addons/alpha/materials/models/gun.vmt",      // exists, other slashes
      "addons\\alpha\\materials\\models\\gone.vmt", // a missing file
      "addons\\alpha\\materials\\other\\gone.vmt",  // a missing folder
      "addons\\alpha\\nothing\\deep\\gone.vmt",     // a missing folder higher up
      "addons\\alpha\\readme.txt\\inside.txt",      // a file used as a folder: passed on
      "addons\\alpha",                              // the folder itself
      "addons\\beta\\lua\\beta\\init.lua",          // exists (named Beta, Init.lua on disk)
      "addons\\beta\\lua\\beta\\other.lua",         // missing
      "addons\\mmdhl_gamma\\models\\gone.mdl",      // not cached: passed on
      "addons\\unknown\\x.txt",                     // no such add-on folder: passed on
      "workshop\\materials\\x.vmt",                 // the workshop folder does not exist
      "workshop",                                   // itself
      "materials\\x.vmt",                           // garrysmod itself: not cached
  };
  for (const char* rel : relative) {
    const std::string path = base + "\\" + rel;
    const Verdict verdict = verdict_of(cache, path);
    const DWORD error = windows_error(path);
    if (verdict == Verdict::MissingFile) {
      if (error != ERROR_FILE_NOT_FOUND) std::fprintf(stderr, "  %s: Windows says %lu\n", rel, error);
      CHECK(error == ERROR_FILE_NOT_FOUND);
    } else if (verdict == Verdict::MissingPath) {
      if (error != ERROR_PATH_NOT_FOUND) std::fprintf(stderr, "  %s: Windows says %lu\n", rel, error);
      CHECK(error == ERROR_PATH_NOT_FOUND);
    }
  }
  CHECK(verdict_of(cache, base + "\\addons\\alpha\\materials\\models\\gone.vmt") == Verdict::MissingFile);
  CHECK(verdict_of(cache, base + "\\addons\\alpha\\materials\\other\\gone.vmt") == Verdict::MissingPath);
  CHECK(verdict_of(cache, base + "\\addons\\alpha\\materials\\models\\gun.vmt") == Verdict::Pass);
  CHECK(verdict_of(cache, base + "\\addons\\mmdhl_gamma\\models\\gone.mdl") == Verdict::Pass);
  CHECK(verdict_of(cache, base + "\\workshop\\materials\\x.vmt") == Verdict::MissingPath);
  CHECK(verdict_of(cache, base + "\\workshop") == Verdict::MissingFile);
  CHECK(verdict_of(cache, base + "\\addons\\alpha\\readme.txt\\inside.txt") == Verdict::Pass);
  CHECK(counters.listed.load() >= 3);
  // A dropped folder answers nothing.
  PathBuffer gone;
  REQUIRE(nl::fs_accel::normalize(std::string_view(base + "\\addons\\alpha\\x.txt"), gone));
  cache.drop_path(gone.view());
  CHECK(verdict_of(cache, base + "\\addons\\alpha\\materials\\models\\gone.vmt") == Verdict::Pass);
  CHECK(counters.dropped.load() == 1);
  CHECK(verdict_of(cache, base + "\\addons\\beta\\lua\\beta\\other.lua") == Verdict::MissingFile);
}

TEST_CASE("fs_accel cache: a folder with a name Windows could fold differently passes") {
  const auto gm = make_tree("fs_accel_unsafe");
  touch(gm / "addons" / "alpha" / "materials" / L"\u017fign.vmt");  // LATIN SMALL LETTER LONG S
  LooseCache cache;
  std::string reason;
  REQUIRE(cache.init(gm.wstring(), nullptr, &reason));
  const std::string base = narrow(gm.wstring());
  CHECK(verdict_of(cache, base + "\\addons\\alpha\\materials\\sign.vmt") == Verdict::Pass);
  CHECK(verdict_of(cache, base + "\\addons\\alpha\\lua\\gone.lua") == Verdict::MissingFile);
}

namespace {
int g_next_calls = 0;
void* __stdcall next_create_a(const char*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*) {
  ++g_next_calls;
  SetLastError(ERROR_ACCESS_DENIED);
  return INVALID_HANDLE_VALUE;
}
void* __stdcall next_create_w(const wchar_t*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*) {
  ++g_next_calls;
  SetLastError(ERROR_ACCESS_DENIED);
  return INVALID_HANDLE_VALUE;
}
int __stdcall next_attributes_a(const char*, int, void*) {
  ++g_next_calls;
  return TRUE;
}
int __stdcall next_attributes_w(const wchar_t*, int, void*) {
  ++g_next_calls;
  return TRUE;
}
}  // namespace

TEST_CASE("fs_accel hooks: misses answered without Windows, the rest passed on, writes drop the folder") {
  namespace t = nl::fs_accel::testing;
  const auto gm = make_tree("fs_accel_hooks");
  LooseCache cache;
  std::string reason;
  REQUIRE(cache.init(gm.wstring(), nullptr, &reason));
  t::bind(&cache, &next_create_a, &next_create_w, &next_attributes_a, &next_attributes_w);
  nl::fs_accel::set_enabled(true);
  const std::string base = narrow(gm.wstring());
  const std::string missing = base + "\\addons\\alpha\\materials\\models\\gone.vmt";
  const std::wstring missing_w(missing.begin(), missing.end());
  g_next_calls = 0;
  CHECK(t::create_a(missing.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr) == INVALID_HANDLE_VALUE);
  CHECK(GetLastError() == ERROR_FILE_NOT_FOUND);
  CHECK(t::create_w(missing_w.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr) == INVALID_HANDLE_VALUE);
  CHECK(GetLastError() == ERROR_FILE_NOT_FOUND);
  WIN32_FILE_ATTRIBUTE_DATA data{};
  CHECK(t::attributes_a(missing.c_str(), GetFileExInfoStandard, &data) == FALSE);
  CHECK(GetLastError() == ERROR_FILE_NOT_FOUND);
  CHECK(t::attributes_w(missing_w.c_str(), GetFileExInfoStandard, &data) == FALSE);
  CHECK(g_next_calls == 0);
  // An existing file, a directory open and a path outside the folders go on.
  const std::string present = base + "\\addons\\alpha\\materials\\models\\gun.vmt";
  t::create_a(present.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  t::create_a(missing.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  t::attributes_a((base + "\\materials\\x.vmt").c_str(), GetFileExInfoStandard, &data);
  CHECK(g_next_calls == 3);
  // A create in the folder drops it: the next miss there goes to Windows.
  t::create_a((base + "\\addons\\alpha\\new.txt").c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
  CHECK(g_next_calls == 4);
  t::create_a(missing.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  CHECK(g_next_calls == 5);
  // Switched off: everything goes on.
  nl::fs_accel::set_enabled(false);
  t::attributes_a((base + "\\addons\\beta\\lua\\gone.lua").c_str(), GetFileExInfoStandard, &data);
  CHECK(g_next_calls == 6);
  nl::fs_accel::set_enabled(true);
  t::bind(nullptr, nullptr, nullptr, nullptr, nullptr);
}

TEST_CASE("fs_accel watcher: a change in a cached folder drops it") {
  const auto gm = make_tree("fs_accel_watcher");
  auto* cache = new LooseCache();  // the watcher thread keeps both for the process
  auto* watcher = new nl::fs_accel::Watcher();
  std::string reason;
  REQUIRE(watcher->arm(gm.wstring(), &reason));
  REQUIRE(cache->init(gm.wstring(), nullptr, &reason));
  REQUIRE(watcher->run(cache, &reason));
  const std::string base = narrow(gm.wstring());
  const std::string path = base + "\\addons\\beta\\lua\\beta\\new.lua";
  CHECK(verdict_of(*cache, path) == Verdict::MissingFile);
  touch(gm / "addons" / "beta" / "lua" / "beta" / "new.lua");
  bool passed = false;
  for (int i = 0; i < 200 && !passed; ++i) {
    passed = verdict_of(*cache, path) == Verdict::Pass;
    if (!passed) std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  CHECK(passed);
  // The other folder is still cached.
  CHECK(verdict_of(*cache, base + "\\addons\\alpha\\materials\\gone.vmt") == Verdict::MissingFile);
}

TEST_CASE("fs_accel marker: a start that ended within 20 s of its hooks leaves them out once") {
  using nl::fs_accel::MarkerCheck;
  using nl::fs_accel::ProcessStamp;
  const auto folder = nl::test::scratch_dir("fs_accel_marker");
  const std::wstring path = (folder / "data" / "nativeloader" / "load_accel_pending.txt").wstring();
  const ProcessStamp self = nl::fs_accel::current_stamp();
  CHECK(self.pid == GetCurrentProcessId());
  CHECK(self.created != 0);
  CHECK(nl::fs_accel::check_marker(path, self) == MarkerCheck::None);  // none yet
  REQUIRE(nl::fs_accel::write_marker(path, self));                     // its folders made
  CHECK(std::filesystem::exists(path));
  CHECK(nl::fs_accel::check_marker(path, self) == MarkerCheck::None);  // this process's own
  // Another process's marker: running, then gone.
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  wchar_t command[] = L"cmd.exe /c exit 0";
  REQUIRE(CreateProcessW(nullptr, command, nullptr, nullptr, FALSE, CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr,
                         nullptr, &startup, &child));
  FILETIME created{}, exited{}, kernel{}, user{};
  REQUIRE(GetProcessTimes(child.hProcess, &created, &exited, &kernel, &user));
  const ProcessStamp other{child.dwProcessId,
                           (static_cast<unsigned long long>(created.dwHighDateTime) << 32) | created.dwLowDateTime};
  REQUIRE(nl::fs_accel::write_marker(path, other));
  CHECK(nl::fs_accel::check_marker(path, self) == MarkerCheck::Running);
  CHECK(!nl::fs_accel::clear_marker(path, self));  // not this process's: kept
  CHECK(std::filesystem::exists(path));
  TerminateProcess(child.hProcess, 0);
  WaitForSingleObject(child.hProcess, 5000);
  CHECK(nl::fs_accel::check_marker(path, self) == MarkerCheck::LeftOut);  // gone (its handle still open here)
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  // This process's id with another creation time: an earlier process that had the id.
  REQUIRE(nl::fs_accel::write_marker(path, ProcessStamp{self.pid, self.created - 1}));
  CHECK(nl::fs_accel::check_marker(path, self) == MarkerCheck::LeftOut);
  // This process's own comes off.
  REQUIRE(nl::fs_accel::write_marker(path, self));
  CHECK(nl::fs_accel::clear_marker(path, self));
  CHECK(!std::filesystem::exists(path));
  // Text that is no marker counts as none.
  std::ofstream(path) << "not a marker";
  CHECK(nl::fs_accel::check_marker(path, self) == MarkerCheck::None);
}
