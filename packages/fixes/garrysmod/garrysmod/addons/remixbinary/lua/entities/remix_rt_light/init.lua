AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    print("[remix_rt_light] Initialize (server)")
    self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    
    -- Hide the physics prop
    self:SetNoDraw(true)
    self:DrawShadow(false)
    
    -- Configure physics: no gravity by default, but not frozen
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(false) -- Disable gravity
        phys:Wake()
    end

    self.LightId = nil
    -- Default parameters; can be overridden via net message
    self:SetNWFloat("rtx_light_color_r", 255)
    self:SetNWFloat("rtx_light_color_g", 220)
    self:SetNWFloat("rtx_light_color_b", 180)
    self:SetNWFloat("rtx_light_radius", 20)
    self:SetNWFloat("rtx_light_brightness", 1)
    self:SetNWFloat("rtx_light_volumetric", 1)
    -- Light type is authoritative on server
    self:SetNWString("rtx_light_type", "sphere")
    -- Shaping defaults
    self:SetNWBool("rtx_light_shape_enabled", false)
    self:SetNWFloat("rtx_light_shape_cone", 90)
    self:SetNWFloat("rtx_light_shape_softness", 0.1)
    self:SetNWFloat("rtx_light_shape_focus", 1.0)
    -- Direction expressed as yaw/pitch
    self:SetNWFloat("rtx_light_dir_yaw", 0)
    self:SetNWFloat("rtx_light_dir_pitch", -90)
    -- Rect/Disk sizes
    self:SetNWFloat("rtx_light_xsize", 40)
    self:SetNWFloat("rtx_light_ysize", 40)
    self:SetNWFloat("rtx_light_xradius", 20)
    self:SetNWFloat("rtx_light_yradius", 20)
    -- Cylinder axis length
    self:SetNWFloat("rtx_light_axis_len", 40)
    -- Distant angular diameter
    self:SetNWFloat("rtx_light_distant_angle", 0.5)
    -- Bonemerge parameters
    self:SetNWBool("rtx_light_is_bonemerged", false)
    self:SetNWInt("rtx_light_parent_id", -1)
    self:SetNWInt("rtx_light_bone_id", -1)
    self:SetNWVector("rtx_light_offset_pos", Vector(0, 0, 0))
    self:SetNWAngle("rtx_light_offset_ang", Angle(0, 0, 0))
end

function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr.Hit then return end
    local classname = ClassName or "remix_rt_light"
    local ent = ents.Create(classname)
    if not IsValid(ent) then return end
    ent:SetPos(tr.HitPos + tr.HitNormal * 16)
    ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ent:Spawn()
    ent:Activate()
    return ent
end

local function vec_to_table(v) return { x = v.x, y = v.y, z = v.z } end

function ENT:CreateRemixLight()
    -- Server no longer creates Remix lights; client is responsible.
    -- This function is kept as a no-op for backward compatibility.
end

-- No server Think: it only scheduled itself for every tick. The client reads the light's position from the
-- entity itself and its settings from the networked values below.

-- The policy the spawn menu applies to a SENT, for every light a player makes outside it (review finding
-- 14): the six light tools and the spawn message's fallback (autorun/sv_rtx.lua). Each light is a Remix
-- light on every RTX client, so it counts against sbox_maxsents, and its creator, prop-protection owner,
-- cleanup and undo name the player.
function RemixRTLight.CanSpawn(ply)
    if not IsValid(ply) then return false end
    -- CheckLimit is sandbox's (it tells the player when the limit is reached); other gamemodes have none.
    return not ply.CheckLimit or ply:CheckLimit("sents")
end

function RemixRTLight.Claim(ply, ent, undoText)
    if not IsValid(ply) or not IsValid(ent) then return end
    if ply.AddCount then ply:AddCount("sents", ent) end
    ent:SetCreator(ply)
    if ent.CPPISetOwner then ent:CPPISetOwner(ply) end
    cleanup.Add(ply, "sents", ent)
    if undoText then
        undo.Create(undoText)
            undo.AddEntity(ent)
            undo.SetPlayer(ply)
        undo.Finish()
    end
end

-- A light for a player at a place, or nil when the limit refuses it.
function RemixRTLight.Spawn(ply, pos, ang, undoText)
    if not RemixRTLight.CanSpawn(ply) then return nil end
    local ent = ents.Create("remix_rt_light")
    if not IsValid(ent) then return nil end
    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()
    RemixRTLight.Claim(ply, ent, undoText)
    return ent
end

