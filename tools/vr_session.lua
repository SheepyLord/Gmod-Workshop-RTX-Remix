-- Real-package V1 acceptance probe, injected by vr_session.py through the game's console.
-- All test evidence leaves through console records or runtime captures under repository out/.
local ID = "nlvr_q_probe"
local began, phase, changed, requested = SysTime(), "flat-before", false, false
local phaseAt, activeAt, nextSample = began, nil, began
local saved, intervals, prior = {}, {}, SysTime()
local captures, errors, states = {}, {}, {}
local native, originalBegin, originalCamera, originalCreate
local overlay, lastFrame, lastCamera
local beginTimes, completionTimes, poseTimes, workTimes = {}, {}, {}, {}
local precedingBegin, previousBeginReturn
local mismatchBegan, mismatchEnded
local flatViewRegistry, priorFlatViews, ownedFlatViews
local flatViewCalls = 0
local before, after, beforeUpscaling
if CONFIG.inspect then require("nlvrqinspect") end
if not CONFIG.flat then
    require("nlvr")
    for _, key in ipairs({"openvr_dll", "manifest", "runtime_dll"}) do
        local allowed, message = nlvr.Start({[key] = "C:/must-not-load.dll"})
        assert(allowed == false and message, "removed path option was accepted: " .. key)
    end
    for _, name in ipairs({"../escape", "C:/outside", "a/b"}) do
        local allowed, message = nlvr.Capture(name, 15)
        assert(allowed == nil and message, "capture path was accepted")
    end
    local serialAllowed, serialError = nlvr.Start({pacing = "serial"})
    assert(serialAllowed == false and serialError, "shipping module accepted removed serial mode")
    print("NLVR_BOUNDARY_REFUSALS 7")
