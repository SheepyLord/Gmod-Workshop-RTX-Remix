local root, scenario = ...
local S = assert(loadfile(root .. "/companion/tests/vr_stubs.lua"))()
S.Math()
local ffi, oldWire = require("ffi"), S.Wire
ffi.cdef("typedef union { double n; unsigned char bytes[8]; } nlvr_motion_double;")
function S.Wire()
    local w = oldWire()
    function w.WriteDouble(n)
        local value = ffi.new("nlvr_motion_double") value.n = n
        for i = 0, 7 do w.WriteUInt(value.bytes[i], 8) end
    end
    function w.ReadDouble()
        local value = ffi.new("nlvr_motion_double")
        for i = 0, 7 do value.bytes[i] = w.ReadUInt(8) end
        return tonumber(value.n)
    end
    return w
end
bit = require("bit")
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function close(a, b, e) assert(math.abs(a - b) < (e or 0.00001), a .. " ~= " .. b) end
local function vec(a, b, e) close((a - b):Length(), 0, e) end
math.Clamp = function(n, a, b) return math.max(a, math.min(b, n)) end
table.RemoveByValue = function(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
local clock, sequence, commands = 0, 0, 0
RealTime = function() return clock end CurTime = RealTime
SysTime = RealTime
engine = {TickCount = function() return sequence end, TickInterval = function() return 1 / 66 end}
FrameNumber = function() return sequence end
MOVETYPE_WALK, MOVETYPE_NOCLIP = 2, 8
IN_DUCK, IN_JUMP, IN_SPEED = 4, 2, 131072
MASK_PLAYERSOLID, COLLISION_GROUP_PLAYER_MOVEMENT = 1, 8
local player = {valid = true, pos = Vector(), kind = MOVETYPE_WALK, duck = false, alive = true}
function player:GetPos() return self.pos end
function player:GetCurrentViewOffset() return Vector(0, 0, self.duck and 28 or 64) end
function player:GetViewOffset() return Vector(0, 0, 64) end
function player:GetViewOffsetDucked() return Vector(0, 0, 28) end
function player:Crouching() return self.duck end
function player:GetHull() return Vector(-16, -16, 0), Vector(16, 16, 72) end
function player:GetHullDuck() return Vector(-16, -16, 0), Vector(16, 16, 36) end
function player:GetStepSize() return 18 end
function player:OnGround() return true end
function player:GetMoveType() return self.kind end
function player:Alive() return self.alive end
function player:InVehicle() return false end
function player:GetWalkSpeed() return 200 end
function player:GetRunSpeed() return 400 end
function player:IsPlayer() return true end
function player:IsListenServerHost() return true end
function player:EyePos() return self.pos + self:GetCurrentViewOffset() end
function LocalPlayer() return player end
function IsValid(p) return type(p) == "table" and p.valid ~= false end
game = {SinglePlayer = function() return true end}
local log = {}
MsgN = function(s) log[#log + 1] = s end
local hooks, cv, callbacks = {}, {}, {}
hook=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib",hooks)
timer = {Create = function() error("unexpected timer") end, Remove = function() end}
cvars = {AddChangeCallback = function(n, fn, id) callbacks[n] = fn end, RemoveChangeCallback = function(n) callbacks[n] = nil end}
local function convar(n, value)
    cv[n] = {value = value, GetFloat = function(self) return tonumber(self.value) end}
end
function GetConVar(n) return cv[n] end
convar("nl_vr_fov", 145) convar("m_yaw", 0.022) convar("nl_vr_scale", 40)
function RunConsoleCommand(n, v) local old = cv[n] and cv[n].value or 0 convar(n, v) if callbacks[n] then callbacks[n](n, old, v) end end
vgui = {CursorVisible = function() return false end}
function include(p) return assert(loadfile(root .. "/vr/addon/lua/" .. p))() end
local boxes = {}
util = {}
-- Swept AABB against independent axis-aligned world fixtures, including a floor plane.
local function trace(q)
    local start, finish, lo, hi = q.start, q.endpos, q.mins, q.maxs
    local best, normal, inside = 1, Vector(0, 0, 1), false
    for _, box in ipairs(boxes) do
        local min, max = box[1] - hi, box[2] - lo
        local enter, leave, axisNormal = -math.huge, math.huge, Vector()
        local strict = true
        for _, k in ipairs({"x", "y", "z"}) do
            if start[k] <= min[k] + 0.00001 or start[k] >= max[k] - 0.00001 then strict = false end
            local d = finish[k] - start[k]
            if math.abs(d) < 0.000001 then
                if start[k] <= min[k] or start[k] >= max[k] then enter, leave = math.huge, -math.huge end
            else
                local a, b = (min[k] - start[k]) / d, (max[k] - start[k]) / d
                local sign = -1 if a > b then a, b, sign = b, a, 1 end
                if a > enter then enter, axisNormal = a, Vector() axisNormal[k] = sign end
                leave = math.min(leave, b)
            end
        end
        if strict then inside = true best = 0 end
        if enter >= -0.000001 and enter <= leave and enter <= best and leave >= 0 then
            best, normal = math.max(0, enter), axisNormal
        end
    end
    return {Hit = best < 1, Fraction = best, HitPos = start + (finish - start) * best,
        HitNormal = normal, StartSolid = inside, AllSolid = inside}
end
util.TraceHull = trace
local function floor(z) boxes[#boxes + 1] = {Vector(-2000, -2000, -1000), Vector(2000, 2000, z or 0)} end
local M = include("nlvr/modules/cl_move_math.lua")
local natives, updates = 0, 0
local native = {BeginFrame = function() end, Actions = function() return {} end, SetFrameCamera = function() return true end}
for _, method in ipairs({"OverlaySource", "OverlayAttach", "OverlayShow", "OverlayDestroy", "OverlayAlpha"}) do
    native[method] = function() return true end
end
native.OverlayCreate = function() natives = natives + 1 return natives end
native.OverlaySortOrder = function() end
RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, IMAGE_FORMAT_RGBA8888 = 8, 2, 0
function GetRenderTargetEx(_, w, h) return {Width = function() return w end, Height = function() return h end} end
surface = {SetDrawColor = function() end, DrawRect = function() updates = updates + 1 end,
    DrawPoly = function() updates = updates + 1 end}
draw = {NoTexture = function() end}
render = {PushRenderTarget = function() end, PopRenderTarget = function() end, Clear = function() end}
cam = {Start2D = function() end, End2D = function() end}
net = {Receivers = {}, Receive = function(n, fn) net.Receivers[n] = fn end, Start = function() end,
    WriteUInt = function() end, WriteFloat = function() end, WriteBool = function() end, SendToServer = function() end}
local function pose(pos, ang) return {valid = true, pos = pos, ang = ang or Angle(), vel = Vector(), angvel = Vector()} end
local C, moveCtx, sent, readers, movers, events
local function client()
    C = include("nlvr/core/cl_core.lua").New(native, function(e) error(e) end, 40)
    C.Frame = {sequence = sequence, hmd = pose(Vector(0, 0, 1.6)), left = pose(Vector(0.1, 0.2, 1.2)), right = pose(Vector(0.2, -0.2, 1.2))}
    C.Space.yaw = 0 C.Feet = player.pos
    native.BeginFrame = function() return C.Frame end
    C.Start({include("nlvr/modules/cl_move.lua")})
    moveCtx = C.Registry.entries[2].ctx
    sent, readers = {}, {}
    -- Use real registration and callbacks; capture the already validated module packet at transport.
    local on = C.Net.On
    -- Registered readers live in the core; deliver via its actual type-byte receiver below.
    C.Net.Send = function(kind, writer) sent[#sent + 1] = {kind = kind, packet = include("nlvr/sh_protocol.lua").Packet(writer)} end
    return C
end
local function cmd()
    local c = S.Command() commands = commands + 1
    function c:CommandNumber() return commands end
    function c:GetMouseX() return self.mouse or 0 end
    function c:SetUpMove(n) self.up = n end
    function c:GetUpMove() return self.up or 0 end
    return c
end
local function input(actions)
    C.Input.Update(actions or {}, clock, C.Settings.dominant == 1)
end
local function tick(dt)
    clock, sequence = clock + (dt or 1 / 66), sequence + 1
    C.Frame.sequence = sequence
    hook.Run("CreateMove", cmd())
end
local function command(c) hook.Run("CreateMove", c or cmd()) end
local function view()
    return hook.Run("CalcView", player, player:EyePos(), Angle(), 90, 1, 10000)
end
local function server()
    sent, readers, movers, events = {}, {}, {}, {}
    local sv = {Players = {[player] = {active = true, scale = 40, head = {valid = true},
        hands = {left = pose(Vector(0, 0, 48)), right = pose(Vector(0, 0, 48))}, lastSync = clock}}, Net = {}}
    sv.Net.On = function(kind, fn) readers[kind] = fn end
    sv.Emit=function(name,...) if events[name] then events[name](...) end end
    sv.Net.Send = function(_, kind, fn) sent[#sent + 1] = {kind = kind, packet = include("nlvr/sh_protocol.lua").Packet(fn)} end
    local ctx = {core = sv, Net = sv.Net, mover = function(p, fn) movers[#movers + 1] = {p, fn} end,
        On = function(n, fn) events[n] = fn end, cleanup = function() end,
        hook = function(n, fn) hook.Add(n, "nlvr.move", fn) end}
    include("nlvr/modules/sv_move.lua").Start(ctx)
    table.sort(movers, function(a, b) return a[1] < b[1] end)
    return sv
end
local function message(kind, writer)
    local wire = S.Wire() writer(wire) wire.Rewind()
    for k, v in pairs(wire) do net[k] = v end
    readers[kind](player)
end
local function room(seq, total) message(M.ROOM, function(w)
    w.WriteUInt(seq, 32) w.WriteFloat(total.x) w.WriteFloat(total.y) w.WriteFloat(total.z)
end) end
local function run_move(command)
    local mv = S.Move() mv.origin = player.pos
    for _, r in ipairs(movers) do if r[2](player, mv, command) then break end end
    hook.Run("FinishMove", player, mv)
    player.pos = mv.origin return mv
end
local cases = {}
function cases.arc()
    local count = 0
    local arc = M.Arc(Vector(0, 0, 48), Vector(1, 0, 0), 40, function(a, b)
        count = count + 1
        if b.z <= 0 then local f = a.z / (a.z - b.z) return {Hit = true, HitPos = a + (b - a) * f, HitNormal = Vector(0, 0, 1)} end
        return {Hit = false}
    end)
    eq(#arc.points, count + 1) close(arc.target.z, 0) assert(arc.target.x > 140 and arc.target.x < 210)
    print("arc segments=" .. count .. " range=" .. arc.target.x)
end
function cases.landing()
    floor() local arc = M.PlayerArc(player, Vector(0, 0, 48), Vector(1, 0, 0), 40)
    local target, reason, route = M.Landing(player, arc, 40, Vector())
    eq(reason, "ok") assert(target.x > 140) vec(M.Route(route, 1), target)
    print("landing=" .. target.x .. "," .. target.z)
end
function cases.landing_refusals()
    floor()
    local arc = {target = Vector(160, 0, 0), hit = {Hit = true, HitNormal = Vector(0, 0, 1)}}
    boxes[#boxes + 1] = {Vector(150, -20, 45), Vector(180, 20, 100)}
    local target, reason = M.Landing(player, arc, 40, Vector()) eq(target, nil) eq(reason, "hull")
    table.remove(boxes) arc.hit.HitNormal = Vector(1, 0, 0)
    target, reason = M.Landing(player, arc, 40, Vector()) eq(reason, "slope")
    arc.hit.HitNormal = Vector(0, 0, 1) arc.target = Vector(400, 0, 0)
    target, reason = M.Landing(player, arc, 40, Vector()) eq(reason, "range")
    arc.target = Vector(100, 0, 80) target, reason = M.Landing(player, arc, 40, Vector()) eq(reason, "height")
    arc.target = Vector(160, 0, 0) boxes[#boxes + 1] = {Vector(50, -100, 0), Vector(60, 100, 200)}
    target, reason = M.Landing(player, arc, 40, Vector()) eq(reason, "path")
end
function cases.teleport_doorway()
    floor() boxes[#boxes + 1] = {Vector(-50, -100, 76), Vector(220, 100, 90)}
    local arc = M.PlayerArc(player, Vector(0, 0, 48), Vector(1, 0, 0), 40)
    local target, reason, route = M.Landing(player, arc, 40, Vector())
    assert(target, reason) eq(#route, 2)
    assert(M.SweepRoute(player, route, 0, 1))
    assert(M.Route(route, 0.5).z < 1) -- a level shift stays on the floor
end
function cases.follow()
    floor() local at = Vector()
    for _ = 1, 100 do at = M.Follow(player, at, Vector(0.4, 0, 0)) end
    vec(at, Vector(40, 0, 0)) print("one_metre=" .. at.x)
end
function cases.steps()
    floor() boxes[#boxes + 1] = {Vector(30, -100, 0), Vector(60, 100, 12)}
    local at = Vector() for _ = 1, 100 do at = M.Follow(player, at, Vector(0.4, 0, 0)) end
    close(at.x, 40) close(at.z, 12)
    print("step=" .. at.z)
end
function cases.crouch()
    eq(M.Crouch(1.1, 1.6, false), false) eq(M.Crouch(1.08, 1.6, false), true)
    eq(M.Crouch(1.2, 1.6, true), true) eq(M.Crouch(1.25, 1.6, true), false)
end
function cases.calibration()
    close(M.Calibration(1.6, 64), 40) close(M.Calibration(2, 64), 32)
    eq(M.Calibration(0 / 0, 64), nil) eq(M.Calibration(0.7, 64), nil)
    client() tick() local ok, result = C.Move.Calibrate() eq(ok, true) close(result.scale, 40) eq(result.restart, false)
end
function cases.debug_reuse()
    client() tick() C.Emit("before_overlay_paint")
    local debug, position, space, anchor, room, head = C.Debug.move, C.Debug.move.position,
        C.Debug.move.space, C.Debug.move.space.anchor, C.Debug.move.room, C.Debug.move.head
    local net = C.Debug.net
    for i=1,100 do tick() C.Emit("before_overlay_paint") end
    eq(C.Debug.move,debug) eq(debug.position,position) eq(debug.space,space)
    eq(space.anchor,anchor) eq(debug.room,room) eq(debug.head,head) eq(C.Debug.net,net)
    C.Stop()
end
function cases.physical_hands_body_filter()
    local proxy,prop,world,other={},{},{},{}
    NLVR_SV={BodyTrace=function(p,e) return e~=p and e~=proxy end}
    local old=util.TraceHull
    util.TraceHull=function(q)
        assert(type(q.filter)=="function")
        eq(q.filter(player),false) eq(q.filter(proxy),false)
        eq(q.filter(prop),true) eq(q.filter(world),true) eq(q.filter(other),true)
        return {Hit=false,HitPos=q.endpos,Fraction=1,HitNormal=Vector(0,0,1)}
    end
    local position,blocked=M.Follow(player,Vector(0,0,1),Vector(40,0,0))
    vec(position,Vector(40,0,1)) eq(blocked,false)
    NLVR=NLVR_SV NLVR_SV=nil
    position,blocked=M.Follow(player,Vector(0,0,1),Vector(40,0,0))
    vec(position,Vector(40,0,1)) eq(blocked,false)
    NLVR=nil
    util.TraceHull=old NLVR_SV=nil
end
function cases.vignette()
    close(M.Vignette(0, 0, 0.6), 0) close(M.Vignette(90, 0, 0.6), 0.3)
    close(M.Vignette(0, 120, 0.6), 0.6) close(M.Vignette(500, 500, 0), 0)
end
function cases.turn_rules()
    local degrees, latch = M.Turn(1, false, false, 30, 120, 0.01) eq(degrees, -30) eq(latch, true)
    degrees, latch = M.Turn(1, latch, false, 30, 120, 0.01) eq(degrees, 0)
    degrees, latch = M.Turn(0, latch, false, 30, 120, 0.01) eq(latch, false)
    degrees = M.Turn(-0.5, false, true, 30, 120, 0.1) close(degrees, 6)
end
function cases.turn_pivot()
    client() tick() C.Space.anchor = Vector(-0.2, 0.3, 0) C.Refresh() -- exercise a nonzero pivot
    local head = C.Pose.head.pos
    for _, d in ipairs({30, -45, 90, -180, 360, 12.5}) do C.Space.Turn(d) vec(C.Pose.head.pos, head) end
    print("turn error=" .. (C.Pose.head.pos - head):Length())
end
function cases.room_client()
    client() tick() C.Frame.hmd.pos = Vector(0.01, 0, 1.6) tick()
    vec(C.Space.anchor, Vector(0.01, 0, 0)) vec(C.Pose.head.pos, Vector(0.4, 0, 64))
    local p = sent[#sent] eq(p.kind, M.ROOM)
    local w = S.Wire() p.packet.Write(w) w.Rewind() w.ReadUInt(32) vec(w.ReadVector(), Vector(0.4, 0, 0))
end
function cases.room_float_wire()
    client() tick() C.Frame.hmd.pos = Vector(0.01, 0, 1.6) tick()
    local wire = S.Wire()
    wire.WriteVector = function() error("cumulative room distance cannot use bounded Source coordinates") end
    sent[#sent].packet.Write(wire)
    wire.Rewind() wire.ReadUInt(32) close(wire.ReadFloat(), 0.4)
    C.Stop() floor() local sv = server()
    sv.Players[player].move = {received = Vector(20000, 0, 0), consumed = Vector(20000, 0, 0)}
    room(1, Vector(20001, 0, 0)) run_move() close(player.pos.x, 1)
end
function cases.room_server()
    floor() local sv = server()
    for i = 1, 100 do room(i, Vector(i * 0.4, 0, 0)) run_move() clock = clock + 0.01 end
    close(player.pos.x, 40) close(sv.Players[player].move.applied.x, 0.4)
end
function cases.room_validation()
    floor() local sv = server() room(1, Vector(1, 0, 0)) run_move()
    room(1, Vector(5, 0, 0)) run_move() close(player.pos.x, 1)
    room(2, Vector(500, 0, 0)) run_move() close(player.pos.x, 1)
    room(2, Vector(2, 0, 1)) run_move() close(player.pos.x, 1)
    room(2, Vector(0 / 0, 0, 0)) run_move() close(player.pos.x, 1)
    room(2, Vector(6, 0, 0)) clock = 1 run_move() close(player.pos.x, 1)
end
function cases.room_wall()
    floor() boxes[#boxes + 1] = {Vector(30, -100, 0), Vector(40, 100, 200)}
    local sv = server() for i = 1, 100 do room(i, Vector(i * 0.4, 0, 0)) run_move() end
    close(player.pos.x, 14) eq(sv.Players[player].move.blocked, true)
    table.remove(boxes) run_move() close(player.pos.x, 14) -- no stored push after a wall disappears
end
local function stick(hand, x, y)
    return {[hand .. "_stick"] = {active = true, x = x, y = y}}
end
local function smooth(mode, left)
    client() C.Settings.move_dir = mode C.Settings.dominant = left and 1 or 0
    tick() local actions = stick(left and "right" or "left", 0, 1)
    C.Frame.left.ang, C.Frame.right.ang = Angle(0, 90, 0), Angle(0, 90, 0)
    native.Actions = function() return actions end
    clock = clock + 0.02 sequence = sequence + 1 C.Frame.sequence = sequence
    local c = cmd() command(c)
    close(c.forward, mode == 1 and 200 or 0) close(c.side, mode == 1 and 0 or -200)
end
function cases.smooth_hand() smooth(0, false) end
function cases.smooth_head() smooth(1, false) end
function cases.smooth_left() smooth(0, true) end
function cases.buttons()
    client() tick() local actions = {left_a = {active = true, state = true}, left_stick_click = {active = true, state = true}, right_stick = {active = true, y = -1}}
    native.Actions = function() return actions end
    sequence = sequence + 1 C.Frame.sequence = sequence local c = cmd() command(c)
    assert(bit.band(c.buttons, IN_JUMP) ~= 0) assert(bit.band(c.buttons, IN_SPEED) ~= 0) assert(bit.band(c.buttons, IN_DUCK) ~= 0)
end
function cases.noclip()
    player.kind = MOVETYPE_NOCLIP client() tick()
    local actions = stick("left", 0, 1) actions.left_trigger_value = {active = true, x = 0.5}
    native.Actions = function() return actions end C.Frame.left.ang = Angle(-30, 0, 0)
    sequence = sequence + 1 C.Frame.sequence = sequence local c = cmd() command(c)
    close(c.forward, 200 * math.cos(math.pi / 6)) close(c.up, 100)
    eq(player.kind, MOVETYPE_NOCLIP)
end
function cases.q5_ladder_overlay_pipeline()
    MOVETYPE_LADDER=9 player.kind=MOVETYPE_LADDER client()
    local turn=math.rad(5)
    native.Actions=function() return stick("left",.65*math.sin(turn),.65*math.cos(turn)) end
    for i=1,3 do
        tick()
        -- Real overlay lifecycle dispatch must not call command-only work without a command.
        C.Emit("before_overlay_paint")
        local c=cmd() command(c)
        assert(c:GetForwardMove()>1,"movement stopped after ladder overlay paint")
        assert(bit.band(c:GetButtons(),IN_FORWARD or 8)~=0,"ladder forward sector missing from real mover")
        eq(bit.band(c:GetButtons(),bit.bor(IN_MOVELEFT or 512,IN_MOVERIGHT or 1024)),0,"small ladder input became a strafe")
    end
    C.Stop()
end
function cases.q5_noclip_underwater()
    player.kind=MOVETYPE_NOCLIP local water=2 player.WaterLevel=function() return water end
    client() C.Frame.hmd.ang=Angle(-45,0,0) C.Frame.left.ang=Angle(-30,70,0)
    local armed,gun=false,45
    local ctx=C.Registry:Add({name="aim_test",order=90,Start=function() end,Stop=function() end}).ctx
    ctx.mover(90,function(c) if armed then C.Aim(Angle(gun,35,0),"weapon") end end)
    local throttle=0
    native.Actions=function() local a=stick("left",0,1) a.left_trigger_value={active=true,x=throttle} return a end
    for _,level in ipairs({0,2,3}) do for _,pitch in ipairs({0,45,-45}) do for _,speed in ipairs({0,.5}) do
        water,armed,gun,throttle=level,pitch~=0,pitch,speed
        sequence=sequence+1 C.Frame.sequence=sequence local c=cmd() command(c)
        local a=c:GetViewAngles() local world=a:Forward()*c.forward+a:Right()*c.side+a:Up()*(c.up or 0)
        vec(world,Angle(-30,70,0):Forward()*player:GetRunSpeed()*speed)
    end end end
    C.Stop()
end
function cases.q4s_medium_head_rule()
    MOVETYPE_LADDER=9
    local medium="water"
    player.GetMoveType=function() return medium=="ladder" and MOVETYPE_LADDER or MOVETYPE_WALK end
    player.WaterLevel=function() return medium=="water" and 3 or 0 end
    client() C.Settings.move_dir=0 C.Frame.hmd.ang=Angle(-45,0,0) C.Frame.left.ang=Angle(0,90,0)
    local armed,gun=false,45
    local ctx=C.Registry:Add({name="aim_test",order=90,Start=function() end,Stop=function() end}).ctx
    ctx.mover(90,function(c) if armed then C.Aim(Angle(gun,35,0),"weapon") end end)
    native.Actions=function() return stick("left",0,1) end
    for _,mode in ipairs({"water","ladder"}) do
        medium=mode
        for _,pitch in ipairs({0,45,-45}) do
            armed,gun=pitch~=0,pitch
            sequence=sequence+1 C.Frame.sequence=sequence local c=cmd() command(c)
            local a=c:GetViewAngles()
            local head=Angle(-45,0,0)
            vec(a:Forward()*c.forward+a:Right()*c.side+a:Up()*(c.up or 0),head:Forward()*player:GetWalkSpeed())
        end
    end
    C.Stop()
end
local function turn(smooth)
    client() C.Settings.turn = smooth and 1 or 0 tick()
    native.Actions = function() return stick("right", 1, 0) end
    local head = C.Pose.head.pos tick(0.02) vec(C.Pose.head.pos, head)
    close(C.Space.yaw, smooth and -2.4 or -30)
    tick(0.02) close(C.Space.yaw, smooth and -4.8 or -30)
end
function cases.snap() turn(false) end
function cases.smooth_turn() turn(true) end
function cases.mouse()
    client() tick() local head = C.Pose.head.pos local c = cmd() c.mouse = 100 command(c)
    close(C.Space.yaw, -2.2) vec(C.Pose.head.pos, head)
end
function cases.claims()
    client() tick() C.Input.Claim("off", "stick", "ui") C.Input.Claim("main", "stick", "ui")
    C.Input.off.stick = {x = 0, y = 1} C.Input.main.stick = {x = 1, y = 0}
    local c = cmd() command(c) close(c.forward, 0) close(C.Space.yaw, 0)
end
local function teleport(mode)
    floor() local sv = server()
    local arc = M.PlayerArc(player, sv.Players[player].hands.right.pos, Vector(1, 0, 0), 40)
    local target = assert(M.Landing(player, arc, 40, player.pos))
    message(M.TELEPORT, function(w) w.WriteUInt(7, 16) w.WriteBool(false) w.WriteUInt(mode, 2) w.WriteVector(target) end)
    assert(sv.Players[player].move.teleport)
    for i = 0, 20 do clock = i * 0.01 run_move() end
    vec(player.pos, target) eq(sv.Players[player].move.last.success, true)
    print("teleport mode=" .. mode .. " error=" .. (player.pos - target):Length())
end
function cases.blink() teleport(1) end
function cases.shift() teleport(2) end
function cases.server_refuse()
    floor() local sv = server()
    message(M.TELEPORT, function(w) w.WriteUInt(1, 16) w.WriteBool(false) w.WriteUInt(1, 2) w.WriteVector(Vector(500, 0, 0)) end)
    eq(sv.Players[player].move.last.success, false) eq(sv.Players[player].move.last.reason, "changed")
    vec(player.pos, Vector())
end
function cases.moving_obstacle()
    floor() local sv = server() local arc = M.PlayerArc(player, Vector(0, 0, 48), Vector(1, 0, 0), 40)
    local target = assert(M.Landing(player, arc, 40, Vector()))
    message(M.TELEPORT, function(w) w.WriteUInt(1, 16) w.WriteBool(false) w.WriteUInt(1, 2) w.WriteVector(target) end)
    boxes[#boxes + 1] = {Vector(50, -100, 0), Vector(60, 100, 200)} clock = 0.1 run_move()
    vec(player.pos, Vector()) eq(sv.Players[player].move.last.reason, "blocked")
end
function cases.mantle()
    floor() boxes[#boxes + 1] = {Vector(140, -60, 0), Vector(230, 60, 48)}
    local sv = server() sv.Players[player].hands.right = pose(Vector(10, -10, 48), Angle(-15, 0, 0))
    local arc = M.PlayerArc(player, Vector(10, -10, 48), Angle(-15, 0, 0):Forward(), 40)
    local target, reason = M.Landing(player, arc, 40, player.pos)
    assert(target, reason) close(target.z, 48.25)
    message(M.TELEPORT, function(w) w.WriteUInt(5, 16) w.WriteBool(false) w.WriteUInt(2, 2) w.WriteVector(target) end)
    for i = 0, 20 do clock = i * 0.01 run_move() end
    vec(player.pos, target) eq(sv.Players[player].move.last.reason, "mantle")
    print("mantle height=" .. target.z .. " error=" .. (player.pos - target):Length())
end
function cases.climbing_resume()
    floor() local sv = server()
    room(1, Vector(10, 0, 0))
    -- Simulate the framework's first-winner arbitration: L's mover was not called this tick.
    hook.Run("FinishMove", player, S.Move())
    run_move() vec(player.pos, Vector())
    room(2, Vector(11, 0, 0)) run_move() vec(player.pos, Vector(1, 0, 0))
end
function cases.climbing_cancels_teleport()
    floor() local sv = server()
    local arc = M.PlayerArc(player, Vector(0, 0, 48), Vector(1, 0, 0), 40)
    local target = assert(M.Landing(player, arc, 40, player.pos))
    message(M.TELEPORT, function(w) w.WriteUInt(8, 16) w.WriteBool(false) w.WriteUInt(1, 2) w.WriteVector(target) end)
    hook.Run("FinishMove", player, S.Move()) -- climbing won, so L did not own this command
    eq(sv.Players[player].move.teleport, nil) eq(sv.Players[player].move.last.reason, "movement_owner")
    clock = 1 run_move() vec(player.pos, Vector()) -- no delayed teleport after release
end
function cases.paused_teleport()
    floor() local sv = server()
    local arc = M.PlayerArc(player, Vector(0, 0, 48), Vector(1, 0, 0), 40)
    local target = assert(M.Landing(player, arc, 40, player.pos))
    message(M.TELEPORT, function(w) w.WriteUInt(8, 16) w.WriteBool(false) w.WriteUInt(1, 2) w.WriteVector(target) end)
    CurTime = function() return 0 end -- paused simulation, but wall time continues
    clock = 2 run_move() vec(player.pos, Vector())
    eq(sv.Players[player].move.last.reason, "expired")
end
function cases.flight_server()
    local sv = server() player.kind = MOVETYPE_NOCLIP
    local c = cmd() c:SetViewAngles(Angle()) c:SetForwardMove(60) c:SetUpMove(80)
    local mv = run_move(c) close(mv.velocity:Length(), 100) vec(player.pos, Vector(60, 0, 80) / 66)
    c:SetForwardMove(180) c:SetUpMove(240) mv = run_move(c) close(mv.velocity:Length(), 300)
    eq(player.kind, MOVETYPE_NOCLIP)
end
function cases.crouch_view()
    client() tick() C.Input.main.stick = {x = 0, y = -1} command(cmd())
    close(C.Pose.head.pos.z, 28)
    C.Frame.hmd.pos.z = 1 tick() close(C.Pose.head.pos.z, 28) -- no upward pop at the physical threshold
    C.Frame.hmd.pos.z = 0.6 tick() close(C.Pose.head.pos.z, 24) -- a deeper bend still lowers the view
end
function cases.seated()
    client() tick() C.Settings.seated = 1 C.Settings.seated_offset = 0.45 tick()
    close(C.Pose.head.pos.z, 82) close(C.Space.seated, 0.45)
    C.Frame.hmd.pos.z = 1 tick() C.Emit("before_overlay_paint") eq(C.Debug.move.physical_crouch, false)
    close(C.Pose.head.pos.z, 58)
end
function cases.calibration_restart()
    client() C.Frame.hmd.pos.z = 2 tick()
    local ok, result = C.Move.Calibrate() eq(ok, true) close(result.scale, 32) eq(result.restart, true)
    close(C.Space.scale, 40) close(GetConVar("nl_vr_scale"):GetFloat(), 32)
end
function cases.eye_ceiling()
    client() tick()
    boxes[#boxes + 1] = {Vector(-100, -100, 75), Vector(100, 100, 77)}
    C.Frame.hmd.pos.z = 2.1 tick() C.Emit("before_overlay_paint")
    close(C.Pose.head.pos.z, 84) eq(C.Debug.move.eye_blocked, true) eq(C.Debug.move.fade, 1)
    -- Endpoint alone is clear: the segment is what prevents looking through the thin ceiling.
    eq(M.Trace(player, C.Pose.head.pos, C.Pose.head.pos, Vector(-2, -2, -2), Vector(2, 2, 2)).StartSolid, false)
end
function cases.lifecycle()
    client() tick() C.Stop() eq(C.Move, nil) eq(NLVR, nil)
    for event, list in pairs(hooks) do eq(next(list), nil) end
    eq(next(callbacks), nil)
end
function cases.tracking_loss()
    client() tick() C.Frame.hmd.valid = false tick() C.Frame.hmd.pos = Vector(1, 0, 1.6) C.Frame.hmd.valid = true tick()
    vec(C.Pose.head.pos, Vector(0, 0, 64)) -- reacquisition does not become a one-metre command
end
function cases.overlays()
    floor() client() tick() native.Actions = function() return stick("right", 0, 1) end
    tick() C.Emit("before_overlay_paint") C.Overlay.Paint()
    print("overlay allocations="..natives.." paint operations="..updates)
    assert(natives >= 4 and natives <= 5) assert(updates >= 256) eq(C.Overlay.Objects.teleport_target.visible, true)
    for _,key in ipairs({"teleport_arc","teleport_arc_2","teleport_arc_3","teleport_target"}) do assert(C.Overlay.Objects[key].visible) end
    native.Actions = function() return {} end tick() C.Emit("before_overlay_paint") C.Overlay.Paint()
    eq(C.Overlay.Objects.vignette.visible, true) -- blink covers the eyes while awaiting the server
    C.Stop() eq(next(C.Overlay.Objects), nil)
end
function cases.blink_ack_fade()
    floor() client() tick() native.Actions = function() return stick("right", 0, 1) end
    tick() native.Actions = function() return {} end tick()
    local wire = S.Wire()
    wire.WriteUInt(M.RESULT, 8) wire.WriteUInt(1, 16) wire.WriteBool(true) wire.WriteString("ok") wire.WriteVector(Vector(180, 0, 0))
    wire.Rewind()
    for _, n in ipairs({"ReadUInt", "ReadBool", "ReadString", "ReadVector"}) do net[n] = wire[n] end
    net.Receivers.nlvr(wire.Length())
    C.Emit("before_overlay_paint") eq(C.Debug.move.pending, false) eq(C.Debug.move.fade, 1)
    clock = clock + 0.09 C.Emit("before_overlay_paint") assert(C.Debug.move.fade > 0 and C.Debug.move.fade < 1)
    clock = clock + 0.2 C.Emit("before_overlay_paint") eq(C.Debug.move.fade, 0)
end
local function receipt(consumed, applied, position, blocked, mode)
    local wire = S.Wire()
    wire.WriteUInt(M.FOLLOW, 8) wire.WriteBool(blocked or false) wire.WriteUInt(mode or MOVETYPE_WALK, 5)
    wire.WriteDouble(CurTime()) wire.WriteDouble(SysTime()) wire.WriteUInt(0, 16)
    for _, v in ipairs({consumed, applied, position}) do wire.WriteFloat(v.x) wire.WriteFloat(v.y) wire.WriteFloat(v.z) end
    wire.Rewind()
    for _, n in ipairs({"ReadUInt", "ReadBool", "ReadFloat", "ReadDouble"}) do net[n] = wire[n] end
    net.Receivers.nlvr(wire.Length())
end
function cases.render_prediction()
    client() tick()
    for i = 1, 180 do
        C.Frame.hmd.pos.y = i / 90 * 0.5
        if i % 3 == 0 then
            local acknowledged = (i - 2) / 90 * 20
            receipt(Vector(0, acknowledged, 0), Vector(0, acknowledged, 0), Vector(0, acknowledged, 0))
            player.pos = Vector(0, acknowledged - 0.1, 0)
        end
        tick(1 / 90) local camera = view()
        close(camera.origin.y, i / 90 * 20, 0.0001)
    end
    print("180 rendered frames; max free-space error <0.0001 units")
    C.Stop() eq(C.ViewFeet, nil)
end
function cases.prediction_authority()
    floor() local p = include("nlvr/modules/cl_move_predict.lua").New()
    p.Receive(Vector(2, 0, 0), Vector(2, 0, 0), Vector(12, 0, 0), MOVETYPE_WALK, false)
    vec(p.Feet(player, Vector(9, 0, 4), Vector(3, 0, 0), true), Vector(13, 0, 0))
    p.Receive(Vector(3, 0, 0), Vector(3, 0, 0), Vector(203, 0, 8), MOVETYPE_WALK, false, clock, clock, 1)
    vec(p.Feet(player, Vector(198, 0, 4), Vector(3, 0, 0), true), Vector(203, 0, 8))
    p.Receive(Vector(10, 0, 0), Vector(3, 0, 0), Vector(203, 0, 8), MOVETYPE_WALK, true)
    vec(p.Feet(player, Vector(203, 0, 8), Vector(10, 0, 0), true), Vector(203, 0, 8))
    boxes[#boxes + 1] = {Vector(230, -100, 0), Vector(240, 100, 200)}
    local at = p.Feet(player, Vector(203, 0, 0), Vector(50, 0, 0), true)
    close(at.x, 214) eq(p.blocked, true)
end
function cases.motion_interpolation()
    local p = include("nlvr/modules/cl_move_predict.lua").New()
    local nextTick, endMove, step, previous, maxBack = 0, 1, 1 / 66, nil, 0
    for i = 0, 120 do
        clock, sequence = i / 90, sequence + 1
        while nextTick <= clock do
            local x = math.min(nextTick, endMove) * 400
            p.Receive(Vector(), Vector(), Vector(x, 0, 0), MOVETYPE_NOCLIP, false, nextTick, nextTick, 0)
            nextTick = nextTick + step
        end
        local at = p.Feet(player, Vector(), Vector(), true).x
        if clock > .05 and clock < .95 then close(at, (clock - step) * 400, .00001) end
        if previous then maxBack = math.max(maxBack, previous - at) end
        previous = at
    end
    close(previous, 400) close(maxBack, 0)
    print("400 units/s at 90 renders / 66 ticks; stop backwards=" .. maxBack)
end
function cases.motion_with_room()
    local p = include("nlvr/modules/cl_move_predict.lua").New()
    clock, sequence = 1, 1
    p.Receive(Vector(4, 0, 0), Vector(4, 0, 0), Vector(14, 0, 0), MOVETYPE_WALK, false, 1, 1, 0)
    p.Receive(Vector(5, 0, 0), Vector(5, 0, 0), Vector(16, 0, 0), MOVETYPE_WALK, false, 1.015, 1.015, 0)
    clock, sequence = 1.02, 2
    local at = p.Feet(player, Vector(), Vector(6, 0, 0), true)
    close(at.x, 10 + (.02 - 1 / 66) / .015 + 6, .000001)
end
function cases.coalesced_motion()
    for _,stride in ipairs({2,3}) do
        local p=include("nlvr/modules/cl_move_predict.lua").New()
        local tick,nextTick,pending,previous,maxError=1/66,0,{},nil,0
        for i=0,270 do
            clock,sequence=i/90,sequence+1
            while nextTick<=clock do
                local n=math.floor(nextTick/tick+.5)
                if n%stride==0 then pending[#pending+1]={stamp=nextTick,arrives=nextTick+tick} end
                nextTick=nextTick+tick
            end
            while pending[1] and pending[1].arrives<=clock do
                local r=table.remove(pending,1)
                p.Receive(Vector(),Vector(),Vector(r.stamp*200,0,0),MOVETYPE_NOCLIP,false,r.stamp,r.stamp,0)
            end
            local at=p.Feet(player,Vector(),Vector(),true).x
            if clock>.5 and previous then
                maxError=math.max(maxError,math.abs((at-previous)-200/90))
            end
            previous=at
        end
        close(maxError,0,.00001) assert(p.bufferSeconds>=stride*tick)
    end
end
-- Renders at 90 Hz and simulates 66 ticks; FOLLOW comes every `stride` ticks, `age(n)` ticks after
-- its stamp. Returns the smallest and largest camera step, as a fraction of the nominal step, measured
-- from `measureFrom` to the end.
local function motorRun(p,start,seconds,generation,origin,speed,stride,age,measureFrom,onFrame)
    local tick,nextTick,pending,previous=1/66,start,{},nil
    local low,high,nominal=math.huge,0,speed/90
    for i=0,math.floor(seconds*90) do
        clock,sequence=start+i/90,sequence+1
        while nextTick<=clock+1e-9 do
            local n=math.floor((nextTick-start)/tick+.5)
            local send=type(stride)=="function" and stride(n) or type(stride)~="function" and n%stride==0
            if send then pending[#pending+1]={stamp=nextTick,arrives=nextTick+age(n)*tick} end
            nextTick=nextTick+tick
        end
        while pending[1] and pending[1].arrives<=clock+1e-9 do
            local r=table.remove(pending,1)
            p.Receive(Vector(),Vector(),Vector(origin+(r.stamp-start)*speed,0,0),MOVETYPE_NOCLIP,false,r.stamp,r.stamp,generation)
        end
        local at=p.Feet(player,Vector(),Vector(),true).x
        if previous and clock-start>=measureFrom then
            local ratio=(at-previous)/nominal
            low,high=math.min(low,ratio),math.max(high,ratio)
        end
        previous=at
        if onFrame then onFrame(clock-start) end
    end
    return low,high
end
function cases.motor_cadence_kept_across_reset()
    -- V4's shared wire coalesces FOLLOW with the hands: every third tick here. A blink, respawn or
    -- pause restarts the trajectory; relearning the cadence from one tick starved the camera.
    local p=include("nlvr/modules/cl_move_predict.lua").New()
    motorRun(p,10,1.5,0,0,200,3,function() return .5 end,99)
    local learned=p.bufferSeconds
    assert(learned>=3/66,"coalesced cadence not learned")
    local low,high=motorRun(p,12,1.2,1,500,200,3,function() return .5 end,learned+.05)
    assert(low>.8 and high<1.2,("camera starved after the reset: %.2f..%.2f"):format(low,high))
    print(("after a reset steps %.3f..%.3f of nominal, buffer %.3f s"):format(low,high,p.bufferSeconds))
end
function cases.motor_buffer_change_without_hold()
    -- One FOLLOW delivered a tick late grows the buffer by a tick. It is kept while needed and
    -- shrinks ten seconds after it was last needed. Applied at once each change held the camera
    -- for a frame or skipped it ahead.
    local p=include("nlvr/modules/cl_move_predict.lua").New()
    local before,held,after
    local low,high=motorRun(p,20,14,0,0,200,2,function(n) return n==90 and 1.2 or .2 end,1,function(t)
        if not before and t>=1.3 then before=p.bufferSeconds end
        if not held and t>=9 then held=p.bufferSeconds end
        if not after and t>=13.5 then after=p.bufferSeconds end
    end)
    assert(held>before+.01,("late packet did not grow the buffer: %.3f -> %.3f"):format(before,held))
    assert(after<held-.01,("buffer never shrank back: %.3f"):format(after))
    assert(low>.5,("camera held when the buffer grew: %.2f of nominal"):format(low))
    assert(high<1.5,("camera skipped when the buffer shrank: %.2f of nominal"):format(high))
    print(("buffer %.3f -> %.3f -> %.3f s, eased: steps %.3f..%.3f of nominal"):format(before,held,after,low,high))
end
function cases.motor_buffer_alternating_gaps_hold()
    -- V4's wire alternates between three- and four-tick gaps. The buffer must settle on the larger
    -- one and stay, not follow every alternation (the PoC eased 3-6 times in 1.4 s: 11-13 % spread).
    local p=include("nlvr/modules/cl_move_predict.lua").New()
    local last,changes=nil,0
    local tick=1/66
    -- Gaps of three ticks with a four-tick gap after every twentieth packet: the sixteen-packet
    -- maximum flips as the long gap enters and leaves it.
    local ticks,n,k={},0,0
    while n<1000 do ticks[n]=true k=k+1 n=n+(k%20==0 and 4 or 3) end
    local send=function(i) return ticks[i]==true end
    local low,high=motorRun(p,30,6,0,0,200,send,function(n) return .2 end,2,function(t)
        if t>=2 then
            if last and math.abs(p.bufferSeconds-last)>1e-9 then changes=changes+1 end
            last=p.bufferSeconds
        end
    end)
    assert(changes==0,("buffer changed %d times on a steady alternating wire"):format(changes))
    assert(low>.97 and high<1.03,("uneven steps %.3f..%.3f"):format(low,high))
    print(("alternating wire: buffer %.3f s, no changes, steps %.3f..%.3f"):format(last,low,high))
end
function cases.render_time_motor()
    local p=include("nlvr/modules/cl_move_predict.lua").New()
    clock,sequence=.04,1
    p.Receive(Vector(),Vector(),Vector(),MOVETYPE_NOCLIP,false,0,0,0)
    p.Receive(Vector(),Vector(),Vector(6,0,0),MOVETYPE_NOCLIP,false,.03,.03,0)
    clock=.06 local earlier=p.Feet(player,Vector(),Vector(),true).x
    clock=.063 local rendered=p.Feet(player,Vector(),Vector(),true).x
    close(rendered-earlier,.6,.00001)
end
function cases.framework_view_feet()
    client() tick() local saved = C.ViewFeet
    C.ViewFeet = function(base) return base + Vector(3, -4, 5) end
    C.Feet = Vector(10, 20, 30)
    local source = Vector(0.3, -0.4, 1.7)
    local world = C.ToWorld(source, Angle())
    vec(world, Vector(25, 0, 103))
    local round = C.ToTracking(world, Angle()) vec(round, source)
    C.ViewFeet = saved C.Stop() eq(C.ViewFeet, nil)
end
function cases.command_roll()
    client() C.Frame.hmd.ang = Angle(7, 10, 25) tick()
    local c = cmd() command(c)
    close(c:GetViewAngles().r, 0)
    local camera = view() close(camera.angles.r, 25)
end
function cases.review_room_pause()
    floor() local sv=server()
    room(1,Vector()) run_move()
    clock=clock+3
    room(2,Vector(120,0,0)) run_move()
    local before=Vector(player.pos.x,player.pos.y,player.pos.z)
    room(3,Vector(120.4,0,0)) run_move()
    close(player.pos.x-before.x,.4)
    vec(sv.Players[player].move.received,Vector(120.4,0,0))
end
function cases.review_paused_room_client()
    client() tick()
    gui={IsGameUIVisible=function() return true end}
    for i=1,60 do
        C.Frame.hmd.pos=Vector(i*.05,0,1.6)
        C.Frame.left.pos=Vector(i*.05+.1,.2,1.2) C.Frame.right.pos=Vector(i*.05+.2,-.2,1.2)
        tick()
    end
    gui.IsGameUIVisible=function() return false end
    C.Frame.hmd.pos=Vector(3.01,0,1.6) tick()
    C.Frame.left.pos=Vector(3.11,.2,1.2) C.Frame.right.pos=Vector(3.21,-.2,1.2) C.Refresh()
    assert((C.Pose.right.pos-player:EyePos()):Length()<100,"paused held controllers remain within sync reach")
    local packet=sent[#sent].packet local wire=S.Wire()
    packet.Write(wire) wire.Rewind() wire.ReadUInt(32)
    close(wire.ReadFloat(),.4)
    C.Stop()
end
function cases.review_follow_stale()
    local prediction=include("nlvr/modules/cl_move_predict.lua").New()
    prediction.Receive(Vector(),Vector(),Vector(4,0,0),MOVETYPE_WALK,false,clock,clock,0)
    vec(prediction.Feet(player,Vector(4,0,0),Vector(),true),Vector(4,0,0))
    clock=clock+.31
    vec(prediction.Feet(player,Vector(80,0,0),Vector(),true),Vector(80,0,0))
    -- Also works if the server move module never started.
    local absent=include("nlvr/modules/cl_move_predict.lua").New()
    vec(absent.Feet(player,Vector(90,0,0),Vector(),true),Vector(90,0,0))
end
function cases.review_render_hands_current_motor()
    client() tick()
    receipt(Vector(),Vector(),Vector())
    clock=clock+1/66 receipt(Vector(),Vector(),Vector(4,0,0))
    clock=clock+1/66 receipt(Vector(),Vector(),Vector(8,0,0))
    C.Refresh()
    clock=clock+.008 -- render later in the same engine frame; no new native pose/base feet
    local camera=view()
    vec(C.Pose.head.pos,camera.origin,.01)
    local expected=camera.origin+Vector(8,-8,-16)
    vec(C.Hand.right.shown.pos,expected,.01)
    C.Stop()
end
assert(cases[scenario], scenario)()
for _, message in ipairs(log) do assert(not message:find("[nlvr] module", 1, true), message) end
print("PASS " .. scenario)
