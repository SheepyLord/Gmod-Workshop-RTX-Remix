-- QA probe for the Night sky editor (ADR 0227): a clear midnight with the clock held, then each element of the night
-- sky changed on its own and screenshots of the same views after each step (NL_SHOT, answered by the session driver
-- with nl_shot_taken <n>): the defaults; the constellations hidden, then bright and white; the stars bright and grey;
-- the Milky Way alone; the nebulae alone; every layer off; the whole image brighter; the moon larger, brighter and
-- glowing (viewed where it stands); the editor's reset. The view is turned by a CalcView hook from a place under open
-- sky near the spawn; HUD and view model are hidden. Prints NL_NIGHT lines with the sky's state. The player's sky and
-- editor settings (archived) are put back before NL_SHOT_DONE.
local SKY = NATIVELOADER_SKY
local function openSky()
    local base = LocalPlayer():GetPos()
    for radius = 0, 6000, 200 do
        for bearing = 0, 345, radius == 0 and 360 or 15 do
            local p = base + Vector(math.cos(math.rad(bearing)) * radius, math.sin(math.rad(bearing)) * radius, 0)
            local down = util.TraceLine({start = p + Vector(0, 0, 300), endpos = p - Vector(0, 0, 3000), mask = MASK_SOLID_BRUSHONLY})
            if down.Hit and not down.StartSolid and not down.HitSky then
                local eye = down.HitPos + Vector(0, 0, 72)
                local open = 0
                for yaw = 0, 315, 45 do
                    local dir = Angle(-50, yaw, 0):Forward()
                    if util.TraceLine({start = eye, endpos = eye + dir * 30000, mask = MASK_SOLID_BRUSHONLY}).HitSky then open = open + 1 end
                end
                local up = util.TraceLine({start = eye, endpos = eye + Vector(0, 0, 30000), mask = MASK_SOLID_BRUSHONLY})
                if up.HitSky and open >= 6 then return eye, open end
            end
        end
    end
end
local place, open = openSky()
print("NL_NIGHT place " .. tostring(place) .. " open " .. tostring(open))

-- The views: the zenith wide, and two bearings 45 degrees up; the moon's own view is set when it is shown. At 1280x720
-- and these fields of view a pixel spans 14-17 texels across of the star layer (about 200 a degree), whose small stars
-- then average into a faint haze; the star steps at the end look through 35 degrees (about 5 texels a pixel).
local VIEWS = { { -89.9, 0, 110, "zenith" }, { -45, 0, 90, "east" }, { -45, 180, 90, "west" } }
local NARROW = { { -70, 135, 35, "narrow" } }
local view
hook.Add("CalcView", "nl_night_sky_editor_probe", function(_, origin, _, fov)
    if not view then return end
    return {origin = place or origin, angles = Angle(view[1], view[2], 0), fov = view[3], drawviewer = false}
end)
hook.Add("HUDShouldDraw", "nl_night_sky_editor_probe", function() if view then return false end end)
hook.Add("PreDrawViewModel", "nl_night_sky_editor_probe", function() if view then return true end end)

-- The editor's settings and the sky's, put back at the end (they are archived).
local KEPT = { "nativeloader_weather_seconds", "nativeloader_weather", "nativeloader_sky_follow_map", "nativeloader_sky_hour",
    "nativeloader_sky_time_passes", "nativeloader_sky_moon" }
local EDITOR = { "night_image", "stars_brightness", "stars_colour", "constellations_brightness", "constellations_colour",
    "milky_way_brightness", "milky_way_colour", "nebulae_brightness", "nebulae_colour", "moon_brightness", "moon_size",
    "moon_glow", "earthshine", "shooting_stars", "shooting_star_brightness", "night_glow" }
