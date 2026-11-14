// The load overlay's estimate (ADR 0215): a translated "%s" filled safely, how a remaining time is said, the bar
// (from where it stands to its cap at the estimate, creeping past it, never back), and the history file the menu
// script learns from (written through a temporary file, bounded, read back).
#include "load_eta.h"
#include "nl_test.h"

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <string>

namespace {
std::string slurp(const std::filesystem::path& path) {
  std::ifstream in(path, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}
}  // namespace

TEST_CASE("load estimate: a translation's one %s is filled, anything else falls back to the English") {
  using nl::engine_guard::overlay::fill_value;
  const char* english = "about %s s left";
  CHECK(fill_value("about %s s left", english, "25") == "about 25 s left");
  CHECK(fill_value("\xE6\xAE\x8B\xE3\x82\x8A\xE7\xB4\x84 %s \xE7\xA7\x92", english, "25") ==
        "\xE6\xAE\x8B\xE3\x82\x8A\xE7\xB4\x84 25 \xE7\xA7\x92");  // "残り約 25 秒"
  CHECK(fill_value("%s", english, "7") == "7");
  CHECK(fill_value("about %d left", english, "25") == "about 25 s left");    // not "%s"
  CHECK(fill_value("%s and %s", english, "25") == "about 25 s left");        // two values
  CHECK(fill_value("no value", english, "25") == "about 25 s left");
  CHECK(fill_value("100% done %s", english, "25") == "about 25 s left");     // a stray percent sign
  CHECK(fill_value("", english, "25") == "about 25 s left");
  CHECK(fill_value("broken", "also broken", "25") == "25");
}

TEST_CASE("load estimate: how a remaining time is said") {
  using nl::engine_guard::overlay::remaining;
  const auto said = [](std::uint64_t ms, bool minutes, unsigned value) {
    const auto r = remaining(ms);
    return r.minutes == minutes && r.value == value;
  };
  CHECK(said(0, false, 1));
  CHECK(said(400, false, 1));
  CHECK(said(1000, false, 1));
  CHECK(said(1001, false, 2));
  CHECK(said(19000, false, 19));
  CHECK(said(19001, false, 20));  // 20 s and up: five-second steps, rounded up
  CHECK(said(21000, false, 25));
  CHECK(said(25000, false, 25));
  CHECK(said(86000, false, 90));
  CHECK(said(89999, true, 2));    // 90 s and up: whole minutes, rounded up
  CHECK(said(120000, true, 2));
  CHECK(said(125000, true, 3));
  CHECK(said(3600000, true, 60));
}

TEST_CASE("load estimate: the bar moves to its cap at the estimate and creeps past it, never back") {
  using nl::engine_guard::overlay::bar_fraction;
  using nl::engine_guard::overlay::kBarCap;
  using nl::engine_guard::overlay::kBarLimit;
  CHECK(bar_fraction(0, 0, 0, 10000) == 0);
  const double half = bar_fraction(0, 0, 5000, 10000);
  CHECK(half > 0.48 && half < 0.49);
  CHECK(bar_fraction(0, 0, 9999, 10000) < kBarCap);
  CHECK(bar_fraction(0, 0, 10000, 10000) == kBarCap);
  const double late = bar_fraction(0, 0, 30000, 10000);  // 20 s past: half way from the cap to the limit
  CHECK(late > kBarCap && late < kBarLimit);
  CHECK(late > (kBarCap + kBarLimit) / 2 - 0.0001 && late < (kBarCap + kBarLimit) / 2 + 0.0001);
  CHECK(bar_fraction(0, 0, 10000000, 10000) < kBarLimit);
  // A new estimate goes on from where the bar stands.
  const double moved = bar_fraction(0.5, 4000, 6000, 8000);
  CHECK(moved > 0.73 && moved < 0.74);
  CHECK(bar_fraction(0.5, 4000, 4000, 8000) == 0.5);
  CHECK(bar_fraction(0.5, 4000, 3000, 8000) == 0.5);  // never below where it stood
  CHECK(bar_fraction(0.98, 0, 1000, 8000) == 0.98);   // above the cap: it holds until the estimate runs out
  CHECK(bar_fraction(0.6, 9000, 9500, 9000) >= kBarCap);  // an estimate already past: it creeps from the cap
  CHECK(bar_fraction(-1, 0, 0, 1000) == 0);
  CHECK(bar_fraction(2, 0, 0, 1000) <= kBarLimit);
}

TEST_CASE("load estimate: the history file's path") {
  using nl::engine_guard::overlay::history_path;
  CHECK(history_path(L"").empty());
  CHECK(history_path(L"C:\\game\\garrysmod") == L"C:\\game\\garrysmod\\data\\nativeloader\\load_times.txt");
  // In a test process there is no game: empty, or a garrysmod folder found up from the executable.
  const std::wstring found = nl::engine_guard::overlay::garrysmod_folder();
  CHECK(found.empty() || found.size() >= 9);
}

TEST_CASE("load estimate: the history is written whole and read back") {
  using nl::engine_guard::overlay::kHistoryLimit;
  using nl::engine_guard::overlay::read_history;
  using nl::engine_guard::overlay::write_history;
  const auto folder = nl::test::scratch_dir("load_eta_history");
  std::filesystem::create_directories(folder / "data");
  const auto file = folder / "data" / "nativeloader" / "load_times.txt";
  CHECK(!read_history(file.wstring()).has_value());  // nothing yet
  const std::string first = "1\t1763100000\tf\t774\t12345678\t24.10\t7.10\tgm_construct\t\n";
  REQUIRE(write_history(file.wstring(), first));  // makes data\nativeloader
  REQUIRE(read_history(file.wstring()).has_value());
  CHECK(*read_history(file.wstring()) == first);
  const std::string second = first + "1\t1763100100\t-\t774\t12345678\t20.00\t5.00\tgm_construct\t\n";
  REQUIRE(write_history(file.wstring(), second));
  CHECK(slurp(file) == second);
  CHECK(!std::filesystem::exists(file.wstring() + L".tmp"));
  // Refused, the file as it was: too large, a NUL, no path.
  CHECK(!write_history(file.wstring(), std::string(kHistoryLimit + 1, 'x')));
  CHECK(!write_history(file.wstring(), std::string("a\0b", 3)));
  CHECK(!write_history(L"", "x"));
  CHECK(slurp(file) == second);
  REQUIRE(write_history(file.wstring(), ""));
  CHECK(read_history(file.wstring()).value_or("missing").empty());
  // A file too large to be one of ours is not read.
  {
    std::ofstream big(file, std::ios::binary | std::ios::trunc);
    big << std::string(kHistoryLimit + 10, 'y');
  }
  CHECK(!read_history(file.wstring()).has_value());
  CHECK(!read_history(L"").has_value());
  std::error_code ignored;
  std::filesystem::remove_all(folder, ignored);
}
