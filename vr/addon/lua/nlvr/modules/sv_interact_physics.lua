local Math = include("nlvr/modules/sv_interact_math.lua")
local Grab = include("nlvr/modules/sh_grab_math.lua")
local Physics = {}
function Physics.New(SV, ctx)
    local P = {proxies = {}, held = {}, pulling = {}, released = {}}
    local meshes = setmetatable({}, {__mode = "k"})
    local gloveCache = setmetatable({}, {__mode = "k"})
    local function rules(ent) if IsValid(ent) then ent:CollisionRulesChanged() end end
    function P.BodyTrace(ply, ent)
        -- TraceHull does not apply our player/hand ShouldCollide exclusions. Match only
        -- those owned-body exclusions, retaining world, NPCs and everybody else's props.
        local proxy, held, released = P.proxies[ent], P.held[ent], P.released[ent]
        return ent ~= ply and not (proxy and proxy.ply == ply) and not (held and held.ply == ply) and
            P.pulling[ent] ~= ply and not (released and released.ply == ply)
    end
    function P.Filter(ply, extra)
        return function(ent)
            return ent ~= ply and not P.proxies[ent] and not (P.held[ent] and P.held[ent].ply == ply) and
                not (P.released[ent] and P.released[ent].ply==ply) and P.pulling[ent] ~= ply and ent ~= extra
        end
    end
    function P.Allowed(ply, ent)
        if not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() or ent:IsNPC() or P.proxies[ent] then return false end
        if P.released[ent] and P.released[ent].ply==ply and P.released[ent].pickupBlocked then return false end
        if P.held[ent] and P.held[ent].ply ~= ply then return false end
        local pickup = GetConVar("sv_playerpickupallowed")
        if pickup and not pickup:GetBool() then return false end
        if ent.CPPICanPickup and ent:CPPICanPickup(ply) == false then return false end
        return hook.Run("AllowPlayerPickup", ply, ent) ~= false
    end
    -- frozen: true searches only bones whose motion is off (to free them), otherwise only moving ones.
    function P.Closest(ent, point, onlyBone, frozen)
        local best, result
        for bone = onlyBone or 0, onlyBone or math.min(ent:GetPhysicsObjectCount()-1, 127) do
            local phys = ent:GetPhysicsObjectNum(bone)
            if IsValid(phys) and phys:IsMotionEnabled() ~= (frozen == true) then
                local localPoint = WorldToLocal(point, Angle(), phys:GetPos(), phys:GetAngles())
                local data = meshes[phys]
                if not data then data = phys:GetMeshConvexes() or {} meshes[phys] = data end
                local nearest, distance
                for _, mesh in ipairs(data) do
                    for i = 1, #mesh-2, 3 do
                        local q = Math.Triangle(localPoint, mesh[i].pos, mesh[i+1].pos, mesh[i+2].pos)
                        local d = q:DistToSqr(localPoint)
                        if not distance or d < distance then nearest, distance = q, d end
                    end
                end
                if not nearest then
                    local world = ent:GetPhysicsObjectCount()>1 and phys:GetPos() or ent:NearestPoint(point)
                    nearest = WorldToLocal(world, Angle(), phys:GetPos(), phys:GetAngles())
                    distance = world:DistToSqr(point)
                end
                if not best or distance < best then
                    best = distance
                    result = {ent = ent, bone = bone, phys = phys, localPos = nearest,
                        point = LocalToWorld(nearest, Angle(), phys:GetPos(), phys:GetAngles()), distance = math.sqrt(distance)}
                end
            end
        end
        return result
    end
    function P.Visible(ply, from, to, ent)
        local trace = util.TraceLine({start = from, endpos = to, filter = P.Filter(ply,ent), mask = MASK_SOLID})
        return not trace.Hit or trace.Entity == ent or trace.Fraction > 0.98
    end
    function P.GloveClosest(ent, point, scale, hand)
        -- This is a targeting hint only. Grab revalidates the exact mesh at acquisition.
        -- A cached local contact follows the body; a moving aim refreshes at most at 10 Hz.
        local cache=gloveCache[ent] or {}
        local key=hand or "free"
        local cached=cache[key]
        if cached and CurTime()<cached.expires and IsValid(cached.result.phys) then
            local r=cached.result
            r.point=LocalToWorld(r.localPos,Angle(),r.phys:GetPos(),r.phys:GetAngles())
            r.distance=(r.point-point):Length()
            return r
        end
        local result=P.Closest(ent,point)
        if result then
            cache[key]={query=point,result=result,expires=CurTime()+.1}
            gloveCache[ent]=cache
        end
        return result
    end
    function P.Nearest(ply, position, reach, frozen)
        local box = Vector(reach,reach,reach)
        local best
        for _, ent in ipairs(ents.FindInBox(position-box, position+box)) do
            if P.Allowed(ply, ent) then
                local candidate = P.Closest(ent, position, nil, frozen)
                if candidate and candidate.distance <= reach and (not best or candidate.distance < best.distance) and
                    P.Visible(ply, position, candidate.point, ent) then best = candidate end
            end
        end
        return best
    end
    function P.Proxy(ply, h, pose, radius)
        P.RemoveProxy(h)
        local ent = ents.Create("base_anim")
        assert(IsValid(ent), "Could not create physical VR hand")
        h.proxy = ent P.proxies[ent] = {ply = ply, hand = h.name}
        ent:SetModel("models/props_junk/PopCan01a.mdl")
        -- Start on the eye side and sweep to the desired wrist before it can act.
        local scale=radius/.075
        local head={valid=true,pos=ply:EyePos(),ang=pose.ang}
        local goal=P.WorldTarget(ply,h,pose,scale,head)
        local box=Vector(radius,radius,radius)
        local trace=util.TraceHull({start=ply:EyePos(),endpos=goal,mins=-box,maxs=box,
            filter=P.Filter(ply),mask=MASK_SOLID})
        local safe=(trace.StartSolid or trace.AllSolid) and ply:EyePos() or trace.HitPos
        ent:SetPos(safe) ent:SetAngles(pose.ang)
        ent:SetNoDraw(true) ent:DrawShadow(false)
        ent:SetPreventTransmit(player.GetAll(), true)
        ent:Spawn()
        ent:PhysicsInitSphere(radius, "rubber") ent:SetSolid(SOLID_VPHYSICS)
        ent:SetCustomCollisionCheck(true) rules(ent)
        local phys = ent:GetPhysicsObject()
        assert(IsValid(phys), "Could not create VR hand physics")
        phys:SetMass(8) phys:EnableGravity(false) phys:EnableDrag(false) phys:Wake()
        ent:AddCallback("PhysicsCollide", function(_, data)
            local relative=(data.OurOldVelocity or Vector())-ply:GetVelocity()
            h.contact = {ent = data.HitEntity, pos = data.HitPos, velocity = relative, speed = relative:Length()}
        end)
        h.phys = phys
        h.radius=radius
    end
    function P.RemoveProxy(h)
        if h.proxy then P.proxies[h.proxy] = nil end
        if IsValid(h.proxy) then h.proxy:Remove() end
        h.proxy,h.phys,h.radius,h.contact,h.previous=nil,nil,nil,nil,nil
    end
    function P.WorldTarget(ply,h,pose,scale,head)
        if h.climb or not head or not head.valid then return pose.pos end
        -- The reviewed client hands cover 18 cm forward of the wrist. Keep that clearance
        -- in the authoritative stop too; the smaller sphere still pushes movable props.
        local radius=scale*0.035
        local low,high=Vector(-radius,-radius,-radius),Vector(radius,radius,radius)
        local extension=pose.ang:Forward()*(scale*0.145)
        for _,axis in ipairs({"x","y","z"}) do low[axis]=low[axis]+math.min(0,extension[axis]) high[axis]=high[axis]+math.max(0,extension[axis]) end
        local shoulder=head.pos+Angle(0,head.ang.y,0):Right()*((h.name=="left" and -0.18 or 0.18)*scale)-Vector(0,0,0.18*scale)
        local function sweep(a,b,mins,maxs)
            return util.TraceHull({start=a,endpos=b,mins=mins or Vector(-radius,-radius,-radius),
                maxs=maxs or Vector(radius,radius,radius),mask=MASK_SOLID_BRUSHONLY,filter=function(ent) return ent:IsWorld() end})
        end
        local first=sweep(head.pos,shoulder)
        if first.Hit then shoulder=first.HitPos+first.HitNormal*(scale*0.005) end
        local tr=sweep(shoulder,pose.pos,low,high)
        if not first.StartSolid and (tr.StartSolid or tr.AllSolid) then
            local back=shoulder-pose.ang:Forward()*(scale*0.25)
            local clear=sweep(back,back,low,high)
            if not clear.StartSolid and not clear.AllSolid and not clear.Hit then tr=sweep(back,pose.pos,low,high) end
        end
        if first.StartSolid or tr.StartSolid or tr.AllSolid then return head.pos end
        if tr.Hit then return tr.HitPos+tr.HitNormal*(scale*0.005),tr end
        return pose.pos
    end
    function P.Follow(ply, h, pose, scale, head)
        local phys, radius = h.phys, scale*0.075
        local target,worldContact=P.WorldTarget(ply,h,pose,scale,head)
        local start=phys:GetPos()
        local obstructed=(target-pose.pos):Length()>scale*0.001
        local box = Vector(radius,radius,radius)
        local filter = P.Filter(ply)
        local tr = util.TraceHull({start = start, endpos = target, mins = -box, maxs = box,
            filter = function(ent) return filter(ent) and not ent:IsNPC() end, mask = MASK_SOLID})
        if tr.Hit and not (h.climb and (tr.StartSolid or math.abs(tr.HitNormal.z) > 0.7)) then
            target=tr.HitPos obstructed=obstructed or (target-pose.pos):Length()>scale*0.001
        end
        local contact=worldContact or tr.Hit and not (h.climb and (tr.StartSolid or math.abs(tr.HitNormal.z)>0.7)) and tr
        if contact and (not h.contact or (h.contact.speed or 0)<pose.vel:Length()) then
            h.contact={ent=contact.Entity,pos=contact.HitPos,velocity=pose.vel,speed=pose.vel:Length()}
        end
        phys:EnableCollisions(not h.climb)
        local feed=pose.wvel or pose.vel or Vector()
        if obstructed then feed=Vector() end
        phys:SetVelocity(Math.Limit(feed+(target-start)*22, math.max(scale*12,feed:Length()+scale*4))) phys:Wake()
        h.followTarget, h.blocked = target, obstructed
    end
    function P.Track(ply, ent)
        P.released[ent]=nil
        local record = P.held[ent]
        if record then record.refs = record.refs+1 return end
        record = {ply = ply, refs = 1}
        P.held[ent] = record rules(ply) rules(ent)
        record.callback = ent:AddCallback("PhysicsCollide", function(_, data)
            local relative=(data.OurOldVelocity or Vector())-ply:GetVelocity()
            record.contact = {ent = data.HitEntity, pos = data.HitPos,
                velocity = relative, speed = relative:Length()}
        end)
    end
    function P.BeginPull(ply,ent) P.pulling[ent]=ply rules(ply) rules(ent) end
    function P.EndPull(ent)
        local ply=P.pulling[ent]
        P.pulling[ent]=nil rules(ply) rules(ent)
    end
    function P.Untrack(ent,grace)
        local record = P.held[ent]
        if not record then return end
        record.refs = record.refs-1
        if record.refs > 0 then return end
        if IsValid(ent) then ent:RemoveCallback("PhysicsCollide", record.callback) end
        P.held[ent] = nil
        if grace then P.released[ent]={ply=record.ply,untilTime=CurTime()+0.2} end
        rules(record.ply) rules(ent)
    end
    function P.RegisterReleased(ply,ent,seconds)
        if not IsValid(ent) then return false end
        P.released[ent]={ply=ply,pickupBlocked=true,untilTime=CurTime()+math.Clamp(tonumber(seconds) or .2,0,.25)}
        rules(ply) rules(ent)
        return true
    end
    function P.ClearReleased(ply)
        for ent,record in pairs(P.released) do
            if not ply or record.ply==ply then P.released[ent]=nil rules(record.ply) rules(ent) end
        end
    end
    function P.MaintainReleased()
        for ent,record in pairs(P.released) do
            if not IsValid(ent) or CurTime()>=record.untilTime then P.released[ent]=nil rules(record.ply) rules(ent) end
        end
    end
    -- What a hold follows (V8, ADR 0203): the tracked palm, stopped at world brushes where the proxy stops,
    -- never the proxy's lagging physics position and never the eye that WorldTarget falls back to in a wall.
    function P.Anchor(h, pose, scale)
        local stop = h and h.followTarget
        local anchor = {pos = pose.pos, ang = pose.ang, vel = pose.wvel or pose.vel or Vector(), spin = pose.angvel or Vector()}
        if stop and stop:DistToSqr(pose.pos) > (scale * 0.001) ^ 2 then
            if stop:DistToSqr(pose.pos) <= (scale * 0.5) ^ 2 then anchor.pos, anchor.vel = stop, Vector()
            elseif h.anchorPos then anchor.pos, anchor.vel = h.anchorPos, Vector() end
        end
        if h then h.anchorPos = anchor.pos end
        return anchor
    end
    -- Velocity control of the held body toward the hand's hold, with the hand's own velocity and spin fed
    -- forward: light bodies follow within two ticks, heavy ones at the hand's strength (Grab.Limits).
    function P.Drive(grip, other, h, otherHand, pose, scale, dt, otherPose)
        local phys = grip.phys
        local anchor = P.Anchor(h, pose, scale)
        local goalPos, goalAng, goalVel, goalSpin, origin
        if other and other.phys == phys and otherPose then
            local second = P.Anchor(otherHand, otherPose, scale)
            if not grip.two or grip.twoWith ~= other then
                -- Capture the pair where the body is now, so a second hand never makes it jump or roll.
                local mid, frame = Grab.PairFrame(anchor, second)
                grip.two, grip.twoWith = mid and Grab.Relation(phys:GetPos(), phys:GetAngles(), mid, frame) or nil, other
            end
            if grip.two then
                goalPos, goalAng = Grab.TwoHand(grip.two, anchor, second)
                goalVel, goalSpin = Grab.PairMotion(anchor, second)
                origin = (anchor.pos + second.pos) * 0.5
            end
        end
        if not goalPos then
            -- Callers from before V8 give the hand's pose in the body's frame (localPos, localAng) instead.
            local rel = grip.rel or Grab.Relation(Vector(), Angle(), grip.localPos or Vector(), grip.localAng or Angle())
            goalPos, goalAng = Grab.OneHand(rel, anchor)
            goalVel, goalSpin, origin = anchor.vel, anchor.spin, anchor.pos
        end
        local center, bodyAng = phys:GetMassCenter(), phys:GetAngles()
        local goalCenter = LocalToWorld(center, Angle(), goalPos, goalAng)
        local body = {pos = LocalToWorld(center, Angle(), phys:GetPos(), bodyAng), ang = bodyAng, vel = phys:GetVelocity(),
            spin = Grab.WorldSpin(phys:GetAngleVelocity(), bodyAng)}
        local goal = {pos = goalCenter, ang = goalAng, vel = goalVel + Grab.Cross(goalSpin, goalCenter - origin), spin = goalSpin}
        local inertia = phys.GetInertia and phys:GetInertia()
        local ent = grip.ent
        local linked = IsValid(ent) and ent:GetPhysicsObjectCount() > 1
        local limits = Grab.Limits(phys:GetMass(), inertia and math.max(inertia.x, inertia.y, inertia.z), scale, linked)
        local dv, dw, distance, angle = Grab.Step(body, goal, limits, dt)
        -- The step's gravity is paid in advance, so a hold never sags whatever the body weighs.
        if phys:IsGravityEnabled() then dv = dv - physenv.GetGravity() * dt end
        phys:SetVelocity(body.vel + dv)
        phys:AddAngleVelocity(Grab.LocalSpin(dw, bodyAng))
        phys:Wake()
        -- The client draws a body that follows its hold at the hand's current pose (hysteresis: 1x in, 2x out).
        local within = distance <= scale * Grab.TRACK_METRES and angle <= math.rad(Grab.TRACK_DEGREES)
        local beyond = distance > 2 * scale * Grab.TRACK_METRES or angle > 2 * math.rad(Grab.TRACK_DEGREES)
        grip.tracking = within or (grip.tracking == true and not beyond)
        grip.goal, grip.goalAng, grip.error, grip.angleError = goalPos, goalAng, distance, angle
        if other and other.phys == phys then
            other.tracking, other.goal, other.goalAng, other.error, other.angleError = grip.tracking, goalPos, goalAng, distance, angle
        end
    end
    -- The physgun's convention: freezing a held ragdoll stops only that bone; a prop stops whole.
    function P.CanFreeze(ply, ent, phys)
        if not IsValid(ent) or not IsValid(phys) or not phys:IsMotionEnabled() then return false end
        if ent.GetUnFreezable and ent:GetUnFreezable() then return false end
        return not (ent.CPPICanPhysgun and ent:CPPICanPhysgun(ply) == false)
    end
    function P.Freeze(ply, ent, phys)
        if not P.CanFreeze(ply, ent, phys) then return false end
        phys:EnableMotion(false)
        -- The physgun's "unfreeze all" (its reload) then frees hand-frozen bodies too.
        if ply.AddFrozenPhysicsObject then ply:AddFrozenPhysicsObject(ent, phys) end
        return true
    end
    function P.Unfreeze(ply, ent, phys)
        if not IsValid(ent) or not IsValid(phys) or phys:IsMotionEnabled() or not P.Allowed(ply, ent) then return false end
        if ent.CPPICanPhysgun and ent:CPPICanPhysgun(ply) == false then return false end
        if hook.Run("CanPlayerUnfreeze", ply, ent, phys) == false then return false end
        phys:EnableMotion(true) phys:Wake()
        return true
    end
    function P.Transport(ply,state,delta)
        local dropped={}
        -- Validate whole entities before moving either hand: no stretched weld/rope
        -- contraptions, and no held bounds jumping through a thin obstacle.
        for _,name in ipairs({"left","right"}) do
            local grip=state.interact[name].grip
            local ent=grip and grip.ent
            if IsValid(ent) and not dropped[ent] then
                if constraint.HasConstraints(ent) then dropped[ent]=true
                else
                    local origin=ent:GetPos()
                    local low,high=ent:WorldSpaceAABB()
                    local hit=util.TraceHull({start=origin,endpos=origin+delta,mins=low-origin,maxs=high-origin,
                        filter=P.Filter(ply,ent),mask=MASK_SOLID})
                    if hit.Hit or hit.StartSolid or hit.AllSolid then dropped[ent]=true end
                end
            end
        end
        local core=SV.core or SV
        for _,name in ipairs({"left","right"}) do
            local grip=state.interact[name].grip
            if grip and dropped[grip.ent] then core.Release(ply,name,false) end
        end
        local moved={}
        for _,name in ipairs({"left","right"}) do
            local h=state.interact[name]
            if IsValid(h.phys) then
                local position=h.phys:GetPos()+delta
                local radius=h.radius or state.scale*.075
                local box=Vector(radius,radius,radius)
                local eye=ply:EyePos()+delta
                local sweep=util.TraceHull({start=eye,endpos=position,mins=-box,maxs=box,
                    filter=P.Filter(ply),mask=MASK_SOLID})
                if sweep.Hit or sweep.StartSolid or sweep.AllSolid then
                    position=(sweep.StartSolid or sweep.AllSolid) and eye or sweep.HitPos
                    h.blocked=true
                end
                h.proxy:SetPos(position)
                h.phys:SetPos(position) h.phys:Wake()
            end
            if h.previous then h.previous=h.previous+delta end
            if h.followTarget then h.followTarget=h.followTarget+delta end
            h.contact,h.climb=nil,nil
            local ent=h.grip and h.grip.ent
            if IsValid(ent) and not moved[ent] then
                moved[ent]=true
                local positions={}
                for bone=0,ent:GetPhysicsObjectCount()-1 do
                    local body=ent:GetPhysicsObjectNum(bone)
                    if IsValid(body) then positions[body]=body:GetPos()+delta end
                end
                ent:SetPos(ent:GetPos()+delta)
                for body,pos in pairs(positions) do body:SetPos(pos) body:Wake() end
            end
            state.hands[name].pos=state.hands[name].pos+delta
        end
        state.head.pos=state.head.pos+delta
        state.interact.climbReferences={}
    end
    ctx.hook("ShouldCollide", function(a,b)
        local proxy = P.proxies[a] or P.proxies[b]
        if proxy then
            local other = P.proxies[a] and b or a
            if other == proxy.ply or P.proxies[other] or other:IsNPC() or
                (P.held[other] and P.held[other].ply == proxy.ply) then return false end
        end
        local held = P.held[a] or P.held[b]
        if held and ((P.held[a] and b or a) == held.ply) then return false end
        local pulling = P.pulling[a] or P.pulling[b]
        if pulling and ((P.pulling[a] and b or a) == pulling) then return false end
        local released=P.released[a] or P.released[b]
        if released then
            local other=P.released[a] and b or a
            if other==released.ply or P.proxies[other] and P.proxies[other].ply==released.ply then return false end
        end
    end)
    ctx.hook("PlayerInitialSpawn", function(ply)
        for ent in pairs(P.proxies) do if IsValid(ent) then ent:SetPreventTransmit(ply,true) end end
    end)
    return P
end
return Physics
