-- Test only (VR V6): pin every ladder step, then drive Auto through measured misses. Appended to the
-- production driver's script; uses its phase, emit and the nlvr module global.
local ID, began, plan, rows = "nlvr_v6_quality", nil, nil, {}
local savedQuality, restored, lastTrace = nil, false, nil
local HOLD, FIXED_FROM = 3.5, 3
local AUTO_AT = FIXED_FROM + 7 * HOLD + 1          -- Auto from the top; frames missed while the GPU has room
local LOAD_AT = AUTO_AT + (Q_CPU_SECONDS or 10)    -- frames missed with the GPU over its budget
local UNLOAD_AT = LOAD_AT + (Q_DOWN_SECONDS or 30) -- the session's own readings again
local END_AT = UNLOAD_AT + (Q_UP_SECONDS or 70)
local realInfo = nlvr.Info
-- Auto measures through nlvr.Info. While a miss is staged this keeps 40 % of the session's frames and
-- reports the GPU at a set share of the frame budget; afterwards ("pass") every frame counts again and
-- the GPU time is the session's, with the counter kept continuous. Every other field is real.
local RATE, GPU = {cpu = 0.4, load = 0.4, pass = 1}, {cpu = 0.3, load = 1.5}
local mode, synthetic, lastReal = nil, nil, nil
local function staged()
    local ok, value = pcall(realInfo)
    if not ok or type(value) ~= "table" or not mode then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = v end
    local counter = (tonumber(value.framesSubmitted) or 0) > 0 and "framesSubmitted" or "framesRendered"
    local real = tonumber(value[counter]) or 0
    if not synthetic or real < lastReal then synthetic, lastReal = real, real end
    synthetic = synthetic + (real - lastReal) * RATE[mode]
    lastReal = real
    copy[counter] = math.floor(synthetic)
    local perf = NLVR and NLVR.Debug and NLVR.Debug.perf
    local budget = perf and perf.budget_ms or 1000 / 45
    if GPU[mode] then copy.gpuMsTotal, copy.gpuMsWork = budget * GPU[mode], budget * GPU[mode] end
    return copy
end
local function stage(next)
    mode = next
    nlvr.Info = next and staged or realInfo
end
local function info() local ok, value = pcall(realInfo) return ok and type(value) == "table" and value or {} end
local function perf()
    local p = NLVR and NLVR.Debug and NLVR.Debug.perf
    if not p then return nil end
    return {step = p.step, name = p.step_name, reason = p.reason, auto = p.auto, scale = p.render_scale,
        dlss = p.dlss, min_bounces = p.min_bounces, max_bounces = p.max_bounces, volumetrics = p.volumetrics,
        fine_clouds = p.fine_clouds, rate = p.rate, gpu_ms = p.gpu_ms, cpu_limited = p.cpu_limited,
        target = p.target_rate, budget = p.budget_ms, changes = p.changes, error = p.error}
end
local function runtime()
    local i = info()
    return {scale = i.qualityRenderScale, dlss = i.qualityDlss, min_bounces = i.qualityMinBounces,
        max_bounces = i.qualityMaxBounces, flags = i.qualityFlags, changes = i.qualityChanges,
        eye_width = i.eyeWidth, eye_height = i.eyeHeight, centre_width = i.centreWidth, render_width = i.renderWidth,
        rec_width = i.eye_width, rec_height = i.eye_height,
        rendered = i.framesRendered, submitted = i.framesSubmitted, gpu_ms = i.gpuMsTotal, gpu_work = i.gpuMsWork}
end
local function restore()
    if restored then return end
    restored = true
    stage(nil)
    if savedQuality then RunConsoleCommand("nl_vr_quality", savedQuality) end
end
hook.Add("PreRender", ID, function()
    if phase ~= "active" then
        if began and phase == "flat-after" then
            restore()
            if #rows > 0 then emit("V6-quality", {rows = rows}) rows = {} end
            hook.Remove("PreRender", ID)
        end
        return
    end
    if not (NLVR and NLVR.Debug and NLVR.Debug.perf) then return end
    local now = SysTime()
    if not began then
        began = now
        local q = GetConVar("nl_vr_quality") savedQuality = q and q:GetString() or "0"
        plan = {}
        for step = 1, 7 do
            local at = FIXED_FROM + (step - 1) * HOLD
            plan[#plan + 1] = {at = at, run = function() RunConsoleCommand("nl_vr_quality", tostring(step)) end}
            plan[#plan + 1] = {at = at + HOLD - 0.3, run = function()
                rows[#rows + 1] = {kind = "fixed", step = step, t = SysTime() - began, perf = perf(), runtime = runtime()}
            end}
        end
        plan[#plan + 1] = {at = AUTO_AT - 1, run = function() RunConsoleCommand("nl_vr_quality", "1") end}
        plan[#plan + 1] = {at = AUTO_AT, run = function()
            stage("cpu") RunConsoleCommand("nl_vr_quality", "0")
            rows[#rows + 1] = {kind = "mark", what = "auto", t = SysTime() - began}
        end}
        plan[#plan + 1] = {at = LOAD_AT, run = function()
            stage("load")
            rows[#rows + 1] = {kind = "mark", what = "load", t = SysTime() - began}
        end}
        plan[#plan + 1] = {at = UNLOAD_AT, run = function()
            stage("pass")
            rows[#rows + 1] = {kind = "mark", what = "unload", t = SysTime() - began}
        end}
        plan[#plan + 1] = {at = END_AT, run = function()
            restore()
            rows[#rows + 1] = {kind = "mark", what = "end", t = SysTime() - began}
            emit("V6-quality", {rows = rows}) rows = {}
        end}
    end
    local t = now - began
    while plan[1] and plan[1].at <= t do table.remove(plan, 1).run() end
    -- Auto's path: one row every half second while it is in charge.
    if t >= AUTO_AT and t < END_AT and (not lastTrace or t - lastTrace >= 0.5) then
        lastTrace = t
        rows[#rows + 1] = {kind = "trace", t = t, perf = perf(), runtime = runtime()}
        if #rows >= 64 then emit("V6-quality", {rows = rows}) rows = {} end
    end
end)
