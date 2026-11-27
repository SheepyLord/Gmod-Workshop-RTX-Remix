-- Companion controls for the NUMOS sky. All option names below the prefix are from the round 1 contract.
local weather = include("nativeloader/enhanced_weather.lua")
local prefix = "rtx.atmosphere.numos."

local function inVR()
    local state = NativeLoaderVR and NativeLoaderVR.state
    return state == "starting" or state == "running" or state == "stopping"
end

local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end

-- A layer appearing or clearing fades at its own height. This also applies if a second choice interrupts a blend.
local function holdLayer(off, on, layer, shape)
    local enable, cover = layer .. "Enable", layer .. "CoverageMean"
    if (off[enable] and off[cover] > 0) or not on[enable] or on[cover] <= 0 then return end
    off[layer .. "CoverageMean"] = 0
    for _, field in ipairs(shape) do off[layer .. field] = on[layer .. field] end
end

local layers = {
    cloudLayer2 = {"BaseHeightMeters", "DepthMeters", "TypeMean", "DensityScale"},
    cloudCirrus = {"BaseHeightMeters", "OpticalDepth", "StreakDirection"},
}

-- Convert the Remix settings page's four fog values to NUMOS height fog. Remix gamma-decodes
-- transmittance only. NUMOS measures visibility at 2% contrast and takes one scattering albedo.
local function presetFog(values, sceneScale)
    local extinction, albedo = 0, 0
    for c in values[1]:gmatch("[%d.]+") do
        local v = tonumber(c)
        local linear = v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
        extinction = extinction - math.log(linear) / 3
    end
    for c in values[3]:gmatch("[%d.]+") do albedo = albedo + tonumber(c) / 3 end
    return {fogVisibilityMeters = -math.log(0.02) * tonumber(values[2]) * 1.905 * sceneScale / extinction,
        fogAlbedo = albedo, fogAnisotropy = tonumber(values[4])}
end

