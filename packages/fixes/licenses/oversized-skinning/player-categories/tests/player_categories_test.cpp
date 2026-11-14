// GPL-2.0. SDK-free regression for automatic categorisation and the player's rtx.conf (the loader's ADR 0213).
// cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 player_categories_test.cpp
// player_categories_test.exe <empty scratch folder>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include "../source/material_pipeline/auto_categorisation/player_categories.h"

namespace fs = std::filesystem;
using namespace MaterialPipeline::AutoCategorisation;

namespace {
constexpr uint32_t SKY = 0x4, IGNORED = 0x8, PARTICLE = 0x400, DECAL = 0x1000, WATER = 0x40000, EMISSIVE = 0x1000000;
constexpr uint32_t OTHER = 0x800;  // a bit that names no list here

void Put(const fs::path& path, const std::string& text) {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file << text;
}
}

int main(int argc, char** argv) {
    assert(argc == 2);
    const fs::path root = fs::u8path(argv[1]);
    fs::remove_all(root);
    fs::create_directories(root);

    // Parsing: only "-0x..." entries of rtx.*Textures lists count; keys match without case, quotes and spaces are
    // trimmed, comments and other options are ignored, and invalid tokens are skipped.
    const std::string conf =
        "# rtx.decalTextures = -0x1\n"
        "rtx.decalTextures = 0x00000000000000AA, -0x00000000000000BB, -0xcc , 0xDD\r\n"
        "RTX.ParticleTextures=\"-0x0000000000000EE1\"\n"
        "  rtx.legacyEmissiveTextures =   -0x0000000000000FF1,-zz, -, -0x, 0x12\n"
        "rtx.someOption = -0x77\n"
        "rtx.textures = -0x78\n"
        "garbage line without equals -0x79\n";
    const auto parsed = PlayerCategories::Parse(conf);
    assert(parsed.count == 4 && !parsed.truncated);
    assert(PlayerCategories::Excluded(parsed, "rtx.decalTextures", 0xbb));
    assert(PlayerCategories::Excluded(parsed, "rtx.decalTextures", 0xcc));
    assert(!PlayerCategories::Excluded(parsed, "rtx.decalTextures", 0xaa));   // a positive entry excludes nothing
    assert(!PlayerCategories::Excluded(parsed, "rtx.decalTextures", 0x1));    // commented out
    assert(PlayerCategories::Excluded(parsed, "rtx.particleTextures", 0xee1));
    assert(PlayerCategories::Excluded(parsed, "RTX.PARTICLETEXTURES", 0xee1));
    assert(PlayerCategories::Excluded(parsed, "rtx.legacyEmissiveTextures", 0xff1));
    assert(!PlayerCategories::Excluded(parsed, "rtx.someOption", 0x77));
    assert(!PlayerCategories::Excluded(parsed, "rtx.particleTextures", 0xbb)); // only its own list
    assert(!PlayerCategories::Excluded(parsed, nullptr, 0xbb) && !PlayerCategories::Excluded(parsed, "rtx.decalTextures", 0));

    // Allowed: only the excluded list's bit goes; other bits and bits that name no list stay.
    assert(PlayerCategories::Allowed(parsed, 0xbb, DECAL | PARTICLE | OTHER) == (PARTICLE | OTHER));
    assert(PlayerCategories::Allowed(parsed, 0xee1, PARTICLE | DECAL) == DECAL);
    assert(PlayerCategories::Allowed(parsed, 0xff1, EMISSIVE | WATER) == WATER);
    assert(PlayerCategories::Allowed(parsed, 0xaa, DECAL | SKY | IGNORED) == (DECAL | SKY | IGNORED));
    assert(PlayerCategories::Allowed(parsed, 0x1234, ~0u) == ~0u);

    // The bound: at most maxHashes exclusions are kept.
    std::string many = "rtx.decalTextures = ";
    for (int i = 1; i <= 10; ++i) many += "-0x" + std::to_string(i) + ",";
    const auto bounded = PlayerCategories::Parse(many, 4);
    assert(bounded.count == 4 && bounded.truncated);

    // The live file: read on the first refresh, again when it changes, cleared when it goes.
    auto& file = PlayerCategories::File::Instance();
    const fs::path path = root / L"rtx.conf";
    file.SetPath(path);
    assert(!file.Refresh(true) && file.Count() == 0 && file.MayAdd("rtx.decalTextures", 0xbb));
    Put(path, "rtx.decalTextures = -0xBB\n");
    assert(file.Refresh(true) && file.Count() == 1);
    assert(!file.MayAdd("rtx.decalTextures", 0xbb) && file.MayAdd("rtx.particleTextures", 0xbb));
    assert(file.Allowed(0xbb, DECAL | WATER) == WATER);
    assert(!file.Refresh(true));                                       // unchanged
    assert(!file.Refresh());                                           // looked at less than two seconds ago
    Put(path, "rtx.decalTextures = -0xBB, -0xBC\nrtx.ignoreTextures = -0x5\n");
    assert(file.Refresh(true) && file.Count() == 3 && file.Allowed(0x5, IGNORED | SKY) == SKY);
    fs::remove(path);
    assert(file.Refresh(true) && file.Count() == 0 && file.MayAdd("rtx.decalTextures", 0xbb));

    fs::remove_all(root);
    std::cout << "PASS player categories: rtx.conf exclusions parsed (case, quotes, comments, invalid tokens, bound), "
                 "only excluded lists' bits dropped, file read again on change and cleared when gone\n";
    return 0;
}
