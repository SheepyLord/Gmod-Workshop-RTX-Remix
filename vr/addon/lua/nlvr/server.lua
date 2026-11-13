-- Included only by the companion's dormant switch, only for the local single-player/listen host.
local server = include("nlvr/core/sv_core.lua").New(include("nlvr/sh_protocol.lua"))
server.Modules = {include("nlvr/modules/sv_move.lua"), include("nlvr/modules/sv_interact.lua"),
    include("nlvr/modules/sv_weapons.lua"), include("nlvr/modules/sv_reload.lua"), include("nlvr/modules/sv_tools.lua")}
return server
