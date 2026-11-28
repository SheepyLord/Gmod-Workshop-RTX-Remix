-- Regression for live repeated-mesh placement, visibility, manual routing and retirement.
if not game.SinglePlayer() or game.GetMap() ~= "gm_flatgrass" or not RTXDebug or not RTXDebug.Remix then
    print("NL_MESH_LIFE_ERROR single-player gm_flatgrass and the Remix developer API are required")
    print("NL_SHOT_DONE")
    return
end
if NLRepeatedMeshLife then return end
NLRepeatedMeshLife = true
local tag = "NLRepeatedMeshLife"
local phases = {"many", "few", "return", "force-merge", "automatic", "removed"}
local models, origins, hiddenPanels, previous = {}, {}, {}, {}
local index, since, waiting, settled, forced = 0, 0, false, false, false
local selected, triangles, floorPosition
local key = "rtx.forceMergeAllMeshes"
local function temporary(name, value)
    local cvar = assert(GetConVar(name), name)
    previous[name] = cvar:GetString()
    RunConsoleCommand(name, value)
end
local function restoreForce()
    if forced then
        assert(RTXDebug.Remix.RestoreConfig(key))
        forced = false
    end
end
local function finish(reason)
    if not NLRepeatedMeshLife then return end
    NLRepeatedMeshLife = nil
    hook.Remove("CalcView", tag)
    hook.Remove("PreRender", tag)
    hook.Remove("PostRender", tag)
    concommand.Remove("nl_shot_taken")
    for _, model in ipairs(models) do if IsValid(model) then model:Remove() end end
    for panel in pairs(hiddenPanels) do if IsValid(panel) then panel:SetVisible(true) end end
    for name, value in pairs(previous) do RunConsoleCommand(name, value) end
    local restored = pcall(restoreForce)
    print("NL_MESH_LIFE_END " .. reason .. " restored=" .. tostring(restored))
    timer.Simple(1, function() print("NL_SHOT_DONE") end)
end
local function guard(fn)
    return function(...)
        if not NLRepeatedMeshLife then return end
        local ok, err = pcall(fn, ...)
        if not ok then print("NL_MESH_LIFE_ERROR " .. tostring(err)); finish("error") end
    end
end
local function nextPhase()
    index = index + 1
    local phase = phases[index]
    if not phase then finish("complete"); return end
    restoreForce()
    if phase == "force-merge" then
        local original = RemixConfig.GetConfigVariable(key)
        assert(RTXDebug.Remix.SetConfig(key, "True", original and tostring(original) ~= "" and tostring(original) or "False"))
        forced = true
    end
    for i, model in ipairs(models) do
        if phase == "removed" then model:Remove()
        else model:SetNoDraw(phase == "few" and i > 3) end
    end
    since, waiting, settled = SysTime(), false, false
end
guard(function()
    temporary("nativeloader_sky", "1")
    temporary("nativeloader_sky_follow_map", "0")
    temporary("nativeloader_sky_time_passes", "0")
    temporary("nativeloader_sky_hour", "13")
    temporary("nativeloader_weather_seconds", "0")
    temporary("nativeloader_weather", "partlyCloudy")
    local start = Vector(0, 0, LocalPlayer():GetPos().z + 512)
    local trace = util.TraceLine({start = start, endpos = start - Vector(0, 0, 16384), mask = MASK_SOLID_BRUSHONLY})
    assert(trace.Hit and not trace.StartSolid, "fixed floor missing")
    floorPosition = trace.HitPos
    for _, path in ipairs({"models/props_c17/oildrum001.mdl", "models/props_junk/wood_crate001a.mdl", "models/props_c17/FurnitureChair001a.mdl"}) do
        for _, meshData in ipairs(util.GetModelMeshes(path, 0, 0) or {}) do
            local count = #(meshData.triangles or {}) / 3
            if count >= 100 and count < 1000 then selected, triangles = path, count; break end
        end
        if selected then break end
    end
    assert(selected, "no small stock prop mesh")
    for i = 1, 88 do
        local model = ClientsideModel(selected, RENDERGROUP_OPAQUE)
        assert(IsValid(model), "could not create test prop")
        models[i] = model
        origins[i] = floorPosition + Vector(100 + math.floor((i - 1) / 11) * 50, ((i - 1) % 11 - 5) * 43, 2)
        model:SetPos(origins[i])
        model:SetColor(i % 2 == 0 and Color(255, 190, 140) or Color(175, 220, 255))
    end
    print("NL_MESH_LIFE_MODEL " .. selected .. " " .. triangles)
    nextPhase()
end)()
if not NLRepeatedMeshLife then return end
hook.Add("CalcView", tag, function()
    return {origin = floorPosition + Vector(-230, 0, 155), angles = Angle(13, 0, 0), fov = 80, drawviewer = false}
end)
hook.Add("PreRender", tag, guard(function()
    if waiting or settled or phases[index] == "removed" then return end
    local t = SysTime() - since
    local moving = t < 4
    for i, model in ipairs(models) do
        if IsValid(model) and not model:GetNoDraw() then
            model:SetPos(origins[i] + Vector(0, moving and 5 * math.sin(t * 4 + i) or 0, 0))
            model:SetAngles(Angle(0, (i % 8) * 15 + (moving and 18 * math.sin(t * 3 + i) or 0), 0))
        end
    end
    settled = not moving
end))
local nextPanelCheck = 0
hook.Add("PostRender", tag, guard(function()
    local now = SysTime()
    if now >= nextPanelCheck then
        nextPanelCheck = now + 1
        for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
            if IsValid(panel) and panel:IsVisible() and panel.GetTitle and panel.Close then
                hiddenPanels[panel] = true
                panel:SetVisible(false)
            end
        end
        if gui.IsGameUIVisible() then gui.HideGameUI() end
    end
    if waiting or now - since < 8 then return end
    local visible = 0
    for _, model in ipairs(models) do
        if IsValid(model) and not model:GetNoDraw() then visible = visible + 1 end
    end
    print("NL_MESH_LIFE_SAMPLE " .. util.TableToJSON({phase = phases[index], visible = visible, forced = forced, wall = os.time()}))
    waiting = true
    print("NL_SHOT mesh-life-" .. phases[index])
end))
concommand.Add("nl_shot_taken", guard(function() if waiting then nextPhase() end end))
