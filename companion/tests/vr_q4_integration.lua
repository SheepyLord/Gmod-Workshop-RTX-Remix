-- Shared lifecycle and guided physical input, never production code.
local qStageDone,qStagePrevious={},nil
local qStages={{name="physics",first=0,last=16},{name="weapons",first=16,last=32},
    {name="reload",first=32,last=52},{name="tools",first=52,last=112}}
local function QStageState(first,last)
    if phase~="active" or not nlvr then return end
    local s=nlvr.TestState()
    if not s or s.time<first or s.time>=last then return end
    local out=table.Copy(s) out.time=out.time-first return out
end
local function QWindow(first,last) return QStageState(first,last)~=nil end
local QPeers=include("nlvr_q_tests/hook_addon.lua").New{emit=emit,probe_view=true,finish=true,features={hands=true,movement=true,menus=true}}
local qCycles,qSeenCore,qWasOn=0,nil,false
local qOldPortFrame,qPortFrame,qPreviousPort,qPreviousPortAt
hook.Add("Think","q4_integration_lifecycle",function()
    if NLVR and NLVR~=qSeenCore then
        qSeenCore=NLVR qCycles=qCycles+1 qWasOn=true
        local modules={}
        for _,entry in ipairs(NLVR.Registry.entries) do modules[entry.module.name]=entry.active and not entry.stopped end
        emit("Q4-integration-start",{cycle=qCycles,modules=modules,ulib=type(hook.GetULibTable)=="function"})
        if phase=="active" then
            for _,entry in ipairs(NLVR.Registry.entries) do if entry.module.name=="move" then
                entry.ctx.mover(-30,function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) cmd:SetMouseY(0) end)
            end end
        end
    elseif qWasOn and not NLVR then
        qWasOn=false qSeenCore=nil
        emit("Q4-integration-off",{cycle=qCycles,ulib=type(hook.GetULibTable)=="function"})
        if qOldPortFrame and nlvr.BeginFrame==qPortFrame then nlvr.BeginFrame=qOldPortFrame end
        qOldPortFrame,qPortFrame=nil,nil
    end
end)
hook.Add("PreRender","q4_integration_stage",function()
    if phase~="active" or not NLVR then return end
    local s=nlvr.TestState() if not s then return end
    if s.time>=112.2 and not qStageDone.hands then
        qStageDone.hands=true RunConsoleCommand("use","nlvr_hands")
    end
    for _,stage in ipairs(qStages) do
        if s.time>=stage.first and s.time<stage.last and qStagePrevious~=stage.name then
            qStagePrevious=stage.name
            local modules={}
            for _,entry in ipairs(NLVR.Registry.entries) do modules[entry.module.name]=entry.active and not entry.stopped end
            emit("Q4-integration-stage",{stage=stage.name,time=s.time,modules=modules})

        end
    end
    if s.time>=32 and s.time<52 and not qOldPortFrame then
        qOldPortFrame=nlvr.BeginFrame
        local previous=qOldPortFrame
        qPortFrame=function(...)
            local f,detail=previous(...)
            local state=QStageState(32,52)
            local active=NLVR and NLVR.Weapon and NLVR.Weapon.Active
            if f and state and active and active.class=="weapon_pistol" and IsValid(active.model) and state.time>=9.5 and state.time<=11 then
                local data=include("nlvr/modules/sh_reload.lua").Guns.weapon_pistol
                local pos,ang=LocalToWorld(data.port,data.axis,active.model:GetPos(),active.model:GetAngles())
                local tp,ta=NLVR.ToTracking(pos,ang)
                tp=tp+ta:Forward()*(.075*math.Clamp(10.5-state.time,0,1))
                local hand=NLVR.Input.offHand
                f[hand].pos,f[hand].ang=tp,ta
                QFrames.Encode(f[hand],hand)
                if qPreviousPort and state.time>qPreviousPortAt then f[hand].vel=(f[hand].pos-qPreviousPort)/(state.time-qPreviousPortAt) end
                qPreviousPort,qPreviousPortAt=f[hand].pos,state.time
            end
            return f,detail
        end
        nlvr.BeginFrame=qPortFrame
    end
end,HOOK_LOW)
