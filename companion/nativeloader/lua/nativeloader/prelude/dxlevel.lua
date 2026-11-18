-- ADR 0246: the DirectX level a server sees from an RTX start.
--
-- Under RTX the runtime offers Source no shaders (d3d9.shaderModel 0), so Source draws with its fixed-function
-- shaders and render.GetDXLevel() answers 80, although the game was started at mat_dxlevel 90 (the package's
-- -dxlevel 90). Servers that refuse clients below 90 (a check meant for DirectX 8 players) refused every RTX
-- player. In a multiplayer game render.GetDXLevel() here answers the level the game was started at, mat_dxlevel,
-- when that is higher, so a check that calls it and one that reads the mat_dxlevel convar (GetConVar, GetConVarNumber,
-- cvars.Number; the console's mat_dxlevel) agree. Single-player, and nativeloader_multiplayer_dxlevel 0, keep the
-- engine's answer. Nothing is hidden: the global NativeLoaderDXLevel says so and gives the engine's own answer (real)
-- to any Lua, a server's included. The render.Supports* functions, mat_info and what Source renders stay as they are.
--
-- The RTX client module runs this in each client realm before the engine runs that realm's includes/init.lua
-- (installation "prelude"), so before any Lua a server sends; the render guard runs it where the module did not
-- (installation "guard"). Before includes/init.lua only the engine's C functions exist: no GetConVar, no
-- CreateClientConVar, no FCVAR_ constants.
if SERVER or MENU_DLL or not CLIENT then return end
local G = _G
if type(rawget(G, "NativeLoaderDXLevel")) == "table" then return end
local render, game = rawget(G, "render"), rawget(G, "game")
local real = type(render) == "table" and rawget(render, "GetDXLevel")
local singlePlayer = type(game) == "table" and rawget(game, "SinglePlayer")
local findConVar = rawget(G, "GetConVar_Internal") or rawget(G, "GetConVar")
local createConVar, findMeta = rawget(G, "CreateConVar"), rawget(G, "FindMetaTable")
if type(real) ~= "function" or type(singlePlayer) ~= "function" or type(findConVar) ~= "function"
    or type(createConVar) ~= "function" or type(findMeta) ~= "function" then return end
local convar = findMeta("ConVar")
local getBool, getString = type(convar) == "table" and convar.GetBool, type(convar) == "table" and convar.GetString
if type(getBool) ~= "function" or type(getString) ~= "function" then return end
local SWITCH = "nativeloader_multiplayer_dxlevel"
-- 128: FCVAR_ARCHIVE, so the player's choice is kept.
local made, switch = pcall(createConVar, SWITCH, "1", 128,
    "1: in a multiplayer game, render.GetDXLevel() reports the DirectX level the game was started at (mat_dxlevel) "
    .. "instead of the level RTX runs Source at; 0: the engine's own answer")
if not made or switch == nil then return end
local found, started = pcall(findConVar, "mat_dxlevel")
if not found then started = nil end
local floor, tonumber, type, pcall = math.floor, tonumber, type, pcall
local api = {version = 1, switch = SWITCH, real = real,
    installation = rawget(G, "__NATIVELOADER_CLIENT_PRELUDE") == true and "prelude" or "guard"}
-- What render.GetDXLevel() answers: the engine's level, or mat_dxlevel (whole levels, as the convar's GetInt reads it)
-- where that is higher in a multiplayer game with the switch on. The engine's level is never above mat_dxlevel, so there
-- the two agree. It never raises an error: whatever cannot be read gives the engine's level.
local function reported()
    local level = real()
    if type(level) ~= "number" or started == nil or singlePlayer() then return level end
    local read, on = pcall(getBool, switch)
    if not read or not on then return level end
    local ok, text = pcall(getString, started)
    local configured = ok and tonumber(text)
    -- Not a finite number (nan, inf): the engine's level.
    if not configured or configured - configured ~= 0 then return level end
    configured = floor(configured)
    if configured > level then return configured end
    return level
end
api.reported = reported
render.GetDXLevel = reported
rawset(G, "NativeLoaderDXLevel", api)
