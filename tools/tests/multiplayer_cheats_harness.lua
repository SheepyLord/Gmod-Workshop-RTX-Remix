-- Runs the companion's real nativeloader/menu/multiplayer_cheats.lua (review finding 16, ADR 0234) against mocked
-- menu-realm globals: the data folder, the timer, IsInGame, RunConsoleCommand and the clock. See the adjacent .md.
local root, scenario = ...
local script = root .. "/companion/nativeloader/lua/nativeloader/menu/multiplayer_cheats.lua"
local REQUEST = "nativeloader_companion/cheats_off.txt"

local data, timers, ran, printed, inGame, clock = {}, {}, {}, {}, true, 1000000
os.time = function() return clock end
function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
file = {
    Exists = function(path, where) return where == "DATA" and data[path] ~= nil end,
    Read = function(path, where) return where == "DATA" and data[path] or nil end,
    Delete = function(path) data[path] = nil end,
}
timer = { Create = function(name, delay, reps, fn) timers[#timers + 1] = { name = name, delay = delay, reps = reps, fn = fn } end }
function IsInGame() return inGame end
function RunConsoleCommand(...) ran[#ran + 1] = table.concat({ ... }, " ") end
print = function(text) printed[#printed + 1] = tostring(text) end

local function load()
    MENU_DLL, NativeLoaderMultiplayerCheats = true, nil
    dofile(script)
    assert(#timers == 1 and timers[1].name == "NativeLoaderMultiplayerCheats" and timers[1].delay == 1 and timers[1].reps == 0,
        "one repeating timer a second")
end
local function tick() timers[1].fn() end

if scenario == "fresh" then
    load()
    tick()
    assert(#ran == 0, "ran without a request")
    data[REQUEST] = tostring(clock - 3)
    tick()
    assert(#ran == 1 and ran[1] == "sv_cheats 0", "a fresh request in a running game: " .. table.concat(ran, ","))
    assert(data[REQUEST] == nil, "the request was kept")
    assert(#printed == 1 and printed[1]:find("sv_cheats 0", 1, true), "no console line")
    tick()
    assert(#ran == 1, "ran twice for one request")
elseif scenario == "loading" then
    load()
    inGame = false
    data[REQUEST] = tostring(clock)
    tick()
    tick()
    assert(#ran == 0 and data[REQUEST] ~= nil, "acted while the game was loading, or dropped the request")
    inGame = true
    clock = clock + 40
    tick()
    assert(#ran == 1 and data[REQUEST] == nil, "the request waited for the game and was carried out")
elseif scenario == "stale" then
    load()
    data[REQUEST] = tostring(clock - 301)
    tick()
    assert(#ran == 0 and data[REQUEST] == nil, "a request older than five minutes (a crashed game's) was carried out or kept")
    data[REQUEST] = tostring(clock + 61)
    tick()
    assert(#ran == 0 and data[REQUEST] == nil, "a request from the future was carried out or kept")
    data[REQUEST] = "sv_cheats 0; quit"
    tick()
    assert(#ran == 0 and data[REQUEST] == nil, "an unreadable request was carried out or kept")
    inGame = false
    data[REQUEST] = tostring(clock - 400)
    tick()
    assert(#ran == 0 and data[REQUEST] == nil, "a stale request waited for a game")
elseif scenario == "realm" then
    MENU_DLL, NativeLoaderMultiplayerCheats = nil, nil
    dofile(script)
    assert(#timers == 0, "ran outside the menu realm")
    load()
    dofile(script)
    assert(#timers == 1, "loaded twice made a second timer")
else
    error("unknown scenario " .. tostring(scenario))
end
io.write("PASS " .. scenario .. "\n")
