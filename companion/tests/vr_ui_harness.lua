local root, scenario = ...
assert(loadfile(root .. "/companion/tests/vr_stubs.lua"))().Math()
math.Clamp = function(n, a, b) return math.max(a, math.min(b, n)) end
local function eq(a, b, why) assert(a == b, (why or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b) assert(math.abs(a - b) < 0.00001, a .. " ~= " .. b) end
function include(path) return assert(loadfile(root .. "/vr/addon/lua/" .. path))() end
IsValid = function(p) return type(p) == "table" and not p.removed end
MOUSE_LEFT, MOUSE_RIGHT, TOP, FILL, TEXT_ALIGN_CENTER = 107, 108, 1, 5, 1
RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, IMAGE_FORMAT_RGBA8888 = 8, 2, 0
color_white = {}
local now, x, y, focus, hover = 0, 17, 29
local menuVisible, screenClicker = false, false
RealTime = function() return now end
FrameNumber=function() return math.floor(now*90) end
ScrW, ScrH = function() return 3840 end, function() return 2160 end
local events, hooks, controls, nativeCalls = {}, {}, {}, {}
local function record(name, ...) events[#events + 1] = {name, x, y, ...} end
input = {GetCursorPos = function() return x, y end, SetCursorPos = function(a, b) x, y = a, b end}
gui = {InternalCursorMoved = function() record("move") end,
    InternalMousePressed = function(b) record("press", b) end,
    InternalMouseReleased = function(b) record("release", b) end,
    InternalMouseWheeled = function(n) record("wheel", n) end}
gui.IsGameUIVisible = function() return menuVisible end
gui.ActivateGameUI = function() menuVisible = true end
gui.HideGameUI = function() menuVisible = false end
gui.EnableScreenClicker = function(b) screenClicker = b end
surface = {SetDrawColor = function() end, DrawRect = function() end, CreateFont = function() end}
draw = {SimpleText = function() end}
local P = {} P.__index = P
function P:GetTable() return self end
function P:LocalToScreen(a,b)
    local panel=self
    while panel do local px,py=panel:GetPos() a,b=a+px,b+py panel=panel:GetParent() end
    return a,b
end
function P:ScreenToLocal(a,b) local px,py=self:LocalToScreen(0,0) return a-px,b-py end
function P:CursorPos() return self:ScreenToLocal(input.GetCursorPos()) end
function P:GetParent() return self.parent end
function P:SetParent(parent) self.parent = parent end
function P:GetPos() return self.x or 0, self.y or 0 end
function P:SetPos(a, b) self.x, self.y = a, b end
function P:GetSize() return self.w or 100, self.h or 100 end
function P:SetSize(w, h) self.w, self.h = w, h end
function P:SetTall(h) self.h = h end
function P:Dock(n) self.dock = n end
function P:GetDock() return self.dock or 0 end
function P:DockMargin() end function P:DockPadding() end
function P:SetVisible(b) self.visible = b end function P:IsVisible() return self.visible == true end
function P:SetPaintedManually(b) self.manual = b end function P:IsPaintedManually() return self.manual == true end
function P:SetKeyboardInputEnabled(b) self.keyboard = b end function P:IsKeyboardInputEnabled() return self.keyboard == true end
function P:SetMouseInputEnabled(b) self.mouse = b end function P:IsMouseInputEnabled() return self.mouse == true end
function P:MakePopup() self.visible, self.mouse, self.keyboard, self.popup = true, true, true, true end
function P:IsPopup() return self.popup end
function P:InvalidateLayout() if self.PerformLayout then self:PerformLayout() end end
function P:PaintManual() if self.Paint then self:Paint(self:GetSize()) end end
function P:SetText(s) self.text = s end function P:GetText() return self.text or "" end
function P:SetFont() end
function P:GetClassName() return self.class == "DTextEntry" and "TextEntry" or "EditablePanel" end
function P:IsMultiline() return false end
function P:SetHangOpen(b) self.hang = b end
function P:Close() self.visible = false end
function P:Remove() self.removed = true end
local world = setmetatable({}, P)
function P:GetChildren()
    local children = {}
    for _, p in ipairs(controls) do if p.parent == self and not p.removed then children[#children + 1] = p end end
    return children
end
function P:GetName() return self.class end
function P:GetWide() return self.w or 100 end function P:GetTall() return self.h or 100 end
vgui = {GetWorldPanel = function() return world end, GetKeyboardFocus = function() return focus end,
    CursorVisible = function() return screenClicker or menuVisible end,
    GetHoveredPanel = function() return hover end,
    Create = function(class, parent)
        local p = setmetatable({parent = parent or world, class = class}, P)
        controls[#controls + 1] = p return p
    end}
hook=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib")
hook.Add("OnSpawnMenuOpen","engine",function() g_SpawnMenu:MakePopup() end)
hook.Add("OnContextMenuOpen","engine",function() g_ContextMenu:MakePopup() end)

NativeLoaderVR = {Recenter = function() record("recenter") end, Stop = function() record("exit") end,
    BuildOptions = function() record("options") end}
local manager = include("nlvr/core/cl_overlay.lua")
local ctx = {Space = {scale = 40}, Pose = {head = {valid = true, pos = Vector(0, 0, 64), ang = Angle(),
    raw = {pos = Vector(0, 0, 1.6), ang = Angle()}}}, Debug = {}, native = {}}
ctx.Input = include("nlvr/core/cl_input.lua").New()
ctx.Input.Update({}, 0, false)
ctx.Ray = function() return Vector(0, 0, 64), Vector(1, 0, 0) end
ctx.ToWorld = function(p, a) return p * 40, a or Angle() end
ctx.Native = ctx.native
ctx.native.WindowInput = function() return true end
ctx.Registry = {current = {}, Own = function() end}
ctx.hook = function(event, fn) hooks[event] = fn hook.Add(event,"nlvr.ui",fn) end
ctx.Emit = function(name, ...) record(name, ...) end
for _, name in ipairs({"OverlaySource", "OverlayAttach", "OverlayShow", "OverlayAlpha", "OverlayDestroy", "OverlaySortOrder"}) do
    ctx.native[name] = function(...) nativeCalls[#nativeCalls + 1] = {name, ...} end
end
local handle = 0
ctx.native.OverlayCreate = function() handle = handle + 1 return handle end
GetRenderTargetEx = function(_, w, h) return {Width = function() return w end, Height = function() return h end} end
ctx.Overlay = manager.New(ctx)
assert(ctx.Overlay.Sizes.keyboard[1] == 1039 and ctx.Overlay.Sizes.keyboard[2] == 391, "S's central keyboard reservation")
local panelsModule = include("nlvr/modules/cl_ui_panels.lua")
local inputModule = include("nlvr/modules/cl_ui_input.lua")
local cases = {}
function cases.verify_background_drag_cursor()
    g_SpawnMenu=vgui.Create("SpawnMenu")
    local panels=panelsModule.New(ctx) panels.Toggle("spawn")
    local slider=vgui.Create("DSlider",g_SpawnMenu) slider:SetPos(50,20)
    local knob=vgui.Create("DButton",slider) hover=knob
    local entry=panels.Owner(knob) local inherited=slider.CursorPos
    local custom=function(self) return inherited(self) end
    slider.CursorPos=custom
    panels.Interaction({panel=entry},120,110)
    -- Stock drag Think reads CursorPos later, after a background desktop poll.
    x,y=0,0
    local a,b=slider:CursorPos()
    eq(a,70,"painted slider must read the controller cursor, not desktop (0,0)") eq(b,48)
    panels.Interaction({panel=entry},160,110)
    a=slider:CursorPos() eq(a,110,"held drag must follow the controller")
    local later=function() return 999,999 end
    g_SpawnMenu.CursorPos=later
    panels.Close("spawn") eq(slider.CursorPos,custom,"restore pre-existing panel method")
    eq(rawget(knob:GetTable(),"CursorPos"),nil,"remove only our instance override")
    eq(g_SpawnMenu.CursorPos,later,"retain later third-party replacement")
end
function cases.verify_window_refusal()
    MsgN=function() end
    local calls=0 ctx.native.OverlayWindow=function() calls=calls+1 return false,"runtime refused" end
    local panels=panelsModule.New(ctx) panels.Toggle("flat")
    assert(panels.WindowState()~="ready","unaccepted window reported ready")
    for i=1,8 do panels.Frame() end
    eq(panels.WindowState(),"unavailable")
    assert(ctx.Overlay.Objects.flat.visible,"refused window needs a visible update fallback")
    assert(not menuVisible,"invisible refused flat panel paused the game")
    eq(calls,1,"permanent refusal retried every frame") panels.Stop()
end
function cases.review_restore_throw()
    MsgN=function() end
    for _,key in ipairs({"spawn","context"}) do
        local p=vgui.Create("BorrowedMenu")
        if key=="spawn" then g_SpawnMenu=p else g_ContextMenu=p end
        local panels=panelsModule.New(ctx)
        panels.Toggle(key)
        local oldRun=hook.Run
        hook.Run=function(event,...)
            if event=="OnSpawnMenuClose" or event=="OnContextMenuClose" then error("test close hook") end
            return oldRun(event,...)
        end
        local oldRemove=P.Remove
        P.Remove=function(self) for _,child in ipairs(self:GetChildren()) do child:Remove() end oldRemove(self) end
        panels.Stop()
        assert(IsValid(p) and p:GetParent()==world,"borrowed real menu must survive a throwing close hook")
        hook.Run=oldRun P.Remove=oldRemove
        p:MakePopup() assert(p:IsVisible(),"Q/C menu still opens after Exit")
    end
end
function cases.review_wrist_exit()
    local callbacks={}
    ctx.On=function(name,fn) callbacks[name]=fn end
    ctx.mover=function() end ctx.cleanup=function() end
    ctx.Ray=function() return nil end
    local ui=include("nlvr/modules/cl_ui.lua")
    ui.Start(ctx) callbacks.ui_toggle("wrist_menu")
    NativeLoaderVR.Stop=function() ui.Stop() ctx.Debug={} end
    for _,p in ipairs(controls) do if p.text=="Exit VR" then p.DoClick() end end
    callbacks.frame()
end
function cases.pixels()
    for _, size in ipairs({{1537, 1025}, {513, 515}, {3840, 2160}, {1280, 720}}) do
        local a, b = inputModule.Pixel(0, 0, unpack(size)) eq(a, 0) eq(b, 0)
        a, b = inputModule.Pixel(1, 1, unpack(size)) eq(a, size[1] - 1) eq(b, size[2] - 1)
        a, b = inputModule.Pixel(0.5, 0.25, unpack(size)) eq(a, math.floor(size[1] / 2)) eq(b, math.floor(size[2] / 4))
    end
end
local fakePanel = {key = "spawn", overlay = {pos = Vector(1.15, 0, 1.52), ang = Angle(), metres = 1.25, width = 1537, height = 1025, device = "world"}}
local hit = {panel = fakePanel, u = 0.25, v = 0.5, distance = 40}
local open, closeHit = true, false
local fake = {Text = function(s) return s end, Hit = function() return hit end,
    Cursor = function(h) return inputModule.Pixel(h.u, h.v, 1537, 1025) end,
    IsOpen = function() return open end, CloseHit = function() return closeHit end,
    Close = function() open = false end, WorldHit = function() return false end,
    Owner = function() return open and fakePanel end, Contains = function() return open end}
local function state(down, time, stick, left)
    now = time
    local actions = {right_trigger = {active = true, state = down}, right_stick = {active = true, y = stick or 0}}
    if left then actions.left_trigger, actions.right_trigger = actions.right_trigger, nil end
    ctx.Input.Update(actions, now, left)
end
local function count(name) local n = 0 for _, e in ipairs(events) do if e[1] == name then n = n + 1 end end return n end
function cases.click_drag()
    local pointer = inputModule.New(ctx, fake)
    state(true, 1) pointer.Frame() eq(count("press"), 1) eq(ctx.Input.Owner("main", "trigger"), "ui")
    eq(x, 384) eq(y, 512) eq(pointer.Dragging(), true)
    state(true, 1.4) hit.u = 0.75 pointer.Frame() eq(count("press"), 1)
    state(true, 1.5) hit = nil pointer.Frame() eq(pointer.Dragging(), true)
    state(false, 1.6) pointer.Frame() eq(count("release"), 1) eq(pointer.Dragging(), false)
    eq(ctx.Input.Owner("main", "trigger"), "ui") eq(x, 17) eq(y, 29)
    eq(pointer.lastClick.u, 0.25)
end
function cases.verify_background_drag_events()
    local widget=vgui.Create("DSlider") hover=widget
    local moves,lastX=0,nil
    local original=function(_,a) moves=moves+1 lastX=a end
    widget.OnCursorMoved=original
    local oldMove=gui.InternalCursorMoved
    gui.InternalCursorMoved=function() x,y=0,0 end -- native background move delivers no widget event
    local pointer=inputModule.New(ctx,fake)
    state(true,1) pointer.Frame()
    hit.u=.75 state(true,1.1) pointer.Frame()
    eq(lastX,1152,"captured Derma callback must receive the moving controller point")
    local before=moves
    state(true,1.2) pointer.Frame() eq(moves,before,"unchanged pixels must not duplicate callbacks")
    local nativeX,nativeY=1152,512
    gui.InternalCursorMoved=function(a,b)
        if a~=nativeX or b~=nativeY then nativeX,nativeY=a,b widget:OnCursorMoved(a,b) end
    end
    hit.u=.5 state(true,1.3) pointer.Frame() eq(moves,before+1,"do not duplicate a delivered native callback")
    eq(widget.OnCursorMoved,original,"restore the observed native callback")
    state(false,1.4) pointer.Frame() pointer.Stop() gui.InternalCursorMoved=oldMove
end
function cases.claims()
    local pointer = inputModule.New(ctx, fake)
    state(true, 1) ctx.Input.Claim("main", "trigger", "interact") pointer.Frame() eq(count("press"), 0)
    state(false, 2) pointer.Frame()
    state(true, 3, 0, true) pointer.Frame() eq(ctx.Input.Owner("left", "trigger"), "ui") eq(count("press"), 1)
    pointer.Stop() eq(count("release"), 1) eq(x, 17) eq(y, 29)
end
function cases.dominant_capture()
    local pointer = inputModule.New(ctx, fake)
    state(true, 1) pointer.Frame()
    ctx.Input.Mirror(true) pointer.Cancel()
    ctx.Input.Update({right_trigger = {active = true, state = true}}, 2, true)
    pointer.Frame() eq(ctx.Input.Owner("right", "trigger"), "ui", "old physical trigger stays consumed after mirroring")
    ctx.Input.Update({}, 3, true) pointer.Frame() eq(ctx.Input.Owner("right", "trigger"), "ui", "release frame")
    ctx.Input.Update({}, 4, true) pointer.Frame() eq(ctx.Input.Owner("right", "trigger"), nil)
    pointer.Stop()
end
function cases.scroll_close()
    local pointer = inputModule.New(ctx, fake)
    for _, t in ipairs({1, 1.01, 1.13, 1.26}) do state(false, t, -0.8) pointer.Frame() end
    eq(count("wheel"), 3)
    closeHit = true state(true, 2) pointer.Frame() eq(open, false) eq(count("press"), 0)
    hit = nil state(true, 2.2) pointer.Frame() eq(ctx.Input.Owner("main", "trigger"), "ui")
    state(false, 2.3) pointer.Frame() eq(ctx.Input.Owner("main", "trigger"), "ui")
    state(false, 2.4) pointer.Frame() eq(ctx.Input.Owner("main", "trigger"), nil)
end
function cases.cursor_error()
    local pointer = inputModule.New(ctx, fake)
    local ok = pcall(pointer.Cursor, hit, function() error("VGUI failed") end)
    eq(ok, false) eq(x, 17) eq(y, 29)
end
function cases.window_cursor()
    fake.Cursor = function() return 140, 250, true end
    gui.InternalCursorMoved = function() error("client cursor routing recentres GameUI") end
    ctx.native.WindowInput = function(kind, a, b) record("native-window", kind, a, b) return true end
    local pointer = inputModule.New(ctx, fake)
    pointer.Cursor(hit, function() end)
    eq(count("native-window"), 1) eq(x, 17) eq(y, 29) pointer.Stop() eq(x, 17) eq(y, 29)
end
function cases.keyboard()
    local shown, hidden = 0, 0
    ctx.native.ShowKeyboard = function(s, title, multiline, limit) shown = shown + 1 eq(s, "old") eq(limit, 4096) return true end
    ctx.native.HideKeyboard = function() hidden = hidden + 1 end
    focus = vgui.Create("DTextEntry") focus.text = "old"
    focus.IsMultiline = function() return false end
    focus.OnValueChange = function(self, value) record("value", value) end
    focus.OnEnter = function() record("enter") end
    local pointer = inputModule.New(ctx, fake)
    pointer.Frame() pointer.Frame() eq(shown, 1) eq(pointer.keyboard, "open")
    pointer.Event{type = "keyboard_done", text = "barrel"}
    eq(focus.text, "barrel") eq(count("value"), 1) eq(count("enter"), 1) eq(hidden, 1)
    eq(pointer.keyboard, "closed") pointer.Event{type = "keyboard_done", text = "late"} eq(focus.text, "barrel")
    pointer.Event{type = "keyboard_closed"}
    focus = nil pointer.Frame()
    focus = vgui.Create("DTextEntry") focus.text = "old" focus.IsMultiline = function() return true end
    pointer.Frame() pointer.Closed("spawn") eq(hidden, 2) eq(pointer.keyboard, "closed")
    pointer.Event{type = "keyboard_done", text = "late"} eq(focus.text, "old")
end
function cases.keyboard_unavailable()
    focus = vgui.Create("DTextEntry") focus.IsMultiline = function() return false end
    local pointer = inputModule.New(ctx, fake) pointer.Frame() eq(pointer.keyboard, "fallback")
    assert(ctx.Overlay.Objects.keyboard) eq(pointer.Fallback.Owner(), fakePanel)
    ctx.native.ShowKeyboard = function() return nil, "refused" end
    focus = vgui.Create("DTextEntry") focus.IsMultiline = function() return false end
    pointer.Frame() eq(pointer.keyboard, "fallback") eq(pointer.keyboardDetail, "refused")
    pointer.Stop() eq(ctx.Overlay.Objects.keyboard, nil)
end
function cases.keyboard_edit()
    local text = string.char(0xe4, 0xb8, 0xad) .. "ab"
    local value, caret = inputModule.Edit(text, 1, "delete") eq(value, string.char(0xe4, 0xb8, 0xad) .. "b") eq(caret, 1)
    value, caret = inputModule.Edit(value, caret, "backspace") eq(value, "b") eq(caret, 0)
    value, caret = inputModule.Edit(value, caret, "char", "A") eq(value, "Ab") eq(caret, 1)
    value, caret = inputModule.Edit(value, caret, "end") eq(caret, 2)
    value, caret = inputModule.Edit(value, caret, "left") eq(caret, 1)
end
function cases.keyboard_layout()
    local keyboard = include("nlvr/modules/cl_ui_keyboard.lua")
    local cells = keyboard.Layout(1039, 391)
    local required = {shift = false, enter = false, backspace = false, close = false, space = false}
    for _, k in ipairs(cells) do
        assert(k.x >= 0 and k.y >= 42 and k.x + k.w <= 1039 and k.y + k.h <= 391)
        if required[k.action] ~= nil then required[k.action] = true end
    end
    for name, present in pairs(required) do assert(present, name) end
    local self = keyboard.New(ctx, function(s) return s end)
    local result = {}
    self.Open(fakePanel, function(action, value) result[#result + 1] = {action, value} end)
    local function click(name)
        for _, k in ipairs(cells) do if k.value == name then
            -- Use the object's actual geometry and hit mapping, not a direct callback.
            local o = ctx.Overlay.Objects.keyboard
            local point = o.pos + o.ang:Right() * ((k.x + k.w / 2) / o.width - 0.5) * o.metres +
                o.ang:Up() * (0.5 - (k.y + k.h / 2) / o.height) * o.metres * o.height / o.width
            local hit = assert(self.Hit(Vector(0, 0, 64), point * 40 - Vector(0, 0, 64)))
            self.Press(hit) self.Release(hit) return
        end end error(name)
    end
    click("Shift") click("a") eq(result[1][1], "char") eq(result[1][2], "A")
    click("Space") eq(result[2][2], " ") click("Close") eq(ctx.Overlay.Objects.keyboard, nil)
end
function cases.window_dispatch()
    local values = {}
    fakePanel.window = true
    fake.Cursor = function() return 140, 249, true end
    fake.WindowState = function() return "ready" end
    ctx.native.WindowInput = function(...) values[#values + 1] = {...} return true end
    local pointer = inputModule.New(ctx, fake)
    state(true, 1) pointer.Frame() state(false, 2, 0.8) pointer.Frame()
    eq(count("press"), 0) eq(count("wheel"), 0)
    local downs, ups, wheel = 0, 0, 0
    for _, e in ipairs(values) do
        if e[1] == "button" then if e[3] then downs = downs + 1 else ups = ups + 1 end
        elseif e[1] == "wheel" then wheel = wheel + 1 end
    end
    eq(downs, 1) eq(ups, 1) eq(wheel, 1) eq(x, 17) eq(y, 29)
    pointer.RequestKeyboard(fakePanel) eq(pointer.keyboard, "fallback")
    pointer.Stop() eq(ctx.Overlay.Objects.keyboard, nil)
end
function cases.fallback_typing()
    focus = vgui.Create("DTextEntry") focus.text, focus.caret = "", 0
    focus.GetCaretPos = function(self) return self.caret end
    focus.SetCaretPos = function(self, value) self.caret = value end
    focus.OnTextChanged = function() record("changed") end
    focus.OnEnter = function() record("enter") end
    ctx.native.ShowKeyboard = function() return nil, "RequestFailed" end
    fake.Hit = function() return nil end
    local pointer = inputModule.New(ctx, fake) pointer.Frame()
    eq(pointer.keyboard, "fallback")
    local inventory=pointer.Fallback.Inventory()
    eq(pointer.Fallback.Inventory(),inventory)
    local function click(label, time)
        local o = assert(ctx.Overlay.Objects.keyboard)
        local cells = include("nlvr/modules/cl_ui_keyboard.lua").Layout(o.width, o.height)
        for _, k in ipairs(cells) do if k.value == label then
            local point = o.pos + o.ang:Right() * ((k.x + k.w / 2) / o.width - 0.5) * o.metres +
                o.ang:Up() * (0.5 - (k.y + k.h / 2) / o.height) * o.metres * o.height / o.width
            ctx.Ray = function() return Vector(0, 0, 64), point * 40 - Vector(0, 0, 64) end
            state(true, time) pointer.Frame() state(false, time + 0.2) pointer.Frame() return
        end end error(label)
    end
    click("Shift", 1) click("b", 2) eq(focus.text, "B") click("Backspace", 3) eq(focus.text, "")
    click("Shift", 4) click("a", 5) eq(focus.text, "a") eq(focus.caret, 1)
    pointer.Event{type = "keyboard_done", text = "late native result"} eq(focus.text, "a")
    pointer.Event{type = "keyboard_closed"} eq(pointer.keyboard, "fallback")
    click("Enter", 6) eq(count("enter"), 1) eq(count("changed"), 4) eq(pointer.keyboard, "closed")
    eq(ctx.Overlay.Objects.keyboard, nil) pointer.Stop()
end
function cases.fallback_window_text()
    fakePanel.window = true
    fake.WindowState = function() return "ready" end
    fake.Hit = function() return nil end
    local values = {}
    ctx.native.WindowInput = function(...) values[#values + 1] = {...} return true end
    ctx.native.ShowKeyboard = function() return true end
    local pointer = inputModule.New(ctx, fake)
    pointer.RequestKeyboard(fakePanel)
    pointer.Event{type = "keyboard_done", text = "hello" .. string.char(0xf0, 0x9f, 0x99, 0x82)}
    pointer.Frame()
    eq(#values, 8) -- six character scalars plus Enter down/up
    eq(values[6][1], "char") eq(values[6][2], 0x1f642)
    eq(values[7][1], "key") eq(values[7][2], "enter") eq(values[7][3], true) eq(values[8][3], false)
    pointer.RequestKeyboard(fakePanel) pointer.Event{type = "keyboard_done", text = "discarded"}
    pointer.Closed("flat") pointer.Frame() eq(#values, 8, "closing drops queued native text")
end
function cases.keyboard_reentrant()
    ctx.native.ShowKeyboard = function() return true end
    ctx.native.HideKeyboard = function() end
    focus = vgui.Create("DTextEntry") focus.IsMultiline = function() return false end
    focus.OnTextChanged = function() open = false end
    focus.OnEnter = function() error("a closed panel was submitted") end
    local pointer = inputModule.New(ctx, fake) pointer.Frame()
    pointer.Event{type = "keyboard_done", text = "closed by change callback"}
    eq(pointer.keyboard, "closed") eq(focus.text, "closed by change callback")
end
function cases.keyboard_nontext()
    focus = vgui.Create("EditablePanel")
    ctx.native.ShowKeyboard = function() error("engine panel methods do not make this a text entry") end
    local pointer = inputModule.New(ctx, fake) pointer.Frame() eq(pointer.keyboard, "closed")
end
function cases.keyboard_switch()
    local shown = 0
    ctx.native.ShowKeyboard = function() shown = shown + 1 return true end
    ctx.native.HideKeyboard = function() end
    local first = vgui.Create("DTextEntry") first.text = "first" focus = first
    local pointer = inputModule.New(ctx, fake) pointer.Frame() eq(shown, 1)
    focus = vgui.Create("DTextEntry") focus.text = "second"
    pointer.Frame() eq(shown, 1, "wait for the old keyboard to close")
    pointer.Event{type = "keyboard_done", text = "late old result"} eq(first.text, "first") eq(focus.text, "second")
    pointer.Event{type = "keyboard_closed"} pointer.Frame() eq(shown, 2)
    pointer.Event{type = "keyboard_done", text = "new result"} eq(focus.text, "new result")
end
function cases.keyboard_toolbar_wait()
    local shown = 0
    ctx.native.ShowKeyboard = function() shown = shown + 1 return true end
    ctx.native.HideKeyboard = function() end
    focus = vgui.Create("DTextEntry")
    local pointer = inputModule.New(ctx, fake) pointer.Frame() eq(shown, 1)
    pointer.RequestKeyboard(fakePanel, focus) eq(shown, 1)
    pointer.Frame() eq(shown, 1)
    pointer.Event{type = "keyboard_closed"} pointer.Frame() eq(shown, 2) eq(pointer.keyboard, "open")
    pointer.Stop()
end
function cases.keyboard_numeric()
    ctx.native.ShowKeyboard = function() return true end
    ctx.native.HideKeyboard = function() end
    focus = vgui.Create("DTextEntry") focus.text = "0.6" focus.GetNumeric = function() return true end
    local pointer = inputModule.New(ctx, fake) pointer.Frame()
    pointer.Event{type = "keyboard_done", text = "barrel"} eq(focus.text, "0.6", "native SetText must not bypass numeric filtering")
end
function cases.panels()
    g_SpawnMenu = vgui.Create("SpawnMenu") g_SpawnMenu:SetPos(11, 22) g_SpawnMenu:SetSize(3840, 2160)
    g_SpawnMenu.PerformLayout = function() assert(ScrW() == 1537 or ScrW() == 3840) end
    local originalLayout = g_SpawnMenu.PerformLayout
    local panels = panelsModule.New(ctx)
    panels.Toggle("spawn") local o = ctx.Overlay.Objects.spawn
    eq(o.width, 1537) eq(o.height, 1025) eq(o.device, "world") near(o.pos.x, 1.15)
    local u, v, distance = ctx.Overlay.Hit(o, Vector(0, 0, 60.8), Vector(1, 0, 0))
    near(u, 0.5) near(v, 0.5) near(distance, 46)
    local px, py = panels.Cursor{panel = {window = true}, u = 0.5, v = 0.5} eq(px, 1920) eq(py, 1080)
    panels.Close("spawn") eq(g_SpawnMenu.removed, nil) eq(g_SpawnMenu:GetParent(), world)
    eq(g_SpawnMenu.PerformLayout, originalLayout)
    eq(g_SpawnMenu.visible, false) eq(g_SpawnMenu.mouse, false) eq(g_SpawnMenu.manual, false)
    eq(g_SpawnMenu.x, 11) eq(g_SpawnMenu.y, 22) eq(g_SpawnMenu.w, 3840) eq(ScrW(), 3840)
    eq(#panels.Inventory(), 0) eq(next(ctx.Overlay.Objects), nil)
end
function cases.wrist()
    local panels = panelsModule.New(ctx) panels.Toggle("wrist_menu")
    local inventory = panels.Inventory()
    local row = inventory[1]
    for i=1,100 do eq(panels.Inventory(inventory),inventory) eq(inventory[1],row) end
    eq(ctx.Overlay.Objects.wrist_menu.device, "left") eq(#panelsModule.Items, 7)
    local buttons = {} for _, p in ipairs(controls) do if p.class == "DButton" then buttons[#buttons + 1] = p end end
    eq(#buttons, 7) eq(buttons[1].text, "Spawn menu") eq(buttons[3].text, "Flat screen")
    buttons[5].DoClick() eq(count("height_calibrate"), 0) panels.Frame() eq(count("height_calibrate"), 1)
    buttons[6].DoClick() panels.Frame() eq(count("recenter"), 1)
    ctx.Input.Mirror(true) panels.Mirror() eq(ctx.Overlay.Objects.wrist_menu.device, "right")
    panels.Toggle("wrist_menu") eq(#panels.Inventory(), 0)
end
function cases.module_debug()
    local callbacks={}
    ctx.Ray=function() return nil end -- tracking absent: test the real debug producer without a billboard pose
    ctx.On=function(name,fn) callbacks[name]=fn end
    ctx.mover=function() end ctx.cleanup=function() end
    local ui=include("nlvr/modules/cl_ui.lua")
    ui.Start(ctx) callbacks.ui_toggle("wrist_menu") callbacks.frame()
    local debug,list,row=ctx.Debug.ui,ctx.Debug.ui.panels,ctx.Debug.ui.panels[1]
    for i=1,100 do callbacks.frame() eq(ctx.Debug.ui,debug) eq(debug.panels,list) eq(list[1],row) end
    ui.Stop() eq(next(ctx.Overlay.Objects),nil)
end
function cases.deferred_button()
    g_SpawnMenu = vgui.Create("SpawnMenu")
    local panels = panelsModule.New(ctx) panels.Toggle("wrist_menu")
    local first
    for _, p in ipairs(controls) do if p.class == "DButton" then first = first or p end end
    ctx.Registry.current = nil
    first.DoClick() eq(ctx.Overlay.Objects.spawn, nil, "deferred engine callback only queues")
    ctx.Registry.current = {}
    panels.Frame() assert(ctx.Overlay.Objects.spawn) eq(ctx.Overlay.Objects.wrist_menu, nil)
    panels.Stop() first.DoClick() panels.Frame() eq(next(ctx.Overlay.Objects), nil, "stopped callbacks cannot reopen")
end
function cases.window()
    local panels = panelsModule.New(ctx) panels.Toggle("flat") eq(panels.WindowState(), "unavailable")
    panels.Close("flat") eq(panels.WindowState(), "closed")
    ctx.native.OverlayWindow = function(h, b) record("window", h, b) return true end
    panels.Toggle("flat") eq(panels.WindowState(), "ready") assert(ctx.Overlay.Objects.flat_close)
    local h = panels.Hit(Vector(0, 0, 60.8), Vector(1, 0, 0)) eq(h.panel.key, "flat")
    panels.Stop() eq(count("window"), 1) eq(next(ctx.Overlay.Objects), nil) -- Destroy retires the source itself
end
function cases.window_menu()
    ctx.native.OverlayWindow = function() return true end
    local panels = panelsModule.New(ctx) panels.Toggle("flat") panels.Frame() panels.Frame()
    eq(menuVisible, true, "an empty flat window opens Escape")
    gui.HideGameUI() panels.Frame() eq(screenClicker, true, "keep real cursor mode after Resume")
    panels.Close("flat") eq(screenClicker, false) eq(menuVisible, false)
    menuVisible = true panels.Toggle("flat") panels.Frame() panels.Frame() panels.Close("flat")
    eq(menuVisible, true, "an existing menu is the player's, not ours to hide")
end
function cases.context_widget()
    g_ContextMenu = vgui.Create("ContextMenu")
    local panels = panelsModule.New(ctx) panels.Toggle("context")
    local widget = vgui.Create("DFrame", g_ContextMenu) widget:SetPos(2000, 1500) widget:MakePopup()
    panels.Frame() eq(widget.manual, true) assert(widget.x < 1281 and widget.y < 961)
    panels.Close("context") eq(widget:GetParent(), g_ContextMenu) eq(widget.removed, nil)
    eq(widget.manual, false) eq(widget.x, 2000) eq(widget.y, 1500)
end
function cases.baseline_flags()
    g_SpawnMenu = vgui.Create("SpawnMenu") g_SpawnMenu.keyboard = true
    local panels = panelsModule.New(ctx) panels.Toggle("wrist_menu")
    g_SpawnMenu.keyboard = false -- MakePopup/focus changes can alter another native popup's flag.
    panels.Stop() eq(g_SpawnMenu.keyboard, true) eq(g_SpawnMenu.visible, false)
end
function cases.invalid_head()
    local panels = panelsModule.New(ctx)
    ctx.Pose.head.valid = false panels.Toggle("spawn") eq(next(ctx.Overlay.Objects), nil)
    ctx.Pose.head.valid = true panels.Toggle("wrist_menu") assert(ctx.Overlay.Objects.wrist_menu)
    ctx.Pose.head.valid = false panels.Toggle("wrist_menu") eq(next(ctx.Overlay.Objects), nil, "tracking loss still permits closing")
end
function cases.resolution_error()
    eq(pcall(panelsModule.Resolution, 1537, 1025, function() eq(ScrW(), 1537) error("layout") end), false)
    eq(ScrW(), 3840) eq(ScrH(), 2160)
end
function cases.page()
    -- Reuse the original page lifecycle stand-ins without changing F/V1's test files.
    assert(loadfile(root .. "/companion/tests/vr_harness.lua"))(root, "idle")
    local variables, choices, buttons = {}, {}, {}
    local panel = {Help = function() end, ControlHelp = function() end}
    function panel:ComboBox(label, cvar)
        eq(label, "") variables[cvar] = true choices[cvar] = {}
        return {AddChoice = function(_, name, value) choices[cvar][#choices[cvar] + 1] = {name, value} end}
    end
    function panel:NumSlider(label, cvar, low, high) eq(label, "") assert(low < high) variables[cvar] = true end
    function panel:CheckBox(label, cvar) assert(#label > 0) variables[cvar] = true end
    function panel:Button(label) local b = {} buttons[label] = b return b end
    NativeLoaderVR.BuildOptions(panel)
    -- V6 added the quality step, V7 true stereo and V8 frame generation.
    local n = 0 for _ in pairs(variables) do n = n + 1 end eq(n, 21)
    for _, cvar in ipairs({"dominant", "move_dir", "turn", "snap_angle", "turn_speed", "teleport", "vignette", "seated", "seated_offset",
        "ghost_hands", "wrist_hud", "gloves", "climb", "melee", "quality", "stereo", "frame_generation"}) do assert(variables["nl_vr_" .. cvar], cvar) end
    eq(#choices.nl_vr_quality, 8) eq(choices.nl_vr_quality[1][2], 0) eq(choices.nl_vr_quality[8][2], 7)
    eq(choices.nl_vr_teleport[1][2], 0) eq(choices.nl_vr_teleport[3][2], 2)
    eq(choices.nl_vr_dominant[2][1], "Left hand")
    eq(buttons["Calibrate height"].DoClick(), false, "no calibration off")
    eq(buttons["SteamVR controller bindings"].DoClick(), false, "no binding UI off")
    local received
    NLVR = {Emit = function(name) received = name end}
    eq(NativeLoaderVR.Calibrate(), true) eq(received, "height_calibrate")
    NLVR.Move = {calibration = {restart = true}}
    assert(NativeLoaderVR.StatusText():find("Height calibrated. Exit VR, then Start VR", 1, true))
    NLVR.Move.calibration.restart = false
    assert(not NativeLoaderVR.StatusText():find("Height calibrated. Exit VR, then Start VR", 1, true))
    NLVR = nil
end
assert(cases[scenario], "Unknown UI scenario")()
print("PASS " .. scenario)
