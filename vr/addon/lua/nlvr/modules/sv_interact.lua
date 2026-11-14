local module = {name = "interact", order = 20}
local Math = include("nlvr/modules/sv_interact_math.lua")
local Grab = include("nlvr/modules/sh_grab_math.lua")
local Protocol = include("nlvr/sh_protocol.lua")
local context, physics, action, live
local hands = {"left", "right"}
-- Pulse kinds: 1 touch, 2 grab, 3 release, 4 catch, 5 hit, 6 freeze, 7 unfreeze (V8).
local pulsePriority={[1]=1,[2]=3,[3]=2,[4]=4,[5]=5,[6]=6,[7]=7}
local function opposite(hand) return hand == "left" and "right" or "left" end
local function floats(w, v)
    if v.p then w.WriteFloat(v.p) w.WriteFloat(v.y) w.WriteFloat(v.r)
    else w.WriteFloat(v.x) w.WriteFloat(v.y) w.WriteFloat(v.z) end
end
local function pulse(h, strength, kind)
    kind=kind or 1
    if h.pulseTick==engine.TickCount() then
        h.strength=math.max(h.strength,math.Clamp(strength,0,1))
        if pulsePriority[kind]>pulsePriority[h.pulseKind] then h.pulseKind=kind end
    else
        h.pulseTick=engine.TickCount()
        h.pulse=((h.pulse or 0)+1)%65536
        h.strength,h.pulseKind=math.Clamp(strength,0,1),kind
    end
end
local function stateFor(ply, hand)
    if hand~="left" and hand~="right" then return end
    local state = live and context.Players[ply]
    return state, state and state.interact and state.interact[hand]
end
local function release(ply, hand, throw)
    local state, h = stateFor(ply, hand)
    if not h or not h.grip then return false end
    local grip = h.grip
    h.grip = nil h.contact=nil physics.Untrack(grip.ent,true)
    local otherHand = state.interact[opposite(hand)]
    local other = otherHand.grip
    if other and other.phys == grip.phys and IsValid(other.phys) then
        -- The hand that stays holds the body where it is now: no jump back to its own old hold.
        local anchor = physics.Anchor(otherHand, state.hands[opposite(hand)], state.scale)
        other.rel = Grab.Relation(other.phys:GetPos(), other.phys:GetAngles(), anchor.pos, anchor.ang)
        other.two, other.twoWith, grip.two, grip.twoWith = nil, nil, nil, nil
    end
    if throw and IsValid(grip.ent) and IsValid(grip.phys) and (not other or other.phys ~= grip.phys) then
        local velocity, spin = Math.Throw(state.history[hand], CurTime(), state.scale)
        local center = LocalToWorld(grip.phys:GetMassCenter(),Angle(),grip.phys:GetPos(),grip.phys:GetAngles())
        local wrist=physics.Anchor(h, state.hands[hand], state.scale).pos
        local centerVelocity = velocity+Math.Cross(spin, center-wrist)
        grip.phys:SetVelocity(centerVelocity)
        local localSpin = WorldToLocal(spin, Angle(), Vector(), grip.phys:GetAngles())*(180/math.pi)
        grip.phys:AddAngleVelocity(localSpin-grip.phys:GetAngleVelocity()) grip.phys:Wake()
        h.lastThrow, h.lastSpin, h.lastHandVelocity = centerVelocity, spin, velocity
    end
    pulse(h,0.18,3)
    context.Emit("release", ply, hand, grip.ent, grip.bone, throw == true)
    return true
end
local function grab(ply, hand, ent, bone, localPos, localAng)
    local state, h = stateFor(ply,hand)
    if not h or state.interact.owners[hand] or not ply:Alive() or not state.hands[hand].valid or not physics.Allowed(ply,ent) then return false end
    bone = bone or 0
    if type(bone) ~= "number" or bone%1 ~= 0 or bone < 0 or bone >= math.min(ent:GetPhysicsObjectCount(),128) then return false end
    local pose = state.hands[hand]
    local anchor = physics.Anchor(h, pose, state.scale)
    local position = anchor.pos
    if position:DistToSqr(ply:EyePos())>context.Reach(ply)^2 then return false end
    local nearest = physics.Closest(ent, position, bone)
    if not nearest or nearest.distance > state.scale*0.16 or not physics.Visible(ply,position,nearest.point,ent) then return false end
    local phys = nearest.phys
    if localPos then
        if not isvector(localPos) or not Protocol.Finite(localPos.x) or not Protocol.Finite(localPos.y) or not Protocol.Finite(localPos.z) then return false end
        local point = LocalToWorld(localPos,Angle(),phys:GetPos(),phys:GetAngles())
        if point:DistToSqr(position) > (state.scale*0.16)^2 then return false end
    else localPos = nearest.localPos end
    local bodyPos, bodyAng = phys:GetPos(), phys:GetAngles()
    local goalAng = bodyAng
    if localAng then
        -- An API caller's hand orientation in the bone's frame: the body turns to meet the hand.
        if not isangle(localAng) or not Protocol.Finite(localAng.p) or not Protocol.Finite(localAng.y) or not Protocol.Finite(localAng.r) then return false end
        local _, inverse = WorldToLocal(Vector(), Angle(), Vector(), localAng)
        _, goalAng = LocalToWorld(Vector(), inverse, Vector(), anchor.ang)
    end
    release(ply,hand,false)
    action.EndPull(h)
    h.climb, h.pull, h.lock, h.target = nil,nil,nil,nil
    -- Hands on (V8): the touched point comes to rest against the palm, and the body keeps that pose in the
    -- hand's frame, so turning the wrist turns it about the hand.
    local point = LocalToWorld(localPos,Angle(),bodyPos,bodyAng)
    local rest = Grab.Snap(point, position, state.scale*Grab.PALM)
    local goalPos = rest - LocalToWorld(localPos,Angle(),Vector(),goalAng)
    h.grip = {ent=ent,bone=bone,phys=phys,localPos=Vector(localPos.x,localPos.y,localPos.z),
        rel=Grab.Relation(goalPos,goalAng,position,anchor.ang),single=ent:GetPhysicsObjectCount()==1}
    local partner = state.interact[opposite(hand)].grip
    if partner and partner.phys == phys then partner.two, partner.twoWith = nil, nil end -- re-form the pair where it is
    physics.Track(ply,ent) pulse(h,0.35,2)
    context.Emit("grab",ply,hand,ent,bone)
    return true
