-- nativeloader_lag_report [seconds]: which add-ons' Lua costs the most of every frame (R28, ADR 0143).
--
-- For the given time (10 s; 2 to 120) every hook, every function of the gamemode and every net receiver of this
-- realm is timed with SysTime(), then everything is put back and the most expensive ones are printed with their
-- add-on, and written to data/nativeloader/lag_report_<realm>.txt. In a local game the client's command also starts
-- the server's half (nativeloader_lag_report_server), whose report follows in the same console. Not counted:
-- timers, entity and weapon Think, panels' Paint. A time includes what the function calls. English only: a report
-- meant to be pasted into an issue.
-- Not sent to other players' clients (no AddCSLuaFile): a diagnosis of this computer's own game.
local realm = SERVER and "server" or "client"
local running = false
local TOP_HOOKS, TOP_NET, MIN_SECONDS, MAX_SECONDS = 15, 5, 2, 120
-- Folders the game has itself: a file there that no mounted add-on has is the game's own.
local STOCK = {"^lua/includes/", "^lua/derma/", "^lua/vgui/", "^lua/menu/", "^lua/postprocess/", "^lua/matproxy/",
    "^gamemodes/base/", "^gamemodes/sandbox/", "^gamemodes/terrortown/"}

local function where(fn)
    local info = debug.getinfo(fn, "S")
    if not info then return "?", 0 end
    local source = tostring(info.source or "?"):gsub("^@", ""):gsub("\\", "/")
    return source, info.linedefined or 0
end

