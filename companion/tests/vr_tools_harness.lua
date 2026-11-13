local root, scenario = ...
local S = assert(loadfile(root .. "/companion/tests/vr_stubs.lua"))() S.Math()
local V, A = getmetatable(Vector()), getmetatable(Angle())
function V:Cross(b) return Vector(self.y * b.z - self.z * b.y, self.z * b.x - self.x * b.z, self.x * b.y - self.y * b.x) end
function A:RotateAroundAxis(axis, degrees)
    axis = axis:GetNormalized()
    local c, s = math.cos(math.rad(degrees)), math.sin(math.rad(degrees))
    local function rotate(v) return v * c + axis:Cross(v) * s + axis * (axis:Dot(v) * (1 - c)) end
    local f, l = rotate(self:Forward()), rotate(-self:Right())
    self.p, self.y, self.r = math.deg(math.atan2(-f.z, math.sqrt(f.x * f.x + f.y * f.y))),
        math.deg(math.atan2(f.y, f.x)), math.deg(math.atan2(l.z, f.x * l.y - f.y * l.x))
end
bit = require("bit")
function include(path) return assert(loadfile(root .. "/vr/addon/lua/" .. path))() end
math.Clamp = function(n, low, high) return math.max(low, math.min(high, n)) end
local function near(a, b, epsilon) assert(math.abs(a - b) < (epsilon or 0.00001), tostring(a) .. " ~= " .. tostring(b)) end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function vec(a, b) near((a - b):Length(), 0) end
local V = getmetatable(Vector())
function V:Angle() return Angle(math.deg(math.atan2(-self.z, math.sqrt(self.x ^ 2 + self.y ^ 2))), math.deg(math.atan2(self.y, self.x)), 0) end
function V:AngleEx() return self:Angle() end
local Math = include("nlvr/modules/sh_tools_math.lua")
local cases = {}
function cases.dependency_absent()
    local context = {}
    -- No fake resource methods: attempting to register anything here fails the scenario.
    local cl = include("nlvr/modules/cl_tools.lua") cl.Start(context) cl.Stop()
    local sv = include("nlvr/modules/sv_tools.lua") sv.Start(context) sv.Stop()
    eq(next(context), nil)
end
function cases.relative_axes()
    for _, delta in ipairs({Angle(90, 0, 0), Angle(0, 90, 0), Angle(0, 0, 90)}) do
        local relative = Math.Relative(Angle(), Angle())
        near(Math.AngleError(Math.Follow(relative, delta), delta), 0, 0.00001)
    end
end
function cases.relative_compound()
    -- Independent forward/right basis transform witnesses; Euler components are never added.
    math.randomseed(181)
    for i = 1, 200 do
        local hand = Angle(math.random(-89, 89), math.random(-180, 180), math.random(-180, 180))
        local prop = Angle(math.random(-89, 89), math.random(-180, 180), math.random(-180, 180))
        local relative = Math.Relative(prop, hand)
        near(Math.AngleError(Math.Follow(relative, hand), prop), 0, 0.00001)
    end
end
function cases.angle_wrap() near(Math.AngleError(Angle(0, 179, 0), Angle(0, -179, 0)), 2) near(Math.AngleError(Angle(89.99, 23, 70), Angle(89.99, 23, 70)), 0) end
function cases.stick_rate()
    for _, hz in ipairs({30, 66, 90, 120}) do
        for _, axis in ipairs({1, -1, 0.6, -0.6}) do
            local carry, sum = 0, 0
            for i = 1, hz * 2 do local n n, carry = Math.DistanceCommand(axis, 1 / hz, carry) sum = sum + n / hz end
            local target = (axis > 0 and 1 or -1) * (math.abs(axis) - 0.2) / 0.8 * 2
            near(sum + carry, target, 0.00001)
        end
    end
end
function cases.stick_deadzone() eq(Math.DistanceCommand(0.2, 0.015, 0), 0) eq(Math.DistanceCommand(-0.2, 0.015, 0), 0) end
function cases.stick_bounded() eq(Math.DistanceCommand(0 / 0, 10, 0), 0) eq(Math.DistanceCommand(1, 30, 0), 1) eq(Math.DistanceCommand(-1, 0.1, 0), -1) end
local function rows(n)
    local result = {}
    for i = 1, n do result[i] = {class = "weapon_" .. i, slot = math.floor(i / 4), position = i % 4} end
    return result
