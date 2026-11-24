// GPL-2.0. The native loader's ADR 0263: regression for source/material_pipeline/to_pbr/game_rescan.h, what
// ToPBR.RescanGameSource takes from Lua, what it forgets and which live materials the worker's rescan concerns.
// Compiles alone (no SDK): cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /utf-8 tests/game_rescan_test.cpp
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <unordered_set>
#include "../source/material_pipeline/to_pbr/game_rescan.h"

namespace {

int g_checks = 0;

void Check(bool condition, const char* what) {
    ++g_checks;
    if (!condition) {
        std::cout << "FAIL game rescan: " << what << "\n";
        std::exit(1);
    }
}

// The worker's live jobs and the module's views, as far as the header reads them.
struct Job {
    std::string identity, source;
};
struct View {
    std::string identity, state, error, family;
};

}  // namespace

int main() {
    namespace R = MaterialPipeline::ToPBR::GameRescan;
    const std::string prefix = "mmd/0123456789abcdef/";

    // One character's prefix: "mmd/", 16 hex digits, "/".
    Check(R::Prefix(prefix), "a prefix");
    Check(R::Prefix("mmd/0123456789ABCDEF/"), "upper-case hex digits, as QueueGameMaterial takes them");
    Check(!R::Prefix("mmd/0123456789abcdef"), "no closing slash");
    Check(!R::Prefix("mmd/0123456789abcde/"), "15 digits");
    Check(!R::Prefix("mmd/0123456789abcdef0/"), "17 digits");
    Check(!R::Prefix("mmd/0123456789abcdeg/"), "not a hex digit");
    Check(!R::Prefix("mmd/0123456789abcdef/skin_1"), "a material name is not a prefix");
    Check(!R::Prefix("mmd/t/0123456789abcd/"), "a texture identity's folder");
    Check(!R::Prefix("MMD/0123456789abcdef/"), "the folder's case");
    Check(!R::Prefix("mmd\\0123456789abcdef\\"), "backslashes");
    Check(!R::Prefix(std::string("mmd/0123456789abc\0ef/", 21)), "a NUL");
    Check(!R::Prefix(""), "empty");

    // Its names.
    Check(R::Named("mmd/0123456789abcdef/skin_1", prefix), "a name of the character");
    Check(!R::Named(prefix, prefix), "the prefix alone is no name");
    Check(!R::Named("mmd/0123456789abcdee/skin_1", prefix), "another character");
    Check(!R::Named("mmd/0123456789ABCDEF/skin_1", prefix), "names compare byte for byte");
    Check(!R::Named("mmd/0123456789abcdef", prefix), "shorter than the prefix");

    // The model as Lua names it.
    Check(R::Source("C:\\Models\\Miku\\miku.pmx"), "a PMX");
    Check(R::Source("E:/models/test.PMX"), "the extension in any case");
    Check(!R::Source("C:\\Models\\Miku\\miku.pmd"), "another extension");
    Check(!R::Source("C:\\Models\\Miku\\miku.pmx.png"), "an image");
    Check(!R::Source("C:\\Models\\Miku\\.pmx"), "no file name before .pmx");
    Check(!R::Source(".pmx"), "too short");
    Check(!R::Source(std::string("C:\\a\0b.pmx", 10)), "a NUL");
    Check(!R::Source("C:\\a\nb.pmx"), "a control character");
    Check(!R::Source("C:\\a\x7F" "b.pmx"), "DEL");
    Check(R::Source(std::string(R::MaxSource - 4, 'a') + ".pmx"), "2048 bytes");
    Check(!R::Source(std::string(R::MaxSource - 3, 'a') + ".pmx"), "2049 bytes");

    // One file's names.
    Check(R::SameFile("C:\\Models\\Miku\\miku.pmx", "c:/models/MIKU/Miku.PMX"), "separators and case");
    Check(R::SameFile("C:\\Models\\Old\\..\\Miku\\.\\miku.pmx", "C:\\Models\\Miku\\miku.pmx"), "dot segments");
    Check(R::SameFile("C:\\Models\\\\Miku//miku.pmx", "C:\\Models\\Miku\\miku.pmx"), "repeated separators");
    Check(R::SameFile(u8"C:\\Models\\\u521D\u97F3\\Miku.pmx", u8"c:/models/\u521D\u97F3/miku.pmx"), "a folder outside ASCII");
    Check(!R::SameFile("C:\\Models\\Miku\\miku.pmx", "C:\\Models\\Miku2\\miku.pmx"), "another folder");
    Check(!R::SameFile("C:\\Models\\Miku\\miku.pmx", "D:\\Models\\Miku\\miku.pmx"), "another drive");
    Check(!R::SameFile("", ""), "no source is no file");
    Check(!R::SameFile("C:\\a\\b.pmx", ""), "no model");
    Check(!R::SameFile(std::string("C:\\a\\\xFF.pmx"), std::string("C:\\a\\\xFF.pmx")), "a name that is not UTF-8");
    Check(R::Normal("C:/Models/Miku/miku.pmx") == L"c:\\models\\miku\\miku.pmx", "the normal form");

    // The identities a rescan lets go: the character's own, and those of the same PMX's earlier import.
    const std::map<std::string, Job> live = {
        {"mmd/0123456789abcdef/skin_1", {"mmd/t/1111111111111111", "C:\\Models\\Miku\\miku.pmx"}},
        {"mmd/0123456789abcdef/hair_2", {"mmd/t/2222222222222222", "C:\\Models\\Miku\\miku.pmx"}},
        {"mmd/0123456789abcdef/face_3", {"mmd/t/2222222222222222", ""}},
        {"mmd/fedcba9876543210/skin_1", {"mmd/t/3333333333333333", "c:/models/miku/MIKU.pmx"}},
        {"mmd/aaaaaaaaaaaaaaaa/body_1", {"mmd/t/4444444444444444", "C:\\Models\\Other\\other.pmx"}},
        {"mmd/aaaaaaaaaaaaaaaa/hair_2", {"mmd/t/1111111111111111", "C:\\Models\\Other\\other.pmx"}},
        {"mmd/0123456789abcdef/none_4", {"", "C:\\Models\\Miku\\miku.pmx"}},
    };
    Check(R::Identities(live, prefix, "C:/Models/Miku/miku.pmx") ==
              std::set<std::string>{"mmd/t/1111111111111111", "mmd/t/2222222222222222", "mmd/t/3333333333333333"},
          "the character's textures and its model's earlier import's, each once, none without an identity");
    Check(R::Identities(live, "mmd/aaaaaaaaaaaaaaaa/", "C:\\Models\\Elsewhere\\other.pmx") ==
              std::set<std::string>{"mmd/t/1111111111111111", "mmd/t/4444444444444444"},
          "by the prefix when the model was moved");
    Check(R::Identities(live, "mmd/bbbbbbbbbbbbbbbb/", "C:\\Models\\Other\\other.pmx") ==
              std::set<std::string>{"mmd/t/1111111111111111", "mmd/t/4444444444444444"},
          "by the model for a new asset id");
    Check(R::Identities(live, "mmd/bbbbbbbbbbbbbbbb/", "C:\\Models\\Nobody\\nobody.pmx").empty(), "nothing of it is live");
    Check(R::Identities(std::map<std::string, Job>{}, prefix, "C:\\Models\\Miku\\miku.pmx").empty(), "no live jobs");

    // Forgotten submissions: only the prefix's.
    std::unordered_set<std::string> submitted = {"mmd/0123456789abcdef/skin_1", "mmd/0123456789abcdef/hair_2",
                                                 "mmd/0123456789abcdee/skin_1", "mmd/aaaaaaaaaaaaaaaa/body_1"};
    Check(R::Forget(submitted, prefix) == 2, "the character's two names");
    Check(submitted == std::unordered_set<std::string>{"mmd/0123456789abcdee/skin_1", "mmd/aaaaaaaaaaaaaaaa/body_1"},
          "the other characters' names stay submitted");
    Check(R::Forget(submitted, prefix) == 0, "nothing more to forget");
    std::set<std::string> ordered = {"mmd/0123456789abcdef/a_1", "mmd/0123456789abcdef/b_2"};
    Check(R::Forget(ordered, prefix) == 2 && ordered.empty(), "any set of names");

    // Waiting views: the prefix's only, errors cleared, families kept.
    std::map<std::string, View> views = {
        {"mmd/0123456789abcdee/zzz_9", {"mmd/t/5555555555555555", "none", "", ""}},
        {"mmd/0123456789abcdef/hair_2", {"mmd/t/2222222222222222", "none", "", ""}},
        {"mmd/0123456789abcdef/skin_1", {"mmd/t/1111111111111111", "error", "the model's source is unavailable", "t_actor_x"}},
        {"mmd/0123456789abcdf0/body_1", {"mmd/t/6666666666666666", "automatic", "", "t_actor_y"}},
    };
    Check(R::Wait(views, prefix) == 2, "the character's two views");
    Check(views["mmd/0123456789abcdef/hair_2"].state == "waiting", "a view without maps waits again");
    Check(views["mmd/0123456789abcdef/skin_1"].state == "waiting" && views["mmd/0123456789abcdef/skin_1"].error.empty() &&
              views["mmd/0123456789abcdef/skin_1"].family == "t_actor_x",
          "an error is cleared, the family kept");
    Check(views["mmd/0123456789abcdee/zzz_9"].state == "none" && views["mmd/0123456789abcdf0/body_1"].state == "automatic",
          "the names beside the prefix's keep their views");
    std::map<std::string, View> none;
    Check(R::Wait(none, prefix) == 0, "no views");

    // The console line's name.
    Check(R::FileName("C:\\Models\\Miku\\miku.pmx") == "miku.pmx", "a file name after '\\'");
    Check(R::FileName("E:/models/test.pmx") == "test.pmx", "a file name after '/'");
    Check(R::FileName("miku.pmx") == "miku.pmx", "a file name alone");

    // At most one rescan a second; a refused call does not move the second.
    using Clock = R::Limit::Clock;
    const Clock::time_point start = Clock::time_point{} + std::chrono::hours(1);
    R::Limit limit;
    Check(limit.Take(start), "the first call");
    Check(!limit.Take(start), "the same moment");
    Check(!limit.Take(start + std::chrono::milliseconds(999)), "within the second");
    Check(limit.Take(start + std::chrono::seconds(1)), "a second later");
    Check(!limit.Take(start + std::chrono::milliseconds(1500)), "half a second after that");
    Check(limit.Take(start + std::chrono::seconds(2)), "a second after the last call taken");
    R::Limit fresh;
    Check(fresh.Take(Clock::time_point{}), "a first call at the clock's start");

    std::cout << "PASS game rescan: " << g_checks
              << " checks (prefixes, names, sources, one file's names, the identities a rescan lets go, forgotten "
                 "submissions, waiting views, the console line's name, one rescan a second)\n";
    return 0;
}
