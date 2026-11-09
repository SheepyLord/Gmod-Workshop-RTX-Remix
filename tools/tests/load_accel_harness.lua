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
local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end

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
local files = {}
file = {
    Exists = function(name) return files[name] ~= nil end,
    Write = function(name, text) files[name] = text note("write " .. name) end,
    Delete = function(name) files[name] = nil note("delete " .. name) end,
    CreateDir = function() end,
}
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
local ADDONS = {
    { title = "Alpha", mounted = true }, { title = "Beta", mounted = true }, { title = "Gamma", mounted = false },
    { title = "Delta", mounted = true }, { title = "Epsilon", mounted = true },
}
engine = { GetAddons = function() return ADDONS end, GetGames = function() return { { folder = "cstrike" } } end }

-- GMod's file.Find and the module's index: the same answers unless a scenario says otherwise.
local function gmod_answer(pattern, path)
    if path == "GAME" or path == "cstrike" then return { "game.txt" }, { "materials" } end
    return { pattern .. "@" .. path }, { "dir" }
end
local gmod_calls = 0
file.Find = function(pattern, path, sorting)
    gmod_calls = gmod_calls + 1
    local files_, dirs = gmod_answer(pattern, path)
    if sorting == "namedesc" then return { "desc:" .. files_[1] }, dirs end
    return files_, dirs
end

local installed = false
local LEFT_OUT = "left out once: the last start with the hooks ended within 20 s of installing them"
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
    FindInAddon = function(pattern, title)
        if title == "Nobody" then return nil, "no add-on has this title" end
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
    if scenario == "menu-off" then CreateConVar("nativeloader_load_accel", "0") end
    dofile(menu_source)
    if scenario == "menu-install" then
        eq(installed, true, "installed at menu start")
        assert(NativeLoaderLoadAccel == module, "the module for the overlay")
        eq(find("write "), nil, "the menu realm writes no file")
        assert(find("loose add-on folders cached"), list())
    elseif scenario == "menu-left-out" then
        eq(installed, false, "left out once")
        eq(NativeLoaderLoadAccel, false, "no module for the overlay")
        assert(find("file lookups are GMod's own: " .. LEFT_OUT), list())
    elseif scenario == "menu-not-menu" or scenario == "menu-off" then
        eq(find("require"), nil, "nothing loaded")
    else
        error("unknown scenario " .. scenario)
    end
    print_ = nil
    io.write("PASS " .. scenario .. "\n")
    return
end

CLIENT = scenario == "tally" or nil
SERVER = not CLIENT or nil
if scenario == "off" then CreateConVar("nativeloader_load_accel", "0") end
if scenario == "verify" then CreateConVar("nativeloader_load_accel_verify", "1") end
local gmod_find = file.Find
dofile(addon_source)

if scenario == "serve" then
    eq(installed, true, "installed")
    eq(find("write "), nil, "no file written")
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
elseif scenario == "off" or scenario == "no-module" then
    eq(find("require"), nil, "nothing loaded")
    eq(file.Find, gmod_find, "file.Find untouched")
elseif scenario == "invalidate" then
    hooks["GameContentChanged/nlloadaccel"]()
    assert(find("invalidate"), list())
elseif scenario == "tally" then
    hooks["InitPostEntity/nlloadaccel"]()
    run_timers()
    assert(find("41 file lookups answered from memory in 7 folders; 3 add-on searches answered from the index"), list())
else
    error("unknown scenario " .. scenario)
end
io.write("PASS " .. scenario .. "\n")
