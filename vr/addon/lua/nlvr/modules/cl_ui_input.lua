-- The engine's VGUI dispatcher retains mouse capture for sliders and dragging.
local Input = {}
function Input.Pixel(u, v, width, height)
    return math.Clamp(math.floor(u * width), 0, width - 1), math.Clamp(math.floor(v * height), 0, height - 1)
end
function Input.Edit(value, caret, action, character)
    local chars, i = {}, 1
    while i <= #value do
        local b = value:byte(i)
        local n = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
        chars[#chars + 1] = value:sub(i, i + n - 1) i = i + n
    end
    caret = math.Clamp(caret or #chars, 0, #chars)
    if action == "left" then caret = math.max(0, caret - 1)
    elseif action == "right" then caret = math.min(#chars, caret + 1)
    elseif action == "home" then caret = 0
    elseif action == "end" then caret = #chars
    elseif action == "backspace" and caret > 0 then table.remove(chars, caret) caret = caret - 1
    elseif action == "delete" then table.remove(chars, caret + 1)
    elseif action == "char" or action == "space" or action == "tab" then
        table.insert(chars, caret + 1, action == "tab" and "\t" or character) caret = caret + 1
    end
    return table.concat(chars), caret
end
function Input.New(ctx, panels)
    local self = {keyboard = "closed"}
    local captured, last, target, focusSeen, scrollAt, swallowed = nil, nil, nil, nil, 0, false
    local keyboardOwner, pendingKeyboard, flatText = nil, nil, {}
    local fallback = include("nlvr/modules/cl_ui_keyboard.lua").New(ctx, panels.Text)
    self.Fallback = fallback
    local waitingClosed = false
    local desktop
    local cursorWindow, restoredAt = false, -math.huge
    local suppressed = {}
    local function window(kind, ...)
        if not ctx.native.WindowInput then error("WindowInput: update the VR module") end
        local result, detail = ctx.native.WindowInput(kind, ...)
        if result == false or result == nil and detail then error(detail or "WindowInput refused") end
    end
    local function restore_cursor()
        if not desktop then return end
        local saved = desktop desktop = nil
        input.SetCursorPos(saved[1], saved[2])
        if not cursorWindow then gui.InternalCursorMoved(saved[1], saved[2]) end
        restoredAt = RealTime()
    end
    local function cursor_move(hit,x,y)
        local held=captured
        local widget=held and held.widget
        local original=IsValid(widget) and widget.OnCursorMoved
        if type(original)~="function" then gui.InternalCursorMoved(x,y) return end
        local prior=rawget(widget:GetTable(),"OnCursorMoved") local delivered=false
        local observe=function(panel,...)
            if panel==widget then delivered=true end
            return original(panel,...)
        end
        widget.OnCursorMoved=observe
        local ok,detail=pcall(gui.InternalCursorMoved,x,y)
        if IsValid(widget) and rawget(widget:GetTable(),"OnCursorMoved")==observe then widget.OnCursorMoved=prior end
        if not ok then error(detail) end
        -- Background VGUI may accept the press/capture but omit move callbacks.
        -- Deliver the stock callback once for changed pixels, never a synthetic value.
        if captured==held and IsValid(widget) and panels.IsOpen(hit.panel) then
            if not delivered and (held.moveX~=x or held.moveY~=y) then
                local sx,sy=x,y
                if IsValid(hit.panel.root) then sx,sy=hit.panel.root:LocalToScreen(x,y) end
                original(widget,widget:ScreenToLocal(sx,sy))
            end
            held.moveX,held.moveY=x,y
        end
    end
    local function cursor(hit, fn)
        local x, y, window = panels.Cursor(hit)
        cursorWindow = window == true
        if cursorWindow then
            -- No OS cursor warp or client VGUI injection for the game window's MENU/HTML.
            local result, detail = ctx.native.WindowInput("cursor", x, y)
            if result == false or result == nil and detail then error(detail or "WindowInput cursor refused") end
            return fn()
        end
        desktop = desktop or {input.GetCursorPos()}
        local ok, result = pcall(function()
            input.SetCursorPos(x, y)
            -- GameUI/HTML uses the actual window cursor. The client InternalCursorMoved path
            -- recentres it while GameUI is active; it is only for our painted client VGUI.
            if panels.Interaction then panels.Interaction(hit,x,y) end
            if not cursorWindow then cursor_move(hit,x,y) end
            if panels.Interaction then panels.Interaction(hit,x,y) end
            local value=fn()
            -- Mouse press can update the hovered control synchronously.
            if panels.Interaction then panels.Interaction(hit,x,y) end
            return value
        end)
        if not ok then restore_cursor() error(result) end
        return result
    end
    local function hide_keyboard(request)
        fallback.Close()
        if request ~= false and keyboardOwner and ctx.native.HideKeyboard then
            local ok, result, detail = pcall(ctx.native.HideKeyboard)
            waitingClosed = ok and result ~= false and not (result == nil and detail) and self.keyboard == "open"
        end
        keyboardOwner, target = nil, nil self.keyboard = "closed"
    end
    local function mouse(hit, button, down)
        if hit.keyboard then
            if down then fallback.Press(hit) else fallback.Release(hit) end
        else
            cursor(hit, function()
                if hit.panel.window then window("button", button == MOUSE_RIGHT and "right" or "left", down)
                elseif down then
                    local widget=vgui.GetHoveredPanel()
                    gui.InternalMousePressed(button)
                    if captured and IsValid(widget) and panels.Contains(widget,hit.panel) then captured.widget=widget end
                else gui.InternalMouseReleased(button) end
            end)
        end
    end
    function self.Cancel()
        local hand = captured and captured.hand or ctx.Input.mainHand
        if hand and ctx.Input[hand].trigger then suppressed[hand] = true end
        if captured and last then
            local held = captured captured = nil
            if not held.keyboard then pcall(mouse, last, held.button, false) end
        end
        captured, last, swallowed, pendingKeyboard, flatText = nil, nil, ctx.Input.main.trigger == true, nil, {}
        restore_cursor()
        if ctx.native.WindowInput then pcall(ctx.native.WindowInput, "release") end
        hide_keyboard()
    end
    function self.Dragging() return captured ~= nil end
    function self.Closed(key)
        if pendingKeyboard and pendingKeyboard.owner.key == key then pendingKeyboard = nil end
        if key == "flat" then flatText = {} end
        if captured and captured.panel.key == key then self.Cancel()
        elseif keyboardOwner and keyboardOwner.key == key then hide_keyboard() end
        if not panels.Any or not panels.Any() then restore_cursor() end
    end
    local function apply(field, owner, entered, submit, caret)
            if IsValid(field) and panels.Contains(field, owner) then
                if field.GetNumeric and field:GetNumeric() then
                    local number = tonumber(entered)
                    if not number and (submit or not entered:match("^%-?%d*%.?%d*$")) or
                        number and (number ~= number or math.abs(number) == math.huge) then return end
                end
                field:SetText(entered)
                if IsValid(field) and field.SetCaretPos then
                    local value = field:GetText()
                    field:SetCaretPos(caret or (utf8 and utf8.len and utf8.len(value) or #value))
                end
                if IsValid(field) and field.OnTextChanged then field:OnTextChanged()
                elseif IsValid(field) and field.OnValueChange then field:OnValueChange(field:GetText()) end
                if submit and IsValid(field) and panels.Contains(field, owner) and field.OnEnter and not field:IsMultiline() then
                    field:OnEnter(field:GetText())
                end
            end
    end
    local function keypress(name) window("key", name, true) window("key", name, false) end
    local function queue_flat(value, submit)
        -- Drain at most eight Unicode characters per frame (at most sixteen UTF-16 messages).
        local i = 1
        while i <= #value do
            if #flatText >= 4096 then error("WindowInput: text queue exceeds 4096 characters") end
            local b = value:byte(i)
            local n = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
            local cp = b % (n == 1 and 128 or n == 2 and 32 or n == 3 and 16 or 8)
            for j = 1, n - 1 do cp = cp * 64 + (value:byte(i + j) or 128) % 64 end
            flatText[#flatText + 1] = cp i = i + n
        end
        if submit then flatText[#flatText + 1] = "enter" end
    end
    local function fallback_action(action, value)
        local owner, field = keyboardOwner, target
        if not owner or not panels.IsOpen(owner) then hide_keyboard(false) return end
        if action == "close" then hide_keyboard(false) return end
        if owner.window then
            if action == "char" or action == "space" then queue_flat(value)
            else keypress(action) end
        elseif IsValid(field) and panels.Contains(field, owner) then
            if action == "enter" then
                if field:IsMultiline() then
                    local value, caret = Input.Edit(field:GetText(), field.GetCaretPos and field:GetCaretPos(), "char", "\n")
                    apply(field, owner, value, false, caret)
                else apply(field, owner, field:GetText(), true) hide_keyboard(false) end
            else
                local value, caret = Input.Edit(field:GetText(), field.GetCaretPos and field:GetCaretPos(), action, value)
                local maximum = field.GetMaximumCharCount and field:GetMaximumCharCount() or 4096
                if maximum <= 0 then maximum = 4096 end
                if (utf8 and utf8.len and utf8.len(value) or #value) <= math.min(4096, maximum) then apply(field, owner, value, false, caret) end
            end
        else hide_keyboard(false) end
    end
    function self.RequestKeyboard(owner, field)
        if waitingClosed then pendingKeyboard = {owner = owner, field = field} return end
        hide_keyboard()
        if waitingClosed then pendingKeyboard = {owner = owner, field = field} return end
        keyboardOwner, target = owner, field
        local initial = not owner.window and IsValid(field) and field:GetText() or ""
        local ok, result, detail = false, nil, "ShowKeyboard is missing"
        if ctx.native.ShowKeyboard then
            ok, result, detail = pcall(ctx.native.ShowKeyboard, initial, panels.Text("Enter text"),
                not owner.window and field:IsMultiline() or false, 4096)
        end
        if ok and result ~= false and not (result == nil and detail) then
            self.keyboard, self.keyboardDetail = "open", nil
        else
            self.keyboard, self.keyboardDetail = "fallback", tostring(detail or result)
            fallback.Open(owner, fallback_action)
        end
    end
    function self.Event(event)
        if event.type == "keyboard_done" and keyboardOwner and self.keyboard == "open" then
            local field, owner = target, keyboardOwner
            hide_keyboard()
            if owner.window then queue_flat(tostring(event.text or ""), true)
            else apply(field, owner, tostring(event.text or ""), true) end
        elseif event.type == "keyboard_closed" then
            waitingClosed = false
            if self.keyboard ~= "fallback" then hide_keyboard(false) end
        end
    end
    local function keyboard()
        local focus = vgui and vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
        if keyboardOwner and (not panels.IsOpen(keyboardOwner) or not keyboardOwner.window and
            (focus ~= target or not IsValid(target) or not panels.Contains(target, keyboardOwner))) then
            hide_keyboard() focusSeen = nil
        end
        if waitingClosed then return end -- a delayed close must never cancel a newly focused field's keyboard
        if focus == focusSeen and not (self.keyboard == "closed" and ctx.Input.main.pressed.trigger and
            vgui.GetHoveredPanel() == focus) then return end
        focusSeen = focus
        local owner = IsValid(focus) and panels.Owner(focus)
        if not owner or not focus.GetText or not focus.SetText or not focus.IsMultiline or
            focus.GetClassName and focus:GetClassName() ~= "TextEntry" then return end
        if not owner.window then self.RequestKeyboard(owner, focus) end
    end
    function self.Frame()
        for hand in pairs(suppressed) do
            ctx.Input.Claim(hand, "trigger", "ui")
            if not ctx.Input[hand].trigger then suppressed[hand] = nil end
        end
        local origin, direction = ctx.Ray("main")
        local hit = origin and panels.Hit(origin, direction)
        local keyHit = origin and fallback.Hit(origin, direction)
        if keyHit and (not hit or keyHit.distance < hit.distance) then hit = keyHit end
        fallback.Hover(hit)
        local main = ctx.Input.main
        if origin and not hit and panels.ContextOpen and panels.ContextOpen() and
            main.pressed.trigger and ctx.Input.Claim("main", "trigger", "ui") then
            panels.WorldClick(origin, direction)
            swallowed = true
            self.lastClick = {panel = "context", world = true}
        end
        if captured and (not (captured.keyboard and fallback.IsOpen() or not captured.keyboard and panels.IsOpen(captured.panel)) or not origin) then self.Cancel() end
        if hit or captured or swallowed then
            local owned = ctx.Input.Claim("main", "trigger", "ui")
            ctx.Input.Claim("main", "stick", "ui")
            if owned then
                if hit and not hit.keyboard and not hit.close then cursor(hit, function() end) end
                if main.pressed.trigger and hit and not swallowed then
                    last = hit
                    if not hit.keyboard and panels.KeyboardHit and panels.KeyboardHit(hit) then
                        self.RequestKeyboard(hit.panel) swallowed = true
                    elseif not hit.keyboard and panels.CloseHit(hit) then
                        panels.Close(hit.panel.key) swallowed = true
                    else
                        local button = not hit.keyboard and panels.WorldHit(hit) and MOUSE_RIGHT or MOUSE_LEFT
                        captured = {panel = hit.panel, button = button, hand = ctx.Input.mainHand, keyboard = hit.keyboard}
                        mouse(hit, button, true)
                        self.lastClick = {panel = hit.panel.key, u = hit.u, v = hit.v, button = button}
                    end
                end
                if captured then
                    -- Capture survives a miss, releasing at the last in-bounds coordinate.
                    if hit and hit.panel == captured.panel then last = hit end
                    if main.released.trigger or not main.trigger then
                        local held = captured captured = nil
                        if held.keyboard then fallback.Release(hit and hit.keyboard and hit or nil)
                        else mouse(last, held.button, false) end
                    elseif last and not last.keyboard then cursor(last, function() end) end
                end
                if not main.trigger then swallowed = false end
                if hit and not hit.keyboard and not hit.close and math.abs(main.stick.y) > 0.35 and RealTime() >= scrollAt then
                    scrollAt = RealTime() + 0.12
                    cursor(hit, function()
                        local steps = main.stick.y > 0 and 1 or -1
                        if hit.panel.window then window("wheel", steps) else gui.InternalMouseWheeled(steps) end
                    end)
                end
            end
        end
        if not hit and not captured then restore_cursor() end
        keyboard()
        if pendingKeyboard and not waitingClosed then
            local request = pendingKeyboard pendingKeyboard = nil
            if panels.IsOpen(request.owner) and (request.owner.window or IsValid(request.field) and
                panels.Contains(request.field, request.owner) and vgui.GetKeyboardFocus() == request.field) then
                self.RequestKeyboard(request.owner, request.field)
            end
        end
        for _ = 1, math.min(8, #flatText) do
            local value = table.remove(flatText, 1)
            if panels.WindowState and panels.WindowState() == "ready" then
                if type(value) == "number" then
                    if value == 10 or value == 13 then keypress("enter") elseif value == 9 then keypress("tab") else window("char", value) end
                else keypress(value) end
            end
        end
        return hit, origin, direction
    end
    self.Cursor = cursor
    function self.MouseOwned() return desktop ~= nil or RealTime() - restoredAt < 0.05 end
    function self.Stop() self.Cancel() focusSeen = nil end
    return self
end
return Input
