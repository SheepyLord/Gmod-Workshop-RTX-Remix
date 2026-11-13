-- V6: the quality step in use. Auto moves one rung at a time from measured frames; a fixed
-- setting pins a rung. Nothing here renders; it only chooses, applies and reports.
local module = {name = "perf", order = 60}
local Ladder = include("nlvr/modules/cl_perf_ladder.lua")
local Control = include("nlvr/modules/cl_perf_control.lua")
local SAMPLE = 0.25   -- seconds between readings of the module's counters
local ID = "nlvr.perf"
-- Reasons are keys ("gpu", "hand", "auto", "down", "up"); the VR page owns their translated wording.
function module.Start(ctx)
    local native, core = ctx.native, ctx.core
    local debug = {}
    ctx.Debug.perf = debug
    local control = Control.New{steps = Ladder.Count()}
    local target, budget = nil, nil
    local lastFrames, lastSample, applied = nil, nil, nil

    local function ceiling()
        local cvar = GetConVar("nl_vr_render_scale")
        return cvar and cvar:GetFloat() or 1
    end
    local function fixed()
        -- 0 is Auto; anything else pins that rung.
        local setting = math.floor(tonumber(core.Settings.quality) or 0)
        if setting > 0 then return math.min(setting, Ladder.Count()) end
        return nil
    end
    local function apply(index, reason, force)
        local step = Ladder.Step(index, ceiling())
        -- V7: true stereo rides on every step; the runtime honours it only with Ray Reconstruction.
        step.stereo = (tonumber(core.Settings.stereo) or 0) >= 1
        if not force and applied and applied.index == step.index and applied.render_scale == step.render_scale and
            applied.stereo == step.stereo then
            debug.reason = reason or debug.reason
            return true
        end
        local ok, err = native.SetQuality(step)
        if not ok then
            -- Report it; the session keeps the step it had. A refused step is not retried every frame.
            debug.error = tostring(err or "refused")
            return false
        end
        applied, debug.error = step, nil
        debug.step, debug.step_name, debug.reason = step.index, step.name, reason
        debug.render_scale, debug.dlss = step.render_scale, step.dlss
        debug.min_bounces, debug.max_bounces = step.min_bounces, step.max_bounces
        debug.volumetrics, debug.fine_clouds, debug.stereo = step.volumetrics, step.fine_clouds, step.stereo
        debug.changes = (debug.changes or 0) + 1
        return true
    end
    local function begin(info)
        local refresh = tonumber(info and info.refresh) or 90
        if refresh <= 0 or refresh ~= refresh then refresh = 90 end
        -- Half the refresh, which SteamVR's Motion Smoothing fills in, is the rate to hold.
        target = refresh / 2
        budget = 1000 / target
        debug.target_rate, debug.budget_ms = target, budget
        local pinned = fixed()
        local start = pinned or (NativeLoaderVR and NativeLoaderVR.StartStep and NativeLoaderVR.StartStep()) or 1
        control.Begin(start, RealTime())
        debug.auto = pinned == nil
        apply(start, pinned and "hand" or "gpu", true)
    end

    ctx.On("setting", function(name)
        if name == "stereo" and target then apply(control.index, debug.reason) return end
        if name ~= "quality" or not target then return end
        local pinned = fixed()
        debug.auto = pinned == nil
        if pinned then
            control.Begin(pinned, RealTime())
            apply(pinned, "hand")
        else
            control.Begin(control.index, RealTime())
            apply(control.index, "auto")
        end
    end)
    -- The render scale slider is a ceiling: lowering it takes effect at once.
    cvars.AddChangeCallback("nl_vr_render_scale", function()
        if target then apply(control.index, debug.reason) end
    end, ID)
    ctx.cleanup(function() cvars.RemoveChangeCallback("nl_vr_render_scale", ID) end)

    ctx.On("frame", function()
        local now = RealTime()
        if lastSample and now - lastSample < SAMPLE then return end
        lastSample = now
        local info = native.Info()
        if type(info) ~= "table" then return end
        if not target then begin(info) end
        -- A simulated session submits nothing; its rendered frames are the only measure there.
        local submitted = tonumber(info.framesSubmitted) or 0
        local counter = submitted > 0 and submitted or tonumber(info.framesRendered) or 0
        local delta = lastFrames and math.max(0, counter - lastFrames) or 0
        lastFrames = counter
        -- The GPU's work: on a headset the frame's total also holds the queue's waits for the CPU (pacing).
        local gpu = tonumber(info.gpuMsWork)
        if not gpu or gpu <= 0 then gpu = tonumber(info.gpuMsTotal) end
        local index, reason = control.Sample(now, delta, target, gpu, budget)
        debug.rate, debug.gpu_ms, debug.cpu_limited = control.rate, control.gpuMs, control.cpuLimited
        if reason and debug.auto then
            if not apply(index, reason) then control.Begin(applied and applied.index or index, now) end
        elseif reason then
            -- A pinned step ignores the controller; keep it measuring from the pinned rung.
            control.Begin(applied and applied.index or control.index, now)
        end
    end)

    ctx.cleanup(function() if ctx.Debug.perf == debug then ctx.Debug.perf = nil end end)
end
function module.Stop() end
return module
