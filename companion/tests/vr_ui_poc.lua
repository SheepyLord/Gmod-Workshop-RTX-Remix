-- Adaptive main-hand timeline at the native-to-Lua boundary. The production hit/input path is unchanged.
local ID = "vr_ui_poc"
local seen, active, native, oldFrame, oldActions, target, uv, focusField = {}, false
local t, previous, expected, chosenIcon, beforeProps, propertyTarget = 0, false, "wrist_menu"
local slideUV, savedSettings, scrollPanel, testedSlider
local beforeVGUI, beforeCursor
local fixtureContainer, originalFieldText
local oldSetCursor, oldMoveCursor, oldMousePress, lastCursor, lastMove
local function cursor_state()
    return {input = {input.GetCursorPos()}, gui = {gui.MousePos()}, visible = vgui.CursorVisible(),
        menu = gui.IsGameUIVisible(), system_focus = system.HasFocus(), window = {ScrW(), ScrH()}}
end
local function panel_state(p)
    if not IsValid(p) then return {exists = false} end
    local x, y = p:GetPos()
    return {exists = true, parent = tostring(p:GetParent()), x = x, y = y, width = p:GetWide(), height = p:GetTall(),
        dock = p:GetDock(), visible = p:IsVisible(), mouse = p:IsMouseInputEnabled(), keyboard = p:IsKeyboardInputEnabled()}
end
local function emit(name, data)
    data = data or {} data.kind, data.name, data.time = "ui", name, t
    print("NLVR_Q " .. util.TableToJSON(data))
end
local function once(at, key, fn)
    if t >= at and not seen[key] then seen[key] = true fn() end
end
local function tree(p, fn)
    if not IsValid(p) then return end
    if fn(p) then return p end
    for _, child in ipairs(p:GetChildren()) do local result = tree(child, fn) if result then return result end end
end
local function visible(p)
    while IsValid(p) do if not p:IsVisible() then return false end p = p:GetParent() end
    return true
end
local function root(key)
    local sizes = {wrist_menu = {513, 515}, spawn = {1537, 1025}, context = {1281, 961}, flat = {1921, 1081}, settings = {1283, 963}}
    return tree(vgui.GetWorldPanel(), function(p)
        local size = sizes[key]
        return p.NLVRPanel == key or size and p:GetName() == "EditablePanel" and
            p:GetWide() == size[1] and p:GetTall() == size[2]
    end)
end
local function locate(key, widget)
    local owner = root(key)
    if not IsValid(owner) or not IsValid(widget) then return end
    local x, y = widget:LocalToScreen(widget:GetWide() / 2, widget:GetTall() / 2)
    x, y = owner:ScreenToLocal(x, y)
    return {x / owner:GetWide(), y / owner:GetTall()}
end
local function button(key, word)
    local p = root(key)
    local label = NATIVELOADER_I18N.L(word)
    return tree(p, function(child) return child.GetText and child:GetText() == label end)
end
local function capture(label)
    local ok, detail = native.Capture("ui-" .. label, 15)
    local geometry = {}
    for _, p in ipairs(NLVR.Debug.ui.panels or {}) do
        local widget = root(p.key)
        if IsValid(widget) then geometry[p.key] = {widget:GetWide(), widget:GetTall()} end
    end
    emit("capture-" .. label, {debug = NLVR and NLVR.Debug.ui, capture_ok = ok, capture_error = detail, geometry = geometry})
end
local function select(key, widget)
    target, uv = key, widget and locate(key, widget) or {0.5, 0.5}
    emit("aim", {panel = key, uv = uv, widget = IsValid(widget) and widget:GetName() or nil})
end
local function props()
    local out = {} for _, ent in ipairs(ents.FindByClass("prop_physics")) do out[ent:EntIndex()] = true end return out
