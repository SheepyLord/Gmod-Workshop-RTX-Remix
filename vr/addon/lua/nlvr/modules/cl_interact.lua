local module={name="interact",order=50}
local context,states,markers,lastConfig,released,bodyTrace
local names={"left","right"}
local function heldEvent(hand,previous,current)
    local old=previous and previous.ent
    local changed=old~=current.ent or (previous and previous.bone~=current.bone)
    if changed and IsValid(old) then released[old]=RealTime()+0.2 end
    local shown=context.Hand[hand]
    if shown then
        shown.held=IsValid(current.ent) and {ent=current.ent,bone=current.bone} or nil
        shown.grip_curls=(IsValid(current.ent) or current.climbing) and {0.7,0.85,0.85,0.85,0.85} or nil
    end
    if IsValid(old) and changed then context.Emit("release",hand,old,previous.bone) end
    if IsValid(current.ent) and changed then context.Emit("grab",hand,current.ent,current.bone) end
end
local function markerPaint(_,w,h)
    surface.SetDrawColor(180,230,255,245)
    surface.DrawOutlinedRect(w*0.28,h*0.28,w*0.44,h*0.44,3)
    surface.DrawLine(w*0.5,h*0.15,w*0.5,h*0.3) surface.DrawLine(w*0.5,h*0.7,w*0.5,h*0.85)
    surface.DrawLine(w*0.15,h*0.5,w*0.3,h*0.5) surface.DrawLine(w*0.7,h*0.5,w*0.85,h*0.5)
end
function module.Start(ctx)
    context,states,markers,lastConfig=ctx,{},{},nil
    released=setmetatable({},{__mode="k"})
    local core=ctx.core or ctx
    bodyTrace=function(ply,ent)
        if ent==ply then return false end
        local now=RealTime()
        if released[ent] then if now<released[ent] then return false else released[ent]=nil end end
        for _,s in pairs(states) do
            if now-s.received<0.4 and (s.ent==ent and IsValid(s.ent) or s.pulling and s.target==ent and IsValid(s.target)) then return false end
        end
        return true
    end
    core.BodyTrace=bodyTrace
    ctx.Debug.interact={left={},right={}}
    ctx.Net.On(41,function()
        for _,hand in ipairs(names) do
            local s={valid=net.ReadBool()}
            if s.valid then s.pos,s.ang,s.offset=net.ReadVector(),net.ReadAngle(),net.ReadVector() end
            s.blocked,s.ent,s.bone=net.ReadBool(),net.ReadEntity(),net.ReadUInt(8)
            s.climbing,s.anchor=net.ReadBool(),net.ReadVector()
            s.target,s.targetPos=net.ReadEntity(),net.ReadVector()
            s.pulling,s.throwVelocity,s.spin=net.ReadBool(),net.ReadVector(),net.ReadVector()
            s.pulse,s.strength,s.kind=net.ReadUInt(16),net.ReadFloat(),net.ReadUInt(3)
            s.received=RealTime()
            local previous=states[hand]
            s.hapticOk,s.hapticError=previous and previous.hapticOk,previous and previous.hapticError
            states[hand]=s heldEvent(hand,previous,s)
            core.HandRevision=(core.HandRevision or 0)+1
            if s.pulse~=(previous and previous.pulse or 0) and ctx.Native.Haptic then
                s.hapticOk,s.hapticError=ctx.Native.Haptic(hand,s.kind==5 and 0.035 or 0.018,100+s.strength*100,s.strength)
            end
            local debug=ctx.Debug.interact[hand]
            debug.proxy_pos,debug.blocked,debug.held,debug.bone=s.pos,s.blocked,IsValid(s.ent) and s.ent:EntIndex() or 0,s.bone
            debug.throw_velocity,debug.throw_spin,debug.climbing,debug.anchor=s.throwVelocity,s.spin,s.climbing,s.anchor
            debug.gloves_target,debug.pulling=IsValid(s.target) and s.target:EntIndex() or 0,s.pulling
            debug.pulse,debug.pulse_kind,debug.haptic_ok,debug.haptic_error=s.pulse,s.kind,s.hapticOk,s.hapticError
        end
    end)
    ctx.resolver(200,function(hand,state)
        local s=states[hand]
        if not s or RealTime()-s.received>0.4 then
            if s and IsValid(s.ent) then heldEvent(hand,s,{}) s.ent=nil end
            state.held,state.grip_curls=nil,nil
            return
        end
        if s.valid then
            -- Predict the current tracked wrist, carrying only authoritative obstruction
            -- correction between snapshots. Never overwrite H's nearer world stop.
            local offset=s.offset or Vector()
            local predicted=state.target.pos+offset
            if offset:Length()>.001 and predicted:DistToSqr(state.target.pos)>state.shown.pos:DistToSqr(state.target.pos) then
                state.shown.pos=predicted
            end
            state.blocked=state.blocked or s.blocked
        end
        if IsValid(s.ent) then state.held={ent=s.ent,bone=s.bone} state.grip_curls={0.7,0.85,0.85,0.85,0.85}
        elseif s.climbing then state.held=nil state.grip_curls={0.7,0.85,0.85,0.85,0.85}
        else state.held,state.grip_curls=nil,nil end
    end)
    ctx.mover(95,function()
        if not next(states) then return end -- wait for the host's physics acknowledgement
        local values={ctx.Settings.gloves~=0,ctx.Settings.climb~=0,ctx.Settings.melee~=0}
        local signature=""
        for _,hand in ipairs(names) do
            for _,control in ipairs({"grip","trigger"}) do
                local owner=ctx.Input.Owner(hand,control)
                values[#values+1]=not owner or owner==ctx.name
            end
        end
        for _,v in ipairs(values) do signature=signature..(v and "1" or "0") end
        if signature~=lastConfig then ctx.Net.Send(40,function(w) for _,v in ipairs(values) do w.WriteBool(v) end end) lastConfig=signature end
    end)
    ctx.On("frame",function()
        for _,hand in ipairs(names) do
            local s=states[hand]
            local show=s and RealTime()-s.received<0.4 and IsValid(s.target) and ctx.Settings.gloves~=0
            local marker=markers[hand]
            if show then
                if not marker then
                    local key="gloves_"..hand local size=ctx.Overlay.Sizes[key]
                    marker=ctx.Overlay.New{key=key,name="Gravity glove target",width=size[1],height=size[2],metres=0.14,paint=markerPaint}
                    markers[hand]=marker
                end
                local head=ctx.Pose.head
                if head and head.valid then
                    local rotation=(s.targetPos-head.pos):Angle()
                    local pos,ang=ctx.ToTracking(s.targetPos,rotation)
                    marker:Place("world",pos,ang,0.14) marker:Show(true)
                end
            elseif marker and (marker.visible or marker.wanted) then marker:Show(false) end
        end
    end)
end
function module.Stop()
    if context then
        local core=context.core or context
        if core.BodyTrace==bodyTrace then core.BodyTrace=nil end
        for _,hand in ipairs(names) do
            local shown=context.Hand[hand]
            if shown then shown.held,shown.grip_curls=nil,nil end
            if markers and markers[hand] then markers[hand]:Destroy() end
        end
        context.Debug.interact=nil
    end
    context,states,markers,released,bodyTrace=nil,nil,nil,nil,nil
end
return module
