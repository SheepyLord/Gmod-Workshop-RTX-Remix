-- Test only: real field/window callbacks, driven by laser geometry and native-boundary actions.
local id, seen, native, core = "vr_ui_followup", {}, nil, nil
local oldFrame, oldActions, oldInput, oldShow, oldHide, t = nil, nil, nil, nil, nil, 0
local target, uv, field, oldText, beforeResume, searchBefore = nil, nil, nil, nil, nil, nil
local function emit(name, values)
    values = values or {} values.kind, values.name, values.time = "ui", name, t
    print("NLVR_Q " .. util.TableToJSON(values))
end
local function once(at, name, fn) if t >= at and not seen[name] then seen[name] = true fn() end end
local function tree(panel, fn)
    if not IsValid(panel) then return end
    if fn(panel) then return panel end
    for _, child in ipairs(panel:GetChildren()) do local result = tree(child, fn) if result then return result end end
end
local function visible(panel)
    while IsValid(panel) do if not panel:IsVisible() then return false end panel = panel:GetParent() end return true
end
local function root(key) return tree(vgui.GetWorldPanel(), function(p) return p.NLVRPanel == key end) end
local function locate(key, widget)
    local owner = root(key)
    if not IsValid(owner) or not IsValid(widget) then return {0.5, 0.5} end
    local x, y = widget:LocalToScreen(widget:GetWide() / 2, widget:GetTall() / 2)
    x, y = owner:ScreenToLocal(x, y)
    return {x / owner:GetWide(), y / owner:GetTall()}
end
local function capture(label)
    local overlays = {}
    for _, panel in ipairs(NLVR.Debug.ui.panels or {}) do
        local state, detail = native.OverlayInfo(panel.handle)
        overlays[panel.key] = state or {error = detail}
    end
    local ok, detail = native.Capture("followup-" .. label, 15)
    emit("followup-capture", {label = label, ok = ok, detail = detail, debug = NLVR.Debug.ui, overlays = overlays})
