-- Private authoritative integration witnesses, never shipped.
local qPhase,qAt,qFixture,qBodies,qOriginalRagdolls="",0,{},nil,GetConVar("ai_serverragdolls"):GetString()
local qP,qA,qSamples,qThrown,qWall,qCarried,qWallPoint
local qSpawnPending,qSpawned,qRespawned
local qWallCase,qWallOrigin,qWallParked,qWallJumped,qWallReady,qWallChecks,qBehind,qSavedMove
local qBench
local function qPlace(ent,pos)
    ent:SetPos(pos) local body=ent:GetPhysicsObject()
    if IsValid(body) then body:SetPos(pos) body:SetVelocity(Vector()) body:Wake() end
end
local function qOut(name,data) data=data or {} data.kind="review-"..name print("NLVR_P "..util.TableToJSON(data)) end
local function qClear(ply)
    if NLVR_SV then for _,hand in ipairs({"left","right"}) do NLVR_SV.Release(ply,hand,false) end end
    for _,e in ipairs(qFixture) do if IsValid(e) then e:Remove() end end qFixture={}
end
local function qSpawn(model,pos,mass)
    local e=ents.Create("prop_physics") e:SetModel(model) e:SetPos(pos) e:Spawn()
    e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    local p=e:GetPhysicsObject() p:EnableGravity(false) if mass then p:SetMass(mass) end
    qFixture[#qFixture+1]=e return e,p
end
concommand.Add("nlvr_review_stage",function(ply,_,args)
    if not IsValid(ply) then ply=Entity(1) end
    local sv=NLVR_SV local s=sv and sv.Players[ply] if not s then return end
    if ply:HasWeapon("nlvr_hands") then ply:SelectWeapon("nlvr_hands") end
    qPhase,qAt=args[1],CurTime() qSamples={} qThrown=nil qSpawnPending,qSpawned,qRespawned=nil,nil,nil
    qClear(ply)
    if not qP then
        local ctx={core=sv,Players=sv.Players,hook=function() end,Reach=sv.Reach,Emit=sv.Emit}
        qP=include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
        qA=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function() end,sv.Grab,sv.Release) qA.physics=qP
        for _,entry in ipairs(sv.Registry.entries) do if entry.module.name=="core" then
            entry.ctx.On("teleport_delta",function(p,delta)
                if qPhase~="blink" and qPhase~="shift" then return end
                local state=sv.Players[p] local grip=state and state.interact.right.grip
                qOut("carry-step",{phase=qPhase,time=CurTime()-qAt,delta=delta,speed=delta:Length()/engine.TickInterval(),
                    held=grip and grip.ent:EntIndex() or 0,carried=IsValid(qCarried) and qCarried:EntIndex() or 0})
            end)
            entry.ctx.On("release",function(_,hand,e)
                if (qPhase=="blink" or qPhase=="shift") and hand=="right" and e==qCarried then
                    qOut("carry-release",{phase=qPhase,time=CurTime()-qAt})
                end
            end)
        end end
    end
    if qPhase=="walk" then
        ply:ConCommand("nlvr_L_stage reset") ply:SetMoveType(MOVETYPE_WALK) ply:SetGravity(0)
    elseif qPhase=="carry-wall" or qPhase=="carry-constraint" then
        local h=s.interact.right
        if not IsValid(h.phys) then qOut("negative-carry",{name=qPhase,setup=false}) return end
        local e,body=qSpawn("models/props_junk/wood_crate001a.mdl",h.phys:GetPos(),10)
        qPlace(e,h.phys:GetPos()+Vector(-e:OBBMins().x+.5,0,0))
        local setup=sv.Grab(ply,"right",e,0)
        local before=body:GetPos() local delta=Vector(160,0,0)
        local precondition=false
        if qPhase=="carry-constraint" then
            local anchor,anchorBody=qSpawn("models/props_junk/PopCan01a.mdl",before+Vector(0,80,0),20)
            anchorBody:EnableMotion(false)
            local weld=constraint.Weld(e,anchor,0,0,0,true,false)
            if IsValid(weld) then qFixture[#qFixture+1]=weld end
            precondition=constraint.HasConstraints(e)
        else
            local wall=qSpawn("models/hunter/plates/plate2x2.mdl",ply:GetPos()+delta+Vector(24,-8,48),100)
            wall:SetAngles(Angle(90,0,0)) wall:PhysicsInitBox(Vector(-64,-64,-.5),Vector(64,64,.5))
            wall:SetCollisionBounds(Vector(-64,-64,-.5),Vector(64,64,.5)) wall:SetCollisionGroup(COLLISION_GROUP_NONE)
            wall:GetPhysicsObject():EnableMotion(false)
            local low,high=e:WorldSpaceAABB()
            local hit=util.TraceHull{start=e:GetPos(),endpos=e:GetPos()+delta,mins=low-e:GetPos(),maxs=high-e:GetPos(),
                mask=MASK_SOLID,filter=function(ent) return ent==wall end}
            precondition=hit.Hit
        end
        sv.Emit("teleport_delta",ply,delta) ply:SetPos(ply:GetPos()+delta)
        qOut("negative-carry",{name=qPhase,setup=setup,precondition=precondition,
            released=sv.Holding(ply,"right")==nil,body_displacement=(body:GetPos()-before):Length(),
            scope="Native body and real public Grab/Transport/Release; synthetic displacement, positive blink/shift tested separately"})
    elseif qPhase=="hold" or qPhase=="blink" or qPhase=="shift" then
        ply:SetMoveType(MOVETYPE_WALK) ply:SetGravity(0)
        ply:ConCommand("nlvr_L_stage reset")
        qSpawnPending=true
        ply:SendLua('RunConsoleCommand("nl_vr_teleport","'..(qPhase=="shift" and '2' or '1')..'")')
    elseif qPhase=="masses" then
        ply:SetMoveType(MOVETYPE_NOCLIP)
        qBodies={}
        for i,mass in ipairs({.5,1,10,250}) do
            local position=ply:GetPos()+Vector(50,100+i*25,64)
            local e,p=qSpawn("models/props_junk/PopCan01a.mdl",position,mass)
            qBodies[#qBodies+1]={ent=e,phys=p,mass=p:GetMass(),requested=mass,goal=position+Vector(20,0,0),peak=0}
        end
        local rag=ents.Create("prop_ragdoll") rag:SetModel("models/Humans/Group01/male_07.mdl")
        rag:SetPos(ply:GetPos()+Vector(100,300,64)) rag:Spawn() qFixture[#qFixture+1]=rag
        local light,bone
        for i=0,rag:GetPhysicsObjectCount()-1 do
            local body=rag:GetPhysicsObjectNum(i)
            if IsValid(body) then
                body:EnableGravity(false)
                if not light or body:GetMass()<light:GetMass() then light,bone=body,i end
            end
        end
        if light then qBodies[#qBodies+1]={ent=rag,phys=light,mass=light:GetMass(),bone=bone,
            goal=light:GetPos()+Vector(1,0,0),ang=light:GetAngles(),peak=0} end
    elseif qPhase=="melee" then
        for i,mass in ipairs({1,250}) do
            local e,p=qSpawn("models/props_c17/oildrum001.mdl",ply:GetPos()+Vector(70,100+i*60,64),mass)
            qA.Hit(ply,s,s.interact.right,e,p:GetPos(),Vector(80,0,0),80)
            qSamples[#qSamples+1]={phys=p,mass=p:GetMass()}
        end
        -- Isolate the reviewed Lua mesh-query cost using a native body with a controlled
        -- 2,000-triangle mesh input. No shipped model or global setting is changed.
        local ent,body=qSpawn("models/props_junk/PopCan01a.mdl",ply:GetPos()+Vector(100,-200,64),10)
        local mesh={} for i=1,2000 do
            mesh[#mesh+1]={pos=Vector(i/2000,-2,-2)} mesh[#mesh+1]={pos=Vector(i/2000,2,-2)} mesh[#mesh+1]={pos=Vector(i/2000,0,2)}
        end
        local function action(bypass)
            local p=include("nlvr/modules/sv_interact_physics.lua").New({},{hook=function() end})
            if bypass then p.GloveClosest=function(e,point) return p.Closest(e,point) end end
            local a=include("nlvr/modules/sv_interact_actions.lua").New({},function() end,function() end,function() end)
            a.physics=p return a
        end
        qBench={ent=ent,body=body,mesh=mesh,before=action(true),after=action(false),calls=0,before_ms=0,after_ms=0}
    elseif qPhase=="wall" then
        -- A native 1-unit-thick collision box covers the entire sweep. A hull-blocking
        -- BSP coordinate alone did not prove this controller-height path was blocked.
        ply:SetMoveType(MOVETYPE_NOCLIP) ply:SetVelocity(-ply:GetVelocity())
        qWallCase,qWallChecks,qWallParked,qWallJumped,qWallReady="start",{},nil,nil,nil
        qWallOrigin=ply:EyePos()+Vector(20,-8,-16) qWallPoint=qWallOrigin
        qWall=ents.Create("base_anim") qWall:SetModel("models/hunter/plates/plate2x2.mdl")
        qWall:SetPos(qWallOrigin) qWall:SetAngles(Angle(90,0,0)) qWall:Spawn()
        qWall:PhysicsInitBox(Vector(-64,-64,-.5),Vector(64,64,.5))
        qWall:SetCollisionBounds(Vector(-64,-64,-.5),Vector(64,64,.5)) qWall:SetSolid(SOLID_VPHYSICS)
        qWall:SetCollisionGroup(COLLISION_GROUP_NONE) qWall:GetPhysicsObject():EnableMotion(false)
        qFixture[#qFixture+1]=qWall
        qBehind=qSpawn("models/props_junk/PopCan01a.mdl",qWallOrigin+Vector(3,0,0),1)
    elseif qPhase=="stale" then
        qSavedMove=s.move
        for _,entry in ipairs(sv.Registry.entries) do if entry.module.name=="move" then sv.Registry:StopEntry(entry) end end
        ply:SetMoveType(MOVETYPE_WALK) ply:SetGravity(0)
    elseif qPhase=="done" then
        -- Restore the deliberately stopped module and its cumulative room baseline
        -- before the final paired CPU control, without replaying discarded room input.
        for _,entry in ipairs(sv.Registry.entries) do if entry.module.name=="move" then
            entry.active,entry.stopped=true,false
            sv.Registry:Call(entry,entry.module.Start,entry.ctx)
            s.move=qSavedMove
        end end
        local modules=true for _,entry in ipairs(sv.Registry.entries) do modules=modules and entry.active and not entry.stopped end
        qOut("move-restored",{modules_live=modules,proxies=IsValid(s.interact.left.phys) and IsValid(s.interact.right.phys),sync_age=CurTime()-(s.lastSync or 0)})
        qOut("corpse-setting",{before=qOriginalRagdolls,after=GetConVar("ai_serverragdolls"):GetString()})
        hook.Remove("Tick","nlvr_combined_review")
    end
    qOut("stage",{name=qPhase,feet=ply:GetPos(),previous_teleport=s.move and s.move.last and s.move.last.id})
end)
local qLast=0
concommand.Add("nlvr_review_health",function(ply,_,args)
    if not IsValid(ply) then ply=Entity(1) end
    local sv=NLVR_SV local state=sv and sv.Players[ply] if not state then return end
    local active=true for _,entry in ipairs(sv.Registry.entries) do active=active and entry.active and not entry.stopped end
    qOut("cpu-health",{label=args[1],modules_live=active,proxies=IsValid(state.interact.left.phys) and IsValid(state.interact.right.phys),
        sync_age=CurTime()-(state.lastSync or 0)})
end)
hook.Add("Tick","nlvr_combined_review",function()
    local ply=Entity(1) local s=NLVR_SV and NLVR_SV.Players[ply]
    if not s or qPhase=="" or qPhase=="done" then return end
    local elapsed=CurTime()-qAt
    if qPhase=="melee" and qBench and elapsed<=1.5 then
        local b=qBench local target=b.body:GetPos()
        local point=target+Vector(-80,-150+200*elapsed,0)
        local poses={left={pos=point,ang=(target-point):Angle()},right={pos=point+Vector(0,10,0),ang=(target-point-Vector(0,10,0)):Angle()}}
        local meta=FindMetaTable("PhysObj") local getMesh,trace=meta.GetMeshConvexes,util.TraceHull
        meta.GetMeshConvexes=function(self,...) if self==b.body then return {b.mesh} end return getMesh(self,...) end
        util.TraceHull=function(t)
            if t.start==poses.left.pos or t.start==poses.right.pos then return {Hit=true,Entity=b.ent,HitPos=target,Fraction=.33} end
            return trace(t)
        end
        local ok,err=pcall(function()
            for _,kind in ipairs({"before","after"}) do
                local began=SysTime()
                for _,hand in ipairs({"left","right"}) do assert(b[kind].Target(ply,poses[hand],40,hand),"walking target refused") end
                b[kind.."_ms"]=b[kind.."_ms"]+(SysTime()-began)*1000
            end
        end)
        meta.GetMeshConvexes,util.TraceHull=getMesh,trace
        if not ok then error(err) end
        b.calls=b.calls+1
    elseif qPhase=="melee" and qBench and not qBench.reported and elapsed>1.5 then
        qBench.reported=true
        qOut("mesh-cost",{triangles=2000,hands=2,iterations=qBench.calls,walking_speed=200,
            before_ms=qBench.before_ms/qBench.calls,after_ms=qBench.after_ms/qBench.calls,
            scope="Full two-hand A.Target on real server ticks, moving queries at 200 u/s, controlled native-body mesh/hit; no fake CurTime"})
    end
    if qPhase=="wall" then
        if not qWallReady and s.hands.right.pos.x>qWallOrigin.x+4 then
            qWallReady=true
            if IsValid(s.interact.right.proxy) then s.interact.right.proxy:Remove() end
        end
        if elapsed>.65 and elapsed<.9 then qWallCase="tracking" end
        if elapsed>1.75 and not qWallParked then
            qWallParked=true qWallCase="clearance"
            qPlace(qWall,qWallOrigin+Vector(0,200,0)) qPlace(qBehind,qWallOrigin+Vector(3,200,0))
        end
        if elapsed>2.05 and not qWallJumped then
            qWallJumped=true qWallCase="teleport"
            local delta=Vector(160,0,0)
            local before=IsValid(s.interact.right.phys) and s.interact.right.phys:GetPos().x or -math.huge
            qWallPoint=qWallOrigin+delta
            qPlace(qWall,qWallPoint) qPlace(qBehind,qWallPoint+Vector(3,0,0))
            NLVR_SV.Emit("teleport_delta",ply,delta) ply:SetPos(ply:GetPos()+delta)
            qOut("wall-discontinuity",{before_far=before>qWallOrigin.x+3,
                scope="Synthetic server teleport_delta and matching player displacement; real blink/shift wiring tested separately"})
        end
        local h=s.interact.right
        if qWallCase~="clearance" and qWallReady and s.hands.right.valid and IsValid(h.phys) and not qWallChecks[qWallCase] then
            local trace=util.TraceHull{start=ply:EyePos(),endpos=ply:EyePos()+Vector(40,-8,-16),
                mins=Vector(-3,-3,-3),maxs=Vector(3,3,3),mask=MASK_SOLID,filter=function(e) return e==qWall end}
            qPlace(qBehind,Vector(qWallPoint.x+3,h.phys:GetPos().y,h.phys:GetPos().z))
            local near=qP.Closest(qBehind,h.phys:GetPos())
            local eligible=qP.Allowed(ply,qBehind) and near and near.distance<=s.scale*.16
            if eligible and trace.Hit and trace.Entity==qWall then
                qWallChecks[qWallCase]=true
                local grabbed=NLVR_SV.Grab(ply,"right",qBehind,0)
                if grabbed then NLVR_SV.Release(ply,"right",false) end
                qOut("wall-guard",{case=qWallCase,geometry_hit=true,
                    eligible_without_wall=true,denied=not grabbed,proxy=h.phys:GetPos(),plane=qWallPoint})
            end
        end
    end
    if qSpawnPending and elapsed>.35 and IsValid(s.interact.right.phys) and
        s.interact.controls.right.grip and bit.band(s.hands.right.buttons,1)~=0 and (s.interact.right.phys:GetPos()-s.hands.right.pos):Length()<1 then
        qSpawnPending=nil
        qCarried=qSpawn("models/props_junk/PopCan01a.mdl",s.interact.right.phys:GetPos()+Vector(1,0,0),10)
        local setup=NLVR_SV.Grab(ply,"right",qCarried,0)
        qOut("carry-setup",{phase=qPhase,setup=setup,control=s.interact.controls.right.grip,
            entity=qCarried:EntIndex(),time=elapsed})
    end
    if qPhase=="wall" and elapsed>.9 and not qRespawned then
        qRespawned=true qWallCase="respawn" local origin=ply:GetPos()
        ply:KillSilent() ply:Spawn() ply:SetPos(origin) ply:SetMoveType(MOVETYPE_NOCLIP)
        ply:SelectWeapon("nlvr_hands")
        qOut("wall-respawn",{feet=origin})
    end
    if qPhase=="masses" then
        for _,r in ipairs(qBodies) do
            if IsValid(r.phys) then
                qP.Drive({phys=r.phys,localPos=Vector(),localAng=Angle()},nil,
                    {phys={GetPos=function() return r.goal end}},nil,{pos=r.goal,ang=r.ang or Angle(),vel=Vector()},s.scale,engine.TickInterval())
                local speed=r.phys:GetVelocity():Length() r.peak=math.max(r.peak,speed)
                r.error=(r.phys:GetPos()-r.goal):Length()
                if not r.settled and r.error<.5 and speed<1 then r.settled=elapsed end
            end
        end
    end
    if CurTime()-qLast<.05 then return end qLast=CurTime()
    local h=s.interact.right local grip=h.grip
    local record={phase=qPhase,time=elapsed,feet=ply:GetPos(),player_velocity=ply:GetVelocity(),held=grip and grip.ent:EntIndex() or 0,
        target=s.hands.right.pos,proxy=IsValid(h.phys) and h.phys:GetPos(),blocked=h.blocked,
        hold_error=grip and grip.goal and (grip.phys:GetPos()-grip.goal):Length(),hand_velocity=s.hands.right.vel,
        hand_world_velocity=s.hands.right.wvel,
        buttons=s.hands.right.buttons,control=s.interact.controls.right.grip,weapon=IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass(),
        carried=IsValid(qCarried) and qCarried:EntIndex(),
        throw=h.lastHandVelocity,prop_velocity=IsValid(qCarried) and qCarried:GetPhysicsObject():GetVelocity(),
        teleport=s.move and s.move.last}
    record.tracked=s.hands.right.valid
    record.sync_age=CurTime()-(s.lastSync or 0)
    if qPhase=="masses" then
        record.bodies={} for _,r in ipairs(qBodies) do record.bodies[#record.bodies+1]={mass=r.mass,requested=r.requested,bone=r.bone,peak=r.peak,error=r.error,settled=r.settled} end
    elseif qPhase=="melee" then
        record.bodies={} for _,r in ipairs(qSamples) do record.bodies[#record.bodies+1]={mass=r.mass,speed=IsValid(r.phys) and r.phys:GetVelocity():Length()} end
    elseif qPhase=="wall" then record.wall=qWallCase~="clearance" and qWallPoint or nil record.wall_case=qWallCase end
    qOut("sample",record)
end)
