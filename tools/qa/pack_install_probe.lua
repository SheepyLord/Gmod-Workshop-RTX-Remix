-- Client half of pack_install_session.py: deployed for one PoC session as the add-on garrysmod/addons/zz_nlpack_probe,
-- so it runs from the map's first frame. It times the Model Hotloader installing a freshly deployed model package
-- (mmdhl.workshop): every frame's length, each model's install, and what took the time, by function, in the long
-- frames. Never install it as an add-on of your own.
-- NLPACK_SETTINGS (the driver puts it in front): quiet = seconds without an install before the probe ends (10),
-- start = seconds to wait for an install to begin (120), limit = seconds for the whole probe (900), spawnmenu = open
-- the spawn menu while the models install, long = a long frame in milliseconds (50).
if not CLIENT then return end
NLPACK = NLPACK or {}
local P = NLPACK
local S = NLPACK_SETTINGS or {}
local clock = SysTime
local LONG = (S.long or 50) / 1000
P.began = clock()
P.frames, P.events, P.long, P.stats, P.frame, P.wrapped = {}, {}, {}, {}, {}, {}
P.stack = {}
-- The library window's updates: each frame in which its list was built again (Refresh) or rows were added to it
-- (AddRows, ADR 0258), with the time of each, the frame's length and the next frame's (layout and removed panels).
P.updates, P.frameIncl = {}, {}

