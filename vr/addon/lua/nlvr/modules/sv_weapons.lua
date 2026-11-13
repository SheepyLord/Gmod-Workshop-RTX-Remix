local module = {name = "weapons", order = 44}
local Math = include("nlvr/modules/sh_weapons.lua")
local Throw = include("nlvr/modules/sv_interact_math.lua")
local function hookEvent(context,event,private)
    local call,live,replaying=hook.Call,true,false
    local changedShots=event=="EntityFireBullets" and setmetatable({},{__mode="k"})
    context.cleanup(function() live=false end)
    if changedShots then
        local gm=gmod and gmod.GetGamemode and gmod.GetGamemode() or GAMEMODE
        if type(gm)=="table" then
            local previous,rawPrevious=gm.EntityFireBullets,rawget(gm,"EntityFireBullets")
            local function apply(self,ent,bullet,...)
                local a,b,c,d,e,f
                if previous then a,b,c,d,e,f=previous(self,ent,bullet,...) end
                if live and changedShots[bullet] then
                    changedShots[bullet]=nil bullet.Tracer=0
                    if a==nil then a=true end
                end
                return a,b,c,d,e,f
            end
            gm.EntityFireBullets=apply
            context.cleanup(function() if rawget(gm,"EntityFireBullets")==apply then gm.EntityFireBullets=rawPrevious end end)
        end
    end
    local function prepare(...)
        local result=call(private,nil,...)
        if result==true and changedShots then local _,bullet=... changedShots[bullet]=true end
        return result
    end
    -- Always register an ordinary hook. Unknown libraries retain this safe fallback;
    -- known live registries also use it when another writer replaces our takeover.
    local fallbackId="nlvr."..context.name
    context.hook(event,function(...)
        if not live or replaying then return end
        if prepare(...)==false then return false end
    end)
    local plain=hook.GetTable()
    local ulib=type(hook.GetULibTable)=="function" and hook.GetULibTable()
    local heldLevels=type(ulib)=="table" and ulib[event]
    if heldLevels then for n=-2,2 do if type(heldLevels[n])~="table" then heldLevels=nil break end end end
    if not heldLevels then
        -- Capability probe uses a private event, never a gameplay hook. GetTable can
        -- be a detached copy even when it looks like the stock table.
        local probe=private..".registry_probe" local first,second={},{}
        hook.Add(probe,fallbackId,function() return first end)
        local probeRegistry=hook.GetTable()
        local saved=probeRegistry[probe]
        probeRegistry[probe]={[fallbackId]=function() return second end}
        local ok,value=pcall(call,probe,nil)
        probeRegistry[probe]=saved
        hook.Remove(probe,fallbackId)
        if not ok or value~=second then return end
    end
    local held=plain[event] or {}
    local owned=setmetatable({},{__index=held,__newindex=function(_,id,fn) held[id]=fn end})
    local ownedLevels
    local id="nlvr.weapons.dispatch"
    local function dispatch(...)
        if not live or replaying then return end
        local changed=prepare(...)
        if changed==false then return false end
        if not live then return end
        -- A rebuilt registry may contain a copy of this dispatcher. In that case
        -- the caller already owns iteration: prepare, then let its other hooks run
        -- once instead of recursively replaying the copied table.
        if plain[event]~=owned and (not ownedLevels or ulib[event]~=ownedLevels) then return end
        if plain[event]==owned then plain[event]=held end
        if ownedLevels and ulib[event]==ownedLevels then ulib[event]=heldLevels end
        replaying=true
        local ok,a,b,c,d,e,f=pcall(call,event,nil,...)
        replaying=false
        if live and plain[event]==held then plain[event]=owned end
        if live and ownedLevels and ulib[event]==heldLevels then ulib[event]=ownedLevels end
        if not ok then error(a,0) end
        if changed and changedShots then local _,bullet=... bullet.Tracer=0 end
        return a,b,c,d,e,f
    end
    rawset(owned,id,dispatch)
    if heldLevels then
        ownedLevels={}
        for n=-2,2 do
            local list=heldLevels[n]
            ownedLevels[n]=setmetatable({},{__index=list,__newindex=function(_,key,value) list[key]=value end})
        end
        rawset(ownedLevels[HOOK_HIGH or -1],id,{fn=dispatch,isstring=true})
        ulib[event]=ownedLevels
    end
    plain[event]=owned
    context.cleanup(function()
        live=false
        hook.Remove(event,fallbackId)
        rawset(owned,id,nil)
        for key,fn in pairs(held) do rawset(owned,key,fn) end
        if plain[event]==owned then plain[event]=held end
        if ownedLevels then
            for n=-2,2 do
                rawset(ownedLevels[n],id,nil)
                for key,entry in pairs(heldLevels[n]) do rawset(ownedLevels[n],key,entry) end
            end
            if ulib[event]==ownedLevels then ulib[event]=heldLevels end
        end
    end)
