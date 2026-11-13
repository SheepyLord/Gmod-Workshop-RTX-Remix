-- Server fixture, injected by the task P driver through ordinary admin console Lua.
local fixtures,phase,began,base,last={},-1,0,nil,0
local originalRagdolls=GetConVar("ai_serverragdolls"):GetString()
local diagnostics
local seenPulses,pulseCounts={},{}
local originalBase
local function out(kind,data) data=data or {} data.kind=kind data.phase=phase print("NLVR_P "..util.TableToJSON(data)) end
local function clear()
    if NLVR_SV then for _,h in ipairs({"left","right"}) do NLVR_SV.Release(Entity(1),h,false) end end
    for _,e in ipairs(fixtures) do if IsValid(e) then e:Remove() end end
    fixtures={}
end
local function spawn(class,model,pos,mass)
    local ent=ents.Create(class)
    if model then ent:SetModel(model) end
    ent:SetPos(pos) ent:Spawn() ent:Activate()
    fixtures[#fixtures+1]=ent
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableGravity(false) if mass then phys:SetMass(mass) end phys:Wake() end
    return ent
end
local function atHand(ent,pose,gap)
    local lo,hi=ent:OBBMins(),ent:OBBMaxs()
    local extent=math.max(math.abs(lo.x),math.abs(hi.x))
    ent:SetAngles(pose.ang)
    ent:SetPos(pose.pos-pose.ang:Up()*((lo.z+hi.z)*0.5)+pose.ang:Forward()*(extent+(gap or 2)))
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then phys:SetPos(ent:GetPos()) phys:SetAngles(ent:GetAngles()) end
end
local function ledge(ply,state,left,right)
    local center=originalBase or state.head.pos
    for z=-96,768,16 do
        for _,dir in ipairs({Vector(1,0,0),Vector(-1,0,0),Vector(0,1,0),Vector(0,-1,0)}) do
            local start=Vector(center.x,center.y,z)
            local tr=util.TraceLine({start=start,endpos=start+dir*1600,mask=MASK_SOLID_BRUSHONLY})
            if tr.HitWorld and math.abs(tr.HitNormal.z)<0.5 then
                local p=tr.HitPos+tr.HitNormal*5
                local upper=util.TraceLine({start=p+Vector(0,0,14),endpos=p+Vector(0,0,14)-tr.HitNormal*14,mask=MASK_SOLID_BRUSHONLY})
                if not upper.Hit and not upper.StartSolid then
                    local mins,maxs=ply:GetHull()
                    for _,hand in ipairs({left,right}) do
                        local feet=p-(hand.pos-ply:GetPos())
                        local clear=util.TraceHull({start=feet,endpos=feet,mins=mins,maxs=maxs,mask=MASK_PLAYERSOLID_BRUSHONLY,filter=ply})
                        if not clear.StartSolid then return p,tr.HitNormal,feet end
                    end
                end
            end
        end
    end
end
local function placeRagdoll(ent,left,right,single)
    local bodies={}
    for i=0,ent:GetPhysicsObjectCount()-1 do
        local p=ent:GetPhysicsObjectNum(i)
        bodies[#bodies+1]={phys=p,pos=p:GetPos(),ang=p:GetAngles(),bone=i,name=ent:GetBoneName(ent:TranslatePhysBoneToBone(i)) or ""}
        p:EnableGravity(false)
    end
    if single then
        -- Put the whole natural corpse ahead of the palm's supporting plane. A one-hand
        -- death-ragdoll test must not impose an unrelated off-hand contact constraint.
        local forward=right.ang:Forward()
        local nearest=diagnostics.Closest(ent,right.pos-forward*10000)
        if nearest then
            local delta=right.pos+forward*4.5-nearest.point
            for _,body in ipairs(bodies) do
                body.phys:SetPos(body.pos+delta) body.phys:SetAngles(body.ang)
                body.phys:SetVelocity(Vector()) body.phys:AddAngleVelocity(-body.phys:GetAngleVelocity())
            end
            local r=diagnostics.Closest(ent,right.pos)
            out("ragdoll-placement",{single=true,right=r and r.distance,right_bone=r and r.bone})
        end
        return
    end
    local a,b,best
    local span=(right.pos-left.pos):Length()
    for i=1,#bodies do for j=i+1,#bodies do
        local x,y=bodies[i],bodies[j]
        local d=(x.pos-y.pos):Length()
        local mirror=x.name:gsub("_L_","_R_")==y.name or y.name:gsub("_L_","_R_")==x.name
        local score=math.abs(d-span)+(mirror and 0 or 20)
        if d>1 and (not best or score<best) then a,b,best=x,y,score end
    end end
    if not a then return end
    local mathlib=include("nlvr/modules/sv_interact_math.lua")
    local origin,rotation=mathlib.TwoHand(a.pos,b.pos,left.pos,right.pos,Vector(0,0,1))
    local result
    for gap=0,20,0.5 do
        for _,body in ipairs(bodies) do
            local p,ang=LocalToWorld(body.pos,body.ang,origin+right.ang:Forward()*gap,rotation)
            body.phys:SetPos(p) body.phys:SetAngles(ang) body.phys:SetVelocity(Vector())
            body.phys:AddAngleVelocity(-body.phys:GetAngleVelocity())
        end
        local l=diagnostics.Closest(ent,left.pos) local r=diagnostics.Closest(ent,right.pos)
        result={left=l and l.distance,right=r and r.distance,left_bone=l and l.bone,right_bone=r and r.bone,gap=gap}
        if l and r and l.bone~=r.bone and l.distance>3.2 and r.distance>3.2 and l.distance<6.1 and r.distance<6.1 then break end
    end
    out("ragdoll-placement",result)
end
local function arena(ply,state)
    local original=ply:GetPos()
    for _,offset in ipairs({Vector(400,0,0),Vector(800,0,0),Vector(0,400,0),Vector(0,-400,0)}) do
        local xy=original+offset
        local ground=util.TraceLine({start=Vector(xy.x,xy.y,1024),endpos=Vector(xy.x,xy.y,-4096),mask=MASK_SOLID_BRUSHONLY})
        if ground.HitWorld and ground.HitNormal.z>0.7 then
            local feet=ground.HitPos+Vector(0,0,24)
            local clear=util.TraceHull({start=feet,endpos=feet,mins=Vector(-220,-100,0),maxs=Vector(100,100,150),
                mask=MASK_SOLID_BRUSHONLY,filter=function(ent) return ent:IsWorld() end})
            if not clear.StartSolid and not clear.Hit then
                out("arena",{feet=feet,ground=ground.HitPos,world_clear=true})
                return feet
            end
        end
    end
    out("arena",{feet=original,world_clear=false})
    return original
end
concommand.Add("nlvr_p_phase",function(ply,_,args)
    if not IsValid(ply) or not (game.SinglePlayer() or ply:IsListenServerHost()) or not NLVR_SV then return end
    local state=NLVR_SV.Players[ply]
    if not state or not state.hands.right.valid then return end
    -- W preserves the player's equipped weapon. V2/V3 explicitly exercises bare Hands.
    if ply:HasWeapon("nlvr_hands") then ply:SelectWeapon("nlvr_hands") end
    diagnostics=diagnostics or include("nlvr/modules/sv_interact_physics.lua").New(NLVR_SV,{hook=function() end})
    local nextPhase=tonumber(args[1])
    if not nextPhase then return end
    if nextPhase==phase then ply:SendLua("NLVR_P_ACK="..phase) return end
    clear() phase,began=nextPhase,CurTime()
    if not base then originalBase=ply:GetPos() base=arena(ply,state) end
    local oldFeet=ply:GetPos()
    if not ply:Alive() then ply:Spawn() end
    local hand={pos=base+state.hands.right.pos-oldFeet,ang=state.hands.right.ang}
    local left={pos=base+state.hands.left.pos-oldFeet,ang=state.hands.left.ang}
    ply:SetMoveType(MOVETYPE_NOCLIP) ply:SetGravity(1) ply:SetPos(base) ply:SetVelocity(-ply:GetVelocity())
    for _,h in ipairs({"left","right"}) do local proxy=state.interact[h].proxy if IsValid(proxy) then proxy:Remove() end end
    if phase==0 or phase==1 then
        local e=spawn("prop_physics",phase==0 and "models/props_c17/oildrum001.mdl" or "models/props_junk/PopCan01a.mdl",hand.pos,phase==0 and 15 or 4)
        atHand(e,hand,2) fixtures.main=e
    elseif phase==2 then
        local e=spawn("prop_physics","models/hunter/blocks/cube025x025x025.mdl",hand.pos,100)
        atHand(e,hand,5) e:GetPhysicsObject():EnableMotion(false) fixtures.main=e
    elseif phase==3 then
        local e=spawn("prop_physics","models/props_debris/wood_board04a.mdl",(hand.pos+left.pos)*0.5,12)
        local lo,hi=Vector(1e9,1e9,1e9),Vector(-1e9,-1e9,-1e9)
        for _,mesh in ipairs(e:GetPhysicsObject():GetMeshConvexes() or {}) do
            for _,vertex in ipairs(mesh) do
                local v=vertex.pos
                lo=Vector(math.min(lo.x,v.x),math.min(lo.y,v.y),math.min(lo.z,v.z))
                hi=Vector(math.max(hi.x,v.x),math.max(hi.y,v.y),math.max(hi.z,v.z))
            end
        end
        if lo.x>hi.x then lo,hi=e:OBBMins(),e:OBBMaxs() end
        local size,center=hi-lo,(lo+hi)*0.5
        local axis=size.z>size.x and size.z>size.y and Vector(0,0,1) or size.x>size.y and Vector(1,0,0) or Vector(0,1,0)
        local offset=hand.ang:Forward()*4.5
        local pos,ang=include("nlvr/modules/sv_interact_math.lua").TwoHand(center-axis*12,center+axis*12,left.pos+offset,hand.pos+offset,Vector(0,0,1))
        e:SetPos(pos) e:SetAngles(ang)
        e:GetPhysicsObject():SetPos(pos) e:GetPhysicsObject():SetAngles(ang)
        out("plank-bounds",{mins=lo,maxs=hi,axis=axis,pos=pos,ang=ang})
        fixtures.main=e
    elseif phase==4 then
        local e=spawn("prop_physics","models/props_junk/wood_crate001a.mdl",hand.pos,250)
        atHand(e,hand,1) fixtures.main=e
    elseif phase==5 then
        local e=spawn("prop_ragdoll","models/Humans/Group01/male_07.mdl",hand.pos)
        placeRagdoll(e,left,hand)
        fixtures.main=e
    elseif phase==6 then
        local point,normal,feet=ledge(ply,state,left,hand)
        if point then
            ply:SetPos(feet)
            for _,h in ipairs({"left","right"}) do local proxy=state.interact[h].proxy if IsValid(proxy) then proxy:Remove() end end
            out("ledge",{point=point,normal=normal,feet=ply:GetPos()})
        else out("ledge-missing") end
    elseif phase==7 then
        local e=spawn("gmod_button","models/maxofs2d/button_05.mdl",hand.pos)
        atHand(e,hand,0) e:SetIsToggle(true) e:GetPhysicsObject():EnableMotion(false) fixtures.main=e
        ply:SetHealth(50) ply:SetArmor(10) ply:SetAmmo(20,"Pistol")
    elseif phase==8 then
        local e=spawn("prop_physics","models/props_junk/watermelon01.mdl",hand.pos,2)
        atHand(e,hand,15) fixtures.main=e
    elseif phase==9 then
        local e=spawn("prop_physics","models/props_junk/PopCan01a.mdl",hand.pos+hand.ang:Forward()*140,4)
        e:SetPos(e:GetPos()-Vector(0,0,e:OBBCenter().z))
        e:GetPhysicsObject():SetPos(e:GetPos())
        local shelf=spawn("prop_physics","models/hunter/blocks/cube025x025x025.mdl",e:GetPos())
        shelf:SetPos(e:GetPos()+Vector(0,0,e:OBBMins().z-shelf:OBBMaxs().z-0.5))
        shelf:GetPhysicsObject():SetPos(shelf:GetPos()) shelf:GetPhysicsObject():EnableMotion(false)
        e:GetPhysicsObject():EnableGravity(true)
        fixtures.main=e
    elseif phase==10 then
        local e=spawn("npc_citizen","models/Humans/Group01/male_07.mdl",hand.pos+hand.ang:Forward()*30)
        -- Explicit server-ragdoll fixture; never change the player's Keep corpses setting.
        e:SetShouldServerRagdoll(true)
        e:SetHealth(100) e:SetNPCState(NPC_STATE_IDLE) fixtures.main=e
    elseif phase==11 then
        local e=spawn("prop_door_rotating","models/props_c17/door01_left.mdl",hand.pos)
        atHand(e,hand,0) fixtures.main=e
    elseif phase==12 then
        local e=ents.Create("func_useableladder")
        e:SetPos(hand.pos)
        e:SetKeyValue("point0",tostring(hand.pos+Vector(0,0,50)))
        e:SetKeyValue("point1",tostring(hand.pos-Vector(0,0,30)))
        e:Spawn() e:Activate() fixtures[#fixtures+1]=e
        fixtures.main=e
        local data=e:GetSaveTable()
        out("ladder",{top=data.point0,bottom=data.point1,disabled=data.StartDisabled})
    elseif phase==13 then
        local e=spawn("prop_physics","models/props_junk/wood_crate001a.mdl",hand.pos,4)
        atHand(e,hand,3.5) fixtures.main=e fixtures.bat=e
    end
    local ent=fixtures.main
    fixtures.initial=IsValid(ent) and ent:GetPos() or ply:GetPos()
    out("begin",{position=fixtures.initial,feet=ply:GetPos(),hand=hand.pos,entity=IsValid(ent) and ent:EntIndex() or 0})
    ply:SendLua("NLVR_P_ACK="..phase)
end)
hook.Add("CreateEntityRagdoll","nlvr_p_probe",function(npc,rag)
    if npc==fixtures.main then fixtures.deathrag=rag fixtures[#fixtures+1]=rag out("death-ragdoll",{entity=rag:EntIndex(),bones=rag:GetPhysicsObjectCount()}) end
end)
hook.Add("Tick","nlvr_p_probe",function()
    local ply=Entity(1)
    local state=NLVR_SV and NLVR_SV.Players[ply]
    if not state or phase<0 then return end
    local t=CurTime()-began
    local d=state.interact
    for _,hand in ipairs({"left","right"}) do
        local h=d[hand]
        if h.pulse and h.pulse~=seenPulses[hand] then
            seenPulses[hand]=h.pulse
            pulseCounts[h.pulseKind]=(pulseCounts[h.pulseKind] or 0)+1
        end
    end
    if (phase==6 or phase==12) and (d.right.climb or d.left.climb) and not fixtures.walkClimb then
        fixtures.walkClimb=true ply:SetMoveType(MOVETYPE_WALK)
    end
    if phase==7 and t>2.5 and not fixtures.kit then
        fixtures.kit=true if IsValid(fixtures.main) then fixtures.main:Remove() end
        local e=spawn("item_healthkit",nil,state.hands.right.pos)
        atHand(e,state.hands.right,0) fixtures.main=e
        ply:SetMoveType(MOVETYPE_WALK) ply:SetGravity(0)
        out("kit-before",{health=ply:Health(),armor=ply:Armor(),entity=e:EntIndex()})
    end
    if phase==7 and t>4 and not fixtures.battery then
        fixtures.battery=true if IsValid(fixtures.main) then fixtures.main:Remove() end
        local e=spawn("item_battery",nil,state.hands.right.pos) atHand(e,state.hands.right,0) fixtures.main=e
        out("battery-before",{health=ply:Health(),armor=ply:Armor(),entity=e:EntIndex()})
    end
    if phase==7 and t>5.1 and not fixtures.ammo then
        fixtures.ammo=true if IsValid(fixtures.main) then fixtures.main:Remove() end
        local e=spawn("item_ammo_pistol",nil,state.hands.right.pos) atHand(e,state.hands.right,0) fixtures.main=e
        out("ammo-before",{ammo=ply:GetAmmoCount("Pistol"),entity=e:EntIndex()})
    end
    if phase==10 and t>4.8 and not fixtures.killed and IsValid(fixtures.main) then
        fixtures.killed=true fixtures.main:TakeDamage(1000,ply,ply)
    end
    if phase==13 and t>3 and not fixtures.secondmelon then
        local e=spawn("prop_physics","models/props_junk/watermelon01.mdl",state.hands.right.pos+state.hands.right.ang:Forward()*60,2)
        fixtures.secondmelon=e fixtures.melonSpawned=true
    end
    if phase==10 and t>5.2 and IsValid(fixtures.deathrag) and not fixtures.positioned then
        fixtures.positioned=true
        placeRagdoll(fixtures.deathrag,state.hands.left,state.hands.right,true)
    end
    if phase==10 and t>6.7 and not fixtures.died then
        fixtures.died=true ply:Kill()
        out("player-death",{vr_active=NLVR_SV~=nil,held=d.right.grip~=nil,proxy=IsValid(d.right.proxy)})
    end
    if CurTime()-last<0.25 then return end last=CurTime()
    local e=fixtures.main
    local r,l=d.right,d.left
    local record={time=t,position=IsValid(e) and e:GetPos() or nil,initial=fixtures.initial,entity_alive=IsValid(e),feet=ply:GetPos(),
        left={proxy=IsValid(l.phys) and l.phys:GetPos() or nil,held=l.grip and l.grip.ent:EntIndex() or 0,bone=l.grip and l.grip.bone or nil,climb=l.climb},
        right={proxy=IsValid(r.phys) and r.phys:GetPos() or nil,hand=state.hands.right.pos,velocity=state.hands.right.vel,
        held=r.grip and r.grip.ent:EntIndex() or 0,bone=r.grip and r.grip.bone or nil,climb=r.climb,target=r.target and r.target.ent:EntIndex() or 0,
        pull=r.pull~=nil,throw=r.lastThrow,spin=r.lastSpin,hand_throw=r.lastHandVelocity,hit=r.lastHit,pulse=r.pulse,kind=r.pulseKind,
        grip_error=r.grip and r.grip.goal and (r.grip.goal-r.grip.phys:GetPos()):Length() or nil},
        health=ply:Health(),armor=ply:Armor(),ammo=ply:GetAmmoCount("Pistol"),player_velocity=ply:GetVelocity(),move_type=ply:GetMoveType(),
        haptic_counts=pulseCounts,
        npc_health=IsValid(e) and e:IsNPC() and e:Health() or nil,
        door=IsValid(e) and e:GetClass()=="prop_door_rotating" and e:GetInternalVariable("m_eDoorState") or nil,
        button=IsValid(e) and e:GetClass()=="gmod_button" and e:GetOn() or nil,ragdoll=IsValid(fixtures.deathrag) and fixtures.deathrag:EntIndex() or nil}
    if IsValid(e) and diagnostics then
        local nearest=diagnostics.Closest(e,IsValid(r.phys) and r.phys:GetPos() or state.hands.right.pos)
        record.nearest=nearest and nearest.distance
        record.use_type=type(e:GetTable().Use) record.raw_use_type=type(rawget(e:GetTable(),"Use"))
        record.pickup_allowed=diagnostics.Allowed(ply,e) record.buttons=state.hands.right.buttons
        record.physics_bodies=e:GetPhysicsObjectCount()
        record.phys_pos=IsValid(e:GetPhysicsObject()) and e:GetPhysicsObject():GetPos() or nil
        record.phys_velocity=IsValid(e:GetPhysicsObject()) and e:GetPhysicsObject():GetVelocity() or nil
        record.phys_spin=IsValid(e:GetPhysicsObject()) and e:GetPhysicsObject():GetAngleVelocity() or nil
        record.hull_point=nearest and nearest.point
        local tr=util.TraceLine({start=state.hands.right.pos,endpos=e:GetPos(),mask=MASK_SOLID,filter=function(candidate) return candidate==e end})
        record.hull_trace=tr.Hit and tr.HitPos or nil record.hull_inside=tr.StartSolid
    end
    if fixtures.melonSpawned then record.held_melon_alive=IsValid(fixtures.secondmelon) end
    if IsValid(fixtures.bat) then
        local near=diagnostics.Closest(fixtures.bat,IsValid(r.phys) and r.phys:GetPos() or state.hands.right.pos)
        record.bat={pos=fixtures.bat:GetPos(),nearest=near and near.distance,buttons=state.hands.right.buttons,
            allowed=diagnostics.Allowed(ply,fixtures.bat),grip=r.wasGrip,mass=fixtures.bat:GetPhysicsObject():GetMass()}
    end
    if r.grip and l.grip and r.grip.phys==l.grip.phys then
        local a,b=r.grip.localPos,l.grip.localPos
        local p=r.grip.phys
        local wa=LocalToWorld(a,Angle(),p:GetPos(),p:GetAngles()) local wb=LocalToWorld(b,Angle(),p:GetPos(),p:GetAngles())
        record.alignment=(wb-wa):GetNormalized():Dot((l.phys:GetPos()-r.phys:GetPos()):GetNormalized())
    end
    out("sample",record)
end)
concommand.Add("nlvr_p_done",function()
    out("cleanup",{active=NLVR_SV~=nil,ragdolls=GetConVar("ai_serverragdolls"):GetString(),saved_ragdolls=originalRagdolls,
        custom=IsValid(Entity(1)) and Entity(1):GetCustomCollisionCheck()})
    clear() hook.Remove("Tick","nlvr_p_probe") hook.Remove("CreateEntityRagdoll","nlvr_p_probe")
    concommand.Remove("nlvr_p_phase") concommand.Remove("nlvr_p_done")
end)
