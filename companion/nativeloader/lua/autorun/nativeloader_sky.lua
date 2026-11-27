-- The sky in RTX sessions (ADR 0031, ADR 0032). The runtime has a physical sky (rtx.skyMode 1:
-- Hillaire scattering with volumetric clouds, stars and moons) that the RTX fixes leave off. This
-- turns it on and drives it: the sun, the moon and the stars for a time of day (by default the time
-- and direction of the map's own sun), a clock that can run, the moon's phase and lunar and solar
-- eclipses, the real night sky or the procedural one, and the runtime's twelve weather presets
-- blended into each other. Everything goes to Remix through the RTX fixes'
-- RemixConfig.SetConfigVariable. The settings are saved client settings (nativeloader_sky*,
-- nativeloader_weather*), shown in the RTX Remix tab under "Sky and weather". Documented in
-- nativeloader_sky.lua.md beside this file.
-- Which sky a map shows (ADR 0249): the RTX sky by default; the map's own sky (its sky textures and its 3D skybox)
-- where the player chooses it for that map; above the RTX sky, the sky a map's RTX version brings (a sky file in
-- data_static/nativeloader/sky/<map>/, or its add-on's hooks). One chat line at the map's start says which and how
-- to switch. nativeloader/map_sky.lua decides; this file does it.
-- ADR 0206: nothing in a start where this machine's loader did not activate RTX (NativeLoaderRTXStart, set by
-- !!!!nativeloader_engine_guard.lua, which runs first).
if NativeLoaderRTXStart and not NativeLoaderRTXStart() then return end
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("nativeloader/sky_model.lua")
    AddCSLuaFile("nativeloader/weather_presets.lua")
    AddCSLuaFile("nativeloader/map_sky.lua")
    AddCSLuaFile("nativeloader/enhanced_sky.lua")
    AddCSLuaFile("nativeloader/enhanced_weather.lua")
    AddCSLuaFile("nativeloader/enhanced_builtin_looks.lua")
    AddCSLuaFile("nativeloader/enhanced_editor.lua")
    AddCSLuaFile("nativeloader/enhanced_editor_panel.lua")
    return
end

local model = include("nativeloader/sky_model.lua")
local presets = include("nativeloader/weather_presets.lua")
local mapSky = include("nativeloader/map_sky.lua")
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N

local DEFAULTS = {
    nativeloader_sky = "1", nativeloader_sky_no_horizon = "0", nativeloader_sky_follow_map = "1",
    -- The Enhanced sky is the default (the user, 2026-11-26); Standard stays a choice and VR's sky.
    nativeloader_sky_enhanced = "1", nativeloader_sky_enhanced_quality = "auto",
    nativeloader_sky_hour = "14.5", nativeloader_sky_direction = "0", nativeloader_sky_time_passes = "1",
    nativeloader_sky_day_minutes = "20", nativeloader_sky_season = "summer", nativeloader_sky_moon = "full",
    nativeloader_sky_moon_day = "1",
    nativeloader_sky_eclipse = "", nativeloader_sky_eclipse_amount = "100", nativeloader_sky_stars = "map",
    nativeloader_weather = "partlyCloudy", nativeloader_weather_seconds = "30", nativeloader_sky_interval = "0.02",
    -- ADR 0253: the chat line at a map's start is off by default (nativeloader_defaults.lua turns a saved copy of the
    -- earlier default off once).
    nativeloader_sky_message = "0",
}

-- The night sky editor (ADR 0227): each element of the night sky on its own, on the RTX Remix tab's Night sky
-- editor page. A setting, its default, its range, the Remix option it sets and the option's value at 1 (the
-- setting is a multiple of it): the night sky image's four layers (each a brightness and a colour), the simulated
-- stars, the moon, the shooting stars. The moon's size is in degrees across and the shooting stars a minute.
local NIGHT = {
    { "nativeloader_sky_night_image", 1, 0, 4, "rtx.atmosphere.starMapBrightness", 0.12 },
    { "nativeloader_sky_stars_brightness", 1, 0, 8, "rtx.atmosphere.starMapStarBrightness", 1 },
    { "nativeloader_sky_stars_colour", 1, 0, 2, "rtx.atmosphere.starMapStarSaturation", 1 },
    { "nativeloader_sky_constellations_brightness", 1, 0, 8, "rtx.atmosphere.starMapConstellationBrightness", 1 },
    { "nativeloader_sky_constellations_colour", 1, 0, 2, "rtx.atmosphere.starMapConstellationSaturation", 1 },
    { "nativeloader_sky_milky_way_brightness", 1, 0, 8, "rtx.atmosphere.starMapGalaxyBrightness", 1 },
    { "nativeloader_sky_milky_way_colour", 1, 0, 2, "rtx.atmosphere.starMapGalaxySaturation", 1 },
    { "nativeloader_sky_nebulae_brightness", 1, 0, 8, "rtx.atmosphere.starMapNebulaBrightness", 1 },
    { "nativeloader_sky_nebulae_colour", 1, 0, 2, "rtx.atmosphere.starMapNebulaSaturation", 1 },
    { "nativeloader_sky_simulated_brightness", 1, 0, 4, "rtx.atmosphere.starBrightness", 0.5 },
    { "nativeloader_sky_simulated_density", 0.5, 0, 1, "rtx.atmosphere.starDensity", 1 },
    { "nativeloader_sky_simulated_twinkle", 1, 0, 4, "rtx.atmosphere.starTwinkleSpeed", 1 },
    { "nativeloader_sky_moon_brightness", 1, 0, 4, "rtx.atmosphere.moon0.brightness", 1 },
    { "nativeloader_sky_moon_size", 1.6, 0.5, 5, "rtx.atmosphere.moon0.angularRadius", 1 },
    { "nativeloader_sky_moon_glow", 1, 0, 4, "rtx.atmosphere.haloMoonBrightness", 15 },
    { "nativeloader_sky_earthshine", 1, 0, 8, "rtx.atmosphere.moon0.darkSideBrightness", 0.005 },
    { "nativeloader_sky_shooting_stars", 1.2, 0, 15, "rtx.atmosphere.shootingStarsPerMinute", 1 },
    { "nativeloader_sky_shooting_star_brightness", 1, 0, 8, "rtx.atmosphere.shootingStarBrightness", 1 },
}
-- The night's glow between the stars, a multiple of the weather's airglow (pushWeather).
local NIGHT_GLOW = { "nativeloader_sky_night_glow", 1, 0, 4 }
local NIGHT_SETTINGS = {}
for _, entry in ipairs(NIGHT) do NIGHT_SETTINGS[entry[1]] = entry end
NIGHT_SETTINGS[NIGHT_GLOW[1]] = NIGHT_GLOW
for name, entry in pairs(NIGHT_SETTINGS) do DEFAULTS[name] = tostring(entry[2]) end
local HELP = {
    nativeloader_sky_enhanced = "RTX sky quality, 0 Standard, 1 Enhanced (the default, desktop only: VR shows Standard)",
    nativeloader_sky_enhanced_quality = "Enhanced sky detail, auto (the loader's performance tier), high, medium or low",
    nativeloader_sky = "Sky on maps without a choice of their own (nativeloader_sky_here): 1 the RTX sky (sun, clouds, stars, "
        .. "moon), 0 the map's own sky and its 3D skybox. A map's RTX version's own sky comes first",
    nativeloader_sky_message = "1: one chat line at a map's start says which sky shows and how to switch (off by default)",
    nativeloader_sky_no_horizon = "1: the physical sky has no horizon: the sky goes on below it, with clouds, the stars and "
        .. "the moon (maps that float in the sky or in space)",
    nativeloader_sky_follow_map = "1: the time of day and the sun's direction come from the map's own sun",
    nativeloader_sky_hour = "Time of day in hours, 0-24 (with nativeloader_sky_follow_map 0)",
    nativeloader_sky_direction = "Turns the sun's path around the sky, in degrees (with nativeloader_sky_follow_map 0)",
    nativeloader_sky_time_passes = "1: the time of day runs on",
    nativeloader_sky_day_minutes = "Real minutes for a whole day while the time runs on",
    nativeloader_sky_season = "spring, summer, autumn or winter: how high the sun climbs and how long the day is",
    nativeloader_sky_moon = "Moon phase: new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, "
        .. "lastQuarter or waningCrescent",
    nativeloader_sky_moon_day = "The moon by day, 0-4: 1 is as bright as the real Moon at its phase, a pale disc over "
        .. "the blue sky; 0 hides it while the sun is up",
    nativeloader_sky_eclipse = "Eclipse: lunar or solar; empty for none. It sets the moon's phase",
    nativeloader_sky_eclipse_amount = "How far through the eclipse, 0-100: lunar total from 70, solar from 90",
    nativeloader_sky_stars = "Night sky: map (the night sky image: stars, galaxy and nebulae) or procedural",
    nativeloader_weather = "Weather: clear, partlyCloudy, overcast, hazy, foggy, drizzle, rainstorm, thunderstorm, "
        .. "snow, blizzard, sandstorm, smoggy; empty leaves clouds, fog and rain to Remix's own settings",
    nativeloader_weather_seconds = "Seconds a change of weather takes",
    nativeloader_sky_interval = "Seconds between updates of the sun, moon, stars and weather, 0-1: 0.02 is 50 a second, "
        .. "0 every frame",
    -- The night sky editor (ADR 0227).
    nativeloader_sky_night_image = "Night sky image: brightness of all its layers, 0-4 (1 as drawn)",
    nativeloader_sky_stars_brightness = "Night sky image: brightness of the stars, 0-8 (1 as drawn, 0 hides them)",
    nativeloader_sky_stars_colour = "Night sky image: colour of the stars, 0-2 (0 grey, 1 as drawn, 2 stronger)",
    nativeloader_sky_constellations_brightness = "Night sky image: brightness of the constellations' bright stars, 0-8",
    nativeloader_sky_constellations_colour = "Night sky image: colour of the constellations' bright stars, 0-2 (0 white)",
    nativeloader_sky_milky_way_brightness = "Night sky image: brightness of the Milky Way, 0-8",
    nativeloader_sky_milky_way_colour = "Night sky image: colour of the Milky Way, 0-2",
    nativeloader_sky_nebulae_brightness = "Night sky image: brightness of the nebulae, 0-8",
    nativeloader_sky_nebulae_colour = "Night sky image: colour of the nebulae, 0-2",
    nativeloader_sky_simulated_brightness = "Simulated stars: brightness, 0-4 (1 as drawn)",
    nativeloader_sky_simulated_density = "Simulated stars: how many, 0-1 (0.5 as drawn)",
    nativeloader_sky_simulated_twinkle = "Simulated stars: how fast they twinkle, 0-4 (0 still)",
    nativeloader_sky_moon_brightness = "The moon's brightness, its disc and its light on the map, 0-4",
    nativeloader_sky_moon_size = "The moon's size in degrees across, 0.5-5 (the real Moon is about 0.5); its light on the "
        .. "map stays the same",
    nativeloader_sky_moon_glow = "The glow around the moon, 0-4",
    nativeloader_sky_earthshine = "Earthshine, the faint light on the moon's dark side, 0-8",
    nativeloader_sky_shooting_stars = "Shooting stars a minute, 0-15 (0 none)",
    nativeloader_sky_shooting_star_brightness = "Brightness of the shooting stars, 0-8",
    nativeloader_sky_night_glow = "The night's glow between the stars (airglow), a multiple of the weather's, 0-4",
}
local cv = {}
for name, value in pairs(DEFAULTS) do cv[name] = CreateClientConVar(name, value, true, false, HELP[name]) end
-- ADR 0249: this map's sky, remembered for the map in data/nativeloader_companion/sky_maps.txt and set from it at each
-- map's start; not saved itself (it is the current map's). The value the companion acts on is `choiceNow` (below):
-- a console command runs on the next frame, and the map's start must not wait for it.
cv.nativeloader_sky_here = CreateClientConVar("nativeloader_sky_here", mapSky.AUTO, false, false,
    "This map's sky, remembered for the map: auto (its RTX version's sky where it has one, else nativeloader_sky's), "
    .. "rtx (the RTX sky), map (the map's own sky and its 3D skybox), addon (its RTX add-on's) or a sky file's id")
