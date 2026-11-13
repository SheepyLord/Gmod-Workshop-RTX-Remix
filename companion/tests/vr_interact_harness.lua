local root,case=...
local S=assert(loadfile(root.."/companion/tests/vr_stubs.lua"))()
S.Math()
math.Clamp=function(v,a,b) return math.min(b,math.max(a,v)) end
local function close(a,b,tolerance) assert(math.abs(a-b)<(tolerance or 0.0001),tostring(a).." ~= "..tostring(b)) end
local function vec(a,b,tolerance) close((a-b):Length(),0,tolerance) end
local V=getmetatable(Vector())
function V:Angle() return Angle(math.deg(math.atan2(-self.z,math.sqrt(self.x^2+self.y^2))),math.deg(math.atan2(self.y,self.x)),0) end
function V:AngleEx(up)
    local a=self:Angle()
    a.r=math.deg(math.atan2(up:Dot(a:Right()),up:Dot(a:Up())))
    return a
end
function include(path) return assert(loadfile(root.."/vr/addon/lua/"..path))() end
local clock,tick=1,66
CurTime=function() return clock end RealTime=CurTime
engine={TickCount=function() return tick end,TickInterval=function() return 1/66 end}
IsValid=function(e) return type(e)=="table" and e.valid==true end
isvector=function(v) return getmetatable(v)==V end
isangle=function(a) return getmetatable(a)==getmetatable(Angle()) end
local hooks,events,cleanup,errors={},{},{},{}
hook=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib")
MsgN=function(s) errors[#errors+1]=s end
local convars={ai_serverragdolls="0",sv_playerpickupallowed="1"}
GetConVar=function(name)
    if convars[name] then return {GetBool=function() return convars[name]~="0" end,GetString=function() return convars[name] end} end
end
RunConsoleCommand=function(name,value) convars[name]=value end
bit=require("bit")
SOLID_VPHYSICS,MASK_SOLID,MASK_SHOT,MASK_PLAYERSOLID,CONTENTS_LADDER,USE_ON,DMG_CLUB=6,1,2,4,8,1,128
physenv={GetGravity=function() return Vector(0,0,-600) end}
constraint={HasConstraints=function(e) return e.constrained==true end}
local entities,nextid={},1
local E={}
E.__index=E
local Phys={}
Phys.__index=Phys
function Phys:GetPos() return self.pos end
function Phys:GetAngles() return self.ang end
function Phys:SetPos(v) self.pos=v end
function Phys:SetAngles(a) self.ang=a end
function Phys:GetMass() return self.mass end
function Phys:GetMassCenter() return Vector() end
function Phys:SetMass(n) self.mass=n end
function Phys:EnableGravity(b) self.gravity=b end
function Phys:IsGravityEnabled() return self.gravity end
function Phys:EnableDrag() end
function Phys:EnableCollisions(b) self.collisions=b end
function Phys:Wake() end
function Phys:IsMotionEnabled() return self.motion end
function Phys:GetMeshConvexes() return self.mesh end
function Phys:GetVelocity() return self.velocity end
function Phys:GetAngleVelocity() return self.spin end
function Phys:SetVelocity(v) self.velocity=v end
function Phys:AddAngleVelocity(v) self.spin=self.spin+v end
function Phys:ApplyForceCenter(v) self.force=v self.velocity=self.velocity+v/self.mass end
function Phys:ApplyForceOffset(v) self.impulse=v end
local function phys(pos,mass)
    return setmetatable({valid=true,pos=pos or Vector(),ang=Angle(),mass=mass or 10,motion=true,gravity=true,
        collisions=true,velocity=Vector(),spin=Vector(),mesh={}},Phys)
end
function E:IsWorld() return self.class=="worldspawn" end
function E:IsNPC() return self.class=="npc_citizen" end
function E:IsPlayer() return self.class=="player" end
function E:GetClass() return self.class end
function E:GetTable() return setmetatable({},{__index=E}) end
function E:EntIndex() return self.id end
function E:GetPos() return self.pos end
function E:GetAngles() return self.ang or Angle() end
function E:WorldSpaceAABB() local ext=self.ext or Vector(2,2,2) return self.pos-ext,self.pos+ext end
function E:WorldSpaceCenter() return self.pos+Vector(0,0,36) end
function E:EyePos() return self.pos+Vector(0,0,64) end
function E:GetPhysicsObjectCount() return #self.bones end
function E:GetPhysicsObjectNum(bone) return self.bones[bone+1] end
function E:GetPhysicsObject() return self.bones[1] end
function E:NearestPoint(p)
    local q=p-self.pos local ext=self.ext or Vector(2,2,2)
    return self.pos+Vector(math.Clamp(q.x,-ext.x,ext.x),math.Clamp(q.y,-ext.y,ext.y),math.Clamp(q.z,-ext.z,ext.z))
end
function E:SetModel() end
function E:SetPos(v) self.pos=v end
function E:SetAngles(a) self.ang=a end
function E:SetNoDraw(b) self.nodraw=b end
function E:GetNoDraw() return self.nodraw==true end
function E:DrawShadow(b) self.shadow=b end
function E:SetPreventTransmit(_,b) self.hidden=b end
function E:Spawn() end
function E:PhysicsInitSphere(r) self.radius=r self.bones={phys(self.pos,8)} end
function E:SetSolid() end
function E:GetCustomCollisionCheck() return self.custom or false end
function E:SetCustomCollisionCheck(b) self.custom=b end
function E:CollisionRulesChanged() self.rules=(self.rules or 0)+1 end
function E:AddCallback(_,fn) self.callback=fn return 1 end
function E:RemoveCallback() self.callback=nil end
function E:Remove() self.valid=false for _,p in ipairs(self.bones) do p.valid=false end end
function E:Alive() return self.alive~=false end
function E:InVehicle() return self.vehicle==true end
function E:Crouching() return false end
function E:GetHull() return Vector(-16,-16,0),Vector(16,16,72) end
function E:GetHullDuck() return Vector(-16,-16,0),Vector(16,16,36) end
function E:SetVelocity(v) self.velocity=v end
function E:GetVelocity() return self.velocity or Vector() end
function E:TakeDamageInfo(info) self.health=(self.health or 100)-info.damage end
function E:Use() self.used=(self.used or 0)+1 end
local function entity(class,pos,mass)
    local e=setmetatable({valid=true,id=nextid,class=class or "prop_physics",pos=pos or Vector(),bones={phys(pos,mass)}},E)
    nextid=nextid+1 entities[#entities+1]=e return e
end
local ply=entity("player")
player={GetAll=function() return {ply} end}
ents={Create=entity,FindByClass=function() return {} end,FindInBox=function(a,b)
    local result={}
    for _,e in ipairs(entities) do
        if IsValid(e) then
            local extent=e.ext or Vector(2,2,2)
            local p=e:GetPos()
            if p.x+extent.x>=a.x and p.x-extent.x<=b.x and p.y+extent.y>=a.y and p.y-extent.y<=b.y and p.z+extent.z>=a.z and p.z-extent.z<=b.z then result[#result+1]=e end
        end
    end
    return result
end}
local forcedTrace
util={TraceLine=function(t)
    if forcedTrace then return forcedTrace(t) end
    return {Hit=false,HitPos=t.endpos,HitNormal=Vector(0,0,1),Fraction=1,StartSolid=false}
end}
util.TraceHull=function(t) return util.TraceLine(t) end
DamageInfo=function()
    return {SetAttacker=function() end,SetInflictor=function() end,SetDamageType=function() end,
        SetDamage=function(self,d) self.damage=d end,SetDamagePosition=function() end,SetDamageForce=function(self,v) self.force=v end}
end
local function pose(p,v,spin)
    return {valid=true,pos=p or Vector(),ang=Angle(),vel=v or Vector(),angvel=spin or Vector(),buttons=0}
end
local state={scale=40,lastSync=clock,head=pose(Vector(0,0,64)),hands={left=pose(Vector(10,8,40)),right=pose(Vector(10,-8,40))},history={left={},right={}}}
local sent,handlers={},{}
local ctx={core={},Players={[ply]=state},Debug={}}
ctx.Reach=function() return state.scale*2.5 end
function ctx.hook(name,fn) hooks[name]=fn hook.Add(name,"nlvr.interact",fn) end
function ctx.On(name,fn) events[name]=fn end
function ctx.cleanup(fn) cleanup[#cleanup+1]=fn end
function ctx.Emit(name,...) if events[name] then events[name](...) end end
function ctx.mover(_,fn) ctx.move=fn end
ctx.Net={On=function(k,fn) handlers[k]=fn end,Send=function(p,k,fn) sent[k]=include("nlvr/sh_protocol.lua").Packet(fn) end}
local M=include("nlvr/modules/sv_interact_math.lua")
local module=include("nlvr/modules/sv_interact.lua")
local function start()
    module.Start(ctx) events.OnStart(ply,state)
    state.interact.options={gloves=true,climb=true,melee=true}
    state.interact.controls={left={grip=true,trigger=true},right={grip=true,trigger=true}}
end
local function stop() module.Stop() for i=#cleanup,1,-1 do cleanup[i]() end end
local function step()
    clock,tick=clock+1/66,tick+1 state.lastSync=clock hook.Run("Tick")
end
local cases={}
local function syncedHands(motor,handVelocity)
    -- Run the real validated sync path, not a reconstruction of its velocity conversion.
    local originalHook,originalNet,originalGame=hook,net,game
    local registrations={}
    hook=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib",registrations)
    game={SinglePlayer=function() return true end}
    local w=S.Wire() w.Receivers={} net=w
    local protocol=include("nlvr/sh_protocol.lua")
    local sv=include("nlvr/core/sv_core.lua").New(protocol) sv.Modules={}
    ply.velocity=motor assert(sv.Start(ply,40))
    local function sample(p)
        p.vel=handVelocity p.grip_force=0 p.trigger_value=0 p.curls={0,0,0,0,0} return p
    end
    local data={seq=1,head=pose(ply:EyePos()),hands={left=sample(pose(Vector(10,8,40))),right=sample(pose(Vector(10,-8,40)))}}
    protocol.WriteSync(w,data) w.Rewind()
    assert(sv.Receive(protocol.SYNC,protocol.SYNC_BITS,ply))
    local result=sv.Players[ply].hands sv.Stop()
    hook,net,game=originalHook,originalNet,originalGame
    return result
end
function cases.verify_walk_not_punch()
    start() step()
    local npc=entity("npc_citizen",Vector(13,0,40)) npc.health=40
    state.hands=syncedHands(Vector(200,0,0),Vector())
    forcedTrace=function(t) return {Hit=t.mask==MASK_SHOT,Entity=npc,HitPos=t.endpos,HitNormal=Vector(-1,0,0),Fraction=.8,StartSolid=false} end
    for i=1,3 do step() end
    assert(npc.health==40 and (not npc.velocity or npc.velocity:Length()==0),"locomotion with still hands punched/pushed an NPC")
    state.hands=syncedHands(Vector(),Vector(80,0,0)) clock=clock+1
    step() assert(npc.health<40 and npc.velocity:Length()>0,"a real hand punch must still hit")
    forcedTrace=nil stop()
end
function cases.verify_bare_contact_world_velocity()
    start() step()
    state.hands=syncedHands(Vector(200,0,0),Vector())
    local npc=entity("npc_citizen",Vector(15,0,40)) npc.health=40
    local h=state.interact.right
    h.proxy.callback(h.proxy,{HitEntity=npc,HitPos=npc.pos,Speed=999,OurOldVelocity=Vector(200,0,0)})
    step() assert(npc.health==40,"walking proxy collision caused melee damage")
    clock=clock+1
    h.proxy.callback(h.proxy,{HitEntity=npc,HitPos=npc.pos,Speed=999,OurOldVelocity=Vector(280,0,0)})
    step() assert(npc.health<40,"real relative proxy collision must still hit")
    stop()
end
function cases.verify_held_contact_world_velocity()
    start() step()
    local prop=entity("prop_physics",state.hands.right.pos+Vector(3,0,0))
    local npc=entity("npc_citizen",Vector(30,0,40)) npc.health=40
    assert(ctx.core.Grab(ply,"right",prop,0))
    state.hands=syncedHands(Vector(200,0,0),Vector()) state.hands.right.buttons=1
    prop.callback(prop,{HitEntity=npc,HitPos=npc.pos,Speed=999,OurOldVelocity=Vector(200,0,0)})
    step()
    assert(npc.health==40 and (not npc.velocity or npc.velocity:Length()==0),"walking with a still held prop hurt/pushed an NPC")
    clock=clock+1
    prop.callback(prop,{HitEntity=npc,HitPos=npc.pos,Speed=999,OurOldVelocity=Vector(280,0,0)})
    step() assert(npc.health<40 and npc.velocity:Length()>0,"a real held-prop strike must still hit")
    stop()
end
function cases.verify_walk_not_glove_flick()
    start() step()
    state.hands=syncedHands(Vector(-200,0,0),Vector())
    local h=state.interact.right local p=state.hands.right p.buttons=1 h.wasGrip=true
    local ent=entity("prop_physics",p.pos+Vector(100,0,0))
    h.lock={target={ent=ent,phys=ent:GetPhysicsObject(),bone=0},pos=p.pos+Vector(10,0,0),at=clock}
    step() assert(not h.pull,"walking backward fired a gravity-glove flick")
    stop()
end
function cases.verify_carry_constraints()
    start() step()
    local ent=entity("prop_physics",state.hands.right.pos+Vector(3,0,0))
    assert(ctx.core.Grab(ply,"right",ent,0)) ent.constrained=true
    local position=ent:GetPhysicsObject():GetPos()
    ctx.Emit("teleport_delta",ply,Vector(200,0,0))
    assert(not ctx.core.Holding(ply,"right"),"teleport must release constrained bodies")
    vec(ent:GetPhysicsObject():GetPos(),position) stop()
end
function cases.verify_carry_wall()
    start() step()
    local ent=entity("prop_physics",state.hands.right.pos+Vector(3,0,0))
    assert(ctx.core.Grab(ply,"right",ent,0))
    local position=ent:GetPhysicsObject():GetPos()
    -- Player's eye/proxy path is clear, but the carried body's swept bounds are blocked.
    ent.WorldSpaceAABB=function() return position-Vector(2,2,2),position+Vector(2,2,2) end
    forcedTrace=function(t)
        local body=t.mins and math.abs(t.mins.x)>=2 and t.start.z<50
        return {Hit=body,StartSolid=false,HitPos=body and t.start+Vector(5,0,0) or t.endpos,HitNormal=Vector(-1,0,0),Fraction=body and .025 or 1}
    end
    ctx.Emit("teleport_delta",ply,Vector(200,0,0))
    assert(not ctx.core.Holding(ply,"right"),"blocked held body stayed held beyond wall")
    assert((ent:GetPhysicsObject():GetPos()-position):Length()<20,"held body teleported through wall")
    forcedTrace=nil stop()
end
function cases.verify_glove_moving_cost()
    local triangles=0 local originalTriangle=M.Triangle
    M.Triangle=function(...) triangles=triangles+1 return originalTriangle(...) end
    local oldInclude=include include=function(path) if path=="nlvr/modules/sv_interact_math.lua" then return M end return oldInclude(path) end
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx) include=oldInclude
    local ent=entity("prop_physics",Vector(100,0,40))
    ent.bones[1].mesh={{{pos=Vector(0,-2,-2)},{pos=Vector(0,2,-2)},{pos=Vector(0,0,2)}}}
    for i=1,66 do
        clock=clock+1/66
        for _,hand in ipairs({"left","right"}) do P.GloveClosest(ent,Vector(i*3,hand=="left" and 0 or 10,40),40,hand) end
    end
    assert(triangles<=22,"moving hands exceeded 10 mesh queries/s each: "..triangles)
end
function cases.verify_heavy_perceptible_lag()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local body=phys(Vector(),250) body:EnableGravity(false)
    local goal=Vector(20,0,0)
    for i=1,40 do
        P.Drive({phys=body,localPos=Vector(),localAng=Angle()},nil,{phys=phys(goal)},nil,pose(goal),40,1/66)
        body.pos=body.pos+body.velocity/66
    end
    assert((goal-body.pos):Length()>3,"250 kg hold settled too quickly to preserve perceptible mass lag")
end
function cases.verify_heavy_moving_lag()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local body=phys(Vector(),250) body:EnableGravity(false)
    local velocity=Vector(40,0,16) local peak,visible=0,0 local dt=1/66
    for i=1,33 do
        local goal=velocity*(i*dt) local target=pose(goal) target.wvel=velocity
        P.Drive({phys=body,localPos=Vector(),localAng=Angle()},nil,{phys=phys(goal)},nil,target,40,dt)
        body.pos=body.pos+body.velocity*dt
        peak=math.max(peak,(goal-body.pos):Length())
        if (goal-body.pos):Length()>3 then visible=visible+dt end
    end
    -- The combined fixture measured only 2.94 units with the former gains. Keep
    -- margin above its unchanged 3-unit acceptance for this real ramp derivative.
    assert(peak>3.3 and peak<8,"moving 250 kg hold has insufficient perceptible lag: "..peak)
    assert(visible>=.36,"heavy lag above 3 units must last through the gesture: "..visible)
end
function cases.review_ragdoll_setting()
    local writes=0
    RunConsoleCommand=function(name,value) if name=="ai_serverragdolls" then writes=writes+1 end convars[name]=value end
    for _,value in ipairs({"0","1"}) do
        convars.ai_serverragdolls=value start() step() stop()
        assert(convars.ai_serverragdolls==value and writes==0,"VR must never write ai_serverragdolls")
    end
end
function cases.review_climb_delays()
    for delay=0,3 do
        local origin,refs,queue=Vector(),{},{}
        local anchor=Vector(10,0,50)
        for i=1,180 do
            local old=queue[math.max(1,#queue-delay)] or Vector()
            local pull=math.min(12,math.max(0,i-30)*.2)
            local head={valid=true,pos=old+Vector(0,0,64)}
            local hands={left={valid=true,pos=old+anchor-Vector(0,0,pull)}}
            local delta=M.ClimbRelative(origin,head,hands,{left=anchor},refs,12)
            origin=origin+delta queue[#queue+1]=origin
            assert(origin:Length()<=12.0001,"delayed climb grew")
        end
        close(origin.z,12)
    end
end
function cases.review_proxy_walk()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    for _,speed in ipairs({200,400}) do
        local h={name="right"}
        local target=pose(Vector(10,0,40),Vector()) target.wvel=Vector(speed,0,0)
        ply.velocity=target.wvel
        P.Proxy(ply,h,target,3)
        P.Follow(ply,h,target,40)
        vec(h.phys:GetVelocity(),target.wvel) -- zero error isolates world feed-forward
        for i=1,180 do
            target.pos=target.pos+target.wvel/66 ply.pos=ply.pos+target.wvel/66
            P.Follow(ply,h,target,40)
            if i>60 then assert(not h.blocked and (target.pos-h.phys:GetPos()):Length()<.8,"walking hand lag/ghost") end
            h.phys:SetPos(h.phys:GetPos()+h.phys:GetVelocity()/66)
        end
        P.RemoveProxy(h) ply.pos,ply.velocity=Vector(),Vector()
    end
end
function cases.review_spring_masses()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    for _,mass in ipairs({.5,1,10,250,.2}) do
        local body=phys(Vector(),mass) body:EnableGravity(false)
        local target=pose(Vector(30,0,0))
        local h={phys=phys(target.pos)}
        local grip={phys=body,localPos=Vector(),localAng=Angle()}
        local settled
        for i=1,330 do
            P.Drive(grip,nil,h,nil,target,40,1/66)
            body.pos=body.pos+body.velocity/66
            if case=="review_critical_spring" then assert(body.pos.x<=target.pos.x+.0001,"hold response overshot its critically damped target") end
            assert(body.velocity:Length()<2000 and body.pos:Length()<61,"unstable spring at mass "..mass)
            if not settled and (body.pos-target.pos):Length()<.3 and body.velocity:Length()<1 then settled=i/66 end
        end
        assert(settled and (body.pos-target.pos):Length()<.01,"spring did not settle")
        print("spring kg="..mass.." settled_s="..settled)
    end
end
function cases.review_critical_spring() cases.review_spring_masses() end
function cases.review_melee_impulse()
    start() step()
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    for _,mass in ipairs({.5,1,10,250}) do
        local ent=entity("prop_physics",Vector(30,0,40),mass)
        A.Hit(ply,state,state.interact.right,ent,ent.pos,Vector(80,0,0),80)
        local delta=ent:GetPhysicsObject().impulse/mass
        assert(delta:Length()<=80,"unbounded melee delta-v mass="..mass)
        print("melee kg="..mass.." delta_units_s="..delta:Length())
    end
    stop()
end
function cases.review_melee_damage_force()
    start() step()
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local ent=entity("prop_physics",Vector(30,0,40),1)
    ent.TakeDamageInfo=function(self,info) self:GetPhysicsObject():ApplyForceCenter(info.force) end
    local original=Phys.ApplyForceOffset
    Phys.ApplyForceOffset=function(self,v) self.impulse=v self.velocity=self.velocity+v/self.mass end
    A.Hit(ply,state,state.interact.right,ent,ent.pos,Vector(80,0,0),80)
    assert(ent:GetPhysicsObject():GetVelocity():Length()<=80,"damage force reapplied an unbounded melee impulse")
    Phys.ApplyForceOffset=original stop()
end
function cases.review_safe_proxy()
    local world=entity("worldspawn")
    MASK_SOLID_BRUSHONLY=16
    forcedTrace=function(q)
        local blocked=q.endpos.x>15 and q.start.x<=15
        return {Hit=blocked,Entity=world,HitPos=blocked and Vector(14,q.endpos.y,q.endpos.z) or q.endpos,
            HitNormal=Vector(-1,0,0),Fraction=blocked and .5 or 1,StartSolid=false}
    end
    start()
    state.hands.right.pos=Vector(30,-8,40)
    for _,reason in ipairs({"start","respawn","tracking","teleport"}) do
        if state.interact.right.proxy then state.interact.right.proxy:Remove() end
        step()
        assert(state.interact.right.phys:GetPos().x<15,"proxy spawned past wall at "..reason)
    end
    forcedTrace=nil stop()
end
function cases.review_teleport_carry()
    start() step()
    local ent=entity("prop_physics",state.hands.right.pos+Vector(3,0,0),10)
    assert(ctx.core.Grab(ply,"right",ent,0))
    local initial=ent:GetPhysicsObject():GetPos()
    for _,mode in ipairs({1,2}) do
        local count=mode==1 and 1 or 20
        for i=1,count do
            local delta=Vector(200/count,0,0)
            ctx.Emit("teleport_delta",ply,delta)
            ply.pos=ply.pos+delta
            state.hands.right.buttons=1 step()
            assert(ctx.core.Holding(ply,"right")==ent,"teleport dropped held body")
        end
    end
    vec(ent:GetPhysicsObject():GetPos(),initial+Vector(400,0,0)) stop()
end
function cases.review_teleport_wall()
    start() step()
    local h=state.interact.right
    h.phys:SetPos(Vector(30,-8,40)) state.hands.right.pos=Vector(30,-8,40)
    local world=entity("worldspawn") local wall=215
    forcedTrace=function(q)
        local hit=q.start.x<wall and q.endpos.x>wall
        return {Hit=hit,HitPos=hit and Vector(wall-1,q.endpos.y,q.endpos.z) or q.endpos,
            HitNormal=Vector(-1,0,0),Entity=world,StartSolid=false}
    end
    ctx.Emit("teleport_delta",ply,Vector(200,0,0))
    assert(h.phys:GetPos().x<wall,"teleport placed hand through new thin wall")
    forcedTrace=nil stop()
end
function cases.review_glove_mesh()
    local triangles=0 local triangle=M.Triangle
    M.Triangle=function(...) triangles=triangles+1 return triangle(...) end
    local originalInclude=include
    include=function(path) if path=="nlvr/modules/sv_interact_math.lua" then return M end return originalInclude(path) end
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    include=originalInclude
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,function() end,function() end)
    A.physics=P
    local ent=entity("prop_physics",Vector(100,0,40),10)
    local mesh={}
    for i=1,2000 do mesh[#mesh+1]={pos=Vector(0,-2,-2)} mesh[#mesh+1]={pos=Vector(0,2,-2)} mesh[#mesh+1]={pos=Vector(0,0,2)} end
    ent.bones[1].mesh={mesh}
    forcedTrace=function(q) return {Hit=true,Entity=ent,HitPos=ent.pos,Fraction=.5} end
    local calls=0
    local mathModule=include
    -- Count triangle visits in the production helper loaded by the physics instance.
    local gets=0 local oldGet=ent.bones[1].GetPos
    ent.bones[1].GetPos=function(self) gets=gets+1 return oldGet(self) end
    local begin=os.clock()
    for i=1,200 do assert(A.Target(ply,pose(Vector(10,0,40)),40)) end
    print("glove2000 mean_ms="..((os.clock()-begin)*1000/200).." phys_position_reads="..gets)
    assert(triangles==2000,"stationary glove target repeated its mesh walk: "..triangles)
    ent.bones[1].mass=250
    assert(not A.Target(ply,pose(Vector(10,0,40)),40),"mass filter before mesh")
end
function cases.review_glove_two_hands()
    local triangles=0 local triangle=M.Triangle
    M.Triangle=function(...) triangles=triangles+1 return triangle(...) end
    local oldInclude=include
    include=function(path) if path=="nlvr/modules/sv_interact_math.lua" then return M end return oldInclude(path) end
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx) include=oldInclude
    local ent=entity("prop_physics",Vector(100,0,40),10)
    ent.bones[1].mesh={{{pos=Vector(0,-2,-2)},{pos=Vector(0,2,-2)},{pos=Vector(0,0,2)}}}
    for i=1,100 do
        P.GloveClosest(ent,Vector(10,0,40),40,"left")
        P.GloveClosest(ent,Vector(10,10,40),40,"right")
    end
    assert(triangles==2,"two hands thrash the glove cache: "..triangles)
end
function cases.math()
    vec(M.Segment(Vector(2,3,40),Vector(),Vector(0,0,80)),Vector(0,0,40))
    vec(M.Segment(Vector(0,0,100),Vector(),Vector(0,0,80)),Vector(0,0,80))
    vec(M.Triangle(Vector(0.25,0.25,3),Vector(),Vector(1,0,0),Vector(0,1,0)),Vector(0.25,0.25,0))
    vec(M.Triangle(Vector(3,0,0),Vector(),Vector(1,0,0),Vector(0,1,0)),Vector(1,0,0))
    local startPoint,finish,g=Vector(0,0,20),Vector(140,10,50),Vector(0,0,-600)
    for i=1,20 do local t=i/20 local velocity=M.Arc(startPoint,finish,t,g) vec(startPoint+velocity*t+g*t*t*0.5,finish) end
    assert(M.Flick(Vector(30,0,50),Vector(25,0,50),Vector(-60,0,0),Vector(0,0,50),40))
    assert(not M.Flick(Vector(30,0,50),Vector(35,0,50),Vector(60,0,0),Vector(0,0,50),40))
    assert(not M.Flick(Vector(30,0,50),Vector(29,0,50),Vector(-60,0,0),Vector(0,0,50),40))
    close(M.Damage(40,40,false),0) close(M.Damage(80,40,false),11) close(M.Damage(160,40,false),25) close(M.Damage(260,40,false),25)
    close(M.Damage(150,40),32) close(M.Damage(150,40,true),32) close(M.Damage(150,40,false),25)
    close(M.Damage(160,40,true),35) close(M.Damage(260,40,true),65) close(M.Damage(10000,40,true),65)
end
function cases.throw()
    local h={}
    for i=1,20 do h[i]={time=clock-(20-i)/66,pose=pose(Vector(),Vector(160,0,20),Vector(0,0,2))} end
    local velocity,spin=M.Throw(h,clock,40) vec(velocity,Vector(160,0,20)) vec(spin,Vector(0,0,2))
    vec(M.Throw(h,clock+2,40),Vector())
    h[#h+1]={time=clock,pose=pose(Vector(),Vector(1e8,0,0),Vector(1e8,0,0))}
    local v,s=M.Throw(h,clock,40) assert(v:Length()<=1000.0001 and s:Length()<=30.0001)
end
function cases.two_hand()
    local p,a=M.TwoHand(Vector(0,0,-20),Vector(0,0,20),Vector(10,20,30),Vector(10,60,30),Vector(0,0,1))
    vec(LocalToWorld(Vector(0,0,-20),Angle(),p,a),Vector(10,20,30))
    vec(LocalToWorld(Vector(0,0,20),Angle(),p,a),Vector(10,60,30))
    for i=1,100 do
        local a,b=Vector(-20,0,0),Vector(20,0,0)
        local p,angle=M.TwoHand(a,b,Vector(10,20,30),Vector(10,60,30),Vector(0,0,1))
        vec(LocalToWorld(a,Angle(),p,angle),Vector(10,20,30)) vec(LocalToWorld(b,Angle(),p,angle),Vector(10,60,30))
        local origin,rot=Vector(1,4,7),Angle(i*0.713, i*2, i/2)
        local lp,la=WorldToLocal(Vector(8,20,10),Angle(15,20,30),origin,rot)
        local got,ang=M.HeldTransform(lp,la,Vector(8,20,10),Angle(15,20,30)) vec(got,origin)
        assert((ang:Forward()-rot:Forward()):Length()<0.0001,"forward rotation "..i)
        assert((ang:Up()-rot:Up()):Length()<0.0001,"up rotation "..i.." got "..ang.p..","..ang.y..","..ang.r.." expected "..rot.p..","..rot.y..","..rot.r)
    end
end
function cases.nearest()
    start()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local long=entity("prop_physics",Vector(105,8,40)) long.ext=Vector(100,2,2)
    local distant=entity("prop_physics",Vector(20,8,40)) distant.ext=Vector(1,1,1)
    local near=P.Nearest(ply,Vector(4,8,40),6.4) assert(near.ent==long) close(near.distance,1)
    local rag=entity("prop_ragdoll",Vector(0,100,0)) rag.bones={phys(Vector(0,100,0)),phys(Vector(40,100,0))}
    rag.ext=Vector(50,2,2)
    -- Real local triangle hulls, with the entity origin far from the second bone.
    rag.bones[2].mesh={{{pos=Vector(0,-2,-2)},{pos=Vector(0,2,-2)},{pos=Vector(0,0,2)}}}
    local bone=P.Closest(rag,Vector(41,100,0)) assert(bone.bone==1) close(bone.distance,1)
    hook.Add("AllowPlayerPickup","peer",function() return false end) assert(not P.Nearest(ply,Vector(4,8,40),6.4))
    hook.Remove("AllowPlayerPickup","peer") long.CPPICanPickup=function() return false end assert(not P.Nearest(ply,Vector(4,8,40),6.4))
    stop()
end
function cases.lifecycle()
    start() step() assert(state.interact.left.proxy.hidden and state.interact.right.proxy.nodraw)
    local ent=entity("prop_physics",state.hands.left.pos+Vector(3,0,0))
    local owner={} ent.owner=owner
    assert(ctx.core.Grab(ply,"left",ent,0)) assert(ctx.core.Holding(ply,"left")==ent)
    assert(hook.Run("ShouldCollide",ent,ply)==false)
    events.OnDeath(ply,state) assert(not ctx.core.Holding(ply,"left")) assert(not state.interact.left.proxy)
    assert(ent:GetPhysicsObject().collisions and ent.owner==owner and not ent.callback)
    assert(ctx.Players[ply]==state) step() assert(state.interact.left.proxy)
    assert(ctx.core.Grab(ply,"left",ent,0))
    stop() assert(not ctx.core.Grab and not state.interact.left.proxy and not ent.callback and not ply.custom)
    assert(convars.ai_serverragdolls=="0")
end
function cases.body_trace()
    start() step()
    local h=state.interact.left
    assert(ctx.core.BodyTrace(ply,h.proxy)==false)
    assert(ctx.core.BodyTrace(ply,ply)==false)
    local other=entity("prop_physics",state.hands.left.pos+Vector(3,0,0))
    assert(ctx.core.BodyTrace(ply,other))
    assert(ctx.core.Grab(ply,"left",other,0))
    assert(ctx.core.BodyTrace(ply,other)==false)
    ctx.core.Release(ply,"left",false)
    assert(ctx.core.BodyTrace(ply,other)==false)
    clock=clock+1 step() assert(ctx.core.BodyTrace(ply,other))
    stop() assert(ctx.core.BodyTrace==nil)
end
function cases.api_throw()
    start() step()
    local ent=entity("prop_physics",state.hands.left.pos+Vector(2,0,0))
    local vel=Vector(120,0,30)
    state.history.left={{time=clock,pose=pose(Vector(),vel,Vector())}}
    assert(not ctx.core.Grab(ply,"wrong",ent,0)) assert(not ctx.core.Grab(ply,"left",ent,100))
    assert(not ctx.core.Grab(ply,"options",ent,0))
    assert(not ctx.core.Grab(ply,"left",ent,0,Vector(math.huge,0,0)))
    assert(ctx.core.Grab(ply,"left",ent,0)) assert(ctx.core.Release(ply,"left",true))
    vec(ent:GetPhysicsObject():GetVelocity(),vel) vec(state.interact.left.lastThrow,vel)
    assert(not ctx.core.Release(ply,"left",true))
    local p=ent:GetPhysicsObject()
    state.history.left={{time=clock,pose=pose(Vector(),vel,Vector(0,0,2))}}
    assert(ctx.core.Grab(ply,"left",ent,0))
    local grip=state.interact.left.grip
    local offset=LocalToWorld(grip.localPos,Angle(),p:GetPos(),p:GetAngles())-p:GetPos()
    assert(ctx.core.Release(ply,"left",true))
    vec(p:GetVelocity()+M.Cross(Vector(0,0,2),offset),vel)
    close(p:GetAngleVelocity().z,math.deg(2))
    local npc=entity("npc_citizen",state.hands.left.pos) assert(not ctx.core.Grab(ply,"left",npc,0))
    stop()
end
function cases.climb()
    local anchors={left=Vector(10,5,50),right=Vector(10,-5,50)}
    local delta,count=M.Climb(Vector(),Vector(),{left=pose(Vector(10,5,30)),right=pose(Vector(10,-5,30))},anchors,100)
    vec(delta,Vector(0,0,20)) assert(count==2)
    start() step()
    state.interact.left.climb=state.hands.left.pos+Vector(0,0,10)
    local mv=S.Move() mv.SetForwardSpeed=function() end mv.SetSideSpeed=function() end mv.SetUpSpeed=function() end
    assert(ctx.move(ply,mv)) vec(mv.origin,Vector()) -- no acquisition jump
    state.hands.left.pos=state.hands.left.pos-Vector(0,0,10)
    assert(ctx.move(ply,mv)) vec(mv.origin,Vector(0,0,10)) vec(mv.velocity,Vector(0,0,660))
    state.interact.left.climb=nil assert(ctx.move(ply,mv)) vec(mv.velocity,Vector(0,0,320)) assert(not ctx.move(ply,mv))
    stop()
end
function cases.climb_delayed_body()
    local anchors,refs={left=Vector(12,8,48)},{}
    local origin,head=Vector(),pose(Vector(0,0,64))
    local hand=pose(Vector(12,8,48)) local hands={left=hand}
    M.ClimbRelative(origin,head,hands,anchors,refs,12)
    for i=1,60 do
        -- Both network poses carry the same arbitrarily delayed motor translation.
        local delayed=math.max(0,i-7)*.2
        head.pos=Vector(0,0,64+delayed)
        hand.pos=Vector(12,8,48+delayed-i*.2)
        origin=origin+M.ClimbRelative(origin,head,hands,anchors,refs,12)
    end
    close(origin.z,12)
    for i=1,20 do origin=origin+M.ClimbRelative(origin,head,hands,anchors,refs,12) end
    close(origin.z,12)
end
function cases.actions()
    start() step()
    local h=state.interact.left
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local npc=entity("npc_citizen",state.hands.left.pos+Vector(1,0,0))
    A.Hit(ply,state,h,npc,npc.pos,Vector(80,0,0),80) close(npc.health,89) assert(npc.velocity:Length()>0)
    A.Hit(ply,state,h,npc,npc.pos,Vector(80,0,0),80) close(npc.health,89)
    clock=clock+1 A.Hit(ply,state,h,npc,npc.pos,Vector(260,0,0),260) close(npc.health,64)
    clock=clock+1 A.Hit(ply,state,h,npc,npc.pos,Vector(260,0,0),260,"held") close(npc.health,-1)
    local button=entity("gmod_button",state.hands.left.pos)
    assert(A.Use(ply,h,state.hands.left,40,true,false)) assert(button.used==1)
    clock=clock+1 hook.Add("PlayerUse","peer",function() return false end) A.Use(ply,h,state.hands.left,40,true,false) assert(button.used==1)
    stop()
end
function cases.two_hand_use()
    start() step()
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local button=entity("gmod_button",state.hands.left.pos)
    assert(A.Use(ply,state.interact.left,state.hands.left,40,true,false))
    assert(A.Use(ply,state.interact.right,state.hands.left,40,true,false))
    assert(button.used==1)
    clock=clock+.31
    assert(A.Use(ply,state.interact.right,state.hands.left,40,true,false)) assert(button.used==2)
    stop()
end
function cases.heavy()
    start() step()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local h=state.interact.left
    local a,b=phys(Vector(),10),phys(Vector(),250)
    local grip={phys=a,localPos=Vector(),localAng=Angle()}
    P.Drive(grip,nil,h,nil,state.hands.left,40,1/66)
    local lightAcceleration=(a.force*66+physenv.GetGravity()*a.mass)/a.mass
    grip.phys=b P.Drive(grip,nil,h,nil,state.hands.left,40,1/66)
    local heavyAcceleration=(b.force*66+physenv.GetGravity()*b.mass)/b.mass
    assert(lightAcceleration:Length()>heavyAcceleration:Length()*10)
    stop()
end
function cases.client()
    local client=include("nlvr/modules/cl_interact.lua")
    local held=entity("prop_physics")
    local c={Debug={},Hand={left={},right={}},Settings={gloves=1,climb=1,melee=1},Input={Owner=function() return nil end},Native={},Overlay={Sizes={gloves_left={273,275},gloves_right={277,279}},Objects={}}}
    if case=="verify_pending_marker" then
        c.Pose={head={valid=true,pos=Vector(0,0,64)}} c.ToTracking=function(p,a) return p,a end
        c.Overlay.New=function(options)
            local o={visible=false}
            function o:Show(v) self.wanted=v if not v then self.hides=(self.hides or 0)+1 end end function o:Place() end function o:Destroy() end
            c.Overlay.Objects[options.key]=o return o
        end
    end
    local receiver,resolver,mover,frame,sends,haptics,emitted=nil,nil,nil,nil,0,0,{}
    c.Net={On=function(_,fn) receiver=fn end,Send=function(_,writer) sends=sends+1 writer({WriteBool=function() end}) end}
    c.resolver=function(_,fn) resolver=fn end c.mover=function(_,fn) mover=fn end c.On=function(_,fn) frame=fn end
    c.Emit=function(name,hand,ent,bone)
        emitted[#emitted+1]=name
        if name=="grab" then assert(c.Hand[hand].held.ent==ent and c.Hand[hand].held.bone==bone) end
    end
    c.Native.Haptic=function() haptics=haptics+1 end
    client.Start(c) mover() assert(sends==0)
    local function receive(ent,sequence)
        local values={}
        for _,hand in ipairs({"left","right"}) do
            local function add(v) values[#values+1]=v end
            add(true) add(Vector(1,2,3)) add(Angle()) add(Vector(-1,0,0)) add(true) add(ent or false) add(2)
            add(false) add(Vector()) add(case=="verify_pending_marker" and held or false) add(Vector(30,0,40)) add(false) add(Vector(120,0,0)) add(Vector(0,0,2)) add(sequence) add(0.35) add(2)
        end
        local cursor=0 local function read() cursor=cursor+1 return values[cursor] end
        net={ReadBool=read,ReadVector=read,ReadAngle=read,ReadEntity=read,ReadUInt=read,ReadFloat=read}
        receiver()
    end
    local leftDebug,rightDebug=c.Debug.interact.left,c.Debug.interact.right
    if case=="verify_pending_marker" then
        receive(false,1) frame()
        assert(c.Overlay.Objects.gloves_right.wanted)
        c.Settings.gloves=0 frame()
        assert(not c.Overlay.Objects.gloves_right.wanted,"pending glove marker remained wanted")
        for i=1,5 do frame() end
        assert(c.Overlay.Objects.gloves_right.hides==1,"idle hidden glove issued repeated native hides")
        client.Stop() return
    end
    receive(held,1) assert(haptics==2 and #emitted==2)
    assert(c.Debug.interact.left==leftDebug and c.Debug.interact.right==rightDebug)
    assert(c.BodyTrace(ply,held)==false and c.BodyTrace(ply,ply)==false)
    assert(c.BodyTrace(ply,entity("prop_physics")))
    mover() assert(sends==1) mover() assert(sends==1)
    local s={shown={pos=Vector(2,2,3)},target={pos=Vector(2,2,3)}} resolver("right",s) vec(s.shown.pos,Vector(1,2,3)) assert(s.held.ent==held and s.blocked and s.grip_curls[2]>0.8)
    -- Between packets a walking hand follows the current pose with the obstruction offset.
    s.target.pos=Vector(12,2,3) s.shown.pos=s.target.pos resolver("right",s) vec(s.shown.pos,Vector(11,2,3))
    receive(held,1) assert(haptics==2 and #emitted==2)
    clock=clock+0.5 resolver("right",s) assert(not s.held and emitted[#emitted]=="release")
    receive(false,2) assert(haptics==4 and not c.Hand.right.held)
    receive(false,65535) receive(false,0) assert(haptics==8)
    receive(false,0) assert(haptics==8)
    client.Stop() client.Stop() assert(c.BodyTrace==nil)
end
function cases.verify_pending_marker() cases.client() end
function cases.gloves()
    start() step()
    local h=state.interact.right
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local ent=entity("prop_physics",state.hands.right.pos+Vector(120,0,0))
    local p=ent:GetPhysicsObject()
    h.pull={ent=ent,phys=p,bone=0,began=clock-0.5,ends=clock+0.1}
    A.Pull(ply,state,h,state.hands.right,true)
    assert(p:GetVelocity():Length()>0)
    h.pull={ent=ent,phys=p,bone=0,began=clock-0.5,ends=clock+0.1}
    A.Pull(ply,state,h,state.hands.right,false) assert(not h.pull and not h.grip)
    p.pos=state.hands.right.pos ent.pos=p.pos
    h.pull={ent=ent,phys=p,bone=0,began=clock-0.5,ends=clock+0.1}
    A.Pull(ply,state,h,state.hands.right,true) assert(h.grip and h.grip.ent==ent)
    stop()
end
function cases.climbing_hands()
    start() step()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local h=state.interact.right
    h.climb=h.phys:GetPos()
    local target=pose(h.phys:GetPos()+Vector(0,0,-20))
    forcedTrace=function(t) return {Hit=true,StartSolid=true,HitNormal=Vector(),HitPos=t.start,Fraction=0} end
    P.Follow(ply,h,target,40) assert(h.phys:GetVelocity().z<0 and not h.phys.collisions)
    h.climb=nil P.Follow(ply,h,target,40) vec(h.phys:GetVelocity(),Vector()) assert(h.phys.collisions)
    h.climb=target.pos
    forcedTrace=function(t) return {Hit=true,StartSolid=false,HitNormal=Vector(1,0,0),HitPos=t.start,Fraction=0} end
    P.Follow(ply,h,target,40) vec(h.phys:GetVelocity(),Vector())
    stop()
end
function cases.ladder()
    start() step()
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local ladder=entity("func_useableladder",Vector(10,-8,0))
    ladder.GetSaveTable=function() return {point1=Vector(),point0=Vector(0,0,80),StartDisabled=false} end
    ents.FindByClass=function() return {ladder} end
    vec(A.Surface(ply,state.hands.right,40),state.hands.right.pos)
    assert(not A.Surface(ply,pose(Vector(30,-8,40)),40))
    stop()
end
function cases.pull_pairs()
    start() step()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local ent=entity("prop_physics",Vector(100,0,40))
    P.BeginPull(ply,ent) assert(hook.Run("ShouldCollide",ent,ply)==false)
    P.EndPull(ent) assert(hook.Run("ShouldCollide",ent,ply)==nil)
    local prop=entity("prop_physics",Vector(11,0,40)) prop.ext=Vector(2,20,2)
    assert(ctx.core.Grab(ply,"left",prop,0)) assert(ctx.core.Grab(ply,"right",prop,0))
    assert(ctx.core.Release(ply,"left",true)) assert(ctx.core.Holding(ply,"right")==prop)
    assert(prop.callback and not state.interact.left.lastThrow)
    stop() assert(not prop.callback)
end
function cases.inventory()
    start() step()
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local item=entity("item_healthkit",state.hands.right.pos)
    local original=item:GetPos()
    local h=state.interact.right
    assert(A.Use(ply,h,state.hands.right,40,true,false)) vec(item:GetPos(),ply:WorldSpaceCenter())
    assert(not item.used) -- do not enter native +use's ordinary prop-carry path
    A.RestoreItems(ply) vec(item:GetPos(),original)
    clock=clock+0.5
    hook.Add("PlayerCanPickupItem","peer",function() return false end)
    A.Use(ply,h,state.hands.right,40,true,false) vec(item:GetPos(),original)
    hook.Remove("PlayerCanPickupItem","peer") clock=clock+0.5
    A.Use(ply,h,state.hands.right,40,true,false) clock=clock+0.2 A.UpdateItems() vec(item:GetPos(),original)
    stop()
end
function cases.native_prop_use()
    start() step()
    local prop=entity("prop_physics",state.hands.right.pos+Vector(3,0,0))
    assert(type(prop:GetTable().Use)=="function" and not rawget(prop:GetTable(),"Use"))
    scripted_ents={GetStored=function(class) return class=="base_anim" and {t={Use=function() end}} or nil end}
    state.hands.right.buttons=1 step()
    assert(ctx.core.Holding(ply,"right")==prop and not prop.used)
    stop()
end
function cases.held_contact()
    start() step()
    local prop=entity("prop_physics",state.hands.right.pos+Vector(3,0,0))
    local target=entity("prop_physics",state.hands.right.pos+Vector(40,0,0))
    assert(ctx.core.Grab(ply,"right",prop,0))
    prop.callback(prop,{HitEntity=target,HitPos=target.pos,Speed=120,OurOldVelocity=Vector(120,0,0)})
    state.hands.right.buttons=1 step()
    close(target.health,77) assert(state.interact.right.lastHit.source=="held")
    step() close(target.health,77)
    stop()
end
function cases.scale()
    start() step()
    local old=state.interact.right.proxy
    close(state.interact.right.radius,3)
    state.scale=80 step()
    assert(not IsValid(old)) close(state.interact.right.radius,6) close(state.interact.right.proxy.radius,6)
    stop()
end
function cases.moved_player()
    start() step()
    local prop=entity("prop_physics",state.hands.right.pos+Vector(3,0,0))
    state.hands.right.buttons=1 step()
    assert(ctx.core.Holding(ply,"right")==prop)
    local old=state.interact.right.proxy
    ply.pos=ply.pos+Vector(400,0,0)
    assert(not ctx.core.Grab(ply,"right",prop,0))
    state.hands.left.pos=state.hands.left.pos+Vector(400,0,0)
    state.hands.right.pos=state.hands.right.pos+Vector(400,0,0)
    step()
    assert(not IsValid(old) and not ctx.core.Holding(ply,"right") and not prop.callback)
    vec(state.interact.right.phys:GetPos(),state.hands.right.pos)
    assert(not state.interact.right.lastThrow)
    stop()
end
function cases.scripted_prop()
    start() step()
    local noop=function() end
    scripted_ents={GetStored=function(class)
        return (class=="base_anim" or class=="sent_crate") and {t={Use=noop}} or nil
    end}
    local prop=entity("sent_crate",state.hands.right.pos+Vector(3,0,0))
    state.hands.right.buttons=1 step()
    assert(ctx.core.Holding(ply,"right")==prop and not prop.used)
    stop()
end
function cases.scripted_item()
    start() step()
    local noop=function() end
    local custom=function() end
    scripted_ents={GetStored=function(class)
        if class=="base_anim" then return {t={Use=noop}} end
        if class=="item_customkit" then return {t={Use=custom}} end
    end}
    local item=entity("item_customkit",state.hands.right.pos)
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    A.Use(ply,state.interact.right,state.hands.right,40,true,false)
    assert(item.used==1) vec(item:GetPos(),state.hands.right.pos)
    stop()
end
function cases.impulse_units()
    start() step()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local h=state.interact.right
    h.phys.pos=Vector()
    for _,dt in ipairs({1/30,1/66,1/120}) do
        local p=phys(Vector(),10)
        local grip={phys=p,localPos=Vector(),localAng=Angle()}
        P.Drive(grip,nil,h,nil,pose(Vector()),40,dt)
        vec(p:GetVelocity()+physenv.GetGravity()*dt,Vector())
        close(p.force.z,10*600*dt)
    end
    stop()
end
function cases.held_grip_contact()
    start() step()
    state.hands.right.buttons=1 step()
    assert(not ctx.core.Holding(ply,"right"))
    local prop=entity("prop_physics",state.hands.right.pos+Vector(3,0,0))
    step() assert(ctx.core.Holding(ply,"right")==prop)
    stop()
end
function cases.finger_world_stop()
    start() step()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local h=state.interact.right
    forcedTrace=function(t)
        if t.maxs.x>7 then return {Hit=true,HitPos=Vector(10,0,64),HitNormal=Vector(-1,0,0),Fraction=0.5,StartSolid=false} end
        return {Hit=false,HitPos=t.endpos,HitNormal=Vector(),Fraction=1,StartSolid=false}
    end
    local target=P.WorldTarget(ply,h,pose(Vector(20,0,64)),40,pose(Vector(0,0,64)))
    vec(target,Vector(9.8,0,64))
    h.phys.pos=target
    P.Follow(ply,h,pose(Vector(12,0,64)),40,pose(Vector(0,0,64))) assert(h.blocked)
    h.climb=Vector(10,0,64)
    vec(P.WorldTarget(ply,h,pose(Vector(20,0,64)),40,pose(Vector(0,0,64))),Vector(20,0,64))
    stop()
end
function cases.usable_claim()
    start() step()
    local button=entity("gmod_button",state.hands.right.pos+Vector(3,0,0))
    state.hands.right.buttons=1 step()
    assert(button.used==1 and not ctx.core.Holding(ply,"right"))
    for _=1,25 do step() end
    assert(button.used==1 and not ctx.core.Holding(ply,"right"))
    state.hands.right.buttons=0 step()
    state.hands.right.buttons=1 step()
    assert(button.used==2 and not ctx.core.Holding(ply,"right"))
    stop()
end
function cases.contact_offset()
    start() step()
    local prop=entity("prop_physics",state.hands.right.pos+Vector(5,0,0),10)
    prop:GetPhysicsObject():EnableGravity(false)
    state.hands.right.buttons=1 step()
    local grip=state.interact.right.grip
    assert(grip and grip.handOffset:Length()>0)
    vec(grip.goal,prop:GetPhysicsObject():GetPos())
    stop()
end
function cases.release_grace()
    start() step()
    local prop=entity("prop_physics",state.hands.right.pos+Vector(5,0,0),4)
    state.hands.right.buttons=1 step()
    assert(ctx.core.Holding(ply,"right")==prop)
    state.history.right={{time=clock,pose=pose(Vector(),Vector(120,0,0),Vector(0,0,1))}}
    assert(ctx.core.Release(ply,"right",true))
    assert(hook.Run("ShouldCollide",prop,state.interact.right.proxy)==false and hook.Run("ShouldCollide",prop,ply)==false)
    local before=prop:GetPhysicsObject():GetVelocity()
    state.interact.right.contact={ent=prop,pos=prop.pos,velocity=Vector(120,0,0),speed=120}
    state.hands.right.buttons=0 step()
    assert(not state.interact.right.lastHit) vec(prop:GetPhysicsObject():GetVelocity(),before)
    clock=clock+0.25 step() assert(hook.Run("ShouldCollide",prop,ply)==nil)
    stop()
end
function cases.sweep_contact()
    start() step()
    local P=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    local h=state.interact.right
    local prop=entity("prop_physics",h.phys:GetPos()+Vector(3,0,0))
    forcedTrace=function(t) return {Hit=true,Entity=prop,HitPos=t.start,HitNormal=Vector(-1,0,0),Fraction=0,StartSolid=false} end
    P.Follow(ply,h,pose(h.phys:GetPos()+Vector(5,0,0),Vector(30,0,0)),40)
    assert(h.contact and h.contact.ent==prop) close(h.contact.speed,30)
    forcedTrace=nil step()
    assert(h.pulseKind==1 and h.strength>0)
    stop()
end
function cases.q4_passive_claims()
    for _,hand in ipairs({"left","right"}) do
        start() step()
        local button=entity("gmod_button",state.hands[hand].pos)
        state.interact.controls[hand]={grip=false,trigger=false}
        step() assert(not button.used,"passive Use escaped claimed controls: "..hand)
        state.interact.controls[hand]={grip=true,trigger=true}
        step() assert(not button.used,"claim ending activated a stale touch")
        button.pos=button.pos+Vector(100,0,0) step()
        button.pos=state.hands[hand].pos step() assert(button.used==1,"fresh contact did not regain Use")
        button.valid=false stop()
    end
end
function cases.q4_hand_ownership()
    start() step()
    local claim=assert(ctx.core.ClaimHand,"missing explicit hand ownership")
    local h=state.interact.right
    local button=entity("gmod_button",state.hands.right.pos)
    assert(claim(ply,"right","weapons",true))
    assert(not claim(ply,"right","peer",true))
    step() assert(not button.used)
    local target=entity("npc_citizen",Vector(10,0,40)) target.health=100
    local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,ctx.core.Grab,ctx.core.Release)
    A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    A.Hit(ply,state,h,target,target:GetPos(),Vector(160,0,0),160)
    assert(target.health==100,"claimed hand punched")
    assert(not claim(ply,"right","peer",false))
    assert(claim(ply,"right","weapons",false))
    step() assert(not button.used,"ownership ending activated a stale touch")
    state.hands.right.buttons=2 step() assert(button.used==1,"fresh trigger did not Use") stop()
end
function cases.q4_released_projectile()
    start() step()
    local ent=entity("npc_grenade_frag",state.hands.right.pos)
    local register=assert(ctx.core.RegisterReleased,"missing projectile registration")
    register(ply,ent,.2)
    assert(not ctx.core.Grab(ply,"right",ent),"released projectile was reacquired during grace")
    assert(ctx.core.BodyTrace(ply,ent)==false)
    assert(hook.Run("ShouldCollide",ent,ply)==false)
    local h=state.interact.right
    h.contact={ent=ent,pos=ent:GetPos(),velocity=Vector(160,0,0),speed=160}
    step() assert(not h.lastHit,"release was punched")
    clock=clock+.21 step() assert(ctx.core.BodyTrace(ply,ent)==true)
    stop() assert(not ctx.core.RegisterReleased and not ctx.core.ClaimHand)
end
function cases.q4r_release_rules()
    start() step()
    local e=entity("npc_grenade_frag",state.hands.right.pos)
    local playerRules,entityRules=ply.rules or 0,e.rules or 0
    ctx.core.RegisterReleased(ply,e,.2)
    assert(ply.rules==playerRules+1 and e.rules==entityRules+1,"registration did not invalidate both collision rules")
    playerRules,entityRules=ply.rules,e.rules
    clock=clock+.21 step()
    assert(ply.rules==playerRules+1 and e.rules==entityRules+1,"expiry did not invalidate both collision rules")
    playerRules,entityRules=ply.rules,e.rules step()
    assert(ply.rules==playerRules and e.rules==entityRules,"idle expiry repeated collision invalidation")
    stop()
end
function cases.q4r_each_use_mask()
    for _,name in ipairs({"left","right"}) do for _,control in ipairs({"grip","trigger"}) do
        start() step()
        local button=entity("gmod_button",state.hands[name].pos)
        state.interact.controls[name][control]=false step()
        assert(not button.used,name.." passive Use ignored only "..control.." claim")
        button.valid=false stop()
    end end
end
function cases.q4s_trigger_claim_item()
    for _,name in ipairs({"left","right"}) do
        start() step()
        local item=entity("item_healthkit",state.hands[name].pos)
        state.interact.controls[name].trigger=false
        state.hands[name].buttons=1 step()
        assert(ctx.core.Holding(ply,name)==item,"trigger-only claim blocked healthkit grab")
        assert(not item.used,"trigger-only claim fired healthkit Use")
        stop()
    end
end
function cases.q4r_owned_grab_and_drop()
    start() step()
    local prop=entity("prop_physics",state.hands.right.pos)
    assert(ctx.core.Grab(ply,"right",prop))
    assert(ctx.core.Holding(ply,"right")==prop)
    assert(ctx.core.ClaimHand(ply,"right","weapons",true))
    assert(not ctx.core.Holding(ply,"right"),"claim did not drop held prop")
    local other=entity("prop_physics",state.hands.right.pos)
    assert(not ctx.core.Grab(ply,"right",other),"owned hand acquired a prop")
    assert(ctx.core.ClaimHand(ply,"right","weapons",false))
    assert(ctx.core.Grab(ply,"right",other),"released owner prevented a new explicit grab")
    stop()
end
function cases.q4r_main_mask_off_damage()
    for _,main in ipairs({"left","right"}) do
        start() step() state.weapon={hand=main,class="nlvr_hands"}
        local A=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end)
        A.physics=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
        for _,name in ipairs({"left","right"}) do
            local target=entity("npc_citizen",state.hands[name].pos) target.health=100
            state.interact.controls[name].grip=false
            A.Hit(ply,state,state.interact[name],target,target:GetPos(),Vector(160,0,0),160)
            if name==main then assert(target.health==100,"claimed main grip punched")
            else assert(target.health<100,"off grip claim incorrectly suppressed off-hand damage") end
        end
        state.weapon=nil stop()
    end
end
function cases.q4r_held_press_across_claim()
    start() step()
    local button=entity("gmod_button",state.hands.right.pos)
    state.interact.controls.right.trigger=false
    state.hands.right.buttons=2 step()
    state.interact.controls.right.trigger=true step()
    assert(not button.used,"held trigger became a fresh press at claim end")
    state.hands.right.buttons=0 step() state.hands.right.buttons=2 step()
    assert(button.used==1,"a genuine fresh press did not use after the claim")
    stop()
end
function cases.q4r_projectile_feedback()
    start() step()
    for _,hand in ipairs({"left","right"}) do
        local h=state.interact[hand]
        assert(ctx.core.ClaimHand(ply,hand,"weapons",true))
        local before=h.pulse or 0
        assert(ctx.core.ProjectileFeedback(ply,hand))
        assert(h.pulse==before+1 and h.pulseKind==2,"grenade grab feedback missing")
        clock=clock+.09 step()
        assert(h.pulse==before+2 and h.pulseKind==3,"grenade release feedback missing")
    end
    ctx.core.ProjectileFeedback(ply,"right") events.OnDeath(ply)
    local after=state.interact.right.pulse clock=clock+.09 step()
    assert(state.interact.right.pulse==after,"dead player got delayed projectile feedback")
    stop() assert(not ctx.core.ProjectileFeedback)
end
function cases.q4r_dispatch_peer()
    local calls=0
    hook.Add("Tick","peer",function() calls=calls+1 return false end,HOOK_MONITOR_HIGH)
    start() step() assert(calls==1,"Tick bypassed the shared dispatcher")
    hook.Remove("Tick","peer") stop()
end
assert(cases[case],case)()
print("PASS "..case)
