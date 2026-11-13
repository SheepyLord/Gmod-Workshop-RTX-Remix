-- Post-dispatch suppression through the live event registry, including cached callers.
local Beam = {}
function Beam.New(ctx, draw)
    local self, live, replaying = {}, true, false
    local event, id, fallbackId = "DrawPhysgunBeam", "nlvr.tools.beam_dispatch", "nlvr." .. ctx.name
    local call = hook.Call
    local registry, owner = ctx.core.Registry, ctx.core.Registry and ctx.core.Registry.current
    local original = hook.GetTable()[event]
    local ulib = type(hook.GetULibTable) == "function" and hook.GetULibTable()
    local originalLevels = type(ulib) == "table" and ulib[event]
    local function localVR(player)
        local active = ctx.Weapon and ctx.Weapon.Active
        return player == LocalPlayer() and active and active.kind == "physgun"
    end
    local function renderBeam(...)
        if registry and owner then registry:Call(owner, draw, ...) else draw(...) end
    end
    -- Register first: this creates an empty ULib event's priority lists. Unknown
    -- libraries keep this ordinary hook and must never make Start VR fail.
    ctx.hook(event, function(...)
        if live and not replaying and localVR(...) then renderBeam(...) return false end
    end)
    local plain = hook.GetTable()
    local held = plain[event] or {}
    local fallback = held[fallbackId]
    local levels = type(ulib) == "table" and ulib[event]
    local owned, ownedLevels
    function self.Stop()
        if not live then return end
        live = false
        if owned and plain[event] == owned then plain[event] = held end
        if ownedLevels and ulib[event] == ownedLevels then ulib[event] = levels end
        local current = hook.GetTable()[event]
        if current and current[fallbackId] == fallback then hook.Remove(event, fallbackId) end
        if owned then
            rawset(owned, id, nil)
            for key, fn in pairs(held) do rawset(owned, key, fn) end
        end
        if plain[event] == held and not original and not next(held) then plain[event] = nil end
        if ownedLevels then
            local empty = true
            for n = -2, 2 do
                rawset(ownedLevels[n], id, nil)
                for key, value in pairs(levels[n]) do rawset(ownedLevels[n], key, value) end
                if next(levels[n]) then empty = false end
            end
            if ulib[event] == levels and not originalLevels and empty then ulib[event] = nil end
        end
    end
    if levels then for n = -2, 2 do if type(levels[n]) ~= "table" then return self end end end
    if not levels then
        if type(ulib) == "table" then return self end
        local probe, first, second = "NLVRToolsBeamRegistryProbe", {}, {}
        local before = hook.GetTable()[probe]
        hook.Add(probe, id, function() return first end)
        local table = hook.GetTable() local saved = table[probe]
        table[probe] = {[id] = function() return second end}
        local ok, result = pcall(call, probe, nil)
        table[probe] = saved hook.Remove(probe, id)
        if not before and saved and not next(saved) then table[probe] = nil end
        if not ok or result ~= second then return self end
    end
    owned = setmetatable({}, {__index = held, __newindex = function(_, key, fn) held[key] = fn end})
    local function dispatch(...)
        if not live or replaying then return end
        if plain[event] ~= owned and (not ownedLevels or ulib[event] ~= ownedLevels) then return end
        local isLocal = localVR(...)
        if plain[event] == owned then plain[event] = held end
        if ownedLevels and ulib[event] == ownedLevels then ulib[event] = levels end
        replaying = true
        local gm = isLocal and gmod and gmod.GetGamemode and gmod.GetGamemode() or nil
        local ok, a, b, c, d, e, f = pcall(call, event, gm, ...)
        replaying = false
        if live and plain[event] == held then plain[event] = owned end
        if live and ownedLevels and ulib[event] == levels then ulib[event] = ownedLevels end
        if not ok then error(a, 0) end
        if isLocal then
            renderBeam(...)
            return false
        end
        return a, b, c, d, e, f
    end
    rawset(owned, id, dispatch)
    if levels then
        ownedLevels = {}
        for n = -2, 2 do
            local list = levels[n]
            ownedLevels[n] = setmetatable({}, {__index = list, __newindex = function(_, key, value) list[key] = value end})
        end
        rawset(ownedLevels[HOOK_HIGH or -1], id, {fn = dispatch, isstring = true})
        ulib[event] = ownedLevels
    end
    plain[event] = owned
    return self
end
return Beam
