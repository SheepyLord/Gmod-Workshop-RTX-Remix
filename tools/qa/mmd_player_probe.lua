-- Client half of mmd_player_session.py: clicks through the Advanced MMD Animation Player as a player
-- does (spawn menu, the tool's motion list, tool gun clicks on two NPCs) and times every frame and
-- the add-on's work in both realms. Sent as console Lua by poc_session.py --lua; never an autorun.
-- NLMP_SETTINGS (set by the driver, prepended to this file): steps, window, motions, manager.
NLMPC = NLMPC or {}
local C = NLMPC
local SETTINGS = NLMP_SETTINGS or {}
C.wrapped = C.wrapped or {}
C.prof = { stats = {}, stack = {}, on = false }
local P = C.prof
local clock = SysTime

local function stat(name)
    local s = P.stats[name]
    if not s then
        s = { calls = 0, incl = 0, self = 0, max = 0 }
        P.stats[name] = s
    end
    return s
end

local function leave(frame, name, ...)
    local stack = P.stack
    for i = #stack, 1, -1 do
        if stack[i] == frame then
            for j = #stack, i, -1 do stack[j] = nil end
            break
        end
    end
    local dt = clock() - frame.start
    local parent = stack[#stack]
    if parent then parent.child = parent.child + dt end
    local s = stat(name)
    s.calls = s.calls + 1
    s.incl = s.incl + dt
    s.self = s.self + (dt - frame.child)
    if dt > s.max then s.max = dt end
    return ...
end

local function wrap_fn(fn, name)
    if not isfunction(fn) or C.wrapped[fn] then return fn end
    local wrapped = function(...)
        if not P.on then return fn(...) end
        local frame = { start = clock(), child = 0 }
        P.stack[#P.stack + 1] = frame
        return leave(frame, name, fn(...))
    end
    C.wrapped[wrapped] = true
    return wrapped
end

local function wrap_field(owner, key, name)
    if istable(owner) and isfunction(owner[key]) then owner[key] = wrap_fn(owner[key], name) end
end

local function source_of(fn)
    local info = debug.getinfo(fn, "S")
    return info and (string.GetFileFromFilename(info.short_src or "?") .. ":" .. tostring(info.linedefined)) or "?"
end

local SKIP = { L = true, LFormat = true }
local function wrap_addon()
    for key, value in pairs(MMDVMDNPC or {}) do
        if isfunction(value) and not SKIP[key] then wrap_field(MMDVMDNPC, key, "MMDVMDNPC." .. key) end
    end
    for name in pairs(net.Receivers) do
        if string.sub(name, 1, 7) == "mmdvmd_" then wrap_field(net.Receivers, name, "net:" .. name) end
    end
    for event, listeners in pairs(hook.GetTable()) do
        for id, fn in pairs(table.Copy(listeners)) do
            local label
            if isstring(id) then
                label = id
            elseif ispanel(id) and IsValid(id) then
                label = "panel:" .. tostring(id.ClassName or "?")
            end
            -- GUI Scaler (the field has it) re-walks the spawn menu when the panel count grows.
            local watched = label and (string.find(label, "MMDVMDNPC", 1, true) or string.find(string.lower(label), "guiscaler", 1, true)
                or string.find(label, "nativeloader", 1, true) or not isstring(id))
            if watched and not C.wrapped[fn] then
                hook.Add(event, id, wrap_fn(fn, "hook:" .. event .. ":" .. label .. "@" .. source_of(fn)))
            end
        end
    end
end

for _, key in ipairs({ "Exists", "Time", "Size", "Find", "Read", "Open", "Write" }) do wrap_field(file, key, "file." .. key) end
for _, key in ipairs({ "JSONToTable", "TableToJSON", "CRC" }) do wrap_field(util, key, "util." .. key) end
wrap_field(vgui, "Create", "vgui.Create")
wrap_field(vgui, "GetAll", "vgui.GetAll")
wrap_field(_G, "GUIScaler_Update", "GUIScaler_Update")
for _, control in ipairs({ "DListView", "DComboBox", "DListView_Line" }) do
    local tbl = vgui.GetControlTable(control)
    for _, key in ipairs({ "AddLine", "Clear", "SelectItem", "DataLayout", "SortByColumn", "AddChoice", "PerformLayout", "SetValue" }) do
        if tbl and rawget(tbl, key) then wrap_field(tbl, key, control .. ":" .. key) end
    end
end
for _, key in ipairs({ "AddText" }) do wrap_field(chat, key, "chat." .. key) end
-- The add-on's requests, by name (a step records how many of each it sent).
C.sent = C.sent or {}
if not C.netWrapped then
    C.netWrapped = true
    local netStart = net.Start
    net.Start = function(name, ...)
        C.sent[name] = (C.sent[name] or 0) + 1
        return netStart(name, ...)
    end
end
wrap_field(_G, "RunConsoleCommand", "RunConsoleCommand")
-- Deferred work (coalesced list rebuilds, details walks) runs from timers: name it by its source.
local timerSimple, timerCreate = timer.Simple, timer.Create
timer.Simple = function(delay, fn, ...)
    if P.on and isfunction(fn) then fn = wrap_fn(fn, "timer:" .. source_of(fn)) end
    return timerSimple(delay, fn, ...)
end
timer.Create = function(name, delay, reps, fn, ...)
    if P.on and isfunction(fn) then fn = wrap_fn(fn, "timer:" .. tostring(name):gsub("%d+", "#") .. "@" .. source_of(fn)) end
    return timerCreate(name, delay, reps, fn, ...)
end

-- Every frame's time while recording.
C.frames = {}
hook.Add("Think", "NLMPC.Frame", function()
    local now = clock()
    if C.recording and C.lastFrame then C.frames[#C.frames + 1] = now - C.lastFrame end
    C.lastFrame = now
end)

local function report()
    local rows = {}
    for name, s in pairs(P.stats) do
        rows[#rows + 1] = { name = name, calls = s.calls, incl_ms = s.incl * 1000, self_ms = s.self * 1000, max_ms = s.max * 1000 }
    end
    table.sort(rows, function(a, b) return a.self_ms > b.self_ms end)
    return rows
end

local function frame_summary()
    local frames = {}
    local total, over50, over100, over250 = 0, 0, 0, 0
    for i, dt in ipairs(C.frames) do
        local ms = dt * 1000
        frames[i] = ms
        total = total + ms
        if ms > 50 then over50 = over50 + 1 end
        if ms > 100 then over100 = over100 + 1 end
        if ms > 250 then over250 = over250 + 1 end
    end
    local sorted = table.Copy(frames)
    table.sort(sorted, function(a, b) return a > b end)
    local median = sorted[math.max(1, math.floor(#sorted / 2))] or 0
    local top = {}
    for i = 1, math.min(8, #sorted) do top[i] = sorted[i] end
    return { count = #frames, window_ms = total, max_ms = sorted[1] or 0, median_ms = median, over_50 = over50,
        over_100 = over100, over_250 = over250, longest_ms = top, all_ms = frames }
end

-- Net to the server half.
local replies = {}
net.Receive("nlmp_reply", function()
    local kind = net.ReadString()
    replies[kind] = (replies[kind] or 0) + 1
end)
local function send(cmd)
    net.Start("nlmp_cmd")
        net.WriteString(cmd)
    net.SendToServer()
end

-- A coroutine driven by Think: wait() yields for seconds of real time.
local co
local function wait(seconds)
    local untilTime = clock() + seconds
    while clock() < untilTime do coroutine.yield() end
end
local function wait_reply(kind, count, timeout)
    local deadline = clock() + (timeout or 30)
    while (replies[kind] or 0) < count and clock() < deadline do coroutine.yield() end
    return (replies[kind] or 0) >= count
end

local function server_file(kind)
    return util.JSONToTable(file.Read("nlmp_probe/server_" .. kind .. ".json", "DATA") or "") or {}
end

local results = {}
local function write_result(name, data)
    file.CreateDir("nlmp_probe")
    file.Write("nlmp_probe/step_" .. string.format("%02d", #results + 1) .. "_" .. name .. ".json", util.TableToJSON(data, true))
    results[#results + 1] = { name = name, max_ms = data.frames.max_ms, over_100 = data.frames.over_100,
        window_ms = data.frames.window_ms }
end

local windowCount = 0
local function measured(name, seconds, action)
    wrap_addon()
    send("begin")
    wait(0.3)
    P.stats, P.stack, P.on = {}, {}, true
    C.frames, C.lastFrame, C.recording = {}, clock(), true
    local sentBefore = table.Copy(C.sent)
    local began = clock()
    local ok, err = pcall(action)
    wait(seconds)
    C.recording, P.on = false, false
    local frames = frame_summary()
    local sent = {}
    for msg, count in pairs(C.sent) do
        if string.sub(msg, 1, 7) == "mmdvmd_" and count ~= (sentBefore[msg] or 0) then sent[msg] = count - (sentBefore[msg] or 0) end
    end
    send("end")
    windowCount = windowCount + 1
    wait_reply("window", windowCount, 30)
    local data = { name = name, action_ok = ok, action_error = ok and nil or tostring(err), seconds = clock() - began,
        frames = frames, sent = sent, client = report(), server = server_file("window") }
    write_result(name, data)
    print(string.format("NLMP_STEP %s max %.0f ms, %d frames over 100 ms, window %.0f ms%s", name, frames.max_ms,
        frames.over_100, frames.window_ms, ok and "" or (" ERROR " .. tostring(err))))
end

-- Finding the tool's panels.
local function descendants(panel, out)
    out = out or {}
    if not IsValid(panel) then return out end
    for _, child in ipairs(panel:GetChildren()) do
        out[#out + 1] = child
        descendants(child, out)
    end
    return out
end
local function tool_motion_list()
    local cp = controlpanel and controlpanel.Get and controlpanel.Get("mmd_vmd_npc")
    for _, panel in ipairs(descendants(cp)) do
        if panel.ClassName == "DListView" and panel.Columns and #panel.Columns >= 4 then return panel end
    end
end
local function line_for(list, motionID)
    if not IsValid(list) then return nil end
    for _, line in ipairs(list:GetLines()) do
        if line.MotionID == motionID then return line end
    end
end

local function aim_at(ent)
    local ply = LocalPlayer()
    if not IsValid(ent) or not IsValid(ply) then return end
    local target = ent:LocalToWorld(ent:OBBCenter())
    ply:SetEyeAngles((target - ply:EyePos()):Angle())
end
local function press(command, hold)
    RunConsoleCommand("+" .. command)
    timerSimple(hold or 0.12, function() RunConsoleCommand("-" .. command) end)
end

-- The new options in the game: a short test dance built for the imported character, then ragdoll
-- collision on and off, keep-expressions on and off, and the debug window's timeline.
local PROBE_MOTION = "nlmp_probe_dance"
local function run_server(kind, timeout)
    local before = replies[kind] or 0
    send(kind)
    wait_reply(kind, before + 1, timeout or 60)
    return server_file(kind)
end

local function timeline_test()
    local out = {}
    MMDVMDNPC.OpenDebugMenu(PROBE_MOTION, -1)
    wait(2.5)
    local frame = MMDVMDNPC.DebugFrame
    out.window = IsValid(frame)
    out.slider = IsValid(frame) and IsValid(frame.Timeline)
    if not out.slider then return out end
    local slider = frame.Timeline
    out.range = { slider:GetMin(), slider:GetMax() }
    out.label_wide, out.slider_wide, out.window_wide = IsValid(slider.Label) and slider.Label:GetWide() or nil, slider:GetWide(), frame:GetWide()
    -- One position.
    local before = C.sent["mmdvmd_debug_request"] or 0
    slider:SetValue(60)
    wait(1)
    out.single = { active = frame.ActiveFrame, requests = (C.sent["mmdvmd_debug_request"] or 0) - before, server = run_server("debug_state", 10) }
    -- A drag: the knob held while it sweeps frames 10 to 110 in about one and a half seconds. (GMod copies
    -- a class's methods into each panel: the original goes back afterwards, never nil.)
    local isEditing = slider.IsEditing
    slider.IsEditing = function() return true end
    before = C.sent["mmdvmd_debug_request"] or 0
    local began, changes = clock(), 0
    for value = 10, 110, 2 do
        slider:SetValue(value)
        changes = changes + 1
        wait(0.03)
    end
    local seconds = clock() - began
    wait(0.4)
    out.drag = { changes = changes, seconds = seconds, requests = (C.sent["mmdvmd_debug_request"] or 0) - before,
        rows_wait_while_held = frame.DebugRowsStale == true, active_while_held = frame.ActiveFrame }
    slider.IsEditing = isEditing
    wait(0.8)
    out.released = { active = frame.ActiveFrame, rows_wait = frame.DebugRowsStale == true, rows = #frame.Rows:GetLines(),
        flex_rows = #frame.FlexRows:GetLines(), server = run_server("debug_state", 10) }
    frame:Close()
    wait(0.5)
    return out
end

local function features()
    local out = {}
    out.build = run_server("build", 150)
    if not out.build.built then return out end
    out.followers = run_server("followers", 30)
    RunConsoleCommand("mmd_vmd_npc_keep_flexes", "0")
    RunConsoleCommand("mmd_vmd_npc_ragdoll_collision", "1")
    wait(0.5)
    out.collision_on = run_server("collision", 60)
    RunConsoleCommand("mmd_vmd_npc_ragdoll_collision", "0")
    wait(0.5)
    out.collision_off = run_server("collision", 60)
    RunConsoleCommand("mmd_vmd_npc_ragdoll_collision", "1")
    RunConsoleCommand("mmd_vmd_npc_keep_flexes", "1")
    wait(0.5)
    out.flexes_kept = run_server("flexes", 60)
    RunConsoleCommand("mmd_vmd_npc_keep_flexes", "0")
    wait(0.5)
    out.flexes_reset = run_server("flexes", 60)
    run_server("select1", 10)
    wait(0.5)
    local ok, result = pcall(timeline_test)
    out.timeline = ok and result or { error = tostring(result) }
    run_server("cleanup", 10)
    return out
end

local function pick_motions()
    local ids = {}
    for _, meta in ipairs(MMDVMDNPC.MotionDetailsOrdered or {}) do ids[#ids + 1] = tostring(meta.id) end
    if #ids == 0 then for _, id in ipairs(MMDVMDNPC.ClientMotions or {}) do ids[#ids + 1] = tostring(id) end end
    table.sort(ids)
    local wanted = SETTINGS.motions or {}
    local a = wanted[1] or ids[math.max(1, math.floor(#ids / 3))]
    local b = wanted[2] or ids[math.max(1, math.floor(#ids * 2 / 3))]
    return a, b, #ids
end

local function sequence()
    send("setup")
    if not wait_reply("setup", 1, 120) then print("NLMP_ERROR setup timed out") end
    local setup = server_file("setup")
    local npcs = {}
    for _, row in ipairs(setup.npcs or {}) do npcs[row.slot] = Entity(row.index) end
    print("NLMP_SETUP " .. util.TableToJSON(setup))
    wait(SETTINGS.settle or 8)
    -- The motion list and details as the tool sees them.
    MMDVMDNPC.RequestMotionList()
    wait(3)
    local motionA, motionB, motionCount = pick_motions()
    print(string.format("NLMP_MOTIONS %d A=%s B=%s", motionCount, tostring(motionA), tostring(motionB)))
    local window = SETTINGS.window or 4

    if SETTINGS.steps ~= false then
    measured("idle_baseline", 5, function() end)
    measured("open_spawnmenu_tool", window, function()
        GAMEMODE:OnSpawnMenuOpen()
        timerSimple(0.5, function() spawnmenu.ActivateTool("mmd_vmd_npc") end)
    end)
    send("wrap_tool")
    wait(1)
    if SETTINGS.tab then
        -- The RTX package's Motion importer creation tab: its Motion Manager is built when first shown.
        measured("open_motion_tab", window, function()
            local menu = IsValid(g_SpawnMenu) and g_SpawnMenu.CreateMenu
            assert(IsValid(menu) and menu.SwitchToName, "no creation menu")
            menu:SwitchToName("#nativeloader.motion_importer")
        end)
    end
    if SETTINGS.manager then
        measured("open_motion_manager", window, function() RunConsoleCommand("mmdvmd_menu") end)
    end
    measured("select_motion_A", window, function()
        local list = tool_motion_list()
        local line = line_for(list, motionA)
        assert(line, "no line for motion A in the tool's list")
        list:OnClickLine(line, true)
    end)
    measured("select_motion_B", window, function()
        local list = tool_motion_list()
        local line = line_for(list, motionB)
        assert(line, "no line for motion B in the tool's list")
        list:OnClickLine(line, true)
    end)
    measured("close_spawnmenu", 2, function() GAMEMODE:OnSpawnMenuClose() end)
    wait(1)
    measured("select_self_reload", window, function() press("reload") end)
    aim_at(npcs[1])
    wait(0.5)
    measured("assign_npc1", window, function() aim_at(npcs[1]) press("attack") end)
    aim_at(npcs[2])
    wait(0.5)
    measured("assign_npc2", window, function() aim_at(npcs[2]) press("attack") end)
    measured("unassign_npc2", window, function() aim_at(npcs[2]) press("attack") end)
    measured("assign_npc2_again", window, function() aim_at(npcs[2]) press("attack") end)
    measured("idle_two_assigned", 5, function() end)
    measured("open_spawnmenu_again", window, function() GAMEMODE:OnSpawnMenuOpen() end)
    measured("select_motion_A_with_npcs", window, function()
        local list = tool_motion_list()
        local line = line_for(list, motionA)
        assert(line, "no line for motion A in the tool's list")
        list:OnClickLine(line, true)
    end)
    measured("close_spawnmenu_again", 2, function() GAMEMODE:OnSpawnMenuClose() end)
    measured("clear_selection", window, function() MMDVMDNPC.RequestClearAssignedActors("all") end)
    end

    if SETTINGS.features then
        local ok, result = pcall(features)
        local featuresOut = ok and result or { error = tostring(result) }
        file.Write("nlmp_probe/features.json", util.TableToJSON(featuresOut, true))
        print("NLMP_FEATURES " .. (ok and "done" or tostring(result)))
    end

    file.Write("nlmp_probe/summary.json", util.TableToJSON({ motions = motionCount, motionA = motionA, motionB = motionB,
        setup = setup, steps = results }, true))
    print("NLMP_DONE")
    print("NL_SHOT_DONE")
end

co = coroutine.create(function()
    local ok, err = pcall(sequence)
    if not ok then
        print("NLMP_ERROR " .. tostring(err))
        print("NL_SHOT_DONE")
    end
end)
hook.Add("Think", "NLMPC.Sequence", function()
    if not co or coroutine.status(co) == "dead" then
        hook.Remove("Think", "NLMPC.Sequence")
        return
    end
    local ok, err = coroutine.resume(co)
    if not ok then
        print("NLMP_ERROR " .. tostring(err))
        print("NL_SHOT_DONE")
        hook.Remove("Think", "NLMPC.Sequence")
    end
end)
print("NLMP_CLIENT_READY")