-- A branch's Model Hotloader files run over the package's for this session (the driver's --hotloader-lua): included
-- again here, before the map's first frame, as the add-on included its own.
for _, name in ipairs(S.override or {}) do include("nlpack_override/" .. name) end
local function now() return clock() - P.began end
local function event(kind, detail)
    P.events[#P.events + 1] = { t = math.Round(now(), 3), kind = kind, detail = detail }
    print(string.format("NLPACK_EVENT %.3f %s %s", now(), kind, detail and util.TableToJSON(detail) or ""))
end

-- A profiler that keeps each call's own time apart from what it calls (as mmd_player_probe.lua does), both for the
-- whole run and for the current frame, so a long frame can say what it spent its time on.
local function stat(tbl, name)
    local s = tbl[name]
    if not s then s = { calls = 0, incl = 0, self = 0, max = 0 } tbl[name] = s end
    return s
end
local function leave(frameEntry, name, ...)
    local stack = P.stack
    for i = #stack, 1, -1 do
        if stack[i] == frameEntry then for j = #stack, i, -1 do stack[j] = nil end break end
    end
    local dt = clock() - frameEntry.start
    local parent = stack[#stack]
    if parent then parent.child = parent.child + dt end
    local own = dt - frameEntry.child
    local s = stat(P.stats, name)
    s.calls, s.incl, s.self = s.calls + 1, s.incl + dt, s.self + own
    if dt > s.max then s.max = dt end
    P.frame[name] = (P.frame[name] or 0) + own
    if name:sub(1, 11) == "ui.Library." then P.frameIncl[name] = (P.frameIncl[name] or 0) + dt end
    return ...
end
-- The install's steps, each call with its time, first two arguments and first result: when each file's transfer and
-- commit began and ended, and each model's asset check ("done": only the calls that did not answer false, still busy).
local TRACE = { ["native.BeginSharedFile"] = true, ["native.CommitSharedFile"] = true, ["native.PollSharedCommit"] = "done",
    ["native.StartAssetCheck"] = true, ["native.PollAssetCheck"] = "done", ["native.SharedFileMatches"] = true }
P.trace = {}
local function traced(entry, name, mode, a, b, ...)
    local first = ...
    if mode ~= "done" or first ~= false then
        P.trace[#P.trace + 1] = { math.Round(entry.start - P.began, 4), name:sub(8), math.Round((clock() - entry.start) * 1000, 2),
            tostring(a):sub(1, 80), tostring(b):sub(1, 80), tostring(first) }
    end
    return ...
end
local function wrap_fn(fn, name)
    if not isfunction(fn) or P.wrapped[fn] then return fn end
    local mode = TRACE[name]
    local wrapped = function(...)
        local entry = { start = clock(), child = 0 }
        P.stack[#P.stack + 1] = entry
        if mode then
            local a, b = ...
            return traced(entry, name, mode, a, b, leave(entry, name, fn(...)))
        end
        return leave(entry, name, fn(...))
    end
    P.wrapped[wrapped] = true
    return wrapped
end
local function wrap_field(owner, key, name)
    if istable(owner) and isfunction(rawget(owner, key)) then owner[key] = wrap_fn(owner[key], name) end
end
local function source_of(fn)
    local info = debug.getinfo(fn, "S")
    return info and (string.GetFileFromFilename(info.short_src or "?") .. ":" .. tostring(info.linedefined)) or "?"
end

-- What is wrapped: the Model Hotloader's native module and its library, workshop and terms tables; GMod's file, util
-- and notification calls; every hook listener with a name (again every two seconds, for listeners added later);
-- timers, named by their source line.
local function wrap_table(tbl, prefix)
    if not istable(tbl) then return end
    for key, value in pairs(tbl) do
        if isstring(key) and isfunction(value) then wrap_field(tbl, key, prefix .. key) end
    end
end
local function wrap_hooks()
    for event, listeners in pairs(hook.GetTable()) do
        for id, fn in pairs(table.Copy(listeners)) do
            if isstring(id) and not P.wrapped[fn] and not string.StartWith(id, "NLPACK.") then
                hook.Add(event, id, wrap_fn(fn, "hook:" .. event .. ":" .. id .. "@" .. source_of(fn)))
            end
        end
    end
end
local function wrap_all()
    if mmdhl then
        wrap_table(mmdhl.native, "native.")
        wrap_table(mmdhl.library, "library.")
        wrap_table(mmdhl.props and mmdhl.props.library, "props.library.")
        wrap_table(mmdhl.terms, "terms.")
        for _, key in ipairs({ "Scan", "Busy", "Reconcile", "AfterInstalls" }) do
            wrap_field(mmdhl.workshop, key, "workshop." .. key)
        end
        -- The library window's rebuild of its list (the spawn menu's External Models tab), and its rows added alone.
        local panel = vgui.GetControlTable and vgui.GetControlTable("MMDHLLibrary")
        if panel then
            wrap_field(panel, "Refresh", "ui.Library.Refresh")
            wrap_field(panel, "AddRows", "ui.Library.AddRows")
        end
    end
    wrap_hooks()
end
for _, key in ipairs({ "Read", "Write", "Exists", "Size", "Time", "Find", "Open", "CreateDir", "Delete", "Append" }) do
    wrap_field(file, key, "file." .. key)
end
for _, key in ipairs({ "JSONToTable", "TableToJSON", "Compress", "Decompress", "SHA256" }) do
    wrap_field(util, key, "util." .. key)
end
for _, key in ipairs({ "AddProgress", "AddLegacy", "Kill" }) do wrap_field(notification, key, "notification." .. key) end
wrap_field(vgui, "Create", "vgui.Create")
local timerSimple, timerCreate = timer.Simple, timer.Create
timer.Simple = function(delay, fn, ...)
    if isfunction(fn) then fn = wrap_fn(fn, "timer:" .. source_of(fn)) end
    return timerSimple(delay, fn, ...)
end
timer.Create = function(name, delay, reps, fn, ...)
    if isfunction(fn) then fn = wrap_fn(fn, "timer:" .. tostring(name):gsub("%x%x%x%x%x%x%x%x+", "#") .. "@" .. source_of(fn)) end
    return timerCreate(name, delay, reps, fn, ...)
end

-- Every frame: its length, whether a model is installing, how many are installed, and for a long frame the six
-- functions that took the most of it.
local last, lastWrap, busySeen, busyNow, quietSince, startedAt
local installedCount, installTimes = 0, {}
local function top(tbl, n)
    local rows = {}
    for name, ms in pairs(tbl) do rows[#rows + 1] = { name, ms } end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = { rows[i][1], math.Round(rows[i][2] * 1000, 2) } end
    return out
end
local function busy() return mmdhl and mmdhl.workshop and mmdhl.workshop.Busy and mmdhl.workshop.Busy() or false end
local lastUpdate
-- What the library window's updates depend on, as events: each library revision (how many characters library.Add
-- listed for it, or none: a rebuild) and the spawn menu's library window shown or hidden (a hidden one does not update).
local seenRevision, windowShown
local function watchLibrary()
    local library = mmdhl and mmdhl.library
    if library and library.revision ~= seenRevision then
        seenRevision = library.revision
        local listed = istable(library.added) and library.added[library.revision]
        event("library_revision", { revision = library.revision, listed = listed and #listed or nil })
    end
    local window = mmdhl and IsValid(mmdhl.spawnPanel) and mmdhl.spawnPanel.Library
    local shown = IsValid(window) and mmdhl.PanelVisible and mmdhl.PanelVisible(window) or false
    if shown ~= windowShown then
        windowShown = shown
        event(shown and "window_shown" or "window_hidden", {})
    end
end
hook.Add("Think", "NLPACK.Frame", function()
    local t = clock()
    if last then
        local dt = t - last
        local b = busy()
        P.frames[#P.frames + 1] = { math.Round(now(), 3), math.Round(dt * 1000, 2), b and 1 or 0, installedCount }
        if dt >= LONG then
            P.long[#P.long + 1] = { t = math.Round(now(), 3), ms = math.Round(dt * 1000, 1), busy = b, installed = installedCount,
                top = top(P.frame, 6) }
        end
        if lastUpdate then lastUpdate.next_ms = math.Round(dt * 1000, 2) lastUpdate = nil end
        local rebuild, rows = P.frameIncl["ui.Library.Refresh"], P.frameIncl["ui.Library.AddRows"]
        if rebuild or rows then
            lastUpdate = { t = math.Round(now(), 3), ms = math.Round(dt * 1000, 2), kind = rebuild and "rebuild" or "rows",
                refresh_ms = rebuild and math.Round(rebuild * 1000, 2) or nil, add_rows_ms = rows and math.Round(rows * 1000, 2) or nil,
                busy = b, installed = installedCount, top = top(P.frame, 4) }
            P.updates[#P.updates + 1] = lastUpdate
        end
        if b ~= busyNow then
            busyNow = b
            event(b and "busy" or "idle", { installed = installedCount })
            if b and not startedAt then startedAt = now() end
            if b then busySeen = true quietSince = nil else quietSince = now() end
        end
    end
    watchLibrary()
    P.frame, P.frameIncl = {}, {}
    last = clock()
    if not lastWrap or t - lastWrap > 2 then lastWrap = t wrap_all() end
end)

-- The probe's result file and the end of the session.
local finished
local function summary()
    local install = { frames = 0, over50 = 0, over100 = 0, over250 = 0, over1000 = 0, max = 0, total = 0 }
    local before = { frames = 0, max = 0, total = 0 }
    local all = {}
    for _, f in ipairs(P.frames) do
        local ms = f[2]
        all[#all + 1] = ms
        local into = (startedAt and f[1] >= startedAt and (not P.doneAt or f[1] <= P.doneAt)) and install or nil
        if into then
            into.frames, into.total, into.max = into.frames + 1, into.total + ms, math.max(into.max, ms)
            if ms > 50 then into.over50 = into.over50 + 1 end
            if ms > 100 then into.over100 = into.over100 + 1 end
            if ms > 250 then into.over250 = into.over250 + 1 end
            if ms > 1000 then into.over1000 = into.over1000 + 1 end
        elseif not startedAt then
            before.frames, before.total, before.max = before.frames + 1, before.total + ms, math.max(before.max, ms)
        end
    end
    local function median(list) table.sort(list) return list[math.max(1, math.floor(#list / 2))] or 0 end
    local rows = {}
    for name, s in pairs(P.stats) do
        rows[#rows + 1] = { name = name, calls = s.calls, self_ms = math.Round(s.self * 1000, 2),
            incl_ms = math.Round(s.incl * 1000, 2), max_ms = math.Round(s.max * 1000, 2) }
    end
    table.sort(rows, function(a, b) return a.self_ms > b.self_ms end)
    while #rows > 80 do rows[#rows] = nil end
    return { started = startedAt, done = P.doneAt, seconds = P.doneAt and startedAt and math.Round(P.doneAt - startedAt, 2) or nil,
        installed = installTimes, install_frames = install, before_install = before, median_ms = median(all),
        long_frames = P.long, functions = rows, events = P.events, trace = P.trace, library_updates = P.updates,
        library = mmdhl and mmdhl.library and mmdhl.library.entries and table.Count(mmdhl.library.entries) or nil }
end
local function finish(reason)
    if finished then return end
    finished = true
    if IsValid(g_SpawnMenu) and g_SpawnMenu.NLPACKClose then g_SpawnMenu.Close, g_SpawnMenu.NLPACKClose = g_SpawnMenu.NLPACKClose, nil end
    event("finish", { reason = reason })
    file.CreateDir("nlpack_probe")
    file.Write("nlpack_probe/result.json", util.TableToJSON(summary(), true))
    local frames = {}
    for i, f in ipairs(P.frames) do frames[i] = table.concat(f, ",") end
    file.Write("nlpack_probe/frames.csv", "t,ms,busy,installed\n" .. table.concat(frames, "\n"))
    print("NLPACK_DONE " .. reason)
    print("NL_SHOT_DONE")
end

-- Each model the Model Hotloader installs, as it finishes; the probe ends when nothing has installed for `quiet`
-- seconds after the last model, or when none began within `start` seconds.
hook.Add("InitPostEntity", "NLPACK.Start", function()
    event("init_post_entity", {})
    wrap_all()
    if mmdhl and mmdhl.workshop and mmdhl.workshop.OnInstalled then
        mmdhl.workshop.OnInstalled(function(item, package)
            installedCount = installedCount + 1
            installTimes[#installTimes + 1] = { t = math.Round(now(), 3), name = item.name, asset = item.asset:sub(1, 8),
                package = package and package.title }
            event("installed", { n = installedCount, name = item.name })
        end)
    else
        event("no_workshop_api", {})
    end
    if S.spawnmenu then
        timerSimple(2, function()
            if GAMEMODE and GAMEMODE.OnSpawnMenuOpen then GAMEMODE:OnSpawnMenuOpen() event("spawnmenu_open", {}) end
            -- On the Model Hotloader's tab, whose list rebuilds when the library changes.
            local menu = IsValid(g_SpawnMenu) and g_SpawnMenu.CreateMenu
            local name = mmdhl and mmdhl.L and mmdhl.L("common.external_models")
            if IsValid(menu) and name and menu.SwitchToName then menu:SwitchToName(name) event("spawnmenu_tab", { name = name }) end
            -- Kept open until the probe ends: a click on the menu's background (sandbox closes it then) or a release
            -- of the menu key while the window lost focus would hide the library window, which then stops updating.
            if IsValid(g_SpawnMenu) and not g_SpawnMenu.NLPACKClose then
                g_SpawnMenu.NLPACKClose = g_SpawnMenu.Close
                g_SpawnMenu.Close = function()
                    P.closesKept = (P.closesKept or 0) + 1
                    event("spawnmenu_close_kept_open", { n = P.closesKept })
                end
            end
        end)
    end
end)
hook.Add("Think", "NLPACK.End", function()
    if finished then return end
    local t = now()
    if busySeen and not busyNow and quietSince and t - quietSince >= (S.quiet or 10) then
        P.doneAt = P.doneAt or quietSince
        finish("installed")
    elseif not busySeen and t >= (S.start or 120) then
        finish("no install began")
    elseif t >= (S.limit or 900) then
        P.doneAt = P.doneAt or t
        finish("time limit")
    end
end)
hook.Add("ShutDown", "NLPACK.ShutDown", function() finish("shutdown") end)
print("NLPACK_PROBE_READY")