end
local function clear(ply, remove)
    local state = live and context.Players[ply]
    if not state or not state.interact then return end
    action.RestoreItems(ply)
    for _, hand in ipairs(hands) do
        local h = state.interact[hand]
        release(ply,hand,false)
        action.EndPull(h)
        h.climb,h.pull,h.lock,h.target,h.previous,h.wasGrip,h.wasTrigger = nil,nil,nil,nil,nil,false,false
        h.projectileReleaseAt=nil
        if remove then physics.RemoveProxy(h) end
    end
    state.interact.anchors, state.interact.launch, state.interact.owners = {}, nil, {}
    physics.ClearReleased(ply)
end
local function start(ply,state)
    state.interact = {left={name="left"},right={name="right"},anchors={},owners={},options={gloves=false,climb=false,melee=false},
        controls={left={grip=false,trigger=false},right={grip=false,trigger=false}}}
    state.interact.custom = ply:GetCustomCollisionCheck()
    ply:SetCustomCollisionCheck(true) ply:CollisionRulesChanged()
end
local function stop(ply)
    local state = context.Players[ply]
    action.RestoreItems(ply)
    clear(ply,true)
    if state and state.interact and IsValid(ply) then
        if ply:GetCustomCollisionCheck() == true then ply:SetCustomCollisionCheck(state.interact.custom) end
        ply:CollisionRulesChanged()
    end
end
local function send(ply,state)
    local data = state.interact
    context.Net.Send(ply,41,function(w)
        for _, hand in ipairs(hands) do
            local h = data[hand]
            w.WriteBool(IsValid(h.phys))
            if IsValid(h.phys) then
                w.WriteVector(h.phys:GetPos()) w.WriteAngle(h.phys:GetAngles())
                w.WriteVector((h.followTarget or state.hands[hand].pos)-state.hands[hand].pos)
            end
            w.WriteBool(h.blocked == true) w.WriteEntity(h.grip and h.grip.ent) w.WriteUInt(h.grip and h.grip.bone or 0,8)
            w.WriteBool(h.climb ~= nil) w.WriteVector(h.climb or Vector())
            w.WriteEntity(h.target and h.target.ent) w.WriteVector(h.target and h.target.point or Vector())
            w.WriteBool(h.pull ~= nil) w.WriteVector(h.lastThrow or Vector()) w.WriteVector(h.lastSpin or Vector())
            w.WriteUInt(h.pulse or 0,16) w.WriteFloat(h.strength or 0) w.WriteUInt(h.pulseKind or 0,3)
            -- V8: the hold's pose in the hand's frame (floats, not quantised), whether the body follows it
            -- now, and whether the entity is one body: the client draws such a body at the hand's pose.
            local grip = h.grip
            local holding = grip ~= nil and IsValid(grip.ent) and grip.rel ~= nil
            w.WriteBool(holding)
            if holding then
                floats(w, grip.rel.pos) floats(w, grip.rel.ang)
                w.WriteBool(grip.tracking == true) w.WriteBool(grip.single == true)
            end
        end
        local left, right = data.left.grip, data.right.grip
        local pair = left and right and left.phys == right.phys and left.two or nil
        w.WriteBool(pair ~= nil)
        if pair then floats(w, pair.pos) floats(w, pair.ang) end
    end)
