-- Follow-up diagnostic: the real Resume control, guarded immediately before a posted press.
local id, seen, native = "vr_ui_window_probe", {}, nil
local oldFrame, oldActions, oldInput, t, before = nil, nil, nil, 0, nil
local pressAt = CONFIG.ui_window_press_at or 5
local function cursor_state()
    local gx, gy = gui.MousePos() local ix, iy = input.GetCursorPos()
    return {gui = {gx, gy}, input = {ix, iy}, focus = system.HasFocus(), menu = gui.IsGameUIVisible()}
end
local function emit(name, values)
    values = values or {} values.kind, values.name, values.time = "ui", name, t
    print("NLVR_Q " .. util.TableToJSON(values))
end
local function once(at, name, fn) if t >= at and not seen[name] then seen[name] = true fn() end end
hook.Add("PreRender", id, function()
    if not NLVR then
        if native then
            native.BeginFrame, native.Actions, native.WindowInput = oldFrame, oldActions, oldInput
            hook.Remove("PreRender", id)
        end
        return
    end
    if not native then
        native = nlvr oldFrame, oldActions, oldInput = native.BeginFrame, native.Actions, native.WindowInput
        native.BeginFrame = function(...)
            local frame, detail = oldFrame(...)
            if frame then
                local clock = native.TestState() t = clock and clock.time or 0
                local o = NLVR.Overlay.Objects.flat
                if o then
                    local u, v = 140 / ScrW(), (ScrH() >= 1440 and 249 or 228) / ScrH()
                    local point = o.pos + o.ang:Right() * ((u - 0.5) * o.metres) + o.ang:Up() * ((0.5 - v) * o.metres * o.height / o.width)
                    frame.right.ang = (point - frame.right.pos):Angle() frame.right.valid = true
                end
            end
            return frame, detail
        end
        native.Actions = function()
            local actions = oldActions() actions.right_trigger = {active = true, state = t >= pressAt and t < pressAt + 0.35} return actions
        end
        native.WindowInput = function(kind, ...)
            if kind == "button" then
                local button, down = ...
                if down then before = gui.IsGameUIVisible() end
                emit("window-press", {button = button, down = down, menu_before_press = before, info = native.Info().window_input, cursor = cursor_state()})
            end
            return oldInput(kind, ...)
        end
    end
    once(1, "flat", function() NLVR.Emit("ui_toggle", "flat") end)
    once(2, "menu", function() if not gui.IsGameUIVisible() then gui.ActivateGameUI() end end)
    once(3, "before", function() native.Capture("window-before", 15) emit("window-before", {visible = gui.IsGameUIVisible()}) end)
    once(pressAt + 2, "result", function()
        native.Capture("window-after", 15)
        emit("window-result", {resumed = before == true and not gui.IsGameUIVisible(), menu_before_press = before,
            visible = gui.IsGameUIVisible(), info = native.Info().window_input, debug = NLVR.Debug.ui, cursor = cursor_state()})
    end)
    once(pressAt + 3, "close", function() NLVR.Emit("ui_toggle", "flat") end)
end)
