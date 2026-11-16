// GPL-2.0, like the rest of the RTX fixes. The native loader's review of 2026-11-16 (finding 7): game
// maps come only from the character's own model. ToPBR.GameMaterialAction's "options" listed the image
// files in the folder of any absolute path ending in .pmx, and its "maps" scanned that folder, whatever
// the player's rtx_topbr_game_maps; any server's client Lua reaches both, and their errors told a missing
// folder from an existing one. An automatic resolution likewise opened any path it was given. The source
// must now be an existing .pmx file that this module's PMX reader takes, one of whose materials draws the
// base texture; a server cannot put such a file on the player's drive. Lua sees one text for every
// refusal; the reason goes to the game's console. Standard C++ and the Windows headers game_pbr.h takes:
// tests/game_source_test.cpp compiles it with that header alone.
#pragma once
#include "game_pbr.h"
#include <cstdint>
#include <filesystem>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

namespace MaterialPipeline { namespace ToPBR { namespace GamePBR {

// The one text Lua sees for a refused source, or for a model folder the scan cannot read.
constexpr const char* SourceRefusal = "the model's source is unavailable (the game console says why)";

struct SourceCheck {
    bool usable = false;   // an existing .pmx file whose materials draw the base texture
    bool present = false;  // a file is there (only the console tells this apart)
    std::string why;       // the reason, for the console
};

// The models checked so far, by path, kept while their size and write time stay the same: a character's
// materials share one model, and each material asks once. At most 16 models; one owner thread.
class SourceModels {
public:
    SourceCheck Check(const std::string& source, const std::string& base) {
        SourceCheck check;
        try {
            const fs::path pmx = fs::u8path(source);
            if (source.empty() || !pmx.is_absolute() || Lower(pmx.extension().u8string()) != ".pmx") {
                check.why = "not a local PMX";
                return check;
            }
            if (base.empty()) {
                check.why = "no base texture";
                return check;
            }
            std::error_code ec;
            if (!fs::is_regular_file(pmx, ec)) {
                check.why = "no PMX file there";
                return check;
            }
            check.present = true;
            const auto size = fs::file_size(pmx, ec);
            const auto written = ec ? fs::file_time_type{} : fs::last_write_time(pmx, ec);
            if (ec) {
                check.why = "the PMX file cannot be read";
                return check;
            }
            auto found = models_.find(pmx);
            if (found == models_.end() || found->second.size != size || found->second.written != written) {
                Model model{size, written, {}};
                const Mesh mesh = ParsePMX(Read(pmx, 256ull * 1024 * 1024));
                for (const auto& part : mesh.parts)
                    if (!part.texture.empty()) model.textures.insert(part.texture);
                if (found == models_.end() && models_.size() >= 16) models_.erase(models_.begin());
                found = models_.insert_or_assign(pmx, std::move(model)).first;
            }
            if (!found->second.textures.count(Lower(base))) {
                check.why = "no material of the PMX draws the base texture";
                return check;
            }
            check.usable = true;
        } catch (const std::exception& e) {
            check.why = e.what();
        }
        return check;
    }

private:
    struct Model {
        std::uintmax_t size = 0;
        fs::file_time_type written{};
        std::set<std::string> textures;
    };
    std::map<fs::path, Model> models_;
};

// The scanned folder of a usable source, for "options" and "maps". A refused source, or a folder the scan
// cannot read, throws SourceRefusal once `why` holds the reason.
inline Discovery& SourceFolder(SourceModels& sources, DiscoveryCache& discovery, const std::string& source,
                               const std::string& base, std::string& why) {
    try {
        const auto check = sources.Check(source, base);
        if (!check.usable) throw std::runtime_error(check.why);
        return discovery.Get(fs::u8path(source).parent_path());
    } catch (const std::exception& e) {
        why = e.what();
        throw std::runtime_error(SourceRefusal);
    }
}

// What "options" lists for a material: the map families and the image files beside the character's model,
// or, for a refusal or anything the folder's scan cannot do, none of them and SourceRefusal.
struct Options {
    std::vector<Family> families;
    std::vector<std::string> files;
    std::string error;
};
inline Options ListOptions(SourceModels& sources, DiscoveryCache& discovery, const std::string& source,
                           const std::string& base, std::string& why) {
    Options options;
    try {
        auto& folder = SourceFolder(sources, discovery, source, base, why);
        options.families = folder.Families();
        options.files = folder.Files();
    } catch (const std::exception& e) {
        if (why.empty()) why = e.what();
        options = Options{};
        options.error = SourceRefusal;
    }
    return options;
}

}}}