-- The engine settings the map's own 3D skybox changed (name=value;...), put back when it goes: a convar, so the next
-- map, which starts the client's Lua afresh, still knows them. Not saved.
local engineSaved = CreateClientConVar("nativeloader_sky_engine_saved", "", false, false,
    "Internal: the engine settings the map's own 3D skybox changed, put back when it goes")
-- nativeloader_defaults.lua registers this before the sky autorun. Migrate before any sky change
-- callbacks exist, so the map's initial sun and R16's map-add-on ownership are preserved.
hook.Run("NativeLoaderSkyDefaults")

-- How often the sky moves on (R3-015): every frame, as games move their sky, would be 0; 0.02 keeps a
-- running clock smooth at a fraction of the calls.
local function interval()
    return math.Clamp(cv.nativeloader_sky_interval:GetFloat(), 0, 1)
end

-- How the look of the physical sky differs from the runtime's defaults, whatever the weather
-- (tuned in the PoC, RESEARCH.md section 28).
local LOOK = {
    ["rtx.atmosphere.timeCycleEnable"] = "False", -- the sun is placed from here
    ["rtx.atmosphere.moon0.enabled"] = "True",
    -- Cumulus-shaped cloud shadows drifting over the ground (the runtime's default; the classic
    -- install's settings, which the package's defaults carry, turned them off).
    ["rtx.atmosphere.cloudVoxelShadowsEnable"] = "True",
    -- A moon a touch cool. Its size (by default 1.6 degrees, about three times the real one's 0.52; the
    -- runtime's 3.5 is a stylised giant) is the night sky editor's (NIGHT); its ground light is MOONLIGHT below.
    ["rtx.atmosphere.moon0.color"] = "0.11, 0.12, 0.135",
    -- The real Moon's face (the runtime's moon textures; on by default there too), its relief at 0.6:
    -- at the full 1 the terminator broke into dark notches when zoomed in (RESEARCH.md section 29).
    ["rtx.atmosphere.moonTextureEnable"] = "True",
    ["rtx.atmosphere.moonReliefStrength"] = "0.6",
    -- The eclipse geometry the stages of sky_model.eclipseSeparation assume.
    ["rtx.atmosphere.eclipseEnable"] = "True",
    ["rtx.atmosphere.eclipseUmbraScale"] = tostring(model.ECLIPSE.umbra),
    ["rtx.atmosphere.eclipsePenumbraScale"] = tostring(model.ECLIPSE.penumbra),
    ["rtx.atmosphere.eclipseSunScale"] = tostring(model.ECLIPSE.sun),
}
-- A night sky editor setting now, held to its range (its default for anything that is not a number).
local function nightValue(name)
    local entry = NIGHT_SETTINGS[name]
    local v = tonumber(cv[name]:GetString())
    if not v or v ~= v then return entry[2] end
    return math.Clamp(v, entry[3], entry[4])
end

-- The moon's size: the option holds the diameter in degrees; the eclipse geometry takes its radius.
local function moonRadius()
    return nightValue("nativeloader_sky_moon_size") / 2
end

-- The moon's light on the ground (rtx.atmosphere.surfaceMoonBrightness, 50 in the runtime). It falls
-- with the disc's area (moonSolidAngleSr), so (3.5 / 1.6)^2 times as much keeps a full moon's night as
-- light as the runtime's default one; for another size the area's change is taken out again, so the
-- moon's size changes how it looks, not how light the night is (the editor's moon brightness does). The
-- runtime gives it full strength as soon as the sun is below the horizon, so a rising full moon lit the
-- towers orange at dusk; it fades in with the twilight instead, from none with the sun 4 degrees down to
-- all of it at 12 (nautical twilight), when real moonlight starts to matter.
local MOONLIGHT, MOONLIGHT_SIZE = 240, 1.6
local function moonlight(sunElevation)
    local size = nightValue("nativeloader_sky_moon_size")
    return MOONLIGHT * (MOONLIGHT_SIZE / size) ^ 2 * model.ease((-sunElevation - 4) / 8)
end

-- The moon by day (ADR 0207). While the sun is up the runtime adds the moon's light to the sky in front of
-- it, as bright as the real Moon at its phase (rtx.atmosphere.daytimeMoonBrightness 1): a pale disc over
-- the blue, a quarter clear in the afternoon, a crescent faint near the sun. The setting scales that, 0 to 4;
-- 0 hides the moon by day, as before. The night's moon is not changed by it.
local function moonByDay()
    return math.Clamp(cv.nativeloader_sky_moon_day:GetFloat(), 0, 4)
end

-- GMod's scale. Remix takes 100 units for a metre (rtx.sceneScale 1), and a GMod unit is 1.905 cm,
-- so a Remix metre is 1.905 real ones and a whole map is a few dozen Remix metres across.
--   * Fog. The presets' fog is made for worlds kilometres wide and barely shows inside a map; each
--     weather's fog is set from how far one sees in it, in real metres, keeping the preset's tint.
--     Denser fog turns dark here: the runtime lights its froxel fog from lights only, not from the
--     sky, so the visibilities stay at 300 m or more.
--   * Rain and snow fall from a smaller volume around the player, so the same particles fall near
--     enough to be seen.
--   * The runtime's own test for cover (occludeUnderCover) traces up to 1 km of Remix distance,
--     100 000 units here, and a map's 3D skybox room hangs above most maps within that: it found
--     cover everywhere and no drop was ever born. The companion checks for cover with the game's
--     own trace instead (sheltered(), below) and lets the rain fade out under a roof.
local VISIBILITY = {
    clear = 13000, partlyCloudy = 8800, overcast = 4400, hazy = 1300, foggy = 400, drizzle = 880,
    rainstorm = 530, thunderstorm = 400, snow = 660, blizzard = 310, sandstorm = 320, smoggy = 670,
}
local WEATHER_LOOK = {
    ["rtx.weather.precipitation.spawnRadiusMeters"] = "8",
    ["rtx.weather.precipitation.spawnHeightMeters"] = "6",
    ["rtx.weather.precipitation.fallMarginMeters"] = "4",
    ["rtx.weather.precipitation.occludeUnderCover"] = "False",
    ["rtx.weather.precipitation.appearance.widthScale"] = "1.6",
}

-- The runtime's recommended weather variation per preset (dxvk-remix-gmod
-- docs/integrators/weather-presets.md, section 8): how fast and how far the cloud cover and the
-- wind wander.
local VARIATION = {
    clear = { 0.6, 0.5 }, partlyCloudy = { 1.0, 1.0 }, overcast = { 0.7, 0.7 }, hazy = { 0.8, 0.6 },
    foggy = { 0.5, 0.4 }, drizzle = { 1.2, 1.1 }, rainstorm = { 1.6, 1.4 }, thunderstorm = { 2.0, 1.6 },
    snow = { 0.9, 0.8 }, blizzard = { 1.8, 1.5 }, sandstorm = { 1.5, 1.6 }, smoggy = { 0.8, 0.7 },
}
-- The fields that wander (rtx_weather.cpp kDriftTable): cover and wind speed in proportion, the wind's
-- direction in degrees; the index seeds the noise.
local WANDER = { { "cloudCoverageMean", 0, 0.15, 0, 1 }, { "cloudWindSpeed", 6, 0.30, 0, math.huge },
    { "cloudWindDirection", 7, 10 } }

local function ready()
    return istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable)
end

-- Option -> text last given to Remix, so an unchanged value is not sent again.
local sent = {}
local function set(option, text)
    if sent[option] == text then return true end
    local ok, result = pcall(RemixConfig.SetConfigVariable, option, text)
    if ok and result ~= false then sent[option] = text return true end
    return false
end

local function configured(option)
    local ok, value = pcall(RemixConfig.GetConfigVariable, option)
    if ok and isstring(value) and value ~= "" then return value end
    return nil
end
local enhanced = include("nativeloader/enhanced_sky.lua")(model, set, configured, presets.defaults, function(key) sent[key] = nil end)

---------------------------------------------------------------- the map's sun

-- A lump Source compressed ("LZMA" first), unpacked through util.Decompress (map_sky.lzmaStream), or nil.
local function unpackLump(lump)
    if string.sub(lump, 1, 4) ~= "LZMA" then return lump end
    local stream = mapSky.lzmaStream(lump)
    if not stream or not (util and util.Decompress) then return nil end
    local ok, out = pcall(util.Decompress, stream)
    return ok and isstring(out) and out ~= "" and out or nil
end

