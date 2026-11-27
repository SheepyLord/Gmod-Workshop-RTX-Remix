-- The Enhanced sky editor's schema. A look contains just these weather keys, in NUMOS units.
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N
local builtins = include("nativeloader/enhanced_builtin_looks.lua")
local folder = "nativeloader_companion/sky_looks/"
local limit = 8192

local function field(key, low, high, decimals, label, help, kind)
    return {key = key, min = low, max = high, decimals = decimals, label = label, help = help, kind = kind or "number"}
end

local groups = {
    {N("Clouds"), {
        field("cloudCoverageMean", 0, 1, 2, N("Cloud cover"), N("0 clears the main layer. At 1 it covers most of the sky.")),
        field("cloudCoverageSpread", 0, 1, 2, N("Gaps and banks"), N("Raise this to put clear gaps next to crowded banks of cloud.")),
        field("cloudTypeMean", 0, 1, 2, N("Cloud type"), N("Move from flat sheets through low rolls to tall heaps.")),
        field("cloudTypeSpread", 0, 1, 2, N("Mix of types"), N("At 0 all clouds have the same shape. Raise it to mix shapes.")),
        field("cloudDensity", 0, 60, 1, N("Cloud density"), N("Denser clouds block more sunlight and have darker bases.")),
        field("cloudBaseHeightMeters", 0, 8000, 0, N("Cloud base (m)"), N("Height of the cloud bottoms above the ground.")),
        field("cloudDepthMeters", 50, 10000, 0, N("Thickness (m)"), N("Vertical distance from cloud base to cloud top.")),
        field("cloudCellSizeKm", 0.5, 6, 2, N("Cluster size (km)"), N("Small clusters scatter across the sky. Large ones form broad banks.")),
        field("cloudColor", 0, 1, 3, N("Cloud colour"), N("Tints the main cloud layer. White keeps the colour of its light."), "colour"),
    }},
    {N("Cloud shape"), {
        field("nubis3ErosionStrength", 0, 2, 2, N("Ragged edges"), N("Higher values carve deeper gaps into the outlines of clouds.")),
        field("cloudBodyBillowSizeKm", 0.2, 4, 2, N("Billow size (km)"), N("Width of the largest rounded lumps in a cloud.")),
        field("cloudBodyBillowGain", 0, 1, 2, N("Fine billows"), N("Raise this to cover the large lumps with smaller, stronger ones.")),
        field("cloudCurlStrengthKm", 0, 1, 2, N("Curl (km)"), N("Pulls the underside sideways into wisps. At 0 it hangs straight.")),
        field("cloudColumnTopVariation", 0, 1, 2, N("Uneven tops"), N("Low values line up the tops. High values let individual towers rise.")),
        field("cloudColumnFeather", 0.05, 1, 2, N("Soft edges"), N("Low values give sharp outlines. High values soften the edges.")),
        field("cloudDiffuseSunStrength", 0, 1, 2, N("Light in shadows"), N("Lets scattered sunlight brighten the undersides of thick clouds.")),
    }},
    {N("Second cloud layer"), {
        field("cloudLayer2Enable", 0, 1, 0, N("Show second layer"), N("Adds a separate sheet above the clouds or a fog bank near the ground."), "bool"),
        field("cloudLayer2CoverageMean", 0, 1, 2, N("Sheet cover"), N("Raise this until separate patches join into a sheet.")),
        field("cloudLayer2BaseHeightMeters", -100, 12000, 0, N("Sheet base (m)"), N("Set the base near zero for ground fog or raise it for a high deck.")),
        field("cloudLayer2DepthMeters", 50, 4000, 0, N("Sheet depth (m)"), N("A shallow layer makes a thin veil. A deep one fills more of the sky.")),
        field("cloudLayer2TypeMean", 0, 1, 2, N("Sheet shape"), N("At 0 the sheet is thickest at its base. At 1 its middle bulges.")),
        field("cloudLayer2DensityScale", 0, 2, 2, N("Sheet density"), N("A multiple of the main cloud density. At 0 the sheet disappears.")),
        field("cloudLayer2Albedo", 0, 1, 3, N("Sheet colour"), N("White scatters all colours. A warmer, darker tint can suggest dust."), "colour"),
    }},
    {N("High ice clouds"), {
        field("cloudCirrusEnable", 0, 1, 0, N("Show cirrus"), N("Adds thin ice streaks that can stay sunlit after the lower clouds darken."), "bool"),
        field("cloudCirrusCoverageMean", 0, 1, 2, N("Streak cover"), N("Choose between a few isolated streaks and a sky full of them.")),
        field("cloudCirrusBaseHeightMeters", 1000, 15000, 0, N("Ice height (m)"), N("Real cirrus usually forms between 6,000 and 13,000 metres.")),
        field("cloudCirrusOpticalDepth", 0, 3, 2, N("Streak opacity"), N("Around 0.1 gives fine transparent streaks. At 1 they look thick.")),
        field("cloudCirrusStreakDirection", 0, 360, 0, N("Streak angle (°)"), N("Turns the streaks across the sky independently of the lower wind.")),
        field("cloudCirrusHaloStrength", 0, 3, 2, N("Ice halo"), N("Brightens the ring around the Sun or Moon where light meets ice crystals.")),
    }},
    {N("Wind"), {
        field("cloudWindSpeed", 0, 0.10, 3, N("Drift (km/s)"), N("Moves the clouds across the map. 0.02 km/s is 20 metres each second.")),
        field("cloudWindDirection", 0, 360, 0, N("Drift angle (°)"), N("Turns the direction of travel. Add 180 degrees to reverse it.")),
        field("cloudEvolutionSpeed", 0, 0.02, 3, N("Rise (km/s)"), N("Moves detail upward inside each cloud. At 0 its shape stops rising.")),
    }},
    {N("Air"), {
        field("aerosolDensity", 0, 100, 2, N("Haze density"), N("Try 1 for clean air, 10 for a soft glow around the Sun and 50 for white haze."), "haze"),
        field("mieAbsorption", 0, 3, 2, N("Haze darkness"), N("At 0.1 the haze is milky and bright. At 1 it absorbs the usual amount of light. At 3 it looks smoky."), "absorption"),
        field("aerosolTint", 0, 1, 3, N("Haze colour"), N("Choose white for neutral haze or a sandy tint for dusty air."), "colour"),
        field("airDensity", 0, 4, 2, N("Air density"), N("1 gives Earth-like air. More air deepens the blue and reddens sunsets.")),
        field("airTint", 0, 1, 3, N("Air colour"), N("Tints the clear sky between clouds. White keeps the natural sky colours."), "colour"),
        field("ozoneDensity", 0, 4, 2, N("Ozone"), N("Raise this to deepen the blue sky during twilight.")),
        field("mieAnisotropy", -0.95, 0.95, 2, N("Haze direction"), N("Positive values concentrate the haze glow toward the Sun.")),
    }},
    {N("Fog"), {
        field("fogVisibilityMeters", 0, 50000, 0, N("Visibility (m)"), N("At 0 there is no height fog. Try 50 m for dense fog or 10,000 m for light haze."), "visibility"),
        field("fogHeightFalloffMeters", 1, 3000, 0, N("Thinning height (m)"), N("Small values confine fog to the ground. Larger values keep it thick higher up.")),
        field("fogBaseHeightMeters", -200, 2000, 0, N("Fog base (m)"), N("Height above the ground where fog reaches the chosen visibility.")),
        field("fogAlbedo", 0, 1, 2, N("Fog brightness"), N("High values scatter light into view. Low values make fog dark like smoke.")),
        field("fogAnisotropy", -0.95, 0.95, 2, N("Fog direction"), N("Positive values brighten fog when you look toward a light. Zero spreads light evenly.")),
        field("aerialPerspectiveFroxelRangeMeters", 100, 12000, 0, N("Shaded mist (m)"), N("How far nearby shadows reach into mist. Try 6,000 m beneath a low cloud sheet.")),
    }},
    {N("Storm"), {
        field("lightningStrikesPerMinute", 0, 60, 1, N("Strikes per minute"), N("Average lightning flashes each minute. Zero turns automatic lightning off.")),
    }},
}

