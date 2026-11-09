-- What the game is doing while a map loads (R24, ADR 0134). The RTX client module runs this companion menu script
-- once in the menu realm of an RTX start (as multiplayer_notice.lua). It loads the engine guard module there (its
-- gmsv_ copy: the guard against material fallback loops is then in place before any map) and drives the guard's
-- load overlay from the menu's loading screen: the menu's Think sees IsInLoading() become true (the overlay starts),
-- passes the stock status line (GetLoadStatus()) on, and sees it end (the overlay hides). GameDetails names the map.
-- The overlay's own thread adds the Lua file running and the game file being read. Documented in loading_status.lua.md.
if not MENU_DLL or NativeLoaderLoadStatus then return end

local api = rawget(_G, "__NATIVELOADER_MENU_API")
local read = istable(api) and isfunction(api.read) and api.read or nil
local function N(text) return text end

local TEXT = {
    loading = N"Loading…",
    loadingMap = N"Loading %s",
    joining = N"Joining %s",
    file = N"File",
}

local enabled
do
    local ok, convar = pcall(CreateConVar, "nativeloader_load_overlay", "1", FCVAR_ARCHIVE,
        "Show what the game is doing while a map loads (RTX sessions)")
    enabled = ok and convar or nil
end
local function on()
    return not enabled or enabled:GetBool()
end

local ALIASES = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }
local catalog
-- The companion's language setting is a client convar the menu realm cannot see: the companion keeps a copy for the
-- menu in data/nativeloader_companion/language.txt (nativeloader/i18n.lua).
local function chosenLanguage()
    local chosen = GetConVar("nativeloader_language")
    if chosen then return chosen:GetString() end
    local saved = file and isfunction(file.Read) and file.Read("nativeloader_companion/language.txt", "DATA")
    return isstring(saved) and #saved <= 16 and saved:match("^[%w%-]+$") and saved or ""
end
local function L(text)
    local code = chosenLanguage()
    if code == "" then
        local gmod = GetConVar("gmod_language")
        code = gmod and gmod:GetString() or "en"
    end
    code = ALIASES[string.lower(code)] or code
    if code == "en" or code == "" then return text end
    if catalog == nil then
        catalog = false
        local source = read and read("nativeloader/nativeloader/i18n_data.lua")
        if isstring(source) then
            -- The menu realm has no CompileString (PoC, R24), only RunString: through a global taken at once.
            if isfunction(CompileString) then
                local chunk = CompileString(source, "nativeloader/i18n_data.lua", false)
                local ok, data = false, nil
                if isfunction(chunk) then ok, data = pcall(chunk) end
                catalog = ok and istable(data) and data or false
            elseif isfunction(RunString) then
                local key = "__NATIVELOADER_I18N_DATA"
                rawset(_G, key, nil)
                pcall(RunString, key .. " = (function()\n" .. source .. "\nend)()", "nativeloader/i18n_data.lua", false)
                local data = rawget(_G, key)
                rawset(_G, key, nil)
                catalog = istable(data) and data or false
            end
        end
    end
    local phrases = catalog and catalog[code]
    local translated = istable(phrases) and phrases[text]
    return isstring(translated) and translated ~= "" and translated or text
end
local function format(template, value)
    local ok, text = pcall(string.format, L(template), value)
    return ok and text or string.format(template, value)
end

-- The engine guard module, loaded now: its guard then covers every map load of this start.
local guard
do
    local ok, err = pcall(require, "nlengineguard")
    local module = rawget(_G, "nlengineguard")
    if ok and istable(module) and isfunction(module.LoadStart) then
        guard = module
    else
        MsgN("[nativeloader] load overlay unavailable: " .. tostring(ok and "no overlay in the engine guard module" or err))
    end
end

NativeLoaderLoadStatus = { loads = 0 }
local loading, lastStatus = false, nil
local heading, headingAt = nil, 0 -- from GameDetails, which may come just before the load is seen
local hosted = false -- this load starts its own server here (a single-player game or a listen server)

local function report(summary)
    if not istable(summary) or not isnumber(summary.seconds) or summary.seconds < 2 then return end
    local parts = {}
    for _, item in ipairs(istable(summary.lua) and summary.lua or {}) do
        if istable(item) and isstring(item.name) and isnumber(item.seconds) and item.seconds >= 0.5 then
            parts[#parts + 1] = string.format("%s (%.1f s)", item.name, item.seconds)
        end
    end
    MsgN(string.format("[nativeloader] map loaded in %.1f s%s", summary.seconds,
        #parts > 0 and ("; Lua files that ran longest: " .. table.concat(parts, ", ")) or ""))
    NativeLoaderLoadStatus.last = summary
end

local function begin()
    loading, lastStatus = true, nil
    NativeLoaderLoadStatus.loads = NativeLoaderLoadStatus.loads + 1
    local fresh = heading ~= nil and SysTime() - headingAt < 10
    if not fresh then hosted = false end
    pcall(guard.LoadStart, fresh and heading or L(TEXT.loading), { lua = "Lua", file = L(TEXT.file) })
end
local function finish()
    loading, hosted = false, false
    local ok, summary = pcall(guard.LoadEnd)
    if ok then report(summary) end
end

-- The menu's Think runs whenever the engine draws a frame, during a load too (between its blocking phases): the
-- overlay's own thread carries it through those.
if guard and isfunction(IsInLoading) then
    hook.Add("Think", "NativeLoaderLoadStatus", function()
        local now = IsInLoading() == true
        if now and not loading then
            if not on() then return end
            begin()
        elseif loading and not now then
            finish()
            return
        end
        if loading and isfunction(GetLoadStatus) then
            local status = GetLoadStatus()
            if isstring(status) then
                status = string.Trim(status)
                if status ~= "" and status ~= lastStatus then
                    lastStatus = status
                    pcall(guard.LoadStatus, status)
                end
            end
        end
    end)
end

if guard and isfunction(GameDetails) then
    local nativeGameDetails = GameDetails
    function GameDetails(servername, serverurl, mapname, maxplayers, ...)
        if isstring(mapname) and mapname ~= "" then
            -- A game started here is loaded, not joined: the engine also names its own server ("My Garry's Mod
            -- Server") later in the load, when IsHostingGame() can read false (the PoC, R24). The loading panel's
            -- call while hosting, and a single-player game's, pass one player.
            if (isfunction(IsHostingGame) and IsHostingGame()) or tonumber(maxplayers) == 1 then hosted = true end
            heading, headingAt = format(TEXT.loadingMap, mapname), SysTime()
            if not hosted and isstring(servername) and servername ~= "" then
                heading = format(TEXT.joining, servername) .. " · " .. mapname
            end
            if loading then pcall(guard.LoadHeading, heading) end
        end
        return nativeGameDetails(servername, serverurl, mapname, maxplayers, ...)
    end
end
