-- A real competing add-on: callbacks remain registered through two VR lifecycles.
local Addon={}
local function copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
function Addon.New(options)
    options=options or {}
    local self={counts={think_vr=0,think_flat=0,input_vr=0,input_flat=0,view_vr=0,view_flat=0,moving=0},cycles=0,exits=0,views=0,bad_views=0,hands=0,menus=0}
    local seen,active,removeAt
    local observed={}
    local id=options.id or "q4_competing_addon"
    local function send(kind)
        if options.emit then options.emit(kind,{counts=copy(self.counts),cycles=self.cycles,exits=self.exits,views=self.views,bad_views=self.bad_views,hands=self.hands,menus=self.menus}) end
    end
    hook.Add("CalcView",id,function()
        if NLVR then self.counts.view_vr=self.counts.view_vr+1 return {origin=Vector(99999,99999,99999),angles=Angle(),fov=13} end
        self.counts.view_flat=self.counts.view_flat+1
    end,HOOK_HIGH)
    hook.Add("Think",id,function()
        if NLVR then
            self.counts.think_vr=self.counts.think_vr+1
            if seen~=NLVR then seen=NLVR active=true self.cycles=self.cycles+1 send("peer-start") end
            if NLVR.Debug and NLVR.Debug.hands then
                local count=0 for _,side in ipairs({"left","right"}) do if (NLVR.Debug.hands[side] or {}).draws and NLVR.Debug.hands[side].draws>0 then count=count+1 end end
                self.hands=math.max(self.hands,count)
            end
            if options.probe_view and NLVR.Pose.head and not observed[self.cycles] then
                local ply=LocalPlayer()
                local v=hook.Run("CalcView",ply,ply:EyePos(),ply:EyeAngles(),90,1,9000)
                self.ObserveView(v,NLVR.Pose.head.pos) observed[self.cycles]=true
            end
        else
            self.counts.think_flat=self.counts.think_flat+1
            if active then active=false self.exits=self.exits+1 send("peer-exit") end
            if options.finish and self.exits==2 then
                removeAt=removeAt or RealTime()+.25
                if RealTime()>=removeAt then
                    if options.emit then options.emit("peer-final",self.Check(options.features)) end
                    self.Remove()
                end
            end
        end
    end,HOOK_MONITOR_HIGH)
    hook.Add("CreateMove",id,function(cmd)
        local key=NLVR and "input_vr" or "input_flat"
        self.counts[key]=self.counts[key]+1
        if NLVR and math.abs(cmd:GetForwardMove())+math.abs(cmd:GetSideMove())+math.abs(cmd:GetUpMove())>1 then self.counts.moving=self.counts.moving+1 end
    end,HOOK_LOW)
    function self.ObserveView(view,head)
        self.views=self.views+1
        if not view or not view.origin or (view.origin-head):Length()>.4 then self.bad_views=self.bad_views+1 end
    end
    function self.HandDraws(count) self.hands=math.max(self.hands,count) end
    function self.MenuAction() self.menus=self.menus+1 end
    function self.Check(features)
        features=features or {}
        local c=self.counts
        local checks={two_starts=self.cycles==2,two_exits=self.exits==2,
            active_think=c.think_vr>=2,active_input=c.input_vr>=2,
            flat_think=c.think_flat>=2,flat_input=c.input_flat>=1,
            competing_view_isolated=c.view_vr==0 and c.view_flat>=1,
            actual_view=self.views>=2 and self.bad_views==0,
            hands=not features.hands or self.hands>=2,
            movement=not features.movement or c.moving>=2,
            menus=not features.menus or self.menus>=1}
        local success=true for _,ok in pairs(checks) do success=success and ok end
        return {success=success,checks=checks,counts=copy(c),cycles=self.cycles,exits=self.exits,views=self.views,bad_views=self.bad_views,hands=self.hands,menus=self.menus}
    end
    function self.Remove()
        hook.Remove("CalcView",id) hook.Remove("Think",id) hook.Remove("CreateMove",id)
        send("peer-removed")
    end
    return self
end
return Addon