return function(model, set, configured, remixDefaults, forget)
    local E = {active = false, inVR = inVR}
    local editor = include("nativeloader/enhanced_editor.lua")(weather)
    E.editor = editor
    local saved = CreateClientConVar("nativeloader_sky_volumetrics_saved", "", false, false,
        "A remaining round 1 volumetrics snapshot, restored once")
    local mapCount = CreateClientConVar("nativeloader_sky_numos_world", "0", false, false,
        "Last map for which the Enhanced sky measured ground, for this process only")
    local world
    local tier, from, to, target, began, duration, releaseAt, selected
    local previous, fog, fogValues = {}, nil, nil
    local nearFog, scale = {}, nil
    local rainFrom, rainTo, rainAt, rainSeconds = 0, 0, 0, 0
    local rainbow, mist = 1, 0
    -- None matches no built-in preset. An empty string passed to RemixConfig is a successful no-op.
    local defaults = {["weather.followGame"] = "True", ["weather.preset"] = "None", ["weather.transitionSeconds"] = "10"}
    for key, value in pairs(weather.defaults) do defaults[key] = model.optionText(value) end

    local function send(key, value)
        set(prefix .. key, model.optionText(value))
    end

    -- Only owned weather settings return to their configured values on "(leave to Remix)" or exit.
    local function weatherOption(key, value)
        if previous[key] == nil then previous[key] = configured(prefix .. key) or defaults[key] end
        set(prefix .. key, value)
    end

    local function release(key)
        if previous[key] ~= nil and set(prefix .. key, previous[key]) then previous[key] = nil end
    end

    local function current(t)
        local p = duration > 0 and model.ease((t - began) / duration) or 1
        if p >= 1 then return copy(target) end
        if p <= 0 then return copy(from) end
        local result = {}
        for key, b in pairs(to) do
            local a = from[key]
            if type(b) == "boolean" then
                result[key] = a or b
            elseif key == "fogVisibilityMeters" then
                -- Zero visibility in NUMOS means no extinction (unlimited visibility).
                local extinction = (a > 0 and (1 - p) / a or 0) + (b > 0 and p / b or 0)
                result[key] = extinction > 0 and 1 / extinction or 0
            elseif key == "cloudWindDirection" or key == "cloudCirrusStreakDirection" then
                result[key] = model.blend("angle", a, b, p)
            else
                result[key] = model.blend("scalar", a, b, p)
            end
        end
        return result
    end

    local function releaseLook()
        from, to, target, releaseAt = nil, nil, nil, nil
        for key in pairs(previous) do if not (fog and fog[key]) then release(key) end end
    end

    local function transition(values, t, seconds)
        if not values and (not target or seconds == 0) then releaseLook() return end
        releaseAt = not values and t + seconds or nil
        values = values or editor.baseline(previous, configured, prefix)
        from = target and current(t) or (seconds > 0 and editor.baseline(previous, configured, prefix) or copy(values))
        target, to, began, duration = copy(values), copy(values), t, seconds
        for layer, shape in pairs(layers) do
            holdLayer(from, to, layer, shape)
            holdLayer(to, from, layer, shape)
        end
    end

    function E.selectWeather(name, t, seconds)
        selected = name
        if editor.own() then
            if not target then transition(editor.look(), t, 0) end
        else
            transition(weather.presets[name], t, name and seconds or 0)
        end
    end

    function E.editLook(action, key, t)
        if action ~= "edit" then
            transition(editor.own() and editor.look() or weather.presets[selected], t, 2)
        end
        if action == "edit" or action == "firstEdit" then
            -- A drag takes effect now, even halfway through loading another look. Other keys finish their blend.
            local value = editor.value(editor.fields[key])
            target[key], to[key], from[key] = value, value, value
        end
    end

    local function wetness(t)
        if rainSeconds <= 0 then return rainTo end
        local p = math.Clamp((t - rainAt) / rainSeconds, 0, 1)
        return rainFrom + (rainTo - rainFrom) * p
    end

    function E.rain(name, intensity, t, seconds)
        local raining = name == "drizzle" or name == "rainstorm" or name == "thunderstorm"
        local level = raining and math.Clamp(intensity, 0, 1) or 0
        if rainTo == level then return end
        rainFrom, rainTo, rainAt = wetness(t), level, t
        rainSeconds = raining and seconds or 300
    end

    local function sceneScale()
        if not scale then
            local configuredScale = tonumber(configured("rtx.sceneScale"))
            scale = configuredScale and configuredScale > 0 and configuredScale or 1
        end
        return scale
    end

    local function releaseNear()
        for key, before in pairs(nearFog) do
            if fog then forget(key) end -- the Remix settings page just wrote its own preset
            if fog or set(key, before) then nearFog[key] = nil end
        end
    end
    local function nearOption(name, text)
        local key = "rtx.volumetrics." .. name
        if not nearFog[key] then nearFog[key] = configured(key) or remixDefaults[key] or "False" end
        set(key, text)
    end
    local function pushNear(values)
        if mist ~= 1 or fog or not values then releaseNear() return end
        -- At the NUMOS visibility, 2% of contrast survives. Remix takes sRGB transmittance
        -- at a measuring distance in its own metres. A white medium at any distance is clear.
        local vis, albedo = values.fogVisibilityMeters, values.fogAlbedo
        local c = vis > 0 and (1.055 * 0.02 ^ (1 / 2.4) - 0.055) or 1
        nearOption("enableFogRemap", "False")
        nearOption("transmittanceColor", model.optionText({c, c, c}))
        nearOption("transmittanceMeasurementDistanceMeters", model.optionText(vis > 0 and vis / (1.905 * sceneScale()) or 1))
        nearOption("singleScatteringAlbedo", model.optionText({albedo, albedo, albedo}))
        nearOption("anisotropy", model.optionText(values.fogAnisotropy))
    end

    -- The preset remains the owner's when weather is left to Remix. While the companion supplies a
    -- weather, send its settings directly: an adapter-selected preset would mask the tuned values.
    function E.pushWeather(t, name, wander)
        send("rainbow.strength", wetness(t) * rainbow)
        if releaseAt and t >= releaseAt then releaseLook() end
        local values
        if target then
            weatherOption("weather.followGame", "False")
            weatherOption("weather.transitionSeconds", "0")
            weatherOption("weather.preset", "None")
            values = current(t)
            wander(values, t, name or "partlyCloudy")
            for key, value in pairs(values) do
                weatherOption(key, model.optionText(fog and fog[key] or value))
            end
        elseif fog then
            for key, value in pairs(fog) do
                weatherOption(key, model.optionText(value))
            end
        end
        pushNear(values)
    end

    function E.updateFog()
        local values = hook.Run("NativeLoaderRemixFogValues")
        if values == fogValues then return end
        fogValues = values
        if values then
            fog = presetFog(values, sceneScale())
        else
            if not target then for key in pairs(fog) do release(key) end end
            fog = nil
        end
    end

    function E.restoreLegacyVolume()
        local value = saved:GetString()
        if value == "" then return end
        if (value ~= "True" and value ~= "False") or set("rtx.volumetrics.enable", value) then saved:SetString("") end
    end
    function E.enter() E.active = true end

    function E.leave()
        E.active = false
        releaseNear()
        from, to, target, releaseAt, fog, fogValues = nil, nil, nil, nil, nil, nil
        for key in pairs(previous) do release(key) end
    end

    function E.hasSavedVolume() return saved:GetString() ~= "" end
    function E.newMap()
        world, scale = nil, nil
        rainFrom, rainTo, rainAt, rainSeconds = 0, 0, 0, 0
    end

    function E.moonLatitude(kind, amount, radius)
        if kind ~= "lunar" then return model.moonLatitude(nil, amount, radius) end
        -- NUMOS sunVisibleFromMoon uses the Sun and Earth's radii as seen from the Moon.
        -- First contact at 0%, complete shadow at 70%, centre at 100% on the existing slider.
        local earth = math.deg(math.asin(1 / 60.27)) * 1.015
        local sun = 0.2666
        if amount < 0.7 then return earth + sun - 2 * sun * amount / 0.7 end
        return (earth - sun) * (1 - amount) / 0.3
    end

    function E.pushSky(quality, moonSize, moonBrightness)
        if not tier and not weather.mode[quality] then
            local body = file.Read("native-loader/status.json", "DATA")
            local status = body and util.JSONToTable(body)
            local activation = istable(status) and status.schema == 1 and status.activation
            local report = istable(activation) and activation.performance_tier
            tier = istable(report) and report.tier or "medium"
        end
        if not world then
            world = tostring(mapCount:GetInt() % 2147483646 + 1)
            mapCount:SetString(world)
        end
        set(prefix .. "worldChangeCount", world)
        set("rtx.skyMode", "2")
        set("rtx.ignoreGameDirectionalLights", "True")
        local detail = weather.mode[quality] or weather.mode[tier]
        if not detail or not detail.qualityLevel then detail = weather.mode.medium end
        for key, value in pairs(weather.mode.common) do if not editor.styles[key] then send(key, value) end end
        for key, value in pairs(detail) do if not editor.styles[key] then send(key, value) end end
        for _, f in ipairs(editor.style) do
            local value = editor.value(f)
            if f.key == "rainbow.strength" then rainbow = value else send(f.key, value) end
            if f.key == "rays.strength" then send("rays.enable", value > 0) end
            if f.key == "volumetrics" then mist = value end
        end
        send("latitudeDegrees", model.LATITUDE)
        send("moon0.angularDiameter", moonSize)
        send("moonDiscGainStops", moonBrightness > 0 and math.max(-16, math.log(moonBrightness) / math.log(2)) or -16)
    end

    function E.celestial(sky, hours, day, north, lunar, daytime)
        send("timeOfDayHours", hours)
        send("dayOfYear", day)
        send("northOffsetDegrees", north)
        send("sunElevation", sky.sun.elevation)
        send("sunRotation", sky.sun.bearing)
        send("moon0.elevation", sky.moon.elevation)
        send("moon0.rotation", sky.moon.bearing)
        -- NUMOS computes the Earth's shadow only for a moon lit by the actual sun (negative phase).
        send("moon0.phase", lunar and -1 or sky.moon.phase)
        local brightness = sky.sun.elevation > 0 and daytime or 1
        send("moon0.enabled", brightness > 0)
        send("moon0.color", {brightness, brightness, brightness})
    end

    return E
end
