-- Runs the companion's real nativeloader/menu/loading_status.lua (R24, ADR 0134; ADR 0214 and 0215) in a mocked menu
-- realm: the engine guard module's overlay functions (LoadStart ... LoadEnd, LoadExpect, LoadSettling, LoadTimes,
-- LoadTimesSave), the menu's IsInLoading/GetLoadStatus/IsInGame, its Think hook on a mocked clock, GameDetails,
-- convars, engine.GetAddons, file.Size and the module's read API. Usage: luajit <this> <repo> <scenario>.
-- See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/companion/nativeloader/lua/nativeloader/menu/loading_status.lua"

local calls, logs, convars, hosting, requireFails = {}, {}, { gmod_language = "en" }, true, false
local inLoading, inGame, loadStatus, clock, thinks = false, true, "", 100, {}
local saved, stored, expects, startLabels = {}, nil, {}, nil
local mountedAddons, mapSizes, demo, oldModule = 774, { gm_construct = 10485760 }, false, false
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function near(a, b, tolerance, what)
    if type(a) ~= "number" or math.abs(a - b) > tolerance then
        error((what or "value") .. ": expected about " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end
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
function IsInGame() return inGame end
function GetLoadStatus() return loadStatus end
hook = { Add = function(event, id, fn)
    thinks[event] = thinks[event] or {}
    thinks[event][id] = fn
end }
-- The engine calls a menu hook: every function added for the event, which must return nothing (a value would end the
-- call for GMod's own hooks).
local function call(event, ...)
    for id, fn in pairs(thinks[event] or {}) do
        local result = fn(...)
        if result ~= nil then error(event .. ":" .. tostring(id) .. " returned a value", 2) end
    end
end
local function think() call("Think") end
engine = {
    GetAddons = function()
        local list = {}
        for i = 1, mountedAddons + 3 do list[i] = { mounted = i <= mountedAddons, title = "addon " .. i } end
        return list
    end,
    IsPlayingDemo = function() return demo end,
}
file = {
    Size = function(path, where)
        eq(where, "GAME", "file.Size's path")
        local map = path:match("^maps/(.+)%.bsp$")
        return map and mapSizes[map] or -1
    end,
}

-- Frames of the game: the menu's Think every `step` seconds (1/64 s: exact sums) for `seconds`.
local function frames(seconds, step)
    step = step or 1 / 64
    local target = clock + seconds
    while clock < target - 1e-9 do
        clock = clock + step
        think()
    end
end
-- The main thread blocked for `seconds`: no Think, then one.
local function freeze(seconds)
    clock = clock + seconds
    think()
end

local guardModule = {
    LoadStart = function(heading, labels)
        startLabels = labels
        calls[#calls + 1] = "start " .. heading .. " lua=" .. labels.lua .. " file=" .. labels.file
    end,
    LoadHeading = function(text) calls[#calls + 1] = "heading " .. text end,
    LoadStatus = function(text) calls[#calls + 1] = "status " .. text end,
    LoadExpect = function(seconds, confidence)
        expects[#expects + 1] = { seconds = seconds, confidence = confidence }
        calls[#calls + 1] = string.format("expect %.1f %d", seconds, confidence)
    end,
    LoadSettling = function() calls[#calls + 1] = "settling" end,
    LoadEnd = function()
        calls[#calls + 1] = "end"
        return { seconds = 47.5, loading = 40, lua = { { name = "lua/arc9/shared/sh_atts.lua", seconds = 5.5 }, { name = "lua/autorun/x.lua", seconds = 0.25 } },
            activity = { remix = 3.4, scripts = 20, spawnmenu = 0.25, files = 4 } }
    end,
    LoadTimes = function() return stored end,
    LoadTimesSave = function(text)
        saved[#saved + 1] = text
        stored = text
        return true
    end,
}
function require(name)
    eq(name, "nlengineguard")
    if requireFails then error("Module not found!") end
    if oldModule then
        -- R24's module: no phase after the load, no estimate, no history.
        nlengineguard = { LoadStart = guardModule.LoadStart, LoadHeading = guardModule.LoadHeading,
            LoadStatus = guardModule.LoadStatus, LoadEnd = guardModule.LoadEnd }
    else
        nlengineguard = guardModule
    end
end
local stockArgs
function GameDetails(...)
    stockArgs = { ... }
    calls[#calls + 1] = "stock details " .. stockArgs[3]
end

local CATALOG = 'return { ja = { ["Loading…"] = "JA-LOADING", ["Loading %s"] = "%s JA", ["File"] = "JA-FILE", '
    .. '["RTX Remix is preparing the scene"] = "JA-REMIX", ["about %s s left"] = "JA %s S", '
    .. '["The map has loaded; the game is starting"] = "JA-SETTLING" } }'
local function run()
    MENU_DLL = true
    __NATIVELOADER_MENU_API = { read = function(name)
        eq(name, "nativeloader/nativeloader/i18n_data.lua")
        return CATALOG
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
local function lastExpect() return expects[#expects] end
local function history(lines)
    return "# a comment line\n" .. table.concat(lines, "\n") .. "\n"
end

if scenario == "load" then
    run()
    think()
    eq(#calls, 0, "nothing while not loading")
    inLoading, loadStatus = true, "  Loading world...  "
    think()
    assert(has("start Loading… lua=Lua file=File"), table.concat(calls, " | "))
    assert(has("status Loading world..."), "the stock status, trimmed")
    assert(has("expect 0.0 0"), "no load to learn from: no estimate")
    think()
    eq(count("status Loading world..."), 1, "an unchanged status is not sent again")
    loadStatus = "Starting Lua"
    think()
    assert(has("status Starting Lua"))
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    assert(has("heading Loading gm_construct") and has("stock details gm_construct"), table.concat(calls, " | "))
    -- "Ready to play!": the engine's load ends after 20 s, the overlay stays (ADR 0214).
    clock = clock + 20
    loadStatus = "Ready to play!"
    inLoading = false
    think()
    assert(has("settling"), table.concat(calls, " | "))
    assert(has("status The map has loaded; the game is starting"), table.concat(calls, " | "))
    assert(not has("end"), "the overlay stays after the engine's load")
    assert(not has("status Ready to play!"), "the stock status of the frame that ended the load is not passed")
    freeze(6) -- the first frames: client Lua, Remix's scene
    frames(1.9)
    assert(not has("end"), "two steady seconds are needed")
    frames(0.2)
    assert(has("end"), table.concat(calls, " | "))
    assert(logs[1]:find("map loaded in 20.0 s, then 8.0 s until the game ran steadily (28.0 s in all)", 1, true), logs[1])
    assert(logs[1]:find("the main thread: Lua 20.0 s, game files 4.0 s, RTX Remix 3.4 s", 1, true), logs[1])
    assert(not logs[1]:find("spawn menu", 1, true), "an activity seen under half a second is left out")
    assert(logs[1]:find("lua/arc9/shared/sh_atts.lua (5.5 s)", 1, true), logs[1])
    assert(not logs[1]:find("x.lua", 1, true), "a file seen under half a second is left out")
    eq(NativeLoaderLoadStatus.loads, 1)
    -- The load is in the history, saved through the module.
    eq(#saved, 1, "saved once")
    assert(saved[1]:find("1\t%d+\tf\t774\t10485760\t20%.00\t8%.00\tgm_construct\t\n"), saved[1])
    eq(#NativeLoaderLoadStatus.history, 1)
    -- The next load starts a new overlay, with an estimate from the first (a rough one: the map is not known yet).
    inLoading = true
    think()
    eq(NativeLoaderLoadStatus.loads, 2)
    eq(lastExpect().confidence, 1, "one load of another (unknown) map: rough")
    near(lastExpect().seconds, 28, 0.01, "the machine's estimate")
elseif scenario == "estimate" then
    -- Five loads of gm_construct (first loads of a game start and later ones) and two other maps.
    stored = history({
        "1\t1000\tf\t774\t10485760\t20.00\t8.00\tgm_construct\t",
        "1\t1100\t-\t774\t10485760\t15.00\t6.00\tgm_construct\t",
        "1\t1200\tf\t774\t10485760\t22.00\t7.00\tgm_construct\t",
        "1\t1300\t-\t774\t10485760\t16.00\t6.00\tgm_construct\t",
        "1\t1400\tf\t774\t10485760\t21.00\t9.00\tgm_construct\t",
        "1\t1500\t-\t774\t52428800\t30.00\t10.00\tgm_bigcity\t",
        "1\t1600\t-\t774\t1048576\t12.00\t4.00\tgm_flatgrass\t",
        "2\t1700\t-\t774\t1048576\t99.00\t99.00\tgm_future\t", -- another version: left out
        "1\tbroken line",
    })
    run()
    eq(#NativeLoaderLoadStatus.history, 7, "the readable lines")
    inLoading = true
    think()
    eq(lastExpect().confidence, 1, "before the map is known: the machine's, rough")
    assert(lastExpect().seconds > 10 and lastExpect().seconds < 60, tostring(lastExpect().seconds))
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    -- This map's newest five, the later loads scaled by the machine's first-load factor (29 / 21.5): about 21 + 8.1.
    eq(lastExpect().confidence, 2, "five loads that agree: good")
    near(lastExpect().seconds, 29.1, 0.1, "this map's estimate")
    eq(NativeLoaderLoadStatus.estimate.basis, "map")
    -- The engine's load took 25 s: the wait after it is expected on top of that.
    clock = clock + 25
    inLoading = false
    think()
    near(lastExpect().seconds, 25 + 8.09, 0.1, "the engine's load as it was, the wait after it as expected")
    frames(2.1)
    assert(has("end"))
    assert(logs[#logs]:find("expected about 29 s", 1, true), logs[#logs])
    eq(#NativeLoaderLoadStatus.history, 8)
    assert(not saved[1]:find("gm_future", 1, true), "an unreadable line is not written back")
elseif scenario == "joined-history" then
    -- Loads of games started here say nothing about a server joined, and the other way round.
    stored = history({ "1\t1000\t-\t774\t10485760\t20.00\t8.00\tgm_construct\t" })
    run()
    hosting = false
    inLoading = true
    think()
    near(lastExpect().seconds, 28, 0.01, "assumed a game started here until GameDetails says otherwise")
    GameDetails("Some Server", "http://x", "gm_construct", 32)
    eq(lastExpect().confidence, 0, "no server joined before: no estimate")
    clock = clock + 30
    inLoading = false
    think()
    frames(2.1)
    assert(saved[1]:find("\tfj\t", 1, true) and saved[1]:find("\tgm_construct\tSome Server\n", 1, true), saved[1])
elseif scenario == "cancelled" then
    run()
    inLoading = true
    think()
    clock = clock + 5
    inGame, inLoading = false, false
    think()
    frames(0.9)
    assert(not has("end"), "a moment without a game is waited out")
    frames(0.2)
    assert(has("end") and not has("settling"), table.concat(calls, " | "))
    eq(#saved, 0, "a load without a game is not timed")
    assert(logs[1]:find("the map load ended without a game after 5.0 s", 1, true), logs[1])
elseif scenario == "late-game" then
    -- The game is there a moment after the engine's load ended: the wait goes on as usual.
    run()
    inLoading = true
    think()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    clock = clock + 10
    inGame, inLoading = false, false
    think()
    assert(not has("settling"))
    frames(0.5)
    inGame = true
    frames(0.5)
    assert(has("settling"), table.concat(calls, " | "))
    frames(2.1)
    assert(has("end"))
    eq(#saved, 1)
    -- Timed from the end of the engine's load: half a second without a game, then two steady seconds.
    assert(saved[1]:find("\t10%.00\t2%.52\tgm_construct\t"), saved[1])
elseif scenario == "left-while-settling" then
    run()
    inLoading = true
    think()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    clock = clock + 10
    inLoading = false
    think()
    assert(has("settling"))
    freeze(3)
    inGame = false
    think()
    assert(has("end"))
    eq(#saved, 0, "a game that ended before it ran steadily is not timed")
    assert(logs[1]:find("map loaded in 10.0 s; the game ended 3.0 s later", 1, true), logs[1])
elseif scenario == "next-while-settling" then
    run()
    inLoading = true
    think()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    clock = clock + 10
    inLoading = false
    think()
    freeze(1)
    inLoading = true
    think()
    eq(count("end"), 1)
    eq(count("heading Loading gm_construct"), 1)
    eq(count("start Loading… lua=Lua file=File"), 2, "the next load's overlay: its heading is too old")
    eq(NativeLoaderLoadStatus.loads, 2)
    eq(#saved, 0)
    assert(logs[1]:find("map loaded in 10.0 s; the next load began 1.0 s later", 1, true), logs[1])
elseif scenario == "capped" then
    run()
    inLoading = true
    think()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    clock = clock + 10
    inLoading = false
    think()
    -- Freezes of 1.2 s between a few frames, for ever: never two steady seconds.
    while not has("end") and clock < 400 do
        freeze(1.2)
        frames(3 / 64)
    end
    assert(has("end"))
    near(clock, 100 + 10 + 120, 1.5, "the wait ends at its time limit")
    assert(saved[1]:find("\tfc\t", 1, true), "a capped first load: " .. saved[1])
    assert(logs[1]:find("without the game running steadily", 1, true), logs[1])
elseif scenario == "slow-frames" then
    -- A game that runs steadily but slowly (two frames a second) is playing: the freeze limit follows its frames.
    run()
    inLoading = true
    think()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    clock = clock + 10
    inLoading = false
    think()
    for _ = 1, 8 do freeze(0.5) end
    assert(has("end"), "steady at two frames a second")
elseif scenario == "workshop" then
    -- The Workshop's work is named on the status line while the overlay is up, the overlay does not wait for it.
    run()
    inLoading = true
    think()
    call("WorkshopSubscriptionsProgress", 120, 774)
    think()
    assert(has("status Workshop: fetching subscriptions (120 of 774)"), table.concat(calls, " | "))
    loadStatus = "Starting Lua"
    think()
    assert(has("status Starting Lua  ·  Workshop: fetching subscriptions (120 of 774)"), table.concat(calls, " | "))
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    clock = clock + 10
    inLoading = false
    think()
    assert(has("status The map has loaded; the game is starting  ·  Workshop: fetching subscriptions (120 of 774)"),
        table.concat(calls, " | "))
    call("WorkshopEnd")
    frames(0.1)
    assert(has("status The map has loaded; the game is starting"), table.concat(calls, " | "))
    call("WorkshopDownloadTotals", 7, 10)
    frames(0.1)
    assert(has("status The map has loaded; the game is starting  ·  Workshop: downloading add-ons (3 of 10)"),
        table.concat(calls, " | "))
    call("WorkshopDownloadTotals", 10, 10) -- GMod's "finished": the last word stays until it is ten seconds old
    call("WorkshopExtractProgress", "123", 0, "Some Add-on", 50)
    frames(0.1)
    assert(has("status The map has loaded; the game is starting  ·  Workshop: extracting Some Add-on"),
        table.concat(calls, " | "))
    frames(2)
    assert(has("end"), "the overlay does not wait for the Workshop")
    -- A word from long ago is not shown at the next load.
    call("WorkshopSubscriptionsProgress", 1, 2)
    clock = clock + 11
    loadStatus = "Loading resources"
    inLoading = true
    think()
    assert(has("status Loading resources"), table.concat(calls, " | "))
elseif scenario == "demo" then
    demo = true
    run()
    inLoading = true
    think()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_construct", 1)
    clock = clock + 10
    inLoading = false
    think()
    frames(2.1)
    assert(has("end"))
    eq(#saved, 0, "a demo's load is not timed")
elseif scenario == "old-module" then
    -- R24's module with this script: the overlay ends with the engine's load, as before; nothing is timed.
    oldModule = true
    run()
    inLoading = true
    think()
    clock = clock + 10
    inLoading = false
    think()
    assert(has("end") and not has("settling"), table.concat(calls, " | "))
    eq(#expects, 0)
    assert(logs[1]:find("map loaded in 47.5 s", 1, true), logs[1])
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
    -- The overlay's new words come translated too, and the English where the catalog has none.
    eq(startLabels.remix, "JA-REMIX")
    eq(startLabels.secondsLeft, "JA %s S")
    eq(startLabels.minutesLeft, "about %s min left")
    eq(startLabels.longer, "Taking longer than usual")
    for _, key in ipairs({ "scripts", "spawnmenu", "files", "secondsRough", "minutesRough", "learning" }) do
        assert(isstring(startLabels[key]) and startLabels[key] ~= "", key)
    end
    inLoading = false
    think()
    assert(has("status JA-SETTLING"), table.concat(calls, " | "))
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
    file.Read = function(path, where)
        eq(path .. "@" .. where, "nativeloader_companion/language.txt@DATA")
        return "ja"
    end
    run()
    GameDetails("Garry's Mod", "127.0.0.1", "gm_flatgrass", 1)
    inLoading = true
    think()
    assert(has("start gm_flatgrass JA lua=Lua file=JA-FILE"), table.concat(calls, " | "))
    file.Read = nil
elseif scenario == "off" then
    convars.nativeloader_load_overlay = "0"
    run()
    inLoading = true
    think()
    inLoading = false
    think()
    frames(2.1)
    eq(#calls, 0, table.concat(calls, " | "))
    eq(#saved, 0, "nothing timed or written")
elseif scenario == "no-module" then
    requireFails = true
    run()
    assert(next(thinks) == nil, "no Think hook without the module")
    assert(logs[1]:find("load overlay unavailable", 1, true), tostring(logs[1]))
elseif scenario == "not-menu" then
    MENU_DLL = nil
    dofile(SCRIPT)
    eq(NativeLoaderLoadStatus, nil)
elseif scenario == "eta" then
    -- The estimator itself (NativeLoaderLoadStatus.Eta), without the module.
    requireFails = true
    run()
    local Eta = NativeLoaderLoadStatus.Eta
    eq(Eta.median({}), nil)
    eq(Eta.median({ 3, 1, 2 }), 2)
    eq(Eta.median({ 4, 1, 3, 2 }), 2.5)
    eq(Eta.clip("abc", 5), "abc")
    eq(Eta.clip("\227\131\173\227\131\188", 4), "\227\131\173", "never inside a character")
    eq(Eta.cleanMap("GM_Construct"), "gm_construct")
    eq(Eta.cleanMap("gm_construct_13_beta"), "gm_construct_13_beta")
    eq(Eta.cleanMap("../cfg/x"), "")
    eq(Eta.cleanMap("maps/x"), "")
    eq(Eta.cleanMap("a\tb"), "")
    eq(Eta.cleanMap(string.rep("a", 65)), "")
    eq(Eta.cleanMap(nil), "")
    eq(Eta.cleanServer("  My\tServer\nName  "), "My Server Name")
    eq(#Eta.cleanServer(string.rep("\227\131\173", 30)), 63, "at most 64 bytes, whole characters")
    -- Records survive the file.
    local records = {
        { t = 1000, map = "gm_construct", server = "", joined = false, first = true, capped = false, addons = 774, size = 10485760, load = 20.5, after = 7.25 },
        { t = 1001, map = "rp_downtown", server = "Some Server", joined = true, first = false, capped = true, load = 60, after = 120 },
    }
    local back = Eta.parse(Eta.serialize(records))
    eq(#back, 2)
    eq(back[1].map, "gm_construct")
    eq(back[1].first, true)
    eq(back[1].joined, false)
    eq(back[1].addons, 774)
    eq(back[1].size, 10485760)
    eq(back[1].load, 20.5)
    eq(back[1].after, 7.25)
    eq(back[2].server, "Some Server")
    eq(back[2].joined, true)
    eq(back[2].capped, true)
    eq(back[2].addons, nil, "an add-on count not known")
    eq(back[2].size, nil)
    eq(#Eta.parse("1\t1000\t-\t774\t0\t-5\t1\tgm_x\t\n1\t1000\t-\t774\t0\t5000\t1\tgm_x\t\n1\t1000\t-\t774\t0\t5\t1\t../x\t\n"), 0,
        "negative or absurd durations and bad map names are left out")
    eq(#Eta.parse(nil), 0)
    -- A hand-edited file: numbers out of any real range are dropped, and what is kept prints back.
    local odd = Eta.parse("1\t1000\t-\t1e300\t1e300\t5\t1\tgm_x\t\n1\t1e300\t-\t774\t0\t5\t1\tgm_y\t\n1\t-5\t-\t774\t0\t5\t1\tgm_z\t\n")
    eq(#odd, 1, "a time out of range drops the line")
    eq(odd[1].addons, nil)
    eq(odd[1].size, nil)
    assert(Eta.serialize(odd):find("\tgm_x\t", 1, true))
    -- Bounded: ten per map, two hundred in all, the newest kept, oldest first.
    local list = {}
    for i = 1, 12 do list = Eta.add(list, { t = i, map = "gm_a", server = "", load = i, after = 1 }) end
    eq(#list, 10)
    eq(list[1].t, 3)
    eq(list[10].t, 12)
    for i = 1, 260 do list = Eta.add(list, { t = 100 + i, map = "gm_" .. i, server = "", load = 5, after = 1 }) end
    eq(#list, Eta.MAX_RECORDS)
    eq(list[#list].map, "gm_260")
    -- Estimates.
    eq(Eta.estimate({}, { map = "gm_a" }), nil)
    eq(Eta.estimate({ { t = 1, map = "gm_a", joined = true, server = "s", load = 5, after = 1 } }, { map = "gm_a" }), nil,
        "a joined server's loads say nothing about a game started here")
    local function loads(totals, map, extra)
        local out = {}
        for i, total in ipairs(totals) do
            local r = { t = i, n = i, map = map or "gm_a", server = "", load = total - 5, after = 5, addons = 774 }
            for k, v in pairs(extra or {}) do r[k] = v end
            out[#out + 1] = r
        end
        return out
    end
    local one = Eta.estimate(loads({ 30 }), { map = "gm_a", addons = 774 })
    eq(one.confidence, "rough", "one load")
    near(one.total, 30, 0.001)
    local two = Eta.estimate(loads({ 30, 33 }), { map = "gm_a", addons = 774 })
    eq(two.confidence, "good", "two loads that agree")
    near(two.total, 31.5, 0.001)
    local outlier = Eta.estimate(loads({ 30, 31, 29, 300, 30 }), { map = "gm_a", addons = 774 })
    near(outlier.total, 30, 0.001, "the median ignores one load that went wrong")
    eq(outlier.confidence, "rough", "loads that disagree")
    local newest = Eta.estimate(loads({ 90, 90, 90, 30, 30, 30, 30, 30 }), { map = "gm_a", addons = 774 })
    near(newest.total, 30, 0.001, "the newest five decide: an old machine or add-on set drops out")
    local more = Eta.estimate(loads({ 30, 30 }), { map = "gm_a", addons = 1548 })
    near(more.total, 30 * (150 + 1548) / (150 + 774), 0.001, "twice the add-ons")
    eq(more.confidence, "rough", "scaled far")
    -- The first load of a game start, from a map loaded both ways (40 against 20: twice as long).
    local mixed = loads({ 20, 20, 20 }, "gm_a")
    for _, r in ipairs(loads({ 40, 40 }, "gm_a", { first = true })) do r.t = r.t + 10; mixed[#mixed + 1] = r end
    near(Eta.firstFactor(mixed, 774), 2, 0.001)
    local first = Eta.estimate(loads({ 20, 20 }, "gm_b"), { map = "gm_b", addons = 774, first = true })
    eq(first.confidence, "rough", "a first load from later loads, without a factor to scale them")
    -- Another map's estimate from the machine's maps, fitted to the map's size (load = 5 + 0.3 s a megabyte).
    local machine = {}
    for i, mb in ipairs({ 10, 20, 30, 40 }) do
        machine[#machine + 1] = { t = i, n = i, map = "gm_m" .. i, server = "", load = 5 + 0.3 * mb, after = 4, size = mb * Eta.MB, addons = 774 }
    end
    local fitted = Eta.estimate(machine, { map = "gm_new", size = 50 * Eta.MB, addons = 774 })
    eq(fitted.basis, "machine")
    eq(fitted.confidence, "rough")
    near(fitted.load, 20, 0.001, "the line through the maps' sizes")
    near(fitted.after, 4, 0.001)
    local unsized = Eta.estimate(machine, { map = "gm_new", addons = 774 })
    near(unsized.load, 5 + 0.3 * 25, 0.001, "without a size: the maps' median")
    local absurd = Eta.estimate(loads({ 5000 }), { map = "gm_a" })
    eq(absurd.load, 900, "an estimate is never above 15 minutes for the load")
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
