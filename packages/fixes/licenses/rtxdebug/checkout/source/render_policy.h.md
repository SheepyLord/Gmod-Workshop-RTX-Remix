# render_policy.h

Pure client-rendering configuration boundary. Local renderer changes require the module's client
realm, the game thread, an open module and Remix API availability. Only syntactically valid rtx.*
keys are accepted without the existing full single-player developer mutation gate. No cvar,
server, Lua execution, memory or detour authority is granted. `RouteConfig` says where a Remix
option write goes: behind the developer gate (session_policy.h) through the Remix API, so the
options `RemixConfig.SetConfigVariable` refuses to every Lua (debug views, the replacement
switches) can be set; under the client rendering gate alone to `RemixConfig`, whose list decides;
names that are not `rtx.*` options nowhere. `RestoreThroughApi` keeps a restore on the route its
value went in. `IsRenderingConVar` is the short allowlist of convar name prefixes (`rtx`, `r_`,
`mat_`, `cl_draw`) that `Engine.GetConVar` may read outside local single-player; every other convar
name is refused there. Tested by render_policy_test.cpp.
