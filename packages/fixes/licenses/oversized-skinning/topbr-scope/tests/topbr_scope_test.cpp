// Regression for topbr_scope.h (patch 14, topbr-scope): world conversion takes only the materials within the player's
// range. A map's BSP names meet the names the texture tracker records; restricted, nothing is taken until Lua names it.
// Builds alone: cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX topbr_scope_test.cpp
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "../source/material_pipeline/to_pbr/topbr_scope.h"

namespace {

int g_checks = 0;

void Check(bool condition, const char* what) {
    ++g_checks;
    if (!condition) {
        std::printf("FAIL %s\n", what);
        std::exit(1);
    }
}

using MaterialPipeline::ToPBR::Scope::Filter;
using MaterialPipeline::ToPBR::Scope::Key;
using MaterialPipeline::ToPBR::Scope::Restricts;
namespace Scope = MaterialPipeline::ToPBR::Scope;

}  // namespace

int main() {
    // Keys: case, slashes, the materials/ prefix and .vmt.
    Check(Key("Materials\\Concrete\\ConcreteFloor001a.vmt") == "concrete/concretefloor001a", "case, slashes, prefix, extension");
    Check(Key("concrete/concretefloor001a") == "concrete/concretefloor001a", "a plain name is its own key");
    // A map's own patched materials: the cubemap patch keeps its coordinates on both sides.
    Check(Key("maps/gm_construct/concrete/concretefloor001a_-123_456_789") == "concrete/concretefloor001a_-123_456_789",
          "a cubemap patch loses only its maps/<map>/ prefix");
    // A blended displacement: the BSP names the runtime patch material, the tracker its two stages.
    Check(Key("maps/gm_flatgrass/nature/blend_grass_wvt_patch") == "nature/blend_grass", "the WVT patch material");
    Check(Key("maps/gm_flatgrass/nature/blend_grass_wvt_patch_stage1") == "nature/blend_grass", "its second base texture");
    Check(Key("nature/blend_grass_stage1") == "nature/blend_grass", "a second stage without the patch");
    Check(Key("maps/onlyone") == "maps/onlyone", "maps/ without a map folder is kept");
    Check(Key("MAPS/GM_X/Glass/Window01") == "glass/window01", "an upper-case BSP name");

    // The player's setting: 0 and 1 restrict, 2 does not, anything else restricts.
    Check(Restricts(Scope::MapSurfaces) && Restricts(Scope::MapAndProps), "0 and 1 restrict");
    Check(!Restricts(Scope::Everything), "2 takes everything");
    Check(Restricts(7) && Restricts(-1), "an unknown value restricts");

    Filter filter;
    // Restricted and empty until Lua names the map's materials: nothing is taken.
    Check(filter.Restricted(), "a new filter is restricted");
    Check(!filter.Allows("concrete/concretefloor001a"), "nothing before Lua names the map's materials");

    // The BSP's names (as game.GetWorld():GetMaterials() gives them) admit the tracker's names.
    const std::vector<std::string> world = {
        "CONCRETE/CONCRETEFLOOR001A",
        "maps/gm_construct/metal/metalwall048a_-512_128_64",
        "maps/gm_construct/nature/blend_grass_wvt_patch",
        "",
        std::string(Scope::MaxNameLength + 1, 'x'),
    };
    Check(filter.Allow(world) == 3, "three names added; empty and overlong ones skipped");
    Check(filter.Allow(world) == 0, "a name is held once");
    Check(filter.Size() == 3, "three keys");
    Check(filter.Allows("concrete/concretefloor001a"), "a world material");
    Check(filter.Allows("maps/gm_construct/metal/metalwall048a_-512_128_64"), "a cubemap-patched world material");
    Check(filter.Allows("maps/gm_construct/nature/blend_grass_wvt_patch"), "a blended displacement");
    Check(filter.Allows("maps/gm_construct/nature/blend_grass_wvt_patch_stage1"), "its second stage");
    Check(!filter.Allows("models/props_c17/oildrum001"), "a prop's material is outside the map's surfaces");
    Check(!filter.Allows("models/weapons/v_hand/v_hand_sheet"), "a weapon's material is outside");
    Check(!filter.Allows("metal/metalwall048a"), "the unpatched name of a cubemap-patched material is not the same key");

    // Props join when Lua names their models' materials (the range with props).
    Check(filter.Allow({"models/props_c17/oildrum001"}) == 1, "a prop's material added");
    Check(filter.Allows("models/props_c17/oildrum001"), "then it is taken");

    // Everything: no restriction, the names stay for a later narrower range.
    filter.Restrict(false);
    Check(filter.Allows("models/weapons/v_hand/v_hand_sheet"), "everything takes any material");
    filter.Restrict(true);
    Check(!filter.Allows("models/weapons/v_hand/v_hand_sheet"), "restricted again");
    Check(filter.Allows("concrete/concretefloor001a"), "the names were kept");

    // Clear (a new map) leaves nothing taken.
    filter.Clear();
    Check(filter.Size() == 0 && !filter.Allows("concrete/concretefloor001a"), "cleared");

    // At most MaxNames keys.
    std::vector<std::string> many;
    many.reserve(Scope::MaxNames + 10);
    for (std::size_t i = 0; i < Scope::MaxNames + 10; ++i) many.push_back("m/" + std::to_string(i));
    Check(filter.Allow(many) == Scope::MaxNames, "the bound");
    Check(filter.Size() == Scope::MaxNames, "no more than MaxNames held");
    Check(!filter.Allows("m/" + std::to_string(Scope::MaxNames + 5)), "a name past the bound is not held");

    std::printf("PASS topbr scope: %d checks\n", g_checks);
    return 0;
}