-- The add-on a Lua file belongs to: a folder under addons/, else the mounted Workshop item that has the file
-- (also under a folder the game has itself: an item's gamemode, post-process effect or module), else the game.
local function owner(path, addons, known)
    if known[path] ~= nil then return known[path] or nil end
    local name = path:match("^addons/([^/]+)/")
    if not name then
        local lower = path:lower()
        if lower:find("^lua/") or lower:find("^gamemodes/") then
            for _, addon in ipairs(addons) do
                if addon.mounted and addon.title and file.Exists(path, addon.title) then
                    name = addon.title
                    break
                end
            end
            if not name then
                for _, folder in ipairs(STOCK) do
                    if lower:find(folder) then
                        name = "Garry's Mod"
                        break
                    end
                end
            end
        end
    end
    known[path] = name or false
    return name
end

local function wrap(fn, entry)
    local function finish(began, ...)
        local took = SysTime() - began
        entry.total, entry.calls = entry.total + took, entry.calls + 1
        if took > entry.worst then entry.worst = took end
        return ...
    end
    return function(...) return finish(SysTime(), fn(...)) end
end

-- Puts one function in a hook's place without hook.Add, whose checks and other add-ons' wrappers of it would run
-- again (and which, in ULib's hook library, would move the hook to the default priority). GMod's hook table is the
-- live one. ULib keeps its own, with a function per priority, and the plain table beside it, which the render
-- guard runs its events from: there the function is put into both. With any other hook library the hook is left
-- alone.
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
    local now = hook.GetTable()[event]
    return istable(now) and rawequal(now[id], to)
end

local function top(entries, count)
    local list = {}
    for _, entry in pairs(entries) do if entry.calls > 0 then list[#list + 1] = entry end end
    table.sort(list, function(a, b) return a.total > b.total end)
    for index = #list, count + 1, -1 do list[index] = nil end
    return list
end

local function report(seconds)
    if running then print("[nativeloader] Lag report (" .. realm .. "): already measuring") return end
    seconds = math.Clamp(tonumber(seconds) or 10, MIN_SECONDS, MAX_SECONDS)
    running = true
    local began = SysTime()
    local hooks, receivers, wrapped, wrappedNet, methods = {}, {}, {}, {}, {}
    local left = 0
    -- The render guard's records name the function a timer times, and it keeps treating it as that function.
    local guard = CLIENT and rawget(_G, "NativeLoaderRenderGuard") or nil
    local timed = istable(guard) and istable(guard.timed) and guard.timed or nil
    local function entryFor(event, id, fn)
        local entry = {event = event, id = id, fn = fn, total = 0, calls = 0, worst = 0}
        entry.wrapper = wrap(fn, entry)
        if timed then timed[entry.wrapper] = fn end
        hooks[#hooks + 1] = entry
        return entry
    end
    local found = {}
    for event, list in pairs(hook.GetTable()) do
        if isstring(event) and istable(list) then
            for id, fn in pairs(list) do
                -- A hook of a panel or an entity that is gone is the hook library's to remove.
                if isfunction(fn) and (isstring(id) or IsValid(id)) then found[#found + 1] = {event, id, fn} end
            end
        end
    end
    for _, item in ipairs(found) do
        local entry = entryFor(item[1], item[2], item[3])
        if swap(entry.event, entry.id, entry.fn, entry.wrapper) then
            wrapped[#wrapped + 1] = entry
        else
            hooks[#hooks] = nil
            left = left + 1
        end
    end
    -- The gamemode's own functions are called after the hooks of the same name.
    local gm = rawget(_G, "GAMEMODE")
    if istable(gm) then
        local names = {}
        for name, fn in pairs(gm) do
            if isstring(name) and isfunction(fn) then names[#names + 1] = name end
        end
        for _, name in ipairs(names) do
            local entry = entryFor(name, "the gamemode", rawget(gm, name))
            rawset(gm, name, entry.wrapper)
            methods[#methods + 1] = entry
        end
    end
    if net and istable(net.Receivers) then
        for name, fn in pairs(net.Receivers) do
            if isfunction(fn) then
                local entry = {event = "net", id = name, fn = fn, total = 0, calls = 0, worst = 0}
                entry.wrapper = wrap(fn, entry)
                receivers[#receivers + 1] = entry
                wrappedNet[name] = entry
            end
        end
        for name, entry in pairs(wrappedNet) do net.Receivers[name] = entry.wrapper end
    end
    -- Frames (the client's Think runs once a frame) or ticks (the server's Tick).
    local frames, frameTotal, frameWorst, last = 0, 0, 0, nil
    local frameEvent = CLIENT and "Think" or "Tick"
    hook.Add(frameEvent, "nativeloader_lag_report", function()
        local now = SysTime()
        if last then
            local took = now - last
            frames, frameTotal = frames + 1, frameTotal + took
            if took > frameWorst then frameWorst = took end
        end
        last = now
    end)
    print(string.format("[nativeloader] Lag report (%s): timing %d hooks, %d gamemode functions and %d net receivers for %d s ...",
        realm, #wrapped, #methods, #receivers, seconds))

    local restored = 0
    -- A hook, a gamemode function or a receiver that was replaced or removed meanwhile is left as it is now.
    local function putBack()
        hook.Remove(frameEvent, "nativeloader_lag_report")
        for _, entry in ipairs(wrapped) do
            if swap(entry.event, entry.id, entry.wrapper, entry.fn) then restored = restored + 1 end
        end
        for _, entry in ipairs(methods) do
            if istable(gm) and rawequal(rawget(gm, entry.event), entry.wrapper) then rawset(gm, entry.event, entry.fn) end
        end
        for name, entry in pairs(wrappedNet) do
            if net.Receivers[name] == entry.wrapper then net.Receivers[name] = entry.fn end
        end
    end
    local function tell()
        local elapsed = math.max(SysTime() - began, 0.001)
        local unit = CLIENT and "frame" or "tick"
        local count = math.max(frames, 1)
        local hookTotal, netTotal = 0, 0
        for _, entry in ipairs(hooks) do hookTotal = hookTotal + entry.total end
        for _, entry in ipairs(receivers) do netTotal = netTotal + entry.total end
        local lines = {}
        local function say(text) lines[#lines + 1] = text print("[nativeloader] " .. text) end
        say(string.format("Lag report (%s, %s, %.1f s): %d %ss, %.1f ms a %s (worst %.0f ms); hooks take %.2f ms of every %s (%.0f ms of every second), net receivers %.2f ms",
            realm, game.GetMap(), elapsed, frames, unit, frameTotal / count * 1000, unit, frameWorst * 1000,
            hookTotal / count * 1000, unit, hookTotal / elapsed * 1000, netTotal / count * 1000))
        local addons, known = engine.GetAddons and engine.GetAddons() or {}, {}
        local function line(index, entry)
            local source, at = where(entry.fn)
            local name = owner(source, addons, known)
            local id = isstring(entry.id) and entry.id or ("<" .. type(entry.id) .. ">")
            say(string.format("%2d. %7.3f ms/%s  worst %6.1f ms  %5d calls  %s \"%s\"  %s:%d%s", index,
                entry.total / count * 1000, unit, entry.worst * 1000, entry.calls, entry.event, id, source, at,
                name and ("  [" .. name .. "]") or ""))
        end
        for index, entry in ipairs(top(hooks, TOP_HOOKS)) do line(index, entry) end
        local slowNet = top(receivers, TOP_NET)
        if #slowNet > 0 then say("Net receivers:") end
        for index, entry in ipairs(slowNet) do line(index, entry) end
        -- What the render guard saw this session (RTX starts): slow render hooks and refused read-backs.
        if istable(guard) then
            if istable(guard.readbacks) and (guard.readbacks.refused or 0) > 0 then
                say(string.format("RTX guard: %d repeated screen read-backs (render.CapturePixels) answered from the last picture read, %d made",
                    guard.readbacks.refused, guard.readbacks.allowed or 0))
            end
            if istable(guard.fonts) and (guard.fonts.calls or 0) > 0 then
                say(string.format("RTX guard: %d repeated font definitions (surface.CreateFont) not made again", guard.fonts.calls))
            end
            for _, record in ipairs(istable(guard.slow) and guard.slow or {}) do
                say(string.format("RTX guard, slow this session: %s \"%s\" %.1f ms of every frame (worst %.0f ms)  %s",
                    tostring(record.api), tostring(record.id), tonumber(record.ms) or 0, tonumber(record.worst_ms) or 0,
                    tostring(record.source)))
            end
        end
        say(string.format("Not counted: timers, entity and weapon Think, panels%s. A time includes what the function calls. %d of %d hooks put back.",
            left > 0 and string.format(", %d hooks of a hook library this report does not know", left) or "", restored, #wrapped))
        file.CreateDir("nativeloader")
        file.Write("nativeloader/lag_report_" .. realm .. ".txt", table.concat(lines, "\n") .. "\n")
        print("[nativeloader] Lag report (" .. realm .. "): also in garrysmod/data/nativeloader/lag_report_" .. realm .. ".txt")
    end

    timer.Simple(seconds, function()
        -- Whatever goes wrong, everything is put back and the next report can start.
        local back, problem = pcall(putBack)
        local told, trouble = true, nil
        if back then told, trouble = pcall(tell) end
        running = false
        if not back or not told then
            print("[nativeloader] Lag report (" .. realm .. "): could not be finished: " .. tostring(problem or trouble))
        end
    end)
end

if SERVER then
    concommand.Add("nativeloader_lag_report_server", function(ply, _, args)
        -- The server's own console, or the player who hosts the game.
        if IsValid(ply) and not ply:IsListenServerHost() then return end
        report(args[1])
    end, nil, "Time every server hook for some seconds and print the most expensive ones")
else
    concommand.Add("nativeloader_lag_report", function(_, _, args)
        report(args[1])
        -- A local game: the server's half too (its command exists only where this file ran on the server).
        if game.SinglePlayer() or (IsValid(LocalPlayer()) and LocalPlayer():IsListenServerHost()) then
            RunConsoleCommand("nativeloader_lag_report_server", tostring(math.Clamp(tonumber(args[1]) or 10, MIN_SECONDS, MAX_SECONDS)))
        end
    end, nil, "Time every Lua hook for some seconds and print which add-ons cost the most of every frame")
end