end
local strokes = {}
local function type_at(start, text)
    for i = 1, #text do strokes[#strokes + 1] = {at = start + (i - 1) * 0.6, key = text:sub(i, i) == " " and "Space" or text:sub(i, i)} end
    local finish = start + #text * 0.6
    strokes[#strokes + 1] = {at = finish, key = "Enter"}
    return finish
end
type_at(6, "barrel")
local consoleEnter = type_at(23, "echo nlvrmconsoleok")
strokes[#strokes + 1] = {at = consoleEnter + 1.5, key = "Close"}
local function key_uv(label)
    local o = NLVR.Overlay.Objects.keyboard
    if not o then return end
    local layout = include("nlvr/modules/cl_ui_keyboard.lua").Layout(o.width, o.height)
    for _, k in ipairs(layout) do if k.value == label then return {(k.x + k.w / 2) / o.width, (k.y + k.h / 2) / o.height} end end
end
local function pulse(at) return t >= at and t < at + 0.25 end
local function search_state()
    local parent = IsValid(field) and field:GetParent()
    return {text = IsValid(field) and field:GetText(), current = IsValid(parent) and parent.CurrentSearch,
        results = IsValid(parent) and parent.OldResults,
        result_children = IsValid(g_SpawnMenu.SearchPropPanel) and #g_SpawnMenu.SearchPropPanel:GetChildren()}
end
hook.Add("PreRender", id, function()
    if not NLVR then
        if native then
            native.BeginFrame, native.Actions, native.WindowInput, native.ShowKeyboard = oldFrame, oldActions, oldInput, oldShow
            if IsValid(field) and oldText then field:SetText(oldText) end
            hook.Remove("PreRender", id)
            local overlays = 0 for _ in pairs(core.Overlay.Objects) do overlays = overlays + 1 end
            emit("followup-off", {keyboard_overlay = core.Overlay.Objects.keyboard ~= nil, overlay_objects = overlays})
        end
        return
    end
    if not native then
        core = NLVR
        assert(NLVR.Overlay.Sizes.keyboard and NLVR.Overlay.Sizes.settings and NLVR.Overlay.Sizes.flat_close,
            "S's reviewed central reservations must be merged for final acceptance")
        native = nlvr oldFrame, oldActions, oldInput, oldShow, oldHide = native.BeginFrame, native.Actions, native.WindowInput, native.ShowKeyboard, native.HideKeyboard
        native.ShowKeyboard = function(...)
            local ok, detail = oldShow(...)
            emit("followup-steam-keyboard", {ok = ok, detail = detail, forced_fallback = CONFIG.ui_force_keyboard_fallback})
            if CONFIG.ui_force_keyboard_fallback then if ok then oldHide() end return nil, "Simulated ShowKeyboard failure for fallback acceptance" end
            return ok, detail
        end
        native.WindowInput = function(kind, ...)
            if kind == "button" and t >= 15 and t <= 18 then
                local button, down = ...
                if down then beforeResume = gui.IsGameUIVisible() end
                emit("followup-resume-press", {down = down, button = button, menu_before_press = beforeResume, info = native.Info().window_input})
            elseif kind == "char" or kind == "key" then emit("followup-window-text", {operation = kind, arguments = {...}}) end
            return oldInput(kind, ...)
        end
        native.BeginFrame = function(...)
            local frame, detail = oldFrame(...)
            if frame then
                local clock = native.TestState() t = clock and clock.time or t
                for _, stroke in ipairs(strokes) do
                    if t >= stroke.at - 0.2 and t < stroke.at + 0.4 then target, uv = "keyboard", key_uv(stroke.key) break end
                end
                local o = NLVR.Overlay.Objects[target or ""]
                if o and uv then
                    local point = o.pos + o.ang:Right() * ((uv[1] - 0.5) * o.metres) + o.ang:Up() * ((0.5 - uv[2]) * o.metres * o.height / o.width)
                    frame.right.pos = Vector(0.05, -0.25, 1.2) frame.right.ang = (point - frame.right.pos):Angle() frame.right.valid = true
                end
            end
            return frame, detail
        end
        native.Actions = function()
            local actions = oldActions()
            local down = pulse(4) or pulse(16) or pulse(20)
            for _, stroke in ipairs(strokes) do down = down or pulse(stroke.at) end
            actions.right_trigger = {active = true, state = down} return actions
        end
        emit("followup-attached", {window_api = native.WindowInput ~= nil, simulated = native.Info().simulated, size_contract_fixture = false})
    end
    once(2, "spawn", function() NLVR.Emit("ui_toggle", "spawn") end)
    once(3, "field", function()
        field = tree(root("spawn"), function(p)
            local parent = p:GetParent()
            return p:GetClassName() == "TextEntry" and visible(p) and IsValid(parent) and parent.Search == p and parent.RefreshResults ~= nil
        end)
        oldText = IsValid(field) and field:GetText()
        target, uv = "spawn", locate("spawn", field) searchBefore = search_state()
        emit("followup-search-before", searchBefore)
    end)
    once(5.3, "keyboard-search", function() capture("keyboard-search") end)
    once(8.9, "typed-search", function() capture("typed-search") end)
    once(12, "search-result", function()
        emit("followup-search-result", {before = searchBefore, after = search_state(), debug = NLVR.Debug.ui}) capture("search-results")
    end)
    once(13, "flat", function() NLVR.Emit("ui_toggle", "flat") target = nil end)
    once(14, "escape", function() print("NLVR_UI_PREPARE " .. CONFIG.ui_run_token .. " hideconsole") if not gui.IsGameUIVisible() then gui.ActivateGameUI() end end)
    once(15, "resume-target", function()
        target, uv = "flat", {140 / ScrW(), (ScrH() >= 1440 and 249 or 228) / ScrH()} capture("resume-before")
    end)
    once(17.5, "resume-result", function()
        emit("followup-resume-result", {menu_before_press = beforeResume, resumed = beforeResume == true and not gui.IsGameUIVisible(), info = native.Info().window_input})
        capture("resume-after")
    end)
    once(18.5, "console", function() print("NLVR_UI_PREPARE " .. CONFIG.ui_run_token .. " showconsole") end)
    once(19, "console-keyboard-target", function() target, uv = "flat_close", {0.5, 0.75} end)
    once(21.3, "keyboard-console", function() capture("keyboard-console") emit("followup-console-open", {visible = gui.IsConsoleVisible()}) end)
    once(consoleEnter + 0.8, "console-result", function()
        capture("console-result") emit("followup-console-result", {info = native.Info().window_input, debug = NLVR.Debug.ui})
    end)
    once(consoleEnter + 3, "closed", function() NLVR.Emit("ui_toggle", "flat") target = nil end)
    once(consoleEnter + 4, "closed-result", function() emit("followup-closed", {debug = NLVR.Debug.ui, info = native.Info().window_input}) end)
end)
