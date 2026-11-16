-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = NP("Sky Editor")
ENT.Author = "RTX Remixed"
ENT.Spawnable = true
ENT.AdminSpawnable = true
-- The first sky editor drives every RTX player's sky, and its apply message is for admins only: so is
-- placing one (the spawn menu and the stock duplicator refuse an AdminOnly class to other players, and a
-- pasted one checks again in PostEntityPaste; review finding 22).
ENT.AdminOnly = true
ENT.Category = "RTX Remix"
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

-- The sky's values within the limits every path that writes or reads them uses: the editor's apply message
-- (autorun/sv_rtx.lua), dupes (init.lua) and every client's sky (cl_init.lua). NaN passes math.Clamp and
-- every comparison, so a value must be a finite number before it is limited.
RemixSkyEditor = RemixSkyEditor or {}

-- [value] = { lowest, highest, default }
RemixSkyEditor.LIMITS = {
    sky_sun_intensity = { 0, 100, 1.0 },
    sky_sun_size = { 0, 10, 0.545 },
    sky_illum_r = { 0, 100, 20 },
    sky_illum_g = { 0, 100, 20 },
    sky_illum_b = { 0, 100, 20 },
    sky_air_density = { 0, 100, 1.0 },
    sky_dust_density = { 0, 100, 1.0 },
    sky_ozone_density = { 0, 100, 1.0 },
    sky_altitude = { 0, 100000, 100 },
    sky_planet_radius = { 1000, 10000, 6371 },
    sky_atmo_thickness = { 10, 500, 100 },
    sky_mie_anisotropy = { -1, 1, 0.97 },
    sky_rayleigh_r = { 0, 0.1, 0.0058 },
    sky_rayleigh_g = { 0, 0.1, 0.0135 },
    sky_rayleigh_b = { 0, 0.1, 0.0331 },
    sky_mie_r = { 0, 0.1, 0.003996 },
    sky_mie_g = { 0, 0.1, 0.003996 },
    sky_mie_b = { 0, 0.1, 0.003996 },
    sky_ozone_r = { 0, 0.01, 0.00204 },
    sky_ozone_g = { 0, 0.01, 0.00497 },
    sky_ozone_b = { 0, 0.01, 0.000214 },
    sky_ozone_alt = { 0, 50, 25 },
    sky_ozone_width = { 1, 30, 15 },
}

function RemixSkyEditor.Finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A value within its limits, or nil for one that is not a finite number.
function RemixSkyEditor.Limit(key, value)
    local limit = RemixSkyEditor.LIMITS[key]
    if not limit or not RemixSkyEditor.Finite(value) then return nil end
    if value < limit[1] then return limit[1] end
    if value > limit[2] then return limit[2] end
    return value
end

-- What the editor's networked value says, within its limits: the default for one that is missing or broken.
function RemixSkyEditor.Get(ent, key)
    local limit = RemixSkyEditor.LIMITS[key]
    return RemixSkyEditor.Limit(key, ent:GetNWFloat(key, limit[3])) or limit[3]
end
