-- Compare runtime builds on gm_flatgrass with tools/poc_session.py --lua and --lua-shots.
if not game.SinglePlayer() or game.GetMap() ~= "gm_flatgrass" or not RTXDebug or not RTXDebug.Remix then
    print("NL_RENDER_ERROR single-player gm_flatgrass and the Remix developer API are required")
    print("NL_SHOT_DONE")
    return
end
if NLRenderOutputProbe then return end
local probe = {}
NLRenderOutputProbe = probe
local keys, previous, active, cvarsBefore, hidden = {}, {}, {}, {}, {}
local function option(key, value, fallback)
    value = tostring(value)
    if active[key] == value then return end
    if not previous[key] then
        local disk = RemixConfig.GetConfigVariable(key)
        previous[key] = disk and tostring(disk) ~= "" and tostring(disk) or fallback
        keys[#keys + 1] = key
    end
    local ok, err = RTXDebug.Remix.SetConfig(key, value, previous[key])
    if not ok then error(key .. " " .. tostring(err)) end
    active[key] = value
end
local function cv(name, value)
    local c = GetConVar(name)
    if not c then error("Missing " .. name) end
    if cvarsBefore[name] == nil then cvarsBefore[name] = c:GetString() end
    RunConsoleCommand(name, value)
end
local function finish(reason)
    if probe.closed then return end
    probe.closed = true
    NLRenderOutputProbe = nil
    hook.Remove("CalcView", "NLRenderOutputProbe")
    hook.Remove("PostRender", "NLRenderOutputProbe")
    concommand.Remove("nl_shot_taken")
    local restored = true
    for i = #keys, 1, -1 do
        if active[keys[i]] then
            local ok = RTXDebug.Remix.RestoreConfig(keys[i])
            restored = restored and ok == true
        end
    end
    for panel in pairs(hidden) do if IsValid(panel) then panel:SetVisible(true) end end
    for name, value in pairs(cvarsBefore) do RunConsoleCommand(name, value) end
    print("NL_RENDER_END " .. util.TableToJSON({ reason = reason, restored = restored }))
    timer.Simple(1.2, function() print("NL_SHOT_DONE") end)
end
local function guarded(fn)
    return function(...)
        if probe.closed then return end
        local ok, err = pcall(fn, ...)
        if not ok then print("NL_RENDER_ERROR " .. tostring(err)); finish("error") end
    end
end
-- Player spawn points vary between runs. Find the ground at the same XY in each build.
local eye = Vector(0, 0, LocalPlayer():GetPos().z + 512)
local trace = util.TraceLine({start = eye, endpos = eye - Vector(0, 0, 16384), mask = MASK_SOLID_BRUSHONLY})
if not trace.Hit or trace.StartSolid then
    print("NL_RENDER_ERROR fixed floor not found")
    finish("error")
    return
end
local covered = trace.HitPos + Vector(0, 0, 68)
local edge = Vector(12500,0,14000)
local scenes = {
    {"covered", covered, 82, 7, 1, 1, 105},
    {"reveal", edge, 50, 7, 1, 1, 4},
    {"partial", edge, 14, 7, 1, 1, 4},
    {"horizon", edge, 50, 7, 1, 0, 4},
    {"standard", edge, 50, 7, 0, 1, 4},
    {"turn", edge, 50, 7, 1, 1, 5},
}
for bits=0,7 do scenes[#scenes+1] = {"effects"..bits, covered, 8, bits, 1, 1, 2} end
local row, index, since, last, frame, position, pitch
local nextPanelCheck = 0
local samples = {}
local function nextScene()
    index = (index or 0) + 1
    row = scenes[index]
    if not row then finish("complete"); return end
    position, pitch = row[2], row[3]
    cv("nativeloader_sky_enhanced", tostring(row[5]))
    cv("nativeloader_sky_no_horizon", tostring(row[6]))
    local bits = row[4]
    option("rtx.sharpening.sharpness", bit.band(bits,1) ~= 0 and "0.55" or "0", "0")
    option("rtx.postfx.enableMotionBlur", bit.band(bits,2) ~= 0 and "True" or "False", "True")
    option("rtx.postfx.enableVignette", bit.band(bits,4) ~= 0 and "True" or "False", "True")
    samples, since, last, probe.waiting = {}, SysTime(), nil, false
    print("NL_RENDER_START " .. row[1])
end
hook.Add("CalcView", "NLRenderOutputProbe", function(_,_,_,fov)
    if not row then return end
    local turn = row[1] == "turn" and 24 * math.sin((SysTime()-since)*1.4) or 0
    return {origin=position, angles=Angle(pitch+turn,0,0), fov=90, drawviewer=false}
end)
hook.Add("PostRender", "NLRenderOutputProbe", guarded(function()
    if not row or probe.waiting or frame == FrameNumber() then return end
    frame = FrameNumber()
    local now=SysTime()
    if now >= nextPanelCheck then
        nextPanelCheck=now+1
        for _,panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
            if IsValid(panel) and panel:IsVisible() and panel.GetTitle and panel.Close then
                hidden[panel]=true
                panel:SetVisible(false)
            end
        end
        if gui.IsGameUIVisible() then gui.HideGameUI() end
    end
    if now-since < row[7] then return end
    if last then samples[#samples+1] = (now-last)*1000 end
    last=now
    if now-since < row[7]+3 then return end
    table.sort(samples)
    local function q(p) return samples[math.max(1,math.ceil(#samples*p))] or 0 end
    print("NL_RENDER_SAMPLE " .. util.TableToJSON({label=row[1], frames=#samples, median=q(.5), p99=q(.99),
          up=RemixConfig.GetUpscalingState(), bits=row[4], enhanced=row[5], no_horizon=row[6], eye={position.x,position.y,position.z},
          enhanced_live=NATIVELOADER_SKY and NATIVELOADER_SKY.enhanced and NATIVELOADER_SKY.enhanced() or false,
          wall=os.time(), render_frame=FrameNumber()}))
    probe.waiting=true
    print("NL_SHOT "..row[1])
end))
concommand.Add("nl_shot_taken", guarded(function()
    if probe.waiting then nextScene() end
end))
guarded(function()
    cv("nativeloader_sky","1")
    cv("nativeloader_sky_follow_map","0")
    cv("nativeloader_sky_time_passes","0")
    cv("nativeloader_sky_hour","13")
    cv("nativeloader_weather_seconds","0")
    cv("nativeloader_weather","partlyCloudy")
    option("rtx.upscalerType","1","1")
    option("rtx.qualityDLSS","1","1")
    option("rtx.frameGenerationType","1","0")
    option("rtx.postfx.enable","True","True")
    option("rtx.postfx.enableChromaticAberration","False","True")
    option("rtx.postfx.vignetteIntensity","0.6","0.6")
    option("rtx.postfx.exposureFraction","0.4","0.4")
    nextScene()
end)()
