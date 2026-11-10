-- Runs the companion's nativeloader_lag_report.lua against a small stand-in for the game's hook table (R28).
local source, scenario = ...
local function eq(a, b, why) assert(a == b, (why or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
CLIENT, SERVER = scenario ~= "server", scenario == "server"
local now = 1000
function SysTime() return now end
function isfunction(v) return type(v) == "function" end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function IsValid(v) return type(v) == "table" and v.valid == true end
function math.Clamp(v, low, high) return math.min(math.max(v, low), high) end
-- The hook library: GMod's own (hook.GetTable is the live table), ULib's (a function per priority, and a plain
-- table kept beside it), or one this report does not know (hook.GetTable hands out a copy).
local hooks, added = {}, {}
local levels = {}
hook = {GetTable = function() return hooks end,
    Add = function(event, id, fn)
        added[#added + 1] = tostring(event) .. "/" .. tostring(id)
        hooks[event] = hooks[event] or {}
        hooks[event][id] = fn
        if scenario == "ulib" then
            levels[event] = levels[event] or {[-2] = {}, [-1] = {}, [0] = {}, [1] = {}, [2] = {}}
            for _, list in pairs(levels[event]) do list[id] = nil end
            levels[event][0][id] = {fn = fn, isstring = type(id) == "string"}
        end
    end,
    Remove = function(event, id)
        if hooks[event] then hooks[event][id] = nil end
        if levels[event] then for _, list in pairs(levels[event]) do list[id] = nil end end
    end}
if scenario == "ulib" then hook.GetULibTable = function() return levels end end
if scenario == "copy" then
    hook.GetTable = function()
        local copy = {}
        for event, list in pairs(hooks) do
            copy[event] = {}
            for id, fn in pairs(list) do copy[event][id] = fn end
        end
        return copy
    end
end
net = {Receivers = {}}
local timers, commands, printed, written, sent = {}, {}, {}, {}, {}
timer = {Simple = function(delay, fn) timers[#timers + 1] = {delay = delay, fn = fn} end}
concommand = {Add = function(name, fn) commands[name] = fn end}
function print(text) printed[#printed + 1] = tostring(text) end
function RunConsoleCommand(...) sent[#sent + 1] = {...} end
local host = {valid = true, IsListenServerHost = function() return true end}
local guest = {valid = true, IsListenServerHost = function() return false end}
function LocalPlayer() return host end
game = {GetMap = function() return "gm_test" end, SinglePlayer = function() return true end}
engine = {GetAddons = function()
    return {{title = "Unmounted Pack", mounted = false}, {title = "Other Pack", mounted = true},
        {title = "Workshop Thing", mounted = true}}
end}
local existsCalls, writeFails = 0, false
local theirs = {["lua/autorun/workshop_thing.lua"] = true, ["lua/postprocess/thing_bloom.lua"] = true,
    ["gamemodes/thingrp/gamemode/cl_init.lua"] = true}
file = {CreateDir = function() end,
    Write = function(name, text) if writeFails then error("disk full") end written[name] = text end,
    Exists = function(path, title)
        existsCalls = existsCalls + 1
        return (title == "Workshop Thing" or title == "Unmounted Pack") and theirs[path] == true
    end}
NativeLoaderRenderGuard = {readbacks = {allowed = 4, refused = 37}, fonts = {calls = 12}, timed = {},
    slow = {{api = "PreDrawViewModels", id = "HRX_StageB", source = "lua/hrx/cl_pipeline.lua", ms = 49.4, worst_ms = 207}}}

assert(loadfile(source))()

local function made(path, code) return assert(loadstring(code, "@" .. path))() end
local function output(needle)
    for _, line in ipairs(printed) do if line:find(needle, 1, true) then return line end end
end
function NOW(seconds) now = now + seconds end

if scenario == "server" then
    eq(commands.nativeloader_lag_report, nil, "the client's command is the client's")
    local run = assert(commands.nativeloader_lag_report_server)
    hook.Add("Tick", "walker", function() now = now + 0.003 end)
    run(guest, nil, {"5"})
    eq(#timers, 0, "another player may not start it")
    run(nil, nil, {"5"})   -- the server's own console
    eq(#timers, 1)
    for _ = 1, 50 do for _, fn in pairs(hooks.Tick) do fn() end now = now + 0.012 end
    timers[1].fn()
    assert(output("Lag report (server, gm_test"), "the server's summary")
    assert(output("ms/tick"), "per tick on the server")
    assert(written["nativeloader/lag_report_server.txt"], "the server's file")
    assert(not output("RTX guard"), "the guard's records are the client's")
    print = nil
    io.write("PASS server\n")
    return
end

eq(commands.nativeloader_lag_report_server, nil, "the server's command is the server's")
local run = assert(commands.nativeloader_lag_report)
local slow = made("addons/slow_addon/lua/autorun/client/slow.lua", "return function() _G.NOW(0.004) end")
local hud = made("lua/autorun/workshop_thing.lua", "return function(a, b) _G.NOW(0.001) return a, nil, b end")
local base = made("lua/includes/modules/draw.lua", "return function() _G.NOW(0.0005) end")
local failing = made("addons/broken/lua/autorun/broken.lua", "return function() error('broken hook') end")
local replaced = made("addons/dynamic/lua/autorun/dynamic.lua", "return function() end")
local receiver = made("addons/slow_addon/lua/autorun/client/slow.lua", "return function() _G.NOW(0.002) end")
-- Files under folders the game has itself: one is a mounted add-on's, one the game's.
local bloom = made("lua/postprocess/thing_bloom.lua", "return function() _G.NOW(0.0007) end")
local stock = made("lua/postprocess/bloom.lua", "return function() _G.NOW(0.0003) end")
-- The gamemode's own functions: an add-on's gamemode.
local gmThink = made("gamemodes/thingrp/gamemode/cl_init.lua", "return function(self) _G.NOW(0.0025) return self end")
local gmPaint = made("gamemodes/base/gamemode/cl_init.lua", "return function() _G.NOW(0.0002) end")
GAMEMODE = {Think = gmThink, HUDPaint = gmPaint, Name = "ThingRP", BaseClass = {}}
local object = {valid = true}
local objectFn = function(self, value) eq(self, object) return value end
local gone = {valid = false}
local goneFn = function() end
hook.Add("Think", "slow_think", slow)
hook.Add("HUDPaint", "thing_hud", hud)
hook.Add("HUDPaint", object, objectFn)
hook.Add("HUDPaint", gone, goneFn)
hook.Add("PostRender", "game_draw", base)
hook.Add("PostRender", "broken", failing)
hook.Add("PostRender", "dynamic", replaced)
hook.Add("RenderScreenspaceEffects", "thing_bloom", bloom)
hook.Add("RenderScreenspaceEffects", "bloom", stock)
net.Receivers.slow_message = receiver
if scenario == "ulib" then
    -- A hook the server's admin tool gave a priority keeps it.
    levels.Think[0].slow_think = nil
    levels.Think[-2].slow_think = {fn = slow, isstring = true}
end
-- What the game's hook.Call would run for an event's named hooks.
local function installed(event, id)
    if scenario == "ulib" then
        for _, list in pairs(levels[event]) do if list[id] then return list[id].fn end end
        return nil
    end
    return hooks[event][id]
end
local addedBefore = #added

run(nil, nil, {"5"})
eq(#timers, 1) eq(timers[1].delay, 5)
eq(#sent, 1, "a local game starts the server's half") eq(sent[1][1], "nativeloader_lag_report_server") eq(sent[1][2], "5")
eq(#added, addedBefore + 1, "hook.Add is used for the frame counter alone") eq(added[#added], "Think/nativeloader_lag_report")
if scenario == "copy" then
    -- A hook library this report does not know: nothing is swapped, and the report says so.
    eq(installed("Think", "slow_think"), slow)
    assert(GAMEMODE.Think ~= gmThink, "the gamemode's functions are timed all the same")
    for _ = 1, 20 do hooks.Think.slow_think() GAMEMODE.Think(GAMEMODE) now = now + 0.010 end
    timers[1].fn()
    eq(GAMEMODE.Think, gmThink)
    assert(output("8 hooks of a hook library this report does not know"), "the hooks it could not time are counted")
    assert(output("0 of 0 hooks put back"), "none was touched")
    print = nil
    io.write("PASS copy\n")
    return
end
assert(installed("Think", "slow_think") ~= slow and installed("HUDPaint", "thing_hud") ~= hud, "hooks are timed")
eq(installed("HUDPaint", gone), goneFn, "a hook of something that is gone is left to the hook library")
assert(net.Receivers.slow_message ~= receiver, "net receivers are timed")
assert(GAMEMODE.Think ~= gmThink and GAMEMODE.HUDPaint ~= gmPaint, "the gamemode's functions are timed")
eq(GAMEMODE.Name, "ThingRP") eq(type(GAMEMODE.BaseClass), "table")
eq(NativeLoaderRenderGuard.timed[installed("Think", "slow_think")], slow, "the render guard is told which function a timer times")
if scenario == "ulib" then
    eq(levels.Think[-2].slow_think.fn, installed("Think", "slow_think"), "the hook keeps its priority")
    eq(levels.Think[0].slow_think, nil)
    -- The render guard runs its events from the plain table: the timer is there too.
    eq(hooks.Think.slow_think, installed("Think", "slow_think"), "the plain table beside it has the timer as well")
end
run(nil, nil, {"5"})
assert(output("already measuring"), "one measurement at a time") eq(#timers, 1)
-- Arguments, every return value and errors pass through the timers.
local values = {installed("HUDPaint", "thing_hud")(1, 3)}
eq(values[1], 1) eq(values[2], nil) eq(values[3], 3)
eq(installed("HUDPaint", object)(object, 7), 7)
eq(GAMEMODE.Think(GAMEMODE), GAMEMODE)
local ok, err = pcall(installed("PostRender", "broken"))
assert(not ok and tostring(err):find("broken hook", 1, true), "an error stays the add-on's")
-- 100 frames; halfway an add-on replaces one of its hooks.
local replacement = function() end
for frame = 1, 100 do
    installed("Think", "slow_think")()
    installed("Think", "nativeloader_lag_report")()
    GAMEMODE.Think(GAMEMODE)
    installed("HUDPaint", "thing_hud")()
    GAMEMODE.HUDPaint()
    installed("PostRender", "game_draw")()
    installed("RenderScreenspaceEffects", "thing_bloom")()
    installed("RenderScreenspaceEffects", "bloom")()
    if frame == 50 then hook.Add("PostRender", "dynamic", replacement) end
    if frame % 10 == 0 then net.Receivers.slow_message() end
    now = now + 0.010
end
if scenario == "failure" then
    -- The report cannot be written: everything is put back all the same, and the next report can start.
    writeFails = true
    timers[1].fn()
    eq(installed("Think", "slow_think"), slow, "put back") eq(GAMEMODE.Think, gmThink)
    assert(output("could not be finished"), "the failure is said")
    writeFails = false
    run(nil, nil, {"5"})
    eq(#timers, 2, "the next report starts")
    timers[2].fn()
    eq(installed("Think", "slow_think"), slow)
    assert(written["nativeloader/lag_report_client.txt"], "and is written")
    print = nil
    io.write("PASS failure\n")
    return
end
timers[1].fn()
eq(installed("Think", "slow_think"), slow, "put back") eq(installed("HUDPaint", "thing_hud"), hud)
eq(installed("HUDPaint", object), objectFn)
eq(installed("PostRender", "dynamic"), replacement, "a hook its add-on replaced stays the add-on's")
eq(net.Receivers.slow_message, receiver)
eq(GAMEMODE.Think, gmThink, "the gamemode's functions are put back") eq(GAMEMODE.HUDPaint, gmPaint)
eq(installed("Think", "nativeloader_lag_report"), nil, "the frame counter is gone")
if scenario == "ulib" then
    eq(levels.Think[-2].slow_think.fn, slow, "back at its priority")
    eq(hooks.Think.slow_think, slow, "and back in the plain table")
    eq(hooks.HUDPaint.thing_hud, hud)
end
local summary = assert(output("Lag report (client, gm_test"), "the summary")
assert(summary:find("99 frames", 1, true), summary)
local first = assert(output(" 1. "), "a first line")
assert(first:find('Think "slow_think"', 1, true) and first:find("4.0", 1, true), first)
assert(first:find("addons/slow_addon/lua/autorun/client/slow.lua:1", 1, true) and first:find("[slow_addon]", 1, true), first)
local second = assert(output(" 2. "))
assert(second:find('Think "the gamemode"', 1, true) and second:find("gamemodes/thingrp/gamemode/cl_init.lua", 1, true), second)
assert(second:find("[Workshop Thing]", 1, true), "an add-on's gamemode is the add-on's: " .. second)
assert(assert(output('HUDPaint "thing_hud"')):find("[Workshop Thing]", 1, true), "a mounted item is found by its file")
assert(assert(output('PostRender "game_draw"')):find("[Garry's Mod]", 1, true), "the game's own Lua is named")
assert(assert(output('RenderScreenspaceEffects "thing_bloom"')):find("[Workshop Thing]", 1, true),
    "an add-on's file in a folder the game has too is the add-on's")
assert(assert(output('RenderScreenspaceEffects "bloom"')):find("[Garry's Mod]", 1, true), "the game's file there is the game's")
assert(assert(output('HUDPaint "the gamemode"')):find("[Garry's Mod]", 1, true), "the base gamemode is the game's")
assert(assert(output('net "slow_message"')):find("10 calls", 1, true), "net receivers are listed")
assert(not output('"dynamic"'), "a hook never called is not listed")
assert(output("37 repeated screen read-backs"), "the guard's read-backs")
assert(output("12 repeated font definitions"), "the guard's fonts")
assert(output('slow this session: PreDrawViewModels "HRX_StageB" 49.4 ms'), "the guard's slow callbacks")
assert(output("A time includes what the function calls."), "what the times mean")
local text = assert(written["nativeloader/lag_report_client.txt"], "the report's file")
assert(text:find('Think "slow_think"', 1, true) and not text:find("[nativeloader]", 1, true), "the file has the lines")
assert(existsCalls <= 16, "an add-on is looked up once per file: " .. existsCalls)
-- The time is clamped; the next run works.
run(nil, nil, {"500"}) eq(timers[2].delay, 120)
timers[2].fn()
run(nil, nil, {"nonsense"}) eq(timers[3].delay, 10)
timers[3].fn()
eq(installed("Think", "slow_think"), slow)
print = nil
io.write("PASS " .. scenario .. "\n")
