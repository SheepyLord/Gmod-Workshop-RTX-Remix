-- Server test fixture loaded by ordinary admin console Lua in W's locked PoC session.
local phase,fixtures,base,previous,last,samples,goal,exactShot=nil,{},nil,nil,0,{},nil,nil
local contacts={}
local phaseId=0
local savedMoveType
local births={}
local function out(kind,data)
    local copy={} for k,v in pairs(data or {}) do copy[k]=v end
    copy.kind=kind copy.phase=phase copy.time=CurTime() copy.tick=engine.TickCount() copy.phase_id=phaseId print("NLVR_W "..util.TableToJSON(copy))
end
local previousEffect=util.Effect
local function effect(name,data,...)
    local _,recipients=...
    if phase and NLVR_SV and (name=="Impact" or name=="StunstickImpact" or name=="Tracer" or name=="AR2Tracer") then
        out("server-effect",{name=name,start=data:GetStart(),origin=data:GetOrigin(),surface=data:GetSurfaceProp(),
            hitbox=data:GetHitBox(),damage_type=data:GetDamageType(),entity=IsValid(data:GetEntity()) and data:GetEntity():EntIndex() or -1,broadcast=recipients==true})
    end
    return previousEffect(name,data,...)
end
util.Effect=effect
local launchClasses={crossbow_bolt=true,rpg_missile=true,grenade_ar2=true,prop_combine_ball=true,npc_grenade_frag=true,npc_grenade_bugbait=true}
local function order(event)
    for ent,r in pairs(births) do
        if not IsValid(ent) or engine.TickCount()-r.tick>2 then births[ent]=nil
        else
            local phys=ent:GetPhysicsObject()
            local velocity=IsValid(phys) and phys:GetVelocity() or ent:GetVelocity()
            local owner=ent:GetOwner() local key=event..tostring(IsValid(owner))..tostring(velocity:Length()>1)
            if not r[key] then
                r[key]=true out("projectile-order",{event=event,class=ent:GetClass(),ticks=engine.TickCount()-r.tick,
                    owner=IsValid(owner),velocity=velocity,pos=ent:GetPos(),motion=IsValid(phys) and phys:IsMotionEnabled()})
            end
        end
    end
end
hook.Add("OnEntityCreated","nlvr_w_order",function(ent)
    if not launchClasses[ent:GetClass()] then return end
    births[ent]={tick=engine.TickCount()} order("created")
    timer.Simple(0,function() order("timer0") end)
end)
for _,event in ipairs({"Think","Tick","PlayerPostThink","PlayerTick","FinishMove","EntityEmitSound","DoAnimationEvent"}) do
    hook.Add(event,"nlvr_w_order",function() order(event) end)
end
local function clear()
    for _,e in ipairs(fixtures) do if IsValid(e) then e:Remove() end end fixtures={}
    goal=nil samples.eyeObstacleAt=nil samples.reviewAt=nil
    exactShot=nil