for _, name in ipairs(EDITOR) do KEPT[#KEPT + 1] = "nativeloader_sky_" .. name end
local kept = {}
for _, name in ipairs(KEPT) do
    local cv = GetConVar(name)
    kept[name] = cv and cv:GetString() or nil
end
print("NL_NIGHT kept " .. util.TableToJSON(kept))

local function set(values)
    for name, value in pairs(values) do RunConsoleCommand("nativeloader_sky_" .. name, tostring(value)) end
end
local function moonView()
    local moon = SKY and SKY.sky and SKY.sky().moon
    if not moon then return { -60, 0, 40, "moon" } end
    -- A bearing is clockwise from the map's north (+Y); GMod's yaw is counter-clockwise from +X.
    return { -moon.elevation, 90 - moon.bearing, 40, "moon" }
end

-- The steps: a label, the settings to change, the views.
local STEPS = {
    { "default", {}, VIEWS },
    { "constellations0", { constellations_brightness = 0 }, VIEWS },
    { "constellations6white", { constellations_brightness = 6, constellations_colour = 0 }, VIEWS },
    { "stars4grey", { constellations_brightness = 1, constellations_colour = 1, stars_brightness = 4, stars_colour = 0 }, VIEWS },
    { "milkyway_alone4", { stars_brightness = 0, stars_colour = 1, constellations_brightness = 0, nebulae_brightness = 0,
        milky_way_brightness = 4 }, VIEWS },
    { "nebulae_alone4", { milky_way_brightness = 0, nebulae_brightness = 4, nebulae_colour = 1.5 }, VIEWS },
    { "all_off", { nebulae_brightness = 0, nebulae_colour = 1 }, VIEWS },
    { "image3", { stars_brightness = 1, constellations_brightness = 1, milky_way_brightness = 1, nebulae_brightness = 1,
        night_image = 3 }, VIEWS },
    { "moon_default", { night_image = 1 }, "moon" },
    { "moon_big", { moon_size = 4, moon_brightness = 2, moon_glow = 3 }, "moon" },
    { "reset", "reset", VIEWS },
    { "stars_default", {}, NARROW },
    { "stars4", { stars_brightness = 4 }, NARROW },
    { "stars0", { stars_brightness = 0 }, NARROW },
    { "stars2grey", { stars_brightness = 2, stars_colour = 0 }, NARROW },
}

local step, shot, shots = 0, 0, nil
local function finish()
    view = nil
    for _, name in ipairs(KEPT) do
        if kept[name] then RunConsoleCommand(name, kept[name]) end
    end
    timer.Simple(1, function() print("NL_SHOT_DONE") end)
end
local nextShot
local function nextStep()
    step = step + 1
    local s = STEPS[step]
    if not s then return finish() end
    if s[2] == "reset" then RunConsoleCommand("nativeloader_sky_night_reset") else set(s[2]) end
    shots = s[3] == "moon" and { moonView() } or s[3]
    shot = 0
    -- A changed layer may load its texture; the image settles in the upscaler's history.
    timer.Simple(1.5, function()
        RunConsoleCommand("nativeloader_sky_status")
        nextShot()
    end)
end
nextShot = function()
    shot = shot + 1
    local v = shots[shot]
    if not v then return nextStep() end
    view = v
    timer.Simple(2.5, function() print(string.format("NL_SHOT %s_%s", STEPS[step][1], v[4])) end)
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.2, nextShot) end)

RunConsoleCommand("nativeloader_weather_seconds", "0")
RunConsoleCommand("nativeloader_weather", "clear")
RunConsoleCommand("nativeloader_sky_time_passes", "0")
RunConsoleCommand("nativeloader_sky_moon", "full")
RunConsoleCommand("nativeloader_sky_time", "0")
set({ night_image = 1, stars_brightness = 1, stars_colour = 1, constellations_brightness = 1, constellations_colour = 1,
    milky_way_brightness = 1, milky_way_colour = 1, nebulae_brightness = 1, nebulae_colour = 1, moon_brightness = 1,
    moon_size = 1.6, moon_glow = 1, earthshine = 1, shooting_stars = 1.2, shooting_star_brightness = 1, night_glow = 1 })
timer.Simple(8, nextStep)
