-- Limited review check: no world target spawned, broken or removed.
local peers=include("nlvr_q_tests/hook_addon.lua").New{emit=emit,probe_view=true,finish=true,
    features={hands=true,movement=true,menus=true}}
local installed,seen,worst,hidden,menuSeen=false,false,false,false,false
local oldFrame,objects,saved={}, {}, {}
local live,requests,lastFrame={}, {}, -1
local peaks={native=0,pending_sources=0}
local originals={}
local function count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
local function tree(panel,test)
    if not IsValid(panel) then return end
    if test(panel) then return panel end
    for _,child in ipairs(panel:GetChildren()) do local p=tree(child,test) if p then return p end end
end
local function point(frame)
    local root=tree(vgui.GetWorldPanel(),function(p) return p.NLVRPanel=="wrist_menu" end)
    if not root then return end
    local button=tree(root,function(p) return p.GetText and p:GetText()==NATIVELOADER_I18N.L("VR settings") end)
    if not button then return end
    local x,y=button:LocalToScreen(button:GetWide()/2,button:GetTall()/2);x,y=root:ScreenToLocal(x,y)
    local o=NLVR.Overlay.Objects.wrist_menu
    if not o then return end
    local p,a=o.pos,o.ang
    if o.device~="world" then local pose=frame[o.device=="head" and "hmd" or o.device] p,a=LocalToWorld(p,a,pose.pos,pose.ang) end
    return p+a:Right()*((x/root:GetWide()-.5)*o.metres)+a:Up()*((.5-y/root:GetTall())*o.metres*o.height/o.width)
end
local function allRoles(ctx,show)
    if show then
        local index=0
        for key,size in pairs(ctx.Overlay.Sizes) do
            local o=ctx.Overlay.Objects[key]
            if not o then
                o=ctx.Overlay.New{key=key,width=size[1],height=size[2],paint=function(_,w,h)
                    surface.SetDrawColor(20,55,90,240) surface.DrawRect(0,0,w,h)
                    draw.SimpleText(key,"DermaDefault",w/2,h/2,color_white,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                end}
                objects[key]=o
                if key=="flat" then o:Window(true) end
            end
            if not saved[key] then
                saved[key]={object=o,wanted=o.wanted,device=o.device,pos=o.pos,ang=o.ang,metres=o.metres,paint=o.paint,show=o.Show}
                local show=o.Show
                -- Mutually exclusive production roles are deliberately held visible for
                -- this resource-pressure witness, including later comfort callbacks.
                o.Show=function(self) return show(self,true) end
            end
            o:Invalidate() o:Alpha(1)
            o:Place("head",Vector(.8,(index%5-2)*.2,(2-math.floor(index/5))*.18),Angle(),.17) o:Show(true)
            index=index+1
        end
    else
        for _,s in pairs(saved) do s.object.Show=s.show end
        for _,o in pairs(objects) do o:Destroy() end
        for key,s in pairs(saved) do if not objects[key] then s.object.paint=s.paint s.object:Place(s.device,s.pos,s.ang,s.metres) s.object:Show(s.wanted==true) end end
        objects,saved={},{}
    end
end
hook.Add("PreRender","q_review_safe",function()
    if phase~="active" or not NLVR then return end
    local state=nlvr.TestState() if not state then return end
    local t=state.time
    if not installed then
        installed,seen=true,true
        local ctx
        for _,entry in ipairs(NLVR.Registry.entries) do if entry.module.name=="ui" then ctx=entry.ctx end end
        assert(ctx,"UI context missing")
        NLVR.Space.Turn(-(NLVR.Space.yaw or 0))
        ctx.mover(-100,function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) cmd:SetMouseY(0) end)
        ctx.On("panel_open",function(key)
            if key=="settings" then menuSeen=true peers.MenuAction() emit("safe-menu-action",{key=key,click=NLVR.Debug.ui.last_click}) end
        end)
        oldFrame=nlvr.BeginFrame
        nlvr.BeginFrame=function(...)
            local f,detail=oldFrame(...)
            local s=nlvr.TestState()
            if f and s and s.time>=6 and s.time<10 then
                local target=point(f)
                if target then
                    f.right.pos,f.right.ang=Vector(.3,-.25,1.2),Angle()
                    QFrames.Aim(f.right,"right",target)
                end
            end
            return f,detail
        end
        for key,o in pairs(NLVR.Overlay.Objects) do if o.handle then live[o.handle]=true end end
        for _,name in ipairs({"OverlayCreate","OverlaySource","OverlayWindow","OverlayDestroy"}) do
            local method=name local original=nlvr[method];originals[method]=original
            nlvr[method]=function(...)
                if FrameNumber()~=lastFrame then requests={} lastFrame=FrameNumber() end
                local handle=...
                if method~="OverlayCreate" then requests[handle]=true peaks.pending_sources=math.max(peaks.pending_sources,count(requests)) end
                local value,detail=original(...)
                if method=="OverlayCreate" and value then live[value]=true
                elseif method=="OverlayDestroy" and value~=false and not detail then live[handle]=nil end
                peaks.native=math.max(peaks.native,count(live))
                return value,detail
            end
        end
        ctx.On("frame",function() local s=nlvr.TestState() if s and s.time>=13 and s.time<17 then allRoles(ctx,true) end end)
        ctx.On("before_overlay_paint",function() local s=nlvr.TestState() if s and s.time>=13 and s.time<17 then allRoles(ctx,true) end end)
        ctx.cleanup(function()
            for name,fn in pairs(originals) do nlvr[name]=fn end
            if oldFrame then nlvr.BeginFrame=oldFrame end
        end)
    end
    if t>=10 and not hidden then
        hidden=true
        if menuSeen then NLVR.Emit("ui_toggle","settings") end
        capture("safe-menus")
    end
    if t>=15.5 and not worst then
        worst=true
        local rows,visible={},0
        for key,o in pairs(NLVR.Overlay.Objects) do
            local info=o.handle and nlvr.OverlayInfo(o.handle)
            rows[key]={visible=o.visible,handle=o.handle,info=info}
            if o.visible then visible=visible+1 end
        end
        emit("safe-overlays",{visible=visible,roles=rows,peaks=peaks,info=nlvr.Info(),menu_action=menuSeen,
            target_policy="no world targets; no damage/spawn/removal; diagnostic mutually exclusive overlay roles forced together"})
        capture("safe-worst-overlays")
    end
    if t>=17 and objects and next(objects) then
        local ctx
        for _,entry in ipairs(NLVR.Registry.entries) do if entry.module.name=="ui" then ctx=entry.ctx end end
        allRoles(ctx,false)
    end
end)
