-- Loads the RTX fixes' light updater (GPL, packages/fixes) under a fake GMod API and checks which helpers a
-- frame draws (R28, ADR 0144). Usage: luajit tools/tests/light_updater_harness.lua <cl_rtx_light_updater.lua> <scenario>
local path, scenario = arg[1], arg[2]
local function check(condition, message)
    if not condition then error("FAIL " .. tostring(scenario) .. ": " .. tostring(message), 2) end
end

---------------------------------------------------------------- vectors and angles
local vector = {}
vector.__index = vector
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vector) end
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector.__mul = function(a, b)
    if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
    return Vector(a.x * b, a.y * b, a.z * b)
end
vector.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
vector.__tostring = function(a) return string.format("%g %g %g", a.x, a.y, a.z) end
function vector:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function vector:Distance(b) return (self - b):Length() end
function vector:DistToSqr(b) local d = self - b return d.x * d.x + d.y * d.y + d.z * d.z end
function vector:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function vector:GetNormalized()
    local length = self:Length()
    if length == 0 then return Vector(0, 0, 0) end
    return Vector(self.x / length, self.y / length, self.z / length)
end
local angle = {}
angle.__index = angle
function Angle(p, y, r) return setmetatable({pitch = p or 0, yaw = y or 0, roll = r or 0}, angle) end
function angle:Forward()
    local p, y = math.rad(self.pitch), math.rad(self.yaw)
    return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function angle:Right()
    local y = math.rad(self.yaw)
    return Vector(math.sin(y), -math.cos(y), 0)
end
function angle:Up()
    local p, y = math.rad(self.pitch), math.rad(self.yaw)
    return Vector(math.sin(p) * math.cos(y), math.sin(p) * math.sin(y), math.cos(p))
end

---------------------------------------------------------------- the game, as far as the file uses it
CLIENT = true
FCVAR_ARCHIVE, FCVAR_NONE = 128, 0
MASK_OPAQUE, MASK_SOLID, RENDERGROUP_OTHER = 16513, 33570827, 4
-- The fake map has forty lights: the draw list is asked for on every map (-1), as the scenarios need it.
local convars = {rtx_lightupdater = "1", rtx_lightupdater_debug_console = "0", rtx_lightupdater_all = "-1"}
local function convar(name, default)
    if convars[name] == nil then convars[name] = tostring(default) end
    local object = {}
    function object:GetBool() return (tonumber(convars[name]) or 0) ~= 0 end
    function object:GetInt() return math.floor(tonumber(convars[name]) or 0) end
    function object:SetBool(value) convars[name] = value and "1" or "0" end
    return object
