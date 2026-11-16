-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = NP("Remix RT Light (Sphere)")
ENT.Author = "RTX Remixed"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.Category = "RTX Remix"
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

-- Light type: "sphere", "rect", "disk", "distant", "cylinder"
ENT.LightType = ENT.LightType or "sphere"

-- The light's settings within the limits every path that writes or reads them uses (review findings 13
-- and 14): the six light tools, the editor's apply message (autorun/sv_rtx.lua), dupes (init.lua) and
-- every client's Remix light (cl_init.lua). A tool's convars, a dupe file and a net message hold whatever
-- their sender put there, and NaN passes math.Clamp, math.max and every comparison, so a value must be a
-- finite number before it is limited.
RemixRTLight = RemixRTLight or {}

RemixRTLight.TYPES = { sphere = true, rect = true, disk = true, cylinder = true, distant = true, dome = true }

-- [setting] = { lowest, highest, default }: the widest range a tool or the editor offers (their sliders
-- reach 2000 for the radius and the shape sizes) and the value a new light starts with.
RemixRTLight.LIMITS = {
    rtx_light_radius = { 1, 2000, 20 },
    rtx_light_brightness = { 0, 10000, 1 },
    rtx_light_volumetric = { 0, 5, 1 },
    rtx_light_shape_cone = { 0, 180, 90 },
    rtx_light_shape_softness = { 0, 1, 0.1 },
    rtx_light_shape_focus = { 0, 10, 1 },
    rtx_light_xsize = { 1, 2000, 40 },
    rtx_light_ysize = { 1, 2000, 40 },
    rtx_light_xradius = { 1, 2000, 20 },
    rtx_light_yradius = { 1, 2000, 20 },
    rtx_light_axis_len = { 1, 2000, 40 },
    rtx_light_distant_angle = { 0, 10, 0.5 },
    rtx_light_color_r = { 0, 255, 255 },
    rtx_light_color_g = { 0, 255, 220 },
    rtx_light_color_b = { 0, 255, 180 },
    rtx_light_dir_yaw = { -360, 360, 0 },
    rtx_light_dir_pitch = { -360, 360, -90 },
}
RemixRTLight.VECTOR_LIMITS = {
    rtx_light_offset_pos = { -500, 500 },
    rtx_light_col = { 0, 10000 },
}
RemixRTLight.ANGLE_LIMITS = {
    rtx_light_offset_ang = { -360, 360 },
}
RemixRTLight.INT_LIMITS = {
    rtx_light_parent_id = { -1, 8191 },
    rtx_light_bone_id = { -1, 255 },
}
-- What the editor's apply message may change: the settings it had before the limits were shared.
RemixRTLight.EDITOR_KEYS = {
    rtx_light_type = true, rtx_light_radius = true, rtx_light_brightness = true, rtx_light_volumetric = true,
    rtx_light_shape_enabled = true, rtx_light_shape_cone = true, rtx_light_shape_softness = true,
    rtx_light_shape_focus = true, rtx_light_xsize = true, rtx_light_ysize = true, rtx_light_xradius = true,
    rtx_light_yradius = true, rtx_light_axis_len = true, rtx_light_distant_angle = true,
    rtx_light_dome_tex = true, rtx_light_col = true, rtx_light_color_r = true, rtx_light_color_g = true,
    rtx_light_color_b = true,
}

function RemixRTLight.Finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, limit)
    if value < limit[1] then return limit[1] end
    if value > limit[2] then return limit[2] end
    return value
end

-- A setting within its limits, or nil for a value that is not a finite number.
function RemixRTLight.Limit(key, value)
    local limit = RemixRTLight.LIMITS[key]
    if not limit or not RemixRTLight.Finite(value) then return nil end
    return clamp(value, limit)
end

-- Three finite numbers from a Vector, an Angle or a table with those fields (a dupe or a net message
-- may hold numbers as strings), or nil.
local function three(value, a, b, c)
    if not (istable(value) or isvector(value) or isangle(value)) then return nil end
    local x, y, z = tonumber(value[a]), tonumber(value[b]), tonumber(value[c])
    if not (RemixRTLight.Finite(x) and RemixRTLight.Finite(y) and RemixRTLight.Finite(z)) then return nil end
    return x, y, z
end

function RemixRTLight.LimitVector(key, value)
    local limit = RemixRTLight.VECTOR_LIMITS[key]
    local x, y, z = three(value, "x", "y", "z")
    if not limit or not x then return nil end
    return Vector(clamp(x, limit), clamp(y, limit), clamp(z, limit))
end

function RemixRTLight.LimitAngle(key, value)
    local limit = RemixRTLight.ANGLE_LIMITS[key]
    local p, y, r = three(value, "p", "y", "r")
    if not limit or not p then return nil end
    return Angle(clamp(p, limit), clamp(y, limit), clamp(r, limit))
end

function RemixRTLight.LimitInt(key, value)
    local limit = RemixRTLight.INT_LIMITS[key]
    if not limit or not RemixRTLight.Finite(value) then return nil end
    return clamp(math.floor(value), limit)
end

-- What a light's networked setting says, within its limits: the default for one that is missing or broken.
function RemixRTLight.Get(ent, key)
    local limit = RemixRTLight.LIMITS[key]
    return RemixRTLight.Limit(key, ent:GetNWFloat(key, limit[3])) or limit[3]
end

function RemixRTLight.GetVector(ent, key, fallback)
    return RemixRTLight.LimitVector(key, ent:GetNWVector(key, Vector(fallback, fallback, fallback)))
        or Vector(fallback, fallback, fallback)
end

function RemixRTLight.GetAngle(ent, key)
    return RemixRTLight.LimitAngle(key, ent:GetNWAngle(key, Angle(0, 0, 0))) or Angle(0, 0, 0)
end
