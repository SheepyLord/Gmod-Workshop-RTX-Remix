-- The character motion importer's dance light (lua/mmd_vmd_npc/cl_flashlight.lua) under a fake GMod API, no
-- game (ADR 0209): the light as it was with the defaults, uniform lighting, its subject, aim, colour
-- temperature, the rim light, presets and the vanilla projected texture.
--   luajit dance_light_harness.lua <add-on lua/mmd_vmd_npc folder> <scenario>
local dir, scenario = arg[1], arg[2]
assert(dir and scenario, "usage: dance_light_harness.lua <lua/mmd_vmd_npc folder> <scenario>")
local function fail(message) error("FAIL " .. scenario .. ": " .. message, 2) end
local function check(condition, message) if not condition then fail(message) end end
local function near(a, b, tolerance, what)
    if type(a) ~= "number" or math.abs(a - b) > (tolerance or 1e-9) * math.max(1, math.abs(b)) then
        fail((what or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
    end
end

---------------------------------------------------------------- vectors and angles, as Source has them
local vector = {}
vector.__index = vector
function Vector(x, y, z)
    if type(x) == "table" then x, y, z = x.x, x.y, x.z end
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector)
end
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector.__mul = function(a, s)
    if type(a) == "number" then a, s = s, a end
    return Vector(a.x * s, a.y * s, a.z * s)
end
vector.__div = function(a, s) return Vector(a.x / s, a.y / s, a.z / s) end
vector.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
vector.__tostring = function(a) return string.format("(%.3f %.3f %.3f)", a.x, a.y, a.z) end
function vector:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function vector:LengthSqr() return self:Dot(self) end
function vector:Length() return math.sqrt(self:Dot(self)) end
function vector:Distance(b) return (self - b):Length() end
function vector:DistToSqr(b) return (self - b):LengthSqr() end
function vector:GetNormalized() local l = self:Length() return l > 0 and self / l or Vector() end
function vector:Angle()
    local yaw, pitch
    if self.x == 0 and self.y == 0 then
        yaw, pitch = 0, self.z > 0 and 270 or 90
    else
        yaw = math.deg(math.atan2(self.y, self.x)) % 360
        pitch = math.deg(math.atan2(-self.z, math.sqrt(self.x ^ 2 + self.y ^ 2))) % 360
    end
    return Angle(pitch, yaw, 0)
end
local angle = {}
angle.__index = angle
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, angle) end
local function trig(a)
    local p, y, r = math.rad(a.p), math.rad(a.y), math.rad(a.r)
    return math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
end
function angle:Forward() local sp, cp, sy, cy = trig(self) return Vector(cp * cy, cp * sy, -sp) end
function angle:Right()
    local sp, cp, sy, cy, sr, cr = trig(self)
    return Vector(-sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp)
end
function angle:Up()
    local sp, cp, sy, cy, sr, cr = trig(self)
    return Vector(cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp)
end
function isvector(v) return getmetatable(v) == vector end
function isangle(v) return getmetatable(v) == angle end
function istable(v) return type(v) == "table" end
function IsValid(v) return type(v) == "table" and v.valid == true end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end

---------------------------------------------------------------- the game, as far as the file uses it
CLIENT = true
MASK_OPAQUE_AND_NPCS = 33570945
MOUSE_FIRST = 107
local now, frame = 100, 1 / 60
function RealTime() return now end
function RealFrameTime() return frame end
function CurTime() return now end
local convars = {}
function CreateClientConVar(name, default) if convars[name] == nil then convars[name] = default end end
function GetConVar(name)
    if convars[name] == nil then return nil end
    return {
        GetString = function() return tostring(convars[name]) end,
        GetBool = function() return (tonumber(convars[name]) or 0) ~= 0 end,
        GetFloat = function() return tonumber(convars[name]) or 0 end,
    }
