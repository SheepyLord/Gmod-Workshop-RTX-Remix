-- Camera-following flashlight for the MMD VMD NPC addon.
--
-- The light is driven along the addon's current view:
--   1. the imported camera-path animation (or its debug preview),
--   2. the third-person self-playback camera (when not in free view),
--   3. otherwise the player's own eyes (optional).
--
-- Two render paths share that view:
--   * RTX-Remix build (the RTXFixesBinary module exposes the global `RemixLight`
--     table): a path-traced sphere spotlight is created/updated directly through
--     RemixLight.CreateSphere/UpdateSphere — the same proven pattern as the remix
--     binary's own rtx_flashlight. We do NOT rely on the binary's
--     ProjectedTexture() wrapper: it is silently disabled by archived convars
--     (rtx_lightupdater, rtx_projectedtexture_wrapper_enabled), and Remix discards
--     the raster lighting a ProjectedTexture produces, so nothing would render.
--   * Vanilla Garry's Mod (no RemixLight): a native ProjectedTexture spotlight.
--
-- Character lighting (ADR 0209), each part off by default so the light stays as it was:
--   * uniform lighting: the light's intensity follows its distance to the character
--     it lights (the inverse square for the Remix light), so the character stays
--     equally lit however near or far the camera is. The distance maths is
--     cl_light_gain.lua, a copy of the RTX fixes' flashlight's (ADR 0208);
--   * aim at the character: the light points at the part of the character the view
--     is on instead of straight along the view;
--   * a colour temperature, a rim light behind the character, and presets that set
--     these together.
-- The character is the one the camera path or the third-person dance view is about,
-- else the dancing character nearest the light's axis inside its cone; with none, the
-- light measures what it points at, as the RTX flashlight does.

if not CLIENT then return end

MMDVMDNPC = MMDVMDNPC or {}

-- Persistent settings (mirrors the remix flashlight's tunables) -------------------
CreateClientConVar("mmd_vmd_npc_flashlight_enabled", "0", true, false, "Enable the MMD camera-following flashlight")
CreateClientConVar("mmd_vmd_npc_flashlight_key", "0", true, false, "Key code that toggles the MMD flashlight")
CreateClientConVar("mmd_vmd_npc_flashlight_follow_eye", "1", true, false, "When no cinematic camera is active, keep the flashlight on the player's eyes")
CreateClientConVar("mmd_vmd_npc_flashlight_shadows", "1", true, false, "Cast dynamic shadows from the MMD flashlight (non-RTX)")
CreateClientConVar("mmd_vmd_npc_flashlight_brightness", "4", true, false, "MMD flashlight brightness")
CreateClientConVar("mmd_vmd_npc_flashlight_fov", "60", true, false, "MMD flashlight cone angle (degrees)")
CreateClientConVar("mmd_vmd_npc_flashlight_distance", "1200", true, false, "MMD flashlight throw distance (far Z)")
CreateClientConVar("mmd_vmd_npc_flashlight_nearz", "12", true, false, "MMD flashlight near Z")
CreateClientConVar("mmd_vmd_npc_flashlight_color_r", "255", true, false, "MMD flashlight red (0-255)")
CreateClientConVar("mmd_vmd_npc_flashlight_color_g", "255", true, false, "MMD flashlight green (0-255)")
CreateClientConVar("mmd_vmd_npc_flashlight_color_b", "255", true, false, "MMD flashlight blue (0-255)")
CreateClientConVar("mmd_vmd_npc_flashlight_offset_forward", "0", true, false, "MMD flashlight forward offset from the view")
CreateClientConVar("mmd_vmd_npc_flashlight_offset_right", "0", true, false, "MMD flashlight right offset from the view")
CreateClientConVar("mmd_vmd_npc_flashlight_offset_up", "0", true, false, "MMD flashlight up offset from the view")
-- RTX-Remix specific light shaping (ignored by the vanilla ProjectedTexture path).
CreateClientConVar("mmd_vmd_npc_flashlight_rtx_radius", "20", true, false, "RTX flashlight light sphere radius")
CreateClientConVar("mmd_vmd_npc_flashlight_rtx_softness", "0.45", true, false, "RTX flashlight cone edge softness (0-1)")
CreateClientConVar("mmd_vmd_npc_flashlight_rtx_volumetric", "0", true, false, "RTX flashlight volumetric intensity multiplier")
-- Character lighting (ADR 0209). The defaults keep the light as it was.
CreateClientConVar("mmd_vmd_npc_flashlight_uniform", "0", true, false, "Uniform lighting: the light follows its distance to the character so the character stays equally lit")
CreateClientConVar("mmd_vmd_npc_flashlight_uniform_strength", "1", true, false, "Uniform lighting: how much of the change with distance it makes up (0-1)")
CreateClientConVar("mmd_vmd_npc_flashlight_uniform_distance", "150", true, false, "Uniform lighting: the distance at which Brightness applies unchanged")
CreateClientConVar("mmd_vmd_npc_flashlight_uniform_max", "16", true, false, "Uniform lighting: the most it brightens the light for a far character")
CreateClientConVar("mmd_vmd_npc_flashlight_aim", "0", true, false, "Aim the MMD flashlight at the character instead of straight along the view")
CreateClientConVar("mmd_vmd_npc_flashlight_temperature", "0", true, false, "MMD flashlight colour temperature in kelvin, tinted by the RGB colour (0 = the RGB colour alone)")
CreateClientConVar("mmd_vmd_npc_flashlight_rim", "0", true, false, "Rim light behind the character, relative to Brightness at the normal distance (0 = off)")

local FLASHLIGHT_TEXTURE = "effects/flashlight001"
-- The remix flashlight's neutral brightness is radiance == color (scale 1.0 at its
-- brightness 1000). Our slider's default is 4, so divide by 4 to land in the same
-- place: brightness 4 -> radiance 255 per channel.
local RTX_BRIGHTNESS_DIVISOR = 4