local style = {
    field("mistStrength", 0, 2, 2, N("Mist"), N("0 clears added haze and map mist. 1 uses the look's mist. 2 doubles the added haze and fog density. A fog preset chosen in Remix settings keeps its own strength.")),
    field("rays.strength", 0, 2, 2, N("Sun rays"), N("Darkens air in cloud shadows to reveal shafts of sunlight. 1 is natural, 0 turns rays off.")),
    field("rainbow.strength", 0, 2, 2, N("Rainbow"), N("Scales the bow in sunlit rain. It fades as the air dries.")),
    field("nightGainStops", 0, 16, 1, N("Night brightness"), N("Each extra stop doubles natural night light. The default is 10 stops.")),
    field("moonlightGainStops", -8, 8, 1, N("Moonlight"), N("Adds or removes stops of moonlight on clouds and the ground.")),
    field("starGainStops", -8, 8, 1, N("Starlight"), N("Adds or removes stops of light from the stars and the Milky Way.")),
    field("starScintillation", 0, 4, 2, N("Star twinkle"), N("Stars near the horizon twinkle most. At 0 they stay steady.")),
    field("cloudShadowStrength", 0, 1, 2, N("Cloud shadows"), N("At 1 clouds shade the ground and air fully. At 0 their shadows disappear.")),
    field("volumetrics", 0, 2, 0, N("Mist on the map"), N("Choose Enhanced mist, Remix fog near you, or Off to clear mist from the map while keeping haze in the sky."), "mist"),
    field("aerialPerspectiveLocalLights", 0, 1, 0, N("Lamp glow in mist"), N("Lets lamps light Enhanced mist. Expect longer frame times near many lamps or with the flashlight on."), "bool"),
}