-- A lump of the open BSP by its index (the header's lump table: offset and length at 8 + 16 * index), or nil.
local function readLump(f, index, limit)
    f:Seek(8 + index * 16)
    local offset, length = f:ReadLong(), f:ReadLong()
    if not (offset and length and offset > 0 and length > 0 and length < limit) then return nil end
    f:Seek(offset)
    local data = f:Read(length)
    return data and unpackLump(data) or nil
end

-- Whether a sky name's faces are there: materials/skybox/<name><side>.vmt, or the _hdr set Source also loads.
local function skyFaces(name)
    if not isstring(name) or name == "" or name:find("..", 1, true) or name:sub(1, 1) == "/" then return false end
    for _, side in ipairs({ "up", "rt", "ft", "lf", "bk" }) do
        if file.Exists("materials/skybox/" .. name .. side .. ".vmt", "GAME")
            or file.Exists("materials/skybox/" .. name .. "_hdr" .. side .. ".vmt", "GAME") then return true end
    end
    return false
end

-- The map's own sun from its BSP entity lump (lump 0), and its sky texture's name. ADR 0249: also its 3D skybox
-- (a sky_camera and its scale) and whether it has sky faces at all (the sky flags of its texinfos, lump 6); a
-- compressed lump is unpacked.
local mapInfo
local function readMap()
    local info = {}
    local f = file.Open("maps/" .. game.GetMap() .. ".bsp", "rb", "GAME")
    if f then
        local text = readLump(f, 0, 32 * 1024 * 1024)
        if text then
            local entities = model.parseEntities(text, { light_environment = true, env_sun = true, worldspawn = true,
                sky_camera = true })
            info.sun = model.sunOfEntities(entities)
            info.camera = mapSky.skyCamera(entities)
            for _, e in ipairs(entities) do
                if e.classname == "worldspawn" then info.skyname = e.skyname end
            end
        end
        local texinfo = readLump(f, 6, 16 * 1024 * 1024)
        if texinfo and bit and bit.band then info.texinfos = mapSky.skyTexinfos(texinfo, bit.band) end
        f:Close()
    end
    if not info.sun and util.GetSunInfo then
        local sun = util.GetSunInfo()
        local d = sun and sun.direction
        if d and d:Length() > 0.5 then
            if d.z < 0 then d = -d end
            local elevation = math.deg(math.asin(math.Clamp(d.z / d:Length(), -1, 1)))
            if elevation > 0 then
                info.sun = { elevation = elevation, bearing = model.wrap360(90 - math.deg(math.atan2(d.y, d.x))) }
            end
        end
    end
    if not info.skyname then
        local skyname = GetConVar("sv_skyname")
        info.skyname = skyname and skyname:GetString() or ""
    end
    info.mood = model.skyTimeOfName(info.skyname)
    info.faces = skyFaces(info.skyname)
    info.facts = mapSky.facts(info)
    return info
end

---------------------------------------------------------------- where the sky is

local function season()
    return model.SEASONS[cv.nativeloader_sky_season:GetString()] or model.SEASONS.summer
end

local function eclipse()
    local kind = cv.nativeloader_sky_eclipse:GetString()
    if enhanced.active and kind == "solar" then return nil end
    return (kind == "lunar" or kind == "solar") and kind or nil
end

-- The moon's phase and its latitude off the ecliptic: an eclipse puts it full or new, as far into the
-- shadow or across the sun as the progress says; otherwise the chosen phase, clear of the shadow.
local function moonPhase()
    local kind = eclipse()
    local phase = model.eclipsePhase(kind)
    if not phase then phase = model.MOON_PHASES[cv.nativeloader_sky_moon:GetString()] or model.MOON_PHASES.full end
    local amount = math.Clamp(cv.nativeloader_sky_eclipse_amount:GetFloat() / 100, 0, 1)
    if enhanced.active then return phase, enhanced.moonLatitude(kind, amount, moonRadius()) end
    return phase, model.moonLatitude(kind, amount, moonRadius())
end

local function skyAt(hours, north)
    local phase, moonLatitude = moonPhase()
    return model.sky(hours, season(), phase, north, nil, moonLatitude)
end

-- The time and the north bearing that match the map: its sun in the afternoon, or for a map set at
-- dusk or at night (by its sky's name) the sun low or gone, with the map's light where the setting
-- sun or the moon stands.
local function followed()
    local day, sun = season(), mapInfo and mapInfo.sun
    local mood = mapInfo and mapInfo.mood
    if mood == "night" then
        local hours = 23
        if not sun then return hours, 0 end
        return hours, model.wrap360(sun.bearing - skyAt(hours, 0).moon.bearing)
    end
    if mood == "dusk" then
        local hours = model.timeForElevation(3, false, day)
        if not sun then return hours, 0 end
        return hours, model.wrap360(sun.bearing - skyAt(hours, 0).sun.bearing)
    end
    if not sun then return tonumber(DEFAULTS.nativeloader_sky_hour), 0 end
    return model.followMap(sun, day)
end

-- The settings changed by this file itself (to show the map's time and direction), so their change
-- callbacks do not take them for the player's.
local writing = {}
local function write(name, value)
    if cv[name]:GetString() == value then return end
    writing[name] = value
    RunConsoleCommand(name, value)
end

local clock -- the time of day now, in hours
local followHours, followNorth -- the map's time and north bearing, while the sky follows it
local function startClock()
    if cv.nativeloader_sky_follow_map:GetBool() then
        followHours, followNorth = followed()
        clock = followHours
        write("nativeloader_sky_hour", string.format("%.2f", followHours))
        write("nativeloader_sky_direction", string.format("%.1f", followNorth))
    else
        clock = model.parseClock(cv.nativeloader_sky_hour:GetString()) or tonumber(DEFAULTS.nativeloader_sky_hour)
        followHours, followNorth = nil, nil
    end
end

-- Whether a change of a setting is this file's own: what write() sent, or, while the sky follows the
-- map, a slider of the panel writing back the map's value as it shows it (rounded to its decimals:
-- two for the time, none for the direction). Only a real move takes the sky off the map's sun.
local function ours(name, value)
    if writing[name] == value then
        writing[name] = nil
        return true
    end
    local n = tonumber(value)
    if not n or not followNorth then return false end
    if name == "nativeloader_sky_hour" then return math.abs(n - followHours) < 0.006 end
    if name == "nativeloader_sky_direction" then return math.abs(model.wrap180(n - followNorth)) < 0.51 end
    return false
end

local function north()
    return followNorth or model.wrap360(cv.nativeloader_sky_direction:GetFloat())
end

local function now()
    return skyAt(clock or 12, north())
end

---------------------------------------------------------------- weather

local weather = { values = nil, from = nil, to = nil, began = 0, seconds = 0, name = nil }

-- A preset as GMod gets it: its fog distance from its visibility (VISIBILITY). The preset gives the
-- fog's transmittance colour over a measuring distance; the distance is chosen so that what one sees
-- fades to 5 % at the visibility (Koschmieder), with the colour's tint kept. The runtime reads the
-- colour as gamma-encoded sRGB and uses it linear (rtx_global_volumetrics.cpp, getVolumeArgs), so the
-- extinction is worked out from the linear colour too.
local function linear(c)
    return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end
local tunedPresets = {}
local function presetValues(name)
    if tunedPresets[name] then return tunedPresets[name] end
    local values = presets.presets[name]
    if not values then return nil end
    local copy = {}
    for k, v in pairs(values) do copy[k] = v end
    local c, visibility = values.transmittanceColor, VISIBILITY[name]
    if c and visibility then
        local configured = ready() and RemixConfig.GetConfigVariable and tonumber(RemixConfig.GetConfigVariable("rtx.sceneScale"))
        local remixMetre = 1.905 * (configured and configured > 0 and configured or 1)
        local extinction = (-math.log(linear(c[1])) - math.log(linear(c[2])) - math.log(linear(c[3]))) / 3
        copy.transmittanceMeasurementDistanceMeters = extinction * (visibility / remixMetre) / 3
    end
    tunedPresets[name] = copy
    return copy
end

local function weatherName()
    local name = cv.nativeloader_weather:GetString()
    if name == "" or not presetValues(name) then return nil end
    return name
end

-- Whether the view is under cover: the game's trace straight up ends on something other than the
-- sky. Rain and snow fade out under a roof and back in outside (see WEATHER_LOOK).
local outdoors = 1
local function sheltered()
    local eye = EyePos()
    local tr = util.TraceLine({ start = eye, endpos = eye + Vector(0, 0, 32768), mask = MASK_SOLID, filter = LocalPlayer() })
    return tr.Hit and not tr.HitSky
end

-- A fog preset chosen under Remix settings (nativeloader_menu.lua) replaces the weather's fog.
local function fogPresetChosen()
    return hook.Run("NativeLoaderRemixFogOverride") == true
end

-- Under the night sky image the weather's airglow is turned down to this fraction: as in Skyrim, the
-- image's nebulae are the night's glow and the space between them is dark. The ground stays as light:
-- the image lights it about as much as the airglow did (RESEARCH.md section 29).
local IMAGE_AIRGLOW = 0.05
local function nightSkyImage()
    return cv.nativeloader_sky_stars:GetString() ~= "procedural"
end

-- The sky without a horizon (R26, ADR 0139), for maps that float in the sky or in space: below the
-- horizon the runtime shows sky instead of the even haze of a ground the map does not have: the sky
-- above's colours mirrored, clouds and high clouds (the opposite side's, so no reflection), the sun's
-- glow around the sun, and the stars and the moon wherever they are.
local function noHorizon()
    return cv.nativeloader_sky_no_horizon:GetBool()
end

-- The options this session's weather has set, which leaving the weather to Remix puts back.
local weatherSet = {}
-- Precipitation is rendered by Remix in both skies. NUMOS has its own clouds, wind, lightning and fog.
local precipitation = {}
for _, field in ipairs(presets.fields) do
    if field.option:find("rtx.weather.precipitation.", 1, true) == 1 then precipitation[#precipitation + 1] = field end
end

local function pushWeather(values)
    for option, text in pairs(WEATHER_LOOK) do
        set(option, text)
        weatherSet[option] = true
    end
    local ownFog = fogPresetChosen()
    for _, field in ipairs(enhanced.active and precipitation or presets.fields) do
        local v = values[field.name]
        if field.name == "precipitationIntensity" and v then v = v * outdoors end
        if field.name == "nightSkyBrightness" and v then
            -- The night sky editor's night glow scales what the weather gives (ADR 0227).
            v = v * (nightSkyImage() and IMAGE_AIRGLOW or 1) * nightValue("nativeloader_sky_night_glow")
        end
        if ownFog and string.find(field.option, "rtx.volumetrics.", 1, true) == 1 then
            -- Forget what was sent, so the weather's fog comes back once the preset is cleared.
            sent[field.option] = nil
        elseif v ~= nil then
            set(field.option, model.optionText(v, field.integer))
            weatherSet[field.option] = true
        end
    end
end

-- What an option goes back to when the weather is left to Remix again (R3-009): rtx.conf's value
-- (GetConfigVariable reads only that file), else what Remix has without it (weather_presets.lua: the
-- package's classic layer, else the runtime's default). The RTX fixes' per-map settings are not
-- known here and are not put back.
local function remixValue(option)
    return configured(option) or presets.defaults[option]
end

local function releaseWeather()
    if not ready() then return end
    local ownFog = fogPresetChosen()
    for option in pairs(weatherSet) do
        -- A fog preset chosen under Remix settings keeps the fog it set.
        if not (ownFog and string.find(option, "rtx.volumetrics.", 1, true) == 1) then
            local text = remixValue(option)
            if text then set(option, text) end
        end
    end
    weatherSet = {}
end

local function wander(values, t, name)
    local variation = VARIATION[name]
    if variation then
        local phase = t * variation[1]
        for _, w in ipairs(WANDER) do
            local v, swing = values[w[1]], model.drift(phase, w[2]) * w[3] * variation[2]
            if w[4] then values[w[1]] = math.Clamp(v + swing * v, w[4], w[5]) else values[w[1]] = model.wrap360(v + swing) end
        end
    end
end

-- The values now: the blend between two presets, plus the slow variation of the cover and the wind.
local function weatherNow(t)
    local values = {}
    local progress = weather.seconds > 0 and model.ease((t - weather.began) / weather.seconds) or 1
    for _, field in ipairs(presets.fields) do
        local a, b = weather.from[field.name], weather.to[field.name]
        values[field.name] = (progress >= 1 or a == nil) and b or model.blend(field.kind, a, b, progress)
    end
    wander(values, t, weather.name)
    return values, progress
end

local function setWeather(instantly)
    local name = weatherName()
    local seconds = instantly and 0 or math.max(cv.nativeloader_weather_seconds:GetFloat(), 0)
    enhanced.rain(name, name and presets.presets[name].precipitationIntensity or 0, CurTime(), seconds)
    if enhanced.active then enhanced.selectWeather(name, CurTime(), seconds) end
    if not name then
        -- Left to Remix: what the weather set goes back to Remix's own values, not the last preset's.
        if weather.name then releaseWeather() end
        weather.name = nil
        return
    end
    local target = presetValues(name)
    local t = CurTime()
    weather.from = (not instantly and weather.values) or target
    weather.to, weather.name, weather.began = target, name, t
    weather.seconds = seconds
end

---------------------------------------------------------------- whose sky it is

-- A map's own RTX add-on may set the sky itself (Modern House RTX does on modern_house, and puts its
-- settings back three times in the first minute). Such a sky is left alone unless the player changes
-- a sky setting in that session. Add-ons say so by answering the hook NativeLoaderSkyOwner with
-- their name.
-- An add-on whose sky belongs to the place, so that no time of day or weather fits it (space around
-- the station of gm_stelliferous), also answers the hook NativeLoaderSkyFixed with true, from the
-- moment its Lua loads on that map (ADR 0248). The player's own sky (Follow the map's sun unticked)
-- then leaves that sky alone at the map's start too; a sky setting changed in the session still takes
-- it over. NATIVELOADER_SKY.takenOver() tells such an add-on when its sky is no longer its own.
local takenOver = false    -- a sky or weather setting changed in this session
local ownFromStart = false -- the player's own sky (Follow the map's sun unticked) at this map's start
local function owner()
    local name = hook.Run("NativeLoaderSkyOwner")
    if isstring(name) and name ~= "" then return name end
    if istable(MHRTX_Config) and game.GetMap() == "modern_house" then return "Modern House RTX" end
    return nil