-- The distance maths shared with the RTX fixes' flashlight (a copy of its file).
local Gain = include("mmd_vmd_npc/cl_light_gain.lua")
if not istable(Gain) then Gain = nil end

local UNIFORM_MIN_GAIN = 1 / 64
-- Seconds to ease the gain: it drops within a frame or two and climbs a little slower, so a
-- dancer swapping places with another does not flash. A camera cut sets it at once.
local UNIFORM_FALL, UNIFORM_RISE = 0.03, 0.12
-- Source's projected texture fades as 100 / distance beyond 100 units (its default
-- linear attenuation); a Remix sphere light with the square of the distance.
local PROJECTED_FALLOFF, PROJECTED_NEAR = 1, 100
local SCAN_INTERVAL = 0.25 -- seconds between looks for dancing characters in the beam
local TRACE_RING = 6 -- directions around the axis when no character is in the beam
local TRACE_WEIGHTS = { 2, 1, 1, 1, 1, 1, 1 }
-- The rim light sits this far behind and above the character's chest, as the camera
-- sees it, and points at its head.
local RIM_BACK, RIM_UP = 80, 40
local RIM_CONE, RIM_SOFTNESS, RIM_FOV = 35, 0.5, 70
local PELVIS_BONES = { "ValveBiped.Bip01_Pelvis", "Pelvis" }
local HEAD_BONES = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1", "Head", "head" }

local function convar_number(name, fallback)
    local cvar = GetConVar(name)
    if not cvar then return fallback or 0 end
    return tonumber(cvar:GetString()) or fallback or 0
end

local function convar_bool(name, fallback)
    local cvar = GetConVar(name)
    if not cvar then return fallback and true or false end
    return cvar:GetBool()
end

local function flashlight_enabled()
    return convar_bool("mmd_vmd_npc_flashlight_enabled", false)
end

-- RTXFixesBinary (RTX-Remix builds) exposes RemixLight; absent in vanilla GMod.
local function remix_available()
    return istable(RemixLight)
        and RemixLight.CreateSphere ~= nil
        and RemixLight.UpdateSphere ~= nil
end

-- The two lights: the main (key) light and the rim light. Light handles live on the
-- persistent MMDVMDNPC table, NOT as file-locals: a Lua auto-refresh re-executes this
-- file with fresh (nil) locals BEFORE the OnReloaded cleanup hook fires, which would
-- orphan a live RemixLight sphere as a frozen duplicate until map change. Table fields
-- survive re-execution, so a refreshed file can reclaim the previous execution's lights.
-- The rest is per-frame state (the reusable RTX tables, the vanilla path's dirty-check
-- caches): losing it on refresh is harmless, the next frame just re-applies.
local function remix_tables()
    local pos, dir, rad = { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }
    local shaping = { direction = dir, coneAngleDegrees = 0, coneSoftness = 0.2, focusExponent = 1.0 }
    return {
        pos = pos, dir = dir, rad = rad, shaping = shaping,
        sphere = { position = pos, radius = 20, shaping = shaping, volumetricRadianceScale = 0 },
        base = { hash = 0, radiance = rad, isDynamic = true, ignoreViewModel = true },
    }
end

local KEY = { idField = "FlashlightRemixLightId", ptField = "FlashlightProjected",
    hashName = "mmd_vmd_npc_flashlight_", remix = remix_tables() }
