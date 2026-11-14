// GPL-2.0. SDK-free regression for ToPBR's publication guard (issue 6; the loader's ADR 0212).
// cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 fallback_guard_test.cpp
// fallback_guard_test.exe <empty scratch folder>
#include <cassert>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <unordered_map>
#include "../source/material_pipeline/to_pbr/fallback_guard.h"

namespace fs = std::filesystem;
using namespace MaterialPipeline::ToPBR;

namespace {
struct Material { bool importedGame; };

void Put(const fs::path& path, const std::string& bytes) {
    fs::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file.write(bytes.data(), std::streamsize(bytes.size()));
}
}

int main(int argc, char** argv) {
    assert(argc == 2);
    const fs::path root = fs::u8path(argv[1]);
    fs::remove_all(root);
    const fs::path generated = root / L"~gmod_topbr";

    // Hash extraction, both forms.
    std::vector<uint64_t> hashes; bool complete = true;
    FallbackGuard::ExtractHashes("over \"mat_ABC\" def Material \"mat_0123456789abcdef\"", hashes, complete);
    assert(complete && hashes.size() == 2 && hashes[0] == 0xabc && hashes[1] == 0x123456789abcdefull);
    FallbackGuard::Result legacy;
    FallbackGuard::ExtractHashes("mat_0123456789abcdef0", legacy);
    assert(!legacy.complete);

    // Selection: a partial scan no longer suppresses everything. Only the hashes another mod names stay out, and
    // each switch still governs its own kind.
    std::unordered_map<uint64_t, Material> materials{{0x123, {true}}, {0x456, {false}}, {0x789, {false}}};
    FallbackGuard::Result guard;
    guard.complete = false;
    guard.hashes.insert(0x789);
    auto visible = FallbackGuard::Select(materials, true, true, guard);
    assert(visible.size() == 2 && visible.count(0x123) && visible.count(0x456) && !visible.count(0x789));
    assert(FallbackGuard::Select(materials, false, true, guard).size() == 1);
    assert(FallbackGuard::Select(materials, true, false, guard).count(0x456) == 1);
    assert(FallbackGuard::Select(materials, false, false, guard).empty());

    // Scanning: another mod's text is read, the generated folder is not, and a Unicode name sorting after '~' works.
    Put(generated / L"mod.usda", "#usda 1.0\nover \"mat_112233\" {}");
    Put(root / L"\uFFFFlater" / L"mod.usda", "#usda 1.0\nover \"mat_AABBCC\" {}");
    Put(root / L"pack" / L"mod.usda", "#usda 1.0\n(\n subLayers = [@./materials.usda@]\n)\n");
    Put(root / L"pack" / L"materials.usda", "over \"RootNode\" { over \"Looks\" { over \"mat_00000000000000DD\" {} } }");
    FallbackGuard::Cache cache;
    auto scan = FallbackGuard::Scan(root, generated, &cache);
    assert(scan.complete && scan.reason.empty() && scan.unread == 0 && scan.files == 3);
    assert(scan.hashes.count(0xaabbcc) && scan.hashes.count(0xdd) && !scan.hashes.count(0x112233));

    // A Remix Toolkit mesh (binary crate) makes the scan partial and says which file; the text it read still counts.
    std::string crate = "PXR-USDC";
    crate.append(4096, '\0');
    Put(root / L"pack" / L"models" / L"chair.usd", crate);
    scan = FallbackGuard::Scan(root, generated, &cache);
    assert(!scan.complete && scan.unread == 1 && scan.reason.find("binary USD") != std::string::npos);
    assert(scan.reason.find("chair.usd") != std::string::npos);
    assert(scan.hashes.count(0xaabbcc) && scan.hashes.count(0xdd));
    // ...and what is published is everything but the named hashes.
    std::unordered_map<uint64_t, Material> world{{0xdd, {false}}, {0xee, {false}}};
    visible = FallbackGuard::Select(world, true, true, scan);
    assert(visible.size() == 1 && visible.count(0xee));

    // A text USD with a NUL byte is binary too.
    Put(root / L"pack" / L"odd.usda", std::string("#usda 1.0\0mat_FF", 16));
    scan = FallbackGuard::Scan(root, generated, &cache);
    assert(!scan.complete && scan.unread == 2);
    fs::remove(root / L"pack" / L"odd.usda");

    // A file over the per-file bound is not read.
    FallbackGuard::Limits small;
    small.fileBytes = 64;
    Put(root / L"big" / L"mod.usda", "#usda 1.0\n" + std::string(100, ' ') + "over \"mat_0000000000000BB0\" {}");
    scan = FallbackGuard::Scan(root, generated, nullptr, small);
    assert(!scan.complete && !scan.hashes.count(0xbb0) && scan.reason.find("big") != std::string::npos);
    scan = FallbackGuard::Scan(root, generated, &cache);
    assert(scan.hashes.count(0xbb0));

    // The read limit stops a scan, and a later scan reads the rest: the cache keeps what was read.
    FallbackGuard::Cache staged;
    FallbackGuard::Limits budget;
    budget.readBytes = 64;
    for (int i = 0; i < 3; ++i)
        Put(root / (L"staged" + std::to_wstring(i)) / L"mod.usda", "#usda 1.0\nover \"mat_00000000000000C" + std::to_string(i) + "\" {}");
    size_t found = 0;
    for (int pass = 0; pass < 32 && found < 3; ++pass) {
        scan = FallbackGuard::Scan(root, generated, &staged, budget);
        found = scan.hashes.count(0xc0) + scan.hashes.count(0xc1) + scan.hashes.count(0xc2);
    }
    assert(found == 3);

    // An unchanged file is not read again: a same-size edit with the old write time put back keeps the cached hash;
    // a real change (another size) is read.
    const fs::path later = root / L"\uFFFFlater" / L"mod.usda";
    const auto written = fs::last_write_time(later);
    Put(later, "#usda 1.0\nover \"mat_AABBCD\" {}");
    fs::last_write_time(later, written);
    scan = FallbackGuard::Scan(root, generated, &cache);
    assert(scan.hashes.count(0xaabbcc) && !scan.hashes.count(0xaabbcd));
    Put(later, "#usda 1.0\nover \"mat_00AABBCE\" {}");
    scan = FallbackGuard::Scan(root, generated, &cache);
    assert(!scan.hashes.count(0xaabbcc) && scan.hashes.count(0xaabbce));

    // A file that went away leaves the cache with its hashes.
    fs::remove_all(root / L"pack");
    scan = FallbackGuard::Scan(root, generated, &cache);
    assert(!scan.hashes.count(0xdd));
    for (const auto& entry : cache.files) assert(entry.first.find(L"pack") == std::wstring::npos);

    // Too many entries stop the walk; it is partial, not empty.
    FallbackGuard::Limits few;
    few.entries = 2;
    scan = FallbackGuard::Scan(root, generated, nullptr, few);
    assert(!scan.complete && scan.reason.find("entries") != std::string::npos);

    // A missing mods folder is a partial scan with nothing named: everything publishes.
    scan = FallbackGuard::Scan(root / L"missing", generated);
    assert(!scan.complete && scan.hashes.empty());
    assert(FallbackGuard::Select(world, true, true, scan).size() == 2);

    fs::remove_all(root);
    std::cout << "PASS fallback guard: partial scans publish, named hashes stay out, binary/NUL/oversized/limits "
                 "named, cache reuse and refresh, removed files, entry bound\n";
    return 0;
}
