// GPL-2.0. The native loader's review of 2026-11-16 (finding 2): regression for source/remix_option_policy.h,
// the Remix options RemixConfig.SetConfigVariable takes from Lua. Compiles alone (no SDK):
//   cl /EHsc /std:c++17 /W4 /WX /UNDEBUG tests/remix_option_policy_test.cpp
// "remix_option_policy_test --verdicts <file>" prints "allow <name>" or "refuse <name>" for each option name in
// the file (one a line): the loader's gate hands it every option the RTX package's Lua sets.
#include <cassert>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>
#include "../source/remix_option_policy.h"

namespace {

bool May(const std::string& key, const std::string& value) { return RemixOptionPolicy::LuaMaySet(key, value); }

enum class Expect { Refused, HashList, Text };
struct RuntimeOption {
    const char* name;
    Expect expect;
};

// Every option of the runtime the package ships (the fork's c6b48ed with runtime/patches 0001-0100, built as
// 25c85588b) whose value is text, a key binding or a hash list: std::string, VirtualKeys, fast_unordered_set and
// std::vector<XXH64_hash_t>, the types that name files, bind keys or throw on a bad item. test_lua_guards.py fails
// while a runtime patch declares one of these this table does not name. Text and hash lists Lua sets are allowed;
// every other one is refused.
const RuntimeOption kRuntimeOptions[] = {
    // std::string
    {"rtx.welcomeMessage", Expect::Refused},
    {"rtx.atmosphere.moonAlbedoTexture", Expect::Refused},
    {"rtx.atmosphere.moonNormalTexture", Expect::Refused},
    {"rtx.atmosphere.starMapTexture", Expect::Refused},
    {"rtx.atmosphere.starMapGalaxyTexture", Expect::Refused},
    {"rtx.atmosphere.starMapNebulaTexture", Expect::Refused},
    {"rtx.cameraSequence.filePath", Expect::Refused},
    {"rtx.gmod.fallbackMods", Expect::Refused},
    {"rtx.gui.language", Expect::Refused},
    {"rtx.gmod.eyeWhiteAliases", Expect::Text},
    {"rtx.neuralRadianceCache.cudaDllDepsDirectoryPath", Expect::Refused},
    {"rtx.nsight.graphicsCaptureInstallPath", Expect::Refused},
    {"rtx.nsight.graphicsCaptureOutputDir", Expect::Refused},
    {"rtx.nsight.graphicsCaptureOutputFile", Expect::Refused},
    {"rtx.legacyEmissiveIntensitiesString", Expect::Text},
    {"rtx.legacyEmissiveColorsString", Expect::Text},
    {"rtx.legacyEmissiveAlphaInvertString", Expect::Refused},
    {"rtx.legacyEmissiveForceAlbedoString", Expect::Refused},
    {"rtx.thinWallThicknessOverridesString", Expect::Refused},
    {"rtx.geometryGenerationHashRuleString", Expect::Refused},
    {"rtx.geometryAssetHashRuleString", Expect::Refused},
    {"rtx.baseGameModRegex", Expect::Refused},
    {"rtx.baseGameModPathRegex", Expect::Refused},
    {"rtx.captureTimestampReplacement", Expect::Refused},
    {"rtx.captureInstanceStageName", Expect::Refused},
    {"rtx.waterSim.rings.texture", Expect::Refused},
    {"rtx.readbackTest.category", Expect::Refused},  // the runtime's unit tests (patch 0040)
    {"rtx.threadTest.text", Expect::Refused},        // the runtime's unit tests (patch 0033)
    // VirtualKeys
    {"rtx.freeCam.keyMoveFaster", Expect::Refused},
    {"rtx.freeCam.keyMoveForward", Expect::Refused},
    {"rtx.freeCam.keyMoveLeft", Expect::Refused},
    {"rtx.freeCam.keyMoveBack", Expect::Refused},
    {"rtx.freeCam.keyMoveRight", Expect::Refused},
    {"rtx.freeCam.keyMoveUp", Expect::Refused},
    {"rtx.freeCam.keyMoveDown", Expect::Refused},
    {"rtx.freeCam.keyPitchDown", Expect::Refused},
    {"rtx.freeCam.keyPitchUp", Expect::Refused},
    {"rtx.freeCam.keyYawLeft", Expect::Refused},
    {"rtx.freeCam.keyYawRight", Expect::Refused},
    {"rtx.remixMenuKeyBinds", Expect::Refused},
    {"rtx.crashHotkey", Expect::Refused},
    {"rtx.gpuCrashHotkey", Expect::Refused},
    {"rtx.captureHotKey", Expect::Refused},
    // fast_unordered_set
    {"rtx.gmod.particleTexturesForSession", Expect::HashList},
    {"rtx.gmod.decalTexturesForSession", Expect::HashList},
    {"rtx.gmod.legacyEffectTexturesForSession", Expect::HashList},
    {"rtx.gmod.ignoredOutlineTextures", Expect::HashList},
    {"rtx.gmod.importedModelSmoothNormalTextures", Expect::HashList},
    {"rtx.gmod.mmdAlphaTexturesForSession", Expect::HashList},
    {"rtx.mmdAlphaTextures", Expect::Refused},
    {"rtx.lightmapTextures", Expect::Refused},
    {"rtx.skyBoxTextures", Expect::Refused},
    {"rtx.skyBoxGeometries", Expect::Refused},
    {"rtx.ignoreTextures", Expect::HashList},
    {"rtx.ignoreLights", Expect::Refused},
    {"rtx.uiTextures", Expect::Refused},
    {"rtx.worldSpaceUiTextures", Expect::Refused},
    {"rtx.worldSpaceUiBackgroundTextures", Expect::Refused},
    {"rtx.legacyEmissiveTextures", Expect::Refused},
    {"rtx.thinWalledOverrideTextures", Expect::Refused},
    {"rtx.hideInstanceTextures", Expect::HashList},
    {"rtx.playerModelTextures", Expect::Refused},
    {"rtx.playerModelBodyTextures", Expect::Refused},
    {"rtx.lightConverter", Expect::Refused},
    {"rtx.particleTextures", Expect::Refused},
    {"rtx.hairCardTextures", Expect::Refused},
    {"rtx.beamTextures", Expect::Refused},
    {"rtx.decalTextures", Expect::Refused},
    {"rtx.dynamicDecalTextures", Expect::Refused},
    {"rtx.singleOffsetDecalTextures", Expect::Refused},
    {"rtx.nonOffsetDecalTextures", Expect::Refused},
    {"rtx.terrainTextures", Expect::Refused},
    {"rtx.opacityMicromapIgnoreTextures", Expect::HashList},
    {"rtx.animatedWaterTextures", Expect::Refused},
    {"rtx.sludgeTextures", Expect::Refused},
    {"rtx.allowBakedLightingTextures", Expect::Refused},
    {"rtx.ignoreAlphaOnTextures", Expect::Refused},
    {"rtx.antiCulling.antiCullingTextures", Expect::Refused},
    {"rtx.postfx.motionBlurMaskOutTextures", Expect::HashList},
    {"rtx.raytracedRenderTargetTextures", Expect::HashList},
    {"rtx.particleEmitterTextures", Expect::Refused},
    {"rtx.smoothNormalsTextures", Expect::Refused},
    {"rtx.test.testHashSetCopy", Expect::Refused},   // the runtime's unit tests (patch 0001)
    {"rtx.test.testScopeHashSet", Expect::Refused},  // the runtime's unit tests (patch 0001)
    // std::vector<XXH64_hash_t>
    {"rtx.gmod.meshReplacementHashAliases", Expect::HashList},
    {"rtx.rayPortalModelTextureHashes", Expect::Refused},
};

void RuntimeOptions() {
    for (const auto& option : kRuntimeOptions) {
        switch (option.expect) {
        case Expect::Refused:
            assert(!May(option.name, "1") && !May(option.name, "") && !May(option.name, "0x10") &&
                   "a text, key or hash option the package's Lua does not set is refused");
            break;
        case Expect::HashList:
            assert(RemixOptionPolicy::HashList(option.name) && May(option.name, "0x00000000DEADBEEF, -0x1") &&
                   May(option.name, "") && !May(option.name, "zz") && !May(option.name, "0x1, x") &&
                   "a hash list Lua sets takes hashes only");
            break;
        case Expect::Text:
            assert(!RemixOptionPolicy::HashList(option.name) &&
                   May(option.name, "0x0000000000000001=0x0000000000000002") &&
                   May(option.name, "A1B2C3D4E5F60718:1.000000,0.500000,0.250000") &&
                   !May(option.name, "..\\..\\x.dds") && !May(option.name, "C:x.dds") &&
                   !May(option.name, "\\\\host\\share\\x") && "text Lua sets names no file");
            break;
        }
    }
}

// What any server could set before (the review's reproduction and its list) stays with rtx.conf and the Remix menu.
void TheReviewsList() {
    for (const char* key :
         {"rtx.captureHotKey", "rtx.captureShowMenuOnHotkey", "rtx.captureInstances", "rtx.captureMaxFrames",
          "rtx.captureEnableMultiframe", "rtx.capture.correctBakedTransforms", "rtx.skyProbeSide",
          "rtx.enableReplacementAssets", "rtx.enableReplacementLights", "rtx.enableReplacementMaterials",
          "rtx.enableReplacementMeshes", "rtx.enableCrashHotkey", "rtx.crashHotkey", "rtx.gpuCrashHotkey",
          "rtx.enableBreakIntoDebuggerOnPressingB", "rtx.profiler.memory.requestSnapshot", "rtx.profiler.memory.enable",
          "rtx.automation.disableBlockingDialogBoxes", "rtx.automation.enableTestTrace", "rtx.waterSim.rings.texture",
          "rtx.welcomeMessage", "rtx.splashMessageDisplayTimeSeconds", "rtx.hideSplashMessage", "rtx.gui.language",
          "rtx.gui.logUntranslatedText", "rtx.remixMenuKeyBinds", "rtx.freeCam.keyMoveForward",
          "rtx.cameraSequence.mode", "rtx.nsight.graphicsCaptureEnabled", "rtx.dumpAllInstancesOnFrame",
          "rtx.gmod.fallbackMods", "rtx.gmod.enableInstrumentation", "rtx.gpuOverride.graphicsPreset.10DE_2684",
          "rtx.showUI", "rtx.geometryAssetHashRuleString", "rtx.baseGameModRegex",
          "rtx.atmosphere.moonAlbedoTexture", "rtx.atmosphere.starMapNebulaTexture"})
        assert(!May(key, "False") && !May(key, "0x10") && !May(key, "1") && "kept from Lua");
    for (const char* key : {"rtx.captureHotKey", "rtx.captureShowMenuOnHotkey", "rtx.skyProbeSide",
                            "rtx.enableReplacementAssets", "rtx.waterSim.rings.texture", "rtx.welcomeMessage",
                            "rtx.splashMessageDisplayTimeSeconds"})
        assert(RemixOptionPolicy::Refused(key) && "the review's list is refused by name, not only by omission");
    // Case and white space do not get past the lists.
    for (const char* key : {"RTX.CAPTUREHOTKEY", " rtx.captureHotKey", "rtx.capture HotKey", "rtx.skyProbeSide\t",
                            "rtx.\nenableReplacementAssets", "rtx.gmod.FallbackMods", "RTX.GMOD.ENABLEINSTRUMENTATION",
                            "rtx.atmosphere.MOONALBEDOTEXTURE", " rtx.waterSim.rings.texture ",
                            "rtx.atmosphere.moonAlbedo\nTexture"})
        assert(!May(key, "1") && "a changed spelling is refused too");
    // The reproduction's values.
    assert(!May("rtx.waterSim.rings.texture", "..\\..\\..\\..\\..\\..\\Users\\Public\\x.dds"));
    assert(!May("rtx.waterSim.rings.texture", "C:Users\\Public\\x.dds"));
    assert(!May("rtx.captureHotKey", "0x10") && !May("rtx.captureShowMenuOnHotkey", "False"));
    assert(!May("rtx.enableReplacementAssets", "False") && !May("rtx.skyProbeSide", "4096"));
}

// A sample of what the RTX package's Lua sets, one or more from each source (the gate hands the whole list to
// --verdicts): it stays settable.
void TheShippedOptions() {
    for (const char* key :
         {// the companion: sky, weather, night sky editor, menu, model layers, eye whites, effect categories
          "rtx.skyMode", "rtx.ignoreGameDirectionalLights", "rtx.atmosphere.sunElevation", "rtx.atmosphere.moon0.phase",
          "rtx.atmosphere.timeCycleEnable", "rtx.atmosphere.starMapConstellationBrightness",
          "rtx.atmosphere.daytimeMoonBrightness", "rtx.atmosphere.noHorizon", "rtx.atmosphere.cloudCoverageMean",
          "rtx.weather.precipitation.intensity", "rtx.weather.precipitation.appearance.widthScale",
          "rtx.volumetrics.enable", "rtx.volumetrics.transmittanceMeasurementDistanceMeters",
          "rtx.playerModel.enablePrimaryShadows", "rtx.graphicsPreset", "rtx.upscalerType", "rtx.qualityDLSS",
          "rtx.frameGenerationType", "rtx.integrateIndirectMode", "rtx.pathMaxBounces", "rtx.skyBrightness",
          "rtx.postfx.enable", "rtx.tonemap.psycho17.purityScale", "rtx.gmod.ignoreOutlineMeshes",
          "rtx.gmod.ignoredOutlineTextures", "rtx.gmod.importedModelSmoothNormalTextures",
          "rtx.gmod.mmdAlphaTexturesForSession", "rtx.gmod.automaticEyeWhites", "rtx.gmod.eyeWhiteBrightness",
          "rtx.gmod.eyeWhiteAliases", "rtx.gmod.particleTexturesForSession", "rtx.gmod.decalTexturesForSession",
          "rtx.gmod.legacyEffectTexturesForSession",
          // the fixes: settings, physgun glow, map lights, ARC9, map configs, RTX Water, Poolrooms RTX
          "rtx.ignoreGamePointLights", "rtx.ignoreGameSpotLights", "rtx.legacyEmissiveColorsString",
          "rtx.legacyEmissiveIntensitiesString", "rtx.raytracedRenderTargetTextures", "rtx.neeCache.enableAnalyticalLight",
          "rtx.risLightSampleCount", "rtx.di.initialSampleCount", "rtx.di.enableDenoiserGradient",
          "rtx.denoiseDirectAndIndirectLightingSeparately", "rtx.suppressLightKeeping", "rtx.hideInstanceTextures",
          "rtx.translucentMaterial.animatedWaterEnable", "rtx.translucentMaterial.animatedWaterPrimaryNormalMotion",
          "rtx.volumetrics.enableAtmosphere",
          // the bullet break simulator, VR, the content packs' looks
          "rtx.recomputeTextureHashOnWrite", "rtx.opacityMicromapIgnoreTextures", "rtx.ignoreTextures",
          "rtx.tonemap.tonemapOperator", "rtx.tonemap.hable.whitePoint", "rtx.tonemap.agx.look",
          "rtx.autoExposure.enabled", "rtx.bloom.enable", "rtx.bloom.burnIntensity",
          "rtx.enableDirectTranslucentShadows",
          // the map RTX add-ons (Modern House RTX and the others built from the fork's map branches)
          "rtx.fallbackLightMode", "rtx.volumetrics.froxelMaxDistanceMeters", "rtx.atmosphere.cloudLayer2CoverageMean",
          // RemixConfig's shortcuts and the atmosphere bindings
          "rtx.enableRaytracing", "rtx.renderResolutionScale", "rtx.defaultToAdvancedUI"})
        assert(RemixOptionPolicy::Allowed(key) && !RemixOptionPolicy::Refused(key) && May(key, "1") &&
               "what the package's Lua sets stays settable");
    // The values the package sends.
    assert(May("rtx.atmosphere.moon0.color", "0.11, 0.12, 0.135"));
    assert(May("rtx.volumetrics.transmittanceColor", "0.93, 0.97, 0.997"));
    assert(May("rtx.ignoreTextures", "0xABCDEF0123456789, -0x35d7392325ed05a9"));
    assert(May("rtx.hideInstanceTextures", "41C11B59983BC9E7"));
    assert(May("rtx.legacyEmissiveColorsString", "A1B2C3D4E5F60718:1.000000,0.500000,0.250000;0000000000000001:0.1,0.2,0.3"));
    assert(May("rtx.legacyEmissiveIntensitiesString", "A1B2C3D4E5F60718:2.000000,0000000000000001:1.000000"));
    assert(May("rtx.gmod.eyeWhiteAliases", "0x0000000000000001=0x0000000000000002"));
    assert(May("rtx.translucentMaterial.animatedWaterPrimaryNormalMotion", "0.0100, -0.0200"));
    assert(May("rtx.raytracedRenderTargetTextures", "0x9B6B9A2DE0DCA4E3"));
    assert(May("rtx.gmod.ignoredOutlineTextures", ""));
}

void Values() {
    for (const char* value : {"C:\\x", "C:x", "\\\\host\\share", "//host/share", "/x", "..", "a/../b", "..\\x",
                              ".. /x", "x/..."})
        assert(!May("rtx.skyBrightness", value) && "an allowed option takes no path");
    for (const char* value : {"1", "1.5", "True", "0.5, 0.25, 0.125", "-3", "0x1", ""})
        assert(May("rtx.skyBrightness", value));
    for (const char* value : {"", "0x1", "0x00000000DEADBEEF", "deadbeef", "DEADBEEF, 0xabc", " 0x1 ,, 0x2 ",
                              "-0x35d7392325ed05a9", "0x41C11B59983BC9E7, -0x35D7392325ED05A9", "41C11B59983BC9E7",
                              "0XAB", "\t0x1\r\n"})
        assert(RemixOptionPolicy::HashListValue(value) && May("rtx.ignoreTextures", value));
    for (const char* value : {"zz", "0x", "-", "0x1g", "0x12345678901234567", "1 2", "0x1;0x2", "+0x1", "--0x1",
                              "0x-1", "0x1, -", "C:x"})
        assert(!May("rtx.ignoreTextures", value) && "a hash list takes hashes only");
    // Sizes: the companion's longest lists fit; a name over 256 bytes or a value over 1 MiB does not.
    std::string list;
    for (int i = 0; i < 4096; ++i) {
        char item[24];
        std::snprintf(item, sizeof(item), "0x%016X, ", static_cast<unsigned>(i) * 2654435761u);
        list += item;
    }
    assert(May("rtx.gmod.particleTexturesForSession", list));
    assert(!May("rtx.skyBrightness", std::string(RemixOptionPolicy::MaxValue + 1, '1')));
    assert(May("rtx.skyBrightness", std::string(RemixOptionPolicy::MaxValue, '1')));
    assert(!May("", "1") && !May(std::string(RemixOptionPolicy::MaxKey + 1, 'a'), "1"));
    std::string why;
    assert(!RemixOptionPolicy::LuaMaySet("rtx.captureHotKey", "0x10", &why) && !why.empty());
    why.clear();
    assert(!RemixOptionPolicy::LuaMaySet("rtx.someUnknownOption", "1", &why) && !why.empty());
    why.clear();
    assert(RemixOptionPolicy::LuaMaySet("rtx.skyBrightness", "2", &why) && why.empty());
}

int Verdicts(const char* path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return 2;
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        std::cout << (RemixOptionPolicy::LuaMaySet(line, "1") ? "allow " : "refuse ") << line << '\n';
    }
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc == 3 && std::string(argv[1]) == "--verdicts") return Verdicts(argv[2]);
    RuntimeOptions();
    TheReviewsList();
    TheShippedOptions();
    Values();
    std::cout << "PASS remix option policy: " << sizeof(kRuntimeOptions) / sizeof(kRuntimeOptions[0])
              << " text, key and hash options of the runtime (allowed lists take hashes only, allowed text no paths), "
                 "the review's list kept from Lua whatever its spelling, what the package's Lua sets still settable, "
                 "path values, hash items and sizes\n";
    return 0;
}
