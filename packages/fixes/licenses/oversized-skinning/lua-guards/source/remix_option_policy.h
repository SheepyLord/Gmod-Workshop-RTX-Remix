// GPL-2.0, like the rest of the RTX fixes. The native loader's review of 2026-11-16 (finding 2): the
// Remix options Lua may set through RemixConfig.SetConfigVariable. Any server's client Lua reaches that
// function, and the runtime keeps what it sets in its User layer, which the Remix menu's "Save Settings"
// writes to user.conf. R19 (ADR 0112) refused fourteen path options by name and let every other option
// through: among them the capture hotkey (a modifier alone fires on every frame it is held, and each
// capture is written under rtx-remix/captures), the sky probe's size, the replacement switches, the crash
// hotkeys and a texture path the upstream merge of 2026-11-14 added. Lua now sets only what the RTX
// package's own Lua sets: the sky, the weather and the fog, the tone curve, the game's lights, the
// session's texture lists and the RTX Remix tab's settings. Everything else stays with rtx.conf and the
// Remix menu. No SDK and no Windows header: tests/remix_option_policy_test.cpp compiles this file alone.
#pragma once

#include <cctype>
#include <cstddef>
#include <string>
#include <string_view>

#include "lua_path_policy.h"

namespace RemixOptionPolicy {

// The longest option name and value Lua may pass. The runtime's names are under 80 bytes; the longest
// values are the companion's texture lists (at most 4096 hashes of 18 characters each, about 90 KB).
constexpr size_t MaxKey = 256;
constexpr size_t MaxValue = 1024 * 1024;

// An option name as the lists below hold it: lower case, without white space.
inline std::string Normal(std::string_view key) {
    std::string out;
    out.reserve(key.size());
    for (char c : key) {
        const auto byte = static_cast<unsigned char>(c);
        if (std::isspace(byte)) continue;
        out += static_cast<char>(std::tolower(byte));
    }
    return out;
}

inline bool StartsWith(std::string_view text, std::string_view prefix) {
    return text.size() >= prefix.size() && text.compare(0, prefix.size(), prefix) == 0;
}

// Never from Lua, whatever the allowed list holds: the options whose value is a file or folder
// (LuaPathPolicy::RemixPathOption), captures, the replacement switches, key bindings, the crash and
// debugger hotkeys, the profiler, automation, the camera sequence recorder, Nsight, the splash and the
// menu's own settings, the sky probe's size, the GPU overrides, the generated mods' rank and diagnostic
// logging.
inline bool Refused(std::string_view key) {
    const std::string name = Normal(key);
    if (LuaPathPolicy::RemixPathOption(name)) return true;
    static constexpr const char* kPrefixes[] = {
        "rtx.capture",            // rtx.captureHotKey, rtx.captureShowMenuOnHotkey, ..., rtx.capture.*
        "rtx.enablereplacement",  // rtx.enableReplacementAssets, ...Lights, ...Materials, ...Meshes
        "rtx.profiler.", "rtx.automation.", "rtx.camerasequence.", "rtx.nsight.", "rtx.freecam.", "rtx.gui.",
        "rtx.gpuoverride.",
    };
    static constexpr const char* kNames[] = {
        "rtx.skyprobeside", "rtx.welcomemessage", "rtx.splashmessagedisplaytimeseconds", "rtx.hidesplashmessage",
        "rtx.enablecrashhotkey", "rtx.crashhotkey", "rtx.gpucrashhotkey", "rtx.enablebreakintodebuggeronpressingb",
        "rtx.remixmenukeybinds", "rtx.dumpallinstancesonframe", "rtx.gmod.fallbackmods",
        "rtx.gmod.enableinstrumentation",
    };
    for (const char* prefix : kPrefixes)
        if (StartsWith(name, prefix)) return true;
    for (const char* refused : kNames)
        if (name == refused) return true;
    return false;
}

// What the RTX package's Lua sets (the patch's README names each source): whole groups where its Lua
// sets many options from data (the sky, the weather and the fog; the tone curve and the content packs'
// looks; ReSTIR DI from the default map config; RTX Water; the companion's session lists), and single
// options.
inline bool Allowed(std::string_view key) {
    const std::string name = Normal(key);
    static constexpr const char* kPrefixes[] = {
        "rtx.atmosphere.", "rtx.weather.", "rtx.volumetrics.", "rtx.tonemap.", "rtx.autoexposure.", "rtx.bloom.",
        "rtx.postfx.", "rtx.di.", "rtx.translucentmaterial.", "rtx.gmod.",
    };
    static constexpr const char* kNames[] = {
        // the sky and the game's lights: the map lights, the fixes' settings, the companion's sky and menu,
        // Poolrooms RTX, the content packs, the map RTX add-ons (their fallback light)
        "rtx.skybrightness", "rtx.skymode", "rtx.ignoregamepointlights", "rtx.ignoregamespotlights",
        "rtx.ignoregamedirectionallights", "rtx.fallbacklightmode", "rtx.playermodel.enableprimaryshadows",
        "rtx.enabledirecttranslucentshadows",
        // the RTX Remix tab's Remix settings
        "rtx.graphicspreset", "rtx.upscalertype", "rtx.qualitydlss", "rtx.framegenerationtype",
        "rtx.integrateindirectmode", "rtx.pathmaxbounces",
        // the physgun's glow
        "rtx.legacyemissivecolorsstring", "rtx.legacyemissiveintensitiesstring",
        // texture lists: ARC9's scopes, the bullet break simulator, VR's held camera, the default map config
        "rtx.raytracedrendertargettextures", "rtx.recomputetexturehashonwrite", "rtx.opacitymicromapignoretextures",
        "rtx.ignoretextures", "rtx.hideinstancetextures",
        // the default map config's settings for API lights
        "rtx.neecache.enableanalyticallight", "rtx.rislightsamplecount",
        "rtx.denoisedirectandindirectlightingseparately", "rtx.suppresslightkeeping",
        // the options RemixConfig's own shortcuts set (SetRaytracing, SetUpscaler, ...)
        "rtx.enableraytracing", "rtx.upscaler", "rtx.denoiser", "rtx.reflectionupscaler",
        "rtx.renderresolutionscale", "rtx.maxbounces", "rtx.volumetricenabled", "rtx.defaulttoadvancedui",
    };
    for (const char* prefix : kPrefixes)
        if (StartsWith(name, prefix)) return true;
    for (const char* allowed : kNames)
        if (name == allowed) return true;
    return false;
}

// The allowed options whose value is a list of texture or mesh hashes (fast_unordered_set and
// std::vector<XXH64_hash_t> in the runtime). The runtime reads each item with std::stoull, unguarded:
// an item that is not a hash would throw through the Remix API.
inline bool HashList(std::string_view key) {
    const std::string name = Normal(key);
    static constexpr const char* kNames[] = {
        "rtx.ignoretextures", "rtx.hideinstancetextures", "rtx.raytracedrendertargettextures",
        "rtx.opacitymicromapignoretextures", "rtx.postfx.motionblurmaskouttextures",
        "rtx.gmod.particletexturesforsession", "rtx.gmod.decaltexturesforsession",
        "rtx.gmod.legacyeffecttexturesforsession", "rtx.gmod.ignoredoutlinetextures",
        "rtx.gmod.importedmodelsmoothnormaltextures", "rtx.gmod.mmdalphatexturesforsession",
        "rtx.gmod.meshreplacementhashaliases",
    };
    for (const char* list : kNames)
        if (name == list) return true;
    return false;
}

// Comma-separated hashes, each of 1 to 16 hex digits after an optional 0x and, to take a hash out of a
// lower layer's list, an optional leading '-' (the runtime's HashSetLayer). Spaces around an item and
// empty items are fine, as the runtime skips them.
inline bool HashListValue(std::string_view value) {
    auto space = [](char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; };
    size_t start = 0;
    while (start <= value.size()) {
        const size_t comma = value.find(',', start);
        std::string_view item = value.substr(start, comma == std::string_view::npos ? std::string_view::npos : comma - start);
        while (!item.empty() && space(item.front())) item.remove_prefix(1);
        while (!item.empty() && space(item.back())) item.remove_suffix(1);
        if (!item.empty()) {
            if (item.front() == '-') item.remove_prefix(1);
            if (item.size() >= 2 && item[0] == '0' && (item[1] == 'x' || item[1] == 'X')) item.remove_prefix(2);
            if (item.empty() || item.size() > 16) return false;
            for (char c : item)
                if (!std::isxdigit(static_cast<unsigned char>(c))) return false;
        }
        if (comma == std::string_view::npos) break;
        start = comma + 1;
    }
    return true;
}

inline bool Refuse(std::string* reason, const char* why) {
    if (reason) *reason = why;
    return false;
}

// Whether Lua may set `key` to `value`; `reason` says why not.
inline bool LuaMaySet(std::string_view key, std::string_view value, std::string* reason = nullptr) {
    if (key.empty() || key.size() > MaxKey) return Refuse(reason, "the option name is empty or longer than 256 bytes");
    if (Refused(key)) return Refuse(reason, "Lua may not set this option");
    if (!Allowed(key)) return Refuse(reason, "the RTX package's Lua does not set this option");
    if (value.size() > MaxValue) return Refuse(reason, "the value is longer than 1 MiB");
    if (LuaPathPolicy::AbsolutePathValue(value))
        return Refuse(reason, "the value names a drive, a root, a network path or a parent folder");
    if (HashList(key) && !HashListValue(value)) return Refuse(reason, "the value is not a list of hashes");
    return true;
}

}  // namespace RemixOptionPolicy
