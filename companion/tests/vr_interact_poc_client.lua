-- Appended after the standard VR probe; its captures/teardown/compositor receipts stay intact.
local lastPhase,seen,ended,offAt=-1,false,false,nil
local captured={}
local lastSend=-1
NLVR_P_ACK=-1
hook.Add("PreRender","nlvr_p_probe",function()
    if NLVR and nlvr and nlvr.TestState then
        local sample=nlvr.TestState()
        if sample then
            seen=true
            local slot=math.floor(sample.time/8)
            local phase=CONFIG.interact_phases and CONFIG.interact_phases[slot+1] or not CONFIG.interact_phases and slot or nil
            if phase and phase<=13 and (phase~=lastPhase or NLVR_P_ACK~=phase and sample.time-lastSend>0.2) then
                lastPhase,lastSend=phase,sample.time RunConsoleCommand("nlvr_p_phase",tostring(phase))
            end
            if phase and phase<=13 and sample.time%8>5 and not captured[phase] then
                local label="interact-"..phase
                local request=nlvr.Capture(label,15)
                if request then
                    captured[phase]=true
                    print("NLVR_P "..util.TableToJSON({kind="eye-capture",phase=phase,label=label,request=request,time=sample.time}))
                end
            end
            if phase==9 and sample.time%8>1 and sample.time%8<2 and NLVR.Debug.interact then
                local marker=NLVR.Overlay.Objects.gloves_right
                if marker and not marker.pCaptured then marker.pCaptured=true nlvr.Capture("gloves",15) end
            end
        end
    elseif seen and not ended then
        offAt=offAt or RealTime()
        if RealTime()-offAt>1 then ended=true NLVR_P_ACK=nil RunConsoleCommand("nlvr_p_done") hook.Remove("PreRender","nlvr_p_probe") end
    end
end)