end
function CreateConVar(name, default) return convar(name, default) end
function GetConVar(name) return convars[name] ~= nil and convar(name, convars[name]) or nil end
file = {Exists = function() return false end}
function include() return nil end
local hooks, commands = {}, {}
hook = {
    Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
}
concommand = {Add = function(name, fn) commands[name] = fn end}
cvars = {AddChangeCallback = function() end}
function IsValid(object) return object ~= nil and object.valid == true end
math.Clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local printed = {}
local real_print = print
function print(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end

local clock, frame, frame_time = 100, 0, 0.0125
function SysTime() clock = clock + 0.0004 return clock end
function CurTime() return frame * frame_time end
function RealFrameTime() return frame_time end
function FrameNumber() return frame end
function ScrW() return 1920 end
function ScrH() return 1080 end
local eye, eye_angles = Vector(0, 0, 0), Angle(0, 0, 0)
function EyePos() return eye end
function EyeAngles() return eye_angles end
local world_entity = {valid = false, world = true}
game = {GetMap = function() return "gm_harness" end, GetWorld = function() return world_entity end}
local spawned = {gmod_light = {}, gmod_lamp = {}}
ents = {FindByClass = function(class) return spawned[class] or {} end}
-- Dynamic lights made from Lua, as the game hands them out: a fresh object per call whose fields can be written,
-- not read (light.pos is nil). With the "entity" variant the object has no metatable to watch.
function isvector(value) return getmetatable(value) == vector end
local indexed = {}
function Entity(index) return indexed[index] or {valid = false} end
local dynamic_lights, written = {}, setmetatable({}, {__mode = "k"})
local dlight = {__index = function() return nil end,
    __newindex = function(object, field, value) written[object][field] = value end}
function DynamicLight(key)
    dynamic_lights[key] = dynamic_lights[key] or {}
    if arg[3] == "entity" then return dynamic_lights[key] end
    local object = setmetatable({}, dlight)
    written[object] = dynamic_lights[key]
    return object
end

-- Helpers: every draw is counted for the frame, by the light it stands at.
local draws, helper_count = {}, 0
function ClientsideModel()
    helper_count = helper_count + 1
    local helper = {valid = true}
    function helper:SetNoDraw() end
    function helper:SetAngles() end
    function helper:SetPos(pos) self.pos = pos end
    function helper:Remove() self.valid = false end
    function helper:DrawModel() draws[#draws + 1] = self.pos end
    return helper
end
local view_setup = {fov = 106.26, fov_unscaled = 90, aspect = 1920 / 1080, zfar = 0}
render = {
    GetColorModulation = function() return 1, 1, 1 end, SetColorModulation = function() end,
    GetBlend = function() return 1 end, SetBlend = function() end,
    GetViewSetup = function() return view_setup end,
    GetHDREnabled = function() return false end,
}

-- Traces: walls are planes x = c (a ray that crosses one is stopped there); the sky is seen from z above sky_from.
local walls, sky_from, traces = {}, nil, 0
local function trace(input)
    traces = traces + 1
    local out = input.output or {}
    local from, to = input.start, input.endpos
    local fraction = 1
    for _, wall in ipairs(walls) do
        local a, b = from.x - wall, to.x - wall
        if (a < 0 and b > 0) or (a > 0 and b < 0) then
            local at = a / (a - b)
            if at < fraction then fraction = at end
        end
    end
    out.Fraction, out.Hit, out.StartSolid = fraction, fraction < 1, false
    out.HitSky = fraction == 1 and sky_from ~= nil and from.z >= sky_from and to.z > from.z + 1000
    return out
end
util = {TraceLine = trace, TraceHull = function() return {Hit = false, StartSolid = false, Fraction = 1} end}

-- The map: light entities and world lights (the engine's list), as NikNaks gives them.
local entities, world_lights, options = {}, {}, {}
local function light(class, x, y, z, extra)
    local entity = {classname = class, origin = Vector(x, y, z), angles = Angle(0, 0, 0)}
    for key, value in pairs(extra or {}) do entity[key] = value end
    entities[#entities + 1] = entity
    return entity
end
local function world_light(kind, x, y, z, brightness, extra)
    local entry = {type = kind, origin = Vector(x, y, z), intensity = Vector(brightness, brightness, brightness),
        normal = Vector(0, 0, -1), style = 0, radius = 0, constant_attn = 0, linear_attn = 0, quadratic_attn = 1}
    for key, value in pairs(extra or {}) do entry[key] = value end
    world_lights[#world_lights + 1] = entry
    return entry
end
local map = {}
function map:FindByClass(class)
    local found = {}
    for _, entity in ipairs(entities) do if entity.classname == class then found[#found + 1] = entity end end
    return found
end
function map:GetBrushBounds() return Vector(-8000, -8000, -8000), Vector(8000, 8000, 8000) end
function map:IsAABBOutsideMap() return false end
function map:FindStaticInSphere() return {} end
function map:GetWorldLights()
    local list = {}
    for index, entry in ipairs(world_lights) do list[index - 1] = entry end
    return list
end
-- Visibility, for the scenarios that ask for it: the row is cut into clusters of ten lights, each of which sees
-- itself alone; a spot at or beyond no_cluster_from is in none.
local clustered, no_cluster_from = false, nil
local function cluster_at(x)
    if no_cluster_from and x >= no_cluster_from then return -1 end
    return math.floor((x + 128) / 2560) + 2
end
local function with_clusters()
    clustered = true
    for _, entry in ipairs(world_lights) do entry.cluster = cluster_at(entry.origin.x) end
    function map:ClusterFromPoint(pos) return cluster_at(pos.x) end
    function map:PVSForOrigin(pos) return {[cluster_at(pos.x)] = true, __map = self} end
end
NikNaks = {CurrentMap = map}
local real_require = require
function require(name) if name == "niknaks" then return NikNaks end return real_require(name) end
RemixConfig = {GetConfigVariable = function(name) return options[name] or "" end}

---------------------------------------------------------------- driving it
local EMIT_SURFACE, EMIT_POINT, EMIT_SPOT, EMIT_SKY = 0, 1, 2, 3
-- A row of plain lights along x, one every 256 units around the map's middle, each with its world light.
local function X(index) return (index - 20) * 256 end
local function row(count)
    for index = 0, count - 1 do
        light("light", X(index), 0, 100)
        world_light(EMIT_POINT, X(index), 0, 100, 5000)
    end
end
local loaded = false
local function load()
    dofile(path)
    loaded = true
end
-- One frame from an eye; returns which lights' helpers were drawn (by the x of the light, helpers stand 8 units
-- before it) and how many.
local function run(x, yaw, y)
    check(loaded, "the updater was not loaded")
    frame = frame + 1
    eye, eye_angles = Vector(x, y or 0, 100), Angle(0, yaw or 0, 0)
    for _, fn in pairs(hooks.Think or {}) do fn() end
    draws = {}
    local render_hook = hooks.PostDrawTranslucentRenderables and hooks.PostDrawTranslucentRenderables.RTXReady_RenderLightUpdaters
    check(render_hook, "the render hook is not installed")
    render_hook(false, false)
    -- A plain light's helper stands 8 units before it; only those are entered here, by the light's number.
    local drawn = {}
    for _, pos in ipairs(draws) do
        local index = (pos.x + 8) / 256 + 20
        if index == math.floor(index) and pos.y == 0 then drawn[index] = pos end
    end
    return drawn, #draws
end
-- Whether the last frame drew a helper standing at x, y.
local function at(x, y)
    for _, pos in ipairs(draws) do
        if pos.x == x and pos.y == y then return true end
    end
    return false
end
-- Frames until the study is done (nothing left to work out), looking along the row from its start.
local function settle(x, yaw)
    for _ = 1, 400 do
        run(x or 0, yaw or 0)
        printed = {}
        commands.rtx_lightupdater_status()
        if printed[1] and printed[1]:find(" 0 are still being worked out", 1, true) then return end
    end
    error("FAIL " .. tostring(scenario) .. ": the study never finished: " .. tostring(printed[1]))
end
local function status()
    printed = {}
    commands.rtx_lightupdater_status()
    return table.concat(printed, "\n")
end
-- Moves on to where the next frame is one on which no light has its turn (turns are slots modulo the refresh
-- count).
local function quiet_frame(lights, refresh)
    while (frame + 1) % refresh <= lights do frame = frame + 1 end
end

if scenario == "bounded" then
    -- Forty steady point lights and nothing else: a helper is drawn while its light is in view or near.
    row(40)
    load()
    local _, first = run(X(30), 0)
    check(first == 40, "the first frame draws every helper, got " .. first)
    local _, second = run(X(30), 0)
    check(second == 40, "the frame after a rebuild draws every helper, got " .. second)
    local _, studying = run(X(30), 0)
    check(studying == 40, "helpers not worked out yet are drawn every frame, got " .. studying)
    settle(X(30), 0)
    check(status():find("40 lights, 40 of them steady point lights: 40 helpers are drawn only", 1, true), status())
    quiet_frame(40, 120)
    local drawn, count = run(X(30), 0)
    -- Looking along +x from light 30: lights 30-39 are ahead; 29 is within 450 units of the eye (the distance
    -- within which the runtime would hand a light that stops to a new dynamic light), 28 is not.
    for index = 30, 39 do check(drawn[index], "light " .. index .. " ahead is drawn") end
    check(drawn[29], "a light within 450 units of the eye is drawn")
    for index = 0, 28 do check(not drawn[index], "light " .. index .. " behind is not drawn") end
    check(count == 11, "the lights ahead and the one behind the eye, got " .. count)
    -- Turned round, the others are needed. Those now behind are held for two frames (the runtime tests a
    -- frame's lights with the view of the frame before), then they are not drawn.
    drawn = run(X(30), 180)
    for index = 0, 31 do check(drawn[index], "light " .. index .. " is drawn when looked at, or near the eye") end
    for index = 32, 39 do check(drawn[index], "light " .. index .. " is held on the frame after it left the view") end
    run(X(30), 180)
    drawn = run(X(30), 180)
    for index = 32, 39 do check(not drawn[index], "light " .. index .. " is not drawn three frames after it left the view") end
    -- Every helper out of view takes a turn within 120 frames.
    local seen = {}
    for _ = 1, 120 do
        local turn = run(X(30), 0)
        for index in pairs(turn) do seen[index] = true end
    end
    for index = 0, 39 do check(seen[index], "light " .. index .. " had its turn") end
    -- rtx_lightupdater_all 1 is the old behaviour.
    convars.rtx_lightupdater_all = "1"
    local _, all = run(X(30), 0)
    check(all == 40, "rtx_lightupdater_all 1 draws every helper, got " .. all)
    check(status():find("rtx_lightupdater_all 1", 1, true), status())
    -- 0, the default, uses the list only where a map has 256 lights or more: not here.
    convars.rtx_lightupdater_all = "0"
    _, all = run(X(30), 0)
    check(all == 40, "a map with forty lights draws every helper by default, got " .. all)
    check(status():find("the map has fewer than 256 lights", 1, true), status())
    convars.rtx_lightupdater_all = "-1"
    quiet_frame(40, 120)
    run(X(30), 0) run(X(30), 0) run(X(30), 0)
    check(#draws == 11, "-1 uses the list on every map, got " .. #draws)
elseif scenario == "dynamic" then
    -- The runtime hands a light that stops being set to a new point light within 300 units and erases it. So the
    -- lights within 450 units of a lamp, and of a light made with DynamicLight, never stop.
    row(40)
    local lamp = {valid = true}
    function lamp:GetPos() return Vector(X(5), 300, 100) end
    function lamp:GetAngles() return Angle(0, 0, 0) end
    function lamp:EntIndex() return 77 end
    spawned.gmod_light[1] = lamp
    load()
    settle(X(30), 0)
    quiet_frame(41, 120)
    for _ = 1, 4 do
        local drawn = run(X(30), 0)
        check(drawn[4] and drawn[5] and drawn[6], "the lights within 450 units of a lamp are drawn every frame")
        check(not drawn[3] and not drawn[7] and not drawn[10], "those farther from it are bounded")
        check(not drawn[14] and not drawn[15] and not drawn[16], "no dynamic light there yet")
    end
    -- A light made from Lua beside light 15, kept alive by a call every frame as add-ons do. Its position cannot
    -- be read from the object: it is noted as it is written ("entity": where that cannot be done, the entity the
    -- light is keyed by stands for it).
    local holder = {valid = true}
    function holder:GetPos() return Vector(X(15), 60, 100) end
    if arg[3] == "entity" then indexed[4001] = holder end
    check(DynamicLight(4001).pos == nil or arg[3] == "entity", "the object's fields cannot be read")
    for _ = 1, 4 do
        DynamicLight(4001).pos = Vector(X(15), 60, 100)
        local drawn = run(X(30), 0)
        check(drawn[14] and drawn[15] and drawn[16], "the lights within 450 units of a Lua dynamic light are drawn")
        check(not drawn[13] and not drawn[17], "those farther from it are not")
    end
    -- It moves on: the lights it left stop after the hold, those it reaches are drawn.
    function holder:GetPos() return Vector(X(20), 60, 100) end
    DynamicLight(4001).pos = Vector(X(20), 60, 100)
    local drawn = run(X(30), 0)
    check(drawn[19] and drawn[20] and drawn[21], "the lights it reached are drawn")
    for _ = 1, 3 do
        DynamicLight(4001).pos = Vector(X(20), 60, 100)
        drawn = run(X(30), 0)
    end
    check(not drawn[14] and not drawn[15], "the lights it left are bounded again")
    -- Its add-on stops calling: a dozen frames and the hold later the lights there are bounded again.
    for _ = 1, 16 do drawn = run(X(30), 0) end
    quiet_frame(41, 120)
    drawn = run(X(30), 0)
    check(not drawn[19] and not drawn[20] and not drawn[21], "a Lua light no longer made is forgotten")
    check(drawn[4] and drawn[5] and drawn[6], "the lamp is still there")
elseif scenario == "texture_light" then
    -- A texture light (a spot light for the runtime: dropped the frame it is not set) beside light 5: the
    -- helpers that may set it are drawn every frame, wherever the eye looks. Far from it nothing changes.
    row(40)
    -- strong, pvs, solid: a texture light bright enough to outshine every neighbour of a helper ten lights away.
    -- The engine takes a light only from a cluster the helper's leaf can see: with the map's visibility data
    -- (pvs) that helper is bounded, without it (strong), or where its spot is in no cluster (solid), it is not.
    local far = arg[3] == "strong" or arg[3] == "pvs" or arg[3] == "solid"
    world_light(EMIT_SURFACE, X(5) + 60, 80, 100, far and 10000000 or 1000)
    -- With walls round light 15 only three steady lights are in sight from its helper: too few to be sure
    -- that the engine's four leave the texture light out, far as it is.
    local closed = arg[3] == "walls"
    if closed then walls = {X(15) - 300, X(15) + 300} end
    if arg[3] == "solid" then no_cluster_from = X(12) end
    if arg[3] == "pvs" or arg[3] == "solid" then with_clusters() end
    load()
    settle(X(30), 0)
    quiet_frame(40, 120)
    for _ = 1, 3 do
        local drawn = run(X(30), 0)
        check(drawn[5], "the helper beside the texture light is drawn every frame")
        check(drawn[4] and drawn[6], "its neighbours, which may set the texture light too, are drawn every frame")
        if arg[3] == "strong" or arg[3] == "solid" then
            check(drawn[15] and drawn[20], "a texture light this bright may be set far along the row")
        elseif arg[3] == "pvs" then
            check(not drawn[15] and not drawn[20] and not drawn[25], "but not from a leaf that cannot see its cluster")
            check(drawn[9] and not drawn[10], "the texture light's own cluster ends between lights 9 and 10")
        else
            check(not drawn[20] and not drawn[25], "helpers far from the texture light are bounded")
            if closed then
                check(drawn[15], "a helper with too few steady lights in sight is drawn every frame")
            else
                check(not drawn[15], "a helper far from the texture light, with its neighbours in sight, is bounded")
            end
        end
    end
    check(not status():find("40 helpers are drawn only", 1, true), status())
elseif scenario == "spot_and_switched" then
    -- A light_spot has its own helper every frame, and so do a named light and a styled one. Each of those helpers
    -- is found to set its own light, so the steady lights beside them need not: they are bounded like the rest.
    -- walls: light 10's helper has three steady lights in sight, as few as in the texture light's scenario, and is
    -- bounded all the same. dim: the spot light is too dim to be among the two strongest where its own helper
    -- stands, so that helper is not known to set it, and the steady light beside it is drawn every frame again.
    row(40)
    local dim = arg[3] == "dim"
    light("light_spot", X(10) + 40, 0, 100)
    world_light(EMIT_SPOT, X(10) + 40, 0, 100, dim and 0.3 or 3000)
    light("light", X(20) + 40, 0, 100, {targetname = "switched"})
    world_light(EMIT_POINT, X(20) + 40, 0, 100, 3000, {style = 33})
    if arg[3] == "walls" or dim then walls = {X(10) - 300, X(10) + 300} end
    load()
    settle(X(39), 0)
    quiet_frame(42, 120)
    local drawn = run(X(39) + 100, 0)
    check(at(X(10) + 42, 0), "the spot light's own helper is drawn every frame")
    check(at(X(20) + 32, 0), "the switched light's own helper is drawn every frame")
    check(not drawn[0] and not drawn[15] and not drawn[30], "helpers away from them are bounded")
    check(not drawn[20], "the steady light beside the switched light is bounded: that light's own helper sets it")
    if dim then
        check(drawn[10], "a spot light its own helper is not known to set keeps the helper beside it drawn")
        check(status():find("1 more are set by their own helpers every frame, 1 have none", 1, true), status())
    else
        check(not drawn[10], "the steady light beside the spot light is bounded: the spot light's own helper sets it")
        check(status():find("2 more are set by their own helpers every frame, 0 have none", 1, true), status())
    end
elseif scenario == "light_set_by_a_neighbour" then
    -- Light A is dim where its own helper stands, beside two far stronger lights: the engine's four lights
    -- there need not include A, so A may reach the runtime only through its neighbours' helpers. Those are
    -- drawn while A is in view, although their own lights are not.
    local dim = arg[3] ~= "bright"
    light("light", 0, 0, 100)
    world_light(EMIT_POINT, 0, 0, 100, dim and 200 or 5000)
    for _, y in ipairs({1500, -1500}) do
        light("light", 0, y, 100)
        world_light(EMIT_POINT, 0, y, 100, 10000000)
    end
    load()
    -- The eye looks along +x at A from 300 units; the two others are far to the sides.
    for _ = 1, 40 do run(-300, 0) end
    check(status():find(" 0 are still being worked out", 1, true), status())
    quiet_frame(3, 120)
    run(-300, 0)
    check(at(-8, 0), "A's own helper is drawn while A is in view")
    if dim then
        check(at(-8, 1500) and at(-8, -1500), "the neighbours' helpers are drawn while A is in view: they may be what sets A")
        -- With A out of view too, and the eye more than 450 units from it, none is needed (after the hold).
        for _ = 1, 4 do run(-1000, 180) end
        check(#draws == 0, "nothing in view, nothing drawn, got " .. #draws)
    else
        check(not at(-8, 1500) and not at(-8, -1500), "the neighbours' helpers are not needed: A's own helper sets A")
    end
elseif scenario == "sky" then
    -- A helper that sees the sky along the sun may set the sun, a directional light: every frame.
    row(40)
    world_light(EMIT_SKY, 0, 0, 0, 3, {normal = Vector(0, 0, -1)})
    for _, entity in ipairs(entities) do
        if entity.origin.x >= X(20) then entity.origin = Vector(entity.origin.x, 0, 400) end
    end
    for _, entry in ipairs(world_lights) do
        if entry.type == EMIT_POINT and entry.origin.x >= X(20) then entry.origin = Vector(entry.origin.x, 0, 400) end
    end
    sky_from = 300
    load()
    settle(X(10), 180)
    quiet_frame(40, 120)
    local drawn = run(X(10), 180)
    for index = 20, 39 do check(drawn[index], "light " .. index .. " under the sky is drawn every frame") end
    check(not drawn[12] and not drawn[18], "lights indoors behind the eye are bounded")
elseif scenario == "options" then
    -- What the list relies on is off in rtx.conf: every helper every frame, and the status says why.
    row(40)
    options["rtx.antiCulling.light.enable"] = arg[3] == "frames" and "True" or " False "
    if arg[3] == "frames" then options["rtx.antiCulling.light.numFramesToExtendLightLifetime"] = "200" end
    load()
    if arg[3] == "frames" then
        -- A shorter lifetime in the runtime: the turns come round sooner (a quarter of it).
        settle(X(30), 0)
        local seen = {}
        for _ = 1, 50 do
            local turn = run(X(30), 0)
            for index in pairs(turn) do seen[index] = true end
        end
        for index = 0, 39 do check(seen[index], "light " .. index .. " had its turn within 50 frames") end
    else
        for _ = 1, 60 do
            local _, count = run(X(30), 0)
            check(count == 40, "every helper every frame, got " .. count)
        end
        check(status():find("rtx.antiCulling.light.enable is off in rtx.conf", 1, true), status())
    end
elseif scenario == "no_world_lights" then
    -- Without the map's world lights nothing can be worked out: every helper every frame, as before R28.
    row(40)
    if arg[3] == "mismatch" then
        for _, entry in ipairs(world_lights) do entry.origin = Vector(entry.origin.x + 4000, 500, 0) end
    elseif arg[3] == "layout" then
        world_lights[3].type = 1090519040
    else
        world_lights = {}
    end
    load()
    for _ = 1, 60 do
        local _, count = run(X(30), 0)
        check(count == 40, "every helper every frame, got " .. count)
    end
    local text = status()
    check(text:find("every light every frame", 1, true), text)
elseif scenario == "rebuild" then
    -- A lamp appears: the list is built again, every helper is drawn for two frames, and what was worked out
    -- for the map's lights is kept (no new traces for them).
    row(40)
    load()
    settle(X(30), 0)
    quiet_frame(40, 120)
    local _, before = run(X(30), 0)
    check(before <= 11, "bounded before the lamp, got " .. before)
    local lamp = {valid = true}
    function lamp:GetPos() return Vector(X(30), 300, 100) end
    function lamp:GetAngles() return Angle(0, 0, 0) end
    function lamp:EntIndex() return 77 end
    spawned.gmod_light[1] = lamp
    local grew = false
    for _ = 1, 400 do
        local _, count = run(X(30), 0)
        if count == 41 then grew = true break end
    end
    check(grew, "the lamp's helper appeared and every helper was drawn for the rebuild")
    local _, warm = run(X(30), 0)
    check(warm == 41, "the frame after the rebuild draws every helper, got " .. warm)
    traces = 0
    quiet_frame(41, 120)
    local _, after = run(X(30), 0)
    check(after <= 12, "bounded again at once, with the lamp's helper every frame, got " .. after)
    check(status():find(" 0 are still being worked out", 1, true), status())
    check(traces == 0, "nothing was worked out again, got " .. traces .. " traces")
else
    error("unknown scenario " .. tostring(scenario))
end
real_print("PASS " .. scenario .. (arg[3] and (" " .. arg[3]) or ""))