end
local function spawn(class,model,pos)
    local ent=ents.Create(class)
    if model then ent:SetModel(model) end
    ent:SetPos(pos) ent:Spawn() ent:Activate() fixtures[#fixtures+1]=ent return ent
end
local function state()
    local ply=Entity(1)
    return ply,NLVR_SV and NLVR_SV.Players[ply]
end
local function select(ply,class)
    if not ply:HasWeapon(class) then ply:Give(class,true) end
    ply:SelectWeapon(class)
    local ent=ply:GetWeapon(class)
    if IsValid(ent) then
        ent:SetClip1(math.max(1,ent:GetMaxClip1()))
        if ent:GetPrimaryAmmoType()>=0 then ply:SetAmmo(200,ent:GetPrimaryAmmoType()) end
        if ent:GetSecondaryAmmoType()>=0 then ply:SetAmmo(10,ent:GetSecondaryAmmoType()) end
        ent:SetNextPrimaryFire(CurTime()) ent:SetNextSecondaryFire(CurTime())
    end
    return ent
end
concommand.Add("nlvr_w_phase",function(_,_,args)
    local ply,s=state() if not s or not s.hands.right.valid then return end
    local wanted=args[1] if not wanted then return end
    if phase==wanted then ply:SendLua("NLVR_W_ACK="..string.format("%q",wanted)) return end
    phase=wanted clear()
    phaseId=phaseId+1 samples.phaseStart=CurTime()
    samples.walk=nil samples.room=nil
    base=base or ply:GetPos() previous=previous or ply:GetActiveWeapon():GetClass()
    savedMoveType=savedMoveType or ply:GetMoveType()
    ply:SetMoveType(MOVETYPE_NOCLIP)
    if not ply:Alive() and wanted~="death" then ply:Spawn() ply:SetMoveType(MOVETYPE_NOCLIP) ply:SetPos(base) end
    ply:SetHealth(5000) ply:GodEnable()
    local class=wanted:match("^weapon_") and wanted or wanted=="gmod_tool" and wanted or wanted=="gmod_camera" and wanted
    class=class or ({pistol="weapon_pistol",["357"]="weapon_357",smg1="weapon_smg1",ar2="weapon_ar2",shotgun="weapon_shotgun"})[wanted:match("^([^-]+)-")]
    class=class or ({bolt="weapon_crossbow",rocket="weapon_rpg",["fore-smg"]="weapon_smg1",["fore-shotgun"]="weapon_shotgun",
        wall="weapon_pistol",["smg-grenade"]="weapon_smg1",["melee-fast"]="weapon_crowbar",["melee-slow"]="weapon_crowbar",["melee-stun"]="weapon_stunstick",["frag-throw"]="weapon_frag",
        ["bugbait-throw"]="weapon_bugbait",hands="nlvr_hands",left="weapon_pistol",respawn="weapon_pistol",
        ["bolt-eye"]="weapon_crossbow",["bullet-passes"]="weapon_pistol",["melee-walk"]="weapon_crowbar",["melee-lunge"]="weapon_crowbar"})[wanted]
    local w=class and select(ply,class)
    if wanted=="death" then ply:GodDisable() ply:KillSilent() end
    if wanted=="left" then ply:SendLua('RunConsoleCommand("nl_vr_dominant","1") RunConsoleCommand("nl_vr_gun_angle","30")') end
    local hand=s.hands.right
    local dir=hand.ang:Forward()
    if wanted:match("%-5$") or wanted:match("%-20$") then
        -- Wait for W's actual new-class geometry and settled timeline pose. The face,
        -- rather than the prop origin or wrist, will be exactly 5/20 m from the muzzle.
        goal={metres=wanted:match("%-20$") and 20 or 5,class=class,ready=CurTime()+.3}
    elseif wanted=="bolt-eye" then
        samples.eyeObstacleAt=CurTime()+.5
    elseif wanted=="bullet-passes" then
        samples.reviewAt=CurTime()+.7
    elseif wanted=="wall" then
        local wall=spawn("prop_physics","models/hunter/plates/plate2x2.mdl",hand.pos+dir*15)
        wall:SetAngles(dir:Angle()+Angle(90,0,0)) local phys=wall:GetPhysicsObject() if IsValid(phys) then phys:EnableMotion(false) end
    elseif wanted:match("^melee") then
        if wanted=="melee-lunge" then
            local floor=spawn("prop_physics","models/hunter/plates/plate4x4.mdl",ply:GetPos()-Vector(0,0,4))
            local top=floor:NearestPoint(ply:GetPos()+Vector(0,0,32))
            floor:SetPos(floor:GetPos()+Vector(0,0,ply:GetPos().z-top.z-.1))
            local phys=floor:GetPhysicsObject() if IsValid(phys) then phys:SetPos(floor:GetPos()) phys:EnableMotion(false) end
            ply:SetMoveType(MOVETYPE_WALK)
        end
        local face=hand.pos+dir*s.scale*.78
        local target=spawn("prop_physics",(wanted=="melee-walk" or wanted=="melee-lunge") and "models/hunter/plates/plate4x4.mdl" or "models/props_junk/wood_crate001a.mdl",face)
        target:SetAngles(dir:Angle()+((wanted=="melee-walk" or wanted=="melee-lunge") and Angle(90,0,0) or Angle()))
        target:SetPos(target:GetPos()+face-target:NearestPoint(hand.pos))
        target:SetHealth(100) local phys=target:GetPhysicsObject() if IsValid(phys) then phys:EnableGravity(false) phys:EnableMotion(false) end
        samples.target=target
        samples.targetIndex=target:EntIndex()
    elseif wanted=="hands" then
        local target=spawn("prop_physics","models/props_junk/PopCan01a.mdl",hand.pos+dir*3)
        local phys=target:GetPhysicsObject() if IsValid(phys) then phys:EnableGravity(false) end
        samples.target=target
    end
    out("phase",{target_index=samples.targetIndex,class=class,valid=IsValid(w),weapon=IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass(),hand=hand,head=s.head})
    ply:SendLua("NLVR_W_ACK="..string.format("%q",wanted))
end)
concommand.Add("nlvr_w_measure",function()
    local ply,s=state() if not s then return end
    local g=NLVR_SV.Weapon(ply)
    local hand=s.weapon and s.weapon.hand or "right"
    local h=s.interact and s.interact[hand]
    local hold=NLVR_SV.Holding(ply,hand)
    out("server",{weapon=g and {class=g.class,kind=g.kind,muzzle=g.muzzle,blocked=g.blocked,twoHanded=g.twoHanded},
        last_shot=s.weapon and s.weapon.lastShot,last_projectile=s.weapon and s.weapon.lastProjectile,
        hand=s.hands[hand],proxy=h and IsValid(h.phys) and h.phys:GetPos(),melee=h and h.lastHit,
        holding=IsValid(hold) and hold:GetClass(),alive=ply:Alive(),hands=ply:HasWeapon("nlvr_hands"),
        sync_age=s.lastSync and CurTime()-s.lastSync,eye=ply:EyePos(),player_pos=ply:GetPos(),
        walk=samples.walk,room=samples.room,target_index=samples.targetIndex,phase_start=samples.phaseStart,target_valid=IsValid(samples.target),target_health=IsValid(samples.target) and samples.target:Health()})
end)
hook.Add("FinishMove","nlvr_w_walk",function(ply,mv)
    if ply~=Entity(1) or not phase or not phase:match("^melee") then return end
    local state=NLVR_SV and NLVR_SV.Players[ply]
    local applied=state and state.move and state.move.applied_total
    if applied then samples.room={applied_total=applied,from=samples.room and samples.room.from or applied} end
    local w=samples.walk or {max_speed=0,displacement=0,from=mv:GetOrigin()}
    w.max_speed=math.max(w.max_speed,mv:GetVelocity():Length())
    w.displacement=math.max(w.displacement,(mv:GetOrigin()-w.from):Length())
    samples.walk=w
end)
hook.Add("EntityTakeDamage","nlvr_w_engine_damage",function(ent,damage)
    if ent~=samples.target or damage:GetAttacker()~=Entity(1) then return end
    local inflictor=damage:GetInflictor()
    local class=IsValid(inflictor) and inflictor:GetClass()
    if class~="weapon_crowbar" and class~="weapon_stunstick" then return end
    out("melee-engine-damage",{entity=ent:EntIndex(),damage=damage:GetDamage(),damage_type=damage:GetDamageType(),
        inflictor=class,position=damage:GetDamagePosition(),health_before=ent:Health()})
end)
hook.Add("PostEntityFireBullets","nlvr_w_fixture",function(ent,b)
    if ent~=Entity(1) then return end
    local gun=NLVR_SV and NLVR_SV.Weapon(ent)
    if samples.reviewShot then
        out("review-bullet",{label=samples.reviewShot,trace=b.Trace,expected_src=samples.reviewSrc,expected_dir=samples.reviewDir})
    end
    out("bullet",{trace=b.Trace,class=IsValid(ent:GetActiveWeapon()) and ent:GetActiveWeapon():GetClass(),zero_spread=samples.exactShooting==true,
        muzzle=gun and gun.muzzle,raw_muzzle=gun and gun.rawMuzzle,blocked=gun and gun.blocked})
    if phase=="pistol-5" and not samples.punch then
        samples.punch=true ent:SetViewPunchAngles(Angle(12,6,3)) ent:SetViewPunchVelocity(Angle())
        out("injected-punch",{angle=ent:GetViewPunchAngles()})
    end
end)
hook.Add("EntityFireBullets","nlvr_w_review_observer",function(_,b)
    if samples.reviewShot=="primary" then
        out("review-bullet-hook",{src=b.Src,dir=b.Dir})
        return true -- deliberately short-circuit: W must already have prepared the bullet
    end
end)
hook.Add("Tick","nlvr_w_fixture",function()
    local ply,s=state()
    if not s or not phase then return end
    if CurTime()-last<.05 then return end last=CurTime()
    local active=ply:GetActiveWeapon()
    if IsValid(active) then samples.exitExpected=active:GetClass()=="nlvr_hands" and previous or active:GetClass() end
    if samples.eyeObstacleAt and CurTime()>=samples.eyeObstacleAt then
        local gun=NLVR_SV.Weapon(ply)
        if gun then
            local eye,aim=ply:GetShootPos(),ply:GetAimVector()
            local obstacle=spawn("prop_physics","models/props_junk/PopCan01a.mdl",eye+aim*s.scale*1.25)
            local phys=obstacle:GetPhysicsObject() if IsValid(phys) then phys:EnableMotion(false) end
            local e=util.TraceLine({start=eye,endpos=eye+aim*s.scale*2,filter=ply})
            local m=util.TraceLine({start=gun.muzzle.pos,endpos=gun.muzzle.pos+gun.muzzle.ang:Forward()*s.scale*2,filter=ply})
            samples.eyeObstacle=obstacle samples.eyeObstacleAt=nil
            out("eye-obstacle",{eye_blocked=e.Entity==obstacle,muzzle_clear=m.Entity~=obstacle,pos=obstacle:GetPos()})
        end
    end
    if samples.reviewAt and CurTime()>=samples.reviewAt then
        local gun=NLVR_SV.Weapon(ply)
        if gun then
            samples.reviewAt=nil
            local exit=gun.muzzle.pos+Vector(80,10,0)
            for _,test in ipairs({{label="primary",src=ply:GetShootPos(),expected=gun.muzzle.pos,dir=gun.muzzle.ang:Forward()},
                {label="penetration",src=exit,expected=exit,dir=Vector(0,1,0)},
                {label="missing-geometry",src=exit,expected=exit,dir=Vector(0,1,0)}}) do
                samples.reviewShot,samples.reviewSrc,samples.reviewDir=test.label,test.expected,test.dir
                local saved=s.weapon if test.label=="missing-geometry" then s.weapon=nil end
                ply:FireBullets({Src=test.src,Dir=test.dir,Spread=Vector(),Num=1,Tracer=1,Damage=1,Distance=100})
                s.weapon=saved
            end
            samples.reviewShot=nil
        end
    end
    for _,contact in ipairs(contacts) do out("collision",contact) end contacts={}
    if goal and CurTime()>=goal.ready then
        local gun=NLVR_SV.Weapon(ply)
        if gun and gun.class==goal.class then
            local dir=gun.muzzle.ang:Forward() local point=gun.muzzle.pos+dir*goal.metres*s.scale
            local target=spawn("prop_physics","models/hunter/plates/plate2x2.mdl",point)
            target:SetAngles(dir:Angle()+Angle(90,0,0))
            local offset=point-target:NearestPoint(gun.muzzle.pos)
            target:SetPos(target:GetPos()+offset)
            local phys=target:GetPhysicsObject() if IsValid(phys) then phys:SetPos(target:GetPos()) phys:SetAngles(target:GetAngles()) phys:EnableMotion(false) end
            out("target",{class=gun.class,metres=goal.metres,pos=target:GetPos(),face=point,muzzle=gun.muzzle})
            exactShot={at=CurTime()+.4,metres=goal.metres,class=goal.class}
            goal=nil
        end
    end
    if exactShot and CurTime()>=exactShot.at then
        local gun=NLVR_SV.Weapon(ply)
        if gun and gun.class==exactShot.class then
            -- A separately labelled native zero-spread bullet isolates convergence
            -- accuracy from each weapon's retained spread. Actual trigger shots also run.
            samples.exactShooting=true
            ply:FireBullets({Src=ply:EyePos(),Dir=s.head.ang:Forward(),Spread=Vector(),Num=1,Tracer=1,
                Damage=1,Distance=(exactShot.metres+1)*s.scale})
            samples.exactShooting=nil exactShot=nil
        end
    end
    local d=s.weapon
    local record=d and d.lastProjectile
    if record and record.finalizedTicks and samples.finalized~=record then
        samples.finalized=record out("projectile-finalized",record)
    end
    if record and samples.projectile~=record then
        samples.projectile=record
        local ent=Entity(record.entity)
        if IsValid(ent) then fixtures[#fixtures+1]=ent end
        local phys=IsValid(ent) and ent:GetPhysicsObject()
        out("projectile",{class=record.class,requested=record,pos=IsValid(ent) and ent:GetPos(),
            velocity=IsValid(phys) and phys:GetVelocity() or IsValid(ent) and ent:GetVelocity(),elapsed=CurTime()-record.time,
            hit_eye_obstacle=IsValid(samples.eyeObstacle) and IsValid(ent) and ent:GetParent()==samples.eyeObstacle})
        samples.lateProjectile={record=record,ent=ent}
    end
    local late=samples.lateProjectile
    if late and CurTime()-late.record.time>=.06 then
        local ent=late.ent local phys=IsValid(ent) and ent:GetPhysicsObject()
        out("projectile-late",{class=late.record.class,requested=late.record,pos=IsValid(ent) and ent:GetPos(),
            velocity=IsValid(phys) and phys:GetVelocity() or IsValid(ent) and ent:GetVelocity(),elapsed=CurTime()-late.record.time})
        samples.lateProjectile=nil
    end
    if phase=="hands" and IsValid(NLVR_SV.Holding(ply,"right")) then out("grab",{held=true}) end
end)
hook.Add("OnEntityCreated","nlvr_w_fixture",function(ent)
    if ent:GetClass()~="npc_grenade_frag" then return end
    ent:AddCallback("PhysicsCollide",function(_,data)
        local other=data.HitEntity
        local own=false local _,s=state()
        if s and s.interact then for _,hand in ipairs({"left","right"}) do if s.interact[hand].proxy==other then own=true end end end
        contacts[#contacts+1]={class=ent:GetClass(),other=IsValid(other) and other:GetClass(),own_proxy=own,speed=data.Speed,
            velocity=data.OurOldVelocity,other_velocity=data.TheirOldVelocity,pos=data.HitPos,custom=ent:GetCustomCollisionCheck()}
    end)
end)
concommand.Add("nlvr_w_done",function()
    local ply=Entity(1) clear()
    local active=IsValid(ply) and ply:GetActiveWeapon()
    local activeClass=IsValid(active) and active:GetClass() or ""
    local expected=samples.exitExpected or previous
    out("weapon-restored",{expected=expected,actual=activeClass,restored=not expected or activeClass==expected})
    if IsValid(ply) then
        ply:GodDisable()
        if previous and ply:HasWeapon(previous) then ply:SelectWeapon(previous) end
        if savedMoveType then ply:SetMoveType(savedMoveType) end
    end
    out("server-off",{vr=NLVR_SV~=nil,hands=IsValid(ply) and ply:HasWeapon("nlvr_hands")})
    hook.Remove("PostEntityFireBullets","nlvr_w_fixture") hook.Remove("Tick","nlvr_w_fixture") hook.Remove("OnEntityCreated","nlvr_w_fixture")
    hook.Remove("EntityFireBullets","nlvr_w_review_observer")
    hook.Remove("FinishMove","nlvr_w_walk")
    hook.Remove("EntityTakeDamage","nlvr_w_engine_damage")
    if util.Effect==effect then util.Effect=previousEffect end
    hook.Remove("OnEntityCreated","nlvr_w_order")
    for _,event in ipairs({"Think","Tick","PlayerPostThink","PlayerTick","FinishMove","EntityEmitSound","DoAnimationEvent"}) do hook.Remove(event,"nlvr_w_order") end
end)
