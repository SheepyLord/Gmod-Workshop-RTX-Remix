-- Runs the load accelerator's real nlloadaccel/load_callbacks.lua (ADR 0241) under LuaJIT in a mocked realm: GMod's
-- hook library (a plain table, as hook.GetTable gives), timers, net receivers, a clock the callbacks advance, file.Write,
-- engine.GetAddons with file.Exists, and the render guard's record of timed functions.
-- Usage: luajit <this> <repo> <scenario>. Prints "PASS <scenario>"; an error otherwise. See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/fs_accel/addon/lua/nlloadaccel/load_callbacks.lua"
local realPrint = print

local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function istable(v) return type(v) == "table" end

SERVER = scenario == "server"
CLIENT = not SERVER
FCVAR_ARCHIVE = 128
local convars = { nativeloader_load_accel_callbacks = scenario == "off" and "0" or nil }
function CreateConVar(name, default)
    if convars[name] == nil then convars[name] = default end
    return { GetBool = function() return convars[name] ~= "0" end }
end
local clock = 1000
function SysTime() return clock end
local function spend(seconds) clock = clock + seconds end

local hookTable = {}
local function plainAdd(event, id, fn)
    hookTable[event] = hookTable[event] or {}
    hookTable[event][id] = fn
end
hook = { Add = plainAdd, GetTable = function() return hookTable end }
local function call(event, ...)
    for _, fn in pairs(hookTable[event] or {}) do fn(...) end
end
local pending = {}
local function plainSimple(delay, fn) pending[#pending + 1] = { delay = delay, fn = fn } end
local created = {}
local function plainCreate(id, delay, reps, fn) created[id] = fn end
timer = { Simple = plainSimple, Create = plainCreate }
local function runTimers(maxDelay)
    local ready = {}
    for i = #pending, 1, -1 do
        if pending[i].delay <= maxDelay then
            table.insert(ready, 1, pending[i].fn)
            table.remove(pending, i)
        end
    end
    for _, fn in ipairs(ready) do fn() end
end
local function plainReceive(name, fn) net.Receivers[name:lower()] = fn end
net = { Receivers = {}, Receive = plainReceive }
local written = {}
file = {
    CreateDir = function() end,
    Write = function(path, text) written[path] = text end,
    Exists = function(path, title) return title == "Model Hotloader" and path == "lua/mmdhl/sharing.lua" end,
}
engine = { GetAddons = function()
    return { { mounted = true, title = "Some Add-on" }, { mounted = true, title = "Model Hotloader" } }
end }
local printed = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(parts, " ")
end
-- A function defined in another add-on's file.
local function defined(chunk, code, ...)
    return assert(loadstring(code, "@" .. chunk))(...)
end

if scenario == "off" then
    dofile(SCRIPT)
    assert(rawequal(hook.Add, plainAdd) and rawequal(timer.Simple, plainSimple) and rawequal(net.Receive, plainReceive),
        "switched off: nothing replaced")
    realPrint("PASS " .. scenario)
    return
end

dofile(SCRIPT)
assert(not rawequal(hook.Add, plainAdd), "hook.Add is timed while the realm's Lua starts")

-- Before the render guard has loaded: its record gets the wrapper once it has.
local early = defined("addons/early/lua/autorun/early.lua", "return function() end")
hook.Add("Think", "early", early)
NativeLoaderRenderGuard = { timed = setmetatable({}, { __mode = "k" }) }
local think = defined("addons/foo/lua/autorun/foo.lua", "return function(spend) spend(0.3) end")
hook.Add("Think", "foo", think)
assert(not rawequal(hookTable.Think.foo, think), "the hook holds a timing wrapper")
if CLIENT then
    assert(rawequal(NativeLoaderRenderGuard.timed[hookTable.Think.foo], think), "the guard names the timed function")
    assert(rawequal(NativeLoaderRenderGuard.timed[hookTable.Think.early], early), "an early wrapper is entered too")
end
-- Arguments and results pass through; the time is its own and what it calls.
local returns = defined("addons/foo/lua/autorun/ret.lua", "return function(a, b) return a + b, 'x' end")
hook.Add("Sum", "ret", returns)
local x, y = hookTable.Sum.ret(2, 3)
eq(x, 5)
eq(y, "x")
call("Think", spend)
-- A slow callback writes the file at once (the load overlay reads it at the end of the load).
local realm = SERVER and "server" or "client"
local path = "nativeloader/load_callbacks_" .. realm .. ".txt"
assert(written[path], "written after a slow callback")
assert(written[path]:find("^load %d+ " .. realm .. "\n"), written[path])
assert(written[path]:find("0.300\t1\t0.300\thook\tThink foo\taddons/foo/lua/autorun/foo.lua:1\t\n", 1, true), written[path])
-- A net receiver, three messages of half a second.
local receiver = defined("lua/mmdhl/sharing.lua", "return function(len, ply, spend) spend(0.5) end")
net.Receive("MMDHL_Catalog", receiver)
for _ = 1, 3 do net.Receivers.mmdhl_catalog(64, nil, spend) end
-- timer.Simple from one place: one entry; timer.Create by its id.
local tick = defined("lua/x.lua", "local spend = ... return function() spend(0.1) end", spend)
for _ = 1, 2 do timer.Simple(0, tick) end
runTimers(0)
timer.Create("pulse", 1, 0, function() spend(0.05) end)
created.pulse()
-- InitPostEntity, then 10 s: the originals go back.
call("InitPostEntity")
assert(#pending >= 1, "the end of the timing is a timer")
runTimers(10)
assert(rawequal(hook.Add, plainAdd), "hook.Add put back")
assert(rawequal(timer.Simple, plainSimple) and rawequal(timer.Create, plainCreate), "timers put back")
assert(rawequal(net.Receive, plainReceive), "net.Receive put back")
assert(rawequal(hookTable.Think.foo, think), "the hook holds its own function again")
assert(rawequal(hookTable.Think.early, early))
assert(rawequal(net.Receivers.mmdhl_catalog, receiver), "the receiver is its own again")
-- The report and the final file, the add-on named.
local line = printed[#printed]
assert(line:find("[nativeloader] load accelerator (" .. realm .. "): Lua callbacks that ran longest during the load: " ..
    "net MMDHL_Catalog 1.5 s (3 calls, lua/mmdhl/sharing.lua:1, Model Hotloader); hook Think foo 0.3 s (1 call, " ..
    "addons/foo/lua/autorun/foo.lua:1, foo)", 1, true), line)
assert(line:find("timer.Simple at lua/x.lua:1 0.2 s (2 calls", 1, true), line)
assert(not line:find("pulse", 1, true), "under 0.1 s is left out")
assert(written[path]:find("^load %d+ " .. realm .. " final\n"), written[path])
assert(written[path]:find("1.500\t3\t0.500\tnet\tMMDHL_Catalog\tlua/mmdhl/sharing.lua:1\tModel Hotloader\n", 1, true), written[path])
-- After the load nothing more is timed.
local later = function() end
hook.Add("Think", "later", later)
assert(rawequal(hookTable.Think.later, later), "after the load hook.Add is GMod's own")
-- A wrapper left in a timer only passes the call on.
local before = NLLOADACCEL_CALLBACKS.entries[1].calls
created.pulse()
eq(NLLOADACCEL_CALLBACKS.entries[1].calls, before)
realPrint("PASS " .. scenario)
