local root, scenario, fixturePath = ...
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function close(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local standins = assert(loadfile(root .. "/companion/tests/vr_stubs.lua"))()
standins.Math()
math.Clamp = function(v, low, high) return math.min(high, math.max(low, v)) end
local vmeta = getmetatable(Vector())
function vmeta:Angle() return Angle(math.deg(math.atan2(-self.z, math.sqrt(self.x^2+self.y^2))), math.deg(math.atan2(self.y,self.x)), 0) end
function vmeta:AngleEx(up) local a=self:Angle() a.r=math.deg(math.atan2(up:Dot(a:Right()),up:Dot(a:Up()))) return a end
local function veq(a, b) close((a - b):Length(), 0) end
local M = {} M.__index = M
function Matrix(other)
    local result = setmetatable({}, M)
    for row = 1, 4 do result[row] = {} for col = 1, 4 do result[row][col] = other and other[row][col] or (row == col and 1 or 0) end end
    return result
end
M.__mul = function(a, b)
    local out = Matrix()
    for r = 1, 4 do for c = 1, 4 do
        local n = 0 for k = 1, 4 do n = n + a[r][k] * b[k][c] end out[r][c] = n
    end end
    return out
end
function M:SetTranslation(v) self[1][4],self[2][4],self[3][4] = v.x,v.y,v.z end
function M:GetTranslation() return Vector(self[1][4],self[2][4],self[3][4]) end
function M:GetAngles()
    return Angle(math.deg(math.atan2(-self[3][1],math.sqrt(self[1][1]^2+self[2][1]^2))),
        math.deg(math.atan2(self[2][1],self[1][1])),math.deg(math.atan2(self[3][2],self[3][3])))
end
function M:SetAngles(a)
    local axes = {a:Forward(), -a:Right(), a:Up()}
    for c, v in ipairs(axes) do self[1][c],self[2][c],self[3][c] = v.x,v.y,v.z end
end
function M:Scale(v)
    for r = 1, 3 do self[r][1],self[r][2],self[r][3] = self[r][1]*v.x,self[r][2]*v.y,self[r][3]*v.z end
end
function M:SetScale(v)
    for r = 1, 3 do for c = 1, 3 do self[r][c] = r==c and ({v.x,v.y,v.z})[r] or 0 end end
end
function M:GetInverse()
    local out = Matrix() -- stand-in input bones are rigid; transpose the rotation independently
    for r = 1, 3 do for c = 1, 3 do out[r][c] = self[c][r] end end
    for r = 1, 3 do out[r][4] = 0 for c = 1, 3 do out[r][4] = out[r][4] - out[r][c]*self[c][4] end end
    return out
end
local models, clock, frame, hooks, lines = {}, 0, 1, {}, {}
local player = {valid = true, model = "models/player/test.mdl"}
function player:GetModel() return self.model end
function LocalPlayer() return player end
function IsValid(o) return type(o) == "table" and o.valid == true end
function RealTime() return clock end
function FrameNumber() return frame end
function MsgN() end
table.RemoveByValue = function(t, value) for i=#t,1,-1 do if t[i]==value then table.remove(t,i) end end end
hook=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib")
local hookAdd,hookRemove=hook.Add,hook.Remove
hook.Add=function(event,id,fn,...) hookAdd(event,id,fn,...) hooks[event]=fn end
hook.Remove=function(event,id) hooks[event]=nil hookRemove(event,id) end
surface = {SetDrawColor = function() end, DrawLine = function(...) lines[#lines+1] = {...} end}
RENDERGROUP_OPAQUE, MASK_SOLID_BRUSHONLY = 0, 16395
local info = {model = "models/test_hands.mdl", skin = 2, body = "0101"}
player_manager = {TranslateToPlayerModelName = function(model) return model end, TranslatePlayerHands = function() return info end}
util = {IsValidModel = function(path) return path ~= "bad.mdl" end}
local function skeleton(prefix, missing)
    local ent = {valid = true, names = {}, parents = {}, manipulated = {}, output = {}, skin = 0}
    local function bone(name, parent)
        local id = #ent.names ent.names[id+1], ent.parents[id] = name, parent or -1 return id
    end
    bone("root")
    for _, letter in ipairs({"L", "R"}) do
        local upper = bone(prefix .. letter .. "_UpperArm", 0)
        local forearm = bone(prefix .. letter .. "_Forearm", upper)
        local wrist = bone(prefix .. letter .. "_Hand", forearm)
        for finger=0,4 do
            local parent = wrist
            for joint=0,2 do
                local name = prefix .. letter .. "_Finger" .. finger .. (joint==0 and "" or joint)
                if not missing or not name:find(missing,1,true) then parent = bone(name,parent) end
            end
        end
    end
    bone("__INVALIDBONE__", 0)
    function ent:GetBoneCount() return #self.names end
    function ent:GetBoneName(id) return not self.metadataPending and self.names[id+1] or nil end
    function ent:GetBoneParent(id) return self.parents[id] end
    function ent:ManipulateBoneAngles(id, angle) self.manipulated[id] = angle end
    function ent:SetNoDraw(v) self.nodraw = v end
    function ent:SetSkin(v) self.skin = v end
    function ent:SetBodyGroups(v) self.body = v end
    function ent:SetSequence(v) self.seq = v end
    function ent:SetCycle(v) self.cycle = v end
    function ent:AddCallback(event, fn) eq(event,"BuildBonePositions") self.callback = fn end
    function ent:SetPos(v) self.pos = v end
    function ent:SetAngles(v) self.ang = v end
    function ent:InvalidateBoneCache() self.output = {} end
    function ent:GetBoneMatrix(id)
        if self.output[id] then return self.output[id] end
        local m = Matrix() m:SetTranslation((self.pos or Vector()) + Vector(id, 0, 0))
        m:SetAngles(self.ang or Angle()) return m
    end
    function ent:SetBoneMatrix(id, m) assert(self:GetBoneName(id) ~= "__INVALIDBONE__") self.output[id] = Matrix(m) end
    function ent:SetupBones() self.metadataPending=false if self.callback then self.callback(self) end end
    function ent:DrawModel() self.draws = (self.draws or 0) + 1 if self.fail then error("engine draw failure") end end
    function ent:GetModel() return self.path end
    function ent:Remove() self.valid = false end
    return ent
end
function ClientsideModel(path, group)
    eq(group,RENDERGROUP_OPAQUE)
    local ent = skeleton(path == "no_wrist.mdl" and "unknown" or "ValveBiped.Bip01_",path=="wrist_only.mdl" and "Finger" or nil)
    if scenario=="skeleton_cache" or scenario=="anatomy_reset" or scenario=="render_rate_sampling" then
        function ent:GetBoneMatrix(id)
            local n=self.names[id+1] or "" local finger,joint=n:match("Finger(%d)(%d*)")
            local m=Matrix() m:SetTranslation(finger and Vector(2+(tonumber(joint) or 0),(tonumber(finger)-2)*.8,0) or Vector())
            m:SetAngles(Angle()) return m
        end
    end
    ent.path,ent.metadataPending = path,true models[#models+1] = ent return ent
end
local function clear_trace(data) return {Hit = false, HitPos = data.endpos, HitNormal = Vector(-1,0,0)} end
util.TraceHull = clear_trace
function include(path) return assert(loadfile(root .. "/vr/addon/lua/" .. path))() end
local P = include("nlvr/modules/cl_hands_pose.lua")
local function state(pos)
    local function pose() return {valid=true,pos=pos or Vector(15,-8,55),ang=Angle(),vel=Vector(),angvel=Vector()} end
    return {target=pose(),shown=pose(),blocked=false}
end
local core = {Space={scale=40},Pose={head={valid=true,pos=Vector(0,0,64),ang=Angle()}},
    Input={left={curls={0,0,0,0,0},splay={0,0,0,0}},right={curls={0,0,0,0,0},splay={0,0,0,0}}},
    Hand={left=state(Vector(15,8,55)),right=state()},Settings={ghost_hands=1}, Debug={},Native={}}
function core.ToTracking(pos,ang) return pos/40,ang end
local overlays, paints, events, resolver = {}, 0, {}, nil
core.Overlay = {Sizes={ghost_left={265,267},ghost_right={269,271}}}
function core.Overlay.New(options)
    assert(not overlays[options.key])
    local obj = {key=options.key,visible=false,dirty=true}
    function obj:Show(v) self.wanted=v self.visible=scenario~="verify_pending_ghost" and v or false if not v then self.hides=(self.hides or 0)+1 end end
    function obj:Place(device,pos,ang,width) self.device,self.pos,self.ang,self.width=device,pos,ang,width end
    function obj:Destroy() self.destroyed=true self.visible=false end
    obj.paint = function() if obj.dirty then obj.dirty=false options.paint(obj,options.width,options.height) paints=paints+1 end end
    overlays[obj.key]=obj return obj
end
local Registry = include("nlvr/core/sh_modules.lua")
core.Registry = Registry.New(core)
function core._On(entry,name,fn)
    events[name]=fn
    core.Registry:Own(function() events[name]=nil end,entry)
end
function core._Resolver(entry,priority,fn)
    eq(priority,10) resolver=fn core.Registry:Own(function() resolver=nil end,entry)
end
local function start() core.Registry:Add(include("nlvr/modules/cl_hands.lua")) core.Registry:Start() end
local function tick(dt)
    clock,frame=clock+(dt or 0.02),frame+1
    if events.before_overlay_paint then events.before_overlay_paint() end
    for _,obj in pairs(overlays) do if not obj.destroyed then obj.paint() end end
end
local cases = {}
function cases.skeleton_cache()
    local saved=assert(loadfile(fixturePath))() local calls,busy=0,false
    local data={valid=true,model="valve_controller_knu_1_0_right",revision=1,aim={pos=Vector(),ang=Angle()},hand={pos=Vector(),ang=Angle()}}
    core.Frame={controllers={left=data,right=data}}
    core.Native.Skeleton=function(side,kind,destination)
        calls=calls+1 if busy then return nil,"busy" end
        local v=saved[side][kind] local out={valid=true,source=kind,bones=v.bones}
        return out
    end
    start() tick() local stable=core.HandModelFrames.right
    for i=1,100 do tick(.01) end
    assert(calls>=200 and calls<=205,"reader must follow render frames without duplicate reads "..calls)
    eq(core.HandModelFrames.right,stable)
    local source=core.Debug.hands.right.skeletal_source busy=true data.revision=data.revision+1 tick(.05)
    eq(core.Debug.hands.right.skeletal_source,source)
    eq(core.HandModelFrames.right,stable)
    core.Registry:Stop()
end
function cases.render_rate_sampling()
    local saved=assert(loadfile(fixturePath))() local counts={left=0,right=0}
    local data={valid=true,model="valve_controller_knu_1_0_right",revision=1,aim={pos=Vector(),ang=Angle()},hand={pos=Vector(),ang=Angle()}}
    core.Frame={controllers={left=data,right=data}}
    core.Native.Skeleton=function(side,kind,buffer)
        if kind=="with_controller" then counts[side]=counts[side]+1 end
        return saved[side][kind]
    end
    start() tick()
    for i=1,90 do tick(1/90) end
    assert(counts.left>=89 and counts.right>=89,"finger sampling does not follow render rate: "..counts.right)
    core.Registry:Stop()
end
function cases.anatomy_reset()
    local data={valid=true,model="valve_controller_knu_1_0_right",aim={pos=Vector(),ang=Angle()},hand={pos=Vector(),ang=Angle()}}
    core.Frame={controllers={left=data,right=data}}
    start() tick() assert(core.HandModelFrames.right)
    info={model="wrist_only.mdl"} data.model=data.model.."_changed" tick(.3)
    eq(core.HandModelFrames.right,nil)
    core.Registry:Stop()
end
function cases.verify_pending_ghost()
    start() tick() core.Hand.right.blocked=true tick()
    assert(overlays.ghost_right.wanted and not overlays.ghost_right.visible)
    core.Hand.right.blocked=false tick()
    assert(not overlays.ghost_right.wanted,"hidden pending ghost remained wanted")
    for i=1,5 do tick() end
    assert(overlays.ghost_right.hides==1,"idle hidden ghost issued repeated native hides")
    core.Registry:Stop()
end
function cases.bones()
    local ent = skeleton("ValveBiped.Bip01_")
    local l,r=P.Bones(ent,"left"),P.Bones(ent,"right")
    eq(l.count,17) eq(r.count,17) eq(l.fingerCount,15) eq(l.wrist,3)
    assert(not l.visible[0] and not l.visible[1] and not l.visible[r.wrist])
    assert(l.visible[l.forearm] and l.visible[l.fingers[5][3]])
end
function cases.aliases()
    local ent=skeleton("Bip01 ") local b=P.Bones(ent,"left") eq(b.fingerCount,15) eq(b.count,17)
    ent.names[4]="BIP01_l_HAND" eq(P.Bones(ent,"left").wrist,3)
end
function cases.missing_bones()
    local ent=skeleton("ValveBiped.Bip01_","_Finger42") local b=P.Bones(ent,"right") eq(b.fingerCount,14)
    P.Apply(ent,b,{1,1,1,1,1},{0,0,0,0},"right")
    ent.names[4]="__INVALIDBONE__" eq(P.Bones(ent,"left").wrist,nil)
    ent.names[1]="ValveBiped.Bip01_L_Hand" eq(P.Bones(ent,"left").wrist,0)
end
function cases.angles()
    close(P.Angles(2,2,1,0,"left").y,95) close(P.Angles(2,2,1,0,"right").y,95)
    close(P.Angles(1,2,1,0,"left").p,50) close(P.Angles(1,2,1,0,"right").p,-50)
    close(P.Angles(1,2,0,0,"left").p,0)
end
function cases.splay()
    assert(P.Angles(2,1,0,1,"left").p < 0)
    assert(P.Angles(5,1,0,1,"left").p > 0)
    close(P.Angles(2,2,0,1,"left").p,0) close(P.Angles(2,1,1,1,"left").p,0)
end
function cases.smoothing()
    local a,b={0,0,0,0,0},{0,0,0,0,0}
    for i=1,90 do a=P.Smooth(a,nil,{curls={1,1,1,1,1}},nil,1/90) end
    for i=1,30 do b=P.Smooth(b,nil,{curls={1,1,1,1,1}},nil,1/30) end
    close(a[1],b[1])
    local c=P.Smooth({0,0,0,0,0},nil,{curls={1}},nil,0.01) assert(c[1]>0 and c[1]<1)
end
function cases.grip()
    local c,s=P.Smooth(nil,nil,{curls={0,0,0,0,0},splay={1,1,1,1}},{1,0.8,0.7,0.6,0.5},0)
    close(c[1],1) close(c[5],0.5) close(s[1],0)
end
function cases.sanitization()
    local c=P.Smooth(nil,nil,{curls={-1,2,0/0,math.huge,"x"}},nil,0)
    eq(table.concat(c,","),"0,1,0,1,0")
end
local function plane(data)
    if data.endpos.x + data.maxs.x <= 10 then return clear_trace(data) end
    if data.start.x + data.maxs.x >= 10 then return {Hit=true,StartSolid=true,HitPos=data.start,HitNormal=Vector(-1,0,0)} end
    local f=(10-data.maxs.x-data.start.x)/(data.endpos.x-data.start.x)
    return {Hit=true,HitPos=data.start+(data.endpos-data.start)*f,HitNormal=Vector(-1,0,0)}
end
function cases.wall()
    util.TraceHull=plane local s=state(Vector(30,-8,55)) local target=s.target.pos
    P.Resolve(core,"right",s) eq(s.blocked,true) close(s.shown.pos.x,2.6) veq(s.target.pos,target)
end
function cases.finger_envelope()
    util.TraceHull=plane local s=state(Vector(8,-8,55))
    P.Resolve(core,"right",s) eq(s.blocked,true) close(s.shown.pos.x,2.6)
    assert(s.shown.pos.x+0.18*core.Space.scale<10)
end
function cases.clear()
    local s=state() P.Resolve(core,"right",s) eq(s.blocked,false) veq(s.target.pos,s.shown.pos)
    s.shown.pos.x=s.shown.pos.x+10 close(s.target.pos.x,15)
end
function cases.shoulder()
    local calls=0
    util.TraceHull=function(data)
        calls=calls+1
        if calls==1 then return {Hit=true,HitPos=Vector(0,-3,62),HitNormal=Vector(0,1,0)} end
        veq(data.start,Vector(0,-2.8,62)) return clear_trace(data)
    end
    P.Resolve(core,"right",state()) eq(calls,2)
end
function cases.solid()
    util.TraceHull=function(data) return {StartSolid=true,Hit=true,HitPos=data.start,HitNormal=Vector(0,0,1)} end
    local s=state() P.Resolve(core,"right",s) eq(s.blocked,true) eq(s.shown.valid,false)
    assert(s.shown.pos ~= core.Pose.head.pos and s.shown.pos ~= s.target.pos)
    s.shown.pos.z=s.shown.pos.z+10 close(core.Pose.head.pos.z,64)
    start() tick()
    P.Resolve(core,"right",core.Hand.right)
    hook.Run("PreDrawTranslucentRenderables",false,false)
    eq(models[2].draws,nil) -- a server resolver setting only pos cannot reveal it
    core.Registry:Stop()
end
function cases.lifecycle()
    start() tick() eq(next(overlays),nil) eq(#models,2)
    core.Hand.right.blocked=true tick() eq(overlays.ghost_right.visible,true) eq(paints,1)
    tick() eq(paints,1) eq(core.Debug.hands.right.paints,1)
    local debug, right, curls, splay = core.Debug.hands, core.Debug.hands.right, core.Debug.hands.right.curls, core.Debug.hands.right.splay
    for i=1,100 do tick() end
    eq(core.Debug.hands,debug) eq(debug.right,right) eq(right.curls,curls) eq(right.splay,splay)
    core.Settings.ghost_hands=0 tick() eq(overlays.ghost_right.visible,false)
    core.Settings.ghost_hands=1 tick() eq(overlays.ghost_right.visible,true)
    core.Hand.right.blocked=false tick() eq(overlays.ghost_right.visible,false)
    core.Registry:Stop() eq(hooks.PreDrawTranslucentRenderables,nil) eq(resolver,nil)
    eq(events.before_overlay_paint,nil) eq(models[1].valid,false) eq(overlays.ghost_right.destroyed,true)
end
function cases.models()
    util.IsValidModel=function() return false end -- local arms need not be server-precached
    start() tick() eq(models[1].skin,2) eq(models[1].body,"0101")
    info={model="models/new.mdl",skin=3,body="110"} tick(0.3)
    eq(#models,4) eq(models[1].valid,false) eq(models[3].skin,3) eq(core.Debug.hands.left.model,"models/new.mdl")
    models[3].valid=false tick(0.3) eq(#models,6)
    core.Registry:Stop()
end
function cases.fallback()
    info={model="no_wrist.mdl"} start() tick() eq(#models,4)
    eq(core.Debug.hands.left.fallback,true) eq(core.Debug.hands.left.model,"models/weapons/c_arms_citizen.mdl")
    core.Registry:Stop()
end
function cases.world_draw()
    start() tick() local function draw(...) return hook.Run("PreDrawTranslucentRenderables",...) end
    draw(true,false) draw(false,true) eq(models[1].draws,nil)
    draw(false,false) eq(models[1].draws,1) eq(models[2].draws,1) eq(models[1].nodraw,true)
    core.Hand.right.shown.valid=false draw(false,false) eq(models[1].draws,2) eq(models[2].draws,1)
    core.Registry:Stop()
end
function cases.matrices()
    start() tick() core.Space.scale=80 hook.Run("PreDrawTranslucentRenderables",false,false)
    local ent=models[1] local b=P.Bones(ent,"left")
    veq(ent.output[b.wrist]:GetTranslation(),core.Hand.left.shown.pos)
    for r=1,3 do for c=1,3 do close(ent.output[0][r][c],0) end end
    local m=ent.output[b.wrist] close(math.sqrt(m[1][1]^2+m[2][1]^2+m[3][1]^2),2)
    local before=Matrix(ent.output[b.fingers[1][1]])
    hook.Run("PreDrawTranslucentRenderables",false,false)
    veq(before:GetTranslation(),ent.output[b.fingers[1][1]]:GetTranslation()) core.Registry:Stop()
end
function cases.dominant()
    start() tick() local left=models[1] core.Input.mainHand="left" tick(0.3)
    eq(models[1],left) eq(#models,2) eq(core.Debug.hands.left.model,core.Debug.hands.right.model) core.Registry:Stop()
end
function cases.invalid_tracking()
    start() tick() core.Hand.right.blocked=true core.Hand.right.target.valid=false tick()
    eq(next(overlays),nil) core.Registry:Stop()
end
function cases.fault_cleanup()
    start() tick() models[1].fail=true hook.Run("PreDrawTranslucentRenderables",false,false)
    eq(models[1].valid,false) eq(models[2].valid,false) eq(hooks.PreDrawTranslucentRenderables,nil)
    eq(resolver,nil) eq(core.Debug.hands,nil) core.Registry:Stop()
end
function cases.q4r_dispatch_peer()
    local calls=0
    hook.Add("PreDrawTranslucentRenderables","peer",function() calls=calls+1 return false end,HOOK_MONITOR_HIGH)
    assert(hook.GetULibTable().PreDrawTranslucentRenderables[HOOK_MONITOR_HIGH].peer,"harness discarded monitor priority")
    cases.world_draw() assert(calls>=3,"hand draw bypassed the shared dispatcher")
    hook.Remove("PreDrawTranslucentRenderables","peer")
end
assert(cases[scenario],scenario)() print("PASS " .. scenario)