end

local function fixed()
    return hook.Run("NativeLoaderSkyFixed") == true
end

---------------------------------------------------------------- which sky the map shows (ADR 0249)

-- The RTX sky by default, on every map. The player may choose, for one map, the map's own sky: its sky textures
-- and, where it has one, its 3D skybox (the user's request of 2026-11-20). Above the RTX sky comes the sky a map's
-- RTX version brings (the user's choice of 2026-11-20): an add-on that sets it from Lua (the hooks above), or a sky
-- file in data_static/nativeloader/sky/<map>/<id>.json, content any add-on may ship: "map" (the map's own sky,
-- which its Remix mod may have replaced) or "skybox" (another sky by its name, set through sv_skyname in a
-- single-player game). A sky or weather setting changed in the session shows the RTX sky until the next map's
-- start, as for a fixed add-on sky (ADR 0248; the user kept it for every sky that is not the RTX sky).
local CHOICES = "nativeloader_companion/sky_maps.txt"
local facts = mapSky.facts() -- this map's (readMap)
local files = {}             -- this map's sky files, as map_sky.sorted orders them
local knownAddon             -- the add-on that set this map's sky, kept once it stops saying so
local choiceNow = mapSky.AUTO
local function singlePlayer() return game.SinglePlayer and game.SinglePlayer() or false end

-- The per-map choices: one "<map> <choice>" a line; "auto" is not written.
local function loadChoices()
    local out, count = {}, 0
    local text = file.Read(CHOICES, "DATA")
    for line in string.gmatch(isstring(text) and text or "", "[^\r\n]+") do
        local map, choice = line:match("^(%S+)%s+(%S+)%s*$")
        if map and mapSky.validMap(map) and mapSky.validChoice(choice) and choice ~= mapSky.AUTO and count < 4096 then
            out[string.lower(map)], count = choice, count + 1
        end
    end
    return out
end

local function saveChoice(map, choice)
    map = string.lower(map)
    if not mapSky.validMap(map) then return end
    local all = loadChoices()
    all[map] = choice ~= mapSky.AUTO and choice or nil
    local names = {}
    for name in pairs(all) do names[#names + 1] = name end
    table.sort(names)
    local lines = {}
    for _, name in ipairs(names) do lines[#lines + 1] = name .. " " .. all[name] end
    file.CreateDir("nativeloader_companion")
    file.Write(CHOICES, table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""))
end

-- The map's sky files, checked (map_sky.declaration); a file left out is named once in the console.
local function readFiles(map)
    local out = {}
    map = string.lower(map or "")
    if not mapSky.validMap(map) or not file.Find then return out end
    local folder = "data_static/nativeloader/sky/" .. map .. "/"
    local names = file.Find(folder .. "*.json", "GAME") or {}
    table.sort(names)
    for i, name in ipairs(names) do
        if i > mapSky.MAX_FILES then
            MsgN("[nativeloader] sky: more than " .. mapSky.MAX_FILES .. " sky files for " .. map .. "; the rest are left out")
            break
        end
        local id = string.lower((string.gsub(name, "%.[Jj][Ss][Oo][Nn]$", "")))
        local size = file.Size and file.Size(folder .. name, "GAME") or 0
        local d, why
        if size > mapSky.MAX_BYTES then
            why = "it is larger than 16 KiB"
        else
            d, why = mapSky.declaration(id, file.Read(folder .. name, "GAME"), util.JSONToTable)
        end
        if d and d.kind == "skybox" and not skyFaces(d.skyname) then
            d, why = nil, "its skyname has no faces in materials/skybox"
        end
        if d then out[#out + 1] = d else MsgN("[nativeloader] sky: " .. folder .. name .. " left out: " .. why) end
    end
    return mapSky.sorted(out)
end

local chosenOther, overruled -- below

-- The add-on that sets this map's sky from Lua, as map_sky.resolve takes it, or nil. An add-on that names itself only
-- while its sky shows (gm_stelliferous RTX asks takenOver() in its answer) is still the map's RTX version's sky for the
-- rest of this map's session once the player's sky replaced it.
local function addonSky()
    local name = owner()
    if name then
        knownAddon = { name = name, fixed = fixed() }
        return knownAddon
    end
    if knownAddon and overruled() then return knownAddon end
    return nil
end

-- Which sky this map shows before a setting changed in the session (map_sky.resolve), cached while what decides
-- it stays the same (the tick asks fifty times a second).
local resolved, resolvedKey
local function resolution()
    local addon = addonSky()
    local key = choiceNow .. "|" .. cv.nativeloader_sky:GetString() .. "|" .. (addon and (addon.name .. "|" .. tostring(addon.fixed)) or "")
    if key ~= resolvedKey then
        resolved = mapSky.resolve({ choice = choiceNow, global = cv.nativeloader_sky:GetString(), facts = facts,
            files = files, addon = addon, single = singlePlayer() })
        resolvedKey = key
    end
    return resolved
end

-- Whether the player chose a sky for this map that is not its RTX add-on's.
function chosenOther()
    if choiceNow == mapSky.RTX or choiceNow == mapSky.MAP then return true end
    for _, d in ipairs(files) do
        if d.id == choiceNow and (d.kind ~= "skybox" or singlePlayer()) then return true end
    end
    return false
end

-- Whether the player's sky replaces a map's add-on's sky now: another sky chosen for the map; the player's own time
-- from the map's start (ADR 0105), not over a fixed sky (ADR 0248); a sky or weather setting changed in the session
-- (ADR 0031). It runs no owner hook: an add-on asks it from its own answer to that hook (gm_stelliferous RTX does).
function overruled()
    return chosenOther() or takenOver or (ownFromStart and not fixed())
end

local function inCharge()
    return ready() and (resolution().sky ~= "addon" or overruled())
end

-- What the companion shows while in charge: "rtx" (the RTX sky) or "own" (the map's own sky or a sky file's). A sky
-- or weather setting changed in the session shows the RTX sky until the next map's start.
local function shownSky()
    local r = resolution()
    if takenOver or r.sky == "rtx" or r.sky == "addon" then return "rtx", r end
    return "own", r
end

local function physicalWanted()
    return (shownSky()) == "rtx"
end

local leaving = false
local function wantEnhanced()
    return cv.nativeloader_sky_enhanced:GetBool() and not leaving and not enhanced.inVR() and inCharge() and physicalWanted()
end

-- What shows now, for the chat line, the panel and nativeloader_sky_status (map_sky.state's `e`).
local function describe()
    local r = resolution()
    local e = {}
    for k, v in pairs(r) do e[k] = v end
    e.package = r.package or (knownAddon and knownAddon.name) or nil
    -- A fixed sky's add-on that has not named itself in this session (the player's choice for the map replaced it
    -- from the start): its sky is still there to go back to.
    e.packageUnnamed = not e.package and fixed() or nil
    if r.sky == "addon" and not overruled() then
        e.shown, e.follows = "addon", not fixed()
    elseif takenOver and r.sky ~= "rtx" then
        e.shown = "taken"
    else
        e.shown = shownSky()
    end
    return e
end

---------------------------------------------------------------- giving it to Remix

local physical -- what the sky is now: true physical, false the map's own sky, nil not set yet
local function pushSky()
    local want = physicalWanted()
    if enhanced.active then
        enhanced.pushSky(cv.nativeloader_sky_enhanced_quality:GetString(), nightValue("nativeloader_sky_moon_size"),
            nightValue("nativeloader_sky_moon_brightness"))
    elseif want then
        set("rtx.skyMode", "1")
        -- The map's own sun reaches Remix as a fixed-function light; the atmosphere makes the sun.
        set("rtx.ignoreGameDirectionalLights", "True")
        for option, text in pairs(LOOK) do set(option, text) end
        -- The night sky: the runtime's night sky image (stars, galaxy, nebulae) or its procedural field.
        set("rtx.atmosphere.starMapEnable", nightSkyImage() and "True" or "False")
        set("rtx.atmosphere.daytimeMoonBrightness", model.optionText(moonByDay()))
    else
        -- The map's own sky: Remix draws its sky textures (and the 3D skybox, syncEngine below), and the map's own
        -- sun lights it. Sent again after another add-on changed it (applyAll forgets what was sent).
        set("rtx.skyMode", "0")
        local configured = RemixConfig.GetConfigVariable and RemixConfig.GetConfigVariable("rtx.ignoreGameDirectionalLights")
        set("rtx.ignoreGameDirectionalLights", (isstring(configured) and configured ~= "") and configured or "False")
    end
    physical = want
end

local function pushCelestial()
    local sky = now()
    if enhanced.active then
        enhanced.celestial(sky, clock or 12, season(), north(), eclipse() == "lunar", moonByDay())
        return
    end
    set("rtx.atmosphere.sunElevation", string.format("%.3f", sky.sun.elevation))
    set("rtx.atmosphere.sunRotation", string.format("%.3f", sky.sun.bearing))
    set("rtx.atmosphere.moon0.elevation", string.format("%.3f", sky.moon.elevation))
    set("rtx.atmosphere.moon0.rotation", string.format("%.3f", sky.moon.bearing))
    set("rtx.atmosphere.moon0.phase", string.format("%.3f", sky.moon.phase))
    set("rtx.atmosphere.starRotation", string.format("%.3f", sky.stars.rotation))
    set("rtx.atmosphere.starAxisElevation", string.format("%.3f", sky.stars.poleElevation))
    set("rtx.atmosphere.starAxisRotation", string.format("%.3f", sky.stars.poleBearing))
    set("rtx.atmosphere.surfaceMoonBrightness", string.format("%.1f", moonlight(sky.sun.elevation)))
end

-- The horizon (R26, ADR 0139) is how the player sees whichever physical sky is shown, the
-- companion's or a map add-on's, not whose sky it is: it is sent also where a map's add-on owns the
-- sky, and changing it does not take that sky over (like nativeloader_sky_interval). Where such an
-- add-on is in charge it goes out only when on or changed, so with the setting at its default the
-- companion still sends that map nothing.
local function pushHorizon(changing)
    if enhanced.active or not ready() then return end
    if changing or noHorizon() or inCharge() then
        set("rtx.atmosphere.noHorizon", noHorizon() and "True" or "False")
    end
end

-- The night sky editor (ADR 0227): how each element of the night sky looks. Like the horizon, how the player
-- sees whichever physical sky is shown, not whose sky it is: a change goes out also where a map's add-on owns the
-- sky, without taking that sky over. With the companion in charge of a physical sky every setting goes with it;
-- where an add-on is in charge only the settings off their defaults (and the one changing), so a player who
-- changed nothing still sends that map nothing.
local function pushNightSky(changing)
    if enhanced.active or not ready() then return end
    local all = inCharge() and physicalWanted()
    for _, entry in ipairs(NIGHT) do
        local v = nightValue(entry[1])
        if all or changing == entry[1] or math.abs(v - entry[2]) > 1e-4 then
            set(entry[5], model.optionText(v * entry[6]))
        end
    end
end

local function selectProvider()
    if ready() and enhanced.hasSavedVolume() then enhanced.restoreLegacyVolume() end
    local want = wantEnhanced()
    if want ~= enhanced.active then
        sent = {}
        if want then
            if next(weatherSet) then releaseWeather() end
            enhanced.enter()
            enhanced.selectWeather(weather.name, CurTime(), 0)
        elseif ready() then
            enhanced.leave()
            -- A late map add-on can claim the sky between ticks. Give back the host precipitation too.
            if not inCharge() then releaseWeather() end
        end
        if clock and followNorth and mapInfo.mood == "night" then
            -- The bearing that puts this provider's Moon at the map light, without restarting a running clock.
            followHours, followNorth = followed()
            write("nativeloader_sky_direction", string.format("%.1f", followNorth))
        end
    end
end

local function apply()
    if leaving then return end
    selectProvider()
    pushHorizon(false)
    pushNightSky(nil)
    if not inCharge() then return end
    pushSky()
    if physical then
        pushCelestial()
        if enhanced.active then
            enhanced.updateFog()
            enhanced.pushWeather(CurTime(), weather.name, wander)
        end
        if weather.name then
            local values = weatherNow(CurTime())
            weather.values = values
            pushWeather(values)
        end
    elseif next(weatherSet) then
        -- ADR 0249: the weather is the RTX sky's. Under the map's own sky what it set goes back to Remix's own values.
        releaseWeather()
    end
end

-- Everything again, as if nothing had been sent (after another add-on may have changed it).
local function applyAll()
    sent = {}
    apply()
end

---------------------------------------------------------------- the map's own 3D skybox and sky name (ADR 0249)

-- The map's 3D skybox under RTX (r_3dsky 1, which the session turns off): the runtime moves what the sky camera
-- draws out to the main camera, magnified by rtx.skyReprojectScale (17 in the package's layer: for maps at scale
-- 16, a touch further out, so a copy of the playable area in the skybox stays behind the map). The session draws
-- the whole map in every view (r_novis 1), so the sky pass drew it too, magnified 16 times around the camera; with
-- visibility by the PAS (the RTX fixes' patch, as the gm_stelliferous and Backrooms remasters use it) the sky pass
-- draws the skybox room alone and the main view what the original game draws around the camera, without the
-- skybox room's miniature. Only while the map's own sky shows with its 3D skybox; what it changed is kept in
-- nativeloader_sky_engine_saved and put back when it goes, on this map or at the next one's start.
local ENGINE = { { "r_3dsky", "1" }, { "r_novis", "0" }, { "rtx_patch_forcenovis", "0" }, { "rtx_patch_vis_pas", "1" } }

local function engineValue(name)
    local c = GetConVar(name)
    return c and c:GetString() or nil
end

local function setEngine(name, value)
    local c = GetConVar(name)
    if not c or c:GetString() == value then return end
    -- The RTX fixes ask before r_3dsky 1 (cl_rtx_settings.lua); the player chose the map's sky here, so the
    -- question is held back for this one change. Their change callback runs with the command, in this order.
    local ask = name == "r_3dsky" and value ~= "0" and engineValue("rtx_show_3dsky_warning") or nil
    if ask and ask ~= "0" then
        RunConsoleCommand("rtx_show_3dsky_warning", "0")
        RunConsoleCommand(name, value)
        RunConsoleCommand("rtx_show_3dsky_warning", ask)
        return
    end
    -- A convar made in Lua (the fixes' patch switches) changes at once; the engine's own on the next command run.
    if not pcall(c.SetString, c, value) then RunConsoleCommand(name, value) end
end

local function syncPatches()
    -- The fixes apply their patch switches every half second; at once is better for a frame or two.
    if isfunction(RTX_SyncPatches) then timer.Simple(0.1, function() pcall(RTX_SyncPatches) end) end
end

local function want3D()
    if not inCharge() then return false end
    local shown, r = shownSky()
    return shown == "own" and r.threeD == true
end

local function syncEngine()
    local saved = engineSaved:GetString()
    if want3D() then
        if saved == "" then
            local parts = {}
            for _, e in ipairs(ENGINE) do
                local v = engineValue(e[1])
                if v and v:match("^[%w%.%-]*$") then parts[#parts + 1] = e[1] .. "=" .. v end
            end
            engineSaved:SetString(table.concat(parts, ";"))
        end
        for _, e in ipairs(ENGINE) do setEngine(e[1], e[2]) end
        syncPatches()
    elseif saved ~= "" then
        for name, value in string.gmatch(saved, "([%w_]+)=([%w%.%-]*)") do
            for _, e in ipairs(ENGINE) do
                if e[1] == name then setEngine(name, value) end
            end
        end
        engineSaved:SetString("")
        syncPatches()
    end
end

-- Another sky by its name (a sky file's "skybox"), through sv_skyname, which every player of a game shares: in a
-- single-player game only. The map's own name comes back when it goes; the next map sets its own.
local skynameSaved
local function syncSkyname()
    local want
    if inCharge() and singlePlayer() then
        local shown, r = shownSky()
        if shown == "own" and r.skyname then want = r.skyname end
    end
    local current = engineValue("sv_skyname")
    if not current then return end
    if want then
        if current ~= want then
            skynameSaved = skynameSaved or current
            RunConsoleCommand("sv_skyname", want)
        end
    elseif skynameSaved then
        if current ~= skynameSaved then RunConsoleCommand("sv_skyname", skynameSaved) end
        skynameSaved = nil
    end
end

-- The sky as it should be now: Remix's options, the engine's 3D skybox, the sky name.
local function refresh()
    applyAll()
    syncEngine()
    syncSkyname()
end

---------------------------------------------------------------- what it says (ADR 0249)

local function sentence(part, translate)
    if not part then return nil end
    local ok, text = pcall(string.format, translate and L(part[1]) or part[1], unpack(part, 2))
    return ok and text or part[1]
end

local function message(translate)
    local e = describe()
    local out = { sentence(mapSky.state(e, facts), translate) }
    out[#out + 1] = sentence(mapSky.advice(e, facts), translate)
    out[#out + 1] = sentence(mapSky.limit(e, facts), translate)
    return table.concat(out, " ")
end

-- One chat line at the map's start: which sky shows and how to switch (the user's request of 2026-11-20), with "Say
-- which sky shows" ticked, off by default (ADR 0253). The console gets it in English either way, for bug reports.
local said = false
local function say()
    if said or not ready() then return end
    said = true
    MsgN("[nativeloader] sky: " .. message(false))
    if cv.nativeloader_sky_message:GetBool() and chat and chat.AddText then
        chat.AddText(Color(118, 185, 0), "[RTX] ", Color(235, 235, 235), message(true))
    end
end

-- A map's add-on that sets its sky again after the player took it over showed that sky until the
-- timer below put the player's back. Modern House RTX does so 23, 43 and 63 s after the map starts:
-- its afternoon sun came up for as long as 10 s in the middle of the player's night, and the daylight
-- then lingered in the image's temporal history wherever the camera had looked, a haze over the
-- stars with a straight edge where the view had turned (native loader review R5, 2026-10-31). An
-- add-on that runs the hook NativeLoaderSkySet after setting the sky gets the player's sky back in
-- the same tick; Modern House RTX's MHRTX.ApplySettings is wrapped to run it (again after a reload
-- of that add-on's Lua replaced it).
local function followMapAddon()
    if not (istable(MHRTX) and isfunction(MHRTX.ApplySettings)) or MHRTX.ApplySettings == MHRTX.nativeLoaderApply then return end
    local applySettings = MHRTX.ApplySettings
    MHRTX.nativeLoaderApply = function(...)
        applySettings(...)
        hook.Run("NativeLoaderSkySet")
    end
    MHRTX.ApplySettings = MHRTX.nativeLoaderApply
end

-- GMod's poster command under RTX (GitHub issue 3, ADR 0226): while the runtime renders a poster's tiles its own
-- clock stands still, and the sky waits with it, so the sun, the moon and the weather are the same in every tile. The
-- engine guard's read-only status, taken now: what a later script puts in the table changes nothing here.
local posterStatus = istable(nlengineguard) and nlengineguard.PosterStatus or nil
local function posterRendering()
    if not isfunction(posterStatus) then return false end
    local ok, status = pcall(posterStatus)
    return ok and istable(status) and (status.state == "starting" or status.state == "rendering")
end

-- The clock and the weather, every nativeloader_sky_interval seconds; what has not changed is not
-- sent again (set).
local lastTick
timer.Create("nativeloader_sky", interval(), 0, function()
    -- A map's add-on that loads after the map started (Modern House RTX does) is followed from its
    -- first sky on, not only once the 10 s timer below finds it.
    followMapAddon()
    if not clock or leaving then return end
    if wantEnhanced() ~= enhanced.active or enhanced.hasSavedVolume() then apply() end
    if not inCharge() then return end
    local t = RealTime()
    local dt = lastTick and math.max(t - lastTick, 0) or 0
    lastTick = t
    -- The time a poster takes is left out: the clock goes on from where it stood.
    if posterRendering() then return end
    if cv.nativeloader_sky_time_passes:GetBool() then
        local minutes = math.max(cv.nativeloader_sky_day_minutes:GetFloat(), 0.1)
        clock = (clock + dt / (minutes * 60) * 24) % 24
    end
    if physical then pushCelestial() end
    if physical and weather.name then
        local values = weatherNow(CurTime())
        weather.values = values
        if (values.precipitationIntensity or 0) > 0 then
            -- Half a second to fade, either way, however often this runs.
            local target, step = sheltered() and 0 or 1, math.min(dt * 2, 1)
            outdoors = target > outdoors and math.min(outdoors + step, target) or math.max(outdoors - step, target)
        end
        pushWeather(values)
    end
    if enhanced.active then enhanced.pushWeather(CurTime(), weather.name, wander) end
end)

enhanced.editor.changed = function(action, key)
    if not enhanced.active or not wantEnhanced() then return end
    if action == "style" then
        pushSky()
    else
        enhanced.editLook(action, key, CurTime())
    end
    enhanced.pushWeather(CurTime(), weather.name, wander)
end

hook.Add("NativeLoaderSkySet", "nativeloader_sky", function()
    if overruled() and owner() and ready() then applyAll() end
    if enhanced.active and not wantEnhanced() then apply() end
end)

hook.Add("NativeLoaderRemixFogChanged", "nativeloader_sky", function()
    if enhanced.active then
        enhanced.updateFog()
        enhanced.pushWeather(CurTime(), weather.name, wander)
    end
end)

-- On a map whose add-on set the sky, once the player took it over: put it back every 10 s.
timer.Create("nativeloader_sky_owned", 10, 0, function()
    followMapAddon()
    if overruled() and owner() and ready() then applyAll() end
end)

---------------------------------------------------------------- settings changing

local function changed(name, _, value)
    if name == "nativeloader_sky_enhanced" or name == "nativeloader_sky_enhanced_quality" then
        -- A preference for the companion's RTX sky never takes a map's own or fixed sky over.
        if clock and (enhanced.active or wantEnhanced()) then apply() end
        return
    end
    if name == "nativeloader_sky_interval" then
        -- How often, not what: it does not take a map's sky over.
        timer.Adjust("nativeloader_sky", interval())
        return
    end
    if name == "nativeloader_sky_no_horizon" then
        -- How the sky is seen, not whose it is (pushHorizon): it does not take a map's sky over either.
        pushHorizon(true)
        return
    end
    if name == "nativeloader_sky_message" then return end
    if enhanced.active and (NIGHT_SETTINGS[name] or name == "nativeloader_sky_stars") then
        if name == "nativeloader_sky_moon_size" or name == "nativeloader_sky_moon_brightness" then
            if wantEnhanced() then pushSky() pushCelestial() end
        end
        return
    end
    if name == "nativeloader_sky" then
        -- ADR 0249: the sky of maps without a choice of their own, not a setting of the RTX sky's; a map's RTX version's
        -- sky stays above it, and it takes no sky over.
        if clock then refresh() end
        return
    end
    if NIGHT_SETTINGS[name] then
        -- The night sky editor (ADR 0227): how the night sky looks, not whose it is (pushNightSky). The moon's size
        -- also moves the eclipse geometry and the moonlight on the ground, the night glow the weather's airglow.
        pushNightSky(name)
        if inCharge() then
            if physical and name == "nativeloader_sky_moon_size" then pushCelestial() end
            if weather.name and name == "nativeloader_sky_night_glow" and weather.values then pushWeather(weather.values) end
        end
        return
    end
    if ours(name, value) or not clock then return end
    takenOver = true
    if name == "nativeloader_sky_hour" or name == "nativeloader_sky_direction" then
        if followNorth then
            -- Moving the time or the direction takes the sun off the map's: the other one keeps the
            -- map's value it shows.
            writing.nativeloader_sky_follow_map = "0"
            RunConsoleCommand("nativeloader_sky_follow_map", "0")
            followHours, followNorth = nil, nil
        end
        if name == "nativeloader_sky_hour" then clock = model.parseClock(value) or clock end
    elseif name == "nativeloader_sky_follow_map" then
        startClock()
    elseif name == "nativeloader_sky_time_passes" and value == "0" then
        -- Stopping the clock keeps the time it shows.
        write("nativeloader_sky_hour", string.format("%.2f", clock))
    elseif name == "nativeloader_sky_eclipse" and value ~= "" and not (enhanced.active and value == "solar") then
        -- An eclipse needs the right side of the horizon: a lunar one the night, a solar one the day.
        -- Choosing one moves the time there if it is not (and so off the map's sun).
        local elevation = now().sun.elevation
        local hours = (value == "lunar" and elevation > -8 and 0) or (value == "solar" and elevation < 15 and 12) or nil
        if hours then
            if followNorth then
                writing.nativeloader_sky_follow_map = "0"
                RunConsoleCommand("nativeloader_sky_follow_map", "0")
                followHours, followNorth = nil, nil
            end
            clock = hours
            write("nativeloader_sky_hour", string.format("%.2f", hours))
        elseif followNorth then
            startClock()
        end
    elseif (name == "nativeloader_sky_season" or name == "nativeloader_sky_moon" or name == "nativeloader_sky_eclipse"
        or name == "nativeloader_sky_eclipse_amount") and followNorth then
        startClock()
    elseif name == "nativeloader_weather" then
        setWeather(false)
    end
    apply()
    -- A map's own sky gives way to the RTX sky until the next map's start (ADR 0249, as ADR 0248 for an add-on's).
    syncEngine()
    syncSkyname()
end
for name in pairs(DEFAULTS) do cvars.AddChangeCallback(name, changed, "nativeloader_sky") end

-- This map's choice (ADR 0249): saved for the map, and shown at once. A change clears a take-over by a setting, so
-- the chosen sky shows again; but an add-on that sets its sky from Lua does so at the map's start, so going back to
-- its sky in the session keeps the RTX sky until the next map starts.
cvars.AddChangeCallback("nativeloader_sky_here", function(_, old, value)
    if writing.nativeloader_sky_here == value then
        writing.nativeloader_sky_here = nil
        return
    end
    if not clock then return end
    value = string.lower((string.gsub(value, "^%s*(.-)%s*$", "%1")))
    if value == "" then value = mapSky.AUTO end
    if not mapSky.validChoice(value) then
        local ids = {}
        for _, d in ipairs(files) do ids[#ids + 1] = d.id end
        MsgN("[nativeloader] nativeloader_sky_here: auto, rtx, map, addon" .. (#ids > 0 and (" or " .. table.concat(ids, ", ")) or ""))
        write("nativeloader_sky_here", choiceNow)
        return
    end
    local before = describe().shown
    choiceNow = value
    saveChoice(game.GetMap(), value)
    takenOver = false
    if resolution().sky == "addon" and before ~= "addon" and not overruled() then takenOver = true end
    refresh()
    MsgN("[nativeloader] sky: " .. message(false))
end, "nativeloader_sky")

local function start()
    -- The player's own time (Follow the map's sun unticked) and weather apply on every map from its
    -- start, also where the map's add-on sets a sky (ADR 0105, the user's item 44 of R16), but not
    -- over a fixed sky such as space (ADR 0248). Following the map keeps such an add-on's sky until a
    -- setting here changes (ADR 0031).
    takenOver, leaving = false, false
    ownFromStart = not cv.nativeloader_sky_follow_map:GetBool()
    followMapAddon()
    mapInfo = readMap()
    -- ADR 0249: the map's own sky, its sky files and the player's choice for it, before anything is sent.
    facts = mapInfo.facts
    files = readFiles(game.GetMap())
    choiceNow = loadChoices()[string.lower(game.GetMap())] or mapSky.AUTO
    write("nativeloader_sky_here", choiceNow)
    resolvedKey = nil
    enhanced.newMap()
    selectProvider()
    startClock()
    setWeather(true)
    refresh()
end

hook.Add("InitPostEntity", "nativeloader_sky", function()
    start()
    -- The RTX fixes' per-map settings set r_3dsky 0 a second after the map starts: the map's own 3D skybox again.
    timer.Simple(1.5, function() syncEngine() syncSkyname() end)
    -- Once more after the RTX fixes' per-map Remix settings (3-4 s after the map starts).
    timer.Simple(5, refresh)
    -- The chat line, once the map's add-ons have said whose the sky is (ADR 0249).
    timer.Simple(6, say)
end)

-- Leaving the map (a level change starts the client's Lua afresh, and a quit): the engine settings the map's own
-- 3D skybox changed go back, and the map's own sky name. The record stays until the next map's start has checked
-- them (syncEngine): a command sent while the map unloads may not run.
hook.Add("ShutDown", "nativeloader_sky", function()
    leaving = enhanced.active or enhanced.hasSavedVolume()
    if ready() and (enhanced.active or enhanced.hasSavedVolume()) then
        if enhanced.active and inCharge() then set("rtx.skyMode", "1") end
        enhanced.restoreLegacyVolume()
        enhanced.leave()
        releaseWeather()
    end
    for name, value in string.gmatch(engineSaved:GetString(), "([%w_]+)=([%w%.%-]*)") do
        for _, e in ipairs(ENGINE) do
            if e[1] == name then setEngine(name, value) end
        end
    end
    if skynameSaved and engineValue("sv_skyname") ~= skynameSaved then RunConsoleCommand("sv_skyname", skynameSaved) end
    skynameSaved = nil
end)

---------------------------------------------------------------- commands

-- Named times: the sun's height before or after noon on the chosen season's day.
local NAMED = {
    sunrise = { 1, true }, morning = { 25, true }, afternoon = { 35, false }, golden = { 8, false },
    sunset = { 0.5, false }, dusk = { -5, false },
}
local function namedTime(name)
    name = string.lower(name or "")
    if name == "noon" then return 12 end
    if name == "midnight" or name == "night" then return name == "night" and 23 or 0 end
    local n = NAMED[name]
    if n then return model.timeForElevation(n[1], n[2], season()) end
    return model.parseClock(name)
end

concommand.Add("nativeloader_sky_time", function(_, _, args)
    local hours = namedTime(args[1])
    if not hours then
        print("[nativeloader] nativeloader_sky_time: hh:mm, hours (0-24) or one of sunrise, morning, noon, "
            .. "afternoon, golden, sunset, dusk, night, midnight")
        return
    end
    RunConsoleCommand("nativeloader_sky_hour", string.format("%.2f", hours))
end)

concommand.Add("nativeloader_sky_reset", function()
    for name, value in pairs(DEFAULTS) do RunConsoleCommand(name, value) end
    print("[nativeloader] Sky and weather settings back to their defaults.")
end)

concommand.Add("nativeloader_sky_night_reset", function()
    for name in pairs(NIGHT_SETTINGS) do RunConsoleCommand(name, DEFAULTS[name]) end
    print("[nativeloader] Night sky editor settings back to their defaults.")
end)

concommand.Add("nativeloader_sky_status", function()
    local sky = now()
    local who = owner()
    print(string.format("[nativeloader] sky: %s; Remix API %s%s", physicalWanted() and "physical" or "the map's own",
        ready() and "ready" or "not available", who and ("; set by " .. who .. (fixed() and ", fixed" or "")
            .. (overruled() and ", taken over" or "")) or ""))
    -- ADR 0249: which sky this map shows, and why.
    local e, ids = describe(), {}
    for _, d in ipairs(files) do ids[#ids + 1] = d.id .. "(" .. d.kind .. (d.skyname and (" " .. d.skyname) or "") .. ")" end
    print(string.format("[nativeloader] this map: %s", message(false)))
    if enhanced.active then
        print(string.format("[nativeloader] Enhanced sky, NUMOS qualityLevel %s (0 high, 1 medium, 2 low)",
            sent["rtx.atmosphere.numos.qualityLevel"] or "unknown"))
    end
    print(string.format("[nativeloader] map sky: choice %s; shows %s (%s, %s)%s; own sky %s; 3D skybox %s; sky files %s; engine %s",
        choiceNow, e.shown, e.sky, e.reason, takenOver and ", taken over" or "", facts.own and "yes" or (facts.open and "no" or "no open sky"),
        facts.own3D and (string.format("scale %s", tostring(facts.scale)) .. (want3D() and ", shown" or "")) or "none",
        #ids > 0 and table.concat(ids, " ") or "none", engineSaved:GetString() ~= "" and engineSaved:GetString() or "as the session set it"))
    print(string.format("[nativeloader] time %s (%s)%s, %s; sun %.1f deg high at bearing %.1f; moon %.1f deg, %s",
        model.clock(clock or 0), cv.nativeloader_sky_follow_map:GetBool() and "the map's" or "chosen",
        cv.nativeloader_sky_time_passes:GetBool() and ", running" or "", cv.nativeloader_sky_season:GetString(),
        sky.sun.elevation, sky.sun.bearing, sky.moon.elevation,
        eclipse() and string.format("%s eclipse %d %%", eclipse(), cv.nativeloader_sky_eclipse_amount:GetInt())
            or cv.nativeloader_sky_moon:GetString()))
    if enhanced.active then
        print(string.format("[nativeloader] NUMOS catalogue stars and Moon, daytime brightness %.2f", moonByDay()))
    else
        print(string.format("[nativeloader] night sky %s; %s; moon by day %.2f", nightSkyImage() and "image" or "procedural",
            noHorizon() and "no horizon (the sky in every direction)" or "horizon", moonByDay()))
        local function v(name) return nightValue("nativeloader_sky_" .. name) end
        print(string.format("[nativeloader] night sky editor: image %.2f; stars %.2f (colour %.2f), constellations %.2f (%.2f), "
            .. "milky way %.2f (%.2f), nebulae %.2f (%.2f); simulated stars %.2f, density %.2f, twinkle %.2f",
            v("night_image"), v("stars_brightness"), v("stars_colour"), v("constellations_brightness"),
            v("constellations_colour"), v("milky_way_brightness"), v("milky_way_colour"), v("nebulae_brightness"),
            v("nebulae_colour"), v("simulated_brightness"), v("simulated_density"), v("simulated_twinkle")))
        print(string.format("[nativeloader] night sky editor: moon %.2f, %.2f deg, glow %.2f, earthshine %.2f; "
            .. "shooting stars %.1f a minute at %.2f; night glow %.2f", v("moon_brightness"), v("moon_size"), v("moon_glow"),
            v("earthshine"), v("shooting_stars"), v("shooting_star_brightness"), v("night_glow")))
    end
    local info = mapInfo or {}
    print(string.format("[nativeloader] map sky %q%s; map sun %s", info.skyname or "", info.mood and (" (" .. info.mood .. ")") or "",
        info.sun and string.format("%.1f deg high at bearing %.1f", info.sun.elevation, info.sun.bearing) or "none"))
    print(string.format("[nativeloader] weather %s", weather.name or "left to Remix"))
end)

---------------------------------------------------------------- the panel

NATIVELOADER_SKY = {
    clock = function() return clock end,
    enhanced = function() return enhanced.active end,
    -- The sun, moon and stars as given to Remix now (sky_model.sky's table). RemixConfig's
    -- GetConfigVariable reads rtx.conf from disk, not these live values.
    sky = function() return now() end,
    owner = owner,
    -- Whether the player's sky replaces a map's add-on's sky now (ADR 0248): an add-on that answers
    -- NativeLoaderSkyFixed sets its sky only while this is false. ADR 0249: also true once the player chose another
    -- sky for the map (nativeloader_sky_here).
    takenOver = function() return overruled() end,
    -- Which sky this map shows (ADR 0249): shown ("rtx", "own", "addon" or "taken"), sky, reason, threeD, the title of
    -- the map's RTX version's sky (package), the player's choice, the map's own sky and its sky files.
    mapSky = function()
        local e = describe()
        local ids = {}
        for _, d in ipairs(files) do ids[#ids + 1] = d.id end
        return { shown = e.shown, sky = e.sky, reason = e.reason, threeD = want3D(), package = e.package,
            choice = choiceNow, own = facts.own, own3D = facts.own3D, scale = facts.scale, files = ids }
    end,
    -- The chat line's words for the sky now, in English (the console's) or translated.
    line = function(translate) return message(translate == true) end,
    ready = ready,
    model = model,
    presets = presets,
}

local WEATHERS = {
    { N("Clear"), "clear" }, { N("Partly cloudy"), "partlyCloudy" }, { N("Overcast"), "overcast" },
    { N("Hazy"), "hazy" }, { N("Foggy"), "foggy" }, { N("Drizzle"), "drizzle" }, { N("Rain"), "rainstorm" },
    { N("Thunderstorm"), "thunderstorm" }, { N("Snow"), "snow" }, { N("Blizzard"), "blizzard" },
    { N("Sandstorm"), "sandstorm" }, { N("Smog"), "smoggy" },
}
local SEASONS = { { N("Spring"), "spring" }, { N("Summer"), "summer" }, { N("Autumn"), "autumn" }, { N("Winter"), "winter" } }
local MOONS = { { N("New moon"), "new" }, { N("Waxing crescent"), "waxingCrescent" },
    { N("First quarter"), "firstQuarter" }, { N("Waxing gibbous"), "waxingGibbous" }, { N("Full moon"), "full" },
    { N("Waning gibbous"), "waningGibbous" }, { N("Last quarter"), "lastQuarter" },
    { N("Waning crescent"), "waningCrescent" } }
local ECLIPSES = { { N("No eclipse"), "" }, { N("Lunar eclipse"), "lunar" }, { N("Solar eclipse"), "solar" } }
local STARS = { { N("Night sky image"), "map" }, { N("Simulated stars"), "procedural" } }
-- One row of buttons, about 55 pixels each: short names.
local TIMES = { { N("Sunrise"), "sunrise" }, { N("Morning"), "morning" }, { N("Noon"), "noon" },
    { N("Sunset"), "sunset" }, { N("Night"), "night" } }

local function combo(panel, label, name, choices)
    local box = panel:ComboBox(L(label), name)
    for _, choice in ipairs(choices) do box:AddChoice(L(choice[1]), choice[2]) end
    return box
end

local function buildPanel(panel)
    if not ready() then
        panel:Help(L("The Remix API is not available in this session, so these settings cannot be applied. Run nativeloader_status for details."))
    end
    local who = owner()
    if who and fixed() then
        panel:Help(string.format(L("On this map %s keeps a sky of its own, such as space, that no time of day or weather fits. It keeps that sky until a setting here is changed; your settings then replace it until the next map."), who))
    elseif who then
        panel:Help(string.format(L("On this map %s also sets the sky. It keeps its sky while Follow the map's sun is ticked and nothing here is changed; otherwise your settings here replace it."), who))
    end
    -- ADR 0249: which sky this map shows, the choice for this map and the one for other maps.
    local function stateText()
        local e = describe()
        local text = sentence(mapSky.state(e, facts), true)
        local limit = sentence(mapSky.limit(e, facts), true)
        if limit then text = text .. " " .. limit end
        if enhanced.inVR() then text = text .. " " .. L("Enhanced sky is unavailable in VR. The RTX sky uses Standard.") end
        return text
    end
    local stateLabel = panel:Help(stateText())
    local stateThink = stateLabel.Think
    local standardOnly, wasEnhanced = {}, nil
    stateLabel.Think = function(self)
        local text = stateText()
        if self:GetText() ~= text then self:SetText(text) end
        if wasEnhanced ~= enhanced.active then
            for _, control in ipairs(standardOnly) do control:SetEnabled(not enhanced.active) end
            wasEnhanced = enhanced.active
        end
        if stateThink then stateThink(self) end
    end
    local here = panel:ComboBox(L("This map"), "nativeloader_sky_here")
    for _, c in ipairs(mapSky.choices({ facts = facts, files = files, addon = knownAddon, single = singlePlayer() })) do
        here:AddChoice(string.format(L(c[2]), c[3] or ""), c[1])
    end
    panel:ControlHelp(L("Remembered for this map. Automatic shows the sky of the map's RTX version where it has one, else the choice under Other maps."))
    if not facts.own then panel:ControlHelp(L("This map has no sky of its own to switch to.")) end
    local sky = panel:ComboBox(L("Other maps"), "nativeloader_sky")
    sky:AddChoice(L("RTX sky"), "1")
    sky:AddChoice(L("Their own sky"), "0")
    panel:ControlHelp(L("The RTX sky has a sun, clouds, stars and a moon, and lights the map from them. A map's own sky shows its sky textures and, where it has one, its 3D skybox."))
    panel:CheckBox(L("Say which sky shows"), "nativeloader_sky_message")
    panel:ControlHelp(L("A chat line at each map's start says which sky shows and how to switch."))
    combo(panel, N("Sky quality"), "nativeloader_sky_enhanced", {{N("Standard"), "0"}, {N("Enhanced"), "1"}})
    panel:ControlHelp(L("Enhanced, the default, adds denser clouds, sun rays and lit mist when the RTX sky is showing. Choose Standard for the Night sky editor's layers and shooting stars."))
    combo(panel, N("Enhanced detail"), "nativeloader_sky_enhanced_quality",
        {{N("Automatic"), "auto"}, {N("High"), "high"}, {N("Medium"), "medium"}, {N("Low"), "low"}})
    panel:ControlHelp(L("Automatic uses the loader's performance tier for clouds and mist."))
    panel:ControlHelp(L("Shape clouds, air and light in the Enhanced sky editor. Both skies use Moon size and Moon brightness from the Night sky editor."))
    panel:Help(L("Time of day, weather and the night sky are the RTX sky's. On a map that shows another sky, changing one of them shows the RTX sky until the next map starts."))
    standardOnly[1] = panel:CheckBox(L("No horizon"), "nativeloader_sky_no_horizon")
    panel:ControlHelp(L("For maps that float in the sky or in space: below the horizon the sky goes on, with clouds, the stars and the moon, instead of the haze of a ground."))
    panel:CheckBox(L("Follow the map's sun"), "nativeloader_sky_follow_map")
    panel:ControlHelp(L("Puts the sun where the map's own sun is; on a map whose add-on sets its own sky, such as Modern House RTX, keeps that sky. Moving Time of day or Sun direction turns this off."))
    panel:NumSlider(L("Time of day"), "nativeloader_sky_hour", 0, 24, 2)
    local nowLabel = panel:Help("")
    local think = nowLabel.Think
    nowLabel.Think = function(self)
        local text = clock and string.format(L("Now %s"), model.clock(clock)) or ""
        if self:GetText() ~= text then self:SetText(text) end
        if think then think(self) end
    end
    local row = vgui.Create("DPanel", panel)
    row:SetPaintBackground(false)
    row:SetTall(22)
    for _, t in ipairs(TIMES) do
        local button = vgui.Create("DButton", row)
        button:SetText(L(t[1]))
        button.DoClick = function() RunConsoleCommand("nativeloader_sky_time", t[2]) end
    end
    row.PerformLayout = function(self, w)
        local buttons = self:GetChildren()
        local width = math.floor((w - (#buttons - 1) * 4) / #buttons)
        for i, b in ipairs(buttons) do b:SetPos((i - 1) * (width + 4), 0) b:SetSize(width, 22) end
    end
    panel:AddItem(row)
    panel:NumSlider(L("Sun direction"), "nativeloader_sky_direction", 0, 360, 0)
    panel:ControlHelp(L("Turns the sun's path around the sky."))
    panel:CheckBox(L("Time passes"), "nativeloader_sky_time_passes")
    panel:NumSlider(L("Day length (min)"), "nativeloader_sky_day_minutes", 2, 240, 0)
    panel:ControlHelp(L("Time passes is on by default. A whole day takes 20 real minutes; untick Time passes to stop the clock."))
    panel:NumSlider(L("Sky update interval (s)"), "nativeloader_sky_interval", 0, 0.25, 3)
    panel:ControlHelp(L("How often the sun, moon, stars and weather move, in seconds: 0.02 is 50 times a second, 0 is every frame. A longer interval costs a little less frame time, but the sky moves in steps."))
    combo(panel, N("Season"), "nativeloader_sky_season", SEASONS)
    combo(panel, N("Moon"), "nativeloader_sky_moon", MOONS)
    panel:NumSlider(L("Moon by day"), "nativeloader_sky_moon_day", 0, 4, 2)
    panel:ControlHelp(L("How bright the moon is while the sun is up. At 1 it is as bright as the real Moon: a pale disc over the blue sky, a quarter clear in the afternoon, a crescent faint near the sun. Higher makes it stand out; 0 hides it by day."))
    combo(panel, N("Eclipse"), "nativeloader_sky_eclipse", ECLIPSES)
    panel:NumSlider(L("Eclipse progress"), "nativeloader_sky_eclipse_amount", 0, 100, 0)
    panel:ControlHelp(L("From first contact (0) to the middle (100): a lunar eclipse is total from 70, a solar one from 90. An eclipse sets the moon's phase, and the time if the sun is on the wrong side of the horizon for it."))
    standardOnly[2] = combo(panel, N("Night sky"), "nativeloader_sky_stars", STARS)
    panel:ControlHelp(L("Night sky image: sharp stars, a galaxy and nebulae, turning with the time and the season."))
    panel:ControlHelp(L("The Night sky editor, next to this page, sets how each part of the night sky looks."))
    local box = panel:ComboBox(L("Weather"), "nativeloader_weather")
    box:AddChoice(L("(leave to Remix)"), "")
    for _, choice in ipairs(WEATHERS) do box:AddChoice(L(choice[1]), choice[2]) end
    panel:ControlHelp(L("Clouds, haze, fog, rain and snow, from Remix's own weather presets."))
    panel:NumSlider(L("Weather change (s)"), "nativeloader_weather_seconds", 0, 300, 0)
    panel:ControlHelp(L("How long a change of weather takes."))
    panel:Button(L("Reset the sky and weather"), "nativeloader_sky_reset")
end

-- The night sky editor (ADR 0227): each element of the night sky on its own. The image's four layers, the
-- simulated stars, the moon, the shooting stars and the night's glow; brightness and colour as multiples of how
-- each is drawn.
local function slider(panel, label, name, decimals)
    local entry = NIGHT_SETTINGS[name]
    return panel:NumSlider(L(label), name, entry[3], entry[4], decimals or 2)
end

local function buildNightPanel(panel)
    panel:Help(L("Enhanced uses Moon size and Moon brightness from this page. Brightness changes the lunar disc. Adjust moonlight on the ground in the Enhanced sky editor."))
    if not ready() then
        panel:Help(L("The Remix API is not available in this session, so these settings cannot be applied. Run nativeloader_status for details."))
    end
    panel:Help(L("How each part of the night sky looks. Brightness: 1 is as drawn, 0 hides it. Colour: 0 is grey, 1 as drawn, 2 stronger. Look up at the night sky while you drag."))
    panel:Button(L("Go to night"), "nativeloader_sky_time", "night")
    panel:CheckBox(L("Time passes"), "nativeloader_sky_time_passes")
    panel:ControlHelp(L("Untick Time passes to keep the night while you edit."))
    combo(panel, N("Night sky"), "nativeloader_sky_stars", STARS)

    panel:Help(L("Night sky image"))
    slider(panel, N("All layers"), "nativeloader_sky_night_image")
    slider(panel, N("Stars"), "nativeloader_sky_stars_brightness")
    slider(panel, N("Star colour"), "nativeloader_sky_stars_colour")
    slider(panel, N("Constellations"), "nativeloader_sky_constellations_brightness")
    slider(panel, N("Constellation colour"), "nativeloader_sky_constellations_colour")
    panel:ControlHelp(L("The constellations' bright blue and violet stars. They come out with the first stars at dusk; the Milky Way and the nebulae wait for full darkness."))
    slider(panel, N("Milky Way"), "nativeloader_sky_milky_way_brightness")
    slider(panel, N("Milky Way colour"), "nativeloader_sky_milky_way_colour")
    slider(panel, N("Nebulae"), "nativeloader_sky_nebulae_brightness")
    slider(panel, N("Nebula colour"), "nativeloader_sky_nebulae_colour")
    panel:ControlHelp(L("A part at 0 is hidden, and its texture leaves video memory."))

    panel:Help(L("Simulated stars"))
    panel:ControlHelp(L("Used when Night sky is set to Simulated stars."))
    slider(panel, N("Brightness"), "nativeloader_sky_simulated_brightness")
    slider(panel, N("Density"), "nativeloader_sky_simulated_density")
    slider(panel, N("Twinkle"), "nativeloader_sky_simulated_twinkle")

    panel:Help(L("Moon"))
    slider(panel, N("Brightness"), "nativeloader_sky_moon_brightness")
    panel:ControlHelp(L("The moon's disc and its light on the map."))
    slider(panel, N("Size (degrees)"), "nativeloader_sky_moon_size")
    panel:ControlHelp(L("How wide the moon looks: the real Moon is about 0.5 degrees. Its light on the map stays the same. A larger moon passes further from Earth's shadow, so it moves a little in the sky; eclipses follow its size."))
    slider(panel, N("Glow"), "nativeloader_sky_moon_glow")
    slider(panel, N("Earthshine"), "nativeloader_sky_earthshine")
    panel:ControlHelp(L("Glow: the halo around the moon. Earthshine: the faint light on its dark side, clearest at a crescent."))

    panel:Help(L("Shooting stars"))
    slider(panel, N("Per minute"), "nativeloader_sky_shooting_stars", 1)
    slider(panel, N("Brightness"), "nativeloader_sky_shooting_star_brightness")

    panel:Help(L("Night glow"))
    slider(panel, N("Brightness"), "nativeloader_sky_night_glow")
    panel:ControlHelp(L("The faint glow of the night air between the stars, from the weather. At 0 the space between the stars is black."))
    panel:Button(L("Reset the night sky"), "nativeloader_sky_night_reset")
end

NATIVELOADER_SKY.buildPanel = buildPanel
NATIVELOADER_SKY.buildNightPanel = buildNightPanel
local editorPanel = include("nativeloader/enhanced_editor_panel.lua")
local function buildEnhancedPanel(panel)
    editorPanel(panel, enhanced.editor, WEATHERS, weatherName, enhanced.inVR, cv.nativeloader_sky_enhanced)
end
NATIVELOADER_SKY.buildEnhancedPanel = buildEnhancedPanel

hook.Add("PopulateToolMenu", "nativeloader_sky", function()
    spawnmenu.AddToolMenuOption("RTX Remix", N("Sky and weather"), "nativeloader_sky", L("Sky and weather"), "", "", buildPanel)
    spawnmenu.AddToolMenuOption("RTX Remix", N("Sky and weather"), "nativeloader_sky_night", L("Night sky editor"), "", "",
        buildNightPanel)
    spawnmenu.AddToolMenuOption("RTX Remix", N("Sky and weather"), "nativeloader_sky_editor", L("Enhanced sky editor"), "", "",
        buildEnhancedPanel)
end)
