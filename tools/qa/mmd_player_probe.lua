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

-- The user's request of 2026-11-16 (ADR 0229): ToPBR's range. Three props are spawned in view, ToPBR is turned on
-- with debug output, and each range runs for 25 seconds between NLTP_PHASE console lines (the console's "Processed
-- material '...'" lines between them are what that range converted). For each: the native converter's view
-- (restricted, names held, the player's setting, materials processed) and whether it takes a world material, the
-- props' materials and the view model's.
local function topbr_range()
    local tp = MaterialPipeline and MaterialPipeline.ToPBR
    if not (tp and tp.GetScope and tp.InScope and tp.GetStats) then return { error = "ToPBR range API missing" } end
    local out = {}
    local world = game.GetWorld():GetMaterials() or {}
    out.world_materials = #world
    local ply = LocalPlayer()
    local base = ply:EyeAngles()
    for index, model in ipairs({ "models/props_c17/oildrum001.mdl", "models/props_junk/wood_crate001a.mdl",
            "models/props_interiors/furniture_chair01a.mdl" }) do
        ply:SetEyeAngles(Angle(20, base.y + (index - 2) * 25, 0))
        RunConsoleCommand("gm_spawn", model)
        wait(0.4)
    end
    ply:SetEyeAngles(Angle(15, base.y, 0))
    wait(1)
    local viewModel = ply:GetViewModel()
    local viewMaterials = IsValid(viewModel) and viewModel:GetMaterials() or {}
    out.view_model_material = viewMaterials[1]
    -- The spawned props' own materials (an oil drum's is models/props_c17/oil_drum001a).
    out.prop_materials = {}
    for _, prop in ipairs(ents.FindByClass("prop_physics")) do
        local first = (prop:GetMaterials() or {})[1]
        if first then out.prop_materials[prop:GetModel() or "?"] = first end
    end
    RunConsoleCommand("rtx_topbr_debug", "1")
    RunConsoleCommand("rtx_topbr_scope", "0")
    RunConsoleCommand("rtx_topbr_enabled", "1")
    local function phase(name, scope, seconds)
        RunConsoleCommand("rtx_topbr_scope", tostring(scope))
        wait(1)
        print("NLTP_PHASE " .. name .. " begin")
        wait(seconds)
        local restricted, held, setting = tp.GetScope()
        local stats = tp.GetStats() or {}
        local function taken(material) if material then return tp.InScope(material) == true end return "none" end
        local props = {}
        for model, material in pairs(out.prop_materials) do props[model] = taken(material) end
        out[name] = { restricted = restricted, held = held, setting = setting, processed = stats.materialsProcessed,
            failed = stats.failedConversions, world = taken(world[1]), props = props,
            view_model = taken(out.view_model_material) }
        print("NLTP_PHASE " .. name .. " end")
    end
    phase("map", 0, 25)
    phase("props", 1, 25)
    phase("everything", 2, 25)
    phase("map_again", 0, 25)
    RunConsoleCommand("rtx_topbr_enabled", "0")
    RunConsoleCommand("rtx_topbr_debug", "0")
    return out
end

-- The user's requests of 2026-11-16: the dancing body's push strength (the bodies as they were before, then 100
-- percent of the ragdoll's weight, the default, 25 and 0) and the hold on the last pose before the reference pose.
local function qol_checks(out)
    RunConsoleCommand("mmd_vmd_npc_ragdoll_collision", "1")
    RunConsoleCommand("mmd_vmd_npc_ragdoll_push", "100")
    wait(0.6)
    -- Where the held-out hands are, for the props in the swing's way.
    if not out.collision_on then out.collision_on = run_server("collision", 60) end
    out.push_old = run_server("push_old", 60)
    for _, percent in ipairs({ 100, 25, 0 }) do
        RunConsoleCommand("mmd_vmd_npc_ragdoll_push", tostring(percent))
        wait(0.6)
        out["push_" .. percent] = run_server("push", 60)
    end
    RunConsoleCommand("mmd_vmd_npc_ragdoll_push", "100")
    wait(0.6)
    out.endhold = run_server("endhold", 60)
    local ok, result = pcall(topbr_range)
    out.topbr_range = ok and result or { error = tostring(result) }
end

local function features()
    local out = {}
    out.build = run_server("build", 150)
    if not out.build.built then return out end
    if SETTINGS.features then
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
    end
    if SETTINGS.qol then
        local ok, result = pcall(qol_checks, out)
        if not ok then out.qol_error = tostring(result) end
    end
    run_server("cleanup", 10)
    return out
end

-- ---- Hide yourself during camera motion (ADR 0250, the user's request of 2026-11-21) ----
-- Screenshots go through poc_session.py --lua-shots: "NL_SHOT <label>", answered with nl_shot_taken <n>.
local shotsTaken, shotsAsked = 0, 0
concommand.Add("nl_shot_taken", function(_, _, args) shotsTaken = tonumber(args and args[1]) or (shotsTaken + 1) end)
-- A fresh PoC's first RTX map opens the RTX Remix guide (eight seconds after the spawn) and may show the loader's
-- update reminder: windows over the shot, removed as vr_session.lua does.
local function clear_windows()
    for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
        local title = IsValid(panel) and isfunction(panel.GetTitle) and string.lower(tostring(panel:GetTitle())) or ""
        if string.find(title, "remix guide", 1, true) or string.find(title, "loader update", 1, true) then panel:Remove() end
    end
end
local function shot(label)
    clear_windows()
    wait(0.3)
    shotsAsked = shotsAsked + 1
    print("NL_SHOT " .. label)
    local deadline = clock() + 90
    while shotsTaken < shotsAsked and clock() < deadline do coroutine.yield() end
    wait(0.3)
    return shotsTaken >= shotsAsked
end

-- Which of Think, CalcView, PreRender, RenderScene and PostRender come in a frame, in order, with
-- FrameNumber(): recorded in first person, so no camera answers CalcView before the marker.
local function hook_order()
    local log = {}
    local function mark(name)
        return function() if #log < 60 then log[#log + 1] = name .. "@" .. FrameNumber() end end
    end
    for _, event in ipairs({ "Think", "CalcView", "PreRender", "RenderScene", "PostRender" }) do
        hook.Add(event, "NLMPC.Order", mark(event))
    end
    wait(0.5)
    for _, event in ipairs({ "Think", "CalcView", "PreRender", "RenderScene", "PostRender" }) do
        hook.Remove(event, "NLMPC.Order")
    end
    return log
end

-- Per frame while a sample runs, the no-draw flags of your body, your active weapon, the RTX fixes' body and
-- weapon copies and a Model Hotloader character's visual proxy: right after the add-on's RenderScene hook
-- hid them (`after_hide_*`), right before and after its PostRender hook put them back (`before_restore_*`,
-- `after_restore_*`) and between frames (`outside_*`, in Think); the camera's state; which of the scene's
-- hooks ran, how often you were no-draw in them and the arguments of one call each (`events`,
-- `events_hidden`, `event_args`); and the radiance your RTX flashlight's light was given
-- (RemixLight.UpdateSphere, recognised by the fixes' hash for your index).
local camSample
local flashHash
local function first(class) return ents.FindByClass(class)[1] end
local function flags(into, prefix)
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    local body, weaponCopy = first("rtx_pseudoplayer"), first("rtx_pseudoweapon")
    local function count(key, condition) if condition then into[prefix .. key] = (into[prefix .. key] or 0) + 1 end end
    count("player", ply:GetNoDraw())
    count("weapon", IsValid(wep) and wep:GetNoDraw())
    count("body_copy", IsValid(body) and body:GetNoDraw())
    count("weapon_copy", IsValid(weaponCopy) and weaponCopy:GetNoDraw())
    local visual = ply.MMDHLVisual
    count("mmd_visual", IsValid(visual) and visual:GetNoDraw())
end
local function wrap_hide_hooks()
    local hooks = hook.GetTable()
    local scene = hooks.RenderScene and hooks.RenderScene.MMDVMDNPCHidePlayer
    local post = hooks.PostRender and hooks.PostRender.MMDVMDNPCHidePlayer
    if isfunction(scene) and not C.sceneWrapped then
        C.sceneWrapped = true
        hook.Add("RenderScene", "MMDVMDNPCHidePlayer", function(...)
            scene(...)
            local s = camSample
            if s then
                s.frames = s.frames + 1
                flags(s, "after_hide_")
                if MMDVMDNPC.CameraAnimActive then s.camera_active = s.camera_active + 1 end
                if MMDVMDNPC.CameraHidesLocalPlayer() then s.hides = s.hides + 1 end
                if LocalPlayer():ShouldDrawLocalPlayer() then s.draws_local_player = s.draws_local_player + 1 end
            end
        end)
    end
    if isfunction(post) and not C.postWrapped then
        C.postWrapped = true
        hook.Add("PostRender", "MMDVMDNPCHidePlayer", function(...)
            local s = camSample
            if s then flags(s, "before_restore_") end
            post(...)
            if s then flags(s, "after_restore_") end
        end)
    end
    return C.sceneWrapped == true and C.postWrapped == true
end
for _, event in ipairs({ "PostDrawOpaqueRenderables", "PreDrawTranslucentRenderables", "PostDrawTranslucentRenderables",
        "RenderScreenspaceEffects", "PreDrawHUD", "PostDrawHUD" }) do
    hook.Add(event, "NLMPC.CameraSample", function(a, b, c)
        local s = camSample
        if not s then return end
        s.events[event] = (s.events[event] or 0) + 1
        if LocalPlayer():GetNoDraw() then s.events_hidden[event] = (s.events_hidden[event] or 0) + 1 end
        -- The arguments a call brought (depth, skybox, 3D skybox for the renderables' hooks), once per sample.
        s.event_args[event] = s.event_args[event] or { tostring(a), tostring(b), tostring(c) }
    end)
end
hook.Add("Think", "NLMPC.CameraSampleOutside", function()
    local s = camSample
    if not s then return end
    s.thinks = s.thinks + 1
    flags(s, "outside_")
end)
local unwrapFlash
local function wrap_flashlight()
    if unwrapFlash or not (istable(RemixLight) and RemixLight.UpdateSphere) then return end
    local original = RemixLight.UpdateSphere
    RemixLight.UpdateSphere = function(base, sphere, id, ...)
        local s = camSample
        if s and istable(base) and base.hash == flashHash and istable(base.radiance) then
            s.flash[#s.flash + 1] = tonumber(base.radiance.x) or -1
        end
        return original(base, sphere, id, ...)
    end
    unwrapFlash = function() RemixLight.UpdateSphere = original end
end
local function sample(seconds)
    camSample = { frames = 0, thinks = 0, camera_active = 0, hides = 0, draws_local_player = 0, flash = {}, events = {},
        events_hidden = {}, event_args = {} }
    wait(seconds)
    local s = camSample
    camSample = nil
    local lo, hi = math.huge, -math.huge
    for _, value in ipairs(s.flash) do lo, hi = math.min(lo, value), math.max(hi, value) end
    s.flash_updates, s.flash_min, s.flash_max = #s.flash, #s.flash > 0 and lo or nil, #s.flash > 0 and hi or nil
    s.flash = nil
    s.hide_option = GetConVar("mmd_vmd_npc_cam_hide_player") and GetConVar("mmd_vmd_npc_cam_hide_player"):GetString()
    s.instance = LocalPlayer().MMDHLClientInstance
    s.body_copies, s.weapon_copies = #ents.FindByClass("rtx_pseudoplayer"), #ents.FindByClass("rtx_pseudoweapon")
    return s
end
local function wait_for(condition, timeout)
    local deadline = clock() + timeout
    while not condition() and clock() < deadline do coroutine.yield() end
    return condition()
end

local function camera_checks(npcs)
    local out = {}
    -- On for the checks, or off for the whole run (--hide-off: a control in which the hide never runs).
    local HIDE_ON = SETTINGS.hide == false and "0" or "1"
    out.hide_setting = HIDE_ON
    -- The guide opens eight seconds after the spawn: wait it out, then close it.
    wait_for(function()
        for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
            if IsValid(panel) and isfunction(panel.GetTitle) and string.find(string.lower(tostring(panel:GetTitle())), "remix guide", 1, true) then return true end
        end
        return false
    end, 15)
    clear_windows()
    out.hook_order = hook_order()
    out.hide_hooks_wrapped = wrap_hide_hooks()
    flashHash = tonumber(util.CRC("rtx_flashlight_" .. LocalPlayer():EntIndex()))
    wrap_flashlight()
    out.flashlight_api = unwrapFlash ~= nil
    local brightness = GetConVar("rtx_flashlight_brightness")
    local savedBrightness = brightness and brightness:GetString() or nil
    out.saved_brightness = savedBrightness
    -- The same light in every shot: the time of day held at 15:00 (put back at the end).
    -- And the RTX fixes' copies of your body and weapon (the companion's "Local player shadow"; the classic
    -- settings switch them off), so the run covers them too.
    local kept = {}
    for _, name in ipairs({ "nativeloader_sky_time_passes", "nativeloader_sky_follow_map", "nativeloader_sky_hour",
            "rtx_pseudoplayer", "rtx_pseudoweapon" }) do
        local cv = GetConVar(name)
        kept[name] = cv and cv:GetString() or nil
    end
    out.copies_setting = { rtx_pseudoplayer = kept.rtx_pseudoplayer, rtx_pseudoweapon = kept.rtx_pseudoweapon }
    RunConsoleCommand("nativeloader_sky_time_passes", "0")
    RunConsoleCommand("nativeloader_sky_time", "15")
    if SETTINGS.copies then
        RunConsoleCommand("rtx_pseudoplayer", "1")
        RunConsoleCommand("rtx_pseudoweapon", "1")
    end
    out.hide_option_default = GetConVar("mmd_vmd_npc_cam_hide_player") and GetConVar("mmd_vmd_npc_cam_hide_player"):GetString()
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", HIDE_ON)
    RunConsoleCommand("mmd_vmd_npc_camera_auto", "1")
    out.build = run_server("camera_build", 150)
    if not out.build.built then
        for name, value in pairs(kept) do RunConsoleCommand(name, value) end
        return out
    end
    -- Your light on the dancer, bright enough to see in daylight; the tool gun in your hand.
    aim_at(npcs[1])
    RunConsoleCommand("rtx_flashlight_brightness", "20000")
    RunConsoleCommand("rtx_flashlight_on")
    wait(1.5)
    out.first_person = sample(1)

    -- The dance's camera motion, looping: you are left out; unticked you are in it; ticked again out.
    out.play = run_server("camera_play", 30)
    out.entered = wait_for(function() return MMDVMDNPC.CameraAnimActive == true end, 10)
    wait(2.5)
    out.hidden = sample(2)
    out.shot_hidden = shot("camera_hidden")
    local view = { origin = MMDVMDNPC.CameraAnimViewOrigin, angles = MMDVMDNPC.CameraAnimViewAngles }
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", "0")
    wait(1)
    out.unticked = sample(2)
    out.shot_unticked = shot("camera_unticked")
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", HIDE_ON)
    wait(1)
    out.ticked_again = sample(1.5)

    -- Stopped: first person, nothing hidden; the same view drawn by this probe (third person) shows you.
    out.stop = run_server("camera_stop", 30)
    out.left = wait_for(function() return MMDVMDNPC.CameraAnimActive ~= true end, 10)
    wait(1)
    out.after_stop = sample(1.5)
    if view.origin and view.angles then
        -- The camera's field of view: vertical 50 as Source's 4:3 horizontal one (cl_camera.lua's conversion).
        local fov = math.deg(2 * math.atan(math.tan(math.rad(25)) * 4 / 3))
        hook.Add("CalcView", "NLMPC.SameView", function()
            return { origin = view.origin, angles = view.angles, fov = fov, drawviewer = true }
        end)
        wait(1)
        out.after_stop_same_view = sample(1)
        out.shot_after_stop = shot("after_stop_same_view")
        hook.Remove("CalcView", "NLMPC.SameView")
    end

    -- Cancelled with the camera toggle while the dance goes on.
    run_server("camera_play", 30)
    wait_for(function() return MMDVMDNPC.CameraAnimActive == true end, 10)
    wait(2.5)
    out.before_toggle = sample(1)
    RunConsoleCommand("mmdvmd_camera_toggle")
    wait(1)
    out.after_toggle = sample(1.5)
    run_server("camera_stop", 30)
    wait(1)

    -- Played once to its end (two seconds' countdown, four seconds' dance, the three seconds' end hold).
    out.play_once = run_server("camera_play_once", 30)
    wait_for(function() return MMDVMDNPC.CameraAnimActive == true end, 10)
    wait(2.5)
    out.once_playing = sample(1)
    local began = clock()
    out.ended = wait_for(function() return MMDVMDNPC.CameraAnimActive ~= true end, 20)
    out.ended_after_seconds = clock() - began
    wait(1)
    out.after_end = sample(1.5)

    -- An imported character as your player model: hidden too, and still the same character after more
    -- than the Model Hotloader's five seconds of hiding (it releases a character hidden that long).
    out.player_model = run_server("player_model", 120)
    wait(6)
    aim_at(npcs[1])
    RunConsoleCommand("rtx_flashlight_on")
    wait(1)
    out.mmd_first_person = sample(1)
    run_server("camera_play", 30)
    wait_for(function() return MMDVMDNPC.CameraAnimActive == true end, 10)
    wait(2.5)
    out.mmd_hidden = sample(2)
    out.shot_mmd_hidden = shot("mmd_camera_hidden")
    wait(6)
    out.mmd_hidden_later = sample(1)
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", "0")
    wait(1.5)
    out.mmd_unticked = sample(1.5)
    out.shot_mmd_unticked = shot("mmd_camera_unticked")
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", HIDE_ON)
    wait(1)

    -- The dancer removed under the camera: the camera motion fails, you are back.
    out.before_remove = sample(1)
    out.remove = run_server("camera_remove", 30)
    out.failed = wait_for(function() return MMDVMDNPC.CameraAnimActive ~= true end, 10)
    wait(1)
    out.after_remove = sample(1.5)

    RunConsoleCommand("rtx_flashlight_off")
    if savedBrightness then RunConsoleCommand("rtx_flashlight_brightness", savedBrightness) end
    for name, value in pairs(kept) do RunConsoleCommand(name, value) end
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", "1")
    if unwrapFlash then unwrapFlash() unwrapFlash = nil end
    run_server("camera_cleanup", 10)
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

    if SETTINGS.features or SETTINGS.qol then
        local ok, result = pcall(features)
        local featuresOut = ok and result or { error = tostring(result) }
        file.Write("nlmp_probe/features.json", util.TableToJSON(featuresOut, true))
        print("NLMP_FEATURES " .. (ok and "done" or tostring(result)))
    end

    -- ADR 0259: session one builds and checks a resized carrier, session two (a new game) finds that build.
    if SETTINGS.carriers and SETTINGS.carriers ~= "" then
        local ok, result = pcall(run_server, "carriers_" .. SETTINGS.carriers, 300)
        local carriersOut = ok and result or { error = tostring(result) }
        file.CreateDir("nlmp_probe")
        file.Write("nlmp_probe/carriers.json", util.TableToJSON(carriersOut, true))
        print("NLMP_CARRIERS " .. (ok and "done" or tostring(result)))
    end

    if SETTINGS.camera then
        local ok, result = pcall(camera_checks, npcs)
        local cameraOut = ok and result or { error = tostring(result) }
        file.CreateDir("nlmp_probe")
        file.Write("nlmp_probe/camera.json", util.TableToJSON(cameraOut, true))
        print("NLMP_CAMERA " .. (ok and "done" or tostring(result)))
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