local RIM = { idField = "FlashlightRimLightId", ptField = "FlashlightRimProjected",
    hashName = "mmd_vmd_npc_flashlight_rim_", remix = remix_tables() }

for _, slot in ipairs({ KEY, RIM }) do
    if MMDVMDNPC[slot.idField] and istable(RemixLight) and RemixLight.DestroyLight then
        RemixLight.DestroyLight(MMDVMDNPC[slot.idField])
    end
    MMDVMDNPC[slot.idField] = nil
    if IsValid(MMDVMDNPC[slot.ptField]) then
        MMDVMDNPC[slot.ptField]:Remove()
    end
    MMDVMDNPC[slot.ptField] = nil
end

-- Uniform lighting's state: the gain now, and where the light was and pointed.
local uniform = {}

local function remix_hash(slot)
    local ply = LocalPlayer()
    local entIndex = IsValid(ply) and ply:EntIndex() or 0
    return tonumber(util.CRC(slot.hashName .. entIndex)) or 987654
end

local function destroy_projected(slot)
    if IsValid(MMDVMDNPC[slot.ptField]) then MMDVMDNPC[slot.ptField]:Remove() end
    MMDVMDNPC[slot.ptField] = nil
    slot.lastPos, slot.lastAng, slot.lastSig = nil, nil, nil
end

local function destroy_remix_light(slot)
    if MMDVMDNPC[slot.idField] and istable(RemixLight) and RemixLight.DestroyLight then
        RemixLight.DestroyLight(MMDVMDNPC[slot.idField])
    end
    MMDVMDNPC[slot.idField] = nil
end

local function destroy_slot(slot)
    destroy_projected(slot)
    destroy_remix_light(slot)
end

local function destroy_flashlight()
    destroy_slot(KEY)
    destroy_slot(RIM)
    uniform = {}
end

MMDVMDNPC.DestroyFlashlight = destroy_flashlight

-- Resolve the origin + angles the flashlight should follow this frame, or nil when
-- it should be hidden (disabled, or free view with eye-follow turned off).
local function resolve_view()
    -- 1. Imported camera-path animation, including the debug-window preview.
    if MMDVMDNPC.CameraAnimActive
        or (MMDVMDNPC.CameraDebugPreviewRenderable and MMDVMDNPC.CameraDebugPreviewRenderable()) then
        if isvector(MMDVMDNPC.CameraAnimViewOrigin) and isangle(MMDVMDNPC.CameraAnimViewAngles) then
            return MMDVMDNPC.CameraAnimViewOrigin, MMDVMDNPC.CameraAnimViewAngles
        end
    end

    -- 2. Third-person self-playback camera (not first-person / free view).
    if MMDVMDNPC.SelfThirdPersonActive
        and isvector(MMDVMDNPC.SelfThirdPersonViewOrigin)
        and isangle(MMDVMDNPC.SelfThirdPersonViewAngles) then
        return MMDVMDNPC.SelfThirdPersonViewOrigin, MMDVMDNPC.SelfThirdPersonViewAngles
    end

    -- 3. Free / first-person view: follow the player's eyes when allowed.
    if convar_bool("mmd_vmd_npc_flashlight_follow_eye", true) then
        local ply = LocalPlayer()
        if IsValid(ply) then
            return ply:EyePos(), ply:EyeAngles()
        end
    end

    return nil
end

-- The character -----------------------------------------------------------------

-- The character the view is about: the debug preview's or the camera path's anchor
-- (the dancer the path is authored around), or the self playback's dancer in its
-- third-person view. The same order as the views in resolve_view.
local function framed_character()
    if MMDVMDNPC.CameraDebugPreviewRenderable and MMDVMDNPC.CameraDebugPreviewRenderable()
        and MMDVMDNPC.CameraDebugAnchor then
        local anchor = MMDVMDNPC.CameraDebugAnchor()
        if IsValid(anchor) then return anchor end
    end
    if MMDVMDNPC.CameraAnimActive and MMDVMDNPC.CameraAnimEntIndex then
        local anchor = Entity(MMDVMDNPC.CameraAnimEntIndex)
        if IsValid(anchor) then return anchor end
    end
    if MMDVMDNPC.SelfThirdPersonActive and IsValid(MMDVMDNPC.SelfPlaybackCameraEnt) then
        return MMDVMDNPC.SelfPlaybackCameraEnt
    end
    return nil
end

