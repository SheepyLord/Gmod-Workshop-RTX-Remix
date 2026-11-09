-- The runtime of a map's RTX companion add-on made by astra_companion.py (the workshop-content-pack
-- skill) from that map's former Astra companion. Each add-on ships its own copy in its own folder;
-- the add-on's autorun file includes it on its map only, in the client realm, and calls it with the
-- add-on's profile (profile.lua, written by the converter).
--
-- While the map is loaded in an RTX session it:
--   * creates the map's Remix API lights (the Blender scene's lights, in Remix units);
--   * sets the map's Remix options (tone curve, haze, sky) and puts each one back when the map
--     unloads: the value in rtx.conf, else the RTX package's defaults layer, else the runtime's;
--   * answers the companion's NativeLoaderSkyOwner hook, so the RTX package's physical sky leaves
--     this map's sky alone (ADR 0031), and its NativeLoaderRemixFogOverride hook, so the weather
--     leaves the map's haze alone; when the player chose their own sky (Follow the map's sun off,
--     or a sky setting changed), the companion's sky is in charge and the scene's suns stay out;
--   * keeps Light2RTX from turning the map's light_environment into a second sun;
--   * neutralises the vanilla bake's tint ($color, $color2) on the materials the Remix mod replaces,
--     whose PBR albedo already carries the colour;
--   * tags the texture hashes of a few materials with Remix categories (animated water, particle,
--     legacy emissive) and takes the tags off again when the map unloads;
--   * removes the base map's rasterised stand-ins (fog, bloom, mist sheets) the profile names.
-- The PBR materials are the Remix mod the native loader deploys beside this add-on.
--
-- Nothing runs per frame. The work happens once, three seconds after the map's entities exist,
-- then the options are set again 20, 40 and 60 s later (other add-ons finish their map setup over
-- the first minute). Hashes that only exist once a texture was first drawn are looked for every
-- 2 s until all are found, for at most a minute.

