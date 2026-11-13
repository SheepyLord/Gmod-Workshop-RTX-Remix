-- Borrow existing sandbox panels; never copy their implementation or replace their controls.
local Panels = {}
Panels.Items = {"spawn", "context", "flat", "settings", "calibrate", "recenter", "exit"}
local titles = {wrist_menu = "Wrist menu", spawn = "Spawn menu", context = "Context menu",
    flat = "Flat screen", settings = "VR settings"}
local function saved_call(p, method, fallback)
    return p[method] and p[method](p) or fallback
end
-- Sandbox layouts use ScrW/ScrH. Scope their virtual desktop to this panel, then restore it
-- even on errors; the actual window, world panel, GUI scaler setting and other panels stay intact.
function Panels.Resolution(w, h, fn)
    local oldW, oldH = ScrW, ScrH
    ScrW, ScrH = function() return w end, function() return h end
    local ok, result = pcall(fn)
    ScrW, ScrH = oldW, oldH
    if not ok then error(result) end
    return result
end
function Panels.Bookmarks(fn)
    local remember, restore = RememberCursorPosition, RestoreCursorPosition
    RememberCursorPosition, RestoreCursorPosition = function() end, function() end
    local ok, result = pcall(fn)
    RememberCursorPosition, RestoreCursorPosition = remember, restore
    if not ok then error(result) end
    return result