local function numberIn(n, f)
    return type(n) == "number" and n >= f.min and n <= f.max
end

local function valid(value, f)
    if f.kind == "bool" then return type(value) == "boolean" end
    if f.kind == "colour" or f.kind == "absorption" then
        if type(value) ~= "table" then return false end
        for k in pairs(value) do if k ~= 1 and k ~= 2 and k ~= 3 then return false end end
        if f.kind == "absorption" then
            local n = value[1]
            return type(n) == "number" and value[2] == n and value[3] == n
                and n >= f.min * f.unit and n <= f.max * f.unit
        end
        return numberIn(value[1], f) and numberIn(value[2], f) and numberIn(value[3], f)
    end
    return numberIn(value, f) and (f.kind ~= "mist" or value == math.floor(value))
end

local function convarText(value)
    if type(value) == "table" then return table.concat(value, ",") end
    if type(value) == "boolean" then return value and "1" or "0" end
    return tostring(value)
end

local function readValue(text, f)
    local v
    if f.kind == "colour" or f.kind == "absorption" then
        local r, g, b = text:match("^%s*([^,]+),([^,]+),([^,]+)%s*$")
        v = {tonumber(r), tonumber(g), tonumber(b)}
    elseif f.kind == "bool" then
        if text == "0" or text == "false" or text == "False" then return false end
        if text == "1" or text == "true" or text == "True" then return true end
    else
        v = tonumber(text)
    end
    if valid(v, f) then return v end
end

local function stem(name)
    if type(name) ~= "string" or #name > 32 or not name:match("^[A-Za-z0-9_-]+$") then return nil end
    name = name:lower()
    if name == "con" or name == "prn" or name == "aux" or name == "nul" or name:match("^com[1-9]$") or name:match("^lpt[1-9]$") then return nil end
    return name
end

