-- Time actual rendered frames on the two Modern House routes from the field study.
if not game.SinglePlayer() or game.GetMap() ~= "modern_house" or not IsValid(LocalPlayer()) then
    print("NL_MESH_ERROR single-player modern_house required")
    print("NL_SHOT_DONE")
    return
end
if NLRepeatedMeshProbe then return end
NLRepeatedMeshProbe = true
local tag = "NLRepeatedMeshProbe"
local previous, panels = {}, {}
local function temporary(name, value)
    local cvar = GetConVar(name)
    if not cvar then error("Missing " .. name) end
    previous[name] = cvar:GetString()
    RunConsoleCommand(name, value)
end
local scenes = {
    {name = "courtyard", origin = Vector(80, 1408, 490), yaw = -90, settle = 95},
    {name = "hall", origin = Vector(-16, 928, 482), yaw = 90, settle = 6},
}
local scene, phase, began, lastFrame, lastTime, lastPosition, distance
local samples, index, window = {}, 0, 0
local previousFocus, focusChanges, retries
local originalPosition, originalAngles = LocalPlayer():GetPos(), EyeAngles()
local function pose(origin, angles)
    RunConsoleCommand("setpos", tostring(origin.x), tostring(origin.y), tostring(origin.z))
    RunConsoleCommand("setang", tostring(angles.p), tostring(angles.y), tostring(angles.r))
end
local function finish(reason)
    if not NLRepeatedMeshProbe then return end
    NLRepeatedMeshProbe = nil
    hook.Remove("PostRender", tag)
    hook.Remove("CreateMove", tag)
    concommand.Remove("nl_shot_taken")
    for name, value in pairs(previous) do RunConsoleCommand(name, value) end
    for panel in pairs(panels) do if IsValid(panel) then panel:SetVisible(true) end end
    pose(originalPosition, originalAngles)
    print("NL_MESH_END " .. reason)
    timer.Simple(1, function() print("NL_SHOT_DONE") end)
end
local function guard(fn)
    return function(...)
        if not NLRepeatedMeshProbe then return end
        local ok, err = pcall(fn, ...)
        if not ok then print("NL_MESH_ERROR " .. tostring(err)); finish("error") end
    end
end
local function nextScene()
    index = index + 1
    scene = scenes[index]
    if not scene then finish("complete"); return end
    pose(scene.origin, Angle(4, scene.yaw, 0))
    phase, began, window, retries = "warm", SysTime(), 0, 0
    print("NL_MESH_SCENE " .. scene.name .. " " .. os.time() .. " " .. FrameNumber())
end
hook.Add("CreateMove", tag, guard(function(cmd)
    if not scene then return end
    local t = phase == "sample" and SysTime() - began or 0
    cmd:ClearMovement()
    if scene.name == "hall" and phase == "sample" then
        local angle = Angle(4 + 5 * math.sin(t * .52), scene.yaw + 68 * math.sin(t * .54), 0)
        cmd:SetViewAngles(angle)
        local off = LocalPlayer():GetPos().y - scene.origin.y
        local speed = math.Clamp(60 * math.cos(t * .88) + (68 * math.sin(t * .88) - off) * 4, -145, 145)
        cmd:SetForwardMove(angle:Forward().y * speed)
        cmd:SetSideMove(angle:Right().y * speed)
    else
        cmd:SetViewAngles(Angle(4, scene.yaw, 0))
    end
end))
local nextPanelCheck = 0
hook.Add("PostRender", tag, guard(function()
    if not scene or phase == "shot" or FrameNumber() == lastFrame then return end
    lastFrame = FrameNumber()
    local now = SysTime()
    if now >= nextPanelCheck then
        nextPanelCheck = now + 1
        for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
            if IsValid(panel) and panel:IsVisible() and panel.GetTitle and panel.Close then
                panels[panel] = true
                panel:SetVisible(false)
            end
        end
        if gui.IsGameUIVisible() then gui.HideGameUI() end
    end
    if phase == "warm" then
        if now - began < scene.settle then return end
        samples, distance, lastPosition, lastTime = {}, 0, LocalPlayer():GetPos(), now
        previousFocus, focusChanges = system.HasFocus(), 0
        began, phase, window = now, "sample", window + 1
        return
    end
    local pos = LocalPlayer():GetPos()
    local focus = system.HasFocus()
    if focus ~= previousFocus then
        focusChanges = focusChanges + 1
        if retries < 3 then
            retries = retries + 1
            print("NL_MESH_FOCUS_RETRY " .. scene.name .. " " .. window .. " " .. retries)
            if scene.name == "hall" then pose(scene.origin, Angle(4, scene.yaw, 0)) end
            window, phase, began = window - 1, "warm", now - scene.settle + 2
            return
        end
    end
    previousFocus = focus
    samples[#samples + 1] = (now - lastTime) * 1000
    distance, lastPosition, lastTime = distance + pos:Distance(lastPosition), pos, now
    if now - began < 12 then return end
    table.sort(samples)
    print("NL_MESH_SAMPLE " .. util.TableToJSON({scene = scene.name, window = window, frames = #samples,
        seconds = now - began, median = samples[math.ceil(#samples * .5)], p99 = samples[math.ceil(#samples * .99)],
        distance = distance, focus = focus, focus_changes = focusChanges, focus_retries = retries,
        background_cap = GetConVar("fps_max_nofocus") and GetConVar("fps_max_nofocus"):GetString(), wall = os.time(), frame = FrameNumber(),
        pbr = GetConVar("rtx_topbr_enabled"):GetBool(), enhanced = NATIVELOADER_SKY and NATIVELOADER_SKY.enhanced(),
        upscaling = RemixConfig.GetUpscalingState(), size = {ScrW(), ScrH()}}))
    retries = 0
    if window == 1 then
        if scene.name == "hall" then pose(scene.origin, Angle(4, scene.yaw, 0)) end
        began, phase = now - scene.settle + 2, "warm"
    else
        phase = "shot"
        print("NL_SHOT mesh-" .. scene.name)
    end
end))
concommand.Add("nl_shot_taken", guard(function() if phase == "shot" then nextScene() end end))
guard(function()
    temporary("rtx_topbr_enabled", "1")
    temporary("nativeloader_sky", "1")
    temporary("nativeloader_sky_follow_map", "0")
    temporary("nativeloader_sky_enhanced", "1")
    temporary("nativeloader_sky_no_horizon", "1")
    temporary("nativeloader_sky_time_passes", "0")
    temporary("nativeloader_sky_hour", "13")
    nextScene()
end)()
