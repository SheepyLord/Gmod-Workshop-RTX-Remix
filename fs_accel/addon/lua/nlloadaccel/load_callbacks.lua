-- The load accelerator, round 3 item D2 (ADR 0241): what held the main thread during a map load without leaving a file
-- name on the stack. The load overlay names the Lua files that ran longest from the file names GMod keeps while a file
-- runs; a hook, a timer or a net receiver runs later, from a file already done, and was invisible there (the second
-- round's 54 s frame was one net receiver called 94 times). Here every hook (hook.Add), timer (timer.Simple,
-- timer.Create) and net receiver (net.Receive) registered while this realm's Lua starts is timed from now until 10 s
-- after InitPostEntity (a frame that is still running then counts whole); then the originals are put back where they
-- still are ours, and the wrappers left in a timer only pass the call on. The slowest are printed, kept in
-- NLLOADACCEL_CALLBACKS and written to data/nativeloader/load_callbacks_<realm>.txt, from which the load overlay's
-- end-of-load line names them. A time includes what the callback calls. Documented in load_callbacks.lua.md.
if NLLOADACCEL_CALLBACKS ~= nil then return end
NLLOADACCEL_CALLBACKS = false

local switch = CreateConVar("nativeloader_load_accel_callbacks", "1", FCVAR_ARCHIVE,
    "Time the hooks, timers and net receivers of a map load and name the slowest at its end (0: off, from the next map)")
if not switch:GetBool() then return end

local REALM = SERVER and "server" or "client"
local FILE = "nativeloader/load_callbacks_" .. REALM .. ".txt"
local SLOW, AFTER, LIMIT, KEEP, SAY, SAY_MIN = 0.25, 10, 900, 8, 5, 0.1
local began = os.time()
local measuring = true
local entries, byKey = {}, {}
local hooks, receivers = {}, {}
local lastWrite = 0
local state = { realm = REALM, began = began, entries = entries }
NLLOADACCEL_CALLBACKS = state

local function where(fn)
    local info = debug.getinfo(fn, "S")
    if not info then return "?" end
    return tostring(info.short_src or "?"):gsub("\\", "/") .. ":" .. tostring(info.linedefined or 0)
end

-- The render guard records a function a timing wrapper times (as for the lag report), so its records keep naming
-- that function and what it leaves out stays left out. Wrappers made before the guard has loaded are entered once it
-- has.
local early = {}
local function registerWithGuard(wrapper, fn)
    if not CLIENT then return end
    local guard = rawget(_G, "NativeLoaderRenderGuard")
    if not (istable(guard) and istable(guard.timed)) then
        if #early < 4096 then early[#early + 1] = { wrapper, fn } end
        return
    end
    for i = 1, #early do guard.timed[early[i][1]] = early[i][2] end
    early = {}
    guard.timed[wrapper] = fn
end

local function top(count)
    local list = {}
    for _, entry in ipairs(entries) do
        if entry.calls > 0 then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    for i = #list, count + 1, -1 do list[i] = nil end
    return list
end

-- The add-on a source file belongs to: a folder under addons/, else the mounted add-on that has the file (only for
-- the few named at the end).
local owners = {}
local function owner(source)
    local path = tostring(source):gsub(":%d+$", "")
    if owners[path] ~= nil then return owners[path] or nil end
    local name = path:match("^addons/([^/]+)/")
    if not name and (path:find("^lua/") or path:find("^gamemodes/")) and istable(engine) and isfunction(engine.GetAddons) then
        for _, addon in ipairs(engine.GetAddons()) do
            if addon.mounted and isstring(addon.title) and file.Exists(path, addon.title) then
                name = addon.title
                break
            end
        end
    end
    owners[path] = name or false
    return name
end

local function write(final)
    lastWrite = SysTime()
    local lines = { string.format("load %d %s%s", began, REALM, final and " final" or "") }
    for _, entry in ipairs(top(KEEP)) do
        lines[#lines + 1] = string.format("%.3f\t%d\t%.3f\t%s\t%s\t%s\t%s", entry.total, entry.calls, entry.worst,
            entry.kind, entry.name, entry.source, final and (owner(entry.source) or "") or "")
    end
    file.CreateDir("nativeloader")
    file.Write(FILE, table.concat(lines, "\n") .. "\n")
end
state.write = write

local function finish(entry, start, ...)
    local took = SysTime() - start
    entry.total, entry.calls = entry.total + took, entry.calls + 1
    if took > entry.worst then entry.worst = took end
    if took >= SLOW and measuring and SysTime() - lastWrite >= 0.5 then write(false) end
    return ...
