-- RTX Remix left in this game without its loader: the window that says so (ADR 0235). A player who deleted
-- bin/win64/winmm.dll (and maybe unsubscribed at the same time) keeps every file the loader deployed: Garry's Mod mounts
-- the add-ons by itself, but without the loader RTX Remix neither starts nor removes itself. Garry's Mod runs no add-on
-- code in its main menu, so the first moment to tell the player is a map: in the client realm of a local game, a while
-- after it loaded, when this machine's loader did not start RTX and its bootstrap is gone. The server's
-- nativeloader_leftovers.lua has tried to remove the package already; it leaves what it did in the data folder. When it
-- removed the package, it shows the short window itself (this file may be gone by then) and this file does nothing.
-- Otherwise this window explains, recommends putting the loader back, and lists what to delete by hand (from the
-- loader's journal). Close, or Don't show this again. Edit the English text below; its translations are in
-- companion/i18n/<language>.po. Documented in nativeloader_leftovers_popup.lua.md.
if not CLIENT or MENU_DLL or NativeLoaderLeftoversPopupAutorun then return end
NativeLoaderLeftoversPopupAutorun = true
-- Never in a start this machine's loader made an RTX start, nor while the loader is installed (an off switch: the
-- loader removes what it deployed itself, and the player chose to start without it).
if NativeLoaderRTXStart and NativeLoaderRTXStart() then return end
do
    local ok, found = pcall(file.Exists, "bin/win64/winmm.dll", "BASE_PATH")
    if not ok or found then return end
end

local STATE = "nativeloader_companion/leftovers_state.json"   -- what this game's server did (nativeloader_leftovers.lua)
local DISMISSED = "nativeloader_companion/leftovers_popup.txt" -- Don't show this again
local JOURNAL = "native-loader/state.json"                      -- the loader's record of what it deployed
local PACKAGE = "gmod-rtx-remix"
local RELEASES = "https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/latest"
local GUIDE = "https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix#uninstalling"
local FRESH = 600 -- seconds: a state older than this is another game's

local function N(text) return text end
local TEXT = {
    title = N"RTX Remix is still in this game, but its loader is gone",
    intro = N"The native loader (bin\\win64\\winmm.dll) was removed while RTX Remix's files stayed in this game. Without the loader, RTX Remix can neither start nor remove itself, so parts of it may still show or look wrong.",
    reason = N"It could not remove itself now: %s.",
    recommended = N"Recommended: put the native loader back",
    step1 = N"1. Download winmm.dll from the latest release (Open the release page) and put it in GarrysMod\\bin\\win64.",
    step2 = N"2. To keep RTX Remix: stay subscribed to it on the Workshop and start Garry's Mod. RTX works again.",
    step3 = N"3. To remove RTX Remix: unsubscribe from it, start Garry's Mod once and quit. The loader removes everything it installed and puts your own files back. Then delete GarrysMod\\bin\\win64\\winmm.dll.",
    manual = N"Or remove it by hand, with Garry's Mod closed",
    addons = N"Delete these folders from GarrysMod\\garrysmod\\addons: %s",
    bin = N"Delete these files from GarrysMod\\garrysmod\\lua\\bin: %s",
    mods = N"Delete these folders from GarrysMod\\rtx-remix\\mods: %s",
    data = N"Delete these folders from GarrysMod\\garrysmod\\data: %s",
    unknown = N"The loader's record of what it installed is gone. Delete the RTX Remix folders from GarrysMod\\garrysmod\\addons (nativeloader, remixbinary and the others it added), its files from GarrysMod\\garrysmod\\lua\\bin and its mods from GarrysMod\\rtx-remix\\mods; the uninstall steps on GitHub list them: %s",
    loaderFolder = N"Last, delete GarrysMod\\native-loader. Your own files the loader had moved aside are in its backup folder: take back what you need first.",
    console = N"If something still looks different after a restart (no 3D skybox, flat lighting), run r_3dsky 1 and mat_specular 1 in the console.",
    release = N"Open the release page",
    copy = N"Copy these steps",
    copied = N"Copied",
    never = N"Don't show this again",
    close = N"Close",
}

-- The player's language, as the companion's other texts take it (nativeloader/i18n.lua, which this file does not load:
-- it is made for RTX starts).
local phrases
do
    local ok, data = pcall(function()
        if not file.Exists("nativeloader/i18n_data.lua", "LUA") then return nil end
        return include("nativeloader/i18n_data.lua")
    end)
    if ok and istable(data) then
        local aliases = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }
        local function code(name)
            local convar = GetConVar(name)
            local value = convar and convar:GetString() or ""
            return aliases[value:lower()] or value
        end
        local chosen = code("nativeloader_language")
        phrases = data[chosen ~= "" and chosen or code("gmod_language")]
    end