-- Dancing: posed by this client (LocalPlaybacks) or by the server (the networked flag).
local function dancing(ent)
    if not IsValid(ent) or (ent.IsDormant and ent:IsDormant()) then return false end
    if MMDVMDNPC.LocalPlaybacks and MMDVMDNPC.LocalPlaybacks[ent] then return true end
    return ent.GetNW2Bool ~= nil and ent:GetNW2Bool("MMDVMDNPCDancing", false) == true
end

-- Bone ids per entity and model (a re-import can change the model under the entity).
local function body_bones(ent)
    local model = ent.GetModel and ent:GetModel() or ""
    local cache = ent.MMDVMDNPCLightBones
    if not cache or cache.model ~= model then
        cache = { model = model, pelvis = false, head = false }
        if ent.LookupBone then
            for _, name in ipairs(PELVIS_BONES) do
                local id = ent:LookupBone(name)
                if id then cache.pelvis = id break end
            end
            for _, name in ipairs(HEAD_BONES) do
                local id = ent:LookupBone(name)
                if id then cache.head = id break end
            end
        end
        ent.MMDVMDNPCLightBones = cache
    end
    return cache
end

local function bone_position(ent, id)
    if not id or not ent.GetBonePosition then return nil end
    local pos = ent:GetBonePosition(id)
    return isvector(pos) and pos or nil
end

-- The character's body as its pelvis and head (the dance moves those bones) and its
-- feet, about as far below the pelvis as the head is above it; from its bounds when the
-- model has no such bones.
local function body_of(ent)
    local bones = body_bones(ent)
    local pelvis, head = bone_position(ent, bones.pelvis), bone_position(ent, bones.head)
    if not pelvis or not head or pelvis:DistToSqr(head) < 1 then
        local base = ent:GetPos()
        local height = 64
        local maxs = ent.OBBMaxs and ent:OBBMaxs()
        if isvector(maxs) and maxs.z > 8 then height = maxs.z end
        pelvis = base + Vector(0, 0, height * 0.5)
        head = base + Vector(0, 0, height * 0.92)
    end
    return { ent = ent, pelvis = pelvis, head = head, feet = pelvis + (pelvis - head) }
end

-- The point of segment a-b nearest the line through origin along dir (a unit vector):
-- where on the body the light's axis passes.
local function nearest_on_segment(a, b, origin, dir)
    local u = b - a
    local uu = u:Dot(u)
    if uu < 1e-6 then return a end
    local w = a - origin
    local ud, uw, dw = u:Dot(dir), u:Dot(w), dir:Dot(w)
    local denom = uu - ud * ud
    local s = 0.5 -- the axis runs along the body: its middle
    if denom > 1e-6 * uu then s = (ud * dw - uw) / denom end
    return a + u * math.Clamp(s, 0, 1)
end

-- Dancing characters this client knows of, and those a periodic look into the beam found.
local scanned, scanAt = {}, -math.huge

