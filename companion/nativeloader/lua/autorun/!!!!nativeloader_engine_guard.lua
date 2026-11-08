-- R23 (ADR 0130): the engine guard and the start-up watchdog (the nlengineguard binary module), before the
-- add-ons' autoruns: "!!!!" sorts before every name that does not itself start with four "!". Shared: in a
-- local game the server realm starts Lua first, and an add-on's shared autorun runs there first. Only in a
-- start where this machine's loader activated RTX: the material loop the guard cuts happens only under RTX's
-- shader paths, and a start through an off switch loads no native code. On a remote server the client realm
-- gets the module earlier from _nativeloader_guard.lua (the early view of includes/init.lua).
-- Documented in the .md beside this file.
if MENU_DLL then return end
if SERVER then AddCSLuaFile() end
if NativeLoaderEngineGuardAutorun then return end
NativeLoaderEngineGuardAutorun = true

local REPORT = "native-loader/startup-stall.json"
local SHOWN = "nativeloader_companion/startup_stall_shown.txt"

-- This machine's loader activated RTX in this start (as _nativeloader_guard.lua decides it): its
-- report says so, and a loader from 0.14.0 on also holds native-loader/rtx-session.txt open.
local function markerHeld()
    local ok, found = pcall(file.Exists, "native-loader/rtx-session.txt", "DATA")
    if ok and found == true then return true end
    local listed, names = pcall(file.Find, "native-loader/rtx-session.txt", "DATA")
    if listed and type(names) == "table" then
        for _, name in ipairs(names) do
            if type(name) == "string" and name:lower() == "rtx-session.txt" then return true end
        end
    end
    return false
end
local function rtxStart()
    if not (file and file.Read and file.Exists) then return false end
    local ok, text = pcall(file.Read, "native-loader/status.json", "DATA")
    if not ok or type(text) ~= "string" or text:find('"schema":1', 1, true) == nil then return markerHeld() end
    if text:find('\n"activation":{"outcome":"active"', 1, true) == nil then return false end
    local major, minor, patch = text:match('"loader_version":"(%d+)%.(%d+)%.(%d+)')
    local marking = major and (tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)) >= 14000
    return not marking or markerHeld()
end
if not rtxStart() then return end

local guard = rawget(_G, "nlengineguard")
if type(guard) ~= "table" then
    local loaded = pcall(require, "nlengineguard")
    guard = loaded and rawget(_G, "nlengineguard")
end
if type(guard) ~= "table" then return end

-- The watchdog's message in the player's language, from the companion's own catalog. The module takes only
-- the first call (in the client realm the early view has made it) and the function leaves the table, so no
-- later Lua, a server's included, sets the text of a native message.
if type(guard.SetMessage) == "function" then
    local title, body = "", ""
    local found, words = pcall(include, "nativeloader/engine_guard_words.lua")
    if found and type(words) == "function" then
        local ok, t, b = pcall(words)
        if ok and type(t) == "string" and type(b) == "string" then title, body = t, b end
    end
    pcall(guard.SetMessage, title, body)
    guard.SetMessage = nil
end

-- The end of the watch. Initialize, or the first tick when an add-on's failing Initialize hook stopped ours,
-- ends it at once; once the gamemode has loaded it ends at the latest 150 s later, so it never stretches
-- over a long map load, while a stall in an Initialize hook (90 s) is still reported. A start that was
-- reported and then went on needs no notice next time.
local function startupDone()
    if type(guard.StartupDone) ~= "function" then return end
    local ok, recovered = pcall(guard.StartupDone)
    if ok and recovered == true then file.Delete(REPORT) end
end
local function gamemodeLoaded()
    if type(guard.StartupDone) == "function" then pcall(guard.StartupDone, 150) end
end
hook.Add("OnGamemodeLoaded", "nativeloader_engine_guard", gamemodeLoaded)
hook.Add("PostGamemodeLoaded", "nativeloader_engine_guard", gamemodeLoaded)
hook.Add("Initialize", "nativeloader_engine_guard", startupDone)
timer.Simple(0, startupDone)

if SERVER then return end

-- The next start: a report left by a start that never got past Lua names the add-on, once.
local function addonOf(name)
    local path = name:gsub("^@", ""):gsub("\\", "/")
    local folder = path:match("^addons/([^/]+)/")
    if folder then return folder, path end
    local lua = path:find("^lua/") and path or "lua/" .. path
    if type(engine) == "table" and type(engine.GetAddons) == "function" then
        for _, addon in ipairs(engine.GetAddons() or {}) do
            if addon.mounted and type(addon.title) == "string" then
                local ok, found = pcall(file.Exists, lua, addon.title)
                if ok and found then return addon.title, lua end
            end
        end
    end
    local _, folders = file.Find("addons/*", "GAME")
    for _, name in ipairs(folders or {}) do
        if file.Exists("addons/" .. name .. "/" .. lua, "GAME") then return name, lua end
    end
    return nil, path
end

local function stallNotice()
    local text = file.Read(REPORT, "DATA")
    local report = type(text) == "string" and util.JSONToTable(text)
    if type(report) ~= "table" then return end
    local token = tostring(report.utc) .. " " .. tostring(report.process_id)
    if file.Read(SHOWN, "DATA") == token then return end
    file.CreateDir("nativeloader_companion")
    file.Write(SHOWN, token)
    local sample = type(report.samples) == "table" and report.samples[#report.samples]
    local name = sample and type(sample.lua) == "table" and sample.lua[1]
    if type(name) ~= "string" then return end
    local addon, path = addonOf(name)
    MsgN("[nativeloader] The last start stopped while starting Lua in " .. path ..
        (addon and (" (" .. addon .. ")") or "") .. " for " .. tostring(report.stalled_seconds) ..
        " s; details in garrysmod/data/" .. REPORT)
    local i18n = include("nativeloader/i18n.lua")
    local L = i18n and i18n.L or function(value) return value end
    local where = addon and string.format(L("%s, in the add-on %s"), path, addon) or path
    local Notice = include("nativeloader/notice.lua")
    if Notice then
        Notice.Show(string.format(L("The last start of Garry's Mod did not get past starting Lua. It stopped in %s.\nIf that happens again, disable that add-on."), where), { seconds = 30 })
    end
end
hook.Add("InitPostEntity", "nativeloader_engine_guard_notice", function()
    timer.Simple(8, function()
        local ok, reason = pcall(stallNotice)
        if not ok then MsgN("[nativeloader] start-up stall notice failed: " .. tostring(reason)) end
    end)
end)