end
function Panels.New(ctx)
    local self, opened, windowState, serial = {}, {}, "closed", 0
    local interacting
    local pending, stopped = {}, false
    local notice, noticeUntil
    function self.Notice(message) notice, noticeUntil = message, RealTime() + 8 end
    local baseline = {}
    for _, p in pairs({spawn = g_SpawnMenu, context = g_ContextMenu}) do
        if IsValid(p) then
            baseline[p] = {visible = p:IsVisible(), mouse = p:IsMouseInputEnabled(), keyboard = p:IsKeyboardInputEnabled(),
                hang = p.GetHangOpen and p:GetHangOpen()}
            if p:IsVisible() and p.Close then
                Panels.Bookmarks(function()
                    if p.SetHangOpen then p:SetHangOpen(false) end
                    p:Close()
                end)
            end
        end
    end
    surface.CreateFont("NLVRUIControl", {font = "Tahoma", size = 20, weight = 500, extended = true})
    surface.CreateFont("NLVRUITitle", {font = "Tahoma", size = 26, weight = 600, extended = true})
    surface.CreateFont("NLVRUIKeyboard", {font = "Tahoma", size = 18, weight = 500, extended = true})
    local pixel = include("nlvr/modules/cl_ui_input.lua").Pixel
    local function text(s)
        local words = NativeLoaderVR and NativeLoaderVR.UILabels
        local source = words and words[s] or s
        return NATIVELOADER_I18N and NATIVELOADER_I18N.L(source) or source
    end
    self.Text = text
    local function root_is_child(p, root)
        while IsValid(p) do if p == root then return true end p = p:GetParent() end
        return false
    end
    function self.Interaction(hit,x,y)
        local entry=hit.panel
        if opened[entry.key]~=entry then return end
        interacting=entry
        if entry.window or x==nil then return end
        entry.cursor={x,y}
        -- Derma drag Think runs after the injected move. An unfocused desktop can
        -- replace its native cursor with (0,0) between frames. Bind only the active
        -- hovered control/ancestor chain to this canvas's controller coordinates.
        local p=vgui.GetHoveredPanel()
        if not root_is_child(p,entry.root) then return end
        entry.cursorMethods=entry.cursorMethods or {}
        while IsValid(p) do
            if not entry.cursorMethods[p] and type(p.CursorPos)=="function" then
                local original,prior=p.CursorPos,rawget(p:GetTable(),"CursorPos")
                local replacement=function(panel)
                    if interacting==entry and opened[entry.key]==entry and entry.cursor then
                        local sx,sy=entry.root:LocalToScreen(entry.cursor[1],entry.cursor[2])
                        return panel:ScreenToLocal(sx,sy)
                    end
                    return original(panel)
                end
                entry.cursorMethods[p]={prior=prior,replacement=replacement}
                p.CursorPos=replacement
            end
            if p==entry.root then break end
            p=p:GetParent()
        end
    end
    function self.Owner(p)
        for _, entry in pairs(opened) do if IsValid(entry.root) and root_is_child(p, entry.root) then return entry end end
        if opened.flat and windowState == "ready" then return opened.flat end
    end
    function self.Contains(p, entry) return opened[entry.key] == entry and self.Owner(p) == entry end
    function self.IsOpen(entry) return opened[entry.key] == entry end
    function self.Any() return next(opened) ~= nil end
    function self.WindowState() return windowState end
    function self.Inventory(list)
        list = list or {}
        for i = #list, 1, -1 do list[i] = nil end
        for key, entry in pairs(opened) do
            entry.debug = entry.debug or {key = key, width = entry.overlay.width,
                height = entry.overlay.height, handle = entry.overlay.handle}
            entry.debug.handle=entry.overlay.handle
            list[#list + 1] = entry.debug
        end
        table.sort(list, function(a, b) return a.key < b.key end)
        return list
    end
    function self.Close(key)
        local entry = opened[key]
        if not entry then return end
        opened[key] = nil
        if interacting == entry then interacting = nil end
        for p,state in pairs(entry.cursorMethods or {}) do
            if IsValid(p) and rawget(p:GetTable(),"CursorPos")==state.replacement then p.CursorPos=state.prior end
        end
        entry.cursorMethods=nil
        ctx.Emit("panel_close", key)
        if key == "flat" then
            if entry.window then pcall(entry.overlay.Window, entry.overlay, false) end
            if entry.clicker then gui.EnableScreenClicker(false) end
            if entry.openedMenu and gui.IsGameUIVisible() then gui.HideGameUI() end
            windowState = "closed"
        end
        for p, state in pairs(entry.widgetPopups or {}) do
            if IsValid(p) then p:SetPaintedManually(state.manual) p:SetPos(state.x, state.y) end
        end
        if entry.restore then
            local ok, err = pcall(entry.restore)
            if not ok then MsgN("[nlvr] UI panel restore: " .. tostring(err)) end
        end
        if IsValid(entry.root) then entry.root:Remove() end
        if entry.closeOverlay then entry.closeOverlay:Destroy() end
        entry.overlay:Destroy()
    end
    local function place(entry)
        if entry.key == "wrist_menu" then
            entry.overlay:Place(ctx.Input.offHand, Vector(0.12, 0, 0.13), Angle(0, 0, 90), 0.32)
            return
        end
        local raw = ctx.Pose.head.raw
        local yaw = Angle(0, raw.ang.y, 0)
        entry.overlay:Place("world", raw.pos + yaw:Forward() * 1.15 - Vector(0, 0, 0.08), yaw, 1.25)
    end
    function self.Mirror() if opened.wrist_menu then place(opened.wrist_menu) end end
    local function borrow(entry, p, prior)
        local x, y = p:GetPos() local w, h = p:GetSize()
        local fields = p.GetTable and p:GetTable() or p
        local old = {parent = p:GetParent(), x = x, y = y, w = w, h = h, dock = p:GetDock(),
            visible = p:IsVisible(), manual = saved_call(p, "IsPaintedManually", false),
            mouse = p:IsMouseInputEnabled(), keyboard = p:IsKeyboardInputEnabled(), layout = p.PerformLayout,
            rawLayout = rawget(fields, "PerformLayout"), leftWidth = p.HorizontalDivider and p.HorizontalDivider:GetLeftWidth()}
        old.visible, old.mouse, old.keyboard = prior.visible, prior.mouse, prior.keyboard
        local layout = function(panel, ...)
            local args = {...}
            return Panels.Resolution(entry.overlay.width, entry.overlay.height - 42,
                function() if old.layout then old.layout(panel, unpack(args)) end end)
        end
        entry.restore = function()
            if not IsValid(p) then return end
            -- Detach the real sandbox menu before any third-party close callback can fail.
            p:SetParent(IsValid(old.parent) and old.parent or vgui.GetWorldPanel())
            if p.Close then
                local ok,err=pcall(Panels.Bookmarks,function()
                    local closed,detail=pcall(hook.Run,"On" .. (entry.key == "spawn" and "Spawn" or "Context") .. "MenuClose")
                    if not closed then MsgN("[nlvr] UI close hook: "..tostring(detail)) end
                    if p.SetHangOpen then p:SetHangOpen(false) end
                    p:Close()
                end)
                if not ok then MsgN("[nlvr] UI close: "..tostring(err)) end
            end
            if p.PerformLayout == layout then p.PerformLayout = old.rawLayout end
            p:SetParent(IsValid(old.parent) and old.parent or vgui.GetWorldPanel())
            p:Dock(old.dock) p:SetPos(old.x, old.y) p:SetSize(old.w, old.h)
            p:SetPaintedManually(old.manual) p:SetVisible(old.visible)
            p:SetMouseInputEnabled(old.mouse) p:SetKeyboardInputEnabled(old.keyboard)
            p:InvalidateLayout(true)
            if old.leftWidth and IsValid(p.HorizontalDivider) then p.HorizontalDivider:SetLeftWidth(old.leftWidth) end
        end
        p.PerformLayout = layout
        p:SetParent(entry.root) p:Dock(NODOCK or 0) p:SetPaintedManually(true)
        p:SetPos(0, 42) p:SetSize(entry.overlay.width, entry.overlay.height - 42)
        p:SetVisible(true) p:SetMouseInputEnabled(true)
        p:InvalidateLayout(true)
        entry.borrowed = p
    end
    local function add_button(parent, label, fn)
        local b = vgui.Create("DButton", parent)
        b.gScF = true -- GUI Scaler's public opt-out; this canvas already has fixed pixel dimensions.
        b:Dock(TOP) b:DockMargin(10, 4, 10, 4) b:SetTall(48) b:SetText(text(label))
        b:SetFont("NLVRUIControl")
        -- Engine VGUI dispatch can defer DoClick beyond the frame's module context. Drain actions
        -- in Frame, where F's registry can own any overlays created by the callback.
        b.DoClick = function() if not stopped then pending[#pending + 1] = fn end end
        return b
    end
    local function body(entry)
        local root = vgui.Create("EditablePanel")
        root.NLVRPanel = entry.key
        root.gScF = true
        entry.root = root
        root:SetSize(entry.overlay.width, entry.overlay.height) root:SetPos(0, 0)
        root:DockPadding(0, 42, 0, 0)
        root:SetPaintedManually(true) root:MakePopup() root:SetKeyboardInputEnabled(false)
        root.Paint = function(_, w, h)
            if entry.key ~= "context" then
                if entry.key == "settings" then surface.SetDrawColor(235, 242, 246, 255)
                else surface.SetDrawColor(12, 18, 26, 250) end
                surface.DrawRect(0, 0, w, h)
            end
            surface.SetDrawColor(35, 58, 75, 255) surface.DrawRect(0, 0, w, 42)
            draw.SimpleText(text(titles[entry.key]), "NLVRUITitle", 12, 6, color_white)
            draw.SimpleText("X", "NLVRUITitle", w - 32, 6, color_white)
            if notice and RealTime() < noticeUntil then
                surface.SetDrawColor(100, 30, 30, 245) surface.DrawRect(0, h - 36, w, 36)
                draw.SimpleText(text(notice), "NLVRUIControl", 12, h - 30, color_white)
            end
        end
        return root
    end
    local function open_sandbox(entry)
        local name = entry.key == "spawn" and "Spawn" or "Context"
        local before
        if entry.key == "spawn" then before = g_SpawnMenu else before = g_ContextMenu end
        local prior = {visible = IsValid(before) and before:IsVisible() or false,
            mouse = IsValid(before) and before:IsMouseInputEnabled() or false,
            keyboard = IsValid(before) and before:IsKeyboardInputEnabled() or false}
        Panels.Bookmarks(function() hook.Run("On" .. name .. "MenuOpen") end)
        local p
        if entry.key == "spawn" then p = g_SpawnMenu else p = g_ContextMenu end
        if not IsValid(p) then
            add_button(entry.root, "This menu is unavailable in this gamemode.", function() end) return
        end
        borrow(entry, p, prior)
    end
    local function windowFallback(entry)
        entry.window,entry.windowPending=false,false windowState="unavailable"
        entry.overlay:Window(false)
        body(entry)
        add_button(entry.root, "The flat screen needs a newer VR module and Remix runtime. Update the RTX package.", function() end)
        entry.overlay:Invalidate() entry.overlay:Show(true)
    end
    local function windowReady(entry)
        entry.window,entry.windowPending=true,false windowState="ready"
        entry.menuWait = 2
        -- The source owns every pixel of flat. Its close mark therefore has its own overlay above it.
        local o = entry.overlay
        local closeSize = ctx.Overlay.Sizes.flat_close
        entry.closeOverlay = ctx.Overlay.New{key = "flat_close", name = "Close flat screen", width = closeSize[1], height = closeSize[2],
            device = "world", pos = o.pos + o.ang:Up() * (o.metres * o.height / o.width / 2 + 0.055),
            ang = o.ang, metres = 0.075, paint = function(_, w, h)
                surface.SetDrawColor(35, 58, 75, 255) surface.DrawRect(0, 0, w, h)
                draw.SimpleText("X", "NLVRUITitle", w / 2, h / 4 - 12, color_white, TEXT_ALIGN_CENTER)
                draw.SimpleText("Aa", "NLVRUITitle", w / 2, h * 3 / 4 - 12, color_white, TEXT_ALIGN_CENTER)
            end}
        entry.closeOverlay:Show(true)
    end
    local function windowStatus(entry)
        if not entry.windowPending then return end
        local state=entry.overlay:WindowState()
        if state=="refused" then windowFallback(entry)
        elseif state=="ready" and entry.overlay:IsVisible() then windowReady(entry) end
    end
    local function window(entry)
        if not ctx.native.OverlayWindow or not ctx.native.WindowInput then windowFallback(entry) return end
        local ok,result,detail=pcall(entry.overlay.Window,entry.overlay,true)
        if not ok or result==false then windowFallback(entry) return end
        entry.window,entry.windowPending=false,true windowState="pending"
    end
    function self.Toggle(key)
        if opened[key] then self.Close(key) return end
        if not titles[key] or not ctx.Pose.head or not ctx.Pose.head.valid or not ctx.Pose.head.raw then return end
        if key ~= "wrist_menu" then
            for _, other in ipairs({"spawn", "context", "flat", "settings"}) do self.Close(other) end
            self.Close("wrist_menu")
        end
        local size = ctx.Overlay.Sizes[key]
        -- Settings and context are mutually exclusive; a unique settings size avoids reserving F's context slot.
        serial = serial + 1
        local entry = {key = key, serial = serial, known = setmetatable({}, {__mode = "k"}), popups = {}, widgetPopups = {}}
        for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do entry.known[p] = true end
        entry.overlay = ctx.Overlay.New{key = key, name = text(titles[key]), width = size[1], height = size[2],
            paint = function()
                if IsValid(entry.root) then
                    Panels.Resolution(size[1], size[2], function()
                        entry.root:PaintManual(true)
                        -- Sandbox Open calls MakePopup. Such panels are not ordinary painted
                        -- children even after reparenting, so paint their complete subtree explicitly.
                        if IsValid(entry.borrowed) then entry.borrowed:PaintManual(true) end
                        for _, popup in ipairs(entry.popups) do if IsValid(popup) then popup:PaintManual(true) end end
                    end)
                end
            end}
        opened[key] = entry place(entry)
        if key == "flat" then window(entry) else body(entry) end
        if key == "spawn" or key == "context" then open_sandbox(entry)
        elseif key == "settings" then
            local scroll = vgui.Create("DScrollPanel", entry.root) scroll.gScF = true scroll:Dock(FILL)
            local panel = vgui.Create("ControlPanel", scroll) panel.gScF = true panel:Dock(TOP)
            panel:SetName(text("VR settings"))
            if NativeLoaderVR.BuildOptions then NativeLoaderVR.BuildOptions(panel) end
            local function readable(p)
                p.gScF = true
                if p.SetFont then p:SetFont("NLVRUIControl") end
                local name = p:GetName()
                if name == "DComboBox" then
                    p:SetTall(34)
                    -- DForm otherwise keeps the combo's wrapper at a 13-pixel font row.
                    -- Our title is a separate full-width help line, so this row is all control.
                    local row = p:GetParent()
                    if IsValid(row) then row.gScF = true row:SetTall(34) end
                    p:Dock(FILL)
                elseif name == "DButton" then p:SetTall(34)
                elseif name == "DNumSlider" then p:SetTall(40)
                elseif name == "DCheckBoxLabel" then p:SetTall(32) end
                for _, child in ipairs(p:GetChildren()) do readable(child) end
            end
            readable(panel)
        elseif key == "wrist_menu" then
            for _, item in ipairs(Panels.Items) do
                local action = item
                local labels = {calibrate = "Calibrate height", recenter = "Recentre VR", exit = "Exit VR"}
                add_button(entry.root, titles[item] or labels[item], function()
                    if action == "calibrate" then ctx.Emit("height_calibrate")
                    elseif action == "recenter" then NativeLoaderVR.Recenter()
                    elseif action == "exit" then NativeLoaderVR.Stop()
                    else self.Toggle(action) end
                end)
            end
        end
        entry.overlay:Show(true)
        if key=="flat" then windowStatus(entry) end
        entry.overlay:SortOrder(key == "wrist_menu" and 20 or 10)
        ctx.Emit("panel_open", key)
    end
    function self.Hit(origin, direction)
        local best
        for _, entry in pairs(opened) do
            for _, overlay in ipairs({entry.overlay, entry.closeOverlay}) do
                local u, v, distance = ctx.Overlay.Hit(overlay, origin, direction)
                if u and (not best or distance < best.distance or distance == best.distance and entry.serial > best.panel.serial) then
                    best = {panel = entry, u = u, v = v, distance = distance, close = overlay == entry.closeOverlay}
                end
            end
        end
        return best
    end
    function self.KeyboardHit(hit) return hit.close and hit.v >= 0.5 end
    function self.CloseHit(hit) return hit.close and hit.v < 0.5 or hit.v * hit.panel.overlay.height < 42 and hit.u * hit.panel.overlay.width > hit.panel.overlay.width - 48 and not hit.panel.window end
    function self.Cursor(hit)
        local entry = hit.panel
        if entry.window then
            local x, y = pixel(hit.u, hit.v, ScrW(), ScrH())
            return x, y, true
        end
        return pixel(hit.u, hit.v, entry.overlay.width, entry.overlay.height)
    end
    function self.WorldHit(hit)
        if hit.panel.key ~= "context" then return false end
        local p = vgui.GetHoveredPanel()
        return IsValid(p) and p.IsWorldClicker and p:IsWorldClicker()
    end
    function self.ContextOpen() return opened.context ~= nil end
    function self.WorldClick(origin, direction)
        local entry = opened.context
        if not entry or not properties or not properties.OnScreenClick then return end
        interacting = entry
        properties.OnScreenClick(origin, direction)
        ctx.Debug.ui.context_ray = {origin = {origin.x, origin.y, origin.z}, direction = {direction.x, direction.y, direction.z}}
    end
    -- The sandbox's default mouse path starts at the eye. Supply both parts of the actual
    -- hand ray to properties instead, without changing global ScreenToVector/EyePos functions.
    ctx.hook("GUIMousePressed", function(code)
        if opened.context then
            local o, d = ctx.Ray("main")
            if o and code == MOUSE_RIGHT and properties and properties.OnScreenClick then
                self.WorldClick(o, d) return true
            end
        end
    end)
    function self.Frame()
        local actions = pending pending = {}
        for _, fn in ipairs(actions) do if not stopped then fn() end end
        -- Derma creates property menus and combo dropdowns as world-panel popups. Bring only
        -- newly created menus from this interaction into its canvas, so their real callbacks work.
        if interacting and self.IsOpen(interacting) and IsValid(interacting.root) then
            for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
                if not interacting.known[p] and p:IsVisible() and p.GetName and
                    (p:GetName() == "DMenu" or p:GetName() == "DTooltip") then
                    local x, y = p:GetPos()
                    p:SetParent(interacting.root) p:SetPos(math.Clamp(x, 0, interacting.overlay.width - p:GetWide()),
                        math.Clamp(y, 42, interacting.overlay.height - p:GetTall()))
                    p:SetPaintedManually(true)
                    interacting.popups[#interacting.popups + 1] = p
                    interacting.known[p] = true
                end
            end
        end
        for key, entry in pairs(opened) do
            if key=="flat" then windowStatus(entry) end
            if entry.window and entry.overlay:IsVisible() then
                if entry.menuWait then
                    entry.menuWait = entry.menuWait - 1
                    if entry.menuWait <= 0 then
                        entry.menuWait = nil
                        -- With no other 2D window open, make the controller-only route useful
                        -- immediately. Existing add-on/console windows keep their own focus.
                        if not gui.IsGameUIVisible() and not vgui.CursorVisible() then
                            gui.ActivateGameUI() entry.openedMenu = true
                        end
                    end
                elseif not gui.IsGameUIVisible() and not vgui.CursorVisible() then
                    gui.EnableScreenClicker(true) entry.clicker = true
                end
            end
            if key == "context" and IsValid(entry.borrowed) then
                -- Desktop widget windows belong to g_ContextMenu, rather than the world panel.
                -- Keep that parent/lifetime and restore their ordinary painting when VR closes.
                for _, p in ipairs(entry.borrowed:GetChildren()) do
                    if p.IsPopup and p:IsPopup() and p:IsVisible() and not entry.widgetPopups[p] then
                        local x, y = p:GetPos()
                        entry.widgetPopups[p] = {x = x, y = y, manual = saved_call(p, "IsPaintedManually", false)}
                        p:SetPaintedManually(true)
                        p:SetPos(math.Clamp(x, 0, math.max(0, entry.overlay.width - p:GetWide())),
                            math.Clamp(y, 0, math.max(0, entry.overlay.height - 42 - p:GetTall())))
                        entry.popups[#entry.popups + 1] = p
                    end
                end
            end
            if IsValid(entry.root) then
                entry.root:SetSize(entry.overlay.width, entry.overlay.height)
                if entry.borrowed and not entry.borrowed:IsVisible() then self.Close(key)
                else entry.overlay:Invalidate() end
            end
        end
    end
    function self.Stop()
        stopped, pending = true, {}
        local keys = {} for key in pairs(opened) do keys[#keys + 1] = key end
        for _, key in ipairs(keys) do self.Close(key) end
        for p, state in pairs(baseline) do
            if IsValid(p) and state.visible and not p:IsVisible() and p.Open then Panels.Bookmarks(function() p:Open() end) end
        end
        for p, state in pairs(baseline) do
            if IsValid(p) then
                p:SetVisible(state.visible) p:SetMouseInputEnabled(state.mouse) p:SetKeyboardInputEnabled(state.keyboard)
                if p.SetHangOpen and state.hang ~= nil then p:SetHangOpen(state.hang) end
            end
        end
        baseline = {}
    end
    return self
end
return Panels
