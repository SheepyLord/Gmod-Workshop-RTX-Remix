-- Private Q review phases, appended to the combined fixture; never packaged.
local RSTART=129
local qReview={seen={},objects={},saved={},painters={},stats={walk={n=0,max_error=0,ghosts=0},sprint={n=0,max_error=0,ghosts=0}}}
local qOldBegin,qOldActions,qOldRefresh,qOldTrace,qCore,qCtx
local qLastStage,qSpawn, qOff
local qOverlayOriginals,qLive,qRequestFrame,qRequests={}, {}, nil, {}
local function qOnce(key,fn)
    if qReview.seen[key] then return end qReview.seen[key]=true fn()
end
local function qTime() local s=nlvr.TestState() return s and s.time-RSTART or -1 end
local function qStage(name)
    if qLastStage==name then return end qLastStage=name RunConsoleCommand("nlvr_review_stage",name)
end
local function qOverlays(show)
    local c=qCore local previous=c.Registry.current
    -- Registry.current is an entry, not its context.
    for _,entry in ipairs(c.Registry.entries) do if entry.ctx==qCtx then c.Registry.current=entry end end
    if show then
        local index=0
        for key,size in pairs(c.Overlay.Sizes) do
            local painter=qReview.painters[key]
            if not painter then
                painter=function(_,w,h)
                    surface.SetDrawColor(32,80,120,230) surface.DrawRect(0,0,w,h)
                    draw.SimpleText(key,"DermaDefault",w/2,h/2,color_white,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                end
                qReview.painters[key]=painter
            end
            local o=c.Overlay.Objects[key]
            if not o then
                o=c.Overlay.New{key=key,width=size[1],height=size[2],paint=painter}
                qReview.objects[key]=o
                if key=="flat" then local ok,detail=o:Window(true) assert(ok~=false and (ok or detail=="pending")) end
            elseif not qReview.saved[key] then
                qReview.saved[key]={o=o,visible=o.wanted,device=o.device,pos=o.pos,ang=o.ang,metres=o.metres,paint=o.paint,alpha=o.alpha}
            end
            o.paint=painter o:Invalidate() o:Alpha(1)
            o:Place("head",Vector(.75,(index%5-2)*.19,(2-math.floor(index/5))*.18),Angle(),.16) o:Show(true)
            index=index+1
        end
    else
        qReview.hidden={}
        for _,o in pairs(qReview.objects) do qReview.hidden[#qReview.hidden+1]=o end
        for _,s in pairs(qReview.saved) do qReview.hidden[#qReview.hidden+1]=s.o end
        for _,o in pairs(qReview.objects) do o:Destroy() end
        for _,s in pairs(qReview.saved) do
            s.o.paint=s.paint s.o:Invalidate() s.o:Alpha(s.alpha or 1)
            s.o:Place(s.device,s.pos,s.ang,s.metres) s.o:Show(s.visible==true)
        end
        qReview.objects={} qReview.saved={}
    end
    c.Registry.current=previous
end
local function qInstall()
    qCore=NLVR
    local overlayStats={native_peak=0,source_peak=0}
    qReview.overlayStats=overlayStats
    local function count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
    for _,o in pairs(qCore.Overlay.Objects) do if o.handle then qLive[o.handle]=true end end
    overlayStats.native_peak=count(qLive)
    local function request(handle)
        local frame=FrameNumber()
        if frame~=qRequestFrame then qRequests,qRequestFrame={},frame end
        qRequests[handle]=true overlayStats.source_peak=math.max(overlayStats.source_peak,count(qRequests))
    end
    for _,method in ipairs({"OverlayCreate","OverlaySource","OverlayWindow","OverlayDestroy"}) do
        local name=method local original=nlvr[name] qOverlayOriginals[name]=original
        if original then nlvr[name]=function(...)
            local handle=...
            if name~="OverlayCreate" then request(handle) end
            local result,detail=original(...)
            if name=="OverlayCreate" and result then qLive[result]=true
            elseif name=="OverlayDestroy" and result~=false and not detail then qLive[handle]=nil end
            overlayStats.native_peak=math.max(overlayStats.native_peak,count(qLive))
            return result,detail
        end end
    end
    for _,entry in ipairs(qCore.Registry.entries) do if entry.module.name=="ui" then qCtx=entry.ctx end end
    qOldBegin,qOldActions,qOldRefresh=nlvr.BeginFrame,nlvr.Actions,qCore.Refresh
    local refresh={calls=0,passes=0,frames=0,max_passes=0,last_frame=-1,frame_passes=0}
    qReview.refresh=refresh
    qCore.Refresh=function(...)
        local number=FrameNumber()
        if refresh.last_frame~=number then
            refresh.max_passes=math.max(refresh.max_passes,refresh.frame_passes)
            refresh.frames=refresh.frames+1 refresh.frame_passes=0 refresh.last_frame=number
        end
        refresh.calls=refresh.calls+1 local hand=qCore.Hand.left
        local t=qTime()
        -- Paired final quiet frames: bypass only the resolver cache for the uncached control.
        if t>=40 and t<42 and number%2==0 then qCore.HandRevision=(qCore.HandRevision or 0)+1 end
        local result=qOldRefresh(...)
        if qCore.Hand.left~=hand then refresh.passes=refresh.passes+1 refresh.frame_passes=refresh.frame_passes+1 end
        return result
    end
    nlvr.BeginFrame=function(...)
        local f=qOldBegin(...)
        local t=qTime()
        if f and t>=0 then
            f.hmd.pos,f.hmd.ang=Vector(0,0,1.6),Angle()
            f.left.pos,f.right.pos=Vector(.25,.2,1.2),Vector(.25,-.2,1.2)
            f.left.ang,f.right.ang=Angle(),Angle()
            if t>=20 and t<23 then f.right.pos=Vector(.85,-.2,1.2) end
            if t>=23 and t<31 then f.right.ang=Angle(20,0,0) end
            if t>=32 and t<33.2 then f.hmd.pos.x=math.min(3,(t-32)*3) end
            if t>=33.2 then f.hmd.pos.x=3+(t>=33.5 and .01 or 0) end
            f.left.pos.x=f.left.pos.x+f.hmd.pos.x
            f.right.pos.x=f.right.pos.x+f.hmd.pos.x
            f.hmd.valid,f.left.valid,f.right.valid=true,true,not (t>=20.4 and t<20.65)
        end
        return f
    end
    nlvr.Actions=function(...)
        local a=qOldActions(...) local t=qTime()
        if t<0 then return a end
        a={left_stick={active=true,x=0,y=0},right_stick={active=true,x=0,y=0}}
        if t>=3 and t<7 then a.left_stick.y=1 a.left_stick_click={active=true,state=t>=5} end
        if t>=8 and t<12 then a.left_stick.y=1 a.left_stick_click={active=true,state=t>=10} end
        a.right_grip={active=true,state=t>=7.7 and t<11.9 or t>=23.5 and t<27 or t>=27.5 and t<31}
        if t>=23.8 and t<24.4 or t>=27.8 and t<28.4 then a.right_stick.y=1 end
        if t>=36 and t<39.5 then a.left_stick.y=1 end
        return a
    end
    qCtx.On("frame",function()
        local t=qTime()
        if t>=0 and t<2.8 then qOverlays(true) end
    end)
    qCtx.On("before_overlay_paint",function()
        local t=qTime() if t>=0 and t<2.8 then qOverlays(true) end
    end)
    qCtx.cleanup(function()
        nlvr.BeginFrame,nlvr.Actions=qOldBegin,qOldActions
        qCore.Refresh=qOldRefresh
        for name,original in pairs(qOverlayOriginals) do nlvr[name]=original end
        hook.Remove("OnSpawnMenuClose","nlvr_review_throw")
        emit("Q-review-refresh",qReview.refresh)
        emit("Q-review-cpu",qReview.cpu or {})
    end)
end
hook.Add("PreRender","nlvr_combined_review",function()
    if not NLVR then
        if qCore and not qOff then
            qOff=true
            if IsValid(qSpawn) then
                if qSpawn.Open then qSpawn:Open() else qSpawn:MakePopup() end
                emit("Q-review-menu-after-exit",{valid=IsValid(qSpawn),parent_world=qSpawn:GetParent()==vgui.GetWorldPanel(),opens=qSpawn:IsVisible(),method=qSpawn.Open and "Open" or "MakePopup",caught=qReview.closeThrows or 0})
                qSpawn:Close()
            end
            hook.Remove("PreRender","nlvr_combined_review")
            hook.Remove("PostRender","nlvr_review_hand_render")
        end
        return
    end
    local t=qTime() if t<0 then return end
    if not qCore then qInstall() end
    if t>=40 and t<42 and nlvrqinspect then
        qReview.cpu=qReview.cpu or {cached={frames=0,cpu_ms=0,cycles=0},uncached={frames=0,cpu_ms=0,cycles=0}}
        local cpu,cycles=nlvrqinspect.Clock() local prior=qReview.clock local number=FrameNumber()
        if prior and number==prior.frame+1 then
            local out=qReview.cpu[prior.mode]
            out.frames=out.frames+1 out.cpu_ms=out.cpu_ms+cpu-prior.cpu out.cycles=out.cycles+cycles-prior.cycles
        end
        qReview.clock={cpu=cpu,cycles=cycles,frame=number,mode=number%2==0 and "uncached" or "cached"}
    end
    qOnce("begin",function()
        RunConsoleCommand("nl_vr_dominant","0") RunConsoleCommand("nl_vr_height","0")
        RunConsoleCommand("use","nlvr_hands")
        local list={} for _,row in ipairs(qCore.Debug.ui.panels) do list[#list+1]=row.key end
        for _,key in ipairs(list) do qCore.Emit("ui_toggle",key) end
        qStage("walk") NativeLoaderVR.Recenter()
    end)
    if t>=1 and t<2.8 then qOnce("overlays",function()
        qOverlays(true)
        local rows,count={},0
        for key,o in pairs(qCore.Overlay.Objects) do
            local info=o.handle and nlvr.OverlayInfo(o.handle)
            rows[key]={visible=o.visible,handle=o.handle,info=info} if o.visible then count=count+1 end
        end
        local active=true for _,entry in ipairs(qCore.Registry.entries) do active=active and entry.active and not entry.stopped end
        emit("Q-review-overlays",{visible=count,roles=rows,modules_active=active,budgets=qReview.overlayStats,info=nlvr.Info()}) capture("review-overlays")
    end) end
    if t>=2.8 then qOnce("hide",function() qOverlays(false) end) end
    if t>=5.2 then qOnce("retired",function()
        local expired={}
        for _,o in ipairs(qReview.hidden or {}) do
            if o.handle and (o.destroyed or not o.wanted and o.hiddenAt and RealTime()-o.hiddenAt>2.1) then expired[#expired+1]=o.key end
        end
        emit("Q-review-retired",{expired_native=expired,budgets=qReview.overlayStats})
    end) end
    if t>=7 then qOnce("walk-result",function() emit("Q-review-walk",qReview.stats) capture("review-walk") end) end
    if t>=12.3 then qOnce("held-result",function()
        emit("Q-review-held-client",{walk=qReview.stats.held_walk,sprint=qReview.stats.held_sprint})
    end) end
    if t>=7.2 and t<13 then qStage("hold") end
    if t>=13 and t<17 then qStage("masses") end
    if t>=17 and t<20 then qStage("melee") end
    if t>=20 and t<23 then qStage("wall") end
    if t>=22.2 then qOnce("wall-image",function() capture("review-wall") end) end
    if t>=23 and t<27 then qStage("blink") end
    if t>=24 then qOnce("blink-input",function()
        emit("Q-review-carry-input",{phase="blink",grip=NLVR.Input.right.grip,owner=NLVR.Input.Owner("right","grip"),
            active=NLVR.Weapon.Active and NLVR.Weapon.Active.class})
    end) end
    if t>=28 then qOnce("shift-input",function()
        emit("Q-review-carry-input",{phase="shift",grip=NLVR.Input.right.grip,owner=NLVR.Input.Owner("right","grip"),
            active=NLVR.Weapon.Active and NLVR.Weapon.Active.class})
    end) end
    if t>=25.6 then qOnce("blink-image",function() capture("review-held-blink") end) end
    if t>=27 and t<31 then qStage("shift") end
    if t>=29.6 then qOnce("shift-image",function() capture("review-held-shift") end) end
    if t>=31 and t<35 then qStage("pause") end
    if t>=31.9 then qOnce("pause-open",function() gui.ActivateGameUI() end) end
    if t>=33.3 then qOnce("pause-close",function() gui.HideGameUI() end) end
    if t>=34.4 then qOnce("pause-result",function()
        local d=qCore.Pose.head.pos-LocalPlayer():EyePos()
        emit("Q-review-pause",{horizontal_error=Vector(d.x,d.y,0):Length(),room=qCore.Debug.move.room})
    end) end
    if t>=35 and t<39.5 then qStage("stale") end
    if t>=38 and t<39.5 then qOnce("stale-before",function() qReview.staleBefore=qCore.Pose.head.pos end) end
    if t>=39.5 then qOnce("stale-after",function()
        emit("Q-review-stale",{travel=(qCore.Pose.head.pos-qReview.staleBefore):Length(),engine=LocalPlayer():GetPos(),head=qCore.Pose.head.pos})
        qStage("done")
        qCore.Emit("ui_toggle","spawn") qSpawn=g_SpawnMenu
        hook.Add("OnSpawnMenuClose","nlvr_review_throw",function()
            qReview.closeThrows=(qReview.closeThrows or 0)+1 error("Q deliberately throwing close hook")
        end)
    end) end
    if t>=40.1 then qOnce("cpu-health-start",function() RunConsoleCommand("nlvr_review_health","start") end) end
    if t>=41.7 then qOnce("cpu-health-end",function() RunConsoleCommand("nlvr_review_health","end") end) end
    if t>=42.3 and t<45 then qStage("carry-wall") end
    if t>=45.3 then qStage("carry-constraint") end
end)
hook.Add("PostRender","nlvr_review_hand_render",function()
    if NLVR~=qCore or not qCore or not lastCamera or not qCore.Frame or lastCamera.sequence~=qCore.Frame.sequence then return end
    local t=qTime()
    local label=t>=3.5 and t<4.8 and "walk" or t>=5.5 and t<6.8 and "sprint" or
        t>=8.8 and t<9.8 and "held_walk" or t>=10.8 and t<11.8 and "held_sprint" or nil
    if not label or qReview.sampleFrame==FrameNumber() then return end
    qReview.sampleFrame=FrameNumber()
    qReview.stats[label]=qReview.stats[label] or {n=0,max_error=0,ghosts=0}
    local out=qReview.stats[label]
    local h=qCore.Hand.right
    local camera=Vector(unpack(lastCamera.origin))
    local expected=h.target.pos+camera-qCore.Pose.head.pos
    local error=(h.shown.pos-expected):Length()
    if label=="held_walk" or label=="held_sprint" then
        local ent=h.held and h.held.ent
        if not IsValid(ent) then return end
        error=(ent:NearestPoint(expected)-expected):Length()
    end
    out.n=out.n+1 out.max_error=math.max(out.max_error,error) out.ghosts=out.ghosts+(h.blocked and 1 or 0)
    out.reference=label:find("held",1,true) and "client prop bounding surface to controller in the rendered camera frame" or
        "controller relative to the rendered camera, same native sequence"
end)
qWristExit=function()
    if not NLVR then return false end
    NLVR.Emit("ui_toggle","wrist_menu")
    local entry
    for _,row in ipairs(NLVR.Debug.ui.panels or {}) do if row.key=="wrist_menu" then entry=row end end
    local function visit(p)
        if p.GetText and p:GetText()=="Exit VR" and p.DoClick then p.DoClick() return true end
        for _,child in ipairs(p:GetChildren()) do if visit(child) then return true end end
    end
    for _,p in ipairs(vgui.GetWorldPanel():GetChildren()) do if visit(p) then return true end end
    return false
end
