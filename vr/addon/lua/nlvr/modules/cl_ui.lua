-- Included at Start VR; all resources belong to the framework's ui module.
local module = {name = "ui", order = 40}
local active
function module.Start(ctx)
    local panels = include("nlvr/modules/cl_ui_panels.lua").New(ctx)
    local pointer = include("nlvr/modules/cl_ui_input.lua").New(ctx, panels)
    local laser = include("nlvr/modules/cl_ui_laser.lua").New(ctx)
    active = {panels = panels, pointer = pointer, laser = laser}
    ctx.Debug.ui = {panels = {}, keyboard = "closed"}
    local laserDebug = {}
    ctx.On("ui_toggle", function(name) panels.Toggle(name) end)
    ctx.On("native_event", pointer.Event)
    ctx.On("panel_close", pointer.Closed)
    ctx.On("setting", function(name) if name == "dominant" then pointer.Cancel() panels.Mirror() end end)
    ctx.On("frame", function()
        local input = ctx.Input
        if input.off.pressed.b and input.Claim("off", "b", "ui") then panels.Toggle("wrist_menu") end
        local hit, origin, direction = pointer.Frame()
        laser.Update(hit, origin, direction, panels.Any())
        panels.Frame()
        -- A deferred wrist action can synchronously stop the entire core.
        if not active or not ctx.Debug.ui then return end
        local debug = ctx.Debug.ui
        debug.panels = panels.Inventory(debug.panels)
        if hit then laserDebug.panel, laserDebug.u, laserDebug.v = hit.panel.key, hit.u, hit.v end
        debug.laser = hit and laserDebug or nil
        local keyboard = pointer.Fallback.Inventory()
        if keyboard then debug.panels[#debug.panels + 1] = keyboard end
        debug.last_click, debug.dragging, debug.keyboard = pointer.lastClick, pointer.Dragging(), pointer.keyboard
        debug.keyboard_detail = pointer.keyboardDetail
        debug.window_source = panels.WindowState()
    end)
    -- Before L's mouse turning: synthetic cursor warps must not rotate the play space.
    ctx.mover(-1000, function(cmd)
        if panels.Any() or pointer.MouseOwned() then cmd:SetMouseX(0) cmd:SetMouseY(0) end
    end)
    -- A trigger used on UI must never also fire a weapon.
    ctx.mover(900, function(cmd)
        if ctx.Input.Owner("main", "trigger") == "ui" then
            cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(bit.bor(IN_ATTACK, IN_ATTACK2))))
        end
    end)
    ctx.cleanup(function() module.Stop() end)
end
function module.Stop()
    if not active then return end
    local current = active active = nil
    for _, part in ipairs({current.pointer, current.panels, current.laser}) do
        local ok, err = pcall(part.Stop)
        if not ok then MsgN("[nlvr] UI cleanup: " .. tostring(err)) end
    end
end
return module
