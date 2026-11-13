-- The companion's V1 contract; no autorun and no native ownership here.
local Session, core = {}, nil
function Session.Start(native, onError, units)
    Session.Stop()
    core = include("nlvr/core/cl_core.lua").New(native, onError, units)
    local modules = {}
    -- Fixed list: feature tasks replace their own files without editing this composition root.
    for _, name in ipairs({"hud", "hands", "move", "ui", "weapons", "reload", "tools", "interact", "perf"}) do
        modules[#modules + 1] = include("nlvr/modules/cl_" .. name .. ".lua")
    end
    return core.Start(modules)
end
function Session.Stop() if core then core.Stop() core = nil end end
function Session.Recenter() if core then core.Recenter() end end
return Session