end
local ctx, pending, grace, actions, shotNumber, released, interpolation
local function restoreOwnership(ply,state)
    if state.weaponOwnerHand and ctx.core.ClaimHand then ctx.core.ClaimHand(ply,state.weaponOwnerHand,"weapons",false) end
    state.weaponOwnerHand=nil
end
local function ownHand(ply,state)
    local data=state.weapon
    local ent=ply:GetActiveWeapon()
    local hand=data and IsValid(ent) and ent:GetClass()==data.class and Math.Kind(data.class)~="hands" and data.hand
    if state.weaponOwnerHand~=hand then restoreOwnership(ply,state) end
    if hand and ctx.core.ClaimHand and ctx.core.ClaimHand(ply,hand,"weapons",true) then state.weaponOwnerHand=hand end
end
local function playerFor(ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then return ent end
    local owner=ent:GetOwner()
    if IsValid(owner) and owner:IsPlayer() then return owner end
    if IsValid(owner) and owner.GetOwner then owner=owner:GetOwner() if IsValid(owner) and owner:IsPlayer() then return owner end end
    local thrower=ent.GetInternalVariable and ent:GetInternalVariable("m_hThrower")
    if IsValid(thrower) and thrower:IsPlayer() then return thrower end
end
local function handPose(state,hand)
    local pose=state.hands[hand]
    if not pose or not pose.valid then return end
    local physical=state.interact and state.interact[hand]
    return {pos=physical and IsValid(physical.phys) and physical.phys:GetPos() or pose.pos,
        ang=pose.ang,vel=pose.vel,angvel=pose.angvel}
end
local function filter(ply,extra,another)
    local skip={[ply]=true}
    if IsValid(extra) then skip[extra]=true end
    if IsValid(another) then skip[another]=true end
    local state=ctx.Players[ply]
    if state and state.interact then
        for _,hand in ipairs({"left","right"}) do
            local h=state.interact[hand]
            if IsValid(h.proxy) then skip[h.proxy]=true end
            if h.grip then skip[h.grip.ent]=true end
        end
    end
    return function(ent) return not skip[ent] end
end
local function weapon(ply,relocating)
    local state=ctx.Players[ply]
    if not state or not IsValid(ply) or not ply:Alive() or ply:InVehicle() or not state.lastSync or CurTime()-state.lastSync>1 then return end
    local ent=ply:GetActiveWeapon()
    if not IsValid(ent) then return end
    local data=state.weapon
    if not data or data.class~=ent:GetClass() then return end
    local pose=handPose(state,data.hand)
    if not pose or pose.pos:DistToSqr(ply:EyePos())>ctx.Reach(ply)^2 then return end
    local ang=Math.GunAngle(pose.ang,data.pitch)
    local offName=Math.Opposite(data.hand)
    local off=handPose(state,offName)
    local offState=state.interact and state.interact[offName]
    local occupied=offState and (offState.grip or offState.climb or offState.blocked)
    if ctx.core.Holding and IsValid(ctx.core.Holding(ply,offName)) then occupied=true end
    local two=false
    if not occupied and data.two and data.fore:Length()>0 and off and bit.band(state.hands[offName].buttons or 0,1)~=0 then
        local point=LocalToWorld(data.fore*state.scale,Angle(),pose.pos,ang)
        if point:DistToSqr(off.pos)<=(state.scale*(data.foreActive and 0.25 or 0.12))^2 then ang=Math.Along(pose.pos,off.pos,ang:Up()) two=true end
    end
    data.foreActive=two
    local muzzle=LocalToWorld(data.offset*state.scale,Angle(),pose.pos,ang)
    local safe,blocked=Math.SafeMuzzle(ply:EyePos(),muzzle,util.TraceLine,filter(ply,ent,relocating),state.scale)
    return {class=ent:GetClass(),kind=Math.Kind(ent:GetClass()),ent=ent,hand=data.hand,twoHanded=two,
        muzzle={pos=safe,ang=ang},rawMuzzle=muzzle,blocked=blocked,pose=pose,
        meleeTip=data.meleeOffset and LocalToWorld(data.meleeOffset*state.scale,Angle(),pose.pos,ang)}
end
local function notify(ply,gun,src,dir,hit,tracer,flash)
    shotNumber=shotNumber+1
    local state=ctx.Players[ply]
    if not state or not state.weapon then return end
    local record={class=gun.class,src=src,dir=dir,hit=hit,blocked=gun.blocked,number=shotNumber,tick=engine.TickCount()}
    state.weapon.lastShot=record
    ctx.Debug.weapons=ctx.Debug.weapons or {}
    ctx.Debug.weapons[ply:EntIndex()]=record
    ctx.Net.Send(ply,65,function(w)
        w.WriteString(gun.class) w.WriteVector(src)
        w.WriteFloat(dir.x) w.WriteFloat(dir.y) w.WriteFloat(dir.z) w.WriteVector(hit)
        w.WriteBool(tracer) w.WriteBool(flash)
        w.WriteUInt(shotNumber%65536,16) -- repeated equal shots must not be coalesced forever
    end)
end
local function give(ply,state,first)
    if not IsValid(ply) or not ply:Alive() then return end
    if first then local old=ply:GetActiveWeapon() state.weaponPrevious=IsValid(old) and old:GetClass() or nil end
    if not ply:HasWeapon("nlvr_hands") then ply:Give("nlvr_hands",true) end
    if first and not state.weaponPrevious then ply:SelectWeapon("nlvr_hands") end
end
local function restore(ply,state)
    restoreOwnership(ply,state)
    if not IsValid(ply) then return end
    local active=ply:GetActiveWeapon()
    local hands=IsValid(active) and active:GetClass()=="nlvr_hands"
    local nextClass=hands and state.weaponPrevious
    if hands and (not nextClass or not ply:HasWeapon(nextClass)) then
        local weight=-math.huge
        for _,ent in ipairs(ply:GetWeapons()) do
            if IsValid(ent) and ent:GetClass()~="nlvr_hands" then
                local value=ent.GetWeight and ent:GetWeight() or 0
                if value>weight then nextClass,weight=ent:GetClass(),value end
            end
        end
    end
    if ply:HasWeapon("nlvr_hands") then ply:StripWeapon("nlvr_hands") end
    if hands and nextClass and ply:HasWeapon(nextClass) then ply:SelectWeapon(nextClass) end
    state.weapon=nil
end
local function clearGrace(ent,record)
    for _,pair in ipairs(record.pairs or {}) do if IsValid(pair) then pair:Remove() end end
    if IsValid(ent) and ent:GetCustomCollisionCheck()==true then
        ent:SetCustomCollisionCheck(record.custom) ent:CollisionRulesChanged()
    end
    grace[ent]=nil
end
local projectileClass={rpg_missile="weapon_rpg",crossbow_bolt="weapon_crossbow",grenade_ar2="weapon_smg1",
    prop_combine_ball="weapon_ar2",npc_grenade_frag="weapon_frag",npc_grenade_bugbait="weapon_bugbait"}
local function showLaunch(ent,record)
    if record.hidden and IsValid(ent) and ent:GetNoDraw() then ent:SetNoDraw(false) end
    record.hidden=nil
end
local function finishNative(record)
    local f=record.finalize
    if not f then return end
    if IsValid(f.ent) and IsValid(f.phys) then
        if f.moving and not f.phys:IsMotionEnabled() then f.phys:EnableMotion(true) end
        f.ent:SetPos(f.pos) f.ent:SetAngles(f.ang)
        f.phys:SetPos(f.pos) f.phys:SetAngles(f.ang)
        local spin=WorldToLocal(f.spin or Vector(),Angle(),Vector(),f.phys:GetAngles())*(180/math.pi)
        f.phys:AddAngleVelocity(spin-f.phys:GetAngleVelocity())
        f.phys:SetVelocityInstantaneous(f.velocity) f.phys:Wake()
        f.receipt.nativePos,f.receipt.nativeVelocity=f.ent:GetPos(),f.phys:GetVelocity()
        f.receipt.finalizedTicks,f.receipt.motionHeld=engine.TickCount()-record.tick,false
    end
    record.finalize=nil
end
local function redirect(ent,record,initializing)
    if record.finalize then
        if initializing then return false end
        finishNative(record) return true
    end
    local ply=playerFor(ent)
    local state=ply and ctx.Players[ply]
    local gun=state and weapon(ply,ent)
    if not gun or gun.class~=projectileClass[record.class] then return false end
    local velocity=ent:GetVelocity()
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then velocity=phys:GetVelocity() end
    if velocity:Length()<1 and gun.kind~="grenade" then return false end -- native setup follows OnEntityCreated
    local pos,dir=gun.muzzle.pos,gun.muzzle.ang:Forward()
    local spin
    if gun.kind=="grenade" then
        local thrown=state.weapon.thrown
        if thrown and CurTime()-thrown.time<1.2 then velocity,spin=thrown.velocity,thrown.spin
        else velocity,spin=Throw.Throw(state.history[gun.hand],CurTime(),state.scale) end
        pos=Math.SafeMuzzle(ply:EyePos(),gun.pose.pos,util.TraceLine,filter(ply,ent),state.scale)
        grace[ent]={ply=ply,expires=CurTime()+0.2,custom=ent:GetCustomCollisionCheck(),pairs={}}
        if ctx.core.RegisterReleased then ctx.core.RegisterReleased(ply,ent,.2) end
        ent:SetCustomCollisionCheck(true) ent:CollisionRulesChanged()
        if state.interact then for _,hand in ipairs({"left","right"}) do
            local h=state.interact[hand]
            local proxy=h.proxy
            if IsValid(proxy) and IsValid(phys) then
                local pair=constraint.NoCollide(ent,proxy,0,0,true)
                if IsValid(pair) then grace[ent].pairs[#grace[ent].pairs+1]=pair end
            end
        end end
    else velocity=dir*velocity:Length() end
    ent:SetPos(pos) ent:SetAngles(dir:Angle())
    if IsValid(phys) then
        phys:SetPos(pos) phys:SetAngles(dir:Angle())
        if spin then
            local localSpin=WorldToLocal(spin,Angle(),Vector(),phys:GetAngles())*(180/math.pi)
            phys:AddAngleVelocity(localSpin-phys:GetAngleVelocity())
        end
        phys:SetVelocityInstantaneous(velocity) phys:Wake()
    else ent:SetLocalVelocity(velocity) end
    if not ent:IsEffectActive(EF_NOINTERP) then
        ent:AddEffects(EF_NOINTERP) interpolation[ent]=engine.TickCount()
    end
    showLaunch(ent,record)
    local feedback=gun.kind=="grenade" and ctx.core.ProjectileFeedback and ctx.core.ProjectileFeedback(ply,gun.hand) or false
    state.weapon.lastProjectile={class=record.class,pos=pos,velocity=velocity,ticks=engine.TickCount()-record.tick,
        entity=ent:EntIndex(),time=CurTime(),nativePos=ent:GetPos(),nativeVelocity=IsValid(phys) and phys:GetVelocity() or ent:GetVelocity(),
        feedback=feedback,nointerp=ent:IsEffectActive(EF_NOINTERP),launchRay={pos=pos,dir=dir}}
    if initializing and gun.kind=="grenade" and IsValid(phys) then
        local moving=phys:IsMotionEnabled()
        record.finalize={ent=ent,phys=phys,pos=pos,ang=phys:GetAngles(),velocity=velocity,spin=spin,
            moving=moving,receipt=state.weapon.lastProjectile}
        -- The grenade's native initializer adds its own velocity after its spawn sound.
        -- Hold motion at the correct hand position until the next pre-physics boundary,
        -- then reapply the captured physical throw; no eye-origin solver step can run.
        if moving then phys:EnableMotion(false) end
        state.weapon.lastProjectile.motionHeld=true
    end
    notify(ply,gun,pos,dir,pos+dir*state.scale*5,false,gun.kind~="grenade")
    return not record.finalize
end
local function melee(ply,state,gun)
    if gun.kind~="melee" or not state.weapon.melee or not state.interact then state.weapon.tip=nil return end
    local h=state.interact[gun.hand]
    if not h then return end
    local tip=gun.meleeTip
    if not tip then state.weapon.tip=nil return end
    local previous=state.weapon.tip
    local body=ply:GetPos()
    local room=state.move and state.move.applied_total or Vector()
    state.weapon.tip={pos=tip,time=CurTime(),class=gun.class,proxy=h.proxy,phys=h.phys,
        body=body,room=room,epoch=state.move and state.move.follow_epoch}
    if not previous or previous.class~=gun.class or previous.proxy~=h.proxy or previous.phys~=h.phys or
        previous.epoch~=(state.move and state.move.follow_epoch) then return end
    local dt=CurTime()-previous.time
    if dt<=0 or dt>0.1 then return end
    -- Tracking velocities exclude walking, snap turns and teleports. Angular velocity
    -- is world radians/s; the cross product accounts for the tool head about the wrist.
    local velocity=(gun.pose.vel or Vector())+Throw.Cross(gun.pose.angvel or Vector(),tip-gun.pose.pos)
    local bodyDelta=body-(previous.body or body)
    local roomDelta=room-(previous.room or room)
    local artificial=bodyDelta-roomDelta
    if artificial:Length()>state.scale*.5 then return end
    local displacement=tip-previous.pos
    local tracked=velocity*dt
    -- Room follow is already represented by tracking. A physical proxy can also be
    -- one body-movement sample behind, especially on the first walking/swing tick.
    -- Accept either synchronized frame, but reject jumps unexplained by either.
    local residual=math.min((displacement-artificial-tracked):Length(),(displacement-tracked):Length())
    if residual>state.scale*.05 or velocity:Length()<state.scale*1.5 then return end
    -- Velocity, not body travel, determines damage. Keep the full world sweep so
    -- a door between the old tip and translated body frame cannot be skipped.
    local sweepStart=previous.pos
    local radius=state.scale*0.03 local hull=Vector(radius,radius,radius)
    local tr=util.TraceHull({start=sweepStart,endpos=tip,mins=-hull,maxs=hull,filter=filter(ply,gun.ent),mask=MASK_SHOT})
    if not tr.Hit or tr.StartSolid or tr.HitPos:DistToSqr(sweepStart)<0.000001 then return end
    -- Share P's exact damage/cooldown implementation, including its held/proxy exclusions.
    local facade=actions.physics
    facade.proxies,facade.held,facade.released={},{},released
    for _,s in pairs(ctx.Players) do
        if s.interact then for _,hand in ipairs({"left","right"}) do local p=s.interact[hand]
            if IsValid(p.proxy) then facade.proxies[p.proxy]=true end
            if p.grip then facade.held[p.grip.ent]=true end
        end end
    end
    local old=h.grip local before=h.lastHit
    h.grip={ent=gun.ent}
    actions.Hit(ply,state,h,tr.Entity,tr.HitPos,velocity,velocity:Length(),"held")
    h.grip=old
    if h.lastHit~=before then
        gun.ent:EmitSound(gun.class=="weapon_stunstick" and "Weapon_StunStick.Melee_Hit" or "Weapon_Crowbar.Melee_Hit")
        -- A hull's HitPos is its centre, outside the actual surface by its radius.
        -- Impact retraces Start -> Origin, so give it a real contact and one centimetre
        -- of inward skin (also robust to effect-network coordinate quantisation).
        local impact=util.TraceLine({start=sweepStart,endpos=tr.HitPos-tr.HitNormal*(radius+state.scale*.01),
            filter=filter(ply,gun.ent),mask=MASK_SHOT})
        if not impact.Hit or impact.Entity~=tr.Entity then impact=tr end
        local origin=impact.HitPos
        if gun.class~="weapon_stunstick" then origin=origin-impact.HitNormal*(impact==tr and radius+state.scale*.01 or state.scale*.01) end
        local effect=EffectData() effect:SetOrigin(origin) effect:SetNormal(impact.HitNormal)
        effect:SetFlags(0) effect:SetAttachment(0)
        effect:SetStart(sweepStart) effect:SetEntity(tr.Entity)
        effect:SetSurfaceProp(impact.SurfaceProps or 0) effect:SetHitBox(impact.HitBoxBone or impact.HitBox or 0) effect:SetDamageType(DMG_CLUB)
        util.Effect(gun.class=="weapon_stunstick" and "StunstickImpact" or "Impact",effect,true,true)
        notify(ply,gun,gun.muzzle.pos,gun.muzzle.ang:Forward(),tr.HitPos,false,false)
    end
end
function module.Start(ctx)
    if not weapons or type(weapons.Register)~="function" then return end
    -- Use a distinct name below: the module-level context is needed by owned callbacks.
    module.Bind(ctx)
end
function module.Bind(context)
    ctx,pending,grace,shotNumber,released,interpolation=context,{},{},0,{},{}
    Math.Hands()
    actions=include("nlvr/modules/sv_interact_actions.lua").New(ctx,function(h,strength,kind)
        h.pulse=((h.pulse or 0)+1)%65536 h.strength,h.pulseKind=strength,kind
    end)
    actions.physics={proxies={},held={},released={}}
    ctx.core.Weapon=weapon
    ctx.cleanup(function() if ctx.core.Weapon==weapon then ctx.core.Weapon=nil end end)
    ctx.On("OnStart",function(ply,state) give(ply,state,true) end)
    ctx.On("OnStop",restore)
    ctx.On("OnSpawn",function(_,state) state.weaponNeedHands=true if state.weapon then state.weapon.tip=nil end end)
    ctx.On("OnDeath",function(ply,state) restoreOwnership(ply,state) if state.weapon then state.weapon.tip,state.weapon.thrown=nil,nil end end)
    ctx.On("release",function(ply,_,ent,_,throw)
        if throw and IsValid(ent) then released[ent]={ply=ply,expires=CurTime()+.2} end
    end)
    ctx.Net.On(64,function(ply)
        local class,hand=net.ReadString(),net.ReadBool() and "left" or "right"
        -- Explicit floats avoid WriteVector's 1/32-unit quantisation in metre offsets.
        local offset=Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
        local fore=Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
        local meleeOffset=Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
        local two,pitch,physical=net.ReadBool(),net.ReadFloat(),net.ReadBool()
        local token=net.ReadUInt(16)
        local ent=ply:GetActiveWeapon()
        if #class>128 or not IsValid(ent) or ent:GetClass()~=class or not Math.Vector(offset) or not Math.Vector(fore) or
            offset:Length()>1.5 or fore:Length()>0.65 or not Math.Vector(meleeOffset) or meleeOffset:Length()>1.5 or
            Math.Kind(class)=="melee" and meleeOffset:Length()<.02 or not Math.Finite(pitch) or math.abs(pitch)>45 then return end
        local old=ctx.Players[ply].weapon
        ctx.Players[ply].weapon={class=class,hand=hand,offset=offset,fore=fore,meleeOffset=meleeOffset,two=two,pitch=pitch,melee=physical,
            tip=old and old.class==class and old.tip or nil,lastShot=old and old.lastShot,lastProjectile=old and old.lastProjectile,
            thrown=old and old.class==class and old.thrown or nil,foreActive=old and old.class==class and old.foreActive or false}
        ownHand(ply,ctx.Players[ply])
        ctx.Net.Send(ply,66,function(w) w.WriteString(class) w.WriteUInt(token,16) end)
    end)
    ctx.On("OnSync",function(_,state)
        local d=state.weapon
        if not d then return end
        local pose=state.hands[d.hand]
        local down=pose and bit.band(pose.buttons or 0,2)~=0
        if d.trigger and not down and Math.Kind(d.class)=="grenade" then
            local v,spin=Throw.Throw(state.history[d.hand],CurTime(),state.scale)
            d.thrown={time=CurTime(),velocity=v,spin=spin}
        end
        d.trigger=down
    end)
    -- Preprocess before the ordinary hook chain: a portal hook may itself return true.
    -- Our private owned callback is registry-guarded; downstream hooks keep their order
    -- and return values. The final true (only after dispatch) applies modified tables.
    ctx.hook("NLVRWeaponBullet",function(ent,bullet)
        local ply=playerFor(ent)
        if not ply or ent~=ply and ent~=ply:GetActiveWeapon() then return end
        if not Math.Vector(bullet.Src) or bullet.Src:DistToSqr(ply:GetShootPos())>25 then return end
        local gun=ply and weapon(ply)
        if not gun then
            -- A VR shot with expired/unacknowledged geometry must not fall through
            -- to an eye-origin bullet. Other players retain the normal engine path.
            if ply and ctx.Players[ply] then return false end
            return
        end
        if gun.kind=="hands" then return false end
        bullet.Src,bullet.Dir=gun.muzzle.pos,gun.muzzle.ang:Forward()
        local tracer=bullet.Tracer==nil and 1 or bullet.Tracer
        bullet.Tracer=0
        local original=bullet.Callback
        local first=true
        bullet.Callback=function(attacker,tr,damage)
            if first then
                first=false
                if tracer>0 then
                    local effect=EffectData()
                    effect:SetStart(tr.StartPos or bullet.Src) effect:SetOrigin(tr.HitPos) effect:SetScale(5000)
                    effect:SetEntity(NULL) effect:SetAttachment(0) effect:SetFlags(0)
                    util.Effect(gun.class=="weapon_ar2" and "AR2Tracer" or "Tracer",effect,true,true)
                end
                notify(ply,gun,tr.StartPos or bullet.Src,bullet.Dir,tr.HitPos,false,true)
            end
            if original then return original(attacker,tr,damage) end
        end
        return true
    end)
    local function ownEvent(event,private) hookEvent(ctx,event,private) end
    ownEvent("EntityFireBullets","NLVRWeaponBullet")
    ctx.hook("OnEntityCreated",function(ent)
        local class=ent:GetClass()
        if projectileClass[class] then
            local record={class=class,time=CurTime(),tick=engine.TickCount()}
            pending[ent]=record
            -- This fly grenade has no initialized-owner launch callback. It must not
            -- render at the eye while ownership resolves; physics is left native.
            if class=="npc_grenade_bugbait" and not ent:GetNoDraw() then
                ent:SetNoDraw(true) record.hidden=true
            end
        end
    end)
    local function launches(ply,initializing)
        if not ctx.Players[ply] then return end
        for ent,record in pairs(pending) do
            if not record.running and IsValid(ent) and playerFor(ent)==ply then
                record.running=true
                local done=redirect(ent,record,initializing)
                record.running=nil
                if done then pending[ent]=nil end
            end
        end
    end
    ctx.hook("PlayerPostThink",function(ply) launches(ply,true) end)
    ctx.hook("DoAnimationEvent",function(ply) launches(ply,true) end)
    ctx.hook("NLVRWeaponLaunch",function(data)
        local ply=playerFor(data.Entity)
        if ply then launches(ply,true) end
    end)
    ownEvent("EntityEmitSound","NLVRWeaponLaunch")
    ctx.hook("Tick",function()
        for ent,at in pairs(interpolation) do
            if not IsValid(ent) or engine.TickCount()>at+1 then
                if IsValid(ent) then ent:RemoveEffects(EF_NOINTERP) end
                interpolation[ent]=nil
            end
        end
        for ent,record in pairs(released) do if not IsValid(ent) or CurTime()>=record.expires then released[ent]=nil end end
        for ent,record in pairs(pending) do
            local owner=IsValid(ent) and playerFor(ent)
            if not IsValid(ent) or CurTime()-record.time>0.25 or owner and not ctx.Players[owner] then
                finishNative(record) showLaunch(ent,record) pending[ent]=nil
            elseif redirect(ent,record) then pending[ent]=nil end
        end
        for ent,record in pairs(grace) do if not IsValid(ent) or CurTime()>=record.expires then clearGrace(ent,record) end end
        for ply,state in pairs(ctx.Players) do
            if state.weaponNeedHands and ply:Alive() then give(ply,state,false) state.weaponNeedHands=nil end
            if ply:Alive() then ownHand(ply,state) else restoreOwnership(ply,state) end
            local gun=weapon(ply)
            if gun then melee(ply,state,gun) elseif state.weapon then state.weapon.tip=nil end
        end
    end)
    ctx.hook("ShouldCollide",function(a,b)
        local record=grace[a] or grace[b]
        local other=grace[a] and b or a
        if not record then return end
        if other==record.ply then return false end
        local state=ctx.Players[record.ply]
        if state and state.interact then for _,hand in ipairs({"left","right"}) do
            if other==state.interact[hand].proxy then return false end
        end end
    end)
end
function module.Stop()
    if not ctx then return end
    for ply,state in pairs(ctx.Players) do restore(ply,state) end
    for ent,record in pairs(pending or {}) do finishNative(record) showLaunch(ent,record) end
    for ent,record in pairs(grace or {}) do clearGrace(ent,record) end
    for ent in pairs(interpolation or {}) do if IsValid(ent) then ent:RemoveEffects(EF_NOINTERP) end end
    pending,released={},{} ctx.Debug.weapons=nil
end
return module
