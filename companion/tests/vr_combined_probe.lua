-- One live session: all production modules, physics, near hands, locomotion and menus.
local ID, lastSlot, lastSend, captured, installed = "nlvr_combined_probe", -1, -1, {}, false
local transitions = {}
local qFingers=QFingerWitness.New()
local seen, ended, offAt = false, false, nil
local P_END,H_END,L_END,SLOT=CONFIG.combined.physical_end,CONFIG.combined.hands_end,
    CONFIG.combined.move_end,CONFIG.combined.physical_slot
NLVR_P_ACK = -1
hook.Add("PreRender", ID, function()
    if not NLVR then
        if seen and not ended then
            offAt=offAt or RealTime()
            if RealTime()-offAt>1 then
                ended=true RunConsoleCommand("nlvr_p_done") hook.Remove("PreRender",ID) NLVR_P_ACK=nil
            end
        end
        return
    end
    local sample = nlvr.TestState()
    if not sample then return end
    local t = sample.time
    if not installed then
        installed, seen = true, true
        local ctx
        for _, entry in ipairs(NLVR.Registry.entries) do if entry.module.name == "move" then ctx = entry.ctx end end
        -- Recorded holds start at the requested fixture yaw, even if desktop input
        -- changed the engine's view while the map/VR module was starting.
        NLVR.Space.Turn(-(NLVR.Space.yaw or 0))
        ctx.mover(-30, function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) cmd:SetMouseY(0) end)
        ctx.cleanup(function() if ClientsideModel==qModel then ClientsideModel=qOriginalModel end end)
        local previous=NLVR.HandDrawObserver
        local function observe(side,hand,matrices,device)
            if previous then previous(side,hand,matrices,device) end
            local time=nlvr.TestState().time
            if time>=P_END+6.2 and time<P_END+6.6 then qFingers.Observe(side,hand.model,time,FrameNumber(),true)
            elseif time>=P_END+6.85 and time<H_END then qFingers.Observe(side,hand.model,time,FrameNumber(),false) end
        end
        NLVR.HandDrawObserver=observe
        ctx.cleanup(function() if NLVR and NLVR.HandDrawObserver==observe then NLVR.HandDrawObserver=previous end end)
    end
    if t < P_END then
        local slot = math.floor(t/SLOT)
        if slot ~= lastSlot or NLVR_P_ACK ~= slot and t-lastSend > .2 then
            lastSlot,lastSend=slot,t RunConsoleCommand("nlvr_p_phase", tostring(slot))
        end
        if t%SLOT > SLOT*.65 and not captured[slot] then
            captured[slot]=true capture("interact-"..slot)
            if slot==4 then emit("Q-held-move",{position=LocalPlayer():GetPos(),move=NLVR.Debug.move,hand=NLVR.Debug.interact.right}) end
        end
        if slot==9 and t%SLOT>0.4 and t%SLOT<0.8 and not captured.gloves then
            captured.gloves=true capture("gloves")
        end
    elseif t < H_END then
        if not transitions.hands then
            transitions.hands=true RunConsoleCommand("nlvr_q_stage", "hands") NativeLoaderVR.Recenter()
        end
        local n = math.floor((t-P_END)/2)
        local label = ({"near-020","near-030","near-050"})[n+1]
        if label and (t-P_END)%2 > 1.1 and not captured[label] then
            captured[label]=true
            local data={label=label}
            for _,side in ipairs({"left","right"}) do
                local state,debug=NLVR.Hand[side],NLVR.Debug.hands[side]
                data[side]={metres=(state.target.pos-NLVR.Pose.head.pos):Length()/NLVR.Space.scale,
                    shown_metres=(state.shown.pos-NLVR.Pose.head.pos):Length()/NLVR.Space.scale,
                    valid=state.shown.valid,blocked=state.blocked,model=debug.model,
                    finger_bones=debug.finger_bones,draws=debug.draws,curls=debug.curls}
            end
            emit("Q-hands",data) capture(label)
        end
        if t>=P_END+7.2 and not captured.curls then
            captured.curls=true local data={}
            local liveModels={}
            for _,model in ipairs(qHandModels) do if IsValid(model) then liveModels[#liveModels+1]=model end end
            for i,side in ipairs({"left","right"}) do
                local debug=NLVR.Debug.hands[side]
                local entry={curls=debug.curls,splay=debug.splay,grip=debug.grip,bends={},rendered=qFingers.Snapshot(side),skeletal_source=debug.skeletal_source}
                local model=liveModels[i]
                if IsValid(model) then
                    for finger=0,4 do
                        local id=model:LookupBone("ValveBiped.Bip01_"..(side=="left" and "L" or "R").."_Finger"..finger)
                        local angle=id and model:GetManipulateBoneAngles(id)
                        entry.bends[#entry.bends+1]=angle and (finger==0 and angle.p or angle.y) or -999
                    end
                end
                data[side]=entry
            end
            emit("Q-tracked-curls",data) capture("tracked-curls")
        end
    elseif t < L_END then
        if not transitions.move then
            transitions.move=true RunConsoleCommand("nlvr_L_stage", "reset") NativeLoaderVR.Recenter()
        end
    elseif not transitions.ui then
        transitions.ui=true RunConsoleCommand("nlvr_q_stage", "ui") NativeLoaderVR.Recenter()
    end
end)
