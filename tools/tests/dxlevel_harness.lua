-- ADR 0246: runs the companion's nativeloader/prelude/dxlevel.lua under LuaJIT in a stand-in client realm that has
-- only what the engine registers before includes/init.lua (C functions: render.GetDXLevel, game.SinglePlayer,
-- GetConVar_Internal, CreateConVar, FindMetaTable), then checks what render.GetDXLevel() answers.
-- Arguments: the file, the scenario. Prints "PASS <scenario>"; an assertion failure exits non-zero.
local source, scenario = ...
local function eq(a, b, why) assert(a == b, (why or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- The engine's state: what the hardware level and the session's settings are.
local engineLevel, single = 80, false
local convarMeta = {}
convarMeta.__index = convarMeta
function convarMeta:GetBool() if self.broken then error("unreadable") end return (tonumber(self.value) or 0) ~= 0 end
function convarMeta:GetString() return self.value end
local convars, created = {}, {}
local function convar(name, value) convars[name] = setmetatable({name = name, value = value}, convarMeta) return convars[name] end
convar("mat_dxlevel", "90")

CLIENT, SERVER, MENU_DLL = true, false, nil
if scenario == "realm_server" then CLIENT, SERVER = false, true end
if scenario == "realm_menu" then CLIENT, MENU_DLL = false, true end
local engineGetDXLevel = function() return engineLevel end
render = {GetDXLevel = engineGetDXLevel}
game = {SinglePlayer = function() return single end}
function FindMetaTable(name) if name == "ConVar" then return convarMeta end end
function CreateConVar(name, value, flags, help)
    created[#created + 1] = {name = name, value = value, flags = flags, help = help}
    return convars[name] or convar(name, value)
end
if scenario == "guard_route" then
    -- After includes/init.lua (the render guard's routes): util.lua's GetConVar, no prelude marker.
    function GetConVar(name) return convars[name] end
else
    function GetConVar_Internal(name) return convars[name] end
    __NATIVELOADER_CLIENT_PRELUDE = true
end
if scenario == "missing_functions" then CreateConVar = nil end
if scenario == "missing_dxlevel" then convars.mat_dxlevel = nil end
if scenario == "server_metatable" then
    -- Server Lua on a remote server (the guard's late route) may have set metamethods on _G.
    setmetatable(_G, {__newindex = function() error("global write through __newindex") end})
end

local function run()
    local chunk = assert(loadfile(source))
    chunk()
end
run()

if scenario == "realm_server" or scenario == "realm_menu" or scenario == "missing_functions" then
    eq(render.GetDXLevel, engineGetDXLevel, "untouched")
    eq(rawget(_G, "NativeLoaderDXLevel"), nil)
    print("PASS " .. scenario)
    return
end

local api = rawget(_G, "NativeLoaderDXLevel")
assert(type(api) == "table", "NativeLoaderDXLevel published")
eq(api.version, 1) eq(api.switch, "nativeloader_multiplayer_dxlevel") eq(api.highest, nil)
eq(api.real, engineGetDXLevel, "the engine's own function")
eq(api.reported, render.GetDXLevel, "render.GetDXLevel is the reported level")
eq(api.installation, scenario == "guard_route" and "guard" or "prelude")
-- The switch: archived (FCVAR_ARCHIVE, 128), on by default, made once.
eq(#created, 1) eq(created[1].name, "nativeloader_multiplayer_dxlevel") eq(created[1].value, "1") eq(created[1].flags, 128)
assert(type(created[1].help) == "string" and #created[1].help > 0, "help text")
-- Nothing is hidden: the function says where it comes from.
local info = debug.getinfo(render.GetDXLevel, "S")
assert(info.what == "Lua" and info.source:find("dxlevel.lua", 1, true), "a Lua function of this file: " .. info.source)
local switch = convars.nativeloader_multiplayer_dxlevel

if scenario == "multiplayer" or scenario == "guard_route" or scenario == "server_metatable" then
    eq(render.GetDXLevel(), 90, "multiplayer: the level the game was started at")
    eq(render.GetDXLevel(), tonumber(convars.mat_dxlevel.value), "the same as the mat_dxlevel convar")
    eq(api.real(), 80, "the engine's own answer stays readable")
    -- Read at every call: the switch, single-player and the session's level.
    switch.value = "0" eq(render.GetDXLevel(), 80, "switched off")
    switch.value = "1" eq(render.GetDXLevel(), 90, "switched on again")
    single = true eq(render.GetDXLevel(), 80, "single-player keeps the engine's level")
    single = false eq(render.GetDXLevel(), 90)
    -- A reference taken after the install (a check that caches the function) reports the same.
    local cached = render.GetDXLevel
    eq(cached(), 90)
    -- Later replacements by a server's Lua do not change what it reads: the functions were taken at install.
    game.SinglePlayer = function() return true end
    convarMeta.GetBool = function() return false end
    eq(render.GetDXLevel(), 90, "captured at install")
elseif scenario == "single_player" then
    single = true
    eq(render.GetDXLevel(), 80, "single-player keeps the engine's level")
elseif scenario == "never_lower" then
    -- A level higher than the session's setting stays: the override only ever raises.
    engineLevel = 95
    eq(render.GetDXLevel(), 95)
    convars.mat_dxlevel.value = "81" engineLevel = 80
    eq(render.GetDXLevel(), 81, "the player's own -dxlevel 81 is what the game was started at")
    convars.mat_dxlevel.value = "70"
    eq(render.GetDXLevel(), 80, "never below the engine's level")
elseif scenario == "agrees" then
    -- Whatever the game was started at, render.GetDXLevel() answers what the mat_dxlevel convar says.
    for _, value in ipairs({"90", "95", "98"}) do
        convars.mat_dxlevel.value = value
        eq(render.GetDXLevel(), tonumber(value), "agrees with mat_dxlevel " .. value)
    end
    convars.mat_dxlevel.value = "95.7"
    eq(render.GetDXLevel(), 95, "whole levels, as GetInt reads them")
    for _, value in ipairs({"inf", "-inf", "1e999"}) do
        convars.mat_dxlevel.value = value
        eq(render.GetDXLevel(), 80, "not a finite number: " .. value)
    end
elseif scenario == "bad_values" then
    for _, value in ipairs({"", "abc", "nan", "0x", " "}) do
        convars.mat_dxlevel.value = value
        eq(render.GetDXLevel(), 80, "unreadable mat_dxlevel " .. value)
    end
    engineLevel = nil
    eq(render.GetDXLevel(), nil, "an engine answer that is not a number passes through")
elseif scenario == "switch_error" then
    -- A switch that cannot be read never makes render.GetDXLevel() raise an error: the engine's level.
    switch.broken = true
    local ok, level = pcall(render.GetDXLevel)
    assert(ok, "no error: " .. tostring(level))
    eq(level, 80)
elseif scenario == "missing_dxlevel" then
    eq(render.GetDXLevel(), 80, "no mat_dxlevel: the engine's level")
elseif scenario == "idempotent" then
    local first = render.GetDXLevel
    run()
    eq(render.GetDXLevel, first, "a second run changes nothing")
    eq(#created, 1, "the switch is made once")
    eq(rawget(_G, "NativeLoaderDXLevel"), api)
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
