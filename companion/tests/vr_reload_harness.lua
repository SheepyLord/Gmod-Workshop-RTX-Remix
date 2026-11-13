-- K-owned fixtures: the engine setters are observable, not a native firing simulator.
local root, scenario, baseline = ...
local S = assert(loadfile(root .. "/companion/tests/vr_stubs.lua"))() S.Math()
local V = getmetatable(Vector()).__index
function V:Angle()
    return Angle(math.deg(math.atan2(-self.z, math.sqrt(self.x * self.x + self.y * self.y))), math.deg(math.atan2(self.y, self.x)), 0)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b) assert(math.abs(a - b) < 0.0001, tostring(a) .. " ~= " .. tostring(b)) end
local function vec(a, b) near((a - b):Length(), 0) end
local now, wall, tick, models, failures = 1, nil, 1, {}, {}
function CurTime() return now end function RealTime() return wall or now end
function IsValid(x) return type(x) == "table" and x.valid ~= false end
function include(p)
    local name=p:match("([^/]+)$")
    local source=baseline and (name=="cl_reload.lua" or name=="sv_reload.lua" or name=="sh_reload.lua") and baseline.."/"..name or root.."/vr/addon/lua/"..p
    return assert(loadfile(source))()
end
function MsgN(s) failures[#failures + 1] = s end
math.Clamp = function(n, a, b) return math.max(a, math.min(b, n)) end
table.RemoveByValue = function(t, x) for i = #t, 1, -1 do if t[i] == x then table.remove(t, i) end end end
engine = {TickCount = function() return tick end}
IN_ATTACK, IN_ATTACK2, IN_RELOAD, MASK_SOLID, RENDERGROUP_OPAQUE = 1, 2048, 8192, 1, 0
local hooks = {}
hook=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib",hooks)
util = {TraceLine = function() return {Hit = false} end}
local readers = {}
local function read() assert(#readers>0,"missing packet field") return table.remove(readers, 1) end
net = {ReadBool = read, ReadEntity = read, ReadUInt = read, ReadInt = read, ReadFloat = read, ReadString = read}
local oldModel=S.Model local entityId=10
S.Model=function(spec) local ent=oldModel(spec) entityId=entityId+1 local id=entityId function ent:EntIndex() return id end return ent end
local R = include("nlvr/modules/sh_reload.lua")
local cases = {}
local engineOracle
local function fixture(class, clip, reserve)
    class = class or "weapon_pistol"
    local d = R.Guns[class]
    local w = S.Weapon{class = class, clip1 = clip or 0, maxClip1 = d and (d.kind=="rpg" and -1 or d.size) or -1, primary = d and 1 or -1, secondary = 2,
        attachments = {{name = "muzzle", pos = d and d.muzzle or Vector(), ang = d and d.axis or Angle()}}}
    w.fields = {m_bInReload = false, m_bMustReload = false, m_bNeedPump = false, m_bDelayedFire1 = false,
        m_bDelayedFire2 = false, m_flHolsterTime = 0}
    w.reads,w.writes = {},{}
    function w:GetInternalVariable(k) self.reads[k]=(self.reads[k] or 0)+1 return k=="m_flHolsterTime" and self.fields[k]-now or self.fields[k] end
    function w:GetSaveTable() return self.fields end
    function w:SetSaveValue(k, v) self.fields[k] = k=="m_flHolsterTime" and now+v or v self.writes[k]=(self.writes[k] or 0)+1 return true end
    function w:SetNextSecondaryFire(v) self.secondaryDeadline=v end
    function w:GetNextSecondaryFire() return self.secondaryDeadline or 0 end
    function w:EmitSound(s) self.sound = s end
    function w:EntIndex() return 2 end
    local p = S.Player{weapons = {w}, active = w, ammo = {[1] = reserve or 45}, ammoMax={[1]=150}}
    function p:GetInternalVariable(k) if k=="m_flNextAttack" then return (self.nextAttack or 0)-now end end
    function p:Alive() return self.alive ~= false end function p:InVehicle() return self.vehicle == true end
    function p:EntIndex() return 1 end
    function p:GetPos() return Vector() end function p:EyePos() return Vector(0, 0, 64) end
    local state = {scale = 40, head = {valid = true, pos = Vector(0, 0, 64), ang = Angle()},
        hands = {right = {valid = true, pos = Vector(16, -12, 48), ang = Angle(), buttons = 0},
            left = {valid = true, pos = Vector(-8, 12, 64), ang = Angle(), buttons = 1}}, lastSync = now}
    return w, p, state
end
local function core()
    local c = {packetBuilds=0,pendingWire={},sentWire={},sentTick={},wireOrder=0,Debug = {}, events = {}, messages = {}, movers = {}, received = {}, Settings = {physical_reload = 1, ammo_counter = 1}, Space = {scale = 40}}
    local Registry = include("nlvr/core/sh_modules.lua")
    c.Registry = Registry.New(c)
    function c._On(entry, name, fn)
        c.events[name] = c.events[name] or {} c.events[name][#c.events[name] + 1] = fn
        c.Registry:Own(function() table.RemoveByValue(c.events[name], fn) end, entry)
    end
    function c._Mover(entry, priority, fn) c.movers[#c.movers + 1] = fn end
    function c._Resolver(entry, priority, fn) c.resolver = fn end
    function c.emit(name, ...) for _, f in ipairs(c.events[name] or {}) do
        local e = c.Registry.entries[1] c.Registry:Call(e, f, ...)
    end end
    c.Emit = c.emit
    function c.flush(p)
        if c.sentTick[p]==tick then return end
        local list=c.pendingWire[p] or {} local selected,kind
        for k,v in pairs(list) do
            if c.sentWire[p] and c.sentWire[p][k]==v.signature then list[k]=nil
            elseif not selected or v.order<selected.order then selected,kind=v,k end
        end
        if selected then
            c.sentWire[p]=c.sentWire[p] or {} c.sentWire[p][kind]=selected.signature
            c.sentTick[p]=tick list[kind]=nil c.messages[#c.messages+1]=selected.out
            if c.deliver then c.deliver(selected.out,p) end
        end
    end
    c.Net = {On = function(n, f) c.received[n] = f end, Send = function(p, n, fn)
        if type(p)=="number" then fn,n,p=n,p,nil end
        c.packetBuilds=c.packetBuilds+1
        local packet=include("nlvr/sh_protocol.lua").Packet(fn)
        local out={kind=n,args={}} local function write(v) out.args[#out.args+1]=v end
        packet.Write({WriteBool=write,WriteUInt=write,WriteInt=write,WriteFloat=write,WriteDouble=write,WriteString=write,WriteEntity=write,WriteVector=write,WriteAngle=write})
        if not p then c.messages[#c.messages+1]=out return end
        c.pendingWire[p]=c.pendingWire[p] or {} c.wireOrder=c.wireOrder+1
        local prior=c.pendingWire[p][n]
        c.pendingWire[p][n]={signature=packet.signature,order=prior and prior.order or c.wireOrder,out=out}
        c.flush(p)
    end}
    function c.receive(n, p, args)
        if n==82 and R.ACK_LEASE and #args==15 then args[#args+1]=0 end
        if n==82 and R.ACK_READY and #args==16 then args[#args+1]=true end
        if n==82 and R.ACK_POLICY and #args==17 then args[#args+1]=args[2] end
        if n==82 and R.ACTION_SERIAL and #args==18 then args[#args+1]=0 args[#args+1]="none" end
        if n==81 and R.ACTION_SERIAL and #args==3 then c.testSerial=(c.testSerial or 0)%65535+1 args[#args+1]=c.testSerial end
        readers = args c.Registry:Call(c.Registry.entries[1], c.received[n], p) eq(#readers, 0)
    end
    return c
end
local function server(class, clip, reserve)
    local w, p, state = fixture(class, clip, reserve)
    local c = core() c.Players = {[p] = state}
    sound = {Play = function(name, pos) w.sound, w.soundPos = name, pos end}
    c.Weapon = function()
        local d = R.Guns[w.class]
        local _, inverse = WorldToLocal(Vector(), Angle(), Vector(), d.frame or Angle())
        local _, aim = LocalToWorld(Vector(), inverse, Vector(), w:GetAngles())
        return {class = w.class, kind = d.kind, muzzle = {pos = LocalToWorld(d.muzzle, Angle(), w:GetPos(), w:GetAngles()), ang = aim}}
    end
    c.Registry:Add(include("nlvr/modules/sv_reload.lua")) c.Registry:Start() c.emit("OnStart", p)
    c.receive(80, p, {true, false})
    local function command(sameTick,fire)
        if not sameTick then tick=tick+1 c.flush(p) end
        state.lastSync = now
        local cmd = S.Command() cmd:AddKey(IN_RELOAD) cmd:AddKey(IN_ATTACK2) if fire then cmd:AddKey(IN_ATTACK) end
        hook.Run("StartCommand",p,cmd)
        if c.engineStep then c.engineStep(w,p,cmd) end
        assert(#failures == 0, table.concat(failures, "\n"))
        return cmd
    end
    local function gesture(k, token, weapon, elapsed)
        elapsed=elapsed or .13
        if wall then wall=wall+elapsed end
        now = now + elapsed tick = tick + 1 state.lastSync = now
        c.receive(81, p, {k, weapon or w, token or 0}) assert(#failures == 0, table.concat(failures, "\n"))
        return c.Debug.reload[1]
    end
    local function take() local d = gesture(1) assert(d.held > 0, d.last_operation) return d.held end
    return c, w, p, state, command, gesture, take
end
function cases.hold()
    for class in pairs(R.Guns) do
        local c, w, p, s, cmd = server(class, class=="weapon_rpg" and -1 or 0, 15)
        c.engineStep=engineOracle
        if class == "weapon_rpg" then p:SetAmmo(14, 1) cmd() p:SetAmmo(13, 1) end
        local buttons = cmd()
        assert(not buttons:KeyDown(IN_RELOAD)) assert(buttons:KeyDown(IN_ATTACK2))
        assert(w:GetNextPrimaryFire() > now + 3000) eq(w:GetInternalVariable("m_bMustReload"), false)
        local endAt = now + 5
        while now < endAt do now = now + 1 / 66 tick = tick + 1 c.receive(80, p, {true, false}) cmd() end
        eq(w:Clip1(), class=="weapon_rpg" and -1 or 0) eq(p:GetActiveWeapon(), w)
        c.Registry:Stop() assert(w:GetNextPrimaryFire() <= now)
    end
end
function cases.release_external()
    local c, w, p, s, cmd = server() cmd() w:SetNextPrimaryFire(now + 9000)
    c.receive(80, p, {false, false}) eq(w:GetNextPrimaryFire(), now + 9000)
end
function cases.secondary_cooldown_survives_hold()
    local c, w, p, s, cmd, act, take = server("weapon_smg1", 0, 45) act(0) cmd()
    local deadline = now + 0.8 w:SetNextSecondaryFire(deadline+1) w:SetNextPrimaryFire(deadline) cmd()
    local token = take() s.hands.left.pos, s.hands.left.ang = R.Guns[w.class].port, R.Guns[w.class].axis
    eq(act(2, token).last_operation, "inserted") near(w:GetNextPrimaryFire(), deadline) near(w:GetNextSecondaryFire(),deadline+1)
end
function cases.disable() local c, w, p, s, cmd = server() cmd() c.receive(80, p, {false, false}) near(w:GetNextPrimaryFire(), now) end
function cases.timeout() local c, w, p, s, cmd = server() cmd() now = now + 2 cmd() near(w:GetNextPrimaryFire(), now) end
function cases.pistol_gate()
    local c,w,p,s,cmd=server() eq(w:GetInternalVariable("m_flSoonestPrimaryAttack"),nil)
    cmd() w:SetNextPrimaryFire(now-.115) cmd() assert(w:GetNextPrimaryFire()>now+3000)
    c.receive(80,p,{false,false}) near(w:GetNextPrimaryFire(),now)
end
function cases.pistol_post_update()
    local c, w, p, s, cmd = server() w.fields.m_flSoonestPrimaryAttack = nil cmd()
    local deadline = w:GetNextPrimaryFire() w:SetNextPrimaryFire(now - 0.115)
    cmd() near(w:GetNextPrimaryFire(), deadline) assert(c.Debug.reload[1].command_primary > 3500)
    c.receive(80, p, {false, false}) assert(w:GetNextPrimaryFire() <= now)
end
function cases.eject()
    local c, w, p, s, cmd, act = server("weapon_pistol", 11, 150)
    eq(p:GiveAmmo(10,1),0) -- pickup is capped at150; SetAmmo is not
    eq(act(0).last_operation, "ejected") eq(w:Clip1(), 0) eq(p:GetAmmoCount(1), 161)
    eq(act(0).last_operation, "ejected") eq(p:GetAmmoCount(1), 161) cmd() assert(w:GetNextPrimaryFire() > now + 3000)
end
function cases.insert()
    for class, size in pairs({weapon_pistol = 18, weapon_357 = 6, weapon_smg1 = 45, weapon_ar2 = 30,
        weapon_shotgun = 1, weapon_crossbow = 1}) do
        local c, w, p, s, cmd, act, take = server(class, 0, 100) cmd()
        if R.Guns[class].kind == "clip" then act(0) end
        local token = take() s.hands.left.pos = R.Guns[class].port s.hands.left.ang = R.Guns[class].axis
        local d = act(2, token) eq(d.last_operation, "inserted") eq(w:Clip1(), size) eq(p:GetAmmoCount(1), 100 - size)
        near(w:GetNextPrimaryFire(), now) assert(w.sound) vec(w.soundPos, R.Point(w, R.Guns[class])) eq(d.held, 0)
        eq(d.last_insertion, "inserted") act(3) eq(c.Debug.reload[1].last_insertion, "inserted")
    end
end
function cases.shotgun()
    local c, w, p, s, cmd, act, take = server("weapon_shotgun", 0, 3)
    for i = 1, 3 do
        s.hands.left.pos = Vector(-8, 12, 64) local token = take()
        s.hands.left.pos, s.hands.left.ang = R.Guns[w.class].port, R.Guns[w.class].axis
        w.fields.m_bInReload, w.fields.m_bDelayedFire1, w.fields.m_bNeedPump = true, true, true
        eq(act(2, token).last_operation, "inserted") eq(w:Clip1(), i) eq(w.fields.m_bInReload, false)
        eq(w.fields.m_bDelayedFire1, false) if i == 1 then eq(w.fields.m_bNeedPump, false) end
    end
    eq(p:GetAmmoCount(1), 0)
end
function cases.crossbow()
    local c, w, p, s, cmd = server("weapon_crossbow", 0, 4)
    w.fields.m_bMustReload = true cmd() eq(w.fields.m_bMustReload, false) eq(p:GetAmmoCount(1), 4)
end
function cases.rpg()
    local c, w, p, s, cmd, act, take = server("weapon_rpg", -1, 3) cmd()
    p:SetAmmo(2, 1) cmd() assert(w:GetNextPrimaryFire() > now + 3000)
    local token = take() s.hands.left.pos, s.hands.left.ang = R.Guns[w.class].port, R.Guns[w.class].axis
    eq(act(2, token).last_operation, "inserted") eq(p:GetAmmoCount(1), 2) eq(w:Clip1(), -1)
    near(w:GetNextPrimaryFire(), now) p:SetAmmo(1, 1) cmd() assert(w:GetNextPrimaryFire() > now + 3000)
end
function cases.reject_far()
    local c, w, p, s, cmd, act, take = server() local token = take()
    act(0)
    s.hands.left.pos = Vector(100, 100, 100) eq(act(2, token).last_operation, "too-far") eq(w:Clip1(), 0)
end
function cases.reject_angle()
    local c, w, p, s, cmd, act, take = server() local token = take()
    act(0)
    s.hands.left.pos = R.Guns[w.class].port s.hands.left.ang = Angle(0, 90, 0)
    eq(act(2, token).last_operation, "alignment")
end
function cases.reject_weapon()
    local c, w, p, s, cmd, act, take = server() local token = take() p.active = S.Weapon()
    eq(act(2, token).last_operation, "weapon") eq(w:Clip1(), 0)
end
function cases.reject_token()
    local c, w, p, s, cmd, act, take = server() local token = take()
    eq(act(2, token + 1).last_operation, "token")
end
function cases.reject_reserve()
    local c, w, p, s, cmd, act = server("weapon_pistol", 0, 0) eq(act(1).last_operation, "reserve")
end
function cases.reject_reserve_changed()
    local c, w, p, s, cmd, act, take = server() local token = take() p:SetAmmo(0, 1)
    eq(act(2, token).last_operation, "reserve")
end
function cases.reject_stale()
    local c, w, p, s, cmd, act, take = server() local token = take() now = now + 0.3 tick = tick + 1
    c.receive(81, p, {2, w, token}) eq(c.Debug.reload[1].last_operation, "stale")
end
function cases.reject_occluded()
    local c, w, p, s, cmd, act, take = server() local token = take()
    act(0)
    s.hands.left.pos, s.hands.left.ang = R.Guns[w.class].port, R.Guns[w.class].axis
    util.TraceLine = function() return {Hit = true} end eq(act(2, token).last_operation, "obstructed")
end
function cases.reject_grip()
    local c, w, p, s, cmd, act = server() s.hands.left.buttons = 0 eq(act(1).last_operation, "zone")
    s.hands.left.buttons = 1 s.interact = {left = {phys = S.Model{pos = Vector(20, 20, 64)}}}
    eq(act(1).last_operation, "zone") eq(c.Debug.reload[1].zone, false)
end
function cases.reject_occupied()
    local c, w, p, s, cmd, act = server() c.Holding = function() return S.Model() end
    eq(act(1).last_operation, "occupied")
end
function cases.reject_magazine()
    local c, w, p, s, cmd, act, take = server() local token = take()
    s.hands.left.pos, s.hands.left.ang = R.Guns[w.class].port, R.Guns[w.class].axis
    eq(act(2, token).last_operation, "magazine-present") eq(w:Clip1(), 0)
end
function cases.reject_carry_expired()
    local c, w, p, s, cmd, act, take = server() local token = take()
    now = now + 31 tick = tick + 1 c.receive(80, p, {true, false})
    eq(act(2, token).last_operation, "stale-ammo")
end
function cases.reject_full()
    local c, w, p, s, cmd, act, take = server("weapon_shotgun", 6, 5) local token = take()
    s.hands.left.pos, s.hands.left.ang = R.Guns[w.class].port, R.Guns[w.class].axis
    eq(act(2, token).last_operation, "full") eq(p:GetAmmoCount(1), 5)
end
function cases.vehicle()
    local c, w, p, s, cmd = server() cmd() p.vehicle = true cmd() near(w:GetNextPrimaryFire(), now)
end
function cases.left_server()
    local c, w, p, s, cmd, act = server() c.receive(80, p, {true, true})
    s.hands.right.pos, s.hands.right.buttons = Vector(-8, -12, 64), 1
    assert(act(1).held > 0)
end
function cases.drop()
    local c, w, p, s, cmd, act, take = server() take() eq(act(3).held, 0) eq(p:GetAmmoCount(1), 45)
end
function cases.death()
    local c, w, p, s, cmd = server() cmd() c.emit("OnDeath", p) near(w:GetNextPrimaryFire(), now)
    eq(c.Debug.reload[1].holding, false) eq(c.Debug.reload[1].held, 0)
end
function cases.zone()
    for _, yaw in ipairs({0, 45, 90, 180, -110}) do
        local head = {valid = true, pos = Vector(10, 20, 64), ang = Angle(60, yaw, 30)}
        for _, side in ipairs({-1, 1}) do
            local off = {valid = true, pos = LocalToWorld(Vector(-0.2, side * 0.3, 0) * 40, Angle(), head.pos, Angle(0, yaw, 0))}
            assert(R.Zone(head, off, 40)) off.pos = head.pos assert(not R.Zone(head, off, 40))
        end
    end
end
function cases.port_transform()
    local w = fixture() local data = R.Guns[w.class]
    for i = 1, 30 do
        w:SetPos(Vector(i, i * 2, i * 3)) w:SetAngles(Angle(i, i * 10, i * 2))
        local _, inverse = WorldToLocal(Vector(), Angle(), Vector(), data.frame)
        local _, aim = LocalToWorld(Vector(), inverse, Vector(), w:GetAngles())
        local muzzle = {pos = LocalToWorld(data.muzzle, Angle(), w:GetPos(), w:GetAngles()), ang = aim}
        local p = R.ServerPort(w, data, muzzle)
        vec(p, R.Point(w, data))
    end
end
function cases.arithmetic()
    for _, d in pairs(R.Guns) do for reserve = 0, 60 do for clip = 0, d.size do
        local result, add = R.Transfer(d, clip, reserve)
        local wanted=math.min(reserve,d.size-clip,d.kind=="shotgun" and 1 or d.size)
        eq(add,wanted) eq(result,clip+wanted) eq(result+reserve-add,clip+reserve)
        if d.kind == "shotgun" then assert(add <= 1) end
    end end end
end
local function client(class)
    local w, p, state = fixture(class, 2, 30)
    LocalPlayer = function() return p end
    function p:GetInternalVariable(k) if k=="m_flNextAttack" then return self.nextAttack or 0 end end
    local c = core() c.Input = include("nlvr/core/cl_input.lua").New()
    c.Pose = {head = state.head, left = state.hands.left, right = state.hands.right}
    for _, hand in ipairs({"left", "right"}) do c.Pose[hand].raw = {pos = c.Pose[hand].pos / 40, ang = c.Pose[hand].ang} end
    c.Hand = {left = {shown = c.Pose.left}, right = {shown = c.Pose.right}}
    c.Weapon = {Active = {ent = w, class = w.class, kind = R.Guns[w.class] and R.Guns[w.class].kind or "swep", hand = "right", model = w}}
    c.ToTracking = function(pos, ang) return pos / 40, ang end
    c.Native = {Haptic = function(hand) c.pulses = (c.pulses or 0) + 1 c.hapticHand = hand return true, 0 end}
    c.Overlay = {Objects = {}, Sizes = {ammo = {387, 129}}}
    c.Overlay.New = function(o)
        o.dirty = true o.paints = 0
        function o:Invalidate() self.dirty = true end
        function o:Place(device, pos, ang, metres) self.device, self.pos = device, pos end
        function o:Show(v) self.visible = v end
        function o:Destroy() self.destroyed = true end
        c.Overlay.Objects[o.key] = o return o
    end
    surface = {CreateFont = function() end} draw = {SimpleText = function() end}
    color_white, TEXT_ALIGN_CENTER = {}, 1 Color = function() return {} end
    local function model(path)
        local m = S.Model{model = path} function m:SetModelScale() end
        function m:Spawn() self.spawned = true end
        function m:GetPhysicsObject() return self.phys or S.NULL end
        if c.boxPhysics then
            function m:GetModelBounds() return Vector(-1, -1, -2), Vector(1, 1, 2) end
            function m:PhysicsInitBox(low, high)
                self.box = {low, high} self.phys = {valid = true}
                function self.phys:EnableMotion(v) self.motion = v end
                function self.phys:EnableGravity(v) self.gravity = v end
                function self.phys:SetVelocity(v) self.velocity = v end
                function self.phys:Wake() self.awake = true end
            end
        end
        models[#models + 1] = m return m
    end
    ClientsideModel = model ents = {CreateClientProp = model}
    c.Registry:Add(include("nlvr/modules/cl_reload.lua")) c.Registry:Start()
    local function frame(actions, withoutCommand, sameTick)
        if c.frameScale then wall=wall or now wall=wall+(c.frameDt or .1) now=now+(c.frameDt or .1)*c.frameScale else now=now+.1 end
        if not sameTick then tick=tick+1 end
        c.Input.Update(actions or {}, now, c.Settings.dominant == 1)
        if c.resolver then for _, hand in ipairs({"left", "right"}) do
            c.Hand[hand] = {shown = c.Pose[hand]}
            c.Registry:Call(c.Registry.entries[1], c.resolver, hand, c.Hand[hand])
        end end
        c.emit("frame") assert(#failures == 0, table.concat(failures, "\n"))
        local cmd = S.Command()
        if not withoutCommand then if c.weaponMove then c.weaponMove(cmd) end for _, f in ipairs(c.movers) do c.Registry:Call(c.Registry.entries[1], f, cmd) end end
        assert(#failures == 0, table.concat(failures, "\n")) return cmd
    end
    local function paint()
        c.emit("before_overlay_paint") assert(#failures == 0, table.concat(failures, "\n"))
        local o = c.Overlay.Objects.ammo
        if o and o.dirty then o.paint(o, 387, 129) o.dirty = false o.paints = o.paints + 1 end
        return o
    end
    c.Input.Update({},now,false) c.emit("frame")
    local initial={w,true,false,true,false,0,0,w:Clip1(),p:GetAmmoCount(1),p:GetAmmoCount(2),"ready","none",0,0,7}
    if R.ACK_LEASE then initial[#initial+1]=0 end
    if R.ACK_READY then initial[#initial+1]=true end
    if R.ACK_POLICY then initial[#initial+1]=true end
    if R.ACTION_SERIAL then initial[#initial+1]=0 initial[#initial+1]="none" end
    c.receive(82,nil,initial)
    return c, w, p, frame, paint
end
local function down(control) return {[control] = {active = true, state = true}} end
function cases.tap_b()
    local c, w, p, f = client("weapon_pistol") c.Settings.physical_reload = 0
    f(down("right_b")) assert(f():KeyDown(IN_RELOAD)) assert(not f():KeyDown(IN_RELOAD))
end
function cases.tap_b_between_commands()
    local c, w, p, f = client("weapon_pistol") c.Settings.physical_reload = 0
    f(down("right_b"), true) f(nil, true) f(nil, true)
    assert(f():KeyDown(IN_RELOAD), "B tap lost between render frames and user command")
    assert(not f():KeyDown(IN_RELOAD), "B tap repeated")
end
function cases.tap_b_preview()
    local c, w, p, f = client("weapon_pistol") c.Settings.physical_reload = 0
    f(down("right_b"), true) f(nil, true)
    for i = 1, 3 do
        local preview = S.Command()
        function preview:CommandNumber() return 0 end
        function preview:TickCount() return 0 end
        for _, mover in ipairs(c.movers) do c.Registry:Call(c.Registry.entries[1], mover, preview) end
    end
    assert(f():KeyDown(IN_RELOAD), "preview command consumed the pending B tap")
    assert(not f():KeyDown(IN_RELOAD), "B tap repeated on another real command")
end
function cases.pending_b_context()
    local c, w, p, f = client("weapon_pistol") c.Settings.physical_reload = 0
    f(down("right_b"), true) f(nil, true)
    c.Settings.physical_reload = 1 assert(not f():KeyDown(IN_RELOAD))
    c.Settings.physical_reload = 0 f(down("right_b"), true) f(nil, true)
    c.Settings.dominant = 1 assert(not f():KeyDown(IN_RELOAD))
    c.Settings.dominant = 0 f(down("right_b"), true) f(nil, true)
    c.Weapon.Active = {ent = S.Weapon{class = "weapon_medkit"}, class = "weapon_medkit", kind = "swep", hand = "right", model = w}
    assert(not f():KeyDown(IN_RELOAD))
end
function cases.hold_b()
    local c, w, p, f = client("weapon_pistol") c.Settings.physical_reload = 0
    for i = 1, 5 do f(down("right_b")) end assert(not f():KeyDown(IN_RELOAD))
end
function cases.physical_b()
    local c, w, p, f = client("weapon_pistol") f(down("right_b")) assert(not f():KeyDown(IN_RELOAD))
end
function cases.swep_b()
    local c, w, p, f = client("weapon_medkit") f(down("right_b")) assert(f():KeyDown(IN_RELOAD))
end
function cases.tap_a()
    local c, w, p, f = client("weapon_pistol")
    f(down("right_a")) assert(not f():KeyDown(IN_ATTACK2))
    local a = c.messages[#c.messages] eq(a.kind, 81) eq(a.args[1], 0)
end
function cases.hold_a()
    local c, w, p, f = client("weapon_pistol")
    for i = 1, 5 do local cmd = f(down("right_a")) if i == 5 then assert(cmd:KeyDown(IN_ATTACK2)) end end
    f() for _, m in ipairs(c.messages) do assert(m.kind ~= 81) end
end
function cases.counter()
    local c, w, p, f, paint = client("weapon_pistol") f()
    local o = paint() eq(o.width, 387) eq(o.height, 129) eq(o.paints, 1) eq(o.device, "right")
    for i = 1, 10 do f() paint() end eq(o.paints, 1)
    w:SetClip1(1) paint() eq(o.paints, 2) p:SetAmmo(10, 2) paint() eq(o.paints, 3)
    c.Overlay.Objects.wheel = {visible = true} paint() eq(o.visible, false)
    c.Overlay.Objects.wheel.visible = false paint() eq(o.visible, true) eq(o.paints, 3)
    c.Settings.ammo_counter = 0 paint() eq(o.visible, false)
    c.Registry:Stop() eq(o.destroyed, true)
end
function cases.no_ammo() local c, w, p, f, paint = client("weapon_crowbar") w.secondary = -1 f() eq(paint(), nil) end
function cases.claims()
    local c, w, p, f = client("weapon_pistol") f(down("left_grip")) eq(c.Input.Owner("off", "grip"), "reload")
end
function cases.counter_left()
    local c, w, p, f, paint = client("weapon_pistol")
    c.Settings.dominant = 1 c.Weapon.Active.hand = "left" f() eq(paint().device, "left")
end
function cases.counter_late_weapon_switch()
    local c, w, p, f, paint = client("weapon_pistol") f() paint()
    local nextWeapon = S.Weapon{class = "weapon_smg1", clip1 = 14, primary = 1, secondary = -1}
    c.Weapon.Active = {ent = nextWeapon, class = "weapon_smg1", kind = "clip", hand = "right", model = nextWeapon}
    local text = {} draw.SimpleText = function(s) text[#text + 1] = s end
    paint() eq(text[1], "14 / 30")
end
function cases.models_cleanup()
    local c, w, p, f = client("weapon_pistol") f()
    local function ack(ejected, token)
        c.receive(82, nil, {w, true, ejected, true, false, 0, token, 0, 45, 4, "ready", "none", 0, 1, 7})
    end
    ack(true, 0) assert(models[1].spawned)
    ack(true, 9) f(down("left_grip")) assert(#models >= 2)
    c.Registry:Stop() for _, model in ipairs(models) do eq(model.valid, false) end
end
function cases.carry_occupies_hand()
    local c, w, p, f = client("weapon_smg1") f()
    c.receive(82, nil, {w, true, true, true, false, 0, 4, 0, 45, 4, "taken", "none", 0, 1, 1})
    f(down("left_grip")) f(down("left_grip"))
    assert(c.Hand.left.held and IsValid(c.Hand.left.held.ent)) eq(c.Hand.left.grip_curls[3], 0.85)
    c.Registry:Stop() eq(c.Hand.left.held, nil)
end
function cases.carry_first_resolver()
    local c, w, p, f = client("weapon_smg1") f(down("left_grip"))
    c.receive(82, nil, {w, true, true, true, false, 0, 4, 0, 45, 4, "taken", "none", 0, 1, 1})
    local shown = {shown = c.Pose.left}
    c.Registry:Call(c.Registry.entries[1], c.resolver, "left", shown)
    assert(shown.held, "first granted frame must block the foregrip before W runs")
    eq(shown.grip_curls[3], 0.85)
    c.Hand.left = shown
    f(down("left_grip")) -- the first marker predates this newly created visual
    c.Registry:Stop()
    eq(c.Hand.left.held, nil)
    for _, model in ipairs(models) do eq(model.valid, false) end
end
function cases.drops_expire()
    local c, w, p, f = client("weapon_pistol") f()
    c.receive(82, nil, {w, true, true, true, false, 0, 0, 0, 45, 4, "ejected", "none", 0, 1, 0})
    eq(#models, 1) now = now + 9 f() eq(models[1].valid, true)
    now = now + 1 f() eq(models[1].valid, false)
end
function cases.empty_client()
    local c, w, p, f = client("weapon_pistol") p:SetAmmo(0, 1) f(down("left_grip"))
    for _, m in ipairs(c.messages) do assert(m.kind ~= 81) end
end
function cases.foregrip_secondary()
    local c, w, p, f = client("weapon_smg1") c.Weapon.Active.twoHanded = true
    local owner = c.Input.Owner
    c.Input.Owner = function(hand, control)
        if hand == "off" and control == "trigger" then return "weapons" end return owner(hand, control)
    end
    assert(f(down("left_trigger")):KeyDown(IN_ATTACK2))
end
function cases.rpg_empty()
    local c, w, p, s, cmd = server("weapon_rpg", -1, 0) cmd() eq(c.Debug.reload[1].clip, 0)
end
function cases.scaled_point()
    local w = fixture() w.GetModelScale = function() return 2 end
    w:SetPos(Vector(10, 20, 30)) w:SetAngles(Angle(10, 35, 60))
    vec(R.Point(w, R.Guns[w.class]), LocalToWorld(R.Guns[w.class].port * 2, Angle(), w:GetPos(), w:GetAngles()))
end
function cases.aim_frame_port()
    local d = {port = Vector(2, -3, 1), muzzle = Vector(10, -20, 3), axis = Angle(0, -90, 0), frame = Angle(0, 90, 90)}
    for _, scale in ipairs({20, 40, 80}) do
        local muzzle = {pos = Vector(4, 5, 6), ang = Angle(10, 35, -20)}
        local p, a = R.ServerPort(nil, d, muzzle, scale)
        local offset, rotation = LocalToWorld((d.port - d.muzzle) * (scale / 40), d.axis, Vector(), d.frame)
        local expected = LocalToWorld(offset, rotation, muzzle.pos, muzzle.ang)
        vec(p, expected) assert(R.Finite(a.p))
    end
end
function cases.eject_ack_once()
    local c, w, p, f = client("weapon_pistol") f()
    local function ack() c.receive(82, nil, {w, true, true, true, false, 0, 0, 0, 45, 4, "ejected", "none", 0, 1, 7}) end
    ack() ack() eq(#models, 1)
    local active = c.Weapon.Active c.Weapon.Active = nil f() c.Weapon.Active = active f()
    ack() eq(#models, 1)
end
function cases.release_drop_once()
    local c, w, p, f = client("weapon_pistol") f()
    c.receive(82, nil, {w, true, false, true, false, 0, 7, 0, 45, 4, "taken", "none", 0, 0, 1})
    f(down("left_grip")) eq(#models, 1)
    for i = 1, 5 do f() end eq(#models, 2) eq(models[1].valid, false) assert(models[2].spawned)
end
function cases.coalesced_carry()
    local c, w, p, f = client("weapon_pistol") f()
    c.receive(82, nil, {w, true, false, true, false, 0, 7, 0, 45, 4, "taken", "none", 0, 0, 1})
    for i = 1, 25 do
        if i%5==0 then c.receive(82,nil,{w,true,false,true,false,0,7,0,45,4,"taken","none",0,0,7}) end
        f(down("left_grip"))
    end
    eq(#models, 1) assert(IsValid(models[1])) eq(c.Input.Owner("off", "grip"), "reload")
end
function cases.haptic_ack_once()
    local c, w, p, f = client("weapon_pistol") f()
    local function ack() c.receive(82, nil, {w, true, false, true, false, 0, 0, 18, 45, 4, "inserted", "inserted", 1, 0, 2}) end
    ack() ack() f() eq(c.pulses, 1) eq(c.hapticHand, "left") eq(c.Debug.reload.haptic_ok, true) eq(c.Debug.reload.haptic_error, 0)
end
function cases.dependency_failure_server()
    local c, w, p, s, cmd = server() cmd() c.Weapon = nil cmd() near(w:GetNextPrimaryFire(), now)
end
function cases.dependency_failure_client()
    local c, w, p, f = client("weapon_pistol") f()
    c.Weapon = nil c.emit("frame")
    eq(c.Registry.entries[1].active, false) eq(#failures, 1) assert(failures[1]:find("physical reload released", 1, true))
    local message = c.messages[#c.messages] eq(message.kind, 80) eq(message.args[1], false)
    failures = {}
end
function cases.proxy_trace_filter()
    local c, w, p, s, cmd, act, take = server() act(0) local token = take()
    s.hands.left.pos, s.hands.left.ang = R.Guns[w.class].port, R.Guns[w.class].axis
    local left, right = S.Model(), S.Model() s.interact = {left = {proxy = left}, right = {proxy = right}}
    util.TraceLine = function(tr)
        local found = {} for _, ent in ipairs(tr.filter) do found[ent] = true end
        assert(found[left] and found[right] and found[p] and found[w]) return {Hit = false}
    end
    eq(act(2, token).last_operation, "inserted")
end
function cases.death_client()
    local c, w, p, f = client("weapon_pistol") f()
    c.receive(82, nil, {w, true, false, true, false, 0, 7, 0, 45, 4, "taken", "none", 0, 0, 1})
    f(down("left_grip")) p.alive = false f() eq(models[1].valid, false) eq(c.Debug.reload.held, 0)
    p.alive = true f() eq(#models, 1)
end
function cases.physics_mesh_fallback()
    local c, w, p, f = client("weapon_357") f() c.boxPhysics = true
    c.receive(82, nil, {w, true, true, true, false, 0, 0, 0, 45, 4, "ejected", "none", 0, 1, 0})
    local m = models[1] assert(m.box and m.spawned) assert(m.phys.motion and m.phys.gravity and m.phys.awake)
    near(m.phys.velocity.z, -35) f() eq(c.Debug.reload.drop_physics, 1)
end
assert(loadfile(root .. "/companion/tests/vr_reload_review_cases.lua"))()(cases, {
 S=S,R=R,server=server,client=client,down=down,eq=eq,near=near,hooks=hooks,
 advance=function(dt,scale,sameTick) wall=wall or now wall=wall+dt now=now+dt*(scale or 1) if not sameTick then tick=tick+1 end end,
 tick=function() return tick end,
 time=function() return now end,
 advanceTick=function() tick=tick+1 end,
 state=function(ply)
   local seen={}
   local function find(fn)
     if seen[fn] then return end seen[fn]=true
     for i=1,50 do local k,v=debug.getupvalue(fn,i) if not k then break end
       if type(v)=="table" and v[ply] and v[ply].guns then return v[ply] end
       if type(v)=="function" then local got=find(v) if got then return got end end
     end
   end
   return assert(find(hooks.StartCommand["nlvr.reload"]),"reload state upvalue not found")
 end,
 setOracle=function(fn) engineOracle=fn end,
})
function cases.q4r_dispatch_peer()
    local calls=0
    hook.Add("StartCommand","peer",function() calls=calls+1 return false end,HOOK_MONITOR_HIGH)
    cases.eject() assert(calls>0,"reload command bypassed the shared dispatcher")
    hook.Remove("StartCommand","peer")
end
assert(cases[scenario], scenario)()
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS " .. scenario)
