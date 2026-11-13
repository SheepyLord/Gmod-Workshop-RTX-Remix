-- Test only: compare client VGUI mouse dispatch modes against the real HTML pause menu.
local ID, active, seen = "vr_ui_flat_probe", false, {}
local native, oldFrame, oldActions, oldMove, oldPress, oldRelease, oldDouble
local oldSetCursor
local t, mode, movement = 0, "original", nil
local beforeMenu, reopenAt = {}, nil
local function state()
    local gx, gy = gui.MousePos() local ix, iy = input.GetCursorPos()
    local h, f = vgui.GetHoveredPanel(), vgui.GetKeyboardFocus()
    return {gui = {gx, gy}, input = {ix, iy}, window = {ScrW(), ScrH()}, visible = vgui.CursorVisible(), menu = gui.IsGameUIVisible(),
        system_focus = system.HasFocus(),
        hovered = IsValid(h) and {h:GetName(), h:GetClassName()}, focus = IsValid(f) and {f:GetName(), f:GetClassName()}}
end
local function emit(name, value)
    value = value or {} value.kind, value.name, value.time, value.mode = "ui", name, t, mode
    print("NLVR_Q " .. util.TableToJSON(value))
end
local function once(at, key, fn) if t >= at and not seen[key] then seen[key] = true fn() end end
local function reset(nextMode)
    mode = nextMode gui.HideGameUI() reopenAt = RealTime() + 0.1
end
hook.Add("PreRender", ID, function()
    if not NLVR then
        if active then
            native.BeginFrame, native.Actions = oldFrame, oldActions
            gui.InternalCursorMoved, gui.InternalMousePressed, gui.InternalMouseReleased = oldMove, oldPress, oldRelease
            input.SetCursorPos = oldSetCursor
            if CONFIG.ui_probe_setters then gui.EnableScreenClicker(false) end
            hook.Remove("PreRender", ID)
        end
        return
    end
    if not active then
        active, native = true, nlvr
        oldFrame, oldActions = native.BeginFrame, native.Actions
        oldMove, oldPress, oldRelease, oldDouble = gui.InternalCursorMoved, gui.InternalMousePressed, gui.InternalMouseReleased, gui.InternalMouseDoublePressed
        oldSetCursor = input.SetCursorPos
        input.SetCursorPos = function(x, y)
            if CONFIG.ui_probe_setters and mode == "gui_setter" then gui.SetMousePos(x, y) else oldSetCursor(x, y) end
        end
        native.BeginFrame = function(...)
            local f, err = oldFrame(...)
            if f then
                local clock = native.TestState() t = clock and clock.time or 0
                local o = NLVR.Overlay.Objects.flat
                local u, v = 140 / ScrW(), (ScrH() >= 1440 and 250 or 228) / ScrH()
                local target = o and o.pos + o.ang:Right() * ((u - 0.5) * o.metres) +
                    o.ang:Up() * ((0.5 - v) * o.metres * o.height / o.width) or Vector(1, 0, 1.3)
                f.right.pos = Vector(0.05, -0.25, 1.2) f.right.ang = (target - f.right.pos):Angle() f.right.valid = true
            end
            return f, err
        end
        native.Actions = function()
            local actions = oldActions()
            local down = false for _, at in ipairs({5, 9, 13, 17, 21, 25, 29}) do if t >= at and t < at + 0.35 then down = true end end
            actions.right_trigger = {active = true, state = down}
            return actions
        end
        gui.InternalCursorMoved = function(x, y)
            local before = state()
            if CONFIG.ui_probe_setters then return end
            if mode == "original" then oldMove(x, y)
            elseif mode == "delta" then local gx, gy = gui.MousePos() oldMove(x - gx, y - gy) end
            movement = {before = before, after = state(), arguments = {x, y}}
        end
        gui.InternalMousePressed = function(code)
            beforeMenu[mode] = gui.IsGameUIVisible()
            emit("flat-probe-press", {state = state(), movement = movement})
            if mode == "raw_mouse" then oldPress(0)
            elseif mode == "raw_double" then oldDouble(0)
            elseif mode == "keycode" then gui.InternalKeyCodePressed(code)
            elseif mode == "double" then oldDouble(code)
            else oldPress(code) end
        end
        gui.InternalMouseReleased = function(code)
            if mode == "raw_mouse" or mode == "raw_double" then oldRelease(0)
            elseif mode == "keycode" then gui.InternalKeyCodeReleased(code) else oldRelease(code) end
        end
    end
    once(1, "client-popup", function() if CONFIG.ui_probe_setters then NLVR.Emit("ui_toggle", "spawn") end end)
    once(1.6, "client-context", function() if CONFIG.ui_probe_setters then NLVR.Emit("ui_toggle", "context") end end)
    once(2, "open", function() NLVR.Emit("ui_toggle", "flat") end)
    once(3, "escape", function() if not gui.IsGameUIVisible() then gui.ActivateGameUI() end emit("flat-probe-ready", {state = state(), debug = NLVR.Debug.ui}) end)
    once(4, "capture", function() native.Capture("flat-probe", 15) end)
    for index, at in ipairs({7, 11, 15, 19, 23, 27, 31}) do
        once(at, "result" .. index, function()
            emit("flat-probe-result", {menu_before_press = beforeMenu[mode], resumed = beforeMenu[mode] == true and not gui.IsGameUIVisible(), state = state(), movement = movement})
            if CONFIG.ui_probe_setters then
                if not gui.IsGameUIVisible() then gui.ActivateGameUI() end
                mode = ({"gui_setter", "clicker_off", "clicker_on", "reset", "raw_mouse", "raw_double", "done"})[index]
                if mode == "clicker_off" then gui.EnableScreenClicker(false)
                elseif mode == "clicker_on" then gui.EnableScreenClicker(true)
                elseif mode == "reset" then gui.EnableScreenClicker(false) gui.HideGameUI() reopenAt = RealTime() + 0.1 end
            else
                local nextMode = ({"no_move", "delta", "keycode", "double", "raw_mouse", "raw_double", "done"})[index]
                reset(nextMode)
            end
        end)
    end
    if reopenAt and RealTime() >= reopenAt then reopenAt = nil gui.ActivateGameUI() end
    once(32, "close", function() gui.HideGameUI() NLVR.Emit("ui_toggle", "flat") end)
end)