end
function module.Start(ctx)
    context, live = ctx, true
    action = include("nlvr/modules/sv_interact_actions.lua").New(ctx, pulse, grab, release)
    physics = include("nlvr/modules/sv_interact_physics.lua").New(ctx,ctx)
    action.physics = physics
    local SV = ctx.core
    SV.Grab,SV.Release = grab,release
    local function claimHand(ply,hand,owner,claimed)
        local state,h=stateFor(ply,hand)
        if not h or type(owner)~="string" or owner=="" then return false end
        local current=state.interact.owners[hand]
        if current and current~=owner then return false end
        state.interact.owners[hand]=claimed and owner or nil
        if claimed then
            release(ply,hand,false) action.EndPull(h)
            h.climb,h.lock,h.target,h.contact=nil,nil,nil,nil
        end
        return true
    end
    local function registerReleased(ply,ent,seconds)
        if not stateFor(ply,"left") or not IsValid(ent) then return false end
        return physics.RegisterReleased(ply,ent,seconds)
    end
    SV.ClaimHand,SV.RegisterReleased=claimHand,registerReleased
    local function projectileFeedback(ply,hand)
        local state,h=stateFor(ply,hand)
        if not h or not ply:Alive() or not state.hands[hand].valid then return false end
        pulse(h,.35,2)
        h.projectileReleaseAt=CurTime()+.08 -- separate network-visible release pulse
        return true
    end
    SV.ProjectileFeedback=projectileFeedback
    ctx.cleanup(function()
        if SV.ClaimHand==claimHand then SV.ClaimHand=nil end
        if SV.RegisterReleased==registerReleased then SV.RegisterReleased=nil end
        if SV.ProjectileFeedback==projectileFeedback then SV.ProjectileFeedback=nil end
    end)
    local bodyTrace = function(ply, ent) return physics.BodyTrace(ply, ent) end
    SV.BodyTrace = bodyTrace
    ctx.cleanup(function() if SV.BodyTrace == bodyTrace then SV.BodyTrace = nil end end)
    SV.Holding = function(ply,hand) local _,h=stateFor(ply,hand) if h and h.grip and IsValid(h.grip.ent) then return h.grip.ent,h.grip.bone end end
    ctx.cleanup(function() SV.Grab,SV.Release,SV.Holding=nil,nil,nil end)
    ctx.On("OnStart",start) ctx.On("OnStop",stop)
    ctx.On("OnDeath",function(ply) clear(ply,true) end)
    ctx.On("teleport_delta",function(ply,delta)
        local state=ctx.Players[ply]
        if state and state.interact then physics.Transport(ply,state,delta) end
    end)
    ctx.On("OnSpawn",function(ply)
        clear(ply,true)
        if IsValid(ply) then ply:SetCustomCollisionCheck(true) ply:CollisionRulesChanged() end
    end)
    ctx.Net.On(40,function(ply)
        local d=ctx.Players[ply].interact
        d.options={gloves=net.ReadBool(),climb=net.ReadBool(),melee=net.ReadBool()}
        for _,hand in ipairs(hands) do d.controls[hand]={grip=net.ReadBool(),trigger=net.ReadBool()} end
    end)
    ctx.mover(5,function(ply,mv) return action.Move(ply,mv) end)
    ctx.hook("Tick",function()
        local dt=engine.TickInterval()
        physics.MaintainReleased()
        action.UpdateItems()
        for ply,state in pairs(ctx.Players) do
            local d=state.interact
            if not d then start(ply,state) d=state.interact end
            for _,hand in ipairs(hands) do
                local h,pose=d[hand],state.hands[hand]
                if h.projectileReleaseAt and CurTime()>=h.projectileReleaseAt then
                    h.projectileReleaseAt=nil
                    if ply:Alive() and pose.valid then pulse(h,.18,3) end
                end
                local reach=ctx.Reach(ply)
                if IsValid(h.phys) and h.phys:GetPos():DistToSqr(ply:EyePos())>reach^2 then
                    release(ply,hand,false) action.EndPull(h) physics.RemoveProxy(h) h.climb,h.lock,h.target=nil,nil,nil
                end
                if not ply:Alive() or not pose.valid or pose.pos:DistToSqr(ply:EyePos())>reach^2 or
                    not state.lastSync or CurTime()-state.lastSync>0.3 or ply:InVehicle() then
                    release(ply,hand,false) action.EndPull(h) physics.RemoveProxy(h) h.climb,h.pull,h.lock,h.target,h.wasGrip,h.wasTrigger=nil,nil,nil,nil,false,false
                else
                    if not IsValid(h.phys) or h.radius~=state.scale*0.075 then
                        local spawnPose={pos=IsValid(h.phys) and h.phys:GetPos() or pose.pos,ang=pose.ang}
                        physics.Proxy(ply,h,spawnPose,state.scale*0.075)
                    end
                    physics.Follow(ply,h,pose,state.scale,state.head)
                    action.Step(ply,state,h,pose,dt)
                end
            end
            for _,hand in ipairs(hands) do
                local h,other=d[hand],d[opposite(hand)]
                if h.grip then
                    if not IsValid(h.grip.ent) or not IsValid(h.grip.phys) or not h.grip.phys:IsMotionEnabled() then release(ply,hand,false)
                    elseif not other.grip or other.grip.phys ~= h.grip.phys or hand=="left" then
                        physics.Drive(h.grip,other.grip,h,other,state.hands[hand],state.scale,dt,state.hands[opposite(hand)])
                    end
                end
            end
            send(ply,state)
        end
    end)
end
function module.Stop()
    if live then for ply in pairs(context.Players) do stop(ply) end end
    live=false
end
return module
