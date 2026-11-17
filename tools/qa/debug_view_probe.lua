-- QA probe (ADR 0237): Remix's albedo debug view set and put back through the RTX debug module, from the same pinned
-- camera. Run by poc_session.py with --camera, --hide-hud, --lua and --lua-shots. Each view gets a Source `jpeg`
-- (garrysmod/screenshots/<NL_DBG_PREFIX>_<label>.jpg) and an NL_SHOT window capture, answered by the driver with
-- nl_shot_taken. Prints NL_DBG lines: the module's gates, every call's result, the override's route.
local PREFIX = NL_DBG_PREFIX or "nl_dbgview"
local VIEW = NL_DBG_VIEW or 23 -- DEBUG_VIEW_ALBEDO in the runtime's debug_view_indices.h
local SETTLE = NL_DBG_SETTLE or 8 -- seconds after a change before the captures: denoisers and exposure
local KEY = "rtx.debugView.debugViewIdx"

local function report(what, ...)
    local values = {}
    for i = 1, select("#", ...) do values[i] = tostring((select(i, ...))) end
    print("NL_DBG " .. what .. " " .. table.concat(values, " | "))
end

local function json(value)
    return istable(value) and util.TableToJSON(value) or tostring(value)
end

local steps, step = {}, 0
local function nextStep()
    step = step + 1
    local current = steps[step]
    if not current then
        print("NL_SHOT_DONE")
        return
    end
    current()
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.5, nextStep) end)

local function capture(label)
    timer.Simple(SETTLE, function()
        LocalPlayer():ConCommand("jpeg " .. PREFIX .. "_" .. label .. " 95")
        report("jpeg", PREFIX .. "_" .. label)
        timer.Simple(2, function() print("NL_SHOT " .. label) end)
    end)
end

if not (istable(RTXDebug) and istable(RTXDebug.Remix)) then
    report("error", "the RTX debug module is not loaded")
    print("NL_SHOT_DONE")
    return
end
report("status", json(RTXDebug.Status()))

steps = {
    function()
        -- RemixConfig keeps refusing the option to every Lua (ADR 0234); the capture shows it did not change.
        report("remixconfig", RemixConfig and RemixConfig.SetConfigVariable(KEY, tostring(VIEW)))
        capture("before")
    end,
    function()
        report("set", RTXDebug.Remix.SetDebugView(VIEW, 0))
        report("overrides", json(RTXDebug.Remix.Overrides()))
        capture("view" .. VIEW)
    end,
    function()
        report("restore", RTXDebug.Remix.RestoreConfig(KEY))
        report("overrides", json(RTXDebug.Remix.Overrides()))
        capture("restored")
    end,
}
nextStep()
