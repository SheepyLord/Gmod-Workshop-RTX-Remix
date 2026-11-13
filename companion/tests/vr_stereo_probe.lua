-- Test only (VR V7): the warp, true stereo, the warp again and stereo again at one fixed step, with the eyes
-- captured in each phase. Appended to the production driver's script; uses its phase and emit and the nlvr
-- module global, whose Capture the driver queues until the overlays are painted.
local ID, began, plan, rows = "nlvr_v7_stereo", nil, nil, {}
local saved, restored, lastTrace = {}, false, nil
local STEP = S_STEP or "1"
local PHASES = {
    {at = 2, stereo = "0", label = "warp"},
    {at = 16, stereo = "1", label = "stereo"},
    {at = 32, stereo = "0", label = "warp-again"},
    {at = 44, stereo = "1", label = "stereo-again"},
}
local CAPTURE_AFTER, END_AT = 9, 58
local function info() local ok, value = pcall(nlvr.Info) return ok and type(value) == "table" and value or {} end
local function row(kind, label)
    local i = info()
    local p = NLVR and NLVR.Debug and NLVR.Debug.perf or {}
    return {kind = kind, label = label, t = SysTime() - began, stereo_active = i.stereoActive,
        gpu_work = i.gpuMsWork, gpu_total = i.gpuMsTotal, gpu_path = i.gpuMsPathTrace, gpu_upscale = i.gpuMsUpscale,
        rate = p.rate, step = p.step, stereo_setting = p.stereo, render_width = i.renderWidth,
        render_height = i.renderHeight, eye_width = i.eyeWidth, eye_height = i.eyeHeight, centre_width = i.centreWidth,
        rendered = i.framesRendered, submitted = i.framesSubmitted, error = p.error}
end
local function restore()
    if restored then return end
    restored = true
    for name, value in pairs(saved) do RunConsoleCommand(name, value) end
end
local current = nil
hook.Add("PreRender", ID, function()
    if phase ~= "active" then
        if began and phase == "flat-after" then
            restore()
            if #rows > 0 then emit("V7-stereo", {rows = rows}) rows = {} end
            hook.Remove("PreRender", ID)
        end
        return
    end
    if not (NLVR and NLVR.Debug and NLVR.Debug.perf) then return end
    local now = SysTime()
    if not began then
        began = now
        for _, name in ipairs({"nl_vr_quality", "nl_vr_stereo"}) do
            local cv = GetConVar(name) saved[name] = cv and cv:GetString() or "0"
        end
        RunConsoleCommand("nl_vr_quality", STEP)
        plan = {}
        for _, p in ipairs(PHASES) do
            plan[#plan + 1] = {at = p.at, run = function()
                RunConsoleCommand("nl_vr_stereo", p.stereo) current = p.label
                rows[#rows + 1] = {kind = "mark", what = p.label, t = SysTime() - began}
            end}
            plan[#plan + 1] = {at = p.at + CAPTURE_AFTER, run = function()
                -- Eyes, overlays and the mirror; the warp also has its centre view.
                local ok, detail = nlvr.Capture("v7-" .. p.label, p.stereo == "1" and 13 or 15)
                local r = row("capture", p.label) r.ok, r.detail = ok, detail
                rows[#rows + 1] = r
            end}
        end
        plan[#plan + 1] = {at = END_AT, run = function()
            restore()
            rows[#rows + 1] = {kind = "mark", what = "end", t = SysTime() - began}
            emit("V7-stereo", {rows = rows}) rows = {}
        end}
    end
    local t = now - began
    while plan[1] and plan[1].at <= t do table.remove(plan, 1).run() end
    if current and t < END_AT and (not lastTrace or t - lastTrace >= 0.5) then
        lastTrace = t
        rows[#rows + 1] = row("trace", current)
        if #rows >= 64 then emit("V7-stereo", {rows = rows}) rows = {} end
    end
end)
