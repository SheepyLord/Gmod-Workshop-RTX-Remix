#include "../source/render_policy.h"
#include "../source/session_policy.h"

#include <iostream>
#include <string>

namespace {

int g_failures = 0;

void Expect(bool condition, const char* what) {
    if (condition) return;
    std::cout << "FAIL: " << what << "\n";
    ++g_failures;
}

// What the engine reports in a game the player started themselves, and on a remote server.
RTXDebug::Policy::SessionFacts Session(bool loopback) {
    RTXDebug::Policy::SessionFacts facts;
    facts.connected = true;
    facts.netChannel = true;
    facts.loopback = loopback;
    facts.demoPlayback = false;
    facts.maxClients = 1;
    return facts;
}

} // namespace

int main() {
    using namespace RTXDebug::Policy;
    Expect(CanConfigureRendering(true, false, true, true), "the client rendering gate opens in the client realm");
    Expect(!CanConfigureRendering(false, false, true, true) && !CanConfigureRendering(true, true, true, true)
        && !CanConfigureRendering(true, false, false, true) && !CanConfigureRendering(true, false, true, false),
        "the client rendering gate needs the game thread, an open module, the client realm and RemixConfig");
    for (const auto key : {"rtx.pathMaxBounces", "rtx.showUI", "rtx.debugView.debugViewIdx"})
        Expect(CanSetConfig(false, true, key), "the rendering gate takes rtx.* names");
    for (const auto key : {"sv_cheats", "sv_allowcslua", "dxvk.foo", "rtx.", "rtx.foo;exec", "rtx.foo\nbar"})
        Expect(!CanSetConfig(false, true, key), "the rendering gate refuses other names");
    Expect(!CanSetConfig(false, false, "rtx.pathMaxBounces"), "no gate, no write");
    Expect(CanSetConfig(true, false, "existing_single_player_option"), "the developer gate passes any call");

    // ADR 0237: where a Remix option write goes. The regression: SetDebugView behind the developer
    // gate reached RemixConfig.SetConfigVariable, whose list (ADR 0234) refuses debug views, so the
    // view never changed. Behind that gate the module writes through the Remix API.
    const char* const debugView = "rtx.debugView.debugViewIdx";
    Expect(RouteConfig(true, true, debugView) == ConfigRoute::RemixApi,
        "behind the developer gate a debug view goes through the Remix API, not RemixConfig");
    Expect(RouteConfig(true, false, debugView) == ConfigRoute::RemixApi,
        "the developer gate does not need RemixConfig");
    for (const auto key : {"rtx.enableReplacementMaterials", "rtx.debugView.displayType", "rtx.pathMaxBounces"})
        Expect(RouteConfig(true, true, key) == ConfigRoute::RemixApi, "behind the developer gate every rtx.* option goes through the API");
    // Without the developer gate RemixConfig decides, as it does for any other Lua: a remote
    // server's client scripts and an add-on in an ordinary game get no more than RemixConfig gives.
    for (const auto key : {debugView, "rtx.enableReplacementMaterials", "rtx.pathMaxBounces"}) {
        Expect(RouteConfig(false, true, key) == ConfigRoute::RemixConfig,
            "without the developer gate an rtx.* write goes to RemixConfig, whose list decides");
        Expect(RouteConfig(false, false, key) == ConfigRoute::Refused, "without either gate a write is refused");
    }
    // Names that are not runtime options: refused whatever the gates (the runtime's options are
    // all rtx.*, and RemixConfig refuses every other name).
    const std::string tooLong = "rtx." + std::string(253, 'a');
    for (const std::string key : {std::string("sv_cheats"), std::string("existing_single_player_option"),
             std::string("dxvk.foo"), std::string("rtx."), std::string("rtx.foo;exec"), std::string("rtx.foo\nbar"),
             std::string(), tooLong}) {
        Expect(RouteConfig(true, true, key) == ConfigRoute::Refused, "the developer gate refuses names that are not rtx.* options");
        Expect(RouteConfig(false, true, key) == ConfigRoute::Refused, "the rendering gate refuses names that are not rtx.* options");
    }

    // The gates composed as the module composes them (session_policy.h): a remote server that runs
    // with sv_cheats 1 for a player launched with -insecure, and tells its scripts they are in
    // single-player, still reaches only RemixConfig; a local game opens the API route only with
    // -insecure and sv_cheats 1, so an add-on's Lua in an ordinary local game stays with RemixConfig.
    const bool remoteGate = CanMutate(true, false, true, IsLocalSinglePlayer(Session(false)), true);
    Expect(RouteConfig(remoteGate, true, debugView) == ConfigRoute::RemixConfig,
        "a remote insecure server with sv_cheats 1 cannot reach the Remix API route");
    const bool localSinglePlayer = IsLocalSinglePlayer(Session(true));
    Expect(RouteConfig(CanMutate(true, false, true, localSinglePlayer, true), true, debugView) == ConfigRoute::RemixApi,
        "local single-player with -insecure and sv_cheats 1 writes a debug view through the Remix API");
    Expect(RouteConfig(CanMutate(true, false, false, localSinglePlayer, true), true, debugView) == ConfigRoute::RemixConfig,
        "a local game without -insecure leaves the debug view to RemixConfig");
    Expect(RouteConfig(CanMutate(true, false, true, localSinglePlayer, false), true, debugView) == ConfigRoute::RemixConfig,
        "a local game with sv_cheats 0 leaves the debug view to RemixConfig");

    // A restore goes back the way the value went in, whatever the gates say by then.
    Expect(RestoreThroughApi(false, ConfigRoute::RemixApi), "a value written through the API is restored through it");
    Expect(!RestoreThroughApi(false, ConfigRoute::RemixConfig), "a value written through RemixConfig is restored through it");
    Expect(RestoreThroughApi(true, ConfigRoute::RemixConfig),
        "once written through the API, a value is restored through it after a later RemixConfig write");

    // The rendering-convar allowlist for Engine.GetConVar outside local single-player.
    for (const auto name : {"r_drawworld", "mat_queue_mode", "rtx_conf", "rtxSomething",
                            "cl_drawhud", "cl_drawviewmodel", "R_SHADOWS", "Mat_Fullbright"})
        Expect(IsRenderingConVar(name), "a rendering convar is readable");
    for (const auto name : {"sv_cheats", "sv_allowcslua", "rcon_password", "cl_name", "net_graph",
                            "", "mat_x;quit", "mat x", "server_rtx", "notrtx"})
        Expect(!IsRenderingConVar(name), "another convar is not readable");

    if (g_failures) return 1;
    std::cout << "Rendering policy tests passed\n";
    return 0;
}
