local ID, attached, began, last, seen, captured = "vr_tools_client_probe", false, nil, 0, {}, {}
local native, originalFrame, originalActions, timeNow, aimWidget, aimProp, saved = nil, nil, nil, 0, nil, false, {}
if T_ORIGINAL_MOUSE_YAW ~= nil then saved.m_yaw = T_ORIGINAL_MOUSE_YAW end
local searches = {}
local originalDrawBeam, beamPeers
local serial = 0
local function emit(name, data)
    data = data or {} data.name, data.realm = name, "client"
    local text = util.TableToJSON(data)
    if #text <= 3000 then print("NLVR_T " .. text) return end
    serial = serial + 1
    local encoded = util.Base64Encode(text):gsub("%s", "")
    local total = math.ceil(#encoded / 2800)
    for i = 1, total do print("NLVR_T_CHUNK client " .. serial .. " " .. i .. "/" .. total .. " " .. encoded:sub((i - 1) * 2800 + 1, i * 2800)) end
end
local function once(t, at, key, fn) if t >= at and not seen[key] then seen[key] = true fn() end end
local function capture(label, t)
    local overlays = {}
    for key, object in pairs(NLVR.Overlay.Objects) do
        if object.visible then
            local state, detail = nlvr.OverlayInfo(object.handle)
            overlays[key] = {handle = object.handle, state = state, detail = detail}
        end
    end
    local ok, detail = nlvr.Capture(label, 15)
    local info = nlvr.Info()
    emit("capture", {time = t, label = label, ok = ok, detail = detail, overlays = overlays,
        camera = lastCamera, info = {eyes = info.eyes, centreWidth = info.centreWidth, centreHeight = info.centreHeight}})
end
local function tree(panel, predicate)
    if not IsValid(panel) then return end
    if predicate(panel) then return panel end
    for _, child in ipairs(panel:GetChildren()) do local result = tree(child, predicate) if result then return result end end
end
local function root()
    return tree(vgui.GetWorldPanel(), function(p) return p.NLVRPanel == "spawn" end)
end
local function toolButton(name)
    local menu = IsValid(g_SpawnMenu) and g_SpawnMenu:GetToolMenu()
    if not IsValid(menu) then return end
    local panel, button
    -- Stock GetTools is an array: ToolPanel ids are numeric, not the tab's display name.
    for _, candidate in pairs(menu.ToolPanels or {}) do
        button = tree(candidate, function(p) return p.Name == name and p.Command and p.DoClick end)
        if button then panel = candidate break end
    end
    if not button then return end
    menu:SetActiveTab(panel.PropertySheetTab)
    -- Reveal the stock item; the actual selection is still a laser click on its untouched callback.
    -- The stock Think re-applies SearchBar's value every 1.5 seconds. Set the real
    -- field too, otherwise that pass silently undoes a one-off filter before the click.
    if searches[panel] == nil then searches[panel] = panel.SearchBar:GetText() end
    local query = language.GetPhrase("tool." .. name .. ".name"):lower()
    panel.SearchBar:SetText(query)
    panel:PerformToolFiltering(query)
    panel:InvalidateLayout(true)
    panel.List:ScrollToChild(button)
    return button
end
local function restoreSearches()
    for panel, value in pairs(searches) do
        if IsValid(panel) then panel.SearchBar:SetText(value) panel:PerformToolFiltering(value:Trim():lower()) end
    end
    searches = {}
end
local function widgetState()
    if not IsValid(aimWidget) then return {valid = false} end
    local x, y = aimWidget:LocalToScreen(aimWidget:GetWide() / 2, aimWidget:GetTall() / 2)
    local hovered = vgui.GetHoveredPanel()
    local ancestors, current = {}, aimWidget
    while IsValid(current) do
        local px, py = current:LocalToScreen(0, 0)
        ancestors[#ancestors + 1] = {name = current:GetName(), x = px, y = py, w = current:GetWide(), h = current:GetTall(),
            visible = current:IsVisible(), mouse = current:IsMouseInputEnabled()}
        current = current:GetParent()
    end
    return {valid = true, x = x, y = y, enabled = aimWidget:IsEnabled(), hovered = IsValid(hovered) and hovered:GetName(),
        hovered_target = hovered == aimWidget, ancestors = ancestors, ui = NLVR.Debug.ui}
end
local function point(frame)
    if IsValid(aimWidget) then
        local panel, object = root(), NLVR.Overlay.Objects.spawn
        if IsValid(panel) and object then
            local x, y = aimWidget:LocalToScreen(aimWidget:GetWide() / 2, aimWidget:GetTall() / 2)
            x, y = panel:ScreenToLocal(x, y)
            return object.pos + object.ang:Right() * ((x / panel:GetWide() - 0.5) * object.metres) +
                object.ang:Up() * ((0.5 - y / panel:GetTall()) * object.metres * object.height / object.width)
        end
    elseif aimProp then
        for _, ent in ipairs(ents.FindByClass("prop_physics")) do
            if ent:GetNWBool("nlvr_t_target") then return NLVR.ToTracking(ent:WorldSpaceCenter()) end
        end
    end
end
hook.Add("PreRender", ID, function()
    if NLVR and nlvr then
        local time = nlvr.TestState()
        local t = time and time.time or 0
        if not attached then
            attached, began = true, RealTime()
            native, originalFrame, originalActions = nlvr, nlvr.BeginFrame, nlvr.Actions
            originalDrawBeam, beamPeers = render.DrawBeam, {one = 0, two = 0}
            hook.Add("DrawPhysgunBeam", ID .. "_peer_one", function() beamPeers.one = beamPeers.one + 1 end)
            hook.Add("DrawPhysgunBeam", ID .. "_peer_two", function() beamPeers.two = beamPeers.two + 1 end)
            render.DrawBeam = function(start, endpoint, ...)
                originalDrawBeam(start, endpoint, ...)
                local caller = debug.getinfo(2, "S")
                local active = NLVR and NLVR.Weapon and NLVR.Weapon.Active
                if caller and caller.source:find("cl_tools.lua", 1, true) and active and active.kind == "physgun" and IsValid(active.model) then
                    local id = active.model:LookupAttachment("muzzle")
                    local tip = active.model:GetAttachment(id and id > 0 and id or 1)
                    emit("beam-draw", {frame = NLVR.Frame.sequence, start = start, endpoint = endpoint,
                        model_muzzle = tip and tip.Pos, peers = beamPeers})
                end
            end
            local beam = GetConVar("physgun_drawbeams")
            if beam then saved.physgun_drawbeams = beam:GetString() RunConsoleCommand("physgun_drawbeams", "1") end
            -- Scripted right-hand poses need a deterministic logical hand and gun basis.
            -- The production settings callbacks apply these normally; all raw strings restore.
            for key, value in pairs({nl_vr_dominant = "0", nl_vr_seated = "0", nl_vr_gun_angle = "0"}) do
                local cv = GetConVar(key)
                if cv then saved[key] = cv:GetString() RunConsoleCommand(key, value) end
            end
            if CONFIG.tools_case == "features" then
                for _, key in ipairs({"gmod_toolmode", "colour_r", "colour_g", "colour_b", "colour_a", "colour_mode", "colour_fx"}) do
                    local cv = GetConVar(key) if cv then saved[key] = cv:GetString() end
                end
                native.BeginFrame = function(...)
                    local frame, detail = originalFrame(...)
                    if frame then
                        local state = native.TestState() timeNow = state and state.time or timeNow
                        if timeNow > 26 and not (CONFIG.tools_review and timeNow >= 60) then
                            frame.right.pos, frame.right.ang = Vector(0.3, -0.25, 1.2), Angle()
                            local target = point(frame)
                            if target then frame.right.ang = (target - frame.right.pos):Angle() end
                            local wheel = NLVR.Debug.tools and NLVR.Debug.tools.wheel
                            if timeNow > 52.6 and timeNow < 54 and wheel and wheel.open then
                                local index
                                for i, entry in ipairs(wheel.entries) do if entry.class == "weapon_crowbar" then index = i break end end
                                if index and index <= 12 then
                                    local count = math.min(12, #wheel.entries)
                                    local angle = (index - 1) * math.pi * 2 / count
                                    local p = wheel.origin + (wheel.angle:Right() * math.sin(angle) + wheel.angle:Up() * math.cos(angle)) * NLVR.Space.scale * 0.14
                                    frame.right.pos = NLVR.ToTracking(p)
                                end
                            end
                        end
                    end
                    return frame, detail
                end
                native.Actions = function()
                    local actions = originalActions()
                    if timeNow > 26 and not (CONFIG.tools_review and timeNow >= 60) then
                        local menuClick = timeNow >= 29 and timeNow < 29.2 or timeNow >= 39 and timeNow < 39.2
                        local down = menuClick and IsValid(aimWidget) or timeNow >= 33.2 and timeNow < 33.4 or
                            timeNow >= 43.2 and timeNow < 43.4
                        actions.right_trigger = {active = true, state = down}
                        actions.right_a = {active = true, state = timeNow >= 45 and timeNow < 45.2}
                        actions.right_b = {active = true, state = timeNow >= 47 and timeNow < 47.15 or timeNow >= 52 and timeNow < 54}
                    end
                    return actions
                end
            end
            local entry = NLVR.Registry:Add{name = "tools_probe", order = 98, Stop = function() end, Start = function(ctx)
                ctx.mover(-10000, function(cmd)
                    cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) cmd:SetMouseY(0)
                    if cmd:CommandNumber() ~= 0 then
                        local clock = native.TestState()
                        emit("command-clock", {number = cmd:CommandNumber(), time = clock and clock.time, frame = NLVR.Frame and NLVR.Frame.sequence})
                    end
                end)
                if CONFIG.tools_linear then
                    ctx.mover(940, function(cmd)
                        local state = native.TestState()
                        if state and state.time >= 20 then cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_USE))) end
                    end)
                end
                if CONFIG.tools_case == "engine" then
                    ctx.mover(940, function(cmd)
                        local state = native.TestState() local time = state and state.time or 0
                        if time >= 4 and time < 18 then
                            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_USE))
                            if time < 5 then cmd:SetMouseX(10)
                            elseif time >= 8 and time < 9 then cmd:SetMouseY(10)
                            elseif time >= 12 and time < 13 then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_LEFT))
                            elseif time >= 16 and time < 17 then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_MOVELEFT)) end
                        end
                    end)
                end
                if CONFIG.tools_case == "motion" then
                    ctx.mover(940, function(cmd)
                        local held = ctx.Debug.tools and ctx.Debug.tools.physgun
                        if held and held.entity ~= 0 then
                            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_USE))
                            if ctx.Input.main.stick.y > 0.2 then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_FORWARD))
                            elseif ctx.Input.main.stick.y < -0.2 then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_BACK)) end
                        end
                    end)
                end
            end}
            NLVR.Registry:Call(entry, entry.module.Start, entry.ctx)
            RunConsoleCommand("nlvr_t_setup")
            emit("attached", {test = time, window = {ScrW(), ScrH()}, scale = NLVR.Space.scale, tool_settings_before = saved})
        end
        if RealTime() - last > 0.1 then
            last = RealTime()
            local muzzle = NLVR.Weapon and NLVR.Weapon.Muzzle()
            emit("sample", {time = t, debug = NLVR.Debug.tools, weapon = NLVR.Weapon and NLVR.Weapon.Active and NLVR.Weapon.Active.class,
                frame = NLVR.Frame and NLVR.Frame.sequence, muzzle = muzzle})
        end
        local shots = CONFIG.tools_case == "engine" and {{5.8, "engine-mouse-x"}, {9.8, "engine-mouse-y"}, {13.8, "engine-left"}, {17.8, "engine-moveleft"}} or
            {{5.8, "yaw"}, {8.4, "pitch"}, {10.9, "roll"}, {14.7, "push"}, {17.7, "pull"}, {19.2, "freeze"}, {20.8, "unfreeze"}, {23.4, "wheel"}}
        for _, shot in ipairs(shots) do
            if t > shot[1] and not captured[shot[2]] then
                captured[shot[2]] = true
                capture("tools-" .. shot[2], t)
            end
        end
        once(t, 25.5, "tap", function() emit("tap", {debug = NLVR.Debug.tools}) end)
        if CONFIG.tools_case ~= "features" then
            once(t, 27, "native-restore", function() for key, value in pairs(saved) do RunConsoleCommand(key, value) end end)
            once(t, 28.5, "native-settings-restored", function()
                local after = {} for key in pairs(saved) do after[key] = GetConVar(key):GetString() end
                emit("tool-settings-restored", {before = saved, after = after})
            end)
        end
        if CONFIG.tools_case == "features" then
            once(t, 26, "spawn-remover", function() NLVR.Emit("ui_toggle", "spawn") end)
            once(t, 27.3, "aim-remover", function() aimWidget = toolButton("remover") emit("menu-target", {tool = "remover", found = IsValid(aimWidget)}) end)
            once(t, 28.4, "remover-menu-image", function() emit("menu-aim", widgetState()) capture("tools-menu-remover", t) end)
            once(t, 29.1, "remover-click", function() emit("menu-click", widgetState()) end)
            once(t, 30, "remover-chosen", function()
                emit("menu-selected", {wanted = "remover", actual = LocalPlayer():GetInfo("gmod_toolmode"), debug = NLVR.Debug.ui})
                aimWidget, aimProp = nil, false restoreSearches() NLVR.Emit("ui_toggle", "spawn")
            end)
            once(t, 30.4, "remover-target", function() RunConsoleCommand("nlvr_t_tool_target", "remover") end)
            once(t, 31, "remover-aim", function() aimProp = true end)
            once(t, 34.7, "remover-result", function()
                local found = 0 for _, e in ipairs(ents.FindByClass("prop_physics")) do if e:GetNWBool("nlvr_t_target") then found = found + 1 end end
                emit("remover-result", {remaining = found, debug = NLVR.Debug.tools})
            end)
            once(t, 35, "removed-image", function() capture("tools-removed", t) end)
            once(t, 36, "spawn-colour", function() aimProp = false NLVR.Emit("ui_toggle", "spawn") end)
            once(t, 37.3, "aim-colour", function() aimWidget = toolButton("colour") emit("menu-target", {tool = "colour", found = IsValid(aimWidget)}) end)
            once(t, 38.4, "colour-menu-image", function() emit("menu-aim", widgetState()) capture("tools-menu-colour", t) end)
            once(t, 39.1, "colour-click", function() emit("menu-click", widgetState()) end)
            once(t, 40, "colour-chosen", function()
                emit("menu-selected", {wanted = "colour", actual = LocalPlayer():GetInfo("gmod_toolmode"), debug = NLVR.Debug.ui})
                aimWidget, aimProp = nil, false restoreSearches() NLVR.Emit("ui_toggle", "spawn")
                for key, value in pairs({colour_r = 32, colour_g = 140, colour_b = 220, colour_a = 255, colour_mode = 0, colour_fx = 0}) do RunConsoleCommand(key, tostring(value)) end
            end)
            once(t, 40.4, "colour-target", function() RunConsoleCommand("nlvr_t_tool_target", "colour") end)
            once(t, 41, "colour-aim", function() aimProp = true end)
            once(t, 44.5, "colour-result", function()
                for _, e in ipairs(ents.FindByClass("prop_physics")) do if e:GetNWBool("nlvr_t_target") then emit("colour-result", {colour = e:GetColor(), entity = e:EntIndex(), debug = NLVR.Debug.tools}) end end
            end)
            once(t, 44.6, "coloured-image", function() capture("tools-coloured", t) end)
            once(t, 44.7, "colour-sample-prepare", function()
                for key, value in pairs({colour_r = 7, colour_g = 9, colour_b = 11}) do RunConsoleCommand(key, tostring(value)) end
            end)
            once(t, 46.5, "secondary-result", function()
                emit("secondary-result", {r = GetConVar("colour_r"):GetInt(), g = GetConVar("colour_g"):GetInt(), b = GetConVar("colour_b"):GetInt()})
            end)
            once(t, 48.5, "reload-result", function()
                for _, e in ipairs(ents.FindByClass("prop_physics")) do if e:GetNWBool("nlvr_t_target") then emit("reload-result", {colour = e:GetColor()}) end end
            end)
            once(t, 42.7, "tool-image", function() capture("tools-info", t) end)
            once(t, 49, "buttons", function() emit("tool-buttons", {debug = NLVR.Debug.tools}) end)
            once(t, CONFIG.tools_review and CONFIG.seconds - 3 or 57, "restore", function() for key, value in pairs(saved) do RunConsoleCommand(key, value) end end)
            once(t, CONFIG.tools_review and CONFIG.seconds - 2.3 or 57.7, "tool-settings-restored", function()
                local after = {} for key in pairs(saved) do after[key] = GetConVar(key):GetString() end
                emit("tool-settings-restored", {before = saved, after = after})
            end)
            once(t, 53.3, "wheel-weapon-image", function() capture("tools-wheel-weapon", t) end)
            once(t, 55, "wheel-weapon-result", function() emit("wheel-weapon-result", {class = LocalPlayer():GetActiveWeapon():GetClass(), debug = NLVR.Debug.tools}) end)
        end
    elseif attached then
        restoreSearches()
        for key, value in pairs(saved) do RunConsoleCommand(key, value) end
        if originalFrame then native.BeginFrame, native.Actions = originalFrame, originalActions end
        if originalDrawBeam then render.DrawBeam = originalDrawBeam end
        hook.Remove("DrawPhysgunBeam", ID .. "_peer_one") hook.Remove("DrawPhysgunBeam", ID .. "_peer_two")
        RunConsoleCommand("nlvr_t_done") hook.Remove("PreRender", ID)
        emit("stopped", {global_absent = NLVR == nil})
    end
end)
