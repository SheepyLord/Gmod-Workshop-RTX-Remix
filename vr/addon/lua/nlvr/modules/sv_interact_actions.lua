local Math = include("nlvr/modules/sv_interact_math.lua")
local Actions = {}
local function index(ent) return IsValid(ent) and ent:EntIndex() or 0 end
function Actions.New(ctx, pulse, grab, release)
    local A = {}
    local inventory={}
    local useTimes=setmetatable({},{__mode="k"})
    local function restoreItem(ent,record)
        if not IsValid(ent) or ent:GetNoDraw() then return end
        local expected=record.destination+record.gravity*((CurTime()-record.began)^2*0.5)
        if ent:GetPos():DistToSqr(record.destination)>16 and ent:GetPos():DistToSqr(expected)>16 then return end
        ent:SetPos(record.pos) ent:SetAngles(record.ang)
        if IsValid(record.phys) then
            record.phys:SetPos(record.pos) record.phys:SetAngles(record.ang)
            record.phys:SetVelocity(record.velocity)
            record.phys:AddAngleVelocity(record.spin-record.phys:GetAngleVelocity())
        end
    end
    function A.RestoreItems(ply)
        for ent,record in pairs(inventory) do
            if not ply or record.ply==ply then restoreItem(ent,record) inventory[ent]=nil end
        end
    end
    function A.UpdateItems()
        for ent,record in pairs(inventory) do
            if not IsValid(ent) then inventory[ent]=nil
            elseif CurTime()>=record.expires then restoreItem(ent,record) inventory[ent]=nil end
        end
    end
    function A.Consume(ply,ent)
        if inventory[ent] then return end
        -- Native CItem::Use carries the kit as a prop. Its trigger touch owns inventory grants.
        local phys=ent:GetPhysicsObject()
        local destination=ply:WorldSpaceCenter()
        local record={ply=ply,pos=ent:GetPos(),ang=ent:GetAngles(),phys=phys,destination=destination,expires=CurTime()+0.15,began=CurTime(),
            gravity=IsValid(phys) and phys:IsGravityEnabled() and physenv.GetGravity() or Vector(),
            velocity=IsValid(phys) and phys:GetVelocity() or Vector(),spin=IsValid(phys) and phys:GetAngleVelocity() or Vector()}
        inventory[ent]=record
        ent:SetPos(destination)
        if IsValid(phys) then phys:SetPos(destination) phys:SetVelocity(Vector()) phys:Wake() end
    end
    function A.EndPull(h)
        if h.pull then A.physics.EndPull(h.pull.ent) h.pull=nil end
    end
    local function customUse(ent)
        local definition=scripted_ents and scripted_ents.GetStored(ent:GetClass())
        local base=scripted_ents and scripted_ents.GetStored("base_anim")
        local use=rawget(ent:GetTable(),"Use") or definition and definition.t and definition.t.Use
        if type(use)~="function" or base and base.t and use==base.t.Use then return end
        return use
    end
    local function usable(ent)
        if not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() or ent:IsNPC() then return false end
        local class=ent:GetClass()
        return class:match("^func_.*button") or class:match("door") or class:match("lever") or
            class=="gmod_button" or class:match("^item_") or customUse(ent)~=nil
    end
    function A.Use(ply,h,pose,scale,gripping,trigger,heldGrip,allowed)
        local reach=scale*((gripping or heldGrip) and 0.16 or 0.13)
        local box=Vector(reach,reach,reach)
        local target,distance
        for _,ent in ipairs(ents.FindInBox(pose.pos-box,pose.pos+box)) do
            if not A.physics.proxies[ent] and usable(ent) then
                local point=ent:NearestPoint(pose.pos)
                local d=point:DistToSqr(pose.pos)
                if d <= reach^2 and (not distance or d<distance) and A.physics.Visible(ply,pose.pos,point,ent) then target,distance=ent,d end
            end
        end
        if not target then h.useTouch=nil return false end
        local item=target:GetClass():match("^item_")
        local edge=target~=h.useTouch or gripping or trigger or item and heldGrip
        h.useTouch=target
        if allowed==false then return false end -- tracking contact is not a Use and must not consume an available grab
        if item and not gripping and not heldGrip then return false end
        if not edge or (h.useAt and CurTime()<h.useAt) then return true end
        local times=useTimes[target]
        if not times then times=setmetatable({},{__mode="k"}) useTimes[target]=times end
        if times[ply] and CurTime()<times[ply] then return true end
        h.useAt=CurTime()+0.3
        times[ply]=h.useAt -- two hands touching one toggle must not activate then immediately deactivate it
        if hook.Run("PlayerUse",ply,target)==false then return true end
        if target.CPPICanUse and target:CPPICanUse(ply)==false then return true end
        if item and hook.Run("PlayerCanPickupItem",ply,target)==false then return true end
        if item and target.CPPICanPickup and target:CPPICanPickup(ply)==false then return true end
        if item and not customUse(target) then A.Consume(ply,target) else target:Use(ply,ply,USE_ON,1) end
        pulse(h,0.2,1)
        h.lastUse=index(target)
        return true
    end
    function A.Hit(ply,state,h,ent,position,velocity,speed,source)
        local main=state.weapon and state.weapon.hand or "right"
        if source~="held" and (state.interact.owners and state.interact.owners[h.name] or
            h.name==main and (state.interact.controls[h.name] or {}).grip==false) then return end
        if not IsValid(ent) or ent:IsWorld() or ent==ply or A.physics.proxies[ent] or A.physics.held[ent] or
            A.physics.released[ent] and A.physics.released[ent].ply==ply then return end
        velocity=Math.Limit(velocity,state.scale*12)
        speed=math.min(speed,state.scale*12)
        if ent:IsNPC() and (not h.pushAt or CurTime()>=h.pushAt) then
            ent:SetVelocity(Math.Limit(velocity*0.55,state.scale*4)) h.pushAt=CurTime()+0.1
        end
        if not state.interact.options.melee then return end
        local damage=Math.Damage(speed,state.scale,source=="held")
        h.hitAt=h.hitAt or setmetatable({},{__mode="k"})
        if damage==0 or (h.hitAt[ent] or 0)>CurTime() then return end
        h.hitAt[ent]=CurTime()+0.35
        local phys=ent:GetPhysicsObject()
        local impulse=velocity*(.55*math.min(IsValid(phys) and phys:GetMass() or 8,8))
        local info=DamageInfo()
        info:SetAttacker(ply)
        info:SetInflictor(source=="held" and h.grip and IsValid(h.grip.ent) and h.grip.ent or IsValid(h.proxy) and h.proxy or ply)
        info:SetDamageType(DMG_CLUB) info:SetDamage(damage) info:SetDamagePosition(position)
        -- Own the native body's impulse once; damage must not apply a second kick.
        info:SetDamageForce(IsValid(phys) and Vector() or impulse)
        ent:TakeDamageInfo(info)
        if IsValid(phys) and phys:IsMotionEnabled() then
            -- Bounded transfer of an 8 kg hand's momentum; light props cannot gain 30x speed.
            phys:ApplyForceOffset(impulse,position)
        end
        h.lastHit={ent=index(ent),damage=damage,speed=speed,source=source or "hand"}
        pulse(h,math.min(0.95,0.2+speed/state.scale*0.08),5)
    end
    function A.Surface(ply,pose,scale)
        -- HL2 point ladders have no solid hull for the usual CONTENTS_LADDER trace.
        for _,ladder in ipairs(ents.FindByClass("func_useableladder")) do
            local data=ladder:GetSaveTable()
            local top,bottom=data.point0 or data.m_vecPlayerMountPositionTop,data.point1 or data.m_vecPlayerMountPositionBottom
            if isvector(top) and isvector(bottom) and not data.StartDisabled and not data.m_bDisabled then
                -- Native endpoints are relative to the ladder origin after Spawn (SDK func_ladder.cpp).
                top=LocalToWorld(top,Angle(),ladder:GetPos(),ladder:GetAngles())
                bottom=LocalToWorld(bottom,Angle(),ladder:GetPos(),ladder:GetAngles())
                local point=Math.Segment(pose.pos,bottom,top)
                if point:DistToSqr(pose.pos)<=(scale*0.16)^2 and A.physics.Visible(ply,pose.pos,point,ladder) then return pose.pos end
            end
        end
        local box=Vector(scale*0.08,scale*0.08,scale*0.08)
        local directions={pose.ang:Forward(),Vector(0,0,-1),Vector(0,0,1),pose.ang:Right(),-pose.ang:Right()}
        for _,dir in ipairs(directions) do
            local tr=util.TraceHull({start=pose.pos,endpos=pose.pos+dir*scale*0.14,mins=-box,maxs=box,
                filter=A.physics.Filter(ply),mask=bit.bor(MASK_PLAYERSOLID,CONTENTS_LADDER)})
            local ladder=tr.Contents and bit.band(tr.Contents,CONTENTS_LADDER)~=0 or
                IsValid(tr.Entity) and tr.Entity:GetClass():match("ladder")
            if tr.Hit and (tr.HitWorld or ladder) then
                if ladder then return pose.pos end
                -- Acquire a lip/side edge, rather than sticking to the middle of every flat wall.
                local normal=tr.HitNormal
                local tangent=Math.Unit(Math.Cross(normal,Vector(0,0,1)),Vector(1,0,0))
                for _,offset in ipairs({Vector(0,0,scale*0.35),tangent*scale*0.3,-tangent*scale*0.3}) do
                    local edge=util.TraceLine({start=pose.pos+offset,endpos=pose.pos+offset-normal*scale*0.22,
                        filter=A.physics.Filter(ply),mask=MASK_PLAYERSOLID})
                    if not edge.Hit and not edge.StartSolid then return pose.pos end
                end
            end
        end
    end
    function A.Target(ply,pose,scale,hand)
        local tr=util.TraceHull({start=pose.pos,endpos=pose.pos+pose.ang:Forward()*scale*6,
            mins=Vector(-1,-1,-1),maxs=Vector(1,1,1),filter=A.physics.Filter(ply),mask=MASK_SOLID})
        local ent=tr.Entity
        if not tr.Hit or not A.physics.Allowed(ply,ent) or A.physics.pulling[ent] or A.physics.held[ent] or
            ent:GetClass()=="prop_ragdoll" or constraint.HasConstraints(ent) then return end
        local body=ent:GetPhysicsObject()
        if not IsValid(body) or not body:IsMotionEnabled() or body:GetMass()>150 or
            (tr.HitPos and (tr.HitPos-pose.pos):Length()>scale*6) then return end
        local nearest=A.physics.GloveClosest(ent,pose.pos,scale,hand)
        if nearest and nearest.distance>scale*0.16 and nearest.distance<=scale*6 and nearest.phys:GetMass()<=150 then return nearest end
    end
    function A.Pull(ply,state,h,pose,grip)
        local pull=h.pull
        if not pull then return end
        local ent,phys=pull.ent,pull.phys
        if not IsValid(ent) or not IsValid(phys) or not phys:IsMotionEnabled() or not A.physics.Allowed(ply,ent) then A.EndPull(h) return end
        local now=CurTime()
        local nearest=A.physics.Closest(ent,pose.pos,pull.bone)
        if grip and nearest and nearest.distance<=state.scale*0.16 and now>pull.began+0.12 then
            if grab(ply,h.name,ent,pull.bone) then pulse(h,0.65,4) end
            return
        end
        if not grip or now>pull.ends+0.2 or not A.physics.Visible(ply,phys:GetPos(),pose.pos,ent) then A.EndPull(h) return end
        local remaining=pull.ends-now
        if remaining>0.04 and remaining<0.28 then
            -- Re-solve the final ballistic segment for a moving hand; collisions never get disabled.
            local gravity=phys:IsGravityEnabled() and physenv.GetGravity() or Vector()
            phys:SetVelocity(Math.Limit(Math.Arc(phys:GetPos(),pose.pos,remaining,gravity),state.scale*16))
        end
    end
    -- V8 (ADR 0204): the holding hand's trigger freezes what it holds where it is; both hands let go of it.
    function A.Freeze(ply,state,h)
        local grip=h.grip
        if not grip or not A.physics.CanFreeze(ply,grip.ent,grip.phys) then return false end
        local otherName=h.name=="left" and "right" or "left"
        local other=state.interact[otherName]
        if other and other.grip and other.grip.phys==grip.phys then release(ply,otherName,false) end
        release(ply,h.name,false)
        if not A.physics.Freeze(ply,grip.ent,grip.phys) then return false end
        pulse(h,0.45,6)
        ctx.Emit("freeze",ply,h.name,grip.ent,grip.bone)
        return true
    end
    -- Grip near a frozen body and pull the trigger: it is freed into the hand.
    function A.Unfreeze(ply,state,h,touch)
        local frozen=A.physics.Nearest(ply,touch.pos,state.scale*0.16,true)
        if not frozen or not A.physics.Unfreeze(ply,frozen.ent,frozen.phys) then return false end
        if grab(ply,h.name,frozen.ent,frozen.bone) then pulse(h,0.45,7) end
        ctx.Emit("unfreeze",ply,h.name,frozen.ent,frozen.bone)
        return true
    end
    function A.Step(ply,state,h,pose,dt)
        local options,control=state.interact.options,state.interact.controls[h.name] or {}
        local owned=state.interact.owners and state.interact.owners[h.name]
        local gripping=not owned and control.grip~=false and bit.band(pose.buttons,1)~=0
        local trigger=not owned and control.trigger~=false and bit.band(pose.buttons,2)~=0
        local pressed,triggered=gripping and not h.wasGrip,trigger and not h.wasTrigger
        -- After a freeze or an unfreeze the same grip takes nothing else until it is let go.
        if not gripping then h.freezeLatch=nil end
        if triggered and gripping and h.grip and A.Freeze(ply,state,h) then h.freezeLatch=true end
        if h.grip and not gripping then release(ply,h.name,control.grip~=false) end
        if h.climb and (not gripping or not options.climb) then
            h.climb=nil
            if state.interact.climbReferences then state.interact.climbReferences[h.name]=nil end
            pulse(h,0.18,3)
        end
        if not options.gloves then A.EndPull(h) h.lock,h.target=nil,nil end
        local touch={pos=h.phys:GetPos(),ang=pose.ang,vel=pose.vel}
        local canUse=not owned and control.grip~=false and control.trigger~=false and not h.grip and not h.climb
        local used=A.Use(ply,h,touch,state.scale,pressed,triggered,gripping,canUse)
        if triggered and gripping and not used and not h.grip and not h.climb and not h.pull and not h.freezeLatch and
            A.Unfreeze(ply,state,h,touch) then
            h.freezeLatch=true
        end
        if gripping and not h.grip and not h.climb and not h.pull and not used and not h.freezeLatch then
            local near=A.physics.Nearest(ply,touch.pos,state.scale*0.16)
            if near then grab(ply,h.name,near.ent,near.bone)
            elseif pressed and options.climb then
                h.climb=A.Surface(ply,touch,state.scale)
                if h.climb then pulse(h,0.3,2) end
            end
            if pressed and not h.grip and not h.climb and options.gloves then
                local target=A.Target(ply,touch,state.scale,h.name)
                if target then h.lock={target=target,pos=pose.pos,at=CurTime()} end
            end
        end
        if not gripping then h.lock=nil end
        if h.lock and not h.grip and not h.pull then
            local lock=h.lock
            if CurTime()-lock.at>1.2 then h.lock=nil
            elseif Math.Flick(lock.pos,pose.pos,pose.vel,state.head.pos,state.scale) then
                local t=lock.target
                if IsValid(t.ent) and IsValid(t.phys) and not A.physics.pulling[t.ent] and not A.physics.held[t.ent] and A.physics.Allowed(ply,t.ent) then
                    local seconds=math.Clamp((t.phys:GetPos()-pose.pos):Length()/(state.scale*5),0.35,0.9)
                    local gravity=t.phys:IsGravityEnabled() and physenv.GetGravity() or Vector()
                    t.phys:SetVelocity(Math.Arc(t.phys:GetPos(),pose.pos,seconds,gravity)) t.phys:Wake()
                    h.pull={ent=t.ent,phys=t.phys,bone=t.bone,began=CurTime(),ends=CurTime()+seconds}
                    A.physics.BeginPull(ply,t.ent)
                    pulse(h,0.3,1)
                end
                h.lock=nil
            end
        end
        A.Pull(ply,state,h,pose,gripping)
        h.target=h.pull and {ent=h.pull.ent,point=IsValid(h.pull.phys) and h.pull.phys:GetPos() or pose.pos} or
            h.lock and h.lock.target or not h.grip and not h.climb and options.gloves and A.Target(ply,touch,state.scale,h.name) or nil
        if h.contact then
            local c=h.contact h.contact=nil
            if not h.contactAt or CurTime()>=h.contactAt then pulse(h,math.Clamp(c.speed/(state.scale*6),0.08,0.7),1) h.contactAt=CurTime()+0.12 end
            A.Hit(ply,state,h,c.ent,c.pos,c.velocity,c.speed)
        end
        if h.grip then
            local record=A.physics.held[h.grip.ent]
            if record and record.contact then local c=record.contact record.contact=nil A.Hit(ply,state,h,c.ent,c.pos,c.velocity,c.speed,"held") end
        elseif h.previous then
            local radius=state.scale*0.075
            local box=Vector(radius,radius,radius)
            local tr=util.TraceHull({start=h.previous,endpos=touch.pos+Math.Limit(pose.vel*dt,state.scale*0.25),
                mins=-box,maxs=box,filter=A.physics.Filter(ply),mask=MASK_SHOT})
            if tr.Hit then
                if not h.contactAt or CurTime()>=h.contactAt then pulse(h,math.Clamp(pose.vel:Length()/(state.scale*6),0.08,0.7),1) h.contactAt=CurTime()+0.12 end
                A.Hit(ply,state,h,tr.Entity,tr.HitPos,pose.vel,pose.vel:Length())
            end
        end
        h.previous,h.wasGrip,h.wasTrigger=touch.pos,bit.band(pose.buttons,1)~=0,bit.band(pose.buttons,2)~=0
    end
    function A.Move(ply,mv)
        local state=ctx.Players[ply]
        if not state or not state.interact then return end
        local d,anchors=state.interact,{}
        for _,hand in ipairs({"left","right"}) do if d[hand].climb then anchors[hand]=d[hand].climb end end
        d.climbReferences=d.climbReferences or {}
        local delta,count=Math.ClimbRelative(mv:GetOrigin(),state.head,state.hands,anchors,d.climbReferences,state.scale*0.3)
        if count>0 and ply:Alive() then
            local mins,maxs=ply:GetHull()
            if ply:Crouching() then mins,maxs=ply:GetHullDuck() end
            local tr=util.TraceHull({start=mv:GetOrigin(),endpos=mv:GetOrigin()+delta,mins=mins,maxs=maxs,
                filter=A.physics.Filter(ply),mask=MASK_PLAYERSOLID})
            local destination=tr.StartSolid and mv:GetOrigin() or tr.HitPos
            local velocity=(destination-mv:GetOrigin())/engine.TickInterval()
            mv:SetOrigin(destination) mv:SetVelocity(velocity)
            mv:SetForwardSpeed(0) mv:SetSideSpeed(0) mv:SetUpSpeed(0)
            d.launch=Math.Limit(velocity,state.scale*8) d.anchors=anchors
            return true
        elseif d.launch then
            mv:SetVelocity(d.launch) d.launch=nil d.anchors={}
            return true
        end
    end
    return A
end
return Actions