return function(weather)
    local ed = {groups = groups, style = style, fields = {}, styles = {}, builtins = builtins, revision = 0}
    local own = CreateClientConVar("nativeloader_sky_own_look", "0", true, false, "Use your saved Enhanced sky look")
    local writing = false

    -- ConVar writes on load are synchronous. Apply the entire validated look before notifying the renderer once.
    local function notify(action, key)
        ed.revision = ed.revision + 1
        if ed.changed then ed.changed(action, key) end
    end
    local function register(f, default, isStyle)
        f.default = default
        -- The slider shows multiples of the library's absorption. Convars, looks and Remix use coefficients per km.
        if f.kind == "absorption" then f.unit = weather.defaults.mieAbsorption[1] end
        local suffix = f.key:gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2"):gsub("%.", "_"):lower()
        f.setting = (isStyle and "nativeloader_sky_style_" or "nativeloader_sky_look_") .. suffix
        f.cv = CreateClientConVar(f.setting, convarText(default), true, false, f.help)
        cvars.AddChangeCallback(f.setting, function(_, old, new)
            if writing or old == new then return end
            if isStyle then notify("style", f.key) return end
            local wasOwn = own:GetBool()
            writing = true
            if not wasOwn then own:SetString("1") end
            writing = false
            notify(wasOwn and "edit" or "firstEdit", f.key)
        end, "nativeloader_sky_editor")
    end
    for _, group in ipairs(groups) do
        for _, f in ipairs(group[2]) do
            register(f, weather.presets.partlyCloudy[f.key], false)
            ed.fields[f.key] = f
        end
    end
    local styleDefaults = {mistStrength = 1, ["rays.strength"] = 1, ["rainbow.strength"] = 1, nightGainStops = weather.mode.common.nightGainStops,
        moonlightGainStops = 0, starGainStops = 0, starScintillation = 1, cloudShadowStrength = 1, volumetrics = 0,
        aerialPerspectiveLocalLights = false}
    for _, f in ipairs(style) do register(f, styleDefaults[f.key], true) ed.styles[f.key] = f end
    cvars.AddChangeCallback("nativeloader_sky_own_look", function()
        if not writing then notify("toggle") end
    end, "nativeloader_sky_editor")

    function ed.own() return own:GetBool() end
    function ed.value(f)
        local value = readValue(f.cv:GetString(), f)
        if value == nil then return f.default end
        return value
    end
    function ed.write(f, value)
        if valid(value, f) and convarText(value) ~= f.cv:GetString() then f.cv:SetString(convarText(value)) end
    end
    function ed.writeColour(f, text)
        local value = readValue(text, f)
        if value then ed.write(f, value) return true end
        return false
    end
    function ed.look()
        local out = {}
        for key, f in pairs(ed.fields) do out[key] = ed.value(f) end
        return out
    end
    function ed.baseline(previous, configured, prefix)
        local out = {}
        for key, f in pairs(ed.fields) do
            local text = previous[key] or configured(prefix .. key)
            local value
            if text then value = readValue(text, f) end
            if value == nil then value = weather.defaults[key] end
            out[key] = value
        end
        return out
    end
    function ed.check(values)
        if type(values) ~= "table" then return false, "missing look object" end
        for key in pairs(values) do if not ed.fields[key] then return false, "unknown look key" end end
        for key, f in pairs(ed.fields) do
            if values[key] == nil then return false, "missing " .. key end
            if not valid(values[key], f) then return false, "invalid value for " .. key end
        end
        return true
    end
    function ed.load(values)
        if not ed.check(values) then return false end
        writing = true
        for key, f in pairs(ed.fields) do ed.write(f, values[key]) end
        own:SetString("1")
        writing = false
        notify("load")
        return true
    end
    function ed.builtin(choice)
        local base = {}
        for key, value in pairs(weather.defaults) do base[key] = value end
        base.cloudLayer2CoverageMean, base.cloudCirrusCoverageMean = 0, 0
        for key, value in pairs(choice.values) do base[key] = value end
        return base
    end
    function ed.weather(name) return weather.presets[name] end

    local function refuse(source, message, detail)
        MsgN("[nativeloader] Enhanced sky look " .. tostring(source) .. " refused: " .. (detail or message))
        return nil, L(message)
    end
    function ed.decode(text, source)
        local bad = N("Invalid look. Check the file version, setting names and ranges.")
        if type(text) ~= "string" or #text > limit or text:find("%f[%a]null%f[%A]") then return refuse(source, bad) end
        -- GMod's JSON reader accepts comments and trailing commas. A shared look is also plain JSON.
        if text:find("/", 1, true) or text:find(",%s*}") or text:find(",%s*%]") then return refuse(source, bad) end
        -- JSON decoders may discard duplicate properties. Do not let a later value conceal an invalid one.
        local seen = {}
        for key in text:gmatch('"([^"]*)"%s*:') do
            if seen[key] or not (key == "version" or key == "look" or ed.fields[key]) then return refuse(source, bad) end
            seen[key] = true
        end
        local ok, doc = pcall(util.JSONToTable, text, false, true)
        if not ok or type(doc) ~= "table" or (doc.version ~= 1 and doc.version ~= 2) then return refuse(source, bad) end
        if doc.version == 1 and type(doc.look) == "table" and doc.look.mieAbsorption == nil then
            doc.look.mieAbsorption = {unpack(weather.defaults.mieAbsorption)}
        end
        local checked, why = ed.check(doc.look)
        if not checked then return refuse(source, bad, why) end
        for k in pairs(doc) do if k ~= "version" and k ~= "look" then return refuse(source, bad) end end
        return doc.look
    end
    function ed.encode() return util.TableToJSON({version = 2, look = ed.look()}, false) end

    local badName = N("Use 1 to 32 letters, digits, hyphens or underscores. Choose a name that Windows can use for a file.")
    local ioError = N("The look file could not be written or removed.")
    local function recover(id)
        local path, backup = folder .. id .. ".json", folder .. id .. ".old.txt"
        if not file.Exists(path, "DATA") and file.Exists(backup, "DATA") then file.Rename(backup, path) end
        return path
    end
    local function readText(path)
        local f = file.Open(path, "rb", "DATA")
        if not f then return nil end
        local size, text = f:Size(), nil
        if size > 0 and size <= limit then text = f:Read(size) end
        f:Close()
        if text and #text == size then return text end
    end
    function ed.read(name)
        local id = stem(name)
        if not id then return refuse(name, badName) end
        return ed.decode(readText(recover(id)), id .. ".json")
    end
    function ed.names()
        local names = {}
        for _, filename in ipairs(file.Find(folder .. "*.old.txt", "DATA") or {}) do
            local id = stem(filename:match("^(.*)%.old%.txt$"))
            if id then recover(id) end
        end
        for _, filename in ipairs(file.Find(folder .. "*.json", "DATA") or {}) do
            local name = filename:match("^(.*)%.json$")
            if name and ed.read(name) then names[#names + 1] = name end
        end
        table.sort(names)
        return names
    end
    function ed.exists(name)
        local id = stem(name)
        return id and file.Exists(recover(id), "DATA") or false
    end
    function ed.save(name, replace)
        local id = stem(name)
        if not id then return refuse(name, badName) end
        local path = folder .. id .. ".json"
        if ed.exists(id) and not replace then return refuse(name, N("A look with that name already exists.")) end
        local text = ed.encode()
        if not ed.decode(text, id) then return nil, L(ioError) end
        file.CreateDir("nativeloader_companion/sky_looks")
        -- Stage and verify before replacing an existing file. Keep an interrupted replacement recoverable.
        local tmp, backup = folder .. id .. ".new.txt", folder .. id .. ".old.txt"
        file.Write(tmp, text)
        if readText(tmp) ~= text then return refuse(id, ioError) end
        local exists = ed.exists(id)
        if file.Exists(backup, "DATA") then
            if not exists or not replace or not ed.read(id) then return refuse(id, ioError) end
            file.Delete(backup) -- a previous replacement committed before its cleanup
        end
        if exists and (not replace or not file.Rename(path, backup)) then return refuse(id, ioError) end
        if not file.Rename(tmp, path) then
            if exists then file.Rename(backup, path) end
            return refuse(id, ioError)
        end
        if exists then file.Delete(backup) end
        return id
    end
    function ed.delete(name)
        local id = stem(name)
        if not id then return refuse(name, badName) end
        if not ed.exists(id) then return refuse(id, ioError) end
        local backup = folder .. id .. ".old.txt"
        if file.Exists(backup, "DATA") then file.Delete(backup) end
        file.Delete(folder .. id .. ".json")
        if ed.exists(id) then return refuse(id, ioError) end
        return true
    end
    return ed
end