end
local function tracking_point(frame)
    if slideUV and target == "settings" and t >= 52.2 then
        uv = {slideUV[1] + math.Clamp((t - 52.2) / 1.5, 0, 1) * 0.12, slideUV[2]}
    end
    if target == "entity" and IsValid(propertyTarget) then return NLVR.ToTracking(propertyTarget:WorldSpaceCenter()) end
    local o = NLVR.Overlay.Objects[target or "wrist_menu"]
    if not o or not uv then return Vector(1, 0, 1.3) end
    local pos, ang = o.pos, o.ang
    if o.device ~= "world" then
        local pose = frame[o.device=="head" and "hmd" or o.device]
        pos, ang = LocalToWorld(pos, ang, pose.pos, pose.ang)
    end
    return pos + ang:Right() * ((uv[1] - 0.5) * o.metres) +
        ang:Up() * ((0.5 - uv[2]) * o.metres * o.height / o.width)
end
local function down(start) return t >= start and t < start + 0.35 end
hook.Add("PreRender", ID, function()
    if not NLVR then
        if active then
            native.BeginFrame, native.Actions = oldFrame, oldActions
            input.SetCursorPos, gui.InternalCursorMoved, gui.InternalMousePressed = oldSetCursor, oldMoveCursor, oldMousePress
            local differences = {}
            for name, panel in pairs({spawn = g_SpawnMenu, context = g_ContextMenu}) do
                local after = panel_state(panel)
                for field, value in pairs(beforeVGUI[name]) do
                    if after[field] ~= value then differences[name .. "." .. field] = {value, after[field]} end
                end
            end
            local roots = 0
            tree(vgui.GetWorldPanel(), function(p) if p.NLVRPanel then roots = roots + 1 end return false end)
            hook.Remove("PreRender", ID)
            emit("off", {vgui_differences = differences, owned_roots = roots,
                cursor_before = beforeCursor, cursor_after = {input.GetCursorPos()}})
        end
        return
    end
    if not active then
        active, native = true, nlvr
        savedSettings = {}
        beforeVGUI = {spawn = panel_state(g_SpawnMenu), context = panel_state(g_ContextMenu)}
        beforeCursor = {input.GetCursorPos()}
        for name in pairs(NLVR.Settings) do savedSettings["nl_vr_" .. name] = GetConVar("nl_vr_" .. name):GetString() end
        oldFrame, oldActions = native.BeginFrame, native.Actions
        oldSetCursor, oldMoveCursor, oldMousePress = input.SetCursorPos, gui.InternalCursorMoved, gui.InternalMousePressed
        input.SetCursorPos = function(x, y)
            oldSetCursor(x, y)
            if t >= 44 and t < 46 then lastCursor = {wanted = {x, y}, after = cursor_state()} end
        end
        gui.InternalCursorMoved = function(x, y)
            oldMoveCursor(x, y)
            if t >= 44 and t < 46 then
                local caller = debug.getinfo(2, "Sl")
                lastMove = {arguments = {x, y}, after = cursor_state(), caller = caller and caller.short_src, line = caller and caller.currentline}
            end
        end
        gui.InternalMousePressed = function(code)
            if t >= 44 and t < 46 then emit("flat-input", {state = cursor_state(), last_set = lastCursor, last_move = lastMove}) end
            return oldMousePress(code)
        end
        native.BeginFrame = function(...)
            local f, detail = oldFrame(...)
            if f then
                local time = native.TestState() t = time and time.time or t
                local point = tracking_point(f)
                f.right.pos = Vector(0.05, -0.25, 1.2)
                f.right.ang = (point - f.right.pos):Angle()
                f.right.valid = true
            end
            return f, detail
        end
        native.Actions = function()
            local a = oldActions()
            a.left_b = {active = true, state = down(2) or down(22) or down(36)}
            a.right_trigger = {active = true, state = down(5) or down(10) or down(14) or down(24) or down(28) or down(32) or down(38) or down(45)}
            if t >= 52 and t < 54 then a.right_trigger.state = true end
            a.right_stick = {active = true, x = 0, y = t >= 57.5 and t < 58.5 and -0.8 or 0}
            return a
        end
        local guiScale = GetConVar("guiscaler_scale_multiplier")
        emit("attached", {keyboard_api = native.ShowKeyboard ~= nil, window_api = native.OverlayWindow ~= nil,
            gui_scale = guiScale and guiScale:GetString()})
    end
    if CONFIG.ui_settings_probe then
        once(2, "settings-only-open", function() NLVR.Emit("ui_toggle", "settings") end)
        once(5, "settings-only-image", function() capture("settings-layout") end)
        once(10, "settings-only-close", function() NLVR.Emit("ui_toggle", "settings") end)
        once(11, "settings-only-restore", function() for name, value in pairs(savedSettings) do RunConsoleCommand(name, value) end end)
        return
    end
    once(3, "wrist-aim", function() select("wrist_menu", button("wrist_menu", "Spawn menu")) end)
    once(4, "wrist", function() capture("wrist") end)
    once(7, "spawn-check", function()
        emit("spawn-open", {open = root("spawn") ~= nil, debug = NLVR.Debug.ui})
        if not root("spawn") then NLVR.Emit("ui_toggle", "spawn") end
    end)
    once(7.4, "content-fixture", function()
        chosenIcon = tree(root("spawn"), function(p)
            return visible(p) and (p:GetName() == "SpawnIcon" or
                p:GetName() == "ContentIcon" and p.GetContentType and p:GetContentType() == "model")
        end)
        if not IsValid(chosenIcon) then
            -- The rollback fixture deliberately has no saved spawnlists. Use the stock factory,
            -- inside the real spawn menu, so its ordinary DoClick/network action remains the subject.
            local creation = g_SpawnMenu:GetCreationMenu()
            local holder = creation:GetActiveTab():GetPanel()
            fixtureContainer = vgui.Create("ContentContainer", holder)
            fixtureContainer.gScF = true
            fixtureContainer:SetPos(200, 36)
            fixtureContainer:SetSize(math.max(100, holder:GetWide() - 200), math.max(100, holder:GetTall() - 36))
            fixtureContainer:SetVisible(true) fixtureContainer:SetZPos(32767)
            chosenIcon = spawnmenu.CreateContentIcon("model", fixtureContainer,
                {model = "models/props_c17/oildrum001.mdl", nicename = "VR fixture barrel"})
            if not IsValid(chosenIcon) then chosenIcon = tree(fixtureContainer, function(p)
                return p:GetName() == "SpawnIcon" or p:GetName() == "ContentIcon"
            end) end
            emit("stock-icon-fixture", {created = IsValid(chosenIcon)})
        end
    end)
    once(8, "spawn", function()
        capture("spawn")
        local list = {}
        tree(root("spawn"), function(p)
            if #list < 20 then list[#list + 1] = {name = p:GetName(), class = p:GetClassName(), visible = p:IsVisible(),
                width = p:GetWide(), height = p:GetTall(), children = #p:GetChildren()} end
            return false
        end)
        emit("spawn-tree", {tree = list})
    end)
    once(9, "prop-aim", function()
        beforeProps = props() select("spawn", chosenIcon)
        local model
        if IsValid(chosenIcon) then model = chosenIcon.GetSpawnName and chosenIcon:GetSpawnName() or chosenIcon:GetModelName() end
        emit("icon", {model = model})
    end)
    once(12, "spawned", function()
        local new = {} for index in pairs(props()) do if not beforeProps[index] then new[#new + 1] = index end end
        emit("spawn-result", {new_entities = new, debug = NLVR.Debug.ui})
    end)
    once(13, "text-aim", function()
        focusField = tree(root("spawn"), function(p) return p:GetClassName() == "TextEntry" and visible(p) end)
        originalFieldText = IsValid(focusField) and focusField:GetText()
        select("spawn", focusField)
    end)
    once(20, "text-result", function()
        emit("keyboard-result", {text = IsValid(focusField) and focusField:GetText(), debug = NLVR.Debug.ui})
        capture("search")
    end)
    once(23, "context-aim", function() select("wrist_menu", button("wrist_menu", "Context menu")) end)
    once(26, "context", function() capture("context") end)
    once(27, "entity-aim", function()
        for _, ent in ipairs(ents.FindByClass("prop_physics")) do if ent:GetNWBool("nlvr_ui_target") then propertyTarget = ent break end end
        target, uv = "entity", nil
        emit("entity-aim", {entity = IsValid(propertyTarget) and propertyTarget:EntIndex(), head = NLVR.Pose.head.pos})
    end)
    once(30.7, "property", function()
        capture("properties")
        local menu = tree(root("context"), function(p) return p:GetName() == "DMenu" end)
        local option = tree(menu, function(p)
            if not p.GetText then return false end
            local word = p:GetText():lower() return word == "#remove" or word == "remove"
        end)
        select("context", option)
        emit("property-menu", {menu = menu ~= nil, remove_option = option ~= nil})
    end)
    once(34, "property-result", function() emit("property-result", {removed = not IsValid(propertyTarget), debug = NLVR.Debug.ui}) end)
    once(37, "flat-aim", function() select("wrist_menu", button("wrist_menu", "Flat screen")) end)
    once(40, "escape", function()
        if NLVR.Debug.ui.window_source == "ready" and not gui.IsGameUIVisible() then gui.ActivateGameUI() end
    end)
    once(43, "flat", function()
        capture("flat") select("flat")
        -- GMod's HTML sidebar uses a fixed left margin. The reference 720p/4K captures
        -- place Resume at y=228/250 respectively; UV still maps through the actual window.
        uv = {140 / ScrW(), (ScrH() >= 1440 and 250 or 228) / ScrH()}
        emit("flat-state", {visible = gui.IsGameUIVisible(), debug = NLVR.Debug.ui})
    end)
    once(47, "resume", function()
        emit("resume-result", {resumed = not gui.IsGameUIVisible(), debug = NLVR.Debug.ui})
        gui.HideGameUI() NLVR.Emit("ui_toggle", "settings")
    end)
    once(50, "settings", function() capture("settings") end)
    once(51, "slider-aim", function()
        local number = tree(root("settings"), function(p)
            return p:GetName()=="DNumSlider" and p.GetMin and p:GetMin()==15 and p:GetMax()==90
        end)
        local slider=IsValid(number) and number.Slider
        testedSlider=slider
        select("settings", IsValid(slider) and slider.Knob)
        if uv then slideUV = {uv[1], uv[2]} end
        emit("slider-start", {uv = uv, snap_angle = GetConVar("nl_vr_snap_angle"):GetFloat()})
    end)
    once(53, "slider-during",function()
        emit("slider-during",{dragging=IsValid(testedSlider) and testedSlider:GetDragging(),
            value=GetConVar("nl_vr_snap_angle"):GetFloat(),uv=uv})
    end)
    once(55, "slider-result", function()
        local changes = {}
        for name, value in pairs(savedSettings) do
            local after = GetConVar(name):GetString()
            if value ~= after then changes[name] = {value, after} end
        end
        emit("slider-result", {changes = changes, debug = NLVR.Debug.ui})
        slideUV = nil
    end)
    once(57, "scroll-aim", function()
        select("settings") uv = {0.6, 0.8}
        scrollPanel = tree(root("settings"), function(p) return p:GetName() == "DScrollPanel" end)
        emit("scroll-start", {scroll = IsValid(scrollPanel) and scrollPanel:GetVBar():GetScroll()})
    end)
    once(59, "scroll-result", function()
        emit("scroll-result", {scroll = IsValid(scrollPanel) and scrollPanel:GetVBar():GetScroll(), debug = NLVR.Debug.ui})
    end)
    once(61, "closed", function()
        NLVR.Emit("ui_toggle", "settings") target = nil
    end)
    once(62, "closed-result", function()
        emit("closed", {debug = NLVR.Debug.ui})
        if IsValid(fixtureContainer) then fixtureContainer:Remove() end
        if IsValid(focusField) and originalFieldText then
            focusField:SetText(originalFieldText)
            if focusField.OnTextChanged then focusField:OnTextChanged() end
        end
        -- Restore after controls are removed: a live slider can reformat its cvar on its next Think.
        for name, value in pairs(savedSettings) do RunConsoleCommand(name, value) end
    end)
end)
