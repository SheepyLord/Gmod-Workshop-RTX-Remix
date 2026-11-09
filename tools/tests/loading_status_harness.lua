-- Runs the companion's real nativeloader/menu/loading_status.lua (R24, ADR 0134) in a mocked menu realm: the engine
-- guard module's overlay functions, the menu's IsInLoading/GetLoadStatus, its Think hook, GameDetails, convars and
-- the module's read API. Usage: luajit <this> <repo> <scenario>. See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/companion/nativeloader/lua/nativeloader/menu/loading_status.lua"

local calls, logs, convars, hosting, requireFails = {}, {}, { gmod_language = "en" }, true, false
local inLoading, loadStatus, clock, thinks = false, "", 100, {}
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function MsgN(text) logs[#logs + 1] = text end
function SysTime() return clock end
function CompileString(source, name) return loadstring(source, name) end
FCVAR_ARCHIVE = 128
function CreateConVar(name, default)
    convars[name] = convars[name] or default
    return { GetBool = function() return convars[name] ~= "0" end }
end
function GetConVar(name)
    if convars[name] == nil then return nil end
    return { GetString = function() return convars[name] end }
end
function IsHostingGame() return hosting end
function IsInLoading() return inLoading end
function GetLoadStatus() return loadStatus end
hook = { Add = function(event, id, fn) thinks[event .. ":" .. id] = fn end }
local function think() for _, fn in pairs(thinks) do fn() end end

local guardModule = {
    LoadStart = function(heading, labels) calls[#calls + 1] = "start " .. heading .. " lua=" .. labels.lua .. " file=" .. labels.file end,
    LoadHeading = function(text) calls[#calls + 1] = "heading " .. text end,
    LoadStatus = function(text) calls[#calls + 1] = "status " .. text end,
    LoadEnd = function()
        calls[#calls + 1] = "end"
        return { seconds = 47.25, lua = { { name = "lua/arc9/shared/sh_atts.lua", seconds = 5.5 }, { name = "lua/autorun/x.lua", seconds = 0.25 } } }
    end,
}
function require(name)
    eq(name, "nlengineguard")
    if requireFails then error("Module not found!") end
    nlengineguard = guardModule
end
local stockArgs
function GameDetails(...)
    stockArgs = { ... }
    calls[#calls + 1] = "stock details " .. stockArgs[3]
end

local function run()
    MENU_DLL = true
    __NATIVELOADER_MENU_API = { read = function(name)
        eq(name, "nativeloader/nativeloader/i18n_data.lua")
        return 'return { ja = { ["Loading…"] = "JA-LOADING", ["Loading %s"] = "%s JA", ["File"] = "JA-FILE" } }'
    end }
    dofile(SCRIPT)
    __NATIVELOADER_MENU_API = nil
end
local function has(text)
    for _, c in ipairs(calls) do if c == text then return true end end
    return false
end
local function count(text)
    local n = 0
    for _, c in ipairs(calls) do if c == text then n = n + 1 end end
    return n
end

if scenario == "load" then
    run()
    think()
    eq(#calls, 0, "nothing while not loading")
    inLoading, loadStatus = true, "  Loading world...  "
    think()
    assert(has("start Loading… lua=Lua file=File"), table.concat(calls, " | "))
    assert(has("status Loading world..."), "the stock status, trimmed")
    think()
    eq(count("status Loading world..."), 1, "an unchanged status is not sent again")
    loadStatus = "Starting Lua"
    think()
    assert(has("status Starting Lua"))
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    assert(has("heading Loading gm_construct") and has("stock details gm_construct"), table.concat(calls, " | "))
    inLoading = false
    think()
    assert(has("end"))
    assert(logs[1]:find("map loaded in 47.2 s", 1, true) or logs[1]:find("map loaded in 47.3 s", 1, true), logs[1])
    assert(logs[1]:find("lua/arc9/shared/sh_atts.lua (5.5 s)", 1, true), logs[1])
    assert(not logs[1]:find("x.lua", 1, true), "a file seen under half a second is left out")
    eq(NativeLoaderLoadStatus.loads, 1)
    -- The next load starts a new overlay.
    inLoading = true
    think()
    eq(NativeLoaderLoadStatus.loads, 2)
elseif scenario == "details-first" then
    run()
    -- GameDetails can come in the frame before the load is seen.
    GameDetails("Garry's Mod", "127.0.0.1", "gm_flatgrass", 1)
    assert(not has("heading Loading gm_flatgrass"), "no heading outside a load")
    inLoading = true
    think()
    assert(has("start Loading gm_flatgrass lua=Lua file=File"), table.concat(calls, " | "))
    -- A heading from long ago is not used.
    inLoading = false
    think()
    clock = clock + 60
    inLoading = true
    think()
    assert(has("start Loading… lua=Lua file=File"), table.concat(calls, " | "))
elseif scenario == "joining" then
    run()
    hosting = false
    inLoading = true
    think()
    GameDetails("Some Server", "http://x", "rp_downtown", 32)
    assert(has("heading Joining Some Server · rp_downtown"), table.concat(calls, " | "))
elseif scenario == "local" then
    -- The PoC (R24): a single-player game's load was first "Loading gm_construct", then the engine named its own
    -- server while IsHostingGame() read false, and the heading became "Joining My Garry's Mod Server".
    run()
    inLoading = true
    think()
    GameDetails("My Garry's Mod Server", "", "gm_construct", 1, 1, "", "sandbox")
    hosting = false
    GameDetails("My Garry's Mod Server", "", "gm_construct", 1, 1, "", "sandbox")
    eq(count("heading Loading gm_construct"), 2, table.concat(calls, " | "))
    -- A listen server: the panel's call while hosting passes one player; the engine's own call has the slots.
    inLoading = false
    think()
    hosting = true
    inLoading = true
    think()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_flatgrass", 1, 1, "", "sandbox")
    hosting = false
    GameDetails("A Listen Server", "", "gm_flatgrass", 8, 8, "", "sandbox")
    eq(count("heading Loading gm_flatgrass"), 2, table.concat(calls, " | "))
    -- The stock function gets every argument.
    eq(stockArgs[1], "A Listen Server")
    eq(stockArgs[4], 8)
    eq(stockArgs[5], 8)
    eq(stockArgs[7], "sandbox")
    -- The next load, a server joined, is named as one: "hosted" ends with the load.
    inLoading = false
    think()
    inLoading = true
    think()
    GameDetails("Some Server", "http://x", "rp_downtown", 32)
    assert(has("heading Joining Some Server · rp_downtown"), table.concat(calls, " | "))
elseif scenario == "translated" then
    convars.gmod_language = "ja"
    run()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_flatgrass", 1)
    inLoading = true
    think()
    assert(has("start gm_flatgrass JA lua=Lua file=JA-FILE"), table.concat(calls, " | "))
elseif scenario == "menu-compile" then
    -- GMod's menu realm has no CompileString, only RunString (PoC, R24).
    CompileString = nil
    RunString = function(code, identifier, handleError)
        eq(identifier, "nativeloader/i18n_data.lua")
        eq(handleError, false)
        assert(loadstring(code, identifier))()
    end
    convars.gmod_language = "ja"
    run()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_flatgrass", 1)
    inLoading = true
    think()
    assert(has("start gm_flatgrass JA lua=Lua file=JA-FILE"), table.concat(calls, " | "))
    eq(rawget(_G, "__NATIVELOADER_I18N_DATA"), nil, "the global is cleared")
elseif scenario == "saved-language" then
    -- The companion's client convar is not visible in the menu realm: the copy the companion keeps for it counts.
    convars.gmod_language = "fr"
    file = { Read = function(path, where)
        eq(path .. "@" .. where, "nativeloader_companion/language.txt@DATA")
        return "ja"
    end }
    run()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_flatgrass", 1)
    inLoading = true
    think()
    assert(has("start gm_flatgrass JA lua=Lua file=JA-FILE"), table.concat(calls, " | "))
    file = nil
elseif scenario == "off" then
    convars.nativeloader_load_overlay = "0"
    run()
    inLoading = true
    think()
    inLoading = false
    think()
    eq(#calls, 0, table.concat(calls, " | "))
elseif scenario == "no-module" then
    requireFails = true
    run()
    assert(next(thinks) == nil, "no Think hook without the module")
    assert(logs[1]:find("load overlay unavailable", 1, true), tostring(logs[1]))
elseif scenario == "not-menu" then
    MENU_DLL = nil
    dofile(SCRIPT)
    eq(NativeLoaderLoadStatus, nil)
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
