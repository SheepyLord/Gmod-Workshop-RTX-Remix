-- R23 (ADR 0130): the start-up watchdog's message in the player's language, for the engine guard's native
-- message box. Returns a function giving title, body (with one %s for the stuck file). It reads the
-- companion's own catalog (nativeloader/i18n_data.lua) for the language nativeloader_language names, else
-- gmod_language, so it works where nativeloader/i18n.lua cannot (the server realm, the early view of
-- includes/init.lua): never words from DATA, which any server's client Lua can write. English needs no
-- catalog. Documented in engine_guard_words.lua.md beside this file.
local function N(text) return text end
local TITLE = N("Garry's Mod is not finishing its start")
local BODY = N("Garry's Mod has spent 90 seconds on one add-on file while starting Lua:\n\n%s\n\nIf the game does not go on, that add-on is stuck: end the game and disable the add-on that has this file. The details are in garrysmod\\data\\native-loader\\startup-stall.json.")
local ALIASES = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }

local function setting(name)
    local convar = type(GetConVar) == "function" and GetConVar(name)
    local ok, value = pcall(function() return convar and convar:GetString() end)
    return ok and type(value) == "string" and value or ""
end

return function()
    local code = setting("nativeloader_language")
    if code == "" then code = setting("gmod_language") end
    code = ALIASES[code:lower()] or code
    if code == "" or code == "en" then return TITLE, BODY end
    local ok, data = pcall(include, "nativeloader/i18n_data.lua")
    local phrases = ok and type(data) == "table" and data[code]
    local title = type(phrases) == "table" and phrases[TITLE]
    local body = type(phrases) == "table" and phrases[BODY]
    if type(title) ~= "string" or title == "" then title = TITLE end
    if type(body) ~= "string" or not body:find("%s", 1, true) then body = BODY end
    return title, body
end