local function candidates(origin, dir, coneCos, reach)
    local now = RealTime()
    if now - scanAt >= SCAN_INTERVAL then
        scanAt = now
        scanned = {}
        if ents and ents.FindInCone then
            for _, ent in ipairs(ents.FindInCone(origin, dir, reach, coneCos) or {}) do
                if dancing(ent) then scanned[#scanned + 1] = ent end
            end
        end
    end
    local list, seen = {}, {}
    local function add(ent)
        if IsValid(ent) and not seen[ent] then
            seen[ent] = true
            list[#list + 1] = ent
        end
    end
    for ent in pairs(MMDVMDNPC.LocalPlaybacks or {}) do add(ent) end
    for entIndex in pairs(MMDVMDNPC.CameraTracks or {}) do add(Entity(entIndex)) end
    local assigned = MMDVMDNPC.AssignedActors
    if istable(assigned) and istable(assigned.order) then
        for _, ent in ipairs(assigned.order) do add(ent) end
    end
    for _, ent in ipairs(scanned) do add(ent) end
    return list
end

-- The character the light is for: the one the view is about, else the dancing character
-- whose body passes nearest the light's axis, inside its cone and throw distance.
local function find_subject(origin, dir, fov, reach)
    local framed = framed_character()
    if framed then return body_of(framed) end
    local coneCos = math.cos(math.rad(math.min(89, fov * 0.5 + 15)))
    local best, bestCos = nil, coneCos
    for _, ent in ipairs(candidates(origin, dir, coneCos, reach)) do
        if dancing(ent) then
            local body = body_of(ent)
            local to = nearest_on_segment(body.feet, body.head, origin, dir) - origin
            local d = to:Length()
            if d > 1 and d <= reach then
                local c = to:Dot(dir) / d
                if c > bestCos then best, bestCos = body, c end
            end
        end
    end
    return best
end

-- With no character in the beam: what the light points at, as the RTX flashlight measures
-- it. Seven traces start at the camera (the light may sit behind it, maybe in a wall) and
-- are measured from the light; near hits count most. Nil when none hit anything.
local _trace_out, _trace_filter = {}, {}
local _trace = { mask = MASK_OPAQUE_AND_NPCS, filter = _trace_filter, output = _trace_out }
local _samples = {}

local function measure_beam(cameraPos, origin, dir, fov, falloff, near, reach)
    local axis = dir:Angle()
    local right, up = axis:Right(), axis:Up()
    _trace.start = cameraPos
    -- Not the player, nor the vehicle they sit in (and the car a seat is parented to).
    local ply = LocalPlayer()
    _trace_filter[1], _trace_filter[2], _trace_filter[3] = ply, nil, nil
    if IsValid(ply) and ply.InVehicle and ply:InVehicle() then
        local vehicle = ply:GetVehicle()
        if IsValid(vehicle) then
            _trace_filter[2] = vehicle
            local parent = vehicle:GetParent()
            if IsValid(parent) then _trace_filter[3] = parent end
        end
    end
    local ring = Gain.Ring(math.Clamp(fov * 0.25, 2, 15), TRACE_RING)
    local hits = 0
    for i, c in ipairs(ring) do
        local direction = dir * c[1] + right * c[2] + up * c[3]
        _trace.endpos = cameraPos + direction * reach
        util.TraceLine(_trace)
        if _trace_out.StartSolid then
            _samples[i] = false
        else
            _samples[i] = _trace_out.HitPos:Distance(origin)
            if _trace_out.Hit then hits = hits + 1 end
        end
    end
    if hits == 0 then return nil end
    return Gain.EffectiveDistance(_samples, #ring, TRACE_WEIGHTS, falloff, near, reach)
end

-- Uniform lighting's gain this frame: from the distance to where the light's axis passes
-- the character's body, or to what the light points at; eased, and set at once when the
-- view jumps (a camera cut) or the character changes. Nothing to measure: it holds.
local function uniform_gain(subject, cameraPos, origin, dir, fov, falloff, near, reach)
    local reference = math.max(1, convar_number("mmd_vmd_npc_flashlight_uniform_distance", 150))
    local strength = math.Clamp(convar_number("mmd_vmd_npc_flashlight_uniform_strength", 1), 0, 1)
    local maxGain = math.max(1, convar_number("mmd_vmd_npc_flashlight_uniform_max", 16))
    local distance
    if subject then
        distance = origin:Distance(nearest_on_segment(subject.feet, subject.head, origin, dir))
    else
        distance = measure_beam(cameraPos, origin, dir, fov, falloff, near, reach)
    end
    local s = uniform
    local who = subject and subject.ent or false
    if distance then
        local target = Gain.Target(distance, reference, strength, falloff, near, UNIFORM_MIN_GAIN, maxGain)
        local jumped = s.gain == nil or s.who ~= who or Gain.Jumped(
            math.sqrt((origin.x - s.x) ^ 2 + (origin.y - s.y) ^ 2 + (origin.z - s.z) ^ 2),
            dir.x * s.dx + dir.y * s.dy + dir.z * s.dz, distance)
        s.gain = jumped and target or Gain.Smooth(s.gain, target, RealFrameTime(), UNIFORM_FALL, UNIFORM_RISE)
        s.distance = distance
    end
    s.who = who
    s.x, s.y, s.z, s.dx, s.dy, s.dz = origin.x, origin.y, origin.z, dir.x, dir.y, dir.z
    return s.gain or 1
end

-- The colour: the RGB setting, times the colour temperature's when one is set (at the
-- luminance of white, so a warmer light is no darker).
local function light_color()
    local r = math.Clamp(math.floor(convar_number("mmd_vmd_npc_flashlight_color_r", 255)), 0, 255)
    local g = math.Clamp(math.floor(convar_number("mmd_vmd_npc_flashlight_color_g", 255)), 0, 255)
    local b = math.Clamp(math.floor(convar_number("mmd_vmd_npc_flashlight_color_b", 255)), 0, 255)
    local kelvin = convar_number("mmd_vmd_npc_flashlight_temperature", 0)
    if Gain and kelvin > 0 then
        local kr, kg, kb = Gain.Kelvin(kelvin)
        r, g, b = r * kr, g * kg, b * kb
    end
    return r, g, b
end

-- Rendering ---------------------------------------------------------------------

-- RTX-Remix path: drive a RemixLight sphere spotlight directly. Updated every
-- frame unconditionally — the light is isDynamic and that is the proven pattern
-- (both the remix flashlight and its ProjectedTexture wrapper update per frame).
-- coneHalf is Remix shaping's HALF angle (center to edge); r, g, b the radiance.
local function apply_remix(slot, origin, dir, coneHalf, softness, radius, volumetric, r, g, b)
    local t = slot.remix
    t.rad.x, t.rad.y, t.rad.z = r, g, b
    t.pos.x, t.pos.y, t.pos.z = origin.x, origin.y, origin.z
    t.dir.x, t.dir.y, t.dir.z = dir.x, dir.y, dir.z
    t.shaping.coneAngleDegrees = coneHalf
    t.shaping.coneSoftness = softness
    t.sphere.radius = radius
    t.sphere.volumetricRadianceScale = volumetric
    t.base.hash = remix_hash(slot)

    local id = MMDVMDNPC[slot.idField]
    if not id then
        local ply = LocalPlayer()
        id = RemixLight.CreateSphere(t.base, t.sphere, IsValid(ply) and ply:EntIndex() or 0)
        if id and id ~= 0 then
            MMDVMDNPC[slot.idField] = id
        end
        return
    end

    RemixLight.UpdateSphere(t.base, t.sphere, id)
end

-- Vanilla path: native ProjectedTexture spotlight. A colour brighter than 255 (a colour
-- temperature's) is carried by the brightness instead.
local function apply_projected(slot, origin, ang, fov, brightness, r, g, b, shadows)
    local farz = math.max(1, convar_number("mmd_vmd_npc_flashlight_distance", 1200))
    local nearz = math.Clamp(convar_number("mmd_vmd_npc_flashlight_nearz", 12), 1, farz - 1)
    local top = math.max(r, g, b)
    if top > 255 then
        brightness = brightness * top / 255
        r, g, b = r * 255 / top, g * 255 / top, b * 255 / top
    end
    r, g, b = math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)

    -- Signature of everything except pos/ang; combined with a position/angle delta
    -- it lets us skip ProjectedTexture:Update() (a shadow-map rebuild) when nothing
    -- actually changed, e.g. a paused dance or a stationary first-person view.
    local sig = table.concat({ fov, farz, nearz, r, g, b, brightness, shadows and 1 or 0 }, ":")

    local projected = MMDVMDNPC[slot.ptField]
    if not IsValid(projected) then
        projected = ProjectedTexture()
        if not IsValid(projected) then
            MMDVMDNPC[slot.ptField] = nil
            return
        end
        projected:SetTexture(FLASHLIGHT_TEXTURE)
        MMDVMDNPC[slot.ptField] = projected
        slot.lastPos, slot.lastAng, slot.lastSig = nil, nil, nil
    end

    local lastPos, lastAng = slot.lastPos, slot.lastAng
    local moved = (not lastPos) or (not lastAng)
        or lastPos:DistToSqr(origin) > 0.01
        or math.abs(lastAng.p - ang.p) > 0.01
        or math.abs(lastAng.y - ang.y) > 0.01
        or math.abs(lastAng.r - ang.r) > 0.01
    if not moved and sig == slot.lastSig then
        return
    end

    projected:SetPos(origin)
    projected:SetAngles(ang)
    projected:SetFOV(fov)
    projected:SetFarZ(farz)
    projected:SetNearZ(nearz)
    projected:SetColor(Color(r, g, b))
    projected:SetBrightness(brightness)
    projected:SetEnableShadows(shadows)
    projected:Update()

    slot.lastPos = origin
    slot.lastAng = Angle(ang.p, ang.y, ang.r)
    slot.lastSig = sig
end

-- The rim light: behind the character as the camera sees it and above its chest, aimed at
-- its head, lighting it at `ratio` of what the main light gives at the normal distance.
local function apply_rim(subject, cameraPos, ratio, brightness, r, g, b, remix, falloff, near)
    local chest = (subject.pelvis + subject.head) * 0.5
    local back = chest - cameraPos
    back.z = 0
    if back:LengthSqr() < 1 then
        -- Straight above or below: behind the character's own back.
        back = subject.ent:GetAngles():Forward() * -1
        back.z = 0
        if back:LengthSqr() < 1e-6 then back = Vector(1, 0, 0) end
    end
    back = back:GetNormalized()
    local pos = chest + back * RIM_BACK + Vector(0, 0, RIM_UP)
    local dir = (subject.head - pos):GetNormalized()
    local reference = math.max(1, convar_number("mmd_vmd_npc_flashlight_uniform_distance", 150))
    local gain = ratio * Gain.Target(pos:Distance(chest), reference, 1, falloff, near, UNIFORM_MIN_GAIN, 64)
    if remix then
        if MMDVMDNPC[RIM.ptField] then destroy_projected(RIM) end
        local scale = brightness / RTX_BRIGHTNESS_DIVISOR * gain
        local radius = math.Clamp(convar_number("mmd_vmd_npc_flashlight_rtx_radius", 20), 1, 200)
        apply_remix(RIM, pos, dir, RIM_CONE, RIM_SOFTNESS, radius, 0, r * scale, g * scale, b * scale)
    else
        apply_projected(RIM, pos, dir:Angle(), RIM_FOV, brightness * gain, r, g, b, false)
    end
end

local function apply_flashlight()
    local cameraPos, ang = resolve_view()
    if not cameraPos or not ang then
        destroy_flashlight()
        return
    end

    local origin = cameraPos
    local offForward = convar_number("mmd_vmd_npc_flashlight_offset_forward", 0)
    local offRight = convar_number("mmd_vmd_npc_flashlight_offset_right", 0)
    local offUp = convar_number("mmd_vmd_npc_flashlight_offset_up", 0)
    if offForward ~= 0 or offRight ~= 0 or offUp ~= 0 then
        origin = origin + ang:Forward() * offForward + ang:Right() * offRight + ang:Up() * offUp
    end

    local fov = math.Clamp(convar_number("mmd_vmd_npc_flashlight_fov", 60), 1, 179)
    local baseBrightness = math.max(0, convar_number("mmd_vmd_npc_flashlight_brightness", 4))
    local brightness = baseBrightness
    local r, g, b = light_color()
    local remix = remix_available()
    local radius = math.Clamp(convar_number("mmd_vmd_npc_flashlight_rtx_radius", 20), 1, 200)
    -- How this light fades with distance, and closer than what nothing gets brighter.
    local falloff, near = 2, radius
    if not remix then falloff, near = PROJECTED_FALLOFF, PROJECTED_NEAR end

    -- Character lighting (ADR 0209): only looked for when an option needs it.
    local useUniform = Gain ~= nil and convar_bool("mmd_vmd_npc_flashlight_uniform", false)
    local useAim = Gain ~= nil and convar_bool("mmd_vmd_npc_flashlight_aim", false)
    local rimRatio = Gain ~= nil and math.max(0, convar_number("mmd_vmd_npc_flashlight_rim", 0)) or 0
    local forward = ang:Forward()
    local dir, lightAng = forward, ang
    local subject
    local gain = 1
    if useUniform or useAim or rimRatio > 0 then
        local reach = math.Clamp(convar_number("mmd_vmd_npc_flashlight_distance", 1200), 256, 16384)
        subject = find_subject(origin, forward, fov, reach)
        if useAim and subject then
            -- The part of the body the view is on: from the pelvis up, so it is never the feet.
            local to = nearest_on_segment(subject.pelvis, subject.head, cameraPos, forward) - origin
            if to:LengthSqr() > 1 then
                dir = to:GetNormalized()
                lightAng = dir:Angle()
            end
        end
        if useUniform then
            gain = uniform_gain(subject, cameraPos, origin, dir, fov, falloff, near, reach)
            brightness = brightness * gain
        end
    end
    if not useUniform then uniform = {} end

    if remix then
        -- Never keep a ProjectedTexture alive in the RTX build: Remix discards its
        -- raster lighting, and the binary's PT wrapper could bridge it into a
        -- SECOND remix light on setups where that wrapper is enabled.
        if MMDVMDNPC[KEY.ptField] then destroy_projected(KEY) end
        local scale = brightness / RTX_BRIGHTNESS_DIVISOR
        -- Remix shaping uses the HALF angle (center to edge); ProjectedTexture FOV is
        -- the full cone, so halve it (the remix PT wrapper does the same). A uniform
        -- lighting boost lights the far character, not the haze beside the camera: the
        -- haze stays at its set level (dimming dims it too).
        apply_remix(KEY, origin, dir,
            math.Clamp(fov * 0.5, 1, 89),
            math.Clamp(convar_number("mmd_vmd_npc_flashlight_rtx_softness", 0.45), 0, 1),
            radius,
            math.max(0, convar_number("mmd_vmd_npc_flashlight_rtx_volumetric", 0)) / math.max(1, gain),
            r * scale, g * scale, b * scale)
    else
        apply_projected(KEY, origin, lightAng, fov, brightness, r, g, b,
            convar_bool("mmd_vmd_npc_flashlight_shadows", true))
    end

    if rimRatio > 0 and subject then
        apply_rim(subject, cameraPos, rimRatio, baseBrightness, r, g, b, remix, falloff, near)
    elseif MMDVMDNPC[RIM.idField] or MMDVMDNPC[RIM.ptField] then
        destroy_slot(RIM)
    end
end

-- Presets (ADR 0209): a look in one choice. Brightness, colour and offsets stay the
-- player's; the menu offers these by their labels.
MMDVMDNPC.FlashlightPresets = {
    { id = "camera", label = "mmd_vmd_npc.lighting.preset_camera", values = {
        { "mmd_vmd_npc_flashlight_uniform", "0" }, { "mmd_vmd_npc_flashlight_aim", "0" },
        { "mmd_vmd_npc_flashlight_rim", "0" }, { "mmd_vmd_npc_flashlight_fov", "100" },
        { "mmd_vmd_npc_flashlight_rtx_softness", "0.45" } } },
    { id = "uniform", label = "mmd_vmd_npc.lighting.preset_uniform", values = {
        { "mmd_vmd_npc_flashlight_uniform", "1" }, { "mmd_vmd_npc_flashlight_uniform_strength", "1" },
        { "mmd_vmd_npc_flashlight_aim", "0" }, { "mmd_vmd_npc_flashlight_rim", "0" },
        { "mmd_vmd_npc_flashlight_fov", "100" }, { "mmd_vmd_npc_flashlight_rtx_softness", "0.45" } } },
    { id = "spot", label = "mmd_vmd_npc.lighting.preset_spot", values = {
        { "mmd_vmd_npc_flashlight_uniform", "1" }, { "mmd_vmd_npc_flashlight_uniform_strength", "1" },
        { "mmd_vmd_npc_flashlight_aim", "1" }, { "mmd_vmd_npc_flashlight_rim", "0" },
        { "mmd_vmd_npc_flashlight_fov", "40" }, { "mmd_vmd_npc_flashlight_rtx_softness", "0.2" } } },
    { id = "stage", label = "mmd_vmd_npc.lighting.preset_stage", values = {
        { "mmd_vmd_npc_flashlight_uniform", "1" }, { "mmd_vmd_npc_flashlight_uniform_strength", "1" },
        { "mmd_vmd_npc_flashlight_aim", "1" }, { "mmd_vmd_npc_flashlight_rim", "0.8" },
        { "mmd_vmd_npc_flashlight_fov", "70" }, { "mmd_vmd_npc_flashlight_rtx_softness", "0.45" } } },
}

function MMDVMDNPC.ApplyFlashlightPreset(id)
    for _, preset in ipairs(MMDVMDNPC.FlashlightPresets) do
        if preset.id == id then
            for _, setting in ipairs(preset.values) do
                RunConsoleCommand(setting[1], setting[2])
            end
            return true
        end
    end
    return false
end

-- Hotkey toggle. input.WasKeyPressed only fires inside Move hooks, so from Think we
-- edge-detect the held state ourselves (same convention as the camera hotkey).
local hotkeyWasDown = false

hook.Add("Think", "MMDVMDNPCFlashlight", function()
    local key = math.floor(convar_number("mmd_vmd_npc_flashlight_key", 0))
    if key > 0 then
        local down
        if MOUSE_FIRST and key >= MOUSE_FIRST then
            down = input.IsMouseDown and input.IsMouseDown(key) or false
        else
            down = input.IsKeyDown and input.IsKeyDown(key) or false
        end

        local suppressed = gui.IsGameUIVisible()
            or (vgui and vgui.CursorVisible and vgui.CursorVisible())
            or (vgui and vgui.GetKeyboardFocus and IsValid(vgui.GetKeyboardFocus()))
        if not suppressed then
            local ply = LocalPlayer()
            suppressed = IsValid(ply) and ply.IsTyping and ply:IsTyping() or false
        end

        if down and not hotkeyWasDown and not suppressed then
            RunConsoleCommand("mmd_vmd_npc_flashlight_enabled", flashlight_enabled() and "0" or "1")
        end
        hotkeyWasDown = down
    else
        hotkeyWasDown = false
    end

    if not flashlight_enabled() then
        if MMDVMDNPC[KEY.ptField] or MMDVMDNPC[KEY.idField] or MMDVMDNPC[RIM.ptField] or MMDVMDNPC[RIM.idField] then
            destroy_flashlight()
        end
        return
    end

    apply_flashlight()
end)

concommand.Add("mmd_vmd_npc_flashlight_toggle", function()
    RunConsoleCommand("mmd_vmd_npc_flashlight_enabled", flashlight_enabled() and "0" or "1")
end)

-- Free the light on map change / lua refresh so it never leaks.
hook.Add("ShutDown", "MMDVMDNPCFlashlightCleanup", destroy_flashlight)
hook.Add("OnReloaded", "MMDVMDNPCFlashlightCleanup", destroy_flashlight)
