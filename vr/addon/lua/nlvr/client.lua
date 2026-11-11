-- V1 client session. Included only after OpenVR is ready; supplies the first traced VR camera.
local Session = {}
local ID = "nativeloader_vr_view"
local native, onError, running, frame, lastHead, yaw, units
local hooks, overlay = {}, nil
local viewRegistry, priorViews, deferredViews, ownedViews
local cameraSequence, cameraView, renderFrame
local failures, lastError, recenterRequested, anchor = 0, nil, false, Vector(0, 0, 0)
local cameraFailures, cameraError, cameraAttemptFrame = 0, nil, nil
local proxies, pendingEntities = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
local target, previousHUD
local overlayCopied, hudFailures, hudError = false, 0, nil
local WIDTH, HEIGHT = 769, 257 -- exact non-power-of-two dimensions reserved for the wrist overlay
local function checked(name, ...)
    local ok, detail = native[name](...)
    if ok == false or (ok == nil and detail ~= nil) then error(name .. ": " .. tostring(detail)) end
    return ok
end
local function add(event, fn)
    hooks[#hooks + 1] = event
    hook.Add(event, ID, fn)
end
local function guard(fn)
    return function(...)
        local ok, result = pcall(fn, ...)
        if not ok then onError(tostring(result)) return end
        return result
    end
end
local function own_view(fn)
    -- hook.Call dispatches an event's raw entries in undefined order. Own just CalcView while VR
    -- runs, withholding other views and preserving late Add/Remove calls in their original table.
    -- Global hook functions (including the guard/lag report's dispatch) remain untouched.
    viewRegistry = hook.GetTable()
    priorViews = viewRegistry.CalcView
    deferredViews = priorViews or {}
    assert(type(deferredViews) == "table", "Unsupported CalcView hook registry")
    local held = deferredViews
    ownedViews = setmetatable({}, {__index = held,
        __newindex = function(_, id, callback) held[id] = callback end})
    rawset(ownedViews, ID, false)
    viewRegistry.CalcView = ownedViews
    add("CalcView", guard(fn))
end
local function paused_proxy_think(entity)
    -- Keep its next think scheduled so restoring the original method resumes it immediately.
    entity:NextThink(CurTime())
    return true
end
local function hide_render_entity(entity, root)
    if not IsValid(entity) then return end
    local entry = proxies[entity]
    if not entry then entry = {noDraw = entity:GetNoDraw()} proxies[entity] = entry end
    if root and not entry.root then
        entry.root, entry.think = true, rawget(entity:GetTable(), "Think")
        entity.Think = paused_proxy_think
    end
    if not entity:GetNoDraw() then entity:SetNoDraw(true) end
    for _, child in ipairs(entity:GetChildren()) do hide_render_entity(child, false) end
end
local function hide_proxy(entity)
    if not IsValid(entity) then return end
    local class = entity:GetClass()
    if class ~= "rtx_pseudoplayer" and class ~= "rtx_pseudoweapon" then return end
    -- In particular the weapon proxy's Think draws the real weapon and re-shows a separate
    -- child model. Hiding only the scripted parent does not suppress those 3D draws.
    hide_render_entity(entity, true)
end
local function hide_proxies()
    -- Do not toggle rtx_pseudoplayer: its restoration callback also changes a Remix shadow option.
    -- Suppress the fixes' render proxies themselves, preserving both convars and runtime settings.
    if ents and ents.FindByClass then
        for _, class in ipairs({"rtx_pseudoplayer", "rtx_pseudoweapon"}) do
            for _, entity in ipairs(ents.FindByClass(class)) do hide_proxy(entity) end
        end
    end
    add("OnEntityCreated", function(entity) pendingEntities[entity] = true end)
end
function Session.Stop()
    running, frame, lastHead, yaw = false, nil, nil, nil
    cameraSequence, cameraView, renderFrame = nil, nil, nil
    cameraAttemptFrame = nil
    for _, event in ipairs(hooks) do hook.Remove(event, ID) end
    hooks = {}
    if viewRegistry and viewRegistry.CalcView == ownedViews then
        viewRegistry.CalcView = (priorViews or next(deferredViews)) and deferredViews or nil
    end
    viewRegistry, priorViews, deferredViews, ownedViews = nil, nil, nil, nil
    for entity, entry in pairs(proxies) do
        if IsValid(entity) then
            if entry.root and rawget(entity:GetTable(), "Think") == paused_proxy_think then entity.Think = entry.think end
            pcall(entity.SetNoDraw, entity, entry.noDraw)
        end
    end
    proxies, pendingEntities = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    if overlay and native then
        pcall(native.OverlayShow, overlay, false)
        pcall(native.OverlayDestroy, overlay)
    end
    overlay, previousHUD = nil, nil
    overlayCopied, hudFailures, hudError = false, 0, nil
end
local function hud_values()
    local player = LocalPlayer()
    if not IsValid(player) then return end
    local weapon = player:GetActiveWeapon()
    local clip, reserve = -1, -1
    if IsValid(weapon) then
        clip = weapon:Clip1()
        local ammo = weapon:GetPrimaryAmmoType()
        if ammo >= 0 then reserve = player:GetAmmoCount(ammo) end
    end
    return {player:Health(), player:Armor(), clip, reserve}
end
local function paint_hud()
    local values = hud_values()
    if not values then return end
    if not overlayCopied then
        local info, detail = native.Info()
        if detail then
            local message = tostring(detail)
            if message ~= hudError then MsgN("[nativeloader] VR wrist: " .. message) hudError = message end
            hudFailures = hudFailures + 1
            if hudFailures >= 30 then onError(message) return end
        else hudFailures, hudError = 0, nil end
        overlayCopied = info and (tonumber(info.overlayUpdates) or 0) > 0 or false
    end
    if previousHUD and overlayCopied then
        local changed = false
        for i = 1, 4 do if values[i] ~= previousHUD[i] then changed = true break end end
        if not changed then return end
    end
    render.PushRenderTarget(target)
    local in2D = false
    local ok, err = pcall(function()
        render.Clear(12, 18, 26, 235, false, false)
        cam.Start2D() in2D = true
        local i18n = NATIVELOADER_I18N
        local function word(text) return i18n and i18n.L(text) or text end
        -- The companion owns/marks these phrases so its catalog builder sees the wrist labels.
        local labels = NativeLoaderVR.WristLabels
        local ammo = values[3] >= 0 and tostring(values[3]) or "-"
        if values[4] >= 0 then ammo = ammo .. " / " .. values[4] end
        for i, value in ipairs({tostring(values[1]), tostring(values[2]), ammo}) do
            local x = (i - 0.5) * WIDTH / 3
            draw.SimpleText(word(labels[i]), "NLVRWristLabel", x, 34, Color(164, 213, 229), TEXT_ALIGN_CENTER)
            draw.SimpleText(value, "NLVRWristValue", x, 105, color_white, TEXT_ALIGN_CENTER)
        end
    end)
    if in2D then cam.End2D() end
    render.PopRenderTarget()
    if not ok then error(err) end
    previousHUD = values
end
local function begin_frame()
    local number = FrameNumber()
    if number == renderFrame then return end
    renderFrame = number
    local nextFrame, detail = native.BeginFrame()
    if detail then
        local message = tostring(detail)
        if message ~= lastError then MsgN("[nativeloader] VR frame: " .. message) lastError = message end
        failures = failures + 1
        if failures >= 30 then onError(message) return end
    else failures, lastError = 0, nil end
    -- A bounded completion timeout/no-scene interval holds the last camera, without pushing it twice.
    frame = nextFrame or frame
    if frame and frame.hmd and frame.hmd.valid then lastHead = frame.hmd end
end
function Session.Recenter() recenterRequested = true end
function Session.Start(api, errorHandler, worldUnitsPerMetre)
    native, onError, running = api, errorHandler, true
    failures, lastError, recenterRequested, anchor = 0, nil, false, Vector(0, 0, 0)
    cameraFailures, cameraError, cameraAttemptFrame = 0, nil, nil
    overlayCopied, hudFailures, hudError = false, 0, nil
    assert(type(worldUnitsPerMetre) == "number" and worldUnitsPerMetre >= 10 and worldUnitsPerMetre <= 100,
        "Invalid session world scale")
    units = worldUnitsPerMetre
    -- The compositor uses the path-traced centre before the desktop's 2D passes. Leave 2D, VGUI
    -- and engine convars alone (fps_max is Lua-blocked); suppress only traced 3D representations.
    add("PreDrawViewModel", function() return true end)
    add("PreDrawPlayerHands", function() return true end)
    add("ShouldDrawLocalPlayer", function() return false end)
    hide_proxies() -- V1 has no local body or hand weapon; V5 supplies the shadow/reflection body
    target = GetRenderTargetEx("nlvr_wrist_v1_769x257", WIDTH, HEIGHT, RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)
    if not target or target:Width() ~= WIDTH or target:Height() ~= HEIGHT then
        error("The render guard or engine refused the 769 x 257 wrist target")
    end
    surface.CreateFont("NLVRWristLabel", {font = "Tahoma", size = 33, weight = 600, extended = true})
    surface.CreateFont("NLVRWristValue", {font = "Tahoma", size = 63, weight = 700, extended = true})
    local overlayError
    overlay, overlayError = native.OverlayCreate("nativeloader.wrist.v1", "RTX VR wrist HUD")
    if not overlay then error(overlayError or "SteamVR could not create the wrist HUD overlay") end
    checked("OverlaySource", overlay, WIDTH, HEIGHT)
    checked("OverlayAttach", overlay, "left", Vector(0, 0, 0.065), Angle(0, 0, 90), 0.23)
    checked("OverlayShow", overlay, true)
    add("PreRender", guard(function()
        assert(hook.GetTable() == viewRegistry and viewRegistry.CalcView == ownedViews,
            "The hook library or CalcView registry changed during VR")
        for entity in pairs(pendingEntities) do hide_proxy(entity) pendingEntities[entity] = nil end
        for entity, entry in pairs(proxies) do
            if IsValid(entity) then
                if entry.root then hide_render_entity(entity, true)
                elseif not entity:GetNoDraw() then entity:SetNoDraw(true) end
            end
        end
        begin_frame()
    end))
    own_view(function(player, origin, angles, fov, near, far)
        if not running or not IsValid(player) then return end
        -- GMod calls the main CalcView before PreRender. Sample here on that path; PreRender and
        -- any additional view queries reuse the same engine frame instead of waiting twice.
        begin_frame()
        if not frame or not lastHead then return end
        if cameraSequence == frame.sequence then return cameraView end
        if cameraAttemptFrame == renderFrame then return cameraView end
        cameraAttemptFrame = renderFrame
        if recenterRequested then
            anchor = Vector(lastHead.pos.x, lastHead.pos.y, 0)
            yaw, recenterRequested = angles.y - lastHead.ang.y, false
        end
        if not yaw then yaw = angles.y - lastHead.ang.y end
        -- CalcView's origin includes engine prediction/interpolation and its current duck/step
        -- offset. Remove that actual view offset to anchor the tracking floor to this same view.
        local feet = origin - player:GetCurrentViewOffset()
        local position, rotation = LocalToWorld((lastHead.pos - anchor) * units, lastHead.ang, feet, Angle(0, yaw, 0))
        local culling = GetConVar("nl_vr_fov"):GetFloat()
        if culling ~= culling then culling = 145 end
        local nextView = {origin = position, angles = rotation, fov = math.Clamp(culling, 100, 170),
            znear = near, zfar = far, drawviewer = false}
        local pushed, detail = native.SetFrameCamera(frame.sequence, position, rotation)
        if pushed == false or (pushed == nil and detail ~= nil) then
            local message = tostring(detail or "SetFrameCamera failed")
            if message ~= cameraError then MsgN("[nativeloader] VR camera: " .. message) cameraError = message end
            cameraFailures = cameraFailures + 1
            if cameraFailures >= 30 then onError(message) end
            return cameraView
        end
        cameraFailures, cameraError = 0, nil
        cameraSequence, cameraView = frame.sequence, nextView
        return cameraView
    end)
    add("PostRender", guard(paint_hud))
    return true
end
return Session
