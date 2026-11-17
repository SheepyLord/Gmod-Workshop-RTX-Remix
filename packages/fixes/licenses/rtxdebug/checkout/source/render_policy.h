#pragma once

#include <cstddef>
#include <string_view>

namespace RTXDebug::Policy {

// This boundary grants only the existing client Remix option API. Engine/gameplay,
// arbitrary Lua, memory and detour operations retain the separate mutation gate.
inline bool IsRenderingOption(std::string_view key) {
    if (key.size() <= 4 || key.size() > 256 || key.substr(0, 4) != "rtx.") return false;
    for (char c : key) {
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9') || c == '_' || c == '.')) return false;
    }
    return true;
}

inline bool CanConfigureRendering(bool mainThread, bool closing, bool clientRealm, bool remixApi) {
    return mainThread && !closing && clientRealm && remixApi;
}

inline bool CanSetConfig(bool fullMutation, bool rendering, std::string_view key) {
    return fullMutation || (rendering && IsRenderingOption(key));
}

// Where a Remix option write goes. RTXFixesBinary's RemixConfig.SetConfigVariable takes only
// the options the RTX package's own Lua sets (the native loader's ADR 0234): any server's client
// scripts and any add-on reach it. Behind the developer mutation gate (session_policy.h: local
// single-player decided natively, sv_cheats 1, -insecure) the module writes through the Remix
// API itself, so the options RemixConfig refuses to every Lua (debug views, the replacement
// switches) stay a developer's tools (the native loader's ADR 0237). Without that gate the
// client rendering gate forwards to RemixConfig, whose list decides: a remote server or an
// add-on in an ordinary game reaches no more through this module than through RemixConfig.
// The runtime's options are all rtx.*, and RemixConfig refuses every other name, so the module
// does too.
enum class ConfigRoute { Refused, RemixConfig, RemixApi };

inline ConfigRoute RouteConfig(bool fullMutation, bool rendering, std::string_view key) {
    if (!CanSetConfig(fullMutation, rendering, key) || !IsRenderingOption(key)) return ConfigRoute::Refused;
    return fullMutation ? ConfigRoute::RemixApi : ConfigRoute::RemixConfig;
}

// A restore goes back the way the value went in. Once the module has written an option through
// the Remix API, only the API can put it back (RemixConfig may refuse that option), whatever the
// gates say by then: restoring undoes only the module's own change, to the value it recorded.
inline bool RestoreThroughApi(bool earlierThroughApi, ConfigRoute route) {
    return earlierThroughApi || route == ConfigRoute::RemixApi;
}

// Convar names that RTXDebug.Engine.GetConVar may read outside local single-player. Outside a
// local game a remote server's client scripts can reach this module, so there GetConVar is limited
// to the rendering surface a multiplayer RTX session inspects; every other convar is refused, and
// ListConsole (which would enumerate them all) is refused outright. The list is deliberately short
// and matched case-insensitively by prefix. Names with unexpected characters never match.
inline bool IsRenderingConVar(std::string_view name) {
    if (name.empty() || name.size() > 128) return false;
    for (char c : name) {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9') || c == '_' || c == '.';
        if (!ok) return false;
    }
    static constexpr std::string_view kPrefixes[] = {"r_", "mat_", "rtx", "cl_draw"};
    for (std::string_view prefix : kPrefixes) {
        if (name.size() < prefix.size()) continue;
        bool match = true;
        for (std::size_t i = 0; i < prefix.size(); ++i) {
            char a = name[i];
            if (a >= 'A' && a <= 'Z') a = static_cast<char>(a - 'A' + 'a');
            if (a != prefix[i]) { match = false; break; }
        }
        if (match) return true;
    }
    return false;
}

} // namespace RTXDebug::Policy
