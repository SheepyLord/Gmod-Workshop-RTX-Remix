-- Test-only API-v1 session. No require, DLL, OpenVR or runtime calls.
return function()
    local state = {calls = {}, cameras = {}, frames = {}, events = {}, overlays = {}, sequence = 0, mode = "off",
        pose = {pos = Vector(0, 0, 1.6), ang = Angle()}, duplicatePushes = 0}
    local function vector(v) return {x = v.x, y = v.y, z = v.z} end
    local function angle(a) return {p = a.p, y = a.y, r = a.r} end
    local function record(name, args)
        state.calls[#state.calls + 1] = {name = name, args = args, frame = FrameNumber(), seconds = SysTime()}
    end
    local api = {}
    function api.Version() record("Version") return 1 end
    function api.Probe()
        record("Probe") return {runtime_api = 3, openvr_dll = true, steamvr_installed = true, steamvr_running = false}
    end
    function api.Start(options)
        record("Start", options) state.mode, state.lastCamera, state.input = "running", nil, nil return true
    end
    function api.State() record("State") return state.mode, "scripted stand-in; no OpenVR" end
    function api.Stop()
        record("Stop") state.mode = "off"
        if state.onStop then state.onStop() end
    end
    function api.Info()
        record("Info")
        return {model = "SCRIPTED TEST (no OpenVR)", refresh = 90, eye_width = 2016, eye_height = 2240,
            devices = {left = true, right = true}, presents = state.sequence, dropped = 0, reprojected = 0,
            compositor_gpu_ms = 0, compositor_cpu_ms = 0, gpuMsTotal = 0, gpuMsPathTrace = 0, gpuMsUpscale = 0,
            gpuMsWarp = 0, gpuMsOther = 0, framesSubmitted = 0, submitErrors = 0, posesMatched = #state.cameras,
            posesUnmatched = 0, centreWidth = 0, centreHeight = 0, renderWidth = 0, renderHeight = 0,
            eyeWidth = 0, eyeHeight = 0}
    end
    function api.BeginFrame()
        record("BeginFrame")
        if state.mode ~= "running" then return end
        state.sequence = state.sequence + 1
        local pose = {valid = true, pos = Vector(state.pose.pos.x, state.pose.pos.y, state.pose.pos.z),
            ang = Angle(state.pose.ang.p, state.pose.ang.y, state.pose.ang.r), vel = Vector(), angvel = Vector()}
        state.frames[state.sequence] = {frame = FrameNumber(), pos = vector(pose.pos), ang = angle(pose.ang)}
        return {sequence = state.sequence, hmd = pose, left = pose, right = pose, ipd = 0.064, seconds_to_photons = 0}
    end
    function api.SetFrameCamera(sequence, origin, angles)
        local item = {sequence = sequence, origin = vector(origin), angles = angle(angles), frame = FrameNumber()}
        record("SetFrameCamera", item)
        state.pushed = state.pushed or {}
        if state.pushed[sequence] then state.duplicatePushes = state.duplicatePushes + 1 end
        state.pushed[sequence] = true
        state.cameras[#state.cameras + 1] = item
        state.lastCamera = item
        if state.onCamera then state.onCamera(sequence, origin, angles) end
    end
    function api.Events() record("Events") local events = state.events state.events = {} return events end
    function api.OverlayCreate(key, name)
        record("OverlayCreate", {key = key, name = name}) state.overlays[1] = {} return 1
    end
    function api.OverlaySource(handle, width, height)
        record("OverlaySource", {handle = handle, width = width, height = height})
        state.overlays[handle].width, state.overlays[handle].height = width, height
    end
    function api.OverlayAttach(handle, device, pos, ang, width)
        record("OverlayAttach", {handle = handle, device = device, pos = vector(pos), ang = angle(ang), width = width})
    end
    function api.OverlayShow(handle, shown) record("OverlayShow", {handle = handle, shown = shown}) end
    function api.OverlayDestroy(handle) record("OverlayDestroy", {handle = handle}) state.overlays[handle] = nil end
    return api, state
end
