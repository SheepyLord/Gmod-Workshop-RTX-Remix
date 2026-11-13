-- Real Source noclip witness with an independently aimed gun, both dominant hands.
local qFlight={rows={},cases={},cycles=0,off=0}
local qCore,qContext,qCase,qAt,qStart,qPeer
local qSaved={}
for _,name in ipairs({"dominant","height","seated","vignette"}) do
    qSaved[name]=GetConVar("nl_vr_"..name):GetString()
end
local QPeers=include("nlvr_q_tests/hook_addon.lua").New{emit=emit,probe_view=true,finish=true,features={hands=true,movement=true}}
hook.Add("Think","q4_flight_lifecycle",function()
    if NLVR and NLVR~=qCore then
        qCore=NLVR qFlight.cycles=qFlight.cycles+1
        if phase~="active" then return end
        for name in pairs(qSaved) do RunConsoleCommand("nl_vr_"..name,"0") end
        for _,entry in ipairs(NLVR.Registry.entries) do if entry.module.name=="move" then qContext=entry.ctx end end
        NLVR.Space.Turn(-(NLVR.Space.yaw or 0))
        qContext.mover(-30,function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) cmd:SetMouseY(0) end)
    elseif qCore and not NLVR then
        qCore=nil qFlight.off=qFlight.off+1
        for name,value in pairs(qSaved) do RunConsoleCommand("nl_vr_"..name,value) end
    end
end)
hook.Add("PreRender","q4_flight_case",function()
    if phase~="active" or not NLVR then return end
    local state=nlvr.TestState() if not state or state.time>=20 then return end
    local index=math.floor(state.time/5)
    if qCase~=index then
        qCase=index qAt=nil qStart=nil
        RunConsoleCommand("nl_vr_dominant",index>=2 and "1" or "0")
        RunConsoleCommand("nlvr_q4_flight",tostring(index))
    end
    local localTime=state.time%5
    if localTime>=1.3 and not qStart then qStart=LocalPlayer():GetPos() end
    if localTime>=3.8 and qStart and not qFlight.cases[index] then
        local delta=LocalPlayer():GetPos()-qStart
        qFlight.cases[index]=true
        emit("Q4-flight-travel",{case=index,hand=index>=2 and "left" or "right",gun_pitch=index%2==0 and 45 or -45,
            units={delta.x,delta.y,delta.z},metres=delta:Length()/NLVR.Space.scale})
        capture("q4-flight-"..index)
    end
end)
hook.Add("CreateMove","q4_flight_observe",function(cmd)
    if phase~="active" or not NLVR or not qCase then return end
    local state=nlvr.TestState() local t=state and state.time%5
    if not t or t<1.5 or t>3.7 or not NLVR.Weapon.Active or NLVR.Weapon.Active.class~="weapon_pistol" then return end
    local angle=cmd:GetViewAngles()
    local actual=angle:Forward()*cmd:GetForwardMove()+angle:Right()*cmd:GetSideMove()+angle:Up()*cmd:GetUpMove()
    if actual:Length()<1 then return end
    local wanted=NLVR.Pose.off.ang:Forward()
    if not qAt or RealTime()-qAt>.2 then
        qAt=RealTime()
        emit("Q4-flight-command",{case=qCase,hand=NLVR.Input.mainHand,gun_pitch=angle.p,
            cosine=actual:GetNormalized():Dot(wanted),speed=actual:Length(),up=actual.z})
    end
end,HOOK_LOW)
