-- Runs the companion's real !!!!nativeloader_engine_guard.lua and nativeloader/engine_guard_words.lua
-- (R23, ADR 0130) against mocked DATA, convars, the catalog, the nlengineguard module, hooks and timers.
-- See the adjacent .md.
local root, scenario = ...
local lua = root .. "/companion/nativeloader/lua/"
local data, hooks, jobs, now, serial = {}, {}, {}, 0, 0
local jsonValues, required, calls, notices, logs = {}, 0, {}, {}, {}
local recovered, moduleMissing = false, false
local addons, addonFiles, legacyFolders = {}, {}, {}
local convars, catalogReads = { gmod_language = "en" }, 0
local TITLE = "Garry's Mod is not finishing its start"

local function reset(realm)
    CLIENT, SERVER, MENU_DLL = realm == "client", realm == "server", nil
    NativeLoaderEngineGuardAutorun, nlengineguard = nil, nil
    hooks, jobs = {}, {}
end
function AddCSLuaFile() end
function MsgN(text) logs[#logs + 1] = text end
function GetConVar(name)
    if convars[name] == nil then return nil end
    return { GetString = function() return convars[name] end }
end
local function status(version, outcome)
    return '{"schema":1,"loader_version":"' .. version .. '"\n"activation":{"outcome":"' .. outcome .. '"}}'
end
file = {
    Read = function(path) return data[path] end,
    Write = function(path, value) data[path] = value end,
    CreateDir = function() end,
    Delete = function(path) data[path] = nil end,
    Exists = function(path, where)
        if where == "DATA" then return data[path] ~= nil end
        if where == "GAME" then return addonFiles["GAME:" .. path] == true end
        return addonFiles[where .. ":" .. path] == true
    end,
    Find = function(pattern, where)
        if where == "GAME" and pattern == "addons/*" then return {}, legacyFolders end
        return {}, {}
    end,
}
util = { JSONToTable = function(text) return jsonValues[text] end }
local function module()
    return {
        installed = true,
        SetMessage = function(title, body) calls[#calls + 1] = "message " .. title .. "|" .. body end,
        StartupDone = function(seconds)
            calls[#calls + 1] = seconds and ("deadline " .. seconds) or "done"
            return seconds == nil and recovered
        end,
    }
end
function require(name)
    required = required + 1
    assert(name == "nlengineguard")
    if moduleMissing then error("Module not found!") end
    nlengineguard = module()
end
function include(path)
    if path == "nativeloader/engine_guard_words.lua" then return dofile(lua .. path) end
    if path == "nativeloader/i18n_data.lua" then
        catalogReads = catalogReads + 1
        return { ja = { [TITLE] = "JA-TITLE" } } -- a body without %s keeps the English
    end
    if path == "nativeloader/i18n.lua" then return { L = function(s) return "T:" .. s end } end
    if path == "nativeloader/notice.lua" then
        return { Show = function(text, options) notices[#notices + 1] = { text = text, options = options } end }
    end
    error("unexpected include " .. path)
end
hook = { Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end }
local function run(event) for _, fn in pairs(hooks[event] or {}) do fn() end end
timer = { Simple = function(delay, fn) serial = serial + 1 jobs[serial] = { at = now + delay, fn = fn } end }
local function advance(seconds)
    local target = now + seconds
    while true do
        local id, due
        for key, job in pairs(jobs) do if job.at <= target and (not due or job.at < due.at) then id, due = key, job end end
        if not due then break end
        now, jobs[id] = due.at, nil
        due.fn()
    end
    now = target
end
engine = { GetAddons = function() return addons end }
local function boot(realm)
    reset(realm)
    dofile(lua .. "autorun/!!!!nativeloader_engine_guard.lua")
end
local function rtx(version)
    data["native-loader/status.json"] = status(version or "0.16.0", "active")
    data["native-loader/rtx-session.txt"] = ""
end
local REPORT = "native-loader/startup-stall.json"
local function report(name)
    local text = "REPORT[" .. name .. "]"
    jsonValues[text] = { utc = "2026-11-08T12:00:00Z", process_id = 4321, stalled_seconds = 93,
        samples = { { where = "x", lua = { "nope.lua" } }, { where = "materialsystem.dll+0xfb53", lua = { name, "@lua/autorun/a.lua" } } } }
    data[REPORT] = text
end

if scenario == "off" then
    data["native-loader/status.json"] = status("0.16.0", "inactive")
    boot("client")
    assert(required == 0 and next(hooks) == nil and next(jobs) == nil, "nothing without an RTX start")
    -- A report from 0.14.0 on needs the session marker: an off-switched start keeps the old report.
    data["native-loader/status.json"] = status("0.16.0", "active")
    boot("client")
    assert(required == 0, "no marker, no module")
    -- An older loader holds no marker: its report decides.
    data["native-loader/status.json"] = status("0.13.0", "active")
    boot("server")
    assert(required == 1, "a 0.13.0 report alone")
    -- No readable report: the marker alone.
    data["native-loader/status.json"], data["native-loader/rtx-session.txt"] = nil, ""
    boot("client")
    assert(required == 2)
elseif scenario == "client" then
    rtx()
    boot("client")
    assert(required == 1 and #calls == 1, "the module and its message")
    assert(calls[1]:find("^message Garry's Mod is not finishing its start|Garry's Mod has spent 90 seconds"), calls[1])
    assert(calls[1]:find("%s", 1, true), "the body keeps %s")
    assert(catalogReads == 0, "English reads no catalog")
    assert(nlengineguard.SetMessage == nil, "removed after the first call: no other Lua sets the text")
    for path in pairs(data) do assert(not path:find("engine_guard_message", 1, true), "no words in DATA") end
    run("OnGamemodeLoaded") run("PostGamemodeLoaded")
    assert(calls[2] == "deadline 150" and calls[3] == "deadline 150", "the gamemode's load bounds the watch")
    run("Initialize")
    assert(calls[4] == "done", "Initialize ends it")
    advance(0)
    assert(calls[5] == "done", "and the first tick, whatever an earlier hook did")
elseif scenario == "server" then
    -- The server realm reads the companion's catalog itself, in the player's language.
    rtx()
    convars.gmod_language = "ja"
    boot("server")
    assert(required == 1 and #calls == 1 and catalogReads == 1)
    assert(calls[1]:find("^message JA%-TITLE|Garry's Mod has spent 90 seconds"), calls[1])
    assert(hooks.InitPostEntity == nil, "no notice in the server realm")
    -- nativeloader_language wins over gmod_language; aliases map as the companion maps them.
    convars.nativeloader_language = "zh"
    calls, catalogReads = {}, 0
    boot("server")
    assert(catalogReads == 1 and calls[1]:find("^message Garry's Mod is not finishing its start|"), calls[1])
elseif scenario == "already-loaded" then
    -- The early view loaded the module and made the first call: the autorun neither loads nor sets again.
    rtx()
    reset("client")
    nlengineguard = module()
    nlengineguard.SetMessage = nil
    dofile(lua .. "autorun/!!!!nativeloader_engine_guard.lua")
    assert(required == 0 and #calls == 0, "the early view's module is used as it is")
    assert(hooks.Initialize and hooks.Initialize.nativeloader_engine_guard, "the watch still ends here")
elseif scenario == "no-module" then
    rtx()
    moduleMissing = true
    boot("client")
    assert(required == 1 and next(hooks) == nil and #calls == 0, "without the module, nothing else")
elseif scenario == "recovered" then
    rtx()
    report("lua/autorun/slow.lua")
    recovered = true
    boot("server")
    run("PostGamemodeLoaded")
    assert(data[REPORT] ~= nil, "a deadline is not the end of the start")
    run("Initialize")
    assert(data[REPORT] == nil, "a start that went on after all leaves no report")
elseif scenario == "notice" then
    rtx()
    report("@lua/arc9/shared/sh_csgo_effects.lua")
    addons = { { title = "Unrelated", mounted = true }, { title = "[ARC9] Gunsmith Reloaded", mounted = true },
        { title = "Unmounted", mounted = false } }
    addonFiles["[ARC9] Gunsmith Reloaded:lua/arc9/shared/sh_csgo_effects.lua"] = true
    addonFiles["Unmounted:lua/arc9/shared/sh_csgo_effects.lua"] = true
    boot("client")
    run("InitPostEntity")
    advance(7.9)
    assert(#notices == 0, "not before eight seconds")
    advance(0.2)
    assert(#notices == 1, "one notice")
    local text = notices[1].text
    assert(text:find("^T:The last start of Garry's Mod did not get past starting Lua"), text)
    assert(text:find("lua/arc9/shared/sh_csgo_effects.lua", 1, true) and text:find("[ARC9] Gunsmith Reloaded", 1, true), text)
    assert(notices[1].options.seconds == 30)
    assert(logs[1]:find("lua/arc9/shared/sh_csgo_effects.lua ([ARC9] Gunsmith Reloaded) for 93 s", 1, true), logs[1])
    -- The next map, the next start: shown once.
    boot("client")
    run("InitPostEntity")
    advance(9)
    assert(#notices == 1, "the same report is not shown again")
    -- A legacy add-on folder.
    report("addons/my_weapons/lua/autorun/loop.lua")
    jsonValues[data[REPORT]].utc = "2026-11-09T00:00:00Z"
    boot("client")
    run("InitPostEntity")
    advance(9)
    assert(#notices == 2 and notices[2].text:find("in the add-on my_weapons", 1, true)
        and notices[2].text:find("addons/my_weapons/lua/autorun/loop.lua", 1, true), notices[2].text)
    -- A file no mounted add-on has: the path alone.
    report("lua/autorun/nowhere.lua")
    jsonValues[data[REPORT]].utc = "2026-11-10T00:00:00Z"
    boot("client")
    run("InitPostEntity")
    advance(9)
    assert(#notices == 3 and notices[3].text:find("It stopped in lua/autorun/nowhere.lua.", 1, true), notices[3].text)
else
    error("Unknown scenario " .. scenario)
end
print("PASS " .. scenario)