local function normalize(value)
    -- Hashes stay strings: a Lua number loses bits of a 64-bit hash.
    if not isstring(value) then return nil end
    local text = string.upper(value)
    local body = text:match("^0X(%x+)$") or text:match("^(%x+)$")
    if not body or #body > 16 or not body:find("[1-9A-F]") then return nil end
    return "0x" .. string.rep("0", 16 - #body) .. body
end

local CREATE = { sphere = "CreateSphere", rect = "CreateRect", disk = "CreateDisk", distant = "CreateDistant" }

return function(P, DIR)
    local previous = rawget(_G, P.global)
    local wasStarted = istable(previous) and previous.started == true
    if istable(previous) and isfunction(previous.Stop) then pcall(previous.Stop, "reload") end
    local defaults = P.defaults or {}

    local M = {
        profile = P, dir = DIR, lights = {}, lightFailures = {}, saved = {}, savedCvars = {},
        owned = {}, pendingCategories = 0, tints = {}, hooksOff = {}, started = false, applies = 0,
        settingsApplied = 0, settingsRefused = {},
    }
    _G[P.global] = M

    local TAG = "[" .. P.title .. "] "
    local function log(fmt, ...)
        MsgC(Color(120, 200, 255), TAG, Color(225, 225, 225), string.format(fmt, ...), "\n")
    end

    local enable = CreateClientConVar(P.prefix .. "_enable", "1", true, false,
        "Run " .. P.title .. " (lights, scoped Remix settings) on " .. P.map, 0, 1)

    local function remixReady()
        return istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable) and istable(RemixLight)
    end

    ------------------------------------------------------------ whose sky

    -- The RTX package's companion drives a physical sky with its own sun and moon. This map keeps
    -- its own sky (it answers NativeLoaderSkyOwner) unless the player chose theirs: Follow the map's
    -- sun unticked, or any sky or weather setting changed in this session (ADR 0031, ADR 0105). Then
    -- the companion is in charge, and the scene's distant lights and the sky options are left out,
    -- so there is never a second sun. With the companion's sky off (the map's skybox) nothing yields.
    -- Not nativeloader_sky_hour and _direction: following the map, the companion writes those itself
    -- at the map's start, and a player who moves either makes it switch Follow the map's sun off,
    -- which is watched.
    local SKY_CONVARS = { "nativeloader_sky", "nativeloader_sky_follow_map", "nativeloader_sky_time_passes",
        "nativeloader_sky_day_minutes", "nativeloader_sky_season", "nativeloader_sky_moon",
        "nativeloader_sky_eclipse", "nativeloader_sky_eclipse_amount", "nativeloader_sky_stars",
        "nativeloader_weather" }
    local skyKeys = {}
    for _, key in ipairs(P.sky_keys or { "rtx.skyMode" }) do skyKeys[key] = true end
    M.playerSky = false

    function M.PlayerSkyInCharge()
        if not P.sky_owner or not istable(rawget(_G, "NATIVELOADER_SKY")) then return false end
        local sky = GetConVar("nativeloader_sky")
        if not sky or not sky:GetBool() then return false end
        if M.playerSky then return true end
        local follow = GetConVar("nativeloader_sky_follow_map")
        return follow ~= nil and not follow:GetBool()
    end

    ------------------------------------------------------------ Remix options

    -- GetConfigVariable reports rtx.conf, not the live value: what comes back on leaving the map is
    -- the player's configured value, else the default the session had without it.
    local function configured(key)
        if isfunction(RemixConfig.GetConfigVariable) then
            local ok, value = pcall(RemixConfig.GetConfigVariable, key)
            if ok and isstring(value) and value ~= "" then return value end
        end
        return defaults[key]
    end

    local function setOption(key, value)
        if M.saved[key] == nil then M.saved[key] = configured(key) or false end
        local ok, result = pcall(RemixConfig.SetConfigVariable, key, value)
        return ok and result ~= false
    end

    function M.ApplySettings()
        local applied, refused = 0, {}
        local playerSky = M.PlayerSkyInCharge()
        for _, option in ipairs(P.remix) do
            local key, value = option[1], option[2]
            -- The game's own lights are hidden only while this add-on's lights stand in for them.
            if (#M.lights > 0 or not key:find("^rtx%.ignoreGame")) and not (playerSky and skyKeys[key]) then
                if setOption(key, value) then applied = applied + 1 else refused[#refused + 1] = key end
            end
        end
        M.settingsApplied, M.settingsRefused = applied, refused
        M.applies = M.applies + 1
        -- A player who took the sky over in the companion gets theirs back in the same tick.
        if P.sky_owner then hook.Run("NativeLoaderSkySet") end
        return applied
    end

    function M.RestoreSettings()
        for i = #P.remix, 1, -1 do
            local key = P.remix[i][1]
            local old = M.saved[key]
            if old then pcall(RemixConfig.SetConfigVariable, key, old) end
        end
        M.saved = {}
    end

    ------------------------------------------------------------ engine settings

    local function setConVar(name, value)
        local cv = GetConVar(name)
        if not cv then return end
        if cv:GetString() == value then return end
        -- Lua-created client convars change at once; engine ones on the next command buffer run.
        if not pcall(cv.SetString, cv, value) then RunConsoleCommand(name, value) end
    end

    -- Applied when this file loads and again at Initialize, InitPostEntity and the start, since the
    -- RTX fixes create their convars when their own autorun runs.
    function M.ApplyEngine()
        if not enable:GetBool() then return end
        for _, option in ipairs(P.engine) do
            local cv = GetConVar(option[1])
            if cv then
                if M.savedCvars[option[1]] == nil then M.savedCvars[option[1]] = cv:GetString() end
                setConVar(option[1], option[2])
            end
        end
    end

    function M.RestoreEngine()
        for name, old in pairs(M.savedCvars) do setConVar(name, old) end
        M.savedCvars = {}
    end

    ------------------------------------------------------------ lights

    M.lightKind = {}

    local function createLights(wanted)
        for i, L in ipairs(P.lights) do
            if wanted(L) then
                local create = RemixLight[CREATE[L.type] or ""]
                local ok, id = false, nil
                if isfunction(create) then ok, id = pcall(create, L.base, L.shape, 0) end
                if ok and isnumber(id) and id ~= 0 then
                    M.lights[#M.lights + 1] = id
                    M.lightKind[id] = L.type
                else
                    M.lightFailures[#M.lightFailures + 1] = { index = i, id = L.id, error = tostring(id) }
                end
            end
        end
    end

    function M.CreateLights()
        M.DestroyLights()
        -- With the player's sky the companion's atmosphere makes the sun and the moon.
        local playerSky = M.PlayerSkyInCharge()
        createLights(function(L) return not (playerSky and L.type == "distant") end)
        if #M.lightFailures > 0 then
            log("%d of %d lights failed; first: %s (%s)", #M.lightFailures, #P.lights,
                tostring(M.lightFailures[1].id), M.lightFailures[1].error)
        end
        return #M.lights
    end

    function M.DestroyLights(only)
        local kept = {}
        for _, id in ipairs(M.lights) do
            if only == nil or M.lightKind[id] == only then
                if istable(RemixLight) and isfunction(RemixLight.DestroyLight) then pcall(RemixLight.DestroyLight, id) end
                M.lightKind[id] = nil
            else
                kept[#kept + 1] = id
            end
        end
        M.lights = kept
        if only == nil then M.lightFailures = {} end
    end

    function M.SunCount()
        local n = 0
        for _, id in ipairs(M.lights) do if M.lightKind[id] == "distant" then n = n + 1 end end
        return n
    end

    -- After a sky setting changed: the scene's suns and sky options follow whose sky it is now.
    function M.RefreshSky()
        if not M.started then return end
        local mine = not M.PlayerSkyInCharge()
        local suns = M.SunCount()
        if mine and suns == 0 then
            createLights(function(L) return L.type == "distant" end)
            for _, option in ipairs(P.remix) do
                if skyKeys[option[1]] then setOption(option[1], option[2]) end
            end
        elseif not mine and suns > 0 then
            M.DestroyLights("distant")
        end
    end

    ------------------------------------------------------------ the vanilla bake's tint

    -- The vanilla map darkens and tints its baked atlases with $color/$color2; Remix multiplies the
    -- replacement albedo by that tint (and a channel above 1 wraps in its byte-sized factor). The
    -- originals are kept and put back when the add-on is switched off, but not when the map unloads:
    -- these materials belong to this map alone, and a material changed in ShutDown can crash the
    -- map change.
    local WHITE = Vector(1, 1, 1)
    function M.ApplyTints()
        if not P.tint then return 0 end
        local changed = 0
        for _, name in ipairs(P.tint.materials) do
            if not M.tints[name] then
                local mat = Material(name)
                if mat and not mat:IsError() then
                    local record = {}
                    for _, key in ipairs(P.tint.keys) do
                        local v = mat:GetVector(key)
                        if v and (v.x ~= 1 or v.y ~= 1 or v.z ~= 1) then
                            record[key] = Vector(v.x, v.y, v.z)
                            mat:SetVector(key, WHITE)
                        end
                    end
                    if next(record) then
                        if P.tint.recompute then mat:Recompute() end
                        changed = changed + 1
                    end
                    M.tints[name] = record
                end
            end
        end
        return changed
    end

    function M.RestoreTints()
        for name, record in pairs(M.tints) do
            if next(record) then
                local mat = Material(name)
                for key, value in pairs(record) do mat:SetVector(key, value) end
                if P.tint.recompute then mat:Recompute() end
            end
        end
        M.tints = {}
    end

    function M.TintCount()
        local n = 0
        for _, record in pairs(M.tints) do if next(record) then n = n + 1 end end
        return n
    end

    ------------------------------------------------------------ Remix hash categories

    local function categoryOf(hash)
        local ok, value = pcall(RemixMaterial.GetHashCategory, hash)
        return (ok and isnumber(value)) and value or 0
    end

    local function claim(hash, flag)
        local key = hash .. "/" .. flag
        if M.owned[key] ~= nil then return end
        local before = categoryOf(hash)
        if bit.band(before, flag) ~= 0 then M.owned[key] = false return end -- set by someone else
        local ok, result = pcall(RemixMaterial.SetHashCategory, hash, flag)
        M.owned[key] = (ok and result ~= false) and { hash = hash, flag = flag } or false
    end

    -- Returns how many of the profile's materials have no texture hash yet (not drawn so far).
    function M.ApplyCategories()
        if not (P.categories and istable(RemixMaterial) and isfunction(RemixMaterial.GetAllTextureHashes)
            and isfunction(RemixMaterial.SetHashCategory) and isfunction(RemixMaterial.GetHashCategory)) then
            M.pendingCategories = 0
            return 0
        end
        local pending = 0
        for _, category in ipairs(P.categories) do
            for _, name in ipairs(category.materials) do
                local ok, hashes = pcall(RemixMaterial.GetAllTextureHashes, name)
                local found = false
                if ok and istable(hashes) then
                    for _, raw in pairs(hashes) do
                        local hash = normalize(raw)
                        if hash then found = true claim(hash, category.flag) end
                    end
                end
                if not found then pending = pending + 1 end
            end
        end
        M.pendingCategories = pending
        return pending
    end

    function M.ReleaseCategories()
        if istable(RemixMaterial) and isfunction(RemixMaterial.RemoveHashCategory) then
            for _, record in pairs(M.owned) do
                if record then
                    -- The API removes a hash's whole set: put back whatever else it had.
                    local keep = bit.band(categoryOf(record.hash), bit.bnot(record.flag))
                    pcall(RemixMaterial.RemoveHashCategory, record.hash)
                    if keep ~= 0 then pcall(RemixMaterial.SetHashCategory, record.hash, keep) end
                end
            end
        end
        M.owned = {}
    end

    function M.CategoryCount()
        local n = 0
        for _, record in pairs(M.owned) do if record then n = n + 1 end end
        return n
    end

    ------------------------------------------------------------ the base map's stand-ins

    function M.HooksOff()
        if not P.hooks_off then return end
        local all = hook.GetTable()
        for _, h in ipairs(P.hooks_off) do
            local fn = all[h[1]] and all[h[1]][h[2]]
            if fn then
                M.hooksOff[#M.hooksOff + 1] = { h[1], h[2], fn }
                hook.Remove(h[1], h[2])
            end
        end
    end

    function M.HooksOn()
        local all = hook.GetTable()
        for _, record in ipairs(M.hooksOff) do
            if not (all[record[1]] and all[record[1]][record[2]]) then hook.Add(record[1], record[2], record[3]) end
        end
        M.hooksOff = {}
    end

    ------------------------------------------------------------ lifecycle

    local TIMER_SETTINGS, TIMER_CATEGORIES = P.id .. "_settings", P.id .. "_categories"

    function M.Start()
        if M.started or not enable:GetBool() then return end
        if not remixReady() then
            log("the Remix API (RemixLight, RemixConfig) is not available; nothing to do")
            return
        end
        M.started = true
        M.WatchSky()
        M.ApplyEngine()
        if P.clear_light2rtx and istable(Light2RTX) and isfunction(Light2RTX.Clear) then pcall(Light2RTX.Clear) end
        local lights = M.CreateLights()
        M.ApplySettings()
        local tints = M.ApplyTints()
        M.HooksOff()
        local pending = M.ApplyCategories()
        timer.Create(TIMER_SETTINGS, 20, 3, function()
            if not M.started then return end
            M.ApplyEngine()
            M.ApplySettings()
            M.ApplyTints()
        end)
        if pending > 0 then
            timer.Create(TIMER_CATEGORIES, 2, 30, function()
                if not M.started or M.ApplyCategories() == 0 then timer.Remove(TIMER_CATEGORIES) end
            end)
        end
        log("started: %d of %d lights, %d Remix settings%s, %d tints neutral, %d stand-ins off, %d hash tags (%d materials not drawn yet)",
            lights, #P.lights, M.settingsApplied,
            not P.sky_owner and "" or M.PlayerSkyInCharge() and " (the player's sky: the scene's suns left out)" or " (its own sky)",
            tints, #M.hooksOff, M.CategoryCount(), pending)
    end

    function M.Stop(reason)
        timer.Remove(TIMER_SETTINGS)
        timer.Remove(TIMER_CATEGORIES)
        -- The engine settings apply from the file's load, before the start.
        M.RestoreEngine()
        if not M.started then return end
        M.started = false
        M.DestroyLights()
        if istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable) then M.RestoreSettings() end
        M.ReleaseCategories()
        M.HooksOn()
        if reason ~= "shutdown" then M.RestoreTints() end
    end

    ------------------------------------------------------------ status

    local function loadHashes()
        if M.hashes ~= nil then return M.hashes end
        M.hashes = false
        local path = DIR .. "/" .. (P.hashes or "hashes.lua")
        local code = file.Read(path, "LUA")
        local fn = code and CompileString(code, path, false)
        if isfunction(fn) then
            local ok, data = pcall(fn)
            if ok and istable(data) then M.hashes = data end
        end
        return M.hashes
    end

    -- Which of the mod's materials the runtime hashes the way the mod expects: for each material the
    -- texture hashes the game uploaded so far, against the aliases the mod replaces.
    function M.Coverage()
        local expected = loadHashes()
        local report = { covered = 0, unseen = 0, mismatched = {} }
        if not (expected and istable(RemixMaterial) and isfunction(RemixMaterial.GetAllTextureHashes)) then return nil end
        for name, aliases in pairs(expected) do
            local set = {}
            for _, alias in ipairs(aliases) do local h = normalize(alias) if h then set[h] = true end end
            local ok, hashes = pcall(RemixMaterial.GetAllTextureHashes, name)
            local seen, miss = false, nil
            if ok and istable(hashes) then
                for _, raw in pairs(hashes) do
                    local h = normalize(raw)
                    if h then
                        seen = true
                        if not set[h] then miss = h end
                    end
                end
            end
            if not seen then report.unseen = report.unseen + 1
            elseif miss then report.mismatched[#report.mismatched + 1] = name .. " " .. miss
            else report.covered = report.covered + 1 end
        end
        table.sort(report.mismatched)
        return report
    end

    function M.Status()
        log("%s on %s: %s", P.title, P.map, M.started and "running" or "stopped")
        local sky = not P.sky_owner and "the companion's"
            or M.PlayerSkyInCharge() and ("the player's (the companion's sun; the scene's suns left out; "
                .. (M.skyChange and ("after " .. M.skyChange) or "Follow the map's sun is off") .. ")")
            or "the map's own (the companion leaves it)"
        log("lights %d of %d (failed %d, suns %d), Remix settings %d (refused: %s), sky %s%s",
            #M.lights, #P.lights, #M.lightFailures, M.SunCount(), M.settingsApplied,
            #M.settingsRefused > 0 and table.concat(M.settingsRefused, ", ") or "none", sky,
            P.fog_owner and ", haze the map's" or "")
        log("tints neutral %d, stand-ins off %d, hash tags %d, materials not drawn yet %d",
            M.TintCount(), #M.hooksOff, M.CategoryCount(), M.pendingCategories)
        local coverage = M.Coverage()
        if coverage then
            log("mod coverage: %d materials hashed as the mod expects, %d not drawn yet, %d with other hashes",
                coverage.covered, coverage.unseen, #coverage.mismatched)
            for i = 1, math.min(8, #coverage.mismatched) do log("  other hash: %s", coverage.mismatched[i]) end
        end
    end

    ------------------------------------------------------------ hooks and commands

    if P.sky_owner then
        hook.Add("NativeLoaderSkyOwner", P.id, function()
            if enable:GetBool() then return P.title end
        end)
    end
    -- Watched from the map's start only: this file loads before the companion's (autorun order),
    -- so callbacks added now would see the companion's convars created at their defaults and then
    -- set to the player's saved values (partlyCloudy -> clear), which is no change of the player's.
    function M.WatchSky()
        if not P.sky_owner or M.watching then return end
        M.watching = true
        for _, name in ipairs(SKY_CONVARS) do
            cvars.AddChangeCallback(name, function(convar, old, new)
                if old == new then return end
                M.playerSky = true
                M.skyChange = M.skyChange or string.format("%s %s -> %s", convar, tostring(old), tostring(new))
                M.RefreshSky()
            end, P.id)
        end
    end
    -- The haze is the map's: the companion's weather then leaves rtx.volumetrics.* alone (the hook
    -- its Remix settings' fog presets answer), whoever drives the sky.
    if P.fog_owner then
        hook.Add("NativeLoaderRemixFogOverride", P.id, function()
            if M.started then return true end
        end)
    end
    hook.Add("Initialize", P.id, M.ApplyEngine)
    hook.Add("InitPostEntity", P.id, function()
        M.ApplyEngine()
        M.WatchSky()
        -- The RTX fixes apply their per-map Remix settings a few seconds after the map starts.
        timer.Simple(3, M.Start)
    end)
    hook.Add("ShutDown", P.id, function() M.Stop("shutdown") end)

    cvars.AddChangeCallback(P.prefix .. "_enable", function(_, _, value)
        if tonumber(value) == 0 then
            M.Stop("disabled")
            M.RestoreTints()
        else
            M.ApplyEngine()
            M.Start()
        end
    end, P.id)
    concommand.Add(P.prefix .. "_status", function() M.Status() end)
    concommand.Add(P.prefix .. "_reload", function()
        M.Stop("reload")
        M.Start()
    end)

    M.ApplyEngine()
    -- A Lua reload after the map started: start again at once.
    if wasStarted then timer.Simple(0, M.Start) end
    return M
end
