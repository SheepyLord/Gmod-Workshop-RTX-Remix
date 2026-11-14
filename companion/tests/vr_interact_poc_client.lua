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
            if phase and phase<=17 and (phase~=lastPhase or NLVR_P_ACK~=phase and sample.time-lastSend>0.2) then
                lastPhase,lastSend=phase,sample.time RunConsoleCommand("nlvr_p_phase",tostring(phase))
            end
            -- V8: where the client draws a held prop against where its physics and the hand are.
            if phase and phase>=14 and phase<=16 and NLVR.Debug.interact and sample.time-(NLVR_P_V8_AT or -1)>=0.25 then
                NLVR_P_V8_AT=sample.time
                local d=NLVR.Debug.interact.right
                local held=d and d.held and d.held>0 and Entity(d.held)
                local predicted=d and d.predicted
                local hand=NLVR.Hand.right and NLVR.Hand.right.shown
                print("NLVR_P "..util.TableToJSON({kind="v8-client",phase=phase,time=sample.time,
                    mode=predicted and predicted.mode,follow=predicted and predicted.follow,blending=predicted and predicted.blending,
                    drawn=predicted and predicted.drawn,physics=IsValid(held) and held:GetPos() or nil,
                    hand=hand and hand.pos,tracking=d and d.tracking,holding=d and d.holding}))
            end
            -- V8 run 3 (--fg-check): after the phases, Frame generation off for 4 s and back to the saved value; the
            -- records carry the page's status (its Motion Smoothing line), Auto's target and rate, and SteamVR's state.
            if CONFIG.fg_check and sample.time>=CONFIG.fg_check_at and NLVR.Debug.perf then
                local perf=NLVR.Debug.perf
                local function record(state)
                    local info=nlvr.Info and nlvr.Info() or {}
                    print("NLVR_P "..util.TableToJSON({kind="v8-frame-generation",state=state,time=sample.time,
                        setting=GetConVar("nl_vr_frame_generation"):GetString(),target=perf.target_rate,rate=perf.rate,
                        budget=perf.budget_ms,smoothing=perf.motion_smoothing,status=NativeLoaderVR.StatusText(),
                        supported=info.motion_smoothing_supported,enabled=info.motion_smoothing_enabled,
                        flags=type(info.timing)=="table" and info.timing.m_nReprojectionFlags or nil}))
                end
                if not NLVR_P_FG then
                    NLVR_P_FG={saved=GetConVar("nl_vr_frame_generation"):GetString(),at=sample.time}
                    record("on") RunConsoleCommand("nl_vr_frame_generation","0")
                elseif not NLVR_P_FG.off and sample.time-NLVR_P_FG.at>=4 then
                    NLVR_P_FG.off=true record("off") RunConsoleCommand("nl_vr_frame_generation",NLVR_P_FG.saved)
                elseif NLVR_P_FG.off and not NLVR_P_FG.back and sample.time-NLVR_P_FG.at>=8 then
                    NLVR_P_FG.back=true record("restored")
                end
            end
            if phase and phase<=17 and sample.time%8>5 and not captured[phase] then
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
