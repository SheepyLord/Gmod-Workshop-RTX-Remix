// Windows Error Reporting's snapshots switched off (R28, ADR 0142): the flags, this test process as the game
// (WerGetFlags reads them back from the process itself), and the module's contract: every realm's load calls it.
#include "crash_report.h"
#include "nl_test.h"

#include <windows.h>

#include <fstream>
#include <sstream>
#include <string>

TEST_CASE("crash report: both snapshot flags are added, other flags kept") {
  using namespace nl::engine_guard::crash_report;
  static_assert(kNoCrashSnapshot == 128);  // werapi.h WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH
  static_assert(kNoHangSnapshot == 256);   // WER_FAULT_REPORTING_DISABLE_SNAPSHOT_HANG
  CHECK(with_snapshots_off(0) == 384);
  CHECK(with_snapshots_off(1 | 32) == (1 | 32 | 384));
  CHECK(with_snapshots_off(384) == 384);
  CHECK(with_snapshots_off(128) == 384);
}

TEST_CASE("crash report: this process gets the flags, and a second call answers the same") {
  using namespace nl::engine_guard::crash_report;
  using GetFlags = HRESULT(WINAPI*)(HANDLE, PDWORD);
  const HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
  const auto get = reinterpret_cast<GetFlags>(GetProcAddress(kernel, "WerGetFlags"));
  REQUIRE(get != nullptr);  // every Windows this project supports has it
  const Result first = disable_snapshots();
  CHECK(first.applied);
  CHECK((first.after & kNoCrashSnapshot) != 0);
  CHECK((first.after & first.before) == first.before);  // nothing the process had was dropped
  DWORD flags = 0;
  REQUIRE(SUCCEEDED(get(GetCurrentProcess(), &flags)));
  CHECK((flags & kNoCrashSnapshot) != 0);
  if (first.reason == "ok") CHECK((flags & kNoHangSnapshot) != 0);
  const Result second = disable_snapshots();
  CHECK(second.applied == first.applied);
  CHECK(second.after == first.after);
  CHECK(second.reason == first.reason);
}

TEST_CASE("crash report: the module switches the snapshots off in every realm and says so") {
  std::ifstream file(NL_ENGINE_GUARD_MODULE_SOURCE);
  REQUIRE(file.good());
  std::stringstream read;
  read << file.rdbuf();
  const std::string text = read.str();
  const auto open = text.find("GMOD_MODULE_OPEN()");
  REQUIRE(open != std::string::npos);
  const auto call = text.find("crash_report::disable_snapshots()", open);
  const auto menu = text.find("if (menu) {", open);
  REQUIRE(call != std::string::npos);
  REQUIRE(menu != std::string::npos);
  CHECK(call < menu);  // before the realms part: the menu, the client and the server all run it
  CHECK(text.find("SetField(-2, \"crash_snapshots_off\")", open) != std::string::npos);
  CHECK(text.find("SetField(-2, \"crash_snapshots\")", open) != std::string::npos);
}