end
local function L(text)
    local translated = istable(phrases) and phrases[text]
    return isstring(translated) and translated ~= "" and translated or text
end

-- What this game's server did, when it wrote it in this game (FRESH).
local function serverState()
    local ok, state = pcall(function() return util.JSONToTable(file.Read(STATE, "DATA") or "") end)
    if not ok or not istable(state) or not isstring(state.outcome) then return nil end
    local at = tonumber(state.at)
    if not at or math.abs(os.time() - at) > FRESH then return nil end
    return state
end

-- The package's folders and files the loader's journal lists, by place: add-ons, lua/bin, Remix mods, data.
local function deployed()
    local ok, journal = pcall(function() return util.JSONToTable(file.Read(JOURNAL, "BASE_PATH") or "") end)
    local files = ok and istable(journal) and istable(journal.current) and journal.current.files
    if not istable(files) then return nil end
    local found = { addons = {}, bin = {}, mods = {}, data = {} }
    local any = false
    for _, entry in ipairs(files) do
        if istable(entry) and entry.package == PACKAGE and isstring(entry.path) then
            local path = entry.path
            local addon = path:match("^garrysmod/addons/([^/]+)/")
            local bin = path:match("^garrysmod/lua/bin/([^/]+)$")
            local mod = path:match("^rtx%-remix/mods/([^/]+)/")
            local data = path:match("^garrysmod/data/([^/]+)/")
            if addon then found.addons[addon] = true any = true
            elseif bin then found.bin[bin] = true any = true
            elseif mod then found.mods[mod] = true any = true
            elseif data then found.data[data] = true any = true end
        end
    end
    if not any then return nil end
    local lists = {}
    for place, names in pairs(found) do
        local sorted = {}
        for name in pairs(names) do sorted[#sorted + 1] = name end
        table.sort(sorted, function(a, b) return a:lower() < b:lower() end)
        lists[place] = sorted
    end
    return lists
end

-- The long window's spec, in the player's language.
local function spec(state)
    local paragraphs = { L(TEXT.intro) }
    if state and isstring(state.error) and state.error ~= "" then
        paragraphs[#paragraphs + 1] = string.format(L(TEXT.reason), state.error)
    end
    local manual = {}
    local lists = deployed()
    if lists then
        for _, place in ipairs({ "addons", "bin", "mods", "data" }) do
            if #lists[place] > 0 then manual[#manual + 1] = string.format(L(TEXT[place]), table.concat(lists[place], ", ")) end
        end
    else
        manual[#manual + 1] = string.format(L(TEXT.unknown), GUIDE)
    end
    manual[#manual + 1] = L(TEXT.loaderFolder)
    manual[#manual + 1] = L(TEXT.console)
    local sections = {
        { heading = L(TEXT.recommended), lines = { L(TEXT.step1), L(TEXT.step2), L(TEXT.step3) } },
        { heading = L(TEXT.manual), lines = manual },
    }
    -- Everything as plain text, for the clipboard.
    local plain = { L(TEXT.title), "" }
    for _, text in ipairs(paragraphs) do plain[#plain + 1] = text end
    for _, section in ipairs(sections) do
        plain[#plain + 1] = ""
        plain[#plain + 1] = section.heading
        for _, text in ipairs(section.lines) do plain[#plain + 1] = text end
    end
    plain[#plain + 1] = ""
    plain[#plain + 1] = RELEASES
    return {
        title = L(TEXT.title),
        paragraphs = paragraphs,
        sections = sections,
        buttons = {
            { text = L(TEXT.release), url = RELEASES },
            { text = L(TEXT.copy), copy = table.concat(plain, "\n"), copied = L(TEXT.copied) },
            { text = L(TEXT.never), dismiss = DISMISSED },
            { text = L(TEXT.close), close = true },
        },
    }
end

local function localGame()
    if game.SinglePlayer() then return true end
    local ply = LocalPlayer()
    return IsValid(ply) and ply:IsListenServerHost()
end

hook.Add("InitPostEntity", "nativeloader_leftovers_popup", function()
    hook.Remove("InitPostEntity", "nativeloader_leftovers_popup")
    -- A moment after the map is in, as the companion's other notices.
    timer.Simple(4, function()
        if not localGame() then return end
        if file.Exists(DISMISSED, "DATA") then return end
        local state = serverState()
        -- The server removed the package and shows the short window itself.
        if state and (state.outcome == "removed" or state.outcome == "partly removed") then return end
        local ok, window = pcall(include, "nativeloader/leftovers_window.lua")
        if not ok or not istable(window) or not isfunction(window.Show) then return end
        window.Show(spec(state))
    end)
end)
