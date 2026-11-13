-- Scripted physical hand/head inputs; observations do not modify movement commands.
local q={case=0,ready=false,correction=0}
local install="q_medium_install"
hook.Add("PreRender",install,function()
    if phase~="active" or not NLVR or q.installed then return end
    q.installed=true
    local context
    for _,entry in ipairs(NLVR.Registry.entries) do if entry.module.name=="move" then context=entry.ctx end end
    assert(context,"movement module context missing")
    context.mover(-100,function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) cmd:SetMouseY(0) end)
    context.On("frame",function()
        if phase=="active" and LocalPlayer():GetNWInt("q_med_case",0)<0 then
            CONFIG.seconds=math.min(CONFIG.seconds,nlvr.TestState().time+1)
        end
    end)
    local begin,actions=nlvr.BeginFrame,nlvr.Actions
    local function current()
        local p=LocalPlayer() local i=p:GetNWInt("q_med_case",0)
        local c=CONFIG.medium_cases[i] local go=p:GetNWFloat("q_med_go",0)
        if i~=q.case then q.case,q.ready,q.correction,q.anchorZ=i,false,0,nil end
        return c,go,go>0 and CurTime()-go or 0
    end
    nlvr.BeginFrame=function(...)
        local f,detail=begin(...)
        local c,go,t=current()
        if f and c and nlvr.TestState().time>=4 then
            f.hmd.pos=Vector(0,0,c.medium=="ladder" and 1 or 1.6)
            f.hmd.ang=Angle(c.head_pitch,go>0 and 5*math.sin(t*2) or 0,0)
            -- Ground approach honors the ordinary off-hand setting. Once attached,
            -- deliberately turn that hand away to witness the ladder's head rule.
            local approach=c.medium=="ladder" and LocalPlayer():GetMoveType()~=MOVETYPE_LADDER
            f.left.pos,f.left.ang=Vector(.3,.25,c.medium=="ladder" and .7 or 1.2),Angle(0,approach and 0 or 180,0) QFrames.Encode(f.left,"left")
            local handZ=c.medium=="ladder" and .75 or 1.25
            f.right.pos,f.right.ang=Vector(.25,-.2,handZ),Angle(c.gun_pitch or 0,90,0) QFrames.Encode(f.right,"right")
        end
        return f,detail
    end
    nlvr.Actions=function(...)
        local c,go,t=current()
        if c and go>0 and t>=0 then
            local value=c.direction=="idle" and 0 or c.medium=="ladder" and c.direction=="down" and -.65 or .65
            if c.medium=="ladder" and t<.12 then value=.65 end -- normal forward auto-mount
            local turn=math.rad(c.stick_angle or 0)
            if c.medium=="ladder" and t<.12 then turn=0 end
            return {left_stick={active=true,x=value*math.sin(turn),y=value*math.cos(turn)},
                left_trigger_value={active=true,x=c.throttle or 0},right_stick={active=true,x=0,y=0}}
        end
        return actions(...)
    end
    hook.Add("CreateMove","q_medium_metadata",function(cmd)
        local c,go=current() if not c or not NLVR.Pose.head then return end
        local weapon=LocalPlayer():GetActiveWeapon()
        local class=IsValid(weapon) and weapon:GetClass() or ""
        local active=NLVR.Weapon and NLVR.Weapon.Active
        local modelPitch=active and IsValid(active.model) and (-active.model:GetForward()):Angle().p or 0
        if nlvr.TestState().time>=4 and not q.ready and go==0 and class==c.weapon and active and active.class==c.weapon and
            (not c.gun_pitch or IsValid(active.model) and math.abs(math.AngleDifference(modelPitch,c.gun_pitch))<.5) then
            q.ready=true RunConsoleCommand("nlvr_q_medium_ready",tostring(c.id))
        end
        local number=cmd:CommandNumber() if number<=0 then return end
        net.Start("q_medium_meta") net.WriteUInt(c.id,8) net.WriteUInt(number,32)
        net.WriteFloat(NLVR.Pose.head.ang.p) net.WriteFloat(NLVR.Pose.head.ang.y)
        net.WriteFloat(cmd:GetViewAngles().p) net.WriteFloat(cmd:GetViewAngles().y)
        net.WriteFloat(modelPitch)
        local off=NLVR.Pose[NLVR.Input.offHand]
        net.WriteFloat(off.ang.p) net.WriteFloat(off.ang.y)
        net.WriteFloat(NLVR.Input.off.stick.x) net.WriteFloat(NLVR.Input.off.stick.y)
        net.WriteString(class) net.WriteUInt(NLVR.Debug.weapons and NLVR.Debug.weapons.draws or 0,32)
        net.SendToServer()
    end,HOOK_MONITOR_LOW)
    context.cleanup(function()
        nlvr.BeginFrame,nlvr.Actions=begin,actions
        hook.Remove("CreateMove","q_medium_metadata") hook.Remove("PreRender",install)
    end)
end)
