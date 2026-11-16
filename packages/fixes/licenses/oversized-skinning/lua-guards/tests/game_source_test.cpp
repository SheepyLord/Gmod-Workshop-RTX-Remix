// GPL-2.0. The native loader's review of 2026-11-16 (finding 7): regression for
// source/material_pipeline/to_pbr/game_source.h, what a game-map action may read. Standard C++ with the
// Windows headers game_pbr.h takes; no SDK. Usage: game_source_test <empty scratch folder>
#include "game_pbr_types.h"
#include "../source/material_pipeline/to_pbr/game_source.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <set>
#include <string>
#include <utility>
#include <vector>

using namespace MaterialPipeline::ToPBR;
namespace fs = std::filesystem;

static void Put(const fs::path& path, const std::string& bytes) {
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    f << bytes;
}

// A PMX 2.0 model in UTF-8: one triangle and one material drawing `texture`, the least the reader takes.
static std::string Pmx(const std::string& texture) {
    std::string b;
    auto u8 = [&](uint8_t v) { b.push_back(static_cast<char>(v)); };
    auto i32 = [&](int32_t v) { b.append(reinterpret_cast<const char*>(&v), 4); };
    auto f32 = [&](float v) { b.append(reinterpret_cast<const char*>(&v), 4); };
    auto text = [&](const std::string& s) { i32(static_cast<int32_t>(s.size())); b += s; };
    b += "PMX ";
    f32(2.0f);
    u8(8);
    const uint8_t globals[] = {1, 0, 1, 1, 1, 1, 1, 1};  // UTF-8, no extra UVs, every index one byte
    for (uint8_t g : globals) u8(g);
    for (int i = 0; i < 4; ++i) text("model");
    i32(3);
    for (int v = 0; v < 3; ++v) {
        for (int i = 0; i < 6; ++i) f32(0.0f);  // position and normal
        f32(static_cast<float>(v % 2));
        f32(static_cast<float>(v / 2));
        u8(0);  // BDEF1
        u8(0);  // bone 0
        f32(1.0f);  // edge scale
    }
    i32(3);
    const uint8_t indices[] = {0, 1, 2};
    for (uint8_t index : indices) u8(index);
    i32(1);
    text(texture);
    i32(1);
    text("cloth");
    text("cloth");
    b.append(65, '\0');  // colours, flags, edge
    u8(0);     // texture 0
    u8(0xFF);  // no sphere map
    u8(0);     // sphere mode
    u8(1);     // shared toon
    u8(0);
    text("");  // memo
    i32(3);    // the material's indices
    return b;
}

int wmain(int argc, wchar_t** argv) {
    assert(argc == 2);
    const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const fs::path root = argv[1];
    // A character's model folder: the model, its base texture and a map beside it.
    const auto model = root / "model";
    fs::create_directories(model / "tex");
    fs::create_directories(model / "maps");
    Put(model / "Model.pmx", Pmx("tex\\Body.png"));
    Put(model / "tex" / "Body.png", "png");
    Put(model / "maps" / "detail.png", "png");
    // The review's reproduction: personal images and no model; a file and a folder only named like one.
    const auto victim = root / "victim";
    fs::create_directories(victim / "Pictures" / "holiday");
    Put(victim / "Pictures" / "holiday" / "IMG_0001.png", "png");
    Put(victim / "passport_scan.jpg", "jpg");
    Put(victim / "notes.pmx", "not a model");
    fs::create_directories(victim / "folder.pmx");

    GamePBR::SourceModels sources;
    const auto pmx = (model / "Model.pmx").u8string();
    // The character's own model, its base texture spelt as the importer or the model spells it.
    for (const char* base : {"tex\\Body.png", "tex/body.png", "TEX/BODY.PNG"}) {
        const auto check = sources.Check(pmx, base);
        assert(check.usable && check.present && check.why.empty() && "the character's own model is used");
    }
    // Every other source is refused; only the console tells a file there from none.
    struct Refusal { fs::path path; std::string base; bool present; };
    const std::vector<Refusal> refusals = {
        {model / "Model.pmx", "tex/other.png", true},           // no material draws that texture
        {model / "Model.pmx", "", false},                       // no base texture
        {victim / "anything.pmx", "tex/body.png", false},       // images, no model
        {root / "NoSuchFolder" / "x.pmx", "tex/body.png", false},
        {victim / "notes.pmx", "tex/body.png", true},           // not a model
        {victim / "folder.pmx", "tex/body.png", false},         // a folder
        {victim / "passport_scan.jpg", "tex/body.png", false},  // not a .pmx
        {fs::path("relative") / "x.pmx", "tex/body.png", false},
    };
    for (const auto& refusal : refusals) {
        const auto check = sources.Check(refusal.path.u8string(), refusal.base);
        assert(!check.usable && check.present == refusal.present && !check.why.empty() && "anything else is refused");
    }
    assert(!sources.Check("", "tex/body.png").usable);
    // The cache follows the model: a changed file is read again.
    Put(model / "Model.pmx", Pmx("tex/other.png"));
    assert(sources.Check(pmx, "tex/other.png").usable && !sources.Check(pmx, "tex/body.png").usable);
    Put(model / "Model.pmx", Pmx("tex\\Body.png"));
    assert(sources.Check(pmx, "tex/body.png").usable);

    // "options": the model's folder is listed; for every refusal nothing is, with one text whether or not the
    // folder exists or holds images.
    GamePBR::DiscoveryCache discovery;
    std::string why;
    const auto listed = GamePBR::ListOptions(sources, discovery, pmx, "tex\\Body.png", why);
    assert(listed.error.empty() && why.empty() && "the model's own folder is listed");
    const std::set<std::string> files(listed.files.begin(), listed.files.end());
    assert(files == std::set<std::string>({(fs::path("tex") / "Body.png").u8string(), (fs::path("maps") / "detail.png").u8string()}));
    const std::vector<std::pair<std::string, std::string>> refused = {
        {(victim / "anything.pmx").u8string(), "tex/body.png"},
        {(root / "NoSuchFolder" / "x.pmx").u8string(), "tex/body.png"},
        {(victim / "notes.pmx").u8string(), "tex/body.png"},
        {(victim / "folder.pmx").u8string(), "tex/body.png"},
        {pmx, "tex/other.png"},
    };
    for (const auto& [source, base] : refused) {
        why.clear();
        const auto options = GamePBR::ListOptions(sources, discovery, source, base, why);
        assert(options.files.empty() && options.families.empty() && "nothing is listed for a refused source");
        assert(options.error == std::string(GamePBR::SourceRefusal) && !why.empty() && "one text for every refusal");
    }
    // "maps": the same refusal, as the error the worker hands back.
    for (const auto& [source, base] : refused) {
        why.clear();
        bool threw = false;
        try {
            GamePBR::SourceFolder(sources, discovery, source, base, why);
        } catch (const std::exception& e) {
            threw = std::string(e.what()) == GamePBR::SourceRefusal;
        }
        assert(threw && !why.empty() && "a manual choice reads no folder of a refused source");
    }
    why.clear();
    assert(GamePBR::SourceFolder(sources, discovery, pmx, "tex/body.png", why).Files().size() == 2 && why.empty());
    if (SUCCEEDED(com)) CoUninitialize();
    std::cout << "PASS game source: the character's own model only (an existing .pmx the reader takes, a material "
                 "drawing the base texture), cached by size and time; images without a model, missing and existing "
                 "folders, a file or folder named .pmx and other files refused with one text; nothing listed then\n";
    return 0;
}