end
local lookEnding = false
concommand.Add("nl_shot_taken", function() end)
concommand.Add("nl_vr_demo_done", function()
    if CONFIG.look then NativeLoaderVR.Stop() lookEnding = true end
end)
local recordNumber = 0
local function emit(kind, value)
    value = value or {} value.kind = kind value.seconds = SysTime() - began
    local text = util.TableToJSON(value)
    if #text < 3000 then print("NLVR_Q " .. text) return end
    -- Source truncates a console line at 4095 bytes. Keep full native/timing/projection evidence.
    recordNumber = recordNumber + 1
    local encoded = util.Base64Encode(text):gsub("%s", "")
    local count = math.ceil(#encoded / 1600)
    for i = 1, count do
        print("NLVR_Q_CHUNK " .. recordNumber .. " " .. i .. "/" .. count .. " " .. encoded:sub((i - 1) * 1600 + 1, i * 1600))
    end
end
local names = {"fps_max", "mat_vsync", "mat_queue_mode", "gmod_mcore_test", "cl_drawhud", "r_drawviewmodel",
    "rtx_pseudoplayer", "rtx_pseudoweapon", "nl_vr_scale", "nl_vr_fov", "nl_vr_render_scale",
    "nativeloader_weather", "nativeloader_sky_time_passes", "nativeloader_sky_hour", "nativeloader_sky_follow_map"}
local function variables()
    local out = {}
    for _, name in ipairs(names) do
        local cv = GetConVar(name)
        if cv then out[name] = cv:GetString() end
    end
    return out
end
local function upscaling()
    if not RemixConfig or not RemixConfig.GetUpscalingState then return end
    local ok, state = pcall(RemixConfig.GetUpscalingState)
    if ok and type(state) == "table" then return state end
end
local function inventory()
    local out = {hooks = {}, timers = {}}
    for event, entries in pairs(hook.GetTable()) do
        for id in pairs(entries) do
            if tostring(id):find("nativeloader_vr", 1, true) then
                out.hooks[#out.hooks + 1] = event .. ":" .. tostring(id)
            end
        end
    end
    for _, id in ipairs({"nativeloader_vr_session"}) do
        if timer.Exists(id) then out.timers[#out.timers + 1] = id end
    end
    return out
end
local function stats(values)
    if #values == 0 then return {frames = 0} end
    local sum, max = 0, 0
    for _, v in ipairs(values) do sum = sum + v max = math.max(max, v) end
    local ordered = table.Copy(values) table.sort(ordered)
    return {frames = #values, mean_ms = sum / #values, median_ms = ordered[math.ceil(#values * 0.5)],
        p95_ms = ordered[math.ceil(#values * 0.95)], p99_ms = ordered[math.ceil(#values * 0.99)],
        max_ms = max, fps = #values * 1000 / sum}
end
local function phase_to(nextPhase)
    emit("phase", {phase = phase, intervals = stats(intervals), began = phaseAt - began})
    phase, phaseAt, intervals = nextPhase, SysTime(), {}
end
local function notices()
    for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if IsValid(p) and p.GetTitle and (tostring(p:GetTitle()):lower():find("loader update", 1, true) or
            tostring(p:GetTitle()):lower():find("remix guide", 1, true)) then p:Remove() end
    end
end
local function shot(label) print("NL_SHOT " .. label) end
local function capture(label)
    if captures[label] then return end
    captures[label] = true
    if label=="neutral" and not CONFIG.live_poses and lastCamera then
        local expected=CONFIG.camera or {823,-657,-40,0,180,0}
        local delta=(lastCamera.angles[2]-expected[5]+180)%360-180
        if math.abs(delta)>.5 then errors[#errors+1]="neutral camera did not use the requested fixture yaw" end
    end
    local ok, detail = native.Capture(label, 15)
    emit("capture", {label = label, ok = ok, detail = detail, frame = lastFrame,
        camera = lastCamera, info = native.Info(), test = native.TestState()})
    shot(label)
end
local function restore_probe()
    hook.Remove("CreateMove",ID)
    hook.Remove("CalcView",ID)
    if flatViewRegistry and flatViewRegistry.CalcView == ownedFlatViews then
        flatViewRegistry.CalcView = priorFlatViews
    end
    if native then
        native.BeginFrame, native.SetFrameCamera, native.OverlayCreate = originalBegin, originalCamera, originalCreate
    end
    for name, value in pairs(saved) do RunConsoleCommand(name, value) end
end
local function attach_probe()
    native = nlvr
    originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate
    native.BeginFrame = function(...)
        local t = SysTime()
        if previousBeginReturn then workTimes[#workTimes + 1] = (t - previousBeginReturn) * 1000 end
        precedingBegin = t
        local f, detail = originalBegin(...)
        previousBeginReturn = SysTime()
        beginTimes[#beginTimes + 1] = (previousBeginReturn - t) * 1000
        if f then
            lastFrame = f
            completionTimes[#completionTimes + 1] = f.completion_wait_ms
            poseTimes[#poseTimes + 1] = f.wait_ms
        elseif detail then errors[#errors + 1] = detail end
        return f, detail
    end
    native.SetFrameCamera = function(seq, origin, ang)
        lastCamera = {sequence = seq, origin = {origin.x, origin.y, origin.z}, angles = {ang.p, ang.y, ang.r}}
        if CONFIG.first_camera_mismatch then
            if not mismatchBegan then
                mismatchBegan=SysTime() emit("first-camera-mismatch",{duration_seconds=5})
            end
            if SysTime()-mismatchBegan<5 then return originalCamera(seq,origin+Vector(1000,0,0),ang) end
            if not mismatchEnded then mismatchEnded=true emit("first-camera-mismatch-ended") end
        end
        return originalCamera(seq, origin, ang)
    end
    native.OverlayCreate = function(...)
        local handle, detail = originalCreate(...) overlay = handle
        return handle, detail
    end
end
local function start()
    NativeLoaderVR.Start({timeline = not CONFIG.live_poses and CONFIG.timeline or nil, pacing = CONFIG.pacing})
    if type(nlvr) == "table" and not native then attach_probe() end
    phase_to("starting") requested = true
end
emit("install-stage", {stage="helpers-ready"})
local function sample()
    local result = {phase = phase, page = NativeLoaderVR.state, detail = NativeLoaderVR.detail,
        intervals = stats(intervals), camera = lastCamera, status_text = NativeLoaderVR.StatusText(), upscaling = upscaling()}
    if CONFIG.flat then result.flat_camera = {calls=flatViewCalls, fov=90, origin=CONFIG.camera} end
    if native then
        result.state, result.native_detail = native.State()
        result.info = native.Info()
        if overlay and native.OverlayVisible then result.overlay_visible = native.OverlayVisible(overlay) end
        if overlay and native.OverlayInfo then result.overlay = native.OverlayInfo(overlay) end
    end
    if nlvrqinspect then result.inspection = nlvrqinspect.Info(result.info and result.info.sdk_ready == true) end
    local p = LocalPlayer()
    if IsValid(p) then
        local w = p:GetActiveWeapon()
        result.hud = {health = p:Health(), armour = p:Armor(),
            clip = IsValid(w) and w:Clip1() or -1,
            reserve = IsValid(w) and p:GetAmmoCount(w:GetPrimaryAmmoType()) or -1}
    end
    emit("sample", result)
end
local function finish(success)
    phase_to("done")
    after = variables()
    local diff = {}
    for name, value in pairs(before or {}) do if value ~= after[name] then diff[name] = {value, after[name]} end end
    local afterUpscaling, selectorDiff = upscaling(), {}
    local checked = beforeUpscaling and beforeUpscaling.ready and afterUpscaling and afterUpscaling.ready
    if checked then
        for _, name in ipairs({"upscaler", "frame_generation", "dlss_supported", "dlss_frame_generation_supported", "fsr_frame_generation_supported"}) do
            if beforeUpscaling[name] ~= afterUpscaling[name] then selectorDiff[name] = {beforeUpscaling[name], afterUpscaling[name]} end
        end
    end
    emit("done", {success = success and next(diff) == nil and next(selectorDiff) == nil and #errors == 0, errors = errors,
        before = before, after = after, variable_differences = diff, inventory = inventory(),
        upscaling_before = beforeUpscaling, upscaling_after = afterUpscaling,
        live_selectors_checked = checked == true, selector_differences = selectorDiff,
        begin_frame = stats(beginTimes), completion_wait = stats(completionTimes),
        wait_get_poses = stats(poseTimes), game_work = stats(workTimes)})
    restore_probe()
    hook.Remove("Think", ID) hook.Remove("PreRender", ID) hook.Remove("PostRender", ID) hook.Remove("CalcView", ID)
    hook.Remove("RenderScene", ID) hook.Remove("HUDPaint", ID)
    print("NL_SHOT_DONE")
end
for _, name in ipairs({"nativeloader_weather", "nativeloader_weather_seconds", "nativeloader_sky_time_passes",
    "nativeloader_sky_hour", "nativeloader_sky_follow_map", "nativeloader_sky_direction",
    "nl_vr_render_scale", "nl_vr_fov"}) do
    local cv = GetConVar(name)
    if cv then saved[name] = cv:GetString() end
end
RunConsoleCommand("nativeloader_weather_seconds", "0")
RunConsoleCommand("nativeloader_weather", "clear")
RunConsoleCommand("nativeloader_sky_time_passes", "0")
RunConsoleCommand("nativeloader_sky_follow_map", "0")
RunConsoleCommand("nativeloader_sky_direction", "0")
RunConsoleCommand("nativeloader_sky_time", "12")
RunConsoleCommand("nl_vr_render_scale", tostring(CONFIG.render_scale))
RunConsoleCommand("nl_vr_fov", "145")
local camera = CONFIG.camera or {823, -657, -40, 0, 180, 0}
local origin, angles = Vector(camera[1], camera[2], camera[3]), Angle(camera[4], camera[5], camera[6])
if not CONFIG.look then
    hook.Add("CreateMove",ID,function(command)
        command:SetViewAngles(angles)
        command:ClearMovement()
        command:ClearButtons()
    end)
end
if CONFIG.flat then
    -- hook.Call stops at the first returned view, in undefined order. A control needs one authority.
    flatViewRegistry = hook.GetTable()
    priorFlatViews = flatViewRegistry.CalcView
    ownedFlatViews = {}
    flatViewRegistry.CalcView = ownedFlatViews
end
hook.Add("CalcView", ID, function()
    if CONFIG.flat then flatViewCalls = flatViewCalls + 1 end
    return {origin = origin, angles = angles, fov = 90, drawviewer = false}
end)
notices()
local barrel = ClientsideModel("models/props_c17/oildrum001.mdl", RENDERGROUP_OPAQUE)
emit("install-stage", {stage="barrel-created",valid=IsValid(barrel)})
if IsValid(barrel) then
    barrel:SetPos(origin + angles:Forward() * 100 + angles:Right() * 35 - Vector(0, 0, 20))
    barrel:SetAngles(Angle(0, 0, 0))
end
hook.Add("HUDPaint", ID, function()
    if NativeLoaderVR.state ~= "running" then return end
    surface.SetDrawColor(255, 0, 255, 255) surface.DrawRect(20, 20, 140, 32)
    draw.SimpleText("DESKTOP HUD", "DermaDefault", 24, 26, Color(0, 0, 0))
end)
local lastPage, pauseAt
hook.Add("PostRender", ID, function()
    local now = SysTime()
    intervals[#intervals + 1] = (now - prior) * 1000 prior = now
end)
hook.Add("PreRender", ID, function()
    local now = SysTime()
    -- RunConsoleCommand dispatches after this callback, so require() may finish on the next tick.
    if (requested or CONFIG.look) and not native and type(nlvr) == "table" then attach_probe() end
    notices()
    -- Console writes are queued. Establish the comparison baseline only after the
    -- fixture commands have actually latched, not during the first cold render callback.
    local fixtureReady = GetConVar("nativeloader_sky_time_passes"):GetString() == "0" and
        math.abs(GetConVar("nativeloader_sky_hour"):GetFloat() - 12) < 0.01
    if not before and now - began >= 1 and fixtureReady then
        before, beforeUpscaling = variables(), upscaling()
        emit("before", {variables = before, upscaling = beforeUpscaling, inventory = inventory(),
            queue_default = GetConVar("mat_queue_mode"):GetDefault(), queue_requested = CONFIG.queue_mode})
    end
    if NativeLoaderVR.state ~= lastPage then
        emit("state", {page = NativeLoaderVR.state, detail = NativeLoaderVR.detail})
        lastPage = NativeLoaderVR.state
    end
    if now >= nextSample then nextSample = now + 1 sample() end
    if CONFIG.look then
        if not captures.look_ready and now - began >= 4 then
            captures.look_ready = true
            print("NLVR preview: RTX Remix > VR > Start VR (or nl_vr_start). Use nl_vr_demo_done when finished; the driver restores settings and quits.")
        end
        if now - began >= CONFIG.seconds and not lookEnding then NativeLoaderVR.Stop() lookEnding = true end
        if lookEnding and NativeLoaderVR.state == "off" then finish(true) end
        return
    end
    if phase == "flat-before" then
        if now - began >= 4 and not captures.flat_before then captures.flat_before = true shot("flat-before") end
        if now - began >= 7 and before then
            if CONFIG.flat then phase_to("flat-control") else start() end
        end
    elseif phase == "flat-control" then
        if now - phaseAt >= CONFIG.seconds then shot("flat-after") finish(true) end
    elseif phase == "starting" then
        if NativeLoaderVR.state == "failed" then
            if CONFIG.expect_failure == NativeLoaderVR.reason and
                (not CONFIG.expect_detail or tostring(NativeLoaderVR.detail):find(CONFIG.expect_detail,1,true)) then
                emit("expected-failure", {reason = NativeLoaderVR.reason, text = NativeLoaderVR.StatusText()}) phase_to("expected-stopping")
            else errors[#errors + 1] = NativeLoaderVR.detail finish(false) end
        elseif NativeLoaderVR.state == "running" and native and (native.Info().framesSubmitted or 0) >= 5 then
            local startup = now - phaseAt
            activeAt = now phase_to("active") emit("running", {info = native.Info(), startup_seconds = startup})
        elseif now - phaseAt > 40 then errors[#errors + 1] = "start did not reach submitted frames in 40 seconds" NativeLoaderVR.Stop() finish(false) end
    elseif phase == "active" then
        local t = now - activeAt
        if NativeLoaderVR.state == "failed" then
            if CONFIG.expect_failure == NativeLoaderVR.reason and
                (not CONFIG.expect_detail or tostring(NativeLoaderVR.detail):find(CONFIG.expect_detail,1,true)) then
                emit("expected-failure", {reason = NativeLoaderVR.reason, text = NativeLoaderVR.StatusText()}) phase_to("expected-stopping")
            else errors[#errors+1]=NativeLoaderVR.detail finish(false) end
            return
        end
        if CONFIG.test_quit then
            if t>2 and not changed then changed=true gui.ActivateGameUI() emit("paused-quit-start",{curtime=CurTime()}) end
            if NativeLoaderVR.state=="off" then
                gui.HideGameUI() emit("paused-quit-ended",{curtime=CurTime(),info=native.Info()}) finish(true)
            elseif t>25 then errors[#errors+1]="native quit not handled while paused" gui.HideGameUI() finish(false) end
            return
        end
        if t >= 3 then capture("neutral") end
        if CONFIG.seconds >= 55 then
            local time = native.TestState()
            time = time and time.time or 0
            if time >= 18 and time < 22 then capture("yaw-plus20") end
            if time >= 30 and time < 34 then capture("yaw-minus20") end
            if time >= 42 and time < 46 then capture("lean-left") end
        end
        if t >= math.min(48, CONFIG.seconds - 5) and not changed then
            changed = true
            RunConsoleCommand("nlvr_q_hud")
        end
        if changed and t >= math.min(50, CONFIG.seconds - 3) then capture("hud-changed") end
        if CONFIG.scene_pause and t >= CONFIG.seconds - 10 and not pauseAt then
            pauseAt = now hook.Add("RenderScene", ID, function() return true end)
            emit("scene-pause", {info = native.Info()})
        end
        if pauseAt and not CONFIG.exit_paused and now - pauseAt >= 5 then
            hook.Remove("RenderScene", ID) emit("scene-resume", {info = native.Info()}) pauseAt = math.huge
        end
        if pauseAt and pauseAt~=math.huge and not CONFIG.exit_paused and now-pauseAt>=1 then capture("deferred-scene") end
        if t >= CONFIG.seconds then
            sample() emit("final-vr", {info = native.Info(), begin_frame = stats(beginTimes),
                completion_wait = stats(completionTimes), wait_get_poses = stats(poseTimes), game_work = stats(workTimes)})
            if CONFIG.quit_in_vr then
                emit("done", {success = #errors == 0, active_shutdown = true, before = before, variables = variables()})
                hook.Remove("Think", ID) restore_probe() print("NL_SHOT_DONE")
            else RunConsoleCommand("nl_vr_exit") phase_to("stopping") end
        end
    elseif phase == "expected-stopping" then
        if now-phaseAt>=2 and (not native or native.State()=="off") then finish(true)
        elseif now-phaseAt>30 then errors[#errors+1]="expected failure did not finish cleanup" finish(false) end
    elseif phase == "stopping" then
        local state = native.State()
        if state == "off" and NativeLoaderVR.state == "off" then
            hook.Remove("RenderScene", ID)
            RunConsoleCommand("nlvr_q_hud", "restore")
            emit("off", {variables = variables(), inventory = inventory()}) phase_to("flat-after")
        elseif now - phaseAt > 30 then errors[#errors + 1] = "stop did not acknowledge off" finish(false) end
    elseif phase == "flat-after" then
        if now - phaseAt >= 5 then shot("flat-after") phase_to("starting-second") end
    elseif phase == "starting-second" then
        if now - phaseAt >= 2 then RunConsoleCommand("nl_vr_start", CONFIG.timeline) phase_to("second") end
    elseif phase == "second" then
        if NativeLoaderVR.state == "running" and (native.Info().framesSubmitted or 0) >= 60 then
            emit("second-cycle", {info = native.Info()}) RunConsoleCommand("nl_vr_exit") phase_to("stopping-second")
        elseif NativeLoaderVR.state == "failed" or now - phaseAt > 35 then errors[#errors + 1] = "second start failed" finish(false) end
    elseif phase == "stopping-second" then
        if native.State() == "off" and NativeLoaderVR.state == "off" then finish(true)
        elseif now - phaseAt > 30 then errors[#errors + 1] = "second stop failed" finish(false) end
    end
end)
emit("probe-ready", {frame_number=FrameNumber(),game_ui_visible=gui.IsGameUIVisible()})
