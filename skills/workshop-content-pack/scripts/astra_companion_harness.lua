-- Runs an add-on made by astra_companion.py against mocked GMod and Remix APIs (LuaJIT).
-- usage: luajit astra_companion_harness.lua <add-on folder> <scenario>
-- scenarios: lifecycle, other_map, no_remix, disable, reload, player_sky, sky_takeover.
-- Prints PASS <scenario> or exits nonzero.

local ADDON, SCENARIO = arg[1], arg[2] or "lifecycle"
assert(ADDON and ADDON ~= "", "usage: astra_companion_harness.lua <add-on folder> <scenario>")
local NAME = ADDON:match("([^/\\]+)[/\\]*$")

local function fail(fmt, ...) error(string.format(fmt, ...), 2) end
local function check(cond, fmt, ...) if not cond then fail(fmt, ...) end end

------------------------------------------------------------ GMod

bit = require("bit")
SERVER, CLIENT = false, true
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function Color(r, g, b) return { r = r, g = g, b = b } end
local output = {}
function MsgC(...)
    local parts = {}
    for _, v in ipairs({ ... }) do if type(v) == "string" then parts[#parts + 1] = v end end
    output[#output + 1] = table.concat(parts)
end
local VectorMeta = {}
VectorMeta.__index = VectorMeta
function Vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, VectorMeta) end

local currentMap = "unset"
game = { GetMap = function() return currentMap end }

local hooks = {}
hook = {
    Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
    GetTable = function() return hooks end,
    Run = function(event, ...)
        for _, fn in pairs(hooks[event] or {}) do
            local a = fn(...)
            if a ~= nil then return a end
        end
    end,
}

local timers, simple = {}, {}
timer = {
    Create = function(id, delay, reps, fn) timers[id] = { delay = delay, reps = reps, left = reps, fn = fn } end,
    Remove = function(id) timers[id] = nil end,
    Simple = function(delay, fn) simple[#simple + 1] = { delay = delay, fn = fn } end,
    Exists = function(id) return timers[id] ~= nil end,
}
local function runSimple()
    while #simple > 0 do
        local queue = simple
        simple = {}
        for _, t in ipairs(queue) do t.fn() end
    end
end
local function tick(id)
    local t = timers[id]
    if not t then return false end
    t.fn()
    if timers[id] == t then
        t.left = t.left - 1
        if t.reps ~= 0 and t.left <= 0 then timers[id] = nil end
    end
    return true
end

local convars, callbacks = {}, {}
local function newConVar(name, value)
    local cv = { name = name, value = tostring(value) }
    function cv:GetString() return self.value end
    function cv:GetBool() return tonumber(self.value) ~= 0 end
    function cv:SetString(v)
        local old = self.value
        self.value = tostring(v)
        for _, cb in pairs(callbacks[name] or {}) do cb(name, old, self.value) end
    end
    convars[name] = cv
    return cv
end
function CreateClientConVar(name, default) return convars[name] or newConVar(name, default) end
function GetConVar(name) return convars[name] end
function RunConsoleCommand(name, value) if convars[name] then convars[name]:SetString(value) end end
cvars = { AddChangeCallback = function(name, fn, id) callbacks[name] = callbacks[name] or {} callbacks[name][id] = fn end }
local commands = {}
concommand = { Add = function(name, fn) commands[name] = fn end }

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
file = { Read = function(path, where) check(where == "LUA", "file.Read %s from %s", path, tostring(where)) return readFile(ADDON .. "/lua/" .. path) end }
function CompileString(code, name) return loadstring(code, name) end
function include(path)
    local fn, err = loadfile(ADDON .. "/lua/" .. path)
    check(fn, "include %s: %s", path, tostring(err))
    return fn()
end
function AddCSLuaFile() end

local materials = {}
local MaterialMeta = {}
MaterialMeta.__index = MaterialMeta
function MaterialMeta:IsError() return self.error end
function MaterialMeta:GetVector(key) local v = self.vars[key] return v and Vector(v.x, v.y, v.z) or nil end
function MaterialMeta:SetVector(key, v)
    check(not self.locked, "%s changed at shutdown", self.name)
    self.vars[key] = Vector(v.x, v.y, v.z)
    self.sets = self.sets + 1
end
function MaterialMeta:Recompute() self.recomputes = self.recomputes + 1 end
function Material(name)
    local mat = materials[name]
    if not mat then
        mat = setmetatable({ name = name, vars = {}, error = true, sets = 0, recomputes = 0 }, MaterialMeta)
        materials[name] = mat
    end
    return mat
end

------------------------------------------------------------ Remix

local rtxConf = {}
local live, setCalls = {}, {}
local function installRemix()
    RemixConfig = {
        SetConfigVariable = function(key, value)
            setCalls[#setCalls + 1] = { key, value }
            if key == "rtx.refused" then return false end
            live[key] = value
            return true
        end,
        GetConfigVariable = function(key) return rtxConf[key] or "" end,
    }
    local nextId, lights = 0, {}
    RemixLight = {}
    for _, kind in ipairs({ "Sphere", "Rect", "Disk", "Distant" }) do
        RemixLight["Create" .. kind] = function(base, shape, entity)
            check(type(base.hash) == "number" and type(base.radiance) == "table", "light base")
            check(type(shape) == "table" and entity == 0, "light shape")
            nextId = nextId + 1
            lights[nextId] = { kind = kind, base = base, shape = shape }
            return nextId
        end
    end
    RemixLight.DestroyLight = function(id) lights[id] = nil return true end
    RemixLight.lights = lights
    local categories, textureHashes = {}, {}
    RemixMaterial = {
        GetAllTextureHashes = function(name) return textureHashes[name] or {} end,
        GetHashCategory = function(hash) return categories[hash] end,
        SetHashCategory = function(hash, flags)
            check(type(hash) == "string" and hash:match("^0x%x+$"), "hash must be a hex string")
            categories[hash] = bit.bor(categories[hash] or 0, flags)
            return true
        end,
        RemoveHashCategory = function(hash) categories[hash] = nil return true end,
        categories = categories, textureHashes = textureHashes,
    }
    local cleared = 0
    Light2RTX = { Clear = function() cleared = cleared + 1 end, cleared = function() return cleared end }
end

------------------------------------------------------------ the add-on

local profile = assert(loadfile(ADDON .. "/lua/" .. NAME .. "/profile.lua"))()
local hashes = assert(loadfile(ADDON .. "/lua/" .. NAME .. "/hashes.lua"))()
local autorun = ADDON .. "/lua/autorun/" .. NAME .. ".lua"

local function loadAddon()
    local fn = assert(loadfile(autorun))
    fn()
end

local function countLights() local n = 0 for _ in pairs(RemixLight.lights) do n = n + 1 end return n end

local PER_FRAME = { "Think", "Tick", "PreRender", "PostRender", "RenderScene", "PreDrawOpaqueRenderables", "PostDrawOpaqueRenderables",
    "PreDrawTranslucentRenderables", "PostDrawTranslucentRenderables", "HUDPaint", "RenderScreenspaceEffects", "CalcView", "SetupWorldFog" }
local function assertNoPerFrameHooks()
    for _, event in ipairs(PER_FRAME) do
        check(not (hooks[event] and hooks[event][profile.id]), "the add-on hooks %s (per frame)", event)
    end
end

local function prepareWorld()
    newConVar("rtx_api_map_lights_autospawn", "1")
    rtxConf["rtx.skyMode"] = nil
    rtxConf[profile.remix[#profile.remix][1]] = "configured-value"
    -- tint materials: the first two tinted, the third already white
    if profile.tint then
        for i, name in ipairs(profile.tint.materials) do
            local mat = Material(name)
            mat.error = false
            for _, key in ipairs(profile.tint.keys) do
                mat.vars[key] = i <= 2 and Vector(0.5, 0.6, 0.7) or Vector(1, 1, 1)
            end
        end
    end
    -- a stand-in hook of the base map for each hooks_off entry
    for _, h in ipairs(profile.hooks_off or {}) do hook.Add(h[1], h[2], function() end) end
    -- categories: every material but the last of each category has a hash already
    for c, category in ipairs(profile.categories or {}) do
        for i, name in ipairs(category.materials) do
            if i < #category.materials then
                RemixMaterial.textureHashes[name] = { string.format("0x%X", 0xA000 + c * 256 + i) }
            end
        end
    end
end

local function normalized(text) return "0x" .. string.rep("0", 18 - #text) .. text:sub(3):upper() end

local function start()
    hook.Run("Initialize")
    hook.Run("InitPostEntity")
    runSimple()
end

local function lifecycle()
    installRemix()
    prepareWorld()
    currentMap = profile.map
    loadAddon()
    local M = _G[profile.global]
    check(istable(M), "the runtime registers %s", profile.global)
    check(convars.rtx_api_map_lights_autospawn:GetString() == "0", "Light2RTX autospawn is off from the file's load")
    check(#setCalls == 0 and countLights() == 0, "nothing reaches Remix before the start")
    if profile.sky_owner then check(hook.Run("NativeLoaderSkyOwner") == profile.title, "the sky owner hook answers") end
    local skySet = 0
    hook.Add("NativeLoaderSkySet", "harness", function() skySet = skySet + 1 end)
    assertNoPerFrameHooks()

    start()
    check(M.started, "started after InitPostEntity + 3 s")
    check(countLights() == #profile.lights, "lights %d of %d", countLights(), #profile.lights)
    check(Light2RTX.cleared() == (profile.clear_light2rtx and 1 or 0), "Light2RTX cleared once")
    for _, option in ipairs(profile.remix) do
        check(live[option[1]] == option[2], "%s = %s (got %s)", option[1], option[2], tostring(live[option[1]]))
    end
    check(not profile.sky_owner or skySet == 1, "NativeLoaderSkySet after the settings")
    if profile.tint then
        local first, third = Material(profile.tint.materials[1]), Material(profile.tint.materials[3] or profile.tint.materials[1])
        for _, key in ipairs(profile.tint.keys) do
            local v = first.vars[key]
            check(v.x == 1 and v.y == 1 and v.z == 1, "%s %s neutral", first.name, key)
        end
        check(#profile.tint.materials < 3 or third.sets == 0, "a white tint is left alone")
        check(M.TintCount() == math.min(2, #profile.tint.materials), "tint count %d", M.TintCount())
        check(not profile.tint.recompute or first.recomputes == 1, "recompute once")
    end
    for _, h in ipairs(profile.hooks_off or {}) do
        check(not (hooks[h[1]] and hooks[h[1]][h[2]]), "stand-in %s/%s removed", h[1], h[2])
    end
    local categories = profile.categories or {}
    check(M.pendingCategories == #categories, "pending materials %d, expected %d", M.pendingCategories, #categories)
    local foreignHash
    if #categories > 0 then
        check(timers[profile.id .. "_categories"], "the category retry timer runs")
        for _, category in ipairs(categories) do
            local name = category.materials[#category.materials]
            RemixMaterial.textureHashes[name] = { string.format("0xBEEF%02X", category.flag % 251) }
        end
        tick(profile.id .. "_categories")
        check(M.pendingCategories == 0, "every material found after its first draw")
        check(not timers[profile.id .. "_categories"], "the retry timer stops")
        for _, category in ipairs(categories) do
            local name = category.materials[#category.materials]
            local hash = normalized(string.format("0xBEEF%02X", category.flag % 251))
            check(bit.band(RemixMaterial.categories[hash] or 0, category.flag) ~= 0, "%s tagged %d", name, category.flag)
        end
        -- another producer's tag on one of the hashes must survive the release
        local first = RemixMaterial.textureHashes[categories[1].materials[1]]
        if first then
            foreignHash = normalized(first[1])
            RemixMaterial.categories[foreignHash] = bit.bor(RemixMaterial.categories[foreignHash], 0x1000)
        end
    end
    -- the first minute: three more passes, then the timer ends
    local calls = #setCalls
    for _ = 1, 3 do check(tick(profile.id .. "_settings"), "settings timer") end
    check(not timers[profile.id .. "_settings"], "the settings timer ends after three passes")
    check(#setCalls == calls + 3 * #profile.remix, "three re-applies")
    assertNoPerFrameHooks()

    -- status and coverage
    output = {}
    local seen = 0
    for name, aliases in pairs(hashes) do
        if seen < 2 then RemixMaterial.textureHashes[name] = { aliases[1] } end
        seen = seen + 1
    end
    commands[profile.prefix .. "_status"]()
    local text = table.concat(output, "\n")
    check(text:find("mod coverage: 2 materials hashed as the mod expects", 1, true), "coverage line: %s", text)

    -- unload
    for _, m in pairs(materials) do m.locked = true end
    hook.Run("ShutDown")
    check(not M.started, "stopped")
    check(countLights() == 0, "lights destroyed")
    for i = #profile.remix, 1, -1 do
        local key = profile.remix[i][1]
        local want = rtxConf[key] or profile.defaults[key]
        check(live[key] == want, "%s restored to %s (got %s)", key, tostring(want), tostring(live[key]))
    end
    check(convars.rtx_api_map_lights_autospawn:GetString() == "1", "Light2RTX autospawn restored")
    for _, h in ipairs(profile.hooks_off or {}) do
        check(hooks[h[1]] and hooks[h[1]][h[2]], "stand-in %s/%s back", h[1], h[2])
    end
    for hash, flags in pairs(RemixMaterial.categories) do
        check(hash == foreignHash and flags == 0x1000, "%s keeps the tags %d after the release", hash, flags)
    end
    check(foreignHash == nil or RemixMaterial.categories[foreignHash] == 0x1000, "the other producer's tag survives")
end

local function otherMap()
    installRemix()
    newConVar("rtx_api_map_lights_autospawn", "1")
    currentMap = "gm_construct"
    loadAddon()
    check(_G[profile.global] == nil, "nothing on another map")
    check(next(hooks) == nil, "no hooks on another map")
    check(convars.rtx_api_map_lights_autospawn:GetString() == "1", "autospawn untouched")
end

local function noRemix()
    RemixConfig, RemixLight, RemixMaterial, Light2RTX = nil, nil, nil, nil
    newConVar("rtx_api_map_lights_autospawn", "1")
    currentMap = profile.map
    loadAddon()
    start()
    local M = _G[profile.global]
    check(not M.started, "no start without the Remix API")
    check(table.concat(output, "\n"):find("not available", 1, true), "it says so")
end

local function disable()
    installRemix()
    prepareWorld()
    currentMap = profile.map
    loadAddon()
    start()
    local M = _G[profile.global]
    check(M.started, "started")
    convars[profile.prefix .. "_enable"]:SetString("0")
    check(not M.started and countLights() == 0, "switched off")
    if profile.tint then
        local v = Material(profile.tint.materials[1]).vars[profile.tint.keys[1]]
        check(v.x == 0.5 and v.y == 0.6 and v.z == 0.7, "tints back when switched off")
    end
    check(convars.rtx_api_map_lights_autospawn:GetString() == "1", "autospawn back when switched off")
    check(not profile.sky_owner or hook.Run("NativeLoaderSkyOwner") == nil, "the sky goes back to the companion")
    convars[profile.prefix .. "_enable"]:SetString("1")
    check(M.started and countLights() == #profile.lights, "on again")
end

local function reload()
    installRemix()
    prepareWorld()
    currentMap = profile.map
    loadAddon()
    start()
    local first = _G[profile.global]
    loadAddon()
    runSimple()
    local second = _G[profile.global]
    check(first ~= second and not first.started and second.started, "a reload stops the old runtime and starts the new")
    check(countLights() == #profile.lights, "no doubled lights after a reload (%d)", countLights())
end

local function suns()
    local n = 0
    for _, light in pairs(RemixLight.lights) do if light.kind == "Distant" then n = n + 1 end end
    return n
end
local function distantInProfile()
    local n = 0
    for _, L in ipairs(profile.lights) do if L.type == "distant" then n = n + 1 end end
    return n
end
local function companionSky(follow)
    NATIVELOADER_SKY = { owner = function() end }
    newConVar("nativeloader_sky", "1")
    newConVar("nativeloader_sky_follow_map", follow)
    newConVar("nativeloader_sky_hour", "14.5")
end

-- The player chose their own sky before the map: the companion's sun, none of the scene's.
local function playerSky()
    installRemix()
    prepareWorld()
    companionSky("0")
    currentMap = profile.map
    loadAddon()
    start()
    local M = _G[profile.global]
    check(M.started and M.PlayerSkyInCharge(), "the player's sky is in charge")
    check(suns() == 0, "no scene sun under the player's sky (%d)", suns())
    check(countLights() == #profile.lights - distantInProfile(), "the other lights are there")
    for _, key in ipairs(profile.sky_keys or {}) do check(live[key] == nil, "%s left to the companion", key) end
    check(not profile.fog_owner or hook.Run("NativeLoaderRemixFogOverride") == true, "the haze stays the map's")
    hook.Run("ShutDown")
    check(not profile.fog_owner or hook.Run("NativeLoaderRemixFogOverride") == nil, "the haze goes back after the map")
end

-- The sky follows the map until a sky setting changes, and comes back with the map's skybox.
local function skyTakeover()
    installRemix()
    prepareWorld()
    companionSky("1")
    currentMap = profile.map
    loadAddon()
    -- the engine sets the player's saved values after the convars are created: no change of theirs
    newConVar("nativeloader_weather", "partlyCloudy")
    convars.nativeloader_weather:SetString("clear")
    start()
    local M = _G[profile.global]
    check(not M.PlayerSkyInCharge() and suns() == distantInProfile(), "the map's sky and suns at first")
    -- a set to the same value is no change
    convars.nativeloader_sky_follow_map:SetString("1")
    check(not M.PlayerSkyInCharge(), "setting the same value takes nothing over")
    -- following the map, the companion writes the hour and direction itself: not a takeover
    convars.nativeloader_sky_hour:SetString("16.25")
    newConVar("nativeloader_sky_direction", "0")
    convars.nativeloader_sky_direction:SetString("212.5")
    check(not M.PlayerSkyInCharge() and suns() == distantInProfile(), "the companion's own writes keep the map's sky")
    -- the player moves the hour: the companion switches Follow the map's sun off
    convars.nativeloader_sky_follow_map:SetString("0")
    check(M.PlayerSkyInCharge() and suns() == 0, "the player's own time hands the sky over: suns gone (%d)", suns())
    local calls = #setCalls
    tick(profile.id .. "_settings")
    for i = calls + 1, #setCalls do
        for _, key in ipairs(profile.sky_keys or {}) do check(setCalls[i][1] ~= key, "%s not set again", key) end
    end
    convars.nativeloader_sky:SetString("0")
    check(not M.PlayerSkyInCharge() and suns() == distantInProfile(), "the map's skybox brings the suns back")
    for _, key in ipairs(profile.sky_keys or {}) do
        local want
        for _, option in ipairs(profile.remix) do if option[1] == key then want = option[2] end end
        check(want == nil or live[key] == want, "%s set again (%s)", key, tostring(live[key]))
    end
    hook.Run("ShutDown")
    check(countLights() == 0, "no light left after the map")
end

local scenarios = { lifecycle = lifecycle, other_map = otherMap, no_remix = noRemix, disable = disable, reload = reload,
    player_sky = playerSky, sky_takeover = skyTakeover }
check(scenarios[SCENARIO], "unknown scenario %s", SCENARIO)
scenarios[SCENARIO]()
print("PASS " .. SCENARIO)
