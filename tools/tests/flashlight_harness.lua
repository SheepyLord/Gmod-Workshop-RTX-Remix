-- R19 regression for the RTX fixes' flashlight Lua under a fake GMod API (no game), and since ADR 0208
-- its automatic brightness:
--   luajit flashlight_harness.lua server <sv_remix_flashlight.lua>
--   luajit flashlight_harness.lua client <cl_remix_flashlight.lua>
--   luajit flashlight_harness.lua auto <cl_remix_flashlight.lua>
local mode, path = arg[1], arg[2]
assert((mode == "server" or mode == "client" or mode == "auto") and path,
    "usage: flashlight_harness.lua server|client|auto <file>")
BRANCH = "x86-64"
SERVER, CLIENT = mode == "server", mode ~= "server"

local now = 100
local frame = 1 / 60
function SysTime() return now end
function CurTime() return now end
function RealTime() return now end
function RealFrameTime() return frame end
local timers = {}
timer = {Simple = function(delay, fn) timers[#timers + 1] = {at = now + delay, fn = fn} end}
local function advance(seconds)
    now = now + seconds
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
    end
    for i = #due, 1, -1 do due[i].fn() end
end

local printed = {}
function print(...) printed[#printed + 1] = table.concat({...}, " ") end
function MsgC() end
function istable(v) return type(v) == "table" end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a or 255} end
function tobool(v) return v == true or v == 1 or v == "1" end
math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
MASK_OPAQUE_AND_NPCS = 33570945
local hooks, receivers, commands = {}, {}, {}
hook = {Add = function(event, name, fn) hooks[event] = fn end}
concommand = {Add = function(name, fn) commands[name] = fn end}
cvars = {AddChangeCallback = function() end}
file = {Exists = function() return false end}
-- include() resolves the fixes' own Lua (the shared light gain) beside the given file's lua/ folder.
local luaRoot = path:gsub("\\", "/"):match("^(.*/lua/)")
function include(name)
    if luaRoot and name:match("^remixlua/") then return dofile(luaRoot .. name) end
end

-- Convars by name, so a test can change one the file created.
local convars = {}
local function convar(name, default)
    local cv = {value = default}
    convars[name] = cv
    function cv:GetBool() return tobool(self.value) end
    function cv:GetFloat() return tonumber(self.value) or 0 end
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    return cv
end
function CreateConVar(name, default) return convar(name, default) end
function CreateClientConVar(name, default) return convar(name, default) end
function GetConVar(name) return convars[name] end
local commandsRun = {}
function RunConsoleCommand(name, value)
    commandsRun[#commandsRun + 1] = {name, value}
    if convars[name] then convars[name].value = value end
end

-- net: what a handler reads is queued by the test; what the code sends is recorded.
local incoming, sent, building = {}, {}, nil
local function take() return table.remove(incoming, 1) end
net = {
    Receive = function(name, fn) receivers[name] = fn end,
    Start = function(name) building = {name = name, data = {}} end,
    WriteEntity = function(v) table.insert(building.data, v) end,
    WriteBool = function(v) table.insert(building.data, v) end,
    WriteUInt = function(v) table.insert(building.data, v) end,
    Broadcast = function() building.to = "all" sent[#sent + 1] = building end,
    Send = function(target) building.to = target sent[#sent + 1] = building end,
    SendToServer = function() building.to = "server" sent[#sent + 1] = building end,
    ReadEntity = take, ReadBool = take, ReadUInt = take,
}
local function receive(name, from, ...)
    -- A refused message is left unread, as GMod discards what a receiver does not read.
    incoming = {...}
    receivers[name](0, from)
end
local function count(name)
    local n = 0
    for _, message in ipairs(sent) do if message.name == name then n = n + 1 end end
    return n
end
local function last(name)
    for i = #sent, 1, -1 do if sent[i].name == name then return sent[i] end end
end

-- Vectors with the methods the file uses, global as in the game.
local vector = {}
vector.__index = vector
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vector) end
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector.__mul = function(a, s)
    if type(a) == "number" then a, s = s, a end
    return Vector(a.x * s, a.y * s, a.z * s)
end
function vector:Set(b) self.x, self.y, self.z = b.x, b.y, b.z end
function vector:Mul(s) self.x, self.y, self.z = self.x * s, self.y * s, self.z * s end
function vector:Add(b) self.x, self.y, self.z = self.x + b.x, self.y + b.y, self.z + b.z end
function vector:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function vector:Distance(b) return (self - b):Length() end
local angles = {Forward = function() return Vector(1, 0, 0) end, Right = function() return Vector(0, 1, 0) end,
                Up = function() return Vector(0, 0, 1) end}
local entities = 0
local function Player(team)
    entities = entities + 1
    local p = {valid = true, alive = true, can = true, team = team or "player", index = entities,
               eye = Vector(0, 0, 64)}
    function p:Alive() return self.alive end
    function p:CanUseFlashlight() return self.can end
    function p:EntIndex() return self.index end
    function p:Nick() return "player" .. self.index end
    function p:EyePos() return self.eye end
    function p:EyeAngles() return angles end
    function p:ShouldDrawLocalPlayer() return false end
    function p:EmitSound() end
    return p
end
-- The base gamemode's rule: spectators may only switch off, others as CanUseFlashlight says.
gmod = {GetGamemode = function()
    return {PlayerSwitchFlashlight = function(_, ply, on)
        if ply.team == "spectator" then return not on end
        return ply:CanUseFlashlight()
    end}
end}

-- The fake world for automatic brightness: a wall across +x at `wall` (nil: open space), traces that
-- start inside something when `solid` is set, and a car's `hull` 12 units ahead of wherever a trace
-- starts unless the trace's filter names it. Every trace is counted.
local world = {wall = nil, solid = false, hull = nil, traces = 0}
local function filtered(t, ent)
    if type(t.filter) == "table" and t.filter.valid == nil then
        for _, v in pairs(t.filter) do if v == ent then return true end end
        return false
    end
    return t.filter == ent
end
util = {AddNetworkString = function() end, CRC = function(text) return tostring(#text) end,
    TraceLine = function(t)
        world.traces = world.traces + 1
        local out = t.output or {}
        local s, e = t.start, t.endpos
        local hit, fraction = false, 1
        if world.wall and e.x > s.x and s.x < world.wall then
            local f = (world.wall - s.x) / (e.x - s.x)
            if f <= 1 then hit, fraction = true, f end
        end
        if world.hull and not filtered(t, world.hull) and e.x > s.x then
            local f = 12 / (e.x - s.x)
            if f < fraction then hit, fraction = true, f end
        end
        out.Hit, out.StartSolid, out.Fraction = hit or world.solid, world.solid, world.solid and 0 or fraction
        out.HitPos = world.solid and Vector(s.x, s.y, s.z)
            or Vector(s.x + (e.x - s.x) * fraction, s.y + (e.y - s.y) * fraction, s.z + (e.z - s.z) * fraction)
        return out
    end}

if mode == "server" then
    dofile(path)
    local switch = hooks.PlayerSwitchFlashlight
    local ply = Player()
    -- F-04: a burst of toggles costs one broadcast; the next one after the cooldown counts.
    for _ = 1, 10 do receive("rtx_flashlight_toggle", ply, 1, 2, 3) advance(0.01) end
    assert(count("rtx_flashlight_state") == 1 and last("rtx_flashlight_state").data[2] == true, "one toggle in the burst")
    advance(0.3)
    receive("rtx_flashlight_toggle", ply, 1, 2, 3)
    assert(count("rtx_flashlight_state") == 2 and last("rtx_flashlight_state").data[2] == false, "the next toggle after it")
    -- The miss: no flashlight for the dead, spectators or a player the gamemode denies; off always.
    ply.alive = false
    advance(1)
    receive("rtx_flashlight_toggle", ply, 1, 2, 3)
    assert(count("rtx_flashlight_state") == 2, "a dead player's toggle does not switch on")
    assert(switch(ply, true) == false, "nor does the flashlight key")
    ply.alive, ply.can = true, false
    advance(1)
    assert(switch(ply, true) == false, "CanUseFlashlight decides")
    local spectator = Player("spectator")
    assert(switch(spectator, true) == false and switch(spectator, false) == true, "spectators may only switch off")
    ply.can = true
    advance(1)
    assert(switch(ply, true) == true and last("rtx_flashlight_state").data[2] == true, "an allowed player switches on")
    assert(switch(ply, true) == false, "a second switch on within the cooldown is refused")
    assert(switch(ply, false) == true and last("rtx_flashlight_state").data[2] == false, "switching off is never refused")
    -- F-04: colours are coalesced: the first goes out at once, the newest when the interval ends.
    advance(1)
    assert(switch(ply, true) == true)
    local colours = count("rtx_flashlight_update_color")
    for i = 1, 10 do receive("rtx_flashlight_update_color", ply, i, i, i) advance(0.005) end
    assert(count("rtx_flashlight_update_color") == colours + 1, "one colour at once")
    advance(0.2)
    local newest = last("rtx_flashlight_update_color")
    assert(count("rtx_flashlight_update_color") == colours + 2 and newest.data[2] == 10 and newest.data[4] == 10,
        "then the newest colour")
    -- A switched-off flashlight broadcasts no colour.
    advance(1)
    assert(switch(ply, false) == true)
    receive("rtx_flashlight_update_color", ply, 5, 5, 5)
    advance(1)
    assert(count("rtx_flashlight_update_color") == colours + 2, "no colour while off")
    hooks.PlayerDisconnected(ply)
    assert(last("rtx_flashlight_state").data[1] == ply and last("rtx_flashlight_state").data[2] == false)
    io.write("PASS flashlight server: toggle cooldown, gamemode and CanUseFlashlight rule, coalesced colours\n")
    return
end

local localPlayer = Player()
function LocalPlayer() return localPlayer end
-- The Remix lights: each one's radiance and volumetric scale as last created or updated.
local nextId, live, haze, destroyed = 0, {}, {}, 0
RemixLight = {
    CreateSphere = function(base, sphere)
        nextId = nextId + 1
        live[nextId], haze[nextId] = base.radiance.x, sphere.volumetricRadianceScale
        return nextId
    end,
    DestroyLight = function(id) assert(live[id], "a live light") live[id] = nil destroyed = destroyed + 1 end,
    UpdateSphere = function(base, sphere, id)
        assert(live[id], "updates go to a live light")
        live[id], haze[id] = base.radiance.x, sphere.volumetricRadianceScale
    end,
}
local function lights() local n = 0 for _ in pairs(live) do n = n + 1 end return n end
dofile(path)

if mode == "client" then
    local other = Player()
    -- F-03: the join-time sync repeats an "on" the broadcast already gave: the first light goes.
    receive("rtx_flashlight_state", nil, other, true, 10, 20, 30)
    receive("rtx_flashlight_state", nil, other, true, 10, 20, 30)
    assert(lights() == 1 and destroyed == 1, "a repeated on replaces the light")
    hooks.PreRender()
    receive("rtx_flashlight_state", nil, other, false, 0, 0, 0)
    assert(lights() == 0, "off removes it")
    receive("rtx_flashlight_state", nil, localPlayer, true, 1, 2, 3)
    receive("rtx_flashlight_state", nil, localPlayer, true, 1, 2, 3)
    assert(lights() == 1, "the local player's light too")
    commands.rtx_flashlight_reload()
    advance(0.2)
    assert(lights() == 1, "reload keeps one light")
    io.write("PASS flashlight client: a repeated on replaces the light, off and reload keep the count\n")
    return
end

---------------------------------------------------------------- automatic brightness (ADR 0208)
local Gain = dofile(luaRoot .. "remixlua/cl/remixapi/cl_remix_light_gain.lua")
local function near(a, b, tolerance, what)
    assert(math.abs(a - b) <= tolerance * math.max(1, math.abs(b)), what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function step(frames)
    for _ = 1, frames or 1 do advance(frame) hooks.PreRender() end
end
-- The gain a wall `wall` units ahead of the eyes should give, worked out the way the file's comments
-- describe: seven traces from the eyes (the axis and six at half the cone, at most 20 degrees off it,
-- the axis counting twice), measured from the light, which sits rtx_flashlight_offset_forward behind.
local function expected(wall)
    local cone = tonumber(convars.rtx_flashlight_cone_angle.value)
    local back = -tonumber(convars.rtx_flashlight_offset_forward.value)
    local reference = tonumber(convars.rtx_flashlight_auto_distance.value)
    local strength = tonumber(convars.rtx_flashlight_auto_strength.value)
    local maxGain = tonumber(convars.rtx_flashlight_auto_max.value)
    local radius = tonumber(convars.rtx_flashlight_radius.value)
    local reach = math.Clamp(reference * maxGain ^ (1 / (2 * strength)) * 1.25, 512, 8192)
    local samples = {}
    for i, c in ipairs(Gain.Ring(math.Clamp(cone * 0.5, 2, 20), 6)) do
        local t = wall and wall / c[1] or reach
        if t > reach then t = reach end
        local x, y, z = c[1] * t + back, c[2] * t, c[3] * t
        samples[i] = math.sqrt(x * x + y * y + z * z)
    end
    local d = Gain.EffectiveDistance(samples, 7, {2, 1, 1, 1, 1, 1, 1}, 2, radius, reach)
    return Gain.Target(d, reference, strength, 2, radius, 1 / 64, maxGain)
end

-- The defaults: on, strength 0.8, normal distance 256, at most 8 times; Brightness 1000 is radiance 255.
assert(convars.rtx_flashlight_auto.value == "1", "automatic brightness is on by default")
world.wall = 251 -- the light 5 units behind the eyes: the beam's axis lands 256 units from it
receive("rtx_flashlight_state", nil, localPlayer, true, 255, 255, 255)
local id = next(live)
near(live[id] / 255, expected(251), 1e-9, "the light comes on at the gain its beam wants, not at the fixed level")
assert(math.abs(live[id] / 255 - 1) < 0.15, "a wall at about the normal distance keeps about the set brightness")

-- A wall up close: within a few frames the light is far dimmer, not blown out.
world.wall = 30
step(12) -- 0.2 s
local close = expected(30)
assert(close < 0.2, "a wall 35 units from the light wants under a fifth of the brightness")
local logShare = function(value, from, to) return math.log(value / from) / math.log(to / from) end
assert(logShare(live[id] / 255, expected(251), close) > 0.9, "dimming is done within 0.2 s")
step(60)
near(live[id] / 255, close, 1e-6, "and settles on the wall's gain")

-- Open space: brighter, at most rtx_flashlight_auto_max times, and only gently.
world.wall = nil
step(12)
assert(logShare(live[id] / 255, close, 8) < 0.35, "brightening is gentle: under a third of the way in 0.2 s")
step(600)
near(live[id] / 255, 8, 1e-6, "far away it reaches Max Boost and stays there")
near(expected(nil), 8, 1e-9, "nothing hit counts as the farthest distance")
-- The boost lights far surfaces, not the haze beside the player: the volumetric scale is divided by it.
convars.rtx_flashlight_volumetric.value = "2"
step(7)
near(haze[id], 2 / 8, 1e-6, "the haze stays at its set level under an eightfold boost")

-- Inside a wall (noclip) the traces tell nothing: the gain holds.
world.solid = true
step(30)
near(live[id] / 255, 8, 1e-6, "traces that start in a solid leave the gain as it was")
world.solid = false

-- Off: the fixed brightness exactly, as before automatic brightness.
convars.rtx_flashlight_auto.value = "0"
world.wall = 30
step(7)
assert(live[id] == 255, "rtx_flashlight_auto 0 is the fixed brightness: radiance " .. tostring(live[id]))
local before = world.traces
step(10)
assert(world.traces == before, "and no traces at all")

-- On again: the measurement starts over at the new gain, without easing from the old one.
convars.rtx_flashlight_auto.value = "1"
step(7)
near(live[id] / 255, close, 1e-6, "switched on again, it is at the wall's gain at once")

-- In a car whose seat is parented to it, the car's own hull is no wall up close.
local car = {valid = true, GetParent = function() return nil end}
local seat = {valid = true, GetParent = function() return car end}
localPlayer.InVehicle = function() return true end
localPlayer.GetVehicle = function() return seat end
world.hull, world.wall = car, 251
step(600)
near(live[id] / 255, expected(251), 1e-6, "the car's hull is left out of the measurement")
localPlayer.InVehicle, localPlayer.GetVehicle, world.hull = nil, nil, nil
world.wall = 30
step(60)

-- Your own light is measured every frame (seven traces); another player's ten times a second.
local other = Player()
other.eye = Vector(0, 100, 64)
receive("rtx_flashlight_state", nil, other, true, 255, 255, 255)
before = world.traces
step(60) -- one second
local traces = world.traces - before
assert(traces >= 7 * 60 + 7 * 9 and traces <= 7 * 60 + 7 * 11,
    "60 frames: 420 traces for your light and about 70 for the other one, not " .. traces)

-- Strength 0 changes nothing with distance; the normal distance and Max Boost are honoured.
convars.rtx_flashlight_auto_strength.value = "0"
step(600)
near(live[id] / 255, 1, 1e-6, "strength 0 keeps the set brightness")
convars.rtx_flashlight_auto_strength.value = "1"
convars.rtx_flashlight_auto_max.value = "3"
world.wall = nil
step(600)
near(live[id] / 255, 3, 1e-6, "Max Boost 3")
convars.rtx_flashlight_auto_distance.value = "1024"
world.wall = 1019
step(600)
near(live[id] / 255, expected(1019), 1e-6, "a wall at a normal distance of 1024")
assert(math.abs(live[id] / 255 - 1) < 0.15, "keeps about the set brightness")

-- The menu: the section with its four settings, and Reset puts their defaults back.
local builder
spawnmenu = {AddToolMenuOption = function(_, _, _, _, _, _, fn) builder = fn end}
hooks.PopulateToolMenu()
local controls = {}
local panel = {}
function panel:ClearControls() end
function panel:Help(text) controls[#controls + 1] = {"help", text} end
function panel:ControlHelp(text) controls[#controls + 1] = {"controlhelp", text} end
function panel:CheckBox(label, name) controls[#controls + 1] = {"checkbox", label, name} end
function panel:NumSlider(label, name, lo, hi) controls[#controls + 1] = {"slider", label, name, lo, hi} end
function panel:AddItem() end
function panel:Button(label) local b = {label = label} controls[#controls + 1] = {"button", label, b} return b end
vgui = {Create = function()
    return {SetPalette = function() end, SetAlphaBar = function() end, SetWangs = function() end, SetColor = function() end}
end}
builder(panel)
local found = {}
for _, c in ipairs(controls) do if c[3] and type(c[3]) == "string" then found[c[3]] = c end end
assert(found.rtx_flashlight_auto and found.rtx_flashlight_auto[1] == "checkbox", "the switch")
assert(found.rtx_flashlight_auto_strength and found.rtx_flashlight_auto_strength[5] == 1, "Strength, 0-1")
assert(found.rtx_flashlight_auto_distance and found.rtx_flashlight_auto_max, "Normal Distance and Max Boost")
local reset
for _, c in ipairs(controls) do if c[1] == "button" then reset = c[3] end end
commandsRun = {}
reset.DoClick()
local set = {}
for _, c in ipairs(commandsRun) do set[c[1]] = c[2] end
assert(set.rtx_flashlight_auto == "1" and set.rtx_flashlight_auto_strength == "0.8"
    and set.rtx_flashlight_auto_distance == "256" and set.rtx_flashlight_auto_max == "8", "Reset restores the defaults")
io.write("PASS flashlight auto: comes on at its gain, dims fast, brightens gently up to Max Boost, holds in a solid, " ..
    "off is the fixed brightness, other players' lights measured ten times a second, menu and Reset\n")