end
function cases.inventory()
    local list = rows(20) list[#list + 1] = {class = "nlvr_hands", slot = 9, position = 9} list[#list + 1] = list[3]
    local sorted = Math.Entries(list, function(x) return x end)
    eq(#sorted, 21) eq(sorted[1].class, "nlvr_hands")
    for i = 3, #sorted do assert(sorted[i].slot >= sorted[i - 1].slot) end
    for n = 1, 155 do
        local many = rows(n) many[#many + 1] = {class = "nlvr_hands", slot = 99, position = 99}
        local all = Math.Entries(many, function(x) return x end)
        eq(#all, n + 1) eq(all[1].class, "nlvr_hands")
    end
end
function cases.layout()
    for n = 1, 155 do
        local seen = {}
        for page = 1, math.ceil(n / 12) do
            local layout, pages = Math.Layout(n, page) eq(pages, math.ceil(n / 12))
            assert(#layout <= 12)
            for _, row in ipairs(layout) do assert(not seen[row.index]) seen[row.index] = true near(row.x ^ 2 + row.y ^ 2, 1) end
        end
        for i = 1, n do assert(seen[i]) end
    end
end
function cases.layout_readable()
    for n = 1, 12 do
        local layout = Math.Layout(n, 1)
        for i, a in ipairs(layout) do
            local x, y = 1035 / 2 + a.x * 1035 * 0.35, 1037 / 2 - a.y * 1037 * 0.35
            assert(x >= 84 and x <= 1035 - 84 and y >= 60 and y <= 1037 - 60)
            for j = i + 1, #layout do
                local b = layout[j]
                assert(math.abs((a.x - b.x) * 1035 * 0.35) >= 168 or math.abs((a.y - b.y) * 1037 * 0.35) >= 120)
            end
        end
    end
end
function cases.picking()
    for n = 1, 52 do
        for page = 1, math.ceil(n / 12) do
            for _, row in ipairs(Math.Layout(n, page)) do eq(Math.Pick(n, page, row.x * 0.14, row.y * 0.14), row.index) end
        end
    end
end
function cases.deadzone() eq(Math.Pick(12, 1, 0.029, 0), nil) eq(Math.Pick(12, 1, 0, 0), nil) assert(Math.Pick(12, 1, 0.031, 0)) eq(Math.Pick(12, 1, 0 / 0, 0), nil) end
function cases.pages()
    local p, latch, changed = Math.Page(1, 3, 0, 0.25, false) eq(p, 2) eq(changed, true)
    eq(Math.Page(p, 3, 0, 0.3, latch), 2)
    p, latch = Math.Page(p, 3, 0, 0, latch) eq(latch, false)
    eq(Math.Page(p, 3, 0, -0.25, latch), 1) eq(Math.Page(1, 3, 0, -0.25, false), 3)
end
local function tool()
    return {Name = "#tool.remover.name", Information = {{name = "left"}, {name = "right"}, {name = "reload"}},
        GetStage = function() return 0 end, GetOperation = function() return 0 end}
end
function cases.tool_info()
    local phrases = {["tool.remover.name"] = "Remover", ["tool.remover.left"] = "Remove", ["tool.remover.right"] = "Remove constraints", ["tool.remover.reload"] = "Remove connected"}
    local info = Math.ToolInfo("remover", tool(), 0, 0, function(s) return phrases[s] or s end)
    eq(info.name, "Remover") eq(info.lines[1], "Trigger: Remove") eq(info.lines[2], "A: Remove constraints") eq(info.lines[3], "B: Remove connected")
end
function cases.tool_stages()
    local t = tool() t.Information = {{name = "left", stage = 0}, {name = "left_1", stage = 1}, {name = "right", op = 2}, {name = "reload", op = 1}}
    local function phrase(s) return s .. " translated" end
    local a, key = Math.ToolInfo("test", t, 0, 2, phrase) local b, other = Math.ToolInfo("test", t, 1, 1, phrase)
    assert(key ~= other) assert(a.lines[1]:find("test.left", 1, true)) assert(b.lines[1]:find("test.left_1", 1, true)) eq(a.lines[3], "B: tool.test.reload translated")
end
function cases.tool_fallback() local info = Math.ToolInfo("missing", {}, 0, 0) eq(#info.lines, 3) eq(info.lines[1], "Trigger: -") end

local now, tick, player, ctx, callbacks, movers, hooks, cleanups, overlays, models
local module
local function init(kind, count, library, beforeStart)
    now, tick, callbacks, movers, hooks, cleanups, overlays = 0, 1, {}, {}, {}, {}, {}
    function IsValid(x) return type(x) == "table" and x.valid == true end
    function CurTime() return now end function RealTime() return now end
    engine = {TickCount = function() return tick end, TickInterval = function() return 1 / 66 end}
    Color = function(r, g, b, a) if type(r) == "table" then return r end return {r = r, g = g, b = b, a = a} end
    color_white = Color(255, 255, 255, 255) TEXT_ALIGN_CENTER = 1
    IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE, IN_FORWARD, IN_BACK, IN_SPEED = 1, 2048, 8192, 32, 8, 16, 131072
    language = {GetPhrase = function(s) if ctx then ctx.phraseCalls = (ctx.phraseCalls or 0) + 1 end return s end}
    surface = {CreateFont = function() end, SetFont = function() end, GetTextSize = function(s) return #s * 10, 20 end}
    function GetConVar(name) return {GetFloat = function() return 10 end, GetBool = function() return ctx.showBeams ~= false end} end
    Material = function(s) if ctx then ctx.materialCalls = (ctx.materialCalls or 0) + 1 end return s end
    render = {SetMaterial = function() end, DrawBeam = function(a, b) ctx.beam = {a, b} end}
    util = {TraceLine = function(t) return {HitPos = t.endpos} end}
    models = {}
    local baseSelection = function() ctx.baseSelectionCalls = (ctx.baseSelectionCalls or 0) + 1 end
    weapons = {GetStored = function(class) if class == "weapon_base" then return {DrawWeaponSelection = baseSelection, WepSelectIcon = 17} end end}
    for i = 1, count or 4 do
        local w = S.Weapon{class = i == 1 and "nlvr_hands" or "weapon_" .. i}
        w.Slot, w.SlotPos, w.PrintName = math.floor(i / 3), i % 3, "Weapon " .. i
        w.DrawWeaponSelection, w.WepSelectIcon = baseSelection, 17
        function w:GetPrintName() return self.PrintName end
        function w:EntIndex() return i end
        function w:GetSlot() return self.Slot end function w:GetSlotPos() return self.SlotPos end
        models[i] = w
    end
    player = S.Player{weapons = models} player.alive = true
    function player:Alive() return self.alive end function player:GetInfo() return self.mode or "remover" end
    function player:GetWeaponColor() return Vector(0.2, 0.6, 1) end
    function LocalPlayer() return player end
    local input = include("nlvr/core/cl_input.lua").New()
    local pose = {valid = true, pos = Vector(20, -10, 48), ang = Angle()}
    ctx = {name = "tools", Debug = {}, Input = input, Pose = {left = pose, right = pose, head = {valid = true, pos = Vector(0, 0, 64), ang = Angle()}},
        Hand = {left = {shown = pose}, right = {shown = pose}}, Space = {scale = 40}, Native = {}, native = {}}
    ctx.core = ctx
    ctx.ToTracking = function(p, a) return p / 40, a end
    ctx.On = function(name, fn) callbacks[name] = fn end
    ctx.mover = function(order, fn) movers[#movers + 1] = {order = order, fn = fn} end
    ctx.hook = function(name, fn) hooks[name] = fn end
    local peers,levels
    hook,peers,levels=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New(library)
    hook.Engine = hook.Call
    ctx.hook = function(name, fn) hooks[name] = fn hook.Add(name, "nlvr.tools", fn) end
    ctx.testHookTables = {plain = peers, levels = levels}
    ctx.cleanup = function(fn) cleanups[#cleanups + 1] = fn end
    local receives = {}
    ctx.Net = {On = function(n, fn) receives[n] = fn end, Send = function(n, fn) end}
    ctx.receives = receives
    ctx.Weapon = {Active = {ent = models[2], kind = kind or "hands", hand = "right"},
        ConvergeAt = function(n) ctx.convergence = n end, Muzzle = function() return Vector(22, -10, 48), Angle() end,
        Ray = function() return Vector(22, -10, 48), Vector(1, 0, 0) end}
    models[2].tool = tool()
    models[2].GetToolObject = function() return models[2].tool end
    ctx.Overlay = {Sizes = {wheel = {1035, 1037}, tool = {643, 133}}, New = function(opts)
        local o = opts o.handle, o.dirty, o.invalidations = #overlays + 1, true, 0
        function o:Show(v) self.visible = v end
        function o:Place(device, p, a, m) self.device, self.pos, self.ang, self.metres = device, p, a, m end
        function o:Invalidate() self.invalidations = self.invalidations + 1 self.dirty = true end
        function o:Destroy() self.destroyed = true self.visible = false end
        overlays[#overlays + 1] = o return o
    end}
    if beforeStart then beforeStart(ctx) end
    module = include("nlvr/modules/cl_tools.lua") module.Start(ctx)
    return ctx
end
local function frame(time, controls, owner)
    now, tick = time, tick + 1
    local actions = {}
    for key, value in pairs(controls or {}) do
        actions[key] = type(value) == "table" and {active = true, x = value.x, y = value.y} or {active = true, state = value}
    end
    ctx.Input.Update(actions, now, ctx.leftDominant)
    if owner then ctx.Input.Claim("main", "stick", owner) end
    callbacks.frame()
end
local function move(buttons, number)
    local cmd = S.Command() cmd:SetButtons(buttons or 0)
    function cmd:CommandNumber() return number == nil and 1 or number end
    function cmd:SetMouseX(n) self.mx = n end function cmd:SetMouseY(n) self.my = n end
    table.sort(movers, function(a, b) return a.order < b.order end)
    for _, m in ipairs(movers) do m.fn(cmd) end
    return cmd
end
function cases.tool_repaint() init("toolgun") frame(0) local o = overlays[1] local n = o.invalidations frame(1) eq(o.invalidations, n) player.mode = "colour" frame(2) assert(o.invalidations > n) end
function cases.tool_switch() init("toolgun") frame(0) eq(ctx.Debug.tools.tool.mode, "remover") player.mode = "colour" frame(1) eq(ctx.Debug.tools.tool.mode, "colour") end
function cases.tool_model_anchor()
    init("toolgun")
    local model = S.Model{pos = Vector(100, 120, 200), ang = Angle(0, 90, 0), bones = {{name = "ValveBiped.Bip01_R_Hand", pos = Vector(5, 0, 2)}}}
    model:SetupBones() ctx.Weapon.Active.model = model frame(0.1)
    vec(ctx.Debug.tools.tool_anchor, Vector(100, 125, 202))
    model:SetPos(Vector(110, 120, 200)) frame(0.2)
    vec(ctx.Debug.tools.tool_anchor, Vector(110, 125, 202))
end
function cases.tool_left()
    init("toolgun") frame(0.1) local right = overlays[1].pos
    ctx.leftDominant, ctx.Weapon.Active.hand = true, "left" frame(0.2)
    local left = overlays[1].pos
    near((left - right):Length(), 0.38)
    eq(overlays[1].visible, true)
end
function cases.tool_hide() init("toolgun") frame(0) eq(overlays[1].visible, true) ctx.Weapon.Active.kind = "clip" frame(1) eq(overlays[1].visible, false) end
function cases.wheel_hold() init() frame(0, {right_b = true}) frame(0.301, {right_b = true}) eq(ctx.Debug.tools.wheel.open, true) eq(overlays[1].width, 1035) eq(overlays[1].height, 1037) end
function cases.wheel_tap() init() frame(0, {right_b = true}) frame(0.2) eq(ctx.Debug.tools.wheel.open, false) eq(#overlays, 0) eq(ctx.Input.Tapped("main", "b"), true) end
local function open() init() frame(0, {right_b = true}) frame(0.31, {right_b = true}) end
function cases.wheel_select()
    open() ctx.Pose.right = {valid = true, pos = ctx.Pose.right.pos + Vector(0, 0, 6), ang = Angle()}
    frame(0.4, {right_b = true}) eq(ctx.Debug.tools.wheel.highlighted, 1)
    frame(0.5) local command = move() eq(command.selected:GetClass(), "nlvr_hands") eq(player:GetActiveWeapon().valid, false)
    player:SelectWeapon("nlvr_hands") eq(move().selected, nil)
end
function cases.wheel_prediction_retry()
    open() ctx.Pose.right = {valid = true, pos = ctx.Pose.right.pos + Vector(0, 0, 6), ang = Angle()}
    frame(0.4, {right_b = true}) frame(0.5)
    eq(move(0, 0).selected, nil)
    eq(move(0, 1).selected:GetClass(), "nlvr_hands")
    eq(move(0, 2).selected, nil)
    player:SelectWeapon("nlvr_hands") eq(move(0, 3).selected, nil)
end
function cases.wheel_refused_once()
    open() ctx.Pose.right = {valid = true, pos = ctx.Pose.right.pos + Vector(0, 0, 6), ang = Angle()}
    frame(0.4, {right_b = true}) frame(0.5)
    local attempts = 0
    for i = 1, 66 do if move(0, i).selected then attempts = attempts + 1 end end
    eq(attempts, 1)
    frame(1.6) move(0, 67)
    eq(ctx.Debug.tools.wheel.selection_error, "refused")
    assert(overlays[1].visible and ctx.Debug.tools.wheel.notice)
end
function cases.wheel_custom_icon()
    init() local calls, clip, unclips, failing = 0, nil, 0, false
    render.SetScissorRect = function(x, y, right, bottom, enabled)
        if enabled then clip = {x = x, y = y, right = right, bottom = bottom}
        else clip = nil unclips = unclips + 1 end
    end
    models[2].DrawWeaponSelection = function(self, x, y, w, h, alpha)
        calls = calls + 1 eq(self, models[2]) assert(w > 0 and h > 0) eq(alpha, 255)
        assert(clip, "custom selection drawing must stay inside its icon")
        eq(clip.x, x) eq(clip.y, y) eq(clip.right, x + w) eq(clip.bottom, y + h)
        if failing then error("intentional selection icon failure") end
    end
    frame(0, {right_b = true}) frame(0.31, {right_b = true})
    surface.SetDrawColor, surface.DrawRect, surface.SetTexture, surface.DrawTexturedRect = function() end, function() end, function() end, function() end
    draw = {SimpleText = function() end}
    overlays[1].paint(nil, 1035, 1037) eq(calls, 1) eq(clip, nil) assert(unclips > 0)
    failing = true
    overlays[1].paint(nil, 1035, 1037) eq(calls, 2) eq(clip, nil) eq(unclips, 2)
end
function cases.tool_use_modifier()
    local t = tool() t.Information = {{name = "left"}, {name = "left_use"}, {name = "right_use"}}
    local info = Math.ToolInfo("test", t, 0, 0, function(s) return s end)
    assert(not info.lines[1]:find("left_use", 1, true)) assert(not info.lines[2]:find("right_use", 1, true))
end
function cases.wheel_selection_expiry()
    open() ctx.Pose.right = {valid = true, pos = ctx.Pose.right.pos + Vector(0, 0, 6), ang = Angle()}
    frame(0.4, {right_b = true}) frame(0.5) eq(move(0, 0).selected, nil)
    frame(2) eq(move(0, 1).selected, nil)
end
function cases.wheel_cancel() open() frame(0.4) eq(move().selected, nil) end
function cases.wheel_death() open() player.alive = false frame(0.4, {right_b = true}) eq(ctx.Debug.tools.wheel.open, false) eq(overlays[1].visible, false) eq(move().selected, nil) end
function cases.wheel_many()
    init(nil, 29) frame(0, {right_b = true}) frame(0.31, {right_b = true}) eq(ctx.Debug.tools.wheel.pages, 3)
    ctx.Pose.right = {valid = true, pos = ctx.Pose.right.pos + ctx.Debug.tools.wheel.angle:Up() * 11, ang = Angle()}
    frame(0.4, {right_b = true}) eq(ctx.Debug.tools.wheel.page, 2) frame(0.5, {right_b = true}) eq(ctx.Debug.tools.wheel.page, 2)
end
function cases.wheel_claims() open() eq(ctx.Input.Owner("main", "trigger"), "tools") eq(move(IN_ATTACK + IN_ATTACK2 + IN_RELOAD + 4):GetButtons(), 4) end
function cases.wheel_trigger_release()
    open() frame(0.4, {right_b = true, right_trigger = true}) eq(move(IN_ATTACK):GetButtons(), 0)
    frame(0.5, {right_trigger = true}) eq(move(IN_ATTACK):GetButtons(), 0)
    frame(0.55, {right_trigger = true}) eq(move(IN_ATTACK):GetButtons(), 0)
    eq(ctx.Input.Owner("main", "trigger"), "tools")
    frame(0.6) eq(move(IN_ATTACK):GetButtons(), IN_ATTACK)
end
function cases.wheel_reacquire()
    open() ctx.Pose.right.valid = false frame(0.4, {right_b = true})
    ctx.Pose.right.valid = true frame(0.5, {right_b = true}) eq(ctx.Debug.tools.wheel.open, false)
    frame(0.6) frame(0.7, {right_b = true}) frame(1.1, {right_b = true}) eq(ctx.Debug.tools.wheel.open, true)
end
function cases.wheel_cancel_trigger_claim()
    open() frame(0.4, {right_b = true, right_trigger = true})
    ctx.Pose.right.valid = false frame(0.5, {right_trigger = true})
    eq(ctx.Debug.tools.wheel.open, false) eq(ctx.Input.Owner("right", "trigger"), "tools")
    frame(0.6) eq(ctx.Input.Owner("right", "trigger"), nil)
end
function cases.wheel_mirror_trigger_claim()
    open() frame(0.4, {right_b = true, right_trigger = true})
    ctx.leftDominant = true frame(0.5, {right_trigger = true})
    eq(ctx.Debug.tools.wheel.open, false) eq(ctx.Input.Owner("right", "trigger"), "tools")
    frame(0.6) eq(ctx.Input.Owner("right", "trigger"), nil)
end
function cases.wheel_weapon_claim()
    init("physgun") frame(0, {right_b = true})
    ctx.Input.Update({right_b = {active = true, state = true}}, 0.31, false)
    ctx.Input.Claim("main", "trigger", "weapons") callbacks.frame()
    eq(ctx.Input.Owner("main", "trigger"), "weapons") eq(move(IN_ATTACK):GetButtons(), 0)
end
function cases.tool_button_passthrough()
    for _, kind in ipairs({"physgun", "toolgun"}) do
        init(kind) frame(0, {right_b = true, right_a = true})
        ctx.Input.Update({right_a = {active = true, state = true}}, 0.2, false)
        ctx.Input.Claim("main", "trigger", "weapons") ctx.Input.Claim("main", "grip", "weapons")
        ctx.Input.Claim("main", "b", "reload") callbacks.frame()
        eq(ctx.Input.Owner("main", "a"), nil) eq(ctx.Input.Owner("main", "b"), "reload")
        eq(ctx.Input.Owner("main", "trigger"), "weapons") eq(ctx.Input.Owner("main", "grip"), "weapons")
        eq(ctx.Debug.tools.wheel.open, false)
        eq(move(IN_ATTACK + IN_ATTACK2 + IN_RELOAD):GetButtons(), IN_ATTACK + IN_ATTACK2 + IN_RELOAD)
    end
end
function cases.wheel_reload_a_claim()
    init("clip") frame(0, {right_b = true, right_a = true})
    ctx.Input.Update({right_b = {active = true, state = true}, right_a = {active = true, state = true}}, 0.31, false)
    ctx.Input.Claim("main", "trigger", "weapons") ctx.Input.Claim("main", "a", "reload") callbacks.frame()
    eq(ctx.Debug.tools.wheel.open, true) eq(ctx.Input.Owner("main", "a"), "reload")
    eq(ctx.Input.Owner("main", "trigger"), "weapons") eq(ctx.Input.Owner("main", "b"), "tools")
    eq(move(IN_ATTACK + IN_ATTACK2 + IN_RELOAD):GetButtons(), 0)
    ctx.Input.Update({right_a = {active = true, state = true}}, 0.4, false)
    ctx.Input.Claim("main", "a", "reload") callbacks.frame()
    eq(ctx.Debug.tools.wheel.open, false) eq(ctx.Input.Owner("main", "a"), "reload")
    eq(move(IN_ATTACK2):GetButtons(), IN_ATTACK2)
end
function cases.wheel_pending_b_claim()
    init("physgun") frame(0, {right_b = true})
    ctx.Input.Update({right_b = {active = true, state = true}}, 0.31, false)
    ctx.Input.Claim("main", "b", "reload") callbacks.frame()
    eq(ctx.Debug.tools.wheel.open, false) eq(#overlays, 0)
    eq(move(IN_RELOAD):GetButtons(), IN_RELOAD)
    ctx.Input.Update({right_b = {active = true, state = true}}, 0.4, false) callbacks.frame()
    eq(ctx.Debug.tools.wheel.open, true) eq(ctx.Input.Owner("main", "b"), "tools")
end
function cases.wheel_lost_b_claim()
    open()
    ctx.Input.Update({right_b = {active = true, state = true}}, 0.4, false)
    ctx.Input.Claim("main", "b", "reload") callbacks.frame()
    eq(ctx.Debug.tools.wheel.open, false) eq(move(IN_RELOAD):GetButtons(), IN_RELOAD)
    ctx.Input.Update({right_b = {active = true, state = true}}, 0.5, false) callbacks.frame()
    eq(ctx.Debug.tools.wheel.open, false)
end
function cases.wheel_inventory_change() open() models[2].valid = false frame(0.4, {right_b = true}) eq(#ctx.Debug.tools.wheel.entries, 3) end
function cases.wheel_mirror() open() ctx.leftDominant = true frame(0.4) eq(ctx.Debug.tools.wheel.open, false) eq(move().selected, nil) end
function cases.wheel_left_selection()
    init() ctx.leftDominant = true frame(0, {left_b = true}) frame(0.31, {left_b = true})
    eq(ctx.Debug.tools.wheel.open, true) eq(ctx.Input.Owner("left", "trigger"), "tools")
    ctx.Pose.left = {valid = true, pos = ctx.Pose.left.pos + ctx.Debug.tools.wheel.angle:Up() * 6, ang = Angle()}
    frame(0.4, {left_b = true}) eq(ctx.Debug.tools.wheel.highlighted, 1)
    frame(0.5) eq(move().selected:GetClass(), "nlvr_hands")
end
local function receipt(ent, distance)
    local values = {ent, 0, Vector(), distance, Angle(0, 90, 0), Angle(0, 88, 0), Angle(0, 90, 0), 2}
    local i = 0 local function read() i = i + 1 return values[i] end
    net = {ReadEntity = read, ReadUInt = read, ReadVector = read, ReadFloat = read, ReadAngle = read}
    ctx.receives[96]()
end
function cases.q5_ladder_distance()
    MOVETYPE_LADDER=9 init("physgun") player.GetMoveType=function() return MOVETYPE_LADDER end
    receipt(models[3],80) frame(.1)
    local climb=move(IN_FORWARD)
    assert(not climb:KeyDown(IN_USE),"climbing pushed held prop with neutral main stick")
    for _,direction in ipairs({1,-1}) do
        frame(direction>0 and .3 or .5,{right_stick={x=0,y=direction}})
        local c=move()
        assert(c:KeyDown(IN_USE) and c:KeyDown(direction>0 and IN_FORWARD or IN_BACK),"ladder lost distance command")
    end
end
function cases.held_distance() init("physgun") receipt(models[3], 80) frame(0.1) eq(ctx.convergence, 80) eq(ctx.Debug.tools.physgun.distance, 2) eq(ctx.Input.Owner("main", "stick"), "tools") end
function cases.stick_drop_latch()
    for _, axis in ipairs({{x = 0, y = 1}, {x = 0, y = -1}, {x = 0.8, y = 0.8}}) do
        init("physgun") receipt(models[3], 80) frame(0.1, {right_stick = axis})
        receipt({valid = false}, 0) frame(0.2, {right_stick = axis})
        eq(ctx.Input.Owner("main", "stick"), "tools")
        local cmd = move() assert(not cmd:KeyDown(IN_USE) and not cmd:KeyDown(IN_FORWARD) and not cmd:KeyDown(IN_BACK))
        frame(0.3, {right_stick = {x = 0.1, y = 0.1}}) eq(ctx.Input.Owner("main", "stick"), nil)
        module.Stop()
    end
end
function cases.drop_trigger_rearm()
    init("physgun") receipt(models[3], 80) frame(0.1, {right_trigger = true})
    receipt({valid = false}, 0) frame(0.2, {right_trigger = true})
    eq(ctx.Debug.tools.physgun.entity, 0) eq(ctx.Input.Owner("main", "trigger"), "tools")
    eq(move(IN_ATTACK):GetButtons(), 0)
    frame(0.3) eq(ctx.Input.Owner("main", "trigger"), nil)
end
function cases.stick_tracking_latch()
    init("physgun") receipt(models[3], 80) frame(0.1, {right_stick = {x = 0, y = 1}})
    ctx.Pose.right.valid = false frame(0.2, {right_stick = {x = 0, y = 1}})
    eq(ctx.Input.Owner("main", "stick"), "tools") assert(not move():KeyDown(IN_USE))
    receipt({valid = false}, 0) ctx.Pose.right.valid = true frame(0.3, {right_stick = {x = 0, y = 1}})
    eq(ctx.Input.Owner("main", "stick"), "tools")
    frame(0.4) eq(ctx.Input.Owner("main", "stick"), nil)
end
function cases.stick_mirror_latch()
    init("physgun") receipt(models[3], 80) frame(0.1, {right_stick = {x = 0, y = 1}})
    ctx.leftDominant, ctx.Weapon.Active.hand = true, "left"
    receipt({valid = false}, 0) frame(0.2, {right_stick = {x = 0, y = 1}})
    eq(ctx.Input.Owner("right", "stick"), "tools")
    frame(0.3) eq(ctx.Input.Owner("right", "stick"), nil)
end
function cases.held_unchanged() init("physgun") receipt(models[3], 80) frame(10) eq(ctx.convergence, 80) eq(ctx.Input.Owner("main", "stick"), "tools") end
function cases.held_tracking_lost()
    init("physgun") receipt(models[3], 80) ctx.Pose.right.valid = false frame(0.1)
    eq(ctx.convergence, nil) eq(ctx.Input.Owner("main", "stick"), "tools") eq(ctx.Debug.tools.physgun.tracked, false)
    assert(not move():KeyDown(IN_USE))
    -- A one-render loss can occur between sync ticks. Retain the authoritative snapshot,
    -- with controls inactive, until the reliable server drop or a valid pose returns.
    ctx.Pose.right.valid = true frame(0.2)
    eq(ctx.convergence, 80) eq(ctx.Input.Owner("main", "stick"), "tools")
end
function cases.held_entity_removed() init("physgun") receipt(models[3], 80) models[3].valid = false frame(0.1) eq(ctx.convergence, nil) eq(ctx.Input.Owner("main", "stick"), nil) end
function cases.stick_owner()
    init("physgun") receipt(models[3], 80) frame(0.1, {right_stick = {x = 0, y = 1}}, "ui")
    local cmd = move()
    assert(not cmd:KeyDown(IN_USE) and not cmd:KeyDown(IN_FORWARD) and not cmd:KeyDown(IN_BACK))
    eq(ctx.Input.Owner("main", "stick"), "ui")
end
function cases.stick_frame_rate()
    for _, hz in ipairs({30, 66, 90, 120}) do
        init("physgun") local commanded, elapsed = 0, 0
        for i = 1, hz do
            receipt(models[3], 80) frame(i / hz, {right_stick = {x = 0, y = 0.6}})
            local cmd = move() assert(cmd:KeyDown(IN_USE)) assert(not cmd:KeyDown(IN_BACK))
            local dt = i == 1 and 1 / 66 or 1 / hz
            if cmd:KeyDown(IN_FORWARD) then commanded = commanded + dt end
            elapsed = elapsed + dt
        end
        near(commanded, elapsed * 0.5, math.max(1 / hz, 1 / 66) + 0.00001)
        module.Stop()
    end
end
function cases.beam() init("physgun") frame(0.1) eq(hook.Run("DrawPhysgunBeam", player, models[2], true, nil, 0, Vector()), false) vec(ctx.beam[1], Vector(22, -10, 48)) eq(hook.Run("DrawPhysgunBeam", {}, models[2], true), nil) end
function cases.beam_hidden()
    init("physgun") frame(0.1)
    ctx.showBeams = false
    eq(hook.Run("DrawPhysgunBeam", player, models[2], true, nil, 0, Vector()), false) eq(ctx.beam, nil)
end
function cases.beam_addon_hooks()
    init("physgun") frame(0.1) local calls = 0
    hook.Add("DrawPhysgunBeam", "peer-one", function() calls = calls + 1 end)
    hook.Add("DrawPhysgunBeam", "peer-two", function() calls = calls + 1 end)
    eq(hook.Run("DrawPhysgunBeam", player, models[2], true, nil, 0, Vector()), false) eq(calls, 2)
    eq(hook.Call("DrawPhysgunBeam", nil, player, models[2], true, nil, 0, Vector()), false) eq(calls, 4)
    module.Stop() hook.Run("DrawPhysgunBeam", player, models[2], true, nil, 0, Vector()) eq(calls, 6)
end
function cases.beam_cached_dispatch()
    init("physgun") frame(0.1) local calls = 0
    hook.Add("DrawPhysgunBeam", "peer", function() calls = calls + 1 end)
    eq(hook.Engine("DrawPhysgunBeam", nil, player, models[2], true, nil, 0, Vector()), false)
    eq(calls, 1) assert(ctx.beam)
end
local function registryLifecycle(library, existing)
    local beforePlain, beforeLevels, peer, calls
    calls = 0
    init("physgun", nil, library, function()
        if existing then
            peer = function() calls = calls + 1 end
            hook.Add("DrawPhysgunBeam", "peer", peer, HOOK_MONITOR_LOW)
        end
        beforePlain, beforeLevels = hook.GetTable().DrawPhysgunBeam, hook.GetULibTable and hook.GetULibTable().DrawPhysgunBeam
    end)
    for run = 1, 2 do
        if run == 2 then
            beforePlain,beforeLevels=hook.GetTable().DrawPhysgunBeam,hook.GetULibTable and hook.GetULibTable().DrawPhysgunBeam
            module.Start(ctx)
        end
        frame(run / 10)
        eq(hook.Engine("DrawPhysgunBeam", nil, player, models[2], true, nil, 0, Vector()), false)
        assert(ctx.beam, "ordinary fallback must draw without failing Start")
        module.Stop()
        if library == "ulib" then
            local after=hook.GetTable().DrawPhysgunBeam or {}
            if existing then eq(next(after),"peer") eq(after.peer,peer) else eq(next(after),nil) end
            eq(hook.GetULibTable().DrawPhysgunBeam, beforeLevels)
            if existing then
                eq(next(beforePlain), "peer") eq(beforePlain.peer, peer)
                for n = -2, 2 do
                    if n == HOOK_MONITOR_LOW then eq(beforeLevels[n].peer.fn, peer) eq(next(beforeLevels[n]), "peer")
                    else eq(next(beforeLevels[n]), nil) end
                end
            end
            eq(hook.GetTable().NLVRToolsBeamRegistryProbe, nil)
            eq(hook.GetULibTable().NLVRToolsBeamRegistryProbe, nil)
        end
        ctx.beam = nil
        hook.Engine("DrawPhysgunBeam", nil, player, models[2], true, nil, 0, Vector())
        eq(ctx.beam, nil)
        hook.Add("DrawPhysgunBeam","late_after_exit",function() end)
        hook.Remove("DrawPhysgunBeam","late_after_exit")
    end
    if library == "ulib" and existing then eq(calls, 4) end
end
function cases.beam_ulib_empty() registryLifecycle("ulib", false) end
function cases.beam_ulib_existing() registryLifecycle("ulib", true) end
function cases.beam_unknown_library() registryLifecycle("unknown", false) end
function cases.beam_rendered_attachment()
    init("physgun") frame(0.1)
    local model = S.Model{}
    function model:LookupAttachment() return 1 end
    function model:GetAttachment() return {Pos = Vector(30, -10, 48), Ang = Angle()} end
    ctx.Weapon.Active.model = model
    hook.Engine("DrawPhysgunBeam", nil, player, models[2], true, nil, 0, Vector())
    vec(ctx.beam[1], Vector(30, -10, 48))
end
function cases.beam_material_cached()
    init("physgun") frame(0.1)
    hook.Run("DrawPhysgunBeam", player, models[2], true, nil, 0, Vector())
    local count, debug = ctx.materialCalls, ctx.Debug.tools.beam
    for _ = 1, 100 do hook.Run("DrawPhysgunBeam", player, models[2], true, nil, 0, Vector()) end
    eq(ctx.materialCalls, count) eq(ctx.Debug.tools.beam, debug)
end
function cases.debug_reused()
    init("toolgun") frame(0)
    local debug, wheel, entries = ctx.Debug.tools, ctx.Debug.tools.wheel, ctx.Debug.tools.wheel.entries
    for i = 1, 100 do frame(i / 1000) end
    eq(ctx.Debug.tools, debug) eq(ctx.Debug.tools.wheel, wheel) eq(ctx.Debug.tools.wheel.entries, entries)
end
function cases.tool_info_cached()
    init("toolgun") frame(0) local count = ctx.phraseCalls
    for i = 1, 100 do frame(i / 1000) end
    eq(ctx.phraseCalls, count)
end
function cases.tool_native_calls_cached()
    init("toolgun") frame(0) local o = overlays[1]
    local places, shows = 0, 0
    local oldPlace, oldShow = o.Place, o.Show
    function o:Place(...) places = places + 1 return oldPlace(self, ...) end
    function o:Show(...) shows = shows + 1 return oldShow(self, ...) end
    for i = 1, 100 do frame(i / 1000) end
    eq(places, 0) eq(shows, 0)
    ctx.Weapon.Active.kind = "hands" frame(1) local hidden = shows
    for i = 1, 100 do frame(1 + i / 1000) end
    eq(shows, hidden)
end
function cases.tool_native_calls_moving()
    init("toolgun") frame(0) local o, places = overlays[1], 0
    local oldPlace, initial = o.Place, ctx.Pose.right.pos
    function o:Place(...) places = places + 1 return oldPlace(self, ...) end
    for i = 1, 100 do
        ctx.Pose.right.pos = initial + Vector(i * 0.004, 0, 0)
        frame(i / 90)
    end
    assert(places >= 3 and places <= 20, "moving hand should coalesce submillimetre placements: " .. places)
end
function cases.presentation_tolerance()
    init() local calls, p, a = 0
    local display = include("nlvr/modules/cl_tools_presentation.lua").New({Place = function(_, _, pos, ang)
        calls, p, a = calls + 1, Vector(pos.x, pos.y, pos.z), Angle(ang.p, ang.y, ang.r)
    end})
    display.Place(Vector(), Angle(0, 179.98, 0), 0.3)
    display.Place(Vector(0.0002, 0, 0), Angle(0, -179.98, 0), 0.3) eq(calls, 1)
    for i = 1, 100 do
        local target = Vector(i * 0.0001, 0, 0)
        display.Place(target, Angle(0, -179.98, 0), 0.3)
        assert((target - p):Length() <= 0.00101)
    end
    assert(calls >= 9 and calls <= 12)
    display.Place(p, Angle(0, -179.7, 0), 0.3) eq(a.y, -179.7)
    local before = calls display.Place(p, a, 0.4) eq(calls, before + 1)
end
function cases.wheel_hands_base_icon()
    init() local handsGlyph = false
    frame(0, {right_b = true}) frame(0.31, {right_b = true})
    surface.SetDrawColor, surface.DrawRect, surface.SetTexture, surface.DrawTexturedRect = function() end, function() end, function() end, function() end
    render.SetScissorRect = function() end
    draw = {SimpleText = function(text) if text == "[ ]" then handsGlyph = true end end}
    overlays[1].paint(nil, 1035, 1037)
    eq(ctx.baseSelectionCalls or 0, 0) assert(handsGlyph, "Hands needs its own glyph, not weapon_base's icon")
end
function cases.wheel_inventory_cached()
    open() local reads = 0 local old = player.GetWeapons
    function player:GetWeapons() reads = reads + 1 return old(self) end
    for i = 1, 50 do frame(0.32 + i / 1000, {right_b = true}) end
    eq(reads, 0)
end
function cases.cleanup() init("toolgun") frame(0.1) module.Stop() eq(ctx.Tools, nil) eq(ctx.Debug.tools, nil) eq(overlays[1].destroyed, true) module.Stop() end

local function server()
    init("physgun")
    local phys = {valid = true, pos = Vector(100, -10, 48), ang = Angle()}
    function phys:GetPos() return self.pos end function phys:GetAngles() return self.ang end
    function phys:GetVelocity() return self.velocity or Vector() end
    function phys:GetVelocityAtPoint() return self.pointVelocity or self.velocity or Vector() end
    function phys:ComputeShadowControl(params) self.shadow = params end
    local controllers = {}
    _G.player = {GetAll = function() return {player} end}
    ents = {Create = function()
        local e = {valid = true} controllers[#controllers + 1] = e
        function e:SetNoDraw(v) self.noDraw = v end function e:SetNotSolid(v) self.notSolid = v end
        function e:SetPreventTransmit() self.hidden = true end function e:Spawn() self.spawned = true end
        function e:StartMotionController() self.motion = true end function e:AddToMotionController(p) self.body = p end
        function e:StopMotionController() self.motion = false end function e:Remove() self.valid = false end
        return e
    end}
    MsgN = function(text) error(text) end
    local ent = {valid = true, held = true}
    function ent:GetPhysicsObjectNum() return phys end function ent:IsPlayerHolding() return self.held end function ent:EntIndex() return 33 end
    function player:GetEyeTrace() return {Entity = ent, PhysicsBone = 0, HitPos = phys.pos} end
    function player:EntIndex() return 1 end
    function player:DropObject() self.useDropped = true ent.held = false self.dropped = true end
    function player:KeyDown(key) return bit.band(self.keys or 0, key) ~= 0 end
    function player:GetInfoNum(name, default) return name == "gm_snapangles" and 45 or default end
    function ent:ForcePlayerDrop() self.held = false player.dropped = true end
    svLimits = {physgun_timeToArrive = 0.05, physgun_maxAngular = 5000, physgun_maxAngularDamping = 10000,
        physgun_maxSpeed = 5000, physgun_maxSpeedDamping = 10000, physgun_DampingFactor = 1}
    GetConVar = function(name) return {GetFloat = function() return svLimits[name] or 0 end} end
    local pose = {valid = true, pos = Vector(20, -10, 48), ang = Angle()}
    local state = {scale = 40, hands = {right = pose, left = pose}}
    local sv = {name = "tools", Players = {[player] = state}, Debug = {}, core = {}}
    sv.On, sv.hook, sv.cleanup = ctx.On, ctx.hook, ctx.cleanup
    sv.Weapon = function() return {kind = "physgun", muzzle = {pos = Vector(22, -10, 48), ang = Angle()}} end
    sv.Net = {On = ctx.Net.On, Send = function(p, n, writer) sv.sent = (sv.sent or 0) + 1 end}
    sv.controllers = controllers
    local m = include("nlvr/modules/sv_tools.lua") m.Start(sv)
    return sv, state, ent, phys, m
end
function cases.rotation_params()
    local sv, state, ent, phys, m = server()
    phys.velocity = Vector(80, 30, -5)
    local p = include("nlvr/modules/sv_tools_rotation.lua").Parameters(phys, Angle(12, 34, 56), 0.015)
    vec(p.pos, Vector(104, -8.5, 47.75)) near(p.angle.p, 12) near(p.angle.y, 34) near(p.angle.r, 56)
    eq(p.teleportdistance, 0) near(p.delta, 0.015)
    m.Stop()
end
function cases.rotation_server_limits()
    local sv, state, ent, phys, m = server()
    svLimits.physgun_timeToArrive, svLimits.physgun_maxAngular, svLimits.physgun_maxAngularDamping = 0.2, 125, 250
    local p = include("nlvr/modules/sv_tools_rotation.lua").Parameters(phys, Angle(), 0.015)
    near(p.secondstoarrive, 0.2) eq(p.maxangular, 125) eq(p.maxangulardamp, 250)
    svLimits.physgun_maxAngular = 0
    p = include("nlvr/modules/sv_tools_rotation.lua").Parameters(phys, Angle(), 0.015)
    eq(p.maxangular, 0) m.Stop()
end
function cases.rotation_damping_factor()
    local sv, state, ent, phys, m = server()
    local rotation = include("nlvr/modules/sv_tools_rotation.lua")
    svLimits.physgun_DampingFactor = 0.35
    near(rotation.Parameters(phys, Angle(), 0.015).dampfactor, 0.35)
    svLimits.physgun_DampingFactor = 0.6
    near(rotation.Parameters(phys, Angle(), 0.015).dampfactor, 0.6) m.Stop()
end
function cases.rotation_damped_residual()
    local sv, state, ent, phys, m = server()
    svLimits.physgun_DampingFactor = 0.8
    hooks.OnPhysgunPickup(player, ent) state.hands.right.ang = Angle(0, 0, 90)
    -- Independent toy plant reproduces the measured native 90 -> 75 degree equilibrium.
    -- This tests feedback, not Source physics; the unchanged PoC <5-degree gate is decisive.
    for _ = 1, 160 do
        sv.controllers[1].PhysicsSimulate(sv.controllers[1], phys, 0.015)
        near(phys.shadow.dampfactor, 0.8) eq(phys.shadow.maxangular, 5000)
        phys.ang.r = phys.ang.r + 0.4 * (phys.shadow.angle.r / 1.2 - phys.ang.r)
    end
    assert(Math.AngleError(phys.ang, Angle(0, 0, 90)) < 1, "uncompensated native damping residual")
    state.hands.right.ang = Angle()
    sv.controllers[1].PhysicsSimulate(sv.controllers[1], phys, 0.015)
    near(Math.AngleError(phys.shadow.angle, Angle()), 0, 0.001) m.Stop()
end
function cases.rotation_feedback_bound()
    local sv, state, ent, phys, m = server()
    svLimits.physgun_DampingFactor = 0.8
    hooks.OnPhysgunPickup(player, ent) state.hands.right.ang, phys.ang = Angle(0, 0, 90), Angle(0, 0, 65)
    for _ = 1, 100 do sv.controllers[1].PhysicsSimulate(sv.controllers[1], phys, 0.015) end
    assert(Math.AngleError(phys.shadow.angle, Angle(0, 0, 90)) <= 30.001)
    svLimits.physgun_maxAngular = 0
    sv.controllers[1].PhysicsSimulate(sv.controllers[1], phys, 0.015)
    near(Math.AngleError(phys.shadow.angle, Angle(0, 0, 90)), 0, 0.001) m.Stop()
end
function cases.rotation_native_snap()
    local sv, state, ent, phys, m = server() hooks.OnPhysgunPickup(player, ent)
    state.hands.right.ang = Angle(0, 37, 0) player.keys = 131072
    sv.controllers[1].PhysicsSimulate(sv.controllers[1], phys, 0.015)
    near(phys.shadow.angle.y, 45)
    player.keys = 0 sv.controllers[1].PhysicsSimulate(sv.controllers[1], phys, 0.015)
    near(phys.shadow.angle.y, 37) m.Stop()
end
function cases.rotation_origin_velocity()
    local sv, state, ent, phys, m = server()
    phys.velocity, phys.pointVelocity = Vector(100, 0, 0), Vector(5, 6, 7)
    local p = include("nlvr/modules/sv_tools_rotation.lua").Parameters(phys, Angle(), 0.015)
    vec(p.pos, phys.pos + phys.pointVelocity * 0.05) m.Stop()
end
function cases.rotation_no_linear_force()
    local sv, state, ent, phys, m = server()
    local p = include("nlvr/modules/sv_tools_rotation.lua").Parameters(phys, Angle(), 0.015)
    eq(p.maxspeed, 0) eq(p.maxspeeddamp, 0) m.Stop()
end
function cases.server_failed_creation_drop()
    local sv, state, ent, phys, m = server()
    MsgN = function() end ents.Create = function() return {valid = false} end
    hooks.OnPhysgunPickup(player, ent)
    hooks.Tick()
    eq(ent.held, false) eq(player.useDropped, nil)
    assert(sv.sent and sv.sent > 0) m.Stop()
end
function cases.server_creation_before_native_attach()
    local sv, state, ent, phys, m = server()
    MsgN = function() end ents.Create = function() return {valid = false} end
    ent.held = false hooks.OnPhysgunPickup(player, ent)
    -- Native IsPlayerHolding becomes true after the successful-pickup Lua hook returns.
    ent.held = true hooks.Tick()
    eq(ent.held, false) m.Stop()
end
function cases.server_drop_rearm()
    local sv, state, ent, phys, m = server() state.hands.right.buttons = 2
    hooks.OnPhysgunPickup(player, ent) state.hands.right.valid = false hooks.Tick()
    state.hands.right.valid = true
    local cmd = S.Command() cmd:SetButtons(IN_ATTACK) hooks.StartCommand(player, cmd)
    assert(not cmd:KeyDown(IN_ATTACK))
    state.hands.right.buttons = 0 cmd:SetButtons(IN_ATTACK) hooks.StartCommand(player, cmd)
    assert(not cmd:KeyDown(IN_ATTACK))
    cmd:SetButtons(0) hooks.StartCommand(player, cmd)
    state.hands.right.buttons = 2 cmd:SetButtons(IN_ATTACK) hooks.StartCommand(player, cmd)
    assert(cmd:KeyDown(IN_ATTACK)) m.Stop()
end
function cases.rotation_lifecycle()
    local sv, state, ent, phys, m = server() hooks.OnPhysgunPickup(player, ent)
    local c = sv.controllers[1] assert(c.spawned and c.motion and c.hidden and c.notSolid and c.noDraw)
    eq(c.body, phys) state.hands.right.ang = Angle(12, 34, 56)
    c.PhysicsSimulate(c, phys, 0.015)
    near(Math.AngleError(phys.shadow.angle, Angle(12, 34, 56)), 0, 0.00001)
    hooks.PhysgunDrop(player) eq(c.valid, false) eq(c.motion, false) eq(phys.valid, true)
    m.Stop()
end
function cases.rotation_failure()
    local sv, state, ent, phys, m = server() hooks.OnPhysgunPickup(player, ent)
    local c, errors = sv.controllers[1], {}
    MsgN = function(text) errors[#errors + 1] = text end
    phys.ComputeShadowControl = function() error("solver refused") end
    c.PhysicsSimulate(c, phys, 0.015)
    assert(c.valid and c.motion and phys.valid) eq(player.dropped, nil) eq(#errors, 1)
    c.PhysicsSimulate(c, phys, 0.015) eq(#errors, 1)
    hooks.Tick()
    eq(player.dropped, true) eq(c.valid, false) eq(phys.valid, true)
    m.Stop()
end
function cases.server_repickup()
    local sv, state, ent, phys, m = server() hooks.OnPhysgunPickup(player, ent)
    local first = sv.controllers[1]
    hooks.OnPhysgunPickup(player, ent)
    eq(first.valid, false) eq(first.motion, false) eq(player.dropped, nil)
    local second = sv.controllers[2] assert(second.valid and second.motion) eq(second.body, phys)
    m.Stop() eq(second.valid, false) eq(phys.valid, true)
end
function cases.rotation_after_stop()
    local sv, state, ent, phys, m = server() hooks.OnPhysgunPickup(player, ent)
    local first = sv.controllers[1]
    hooks.PhysgunDrop(player)
    first.PhysicsSimulate(first, phys, 0.015)
    eq(phys.shadow, nil) eq(phys.valid, true)
    m.Stop()
end
function cases.server_pickup()
    local sv, state, ent = server() eq(hooks.OnPhysgunPickup(player, ent), nil)
    state.hands.right.ang = Angle(0, 0, 90) hooks.Tick()
    near(sv.Debug.tools[1].distance, 78 / 40) near(sv.Debug.tools[1].difference, 90)
    eq(hooks.PhysgunPickup, nil) -- no permission-returning hook is installed
end
function cases.server_drop() local sv, state, ent = server() hooks.OnPhysgunPickup(player, ent) hooks.Tick() assert(sv.Debug.tools[1]) eq(hooks.PhysgunDrop(player), nil) eq(sv.Debug.tools[1], nil) end
function cases.server_stale() local sv, state, ent, phys, m = server() hooks.OnPhysgunPickup(player, ent) state.hands.right.valid = false hooks.Tick() eq(sv.Debug.tools[1], nil) eq(player.dropped, true) m.Stop() m.Stop() end
function cases.server_stop()
    local sv, state, ent, phys, m = server() hooks.OnPhysgunPickup(player, ent) local sent = sv.sent
    m.Stop() eq(player.dropped, true) eq(sv.sent, sent + 1) eq(sv.Debug.tools, nil)
end
function cases.server_left()
    local sv, state, ent = server()
    state.hands.left = {valid = true, pos = Vector(20, 10, 48), ang = Angle(0, 0, 90)}
    net = {ReadBool = function() return true end} ctx.receives[97](player)
    hooks.OnPhysgunPickup(player, ent)
    state.hands.left.ang = Angle(0, 0, 180) hooks.Tick()
    near(sv.Debug.tools[1].difference, 90)
    net.ReadBool = function() return false end ctx.receives[97](player)
    eq(player.dropped, true) eq(sv.Debug.tools[1], nil)
end
assert(cases[scenario], scenario)()
print("PASS " .. scenario)
