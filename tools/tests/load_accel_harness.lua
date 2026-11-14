-- Runs the load accelerator's Lua (R26) under LuaJIT with a mocked GMod and nlfsaccel module: the add-on's autorun
-- (fs_accel/addon/lua/autorun/!!!!!nlloadaccel.lua) or the companion's menu script (nativeloader/menu/load_accel.lua).
-- Usage: luajit <this> <addon.lua> <menu.lua> <scenario>. See the adjacent .md.
local addon_source, menu_source, scenario = ...

local log = {}
local function note(text) log[#log + 1] = text end
local function list() return table.concat(log, " | ") end
local function find(text)
    for _, line in ipairs(log) do if line:find(text, 1, true) then return line end end
end
local function eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

-- GMod.
local convars = {}
function CreateConVar(name, default)
    if not convars[name] then convars[name] = { value = default } end
    local item = convars[name]
    return { GetBool = function() return item.value ~= "0" end, GetString = function() return item.value end }
end
function GetConVar(name) return convars[name] and CreateConVar(name) end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function tobool(v) return v ~= nil and v ~= false and v ~= "0" and v ~= 0 end
FCVAR_ARCHIVE, FCVAR_NONE = 128, 0
string.Comma = function(n) return tostring(n) end
function print(text) note("print " .. tostring(text)) end
function MsgN(text) note("print " .. tostring(text)) end
local clock = 100
function SysTime() return clock end
local loading = false
function IsInLoading() return loading end
local OFF_FILE = "nativeloader/load_accel_off.txt"
local files = {}
file = {
    Exists = function(name) return files[name] ~= nil end,
    Write = function(name, text) files[name] = text note("write " .. name) end,
    Delete = function(name) files[name] = nil note("delete " .. name) end,
    CreateDir = function() end,
}
file.Read = function(name) return files[name] end
-- ADR 0206: an RTX start of this machine's loader (its report, its held marker), unless the scenario says otherwise.
if scenario ~= "not-rtx" then
    files["native-loader/status.json"] = '{"schema":1,"loader_version":"0.16.0",\n"activation":{"outcome":"active"}}'
    if scenario ~= "not-rtx-marker" then files["native-loader/rtx-session.txt"] = "" end
end
local timers = {}
timer = { Simple = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
local function run_timers()
    local due = timers
    timers = {}
    for _, item in ipairs(due) do item.fn() end
end
local hooks = {}
hook = {
    Add = function(event, name, fn) hooks[event .. "/" .. name] = fn end,
    Remove = function(event, name) hooks[event .. "/" .. name] = nil end,
}
cvars = { AddChangeCallback = function(name, fn) hooks["cvar/" .. name] = fn end }
util = { IsBinaryModuleInstalled = function(name) return name == "nlfsaccel" and scenario ~= "no-module" end,
    TableToJSON = function() return "{}" end }
game = { IsDedicated = function() return scenario == "server-dedicated" end }
local ADDONS = {
    { title = "Alpha", mounted = true }, { title = "Beta", mounted = true }, { title = "Gamma", mounted = false },
    { title = "Delta", mounted = true }, { title = "Epsilon", mounted = true },
}
if scenario == "selftest-none" then
    for _, addon in ipairs(ADDONS) do addon.mounted = false end
end
engine = { GetAddons = function() return ADDONS end, GetGames = function() return { { folder = "cstrike" } } end }

-- GMod's file.Find and the module's index: the same answers unless a scenario says otherwise.
local function gmod_answer(pattern, path)
    if path == "GAME" or path == "cstrike" then return { "game.txt" }, { "materials" } end
    if scenario == "selftest-skip" and path == "Alpha" then return {}, {} end  -- a title GMod's table does not hold
    return { pattern .. "@" .. path }, { "dir" }
end
local gmod_calls = 0
file.Find = function(pattern, path, sorting)
    gmod_calls = gmod_calls + 1
    local files_, dirs = gmod_answer(pattern, path)
    if sorting == "namedesc" then return { "desc:" .. (files_[1] or "") }, dirs end
    return files_, dirs
end

local installed = false
local LEFT_OUT = "left out once: the last start with the hooks ended before a map had loaded with them"
local index_calls = 0
local module = {
    Status = function() return { installed = installed, answered = 41, roots = 7, finds_served = 3, disagreements = 0 } end,
    Install = function()
        note("install")
        if scenario == "left-out" or scenario == "menu-left-out" then return false, LEFT_OUT end
        installed = true
        return true, "installed"
    end,
    SetVerify = function(on) note("verify " .. tostring(on)) end,
    Invalidate = function() note("invalidate") end,
    CountFind = function(served) note("count " .. tostring(served)) end,
    Settled = function() note("settled") end,
    FindInAddon = function(pattern, title)
        index_calls = index_calls + 1
        if title == "Nobody" then return nil, "no add-on has this title" end
        if scenario == "selftest-skip" and title == "Alpha" then return nil, "no add-on has this title" end
        if scenario == "selftest-changing" and index_calls == 1 then return nil, "GMod's add-on table is changing" end
        if scenario == "selftest-mismatch" then return { "other" }, {} end
        if scenario == "verify" and pattern == "later/*" then return { "stale" }, {} end
        return gmod_answer(pattern, title)
    end,
}
function require(name)
    note("require " .. name)
    nlfsaccel = module
end

if scenario:sub(1, 5) == "menu-" then
    MENU_DLL = scenario ~= "menu-not-menu" or nil
    if scenario == "menu-off" then files[OFF_FILE] = "nativeloader_load_accel 0" end
    dofile(menu_source)
    if scenario == "menu-install" then
        eq(installed, true, "installed at menu start")
        assert(NativeLoaderLoadAccel == module, "the module for the overlay")
        eq(convars.nativeloader_load_accel, nil, "no convar of the menu realm's own")
        eq(find("write "), nil, "the menu realm writes no file")
        assert(find("loose add-on folders cached"), list())
        -- The marker may come off 10 s after the first load ends, not before a load, nor during one.
        local think = hooks["Think/NativeLoaderLoadAccel"]
        assert(think, "a Think hook waits for the first load")
        clock = clock + 30
        think()
        eq(find("settled"), nil, "no load yet")
        loading = true
        think()
        clock = clock + 60
        think()
        eq(find("settled"), nil, "still loading")
        loading = false
        think()
        clock = clock + 9
        think()
        eq(find("settled"), nil, "9 s after the load")
        clock = clock + 2
        think()
        assert(find("settled"), list())
        eq(hooks["Think/NativeLoaderLoadAccel"], nil, "the hook removed")
    elseif scenario == "menu-left-out" then
        eq(installed, false, "left out once")
        eq(NativeLoaderLoadAccel, false, "no module for the overlay")
        assert(find("file lookups are GMod's own: " .. LEFT_OUT), list())
        eq(hooks["Think/NativeLoaderLoadAccel"], nil, "nothing to settle")
    elseif scenario == "menu-off" then
        eq(find("require"), nil, "nothing loaded")
        assert(find("off (nativeloader_load_accel 0)"), list())
    elseif scenario == "menu-not-menu" then
        eq(find("require"), nil, "nothing loaded")
    else
        error("unknown scenario " .. scenario)
    end
    io.write("PASS " .. scenario .. "\n")
    return
end

CLIENT = (scenario == "tally" or scenario == "off-client" or scenario == "on-client") or nil
SERVER = not CLIENT or nil
if scenario == "off" or scenario == "off-client" then CreateConVar("nativeloader_load_accel", "0") end
if scenario == "on-client" then files[OFF_FILE] = "nativeloader_load_accel 0" end
if scenario == "verify" then CreateConVar("nativeloader_load_accel_verify", "1") end
local gmod_find = file.Find
dofile(addon_source)

if scenario == "serve" then
    eq(installed, true, "installed")
    eq(find("write "), nil, "no file written")
    eq(find("verify "), nil, "the checks' switch left alone while off")
    assert(file.Find ~= gmod_find, "file.Find replaced")
    local before = gmod_calls
    local found, dirs = file.Find("lua/*", "Alpha")
    eq(found[1], "lua/*@Alpha")
    eq(dirs[1], "dir")
    assert(gmod_calls > before, "the self-test asked GMod first")
    local after_selftest = gmod_calls
    found = file.Find("materials/*", "Beta")
    eq(found[1], "materials/*@Beta")
    eq(gmod_calls, after_selftest, "answered from the index, GMod not asked")
    assert(find("count true"), list())
    -- Search paths, date sorting: GMod's own.
    found = file.Find("x", "GAME")
    eq(found[1], "game.txt")
    found = file.Find("x", "cstrike")
    eq(found[1], "game.txt")
    file.Find("x", "Alpha", "datedesc")
    eq(gmod_calls, after_selftest + 3, "GMod asked for GAME, a game's folder and a date sorting")
    -- namedesc: the index's answer reversed.
    found = file.Find("a/*", "Alpha", "namedesc")
    eq(found[1], "a/*@Alpha")
elseif scenario == "not-title" then
    local found = file.Find("x/*", "Nobody")
    eq(found[1], "x/*@Nobody")
    assert(find("count false"), list())
elseif scenario == "selftest-mismatch" then
    local found = file.Find("lua/*", "Alpha")
    eq(found[1], "lua/*@Alpha", "GMod's answer")
    assert(find("add-on searches are GMod's own"), list())
    local calls = gmod_calls
    file.Find("materials/*", "Beta")
    eq(gmod_calls, calls + 1, "GMod asked for every later search too")
elseif scenario == "selftest-skip" then
    -- Alpha is listed as mounted but GMod's table does not hold it (GMod finds nothing either): tested with others.
    local found = file.Find("lua/*", "Beta")
    eq(found[1], "lua/*@Beta")
    eq(find("add-on searches are GMod's own"), nil, list())
    assert(find("count true"), list())
elseif scenario == "selftest-none" then
    -- No mounted add-on to compare with: the index is not trusted.
    file.Find("lua/*", "Alpha")
    assert(find("add-on searches are GMod's own: no mounted add-on to test the index with"), list())
elseif scenario == "selftest-changing" then
    -- GMod's table changing during the self-test: no verdict, GMod answers; the next search tests again and trusts.
    local calls = gmod_calls
    local found = file.Find("lua/*", "Beta")
    eq(found[1], "lua/*@Beta")
    eq(find("count"), nil, "not counted: no verdict yet")
    eq(find("add-on searches are GMod's own"), nil, list())
    assert(gmod_calls > calls, "GMod answered")
    file.Find("lua/*", "Beta")
    assert(find("count true"), list())
elseif scenario == "verify" then
    assert(find("verify true"), list())
    local found = file.Find("later/*", "Alpha")
    eq(found[1], "later/*@Alpha", "GMod's answer when the index differs")
    assert(find("check: \"later/*\""), list())
elseif scenario == "left-out" then
    -- The hooks left out once (the module's marker): one line; the add-on searches still go through the index.
    eq(installed, false, "left out once")
    assert(find("file lookups are GMod's own: " .. LEFT_OUT), list())
    assert(file.Find ~= gmod_find, "file.Find replaced")
    local found = file.Find("lua/*", "Alpha")
    eq(found[1], "lua/*@Alpha")
elseif scenario == "not-rtx" or scenario == "not-rtx-marker" then
    -- A start without RTX (an off switch, a removed loader): no convar, no module, GMod's own file.Find.
    eq(find("require"), nil, "nothing loaded")
    eq(GetConVar("nativeloader_load_accel"), nil, "no convar")
    eq(file.Find, gmod_find, "file.Find untouched")
elseif scenario == "off" or scenario == "no-module" then
    eq(find("require"), nil, "nothing loaded")
    eq(file.Find, gmod_find, "file.Find untouched")
    eq(files[OFF_FILE], nil, "the server realm keeps no file for the menu")
elseif scenario == "off-client" then
    -- Off: the client keeps it for the menu realm; turned on again, the file goes.
    eq(find("require"), nil, "nothing loaded")
    assert(files[OFF_FILE], "the file for the menu written: " .. list())
    hooks["cvar/nativeloader_load_accel"]("nativeloader_load_accel", "0", "1")
    eq(files[OFF_FILE], nil, "removed when turned on again")
elseif scenario == "on-client" then
    eq(files[OFF_FILE], nil, "a file left from an earlier off removed")
    assert(find("require nlfsaccel"), list())
elseif scenario == "invalidate" then
    hooks["GameContentChanged/nlloadaccel"]()
    assert(find("invalidate"), list())
elseif scenario == "tally" then
    hooks["InitPostEntity/nlloadaccel"]()
    run_timers()
    assert(find("41 file lookups answered from memory in 7 folders; 3 add-on searches answered from the index"), list())
    assert(find("settled"), list())
elseif scenario == "server-dedicated" or scenario == "server-listen" then
    -- A dedicated server has no menu realm: its own InitPostEntity settles. A listen server's comes before its client
    -- has loaded: the client (and the menu) settle there.
    hooks["InitPostEntity/nlloadaccel"]()
    run_timers()
    if scenario == "server-dedicated" then
        assert(find("settled"), list())
    else
        eq(find("settled"), nil, list())
    end
    eq(find("file lookups answered from memory"), nil, "no tally on the server")
else
    error("unknown scenario " .. scenario)
end
io.write("PASS " .. scenario .. "\n")