end
local ran = {}
function RunConsoleCommand(name, value) ran[#ran + 1] = { name, value } convars[name] = value end
local hooks, commands = {}, {}
hook = { Add = function(event, name, fn) hooks[event .. "/" .. name] = fn end }
concommand = { Add = function(name, fn) commands[name] = fn end }
input = { IsKeyDown = function() return false end, IsMouseDown = function() return false end }
gui = { IsGameUIVisible = function() return false end }
vgui = { CursorVisible = function() return false end, GetKeyboardFocus = function() return nil end }
function include(name)
    if name == "mmd_vmd_npc/cl_light_gain.lua" then return dofile(dir .. "/cl_light_gain.lua") end
    error("unexpected include " .. tostring(name))
end

-- Entities: the player and dancers whose pelvis and head bones the test places.
local registry = {}
function Entity(index) return registry[index] or { valid = false } end
local function Ent(index, fields)
    local e = { valid = true, index = index, pos = Vector(), ang = Angle(), model = "models/dancer.mdl", bones = {},
                bonePos = {}, nw2 = {}, dormant = false, maxs = Vector(16, 16, 72) }
    for k, v in pairs(fields or {}) do e[k] = v end
    function e:EntIndex() return self.index end
    function e:GetPos() return Vector(self.pos) end
    function e:GetAngles() return Angle(self.ang.p, self.ang.y, self.ang.r) end
    function e:GetModel() return self.model end
    function e:LookupBone(name) return self.bones[name] end
    function e:GetBonePosition(id) return self.bonePos[id] and Vector(self.bonePos[id]), Angle() end
    function e:OBBMaxs() return Vector(self.maxs) end
    function e:IsDormant() return self.dormant end
    function e:GetNW2Bool(key, default) local v = self.nw2[key] if v == nil then return default end return v end
    registry[index] = e
    return e
end
local player = Ent(1, { eye = Vector(0, 0, 64), eyeAng = Angle(0, 0, 0) })
function player:EyePos() return Vector(self.eye) end
function player:EyeAngles() return Angle(self.eyeAng.p, self.eyeAng.y, self.eyeAng.r) end
function player:IsTyping() return false end
function LocalPlayer() return player end
-- A dancer standing at feet, `height` tall: pelvis at half its height, head at nine tenths.
local function Dancer(index, feet, height, how)
    height = height or 72
    local e = Ent(index, { pos = Vector(feet), bones = { ["ValveBiped.Bip01_Pelvis"] = 0, ["ValveBiped.Bip01_Head1"] = 6 } })
    e.bonePos[0] = feet + Vector(0, 0, height * 0.5)
    e.bonePos[6] = feet + Vector(0, 0, height * 0.9)
    if how == "local" then
        MMDVMDNPC.LocalPlaybacks = MMDVMDNPC.LocalPlaybacks or {}
        MMDVMDNPC.LocalPlaybacks[e] = {}
    elseif how ~= "still" then
        e.nw2.MMDVMDNPCDancing = true
    end
    return e
end

-- The Remix API: each light's fields as last created or updated.
local lights, created, destroyed = {}, 0, 0
local function copyLight(base, sphere)
    local s = sphere.shaping
    return { hash = base.hash, r = base.radiance.x, g = base.radiance.y, b = base.radiance.z,
             pos = Vector(sphere.position.x, sphere.position.y, sphere.position.z),
             dir = Vector(s.direction.x, s.direction.y, s.direction.z), cone = s.coneAngleDegrees,
             softness = s.coneSoftness, radius = sphere.radius, volumetric = sphere.volumetricRadianceScale }
end
local remixApi = {
    CreateSphere = function(base, sphere) created = created + 1 lights[created] = copyLight(base, sphere) return created end,
    UpdateSphere = function(base, sphere, id) check(lights[id], "an update goes to a live light") lights[id] = copyLight(base, sphere) end,
    DestroyLight = function(id) check(lights[id], "a live light is destroyed") lights[id] = nil destroyed = destroyed + 1 end,
}
RemixLight = remixApi
local function count() local n = 0 for _ in pairs(lights) do n = n + 1 end return n end

-- Source's projected textures.
local projected = {}
function ProjectedTexture()
    local pt = { valid = true, updates = 0 }
    for _, name in ipairs({ "Texture", "Pos", "Angles", "FOV", "FarZ", "NearZ", "Color", "Brightness", "EnableShadows" }) do
        pt["Set" .. name] = function(self, v) self[name] = v end
    end
    function pt:Update() self.updates = self.updates + 1 end
    function pt:Remove() self.valid = false end
    projected[#projected + 1] = pt
    return pt
end
local function livePT() local out = {} for _, pt in ipairs(projected) do if pt.valid then out[#out + 1] = pt end end return out end

-- util: a stable CRC, and traces against a wall across +x at world.wall (nil: open space) and a car's
-- hull 12 units ahead of wherever a trace starts unless the trace's filter names it.
local world = { wall = nil, hull = nil, traces = 0, cone = {}, scans = 0 }
local function filtered(t, ent)
    if type(t.filter) == "table" and t.filter.valid == nil then
        for _, v in pairs(t.filter) do if v == ent then return true end end
        return false
    end
    return t.filter == ent
end
util = {
    CRC = function(text) local h = 0 for i = 1, #text do h = (h * 31 + text:byte(i)) % 4294967296 end return tostring(h) end,
    TraceLine = function(t)
        world.traces = world.traces + 1
        local out, s, e = t.output, t.start, t.endpos
        local fraction, hit = 1, false
        if world.wall and e.x > s.x and s.x < world.wall then
            local f = (world.wall - s.x) / (e.x - s.x)
            if f <= 1 then fraction, hit = f, true end
        end
        if world.hull and not filtered(t, world.hull) and e.x > s.x then
            local f = 12 / (e.x - s.x)
            if f < fraction then fraction, hit = f, true end
        end
        out.Hit, out.StartSolid, out.Fraction = hit, false, fraction
        out.HitPos = s + (e - s) * fraction
        return out
    end,
}
ents = { FindInCone = function() world.scans = world.scans + 1 return world.cone end }

MMDVMDNPC = {}
local file = dir .. "/cl_flashlight.lua"
dofile(file)
local think = assert(hooks["Think/MMDVMDNPCFlashlight"], "the Think hook")
local function step(frames) for _ = 1, frames or 1 do now = now + frame think() end end
local KEYHASH = tonumber(util.CRC("mmd_vmd_npc_flashlight_1"))
local RIMHASH = tonumber(util.CRC("mmd_vmd_npc_flashlight_rim_1"))
local function byHash(hash) for id, l in pairs(lights) do if l.hash == hash then return l, id end end end
local function key() return byHash(KEYHASH) end
local function rim() return byHash(RIMHASH) end

-- The classic RTX install's values, which the companion applies as first-run defaults.
local function classic()
    for name, value in pairs({ brightness = "0.28", fov = "100", distance = "8192", nearz = "1", offset_forward = "-45",
        rtx_radius = "30", rtx_softness = "0.45", rtx_volumetric = "1", enabled = "1" }) do
        convars["mmd_vmd_npc_flashlight_" .. name] = value
    end
end
local BASE = 255 * 0.28 / 4 -- radiance per channel at Brightness 0.28

-- The camera path: anchored on `anchor`, the view at `pos` looking at `at`.
local function cameraPath(anchor, pos, at)
    MMDVMDNPC.CameraAnimActive = true
    MMDVMDNPC.CameraAnimEntIndex = anchor.index
    MMDVMDNPC.CameraAnimViewOrigin = Vector(pos)
    MMDVMDNPC.CameraAnimViewAngles = (at - pos):Angle()
end
-- The point of segment a-b nearest the line through o along d, found by a fine search, not the file's algebra.
local function nearestBySearch(a, b, o, d)
    local best, bestDist
    for i = 0, 20000 do
        local p = a + (b - a) * (i / 20000)
        local w = p - o
        local along = w:Dot(d)
        local off = (w - d * along):LengthSqr()
        if not bestDist or off < bestDist then best, bestDist = p, off end
    end
    return best
end
local function body(e)
    local pelvis, head = e.bonePos[0], e.bonePos[6]
    return pelvis + (pelvis - head), pelvis, head
end
-- The radiance uniform lighting should give for the light at origin along d lighting dancer e.
local function uniformRadiance(e, origin, d, opts)
    opts = opts or {}
    local feet, _, head = body(e)
    local distance = origin:Distance(nearestBySearch(feet, head, origin, d))
    local gain = (distance / (opts.reference or 150)) ^ (2 * (opts.strength or 1))
    return BASE * math.Clamp(gain, 1 / 64, opts.max or 16), distance
end

if scenario == "defaults" then
    -- The light as it was: the same place, direction, radiance and shaping, and no traces or looks for dancers.
    classic()
    player.eyeAng = Angle(10, 30, 0)
    step()
    local l = key()
    check(l and count() == 1, "one light")
    local forward = player.eyeAng:Forward()
    near((l.pos - (player.eye + forward * -45)):Length(), 0, 1e-9, "45 units behind the eyes")
    near((l.dir - forward):Length(), 0, 1e-12, "straight along the view")
    near(l.r, BASE, 1e-12, "radiance 255 * 0.28 / 4") near(l.g, BASE, 1e-12) near(l.b, BASE, 1e-12)
    check(l.cone == 50 and l.softness == 0.45 and l.radius == 30 and l.volumetric == 1, "the shaping as set")
    step(30)
    check(world.traces == 0 and world.scans == 0, "nothing measured with the new options off")
    -- The camera path's view, and no view at all.
    local dancer = Dancer(50, Vector(500, 0, 0), 72)
    cameraPath(dancer, Vector(300, 50, 60), Vector(500, 0, 40))
    step()
    l = key()
    near((l.pos - (MMDVMDNPC.CameraAnimViewOrigin + MMDVMDNPC.CameraAnimViewAngles:Forward() * -45)):Length(), 0, 1e-9,
        "the camera path's view")
    near(l.r, BASE, 1e-12, "the same brightness")
    MMDVMDNPC.CameraAnimActive = false
    convars.mmd_vmd_npc_flashlight_follow_eye = "0"
    step()
    check(count() == 0, "no view, no light")
    convars.mmd_vmd_npc_flashlight_follow_eye = "1"
    step()
    check(count() == 1, "back")
    -- A Lua refresh: the file runs again and takes the light it left behind.
    dofile(file)
    check(count() == 0, "a refresh reclaims the old light")
    think = hooks["Think/MMDVMDNPCFlashlight"]
    step()
    check(count() == 1, "and makes one new light")
    convars.mmd_vmd_npc_flashlight_enabled = "0"
    step()
    check(count() == 0, "off removes it")
    -- Vanilla Garry's Mod: a projected texture, set as before and not updated while nothing changes.
    RemixLight = nil
    convars.mmd_vmd_npc_flashlight_enabled = "1"
    step()
    local pts = livePT()
    check(#pts == 1, "one projected texture")
    local pt = pts[1]
    check(pt.Brightness == 0.28 and pt.FOV == 100 and pt.FarZ == 8192 and pt.NearZ == 1 and pt.EnableShadows == true,
        "brightness, FOV, distances and shadows as set")
    check(pt.Color.r == 255 and pt.Color.g == 255 and pt.Color.b == 255, "white")
    check(pt.Texture == "effects/flashlight001" and pt.Angles.p == 10 and pt.Angles.y == 30, "texture and view angles")
    step(5)
    check(pt.updates == 1, "no update while nothing changes")
    player.eyeAng = Angle(10, 31, 0)
    step()
    check(pt.updates == 2, "an update when the view turns")
elseif scenario == "uniform" then
    -- Uniform lighting on the camera path's dancer: the light follows its distance as the inverse square.
    classic()
    convars.mmd_vmd_npc_flashlight_uniform = "1"
    local dancer = Dancer(50, Vector(1000, 0, 0), 72)
    local chest = Vector(1000, 0, 50.4)
    -- Another dancer right on the view's axis, nearer: the path's own dancer stays the subject.
    Dancer(51, Vector(900, 0, 0), 72, "local")
    local samples = {}
    for _, distance in ipairs({ 60, 150, 400, 1200 }) do
        local cam = chest - Vector(distance, 0, 0)
        cameraPath(dancer, cam, chest)
        step()
        local l = key()
        local forward = MMDVMDNPC.CameraAnimViewAngles:Forward()
        local origin = cam + forward * -45
        local want, d = uniformRadiance(dancer, origin, forward)
        near(l.r, want, 1e-6, "a cut to " .. distance .. " units gives that distance's light in the same frame")
        -- A boost lights the far dancer, not the haze beside the camera; dimming dims the haze too.
        near(l.volumetric, 1 / math.max(1, want / BASE), 1e-9, "the haze at its set level")
        samples[#samples + 1] = { r = l.r, d = d }
    end
    -- Within the clamps the dancer gets the same light at every distance: radiance / d^2 is constant.
    near(samples[1].r / samples[1].d ^ 2, samples[2].r / samples[2].d ^ 2, 1e-6, "60 and 150 units")
    near(samples[3].r / samples[3].d ^ 2, samples[2].r / samples[2].d ^ 2, 1e-6, "400 and 150 units")
    near(samples[4].r, BASE * 16, 1e-9, "1245 units: Max boost 16")
    near(samples[2].r, BASE * (195 / 150) ^ 2, 1e-6, "Brightness applies at the normal distance (150) from the light")
    -- A smooth dolly-in is eased, never more than a little brighter than its target, and settles.
    local cam = chest - Vector(400, 0, 0)
    cameraPath(dancer, cam, chest)
    step(30)
    for i = 1, 30 do
        cam = chest - Vector(400 - i * 8, 0, 0)
        cameraPath(dancer, cam, chest)
        step()
        local want = uniformRadiance(dancer, cam + Vector(-45, 0, 0), Vector(1, 0, 0))
        check(key().r <= want * 1.15, "a dolly-in stays within 15 % of its target (frame " .. i .. ")")
    end
    step(10)
    near(key().r, (uniformRadiance(dancer, cam + Vector(-45, 0, 0), Vector(1, 0, 0))), 1e-3, "and settles on it")
    -- A face close-up: the distance is to the head, where the view's axis passes the body.
    local head = Vector(1000, 0, 64.8)
    cam = head - Vector(40, 0, 0)
    cameraPath(dancer, cam, head)
    step()
    local want, d = uniformRadiance(dancer, cam + Vector(-45, 0, 0), Vector(1, 0, 0))
    near(d, 85, 1e-3, "85 units from the light to the face")
    near(key().r, want, 1e-6, "the face's distance decides")
    -- Strength 0.5 halves the exponent; Max boost and the normal distance are honoured.
    convars.mmd_vmd_npc_flashlight_uniform_strength = "0.5"
    convars.mmd_vmd_npc_flashlight_uniform_distance = "300"
    convars.mmd_vmd_npc_flashlight_uniform_max = "2"
    cam = chest - Vector(1200, 0, 0)
    cameraPath(dancer, cam, chest)
    step()
    near(key().r, BASE * 2, 1e-9, "Max boost 2")
    cam = chest - Vector(100, 0, 0)
    cameraPath(dancer, cam, chest)
    step()
    near(key().r, (uniformRadiance(dancer, cam + Vector(-45, 0, 0), Vector(1, 0, 0),
        { strength = 0.5, reference = 300, max = 2 })), 1e-6, "strength 0.5 at a normal distance of 300")
    -- Off: the set brightness exactly; on again, the gain starts over at its target.
    convars.mmd_vmd_npc_flashlight_uniform = "0"
    step()
    near(key().r, BASE, 1e-12, "off is the brightness as set")
    convars.mmd_vmd_npc_flashlight_uniform = "1"
    step()
    near(key().r, (uniformRadiance(dancer, cam + Vector(-45, 0, 0), Vector(1, 0, 0),
        { strength = 0.5, reference = 300, max = 2 })), 1e-6, "on again: at its target at once")
    check(world.traces == 0, "a dancer in view needs no traces")
elseif scenario == "subject" then
    -- In first person the subject is the dancing character whose body passes nearest the light's axis.
    classic()
    convars.mmd_vmd_npc_flashlight_uniform = "1"
    convars.mmd_vmd_npc_flashlight_offset_forward = "0"
    local onAxis = Dancer(60, Vector(600, 0, 0), 72, "local") -- this client poses it
    local offAxis = Dancer(61, Vector(300, 150, 0), 72) -- only the server's flag says it dances
    local behind = Dancer(62, Vector(-200, 0, 0), 72, "local")
    local still = Dancer(63, Vector(200, 0, 0), 72, "still") -- not dancing: ignored though nearest
    world.cone = { offAxis, still }
    player.eye, player.eyeAng = Vector(0, 0, 50), Angle(0, 0, 0)
    step()
    local want = uniformRadiance(onAxis, player.eye, Vector(1, 0, 0))
    near(key().r, want, 1e-6, "the dancer on the axis, not the nearer one off it, the one behind or the still one")
    local scans = world.scans
    step(14)
    check(world.scans == scans, "dancers in the beam are looked for four times a second, not every frame")
    step(2)
    check(world.scans == scans + 1, "the next look after a quarter of a second")
    -- Without it the one off the axis, found by the look into the beam.
    MMDVMDNPC.LocalPlaybacks[onAxis] = nil
    onAxis.valid = false
    step(60)
    near(key().r, (uniformRadiance(offAxis, player.eye, Vector(1, 0, 0))), 1e-3, "then the dancer off the axis")
    -- No dancer in the beam: what the light points at, measured by seven traces.
    offAxis.nw2.MMDVMDNPCDancing = false
    world.wall = 400
    local traces = world.traces
    step(60)
    check(world.traces - traces == 7 * 60, "seven traces a frame")
    local G = dofile(dir .. "/cl_light_gain.lua")
    local samples = {}
    for i, c in ipairs(G.Ring(15, 6)) do samples[i] = 400 / c[1] end -- a quarter of the cone, at most 15 degrees
    local d = G.EffectiveDistance(samples, 7, { 2, 1, 1, 1, 1, 1, 1 }, 2, 30, 8192)
    near(key().r, BASE * G.Target(d, 150, 1, 2, 30, 1 / 64, 16), 1e-6, "the wall's distance")
    -- In a car whose seat is parented to it, the car's own hull is no wall up close.
    local car = Ent(70)
    local seat = Ent(71)
    function seat:GetParent() return car end
    function car:GetParent() return nil end
    function player:InVehicle() return true end
    function player:GetVehicle() return seat end
    world.hull = car
    step(30)
    near(key().r, BASE * G.Target(d, 150, 1, 2, 30, 1 / 64, 16), 1e-6, "the car's hull is left out")
    player.InVehicle, player.GetVehicle, world.hull = nil, nil, nil
    -- Nothing at all: the gain holds instead of jumping to its maximum.
    local held = key().r
    world.wall = nil
    step(30)
    near(key().r, held, 1e-12, "nothing hit: the light holds")
    -- The self playback's third-person view is about its dancer, wherever the axis points.
    local selfDancer = Dancer(64, Vector(0, 300, 0), 72, "local")
    MMDVMDNPC.SelfThirdPersonActive = true
    MMDVMDNPC.SelfPlaybackCameraEnt = selfDancer
    MMDVMDNPC.SelfThirdPersonViewOrigin = Vector(0, 150, 50)
    MMDVMDNPC.SelfThirdPersonViewAngles = Angle(0, 90, 0)
    step()
    near(key().r, (uniformRadiance(selfDancer, Vector(0, 150, 50), Vector(0, 1, 0))), 1e-6, "the self dancer")
elseif scenario == "aim" then
    -- Aim at the character: the light points at the part of the body the view is on, from the pelvis up.
    classic()
    convars.mmd_vmd_npc_flashlight_aim = "1"
    local dancer = Dancer(50, Vector(500, 0, 0), 72)
    local cam = Vector(300, 0, 50)
    cameraPath(dancer, cam, Vector(500, 0, 50))
    MMDVMDNPC.CameraAnimViewAngles = Angle(0, 15, 0) -- the dancer sits off the frame's centre
    step()
    local forward = MMDVMDNPC.CameraAnimViewAngles:Forward()
    local origin = cam + forward * -45
    local _, pelvis, head = body(dancer)
    local point = nearestBySearch(pelvis, head, cam, forward)
    near((key().dir - (point - origin):GetNormalized()):Length(), 0, 1e-4, "at the body where the view's axis passes")
    check(world.traces == 0, "no traces")
    -- Looking at the feet: the pelvis, never lower.
    cameraPath(dancer, cam, Vector(500, 0, 2))
    step()
    local down = cam + MMDVMDNPC.CameraAnimViewAngles:Forward() * -45
    near((key().dir - (pelvis - down):GetNormalized()):Length(), 0, 1e-9, "at most down to the pelvis")
    -- Without a character in view it points along the view as before.
    MMDVMDNPC.CameraAnimActive = false
    dancer.nw2.MMDVMDNPCDancing = false
    player.eyeAng = Angle(0, -40, 0)
    step()
    near((key().dir - player.eyeAng:Forward()):Length(), 0, 1e-12, "no character: along the view")
    -- The vanilla projected texture turns the same way.
    RemixLight = nil
    dancer.nw2.MMDVMDNPCDancing = true
    cameraPath(dancer, cam, Vector(500, 0, 50))
    MMDVMDNPC.CameraAnimViewAngles = Angle(0, 15, 0)
    step()
    local pt = livePT()[1]
    local aimed = (point - origin):GetNormalized():Angle()
    near(pt.Angles.p, aimed.p, 1e-4, "projected pitch") near(pt.Angles.y, aimed.y, 1e-4, "projected yaw")
elseif scenario == "temperature" then
    classic()
    local G = dofile(dir .. "/cl_light_gain.lua")
    step()
    near(key().r, BASE, 1e-12, "0 K is the RGB colour") near(key().b, BASE, 1e-12)
    convars.mmd_vmd_npc_flashlight_temperature = "3200"
    step()
    local l = key()
    check(l.r > l.g and l.g > l.b, "3200 K is warm")
    near((0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b) / BASE, 1, 1e-9, "at the luminance of white")
    local kr, kg, kb = G.Kelvin(3200)
    convars.mmd_vmd_npc_flashlight_color_g = "128"
    step()
    near(key().g, 128 * kg * 0.28 / 4, 1e-9, "the RGB colour tints it") near(key().r, 255 * kr * 0.28 / 4, 1e-9)
    convars.mmd_vmd_npc_flashlight_temperature = "6600"
    step()
    near(key().g, 128 * 0.28 / 4, 1e-9, "6600 K is white")
    -- The projected texture takes a colour up to 255: the rest goes into its brightness.
    RemixLight = nil
    convars.mmd_vmd_npc_flashlight_color_g = "255"
    convars.mmd_vmd_npc_flashlight_temperature = "2000"
    step()
    local pt = livePT()[1]
    kr, kg, kb = G.Kelvin(2000)
    check(pt.Color.r == 255, "the strongest channel at 255")
    near(pt.Brightness, 0.28 * kr, 1e-9, "the brightness carries the rest")
    check(pt.Color.g == math.floor(255 * kg / kr + 0.5), "green in proportion")
elseif scenario == "rim" then
    classic()
    convars.mmd_vmd_npc_flashlight_rim = "0.8"
    local dancer = Dancer(50, Vector(500, 0, 0), 72)
    local cam = Vector(300, 100, 50)
    cameraPath(dancer, cam, Vector(500, 0, 50))
    step()
    check(count() == 2, "the main light and the rim light")
    local r = rim()
    local _, pelvis, head = body(dancer)
    local chest = (pelvis + head) * 0.5
    local back = chest - cam
    back.z = 0
    back = back:GetNormalized()
    local pos = chest + back * 80 + Vector(0, 0, 40)
    near((r.pos - pos):Length(), 0, 1e-9, "80 units behind the chest as the camera sees it, 40 above")
    near((r.dir - (head - pos):GetNormalized()):Length(), 0, 1e-9, "aimed at the head")
    near(r.r, BASE * 0.8 * (pos:Distance(chest) / 150) ^ 2, 1e-9, "0.8 of the main light at the normal distance")
    check(r.cone == 35 and r.softness == 0.5 and r.radius == 30 and r.volumetric == 0, "its shaping, without haze")
    check(key().r == BASE, "the main light as set")
    -- Straight above: behind the character's own back.
    dancer.ang = Angle(0, 90, 0)
    cameraPath(dancer, Vector(500, 0, 400), chest)
    step()
    near((rim().pos - (chest + Vector(0, -80, 40))):Length(), 0, 1e-9, "behind its back")
    -- Off, and without a character.
    convars.mmd_vmd_npc_flashlight_rim = "0"
    step()
    check(count() == 1 and key() and not rim(), "rim 0 removes it")
    convars.mmd_vmd_npc_flashlight_rim = "0.8"
    step()
    check(count() == 2, "back")
    MMDVMDNPC.CameraAnimActive = false
    dancer.nw2.MMDVMDNPCDancing = false
    step()
    check(count() == 1 and not rim(), "no character, no rim light")
    dancer.nw2.MMDVMDNPCDancing = true
    cameraPath(dancer, cam, Vector(500, 0, 50))
    step()
    check(count() == 2, "back with the character")
    -- A refresh and switching off take both lights.
    dofile(file)
    check(count() == 0, "a refresh reclaims both")
    think = hooks["Think/MMDVMDNPCFlashlight"]
    step()
    check(count() == 2, "and makes both again")
    convars.mmd_vmd_npc_flashlight_enabled = "0"
    step()
    check(count() == 0, "off removes both")
    -- Vanilla: a second projected texture without shadows.
    RemixLight = nil
    convars.mmd_vmd_npc_flashlight_enabled = "1"
    step()
    local pts = livePT()
    check(#pts == 2, "two projected textures")
    check(pts[1].EnableShadows == true and pts[2].EnableShadows == false and pts[2].FOV == 70, "the rim casts no shadow")
elseif scenario == "presets" then
    for _, preset in ipairs(MMDVMDNPC.FlashlightPresets) do
        ran = {}
        check(MMDVMDNPC.ApplyFlashlightPreset(preset.id) == true, preset.id)
        check(#ran == #preset.values and #ran >= 5, preset.id .. " sets its values")
        for _, setting in ipairs(ran) do
            check(setting[1]:match("^mmd_vmd_npc_flashlight_") and convars[setting[1]] ~= nil, "an existing setting: " .. setting[1])
            check(not setting[1]:match("brightness") and not setting[1]:match("color") and not setting[1]:match("offset"),
                "a preset leaves brightness, colour and offsets alone")
        end
    end
    local ids = {}
    for _, preset in ipairs(MMDVMDNPC.FlashlightPresets) do ids[#ids + 1] = preset.id end
    check(table.concat(ids, ",") == "camera,uniform,spot,stage", "four presets in order")
    MMDVMDNPC.ApplyFlashlightPreset("stage")
    check(convars.mmd_vmd_npc_flashlight_uniform == "1" and convars.mmd_vmd_npc_flashlight_aim == "1"
        and convars.mmd_vmd_npc_flashlight_rim == "0.8", "the stage: uniform, aimed, with a rim light")
    MMDVMDNPC.ApplyFlashlightPreset("camera")
    check(convars.mmd_vmd_npc_flashlight_uniform == "0" and convars.mmd_vmd_npc_flashlight_aim == "0"
        and convars.mmd_vmd_npc_flashlight_rim == "0", "the camera light as it was")
    ran = {}
    check(MMDVMDNPC.ApplyFlashlightPreset("nope") == false and #ran == 0, "an unknown preset does nothing")
elseif scenario == "vanilla_uniform" then
    -- Without Remix the projected texture fades as 100 / d beyond 100 units: uniform lighting makes that up.
    RemixLight = nil
    classic()
    convars.mmd_vmd_npc_flashlight_uniform = "1"
    local dancer = Dancer(50, Vector(1000, 0, 0), 72)
    local chest = Vector(1000, 0, 50.4)
    for _, distance in ipairs({ 20, 300, 2000 }) do
        local cam = chest - Vector(distance, 0, 0)
        cameraPath(dancer, cam, chest)
        step()
        local d = distance + 45
        near(livePT()[1].Brightness, 0.28 * math.Clamp(math.max(d, 100) / 150, 1 / 64, 16), 1e-6, distance .. " units")
    end
else
    fail("unknown scenario")
end
io.write("PASS dance light " .. scenario .. "\n")