end

local function entryFor(kind, name, fn)
    local key = kind .. "\0" .. name
    local entry = byKey[key]
    if not entry then
        entry = { kind = kind, name = name, source = where(fn), total = 0, calls = 0, worst = 0 }
        byKey[key] = entry
        entries[#entries + 1] = entry
    end
    return entry
end

local function timed(kind, name, fn)
    local entry = entryFor(kind, name, fn)
    local function wrapper(...)
        if not measuring then return fn(...) end
        return finish(entry, SysTime(), fn(...))
    end
    registerWithGuard(wrapper, fn)
    return wrapper
end

local realAdd, realSimple, realCreate, realReceive = hook.Add, timer.Simple, timer.Create, net and net.Receive

local function add(event, id, fn, ...)
    if measuring and isfunction(fn) and event ~= nil and id ~= nil then
        local original = fn
        fn = timed("hook", tostring(event) .. " " .. tostring(id), original)
        hooks[#hooks + 1] = { event = event, id = id, wrapper = fn, fn = original }
    end
    return realAdd(event, id, fn, ...)
end
local function simple(delay, fn, ...)
    if measuring and isfunction(fn) then fn = timed("timer", "timer.Simple at " .. where(fn), fn) end
    return realSimple(delay, fn, ...)
end
local function create(id, delay, repetitions, fn, ...)
    if measuring and isfunction(fn) then fn = timed("timer", "timer " .. tostring(id), fn) end
    return realCreate(id, delay, repetitions, fn, ...)
end
local function receive(name, fn, ...)
    if measuring and isstring(name) and isfunction(fn) then
        local original = fn
        fn = timed("net", name, original)
        receivers[name:lower()] = { wrapper = fn, fn = original }
    end
    return realReceive(name, fn, ...)
end
hook.Add, timer.Simple, timer.Create = add, simple, create
if isfunction(realReceive) then net.Receive = receive end

-- Puts one function in a hook's place without hook.Add (as the lag report does, ULib's hook table included): only where
-- the hook still holds the wrapper.
local function swap(event, id, from, to)
    if isfunction(hook.GetULibTable) then
        local all = hook.GetULibTable()
        local levels = istable(all) and all[event]
        local done = false
        if istable(levels) then
            for _, list in pairs(levels) do
                local slot = istable(list) and list[id]
                if istable(slot) and rawequal(slot.fn, from) then
                    slot.fn = to
                    done = true
                    break
                end
            end
        end
        local plain = hook.GetTable()[event]
        if istable(plain) and rawequal(plain[id], from) then
            plain[id] = to
            done = true
        end
        return done
    end
    local list = hook.GetTable()[event]
    if not istable(list) or not rawequal(list[id], from) then return false end
    list[id] = to
    return true
end

local function stop()
    if not measuring then return end
    measuring = false
    if hook.Add == add then hook.Add = realAdd end
    if timer.Simple == simple then timer.Simple = realSimple end
    if timer.Create == create then timer.Create = realCreate end
    if isfunction(realReceive) and net.Receive == receive then net.Receive = realReceive end
    local restored = 0
    for _, item in ipairs(hooks) do
        if swap(item.event, item.id, item.wrapper, item.fn) then restored = restored + 1 end
    end
    if net and istable(net.Receivers) then
        for name, item in pairs(receivers) do
            if rawequal(net.Receivers[name], item.wrapper) then
                net.Receivers[name] = item.fn
                restored = restored + 1
            end
        end
    end
    state.restored = restored
    write(true)
    local parts = {}
    for _, entry in ipairs(top(SAY)) do
        if entry.total >= SAY_MIN then
            local from = owner(entry.source)
            parts[#parts + 1] = string.format("%s %s %.1f s (%d call%s, %s%s)", entry.kind, entry.name, entry.total,
                entry.calls, entry.calls == 1 and "" or "s", entry.source, from and (", " .. from) or "")
        end
    end
    print("[nativeloader] load accelerator (" .. REALM .. "): " .. (#parts > 0 and
        ("Lua callbacks that ran longest during the load: " .. table.concat(parts, "; ")) or
        string.format("no Lua callback ran %.1f s or longer during the load", SAY_MIN)))
end
state.stop = stop

realAdd("InitPostEntity", "nlloadaccel_callbacks", function() realSimple(AFTER, stop) end)
realSimple(LIMIT, stop)