-- Writes the settings in `values` that are valid, each within its limits (shared.lua); a setting that is
-- missing, of the wrong kind or not a finite number is left as it is. `keys`, when given, names the only
-- settings this path may change.
function RemixRTLight.Apply(ent, values, keys)
    if not IsValid(ent) or not istable(values) then return end
    local function given(key) return values[key] ~= nil and (keys == nil or keys[key]) end

    if given("rtx_light_type") and isstring(values.rtx_light_type) then
        local lt = string.lower(values.rtx_light_type)
        if RemixRTLight.TYPES[lt] then ent:SetNWString("rtx_light_type", lt) end
    end
    for key in pairs(RemixRTLight.LIMITS) do
        local v = given(key) and RemixRTLight.Limit(key, values[key])
        if v then ent:SetNWFloat(key, v) end
    end
    for _, key in ipairs({ "rtx_light_shape_enabled", "rtx_light_is_bonemerged" }) do
        if given(key) then ent:SetNWBool(key, values[key] and true or false) end
    end
    for key in pairs(RemixRTLight.INT_LIMITS) do
        local v = given(key) and RemixRTLight.LimitInt(key, values[key])
        if v then ent:SetNWInt(key, v) end
    end
    for key in pairs(RemixRTLight.VECTOR_LIMITS) do
        local v = given(key) and RemixRTLight.LimitVector(key, values[key])
        if v then ent:SetNWVector(key, v) end
    end
    for key in pairs(RemixRTLight.ANGLE_LIMITS) do
        local v = given(key) and RemixRTLight.LimitAngle(key, values[key])
        if v then ent:SetNWAngle(key, v) end
    end
    if given("rtx_light_dome_tex") and isstring(values.rtx_light_dome_tex) and values.rtx_light_dome_tex ~= "" then
        ent:SetNWString("rtx_light_dome_tex", string.sub(values.rtx_light_dome_tex, 1, 256))
    end
end

-- Duplicator support: persist NWVar configuration
local function getNWTable(ent)
    return {
        rtx_light_type = ent:GetNWString("rtx_light_type", "sphere"),
        rtx_light_radius = ent:GetNWFloat("rtx_light_radius", 20),
        rtx_light_brightness = ent:GetNWFloat("rtx_light_brightness", 1),
        rtx_light_volumetric = ent:GetNWFloat("rtx_light_volumetric", 1),
        rtx_light_shape_enabled = ent:GetNWBool("rtx_light_shape_enabled", false),
        rtx_light_shape_cone = ent:GetNWFloat("rtx_light_shape_cone", 90),
        rtx_light_shape_softness = ent:GetNWFloat("rtx_light_shape_softness", 0.1),
        rtx_light_shape_focus = ent:GetNWFloat("rtx_light_shape_focus", 1.0),
        rtx_light_dir_yaw = ent:GetNWFloat("rtx_light_dir_yaw", 0),
        rtx_light_dir_pitch = ent:GetNWFloat("rtx_light_dir_pitch", -90),
        rtx_light_xsize = ent:GetNWFloat("rtx_light_xsize", 40),
        rtx_light_ysize = ent:GetNWFloat("rtx_light_ysize", 40),
        rtx_light_xradius = ent:GetNWFloat("rtx_light_xradius", 20),
        rtx_light_yradius = ent:GetNWFloat("rtx_light_yradius", 20),
        rtx_light_axis_len = ent:GetNWFloat("rtx_light_axis_len", 40),
        rtx_light_distant_angle = ent:GetNWFloat("rtx_light_distant_angle", 0.5),
        rtx_light_color_r = ent:GetNWFloat("rtx_light_color_r", 255),
        rtx_light_color_g = ent:GetNWFloat("rtx_light_color_g", 220),
        rtx_light_color_b = ent:GetNWFloat("rtx_light_color_b", 180),
        rtx_light_is_bonemerged = ent:GetNWBool("rtx_light_is_bonemerged", false),
        rtx_light_parent_id = ent:GetNWInt("rtx_light_parent_id", -1),
        rtx_light_bone_id = ent:GetNWInt("rtx_light_bone_id", -1),
        rtx_light_offset_pos = ent:GetNWVector("rtx_light_offset_pos", Vector(0, 0, 0)),
        rtx_light_offset_ang = ent:GetNWAngle("rtx_light_offset_ang", Angle(0, 0, 0)),
    }
end

function ENT:PreEntityCopy()
    local t = getNWTable(self)
    duplicator.StoreEntityModifier(self, "RemixRTLightData", t)
end

function ENT:PostEntityPaste(ply, ent, createdEntities)
    -- A dupe file holds whatever its author wrote: each setting within the light's limits.
    local mod = ent.EntityMods and ent.EntityMods["RemixRTLightData"]
    if mod then
        RemixRTLight.Apply(self, mod)
    end
    
    -- Ensure pasted entities also have physics configured correctly
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(false)
    end
    self:SetNoDraw(true)
    self:DrawShadow(false)
end


