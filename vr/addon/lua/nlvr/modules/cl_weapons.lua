-- The public table is session-owned; K and T may retain it until Exit.
local module = {name = "weapons", order = 44}
local Math = include("nlvr/modules/sh_weapons.lua")
local Model = include("nlvr/modules/cl_weapons_model.lua")
local function hookEvent(context,event,private)
    local call,live,replaying=hook.Call,true,false
    local changedShots=event=="EntityFireBullets" and setmetatable({},{__mode="k"})
    context.cleanup(function() live=false end)
    if changedShots then
        local gm=gmod and gmod.GetGamemode and gmod.GetGamemode() or GAMEMODE
        if type(gm)=="table" then
            local previous,rawPrevious=gm.EntityFireBullets,rawget(gm,"EntityFireBullets")
            local function apply(self,ent,bullet,...)
                local a,b,c,d,e,f
                if previous then a,b,c,d,e,f=previous(self,ent,bullet,...) end
                if live and changedShots[bullet] then
                    changedShots[bullet]=nil bullet.Tracer=0
                    if a==nil then a=true end
                end
                return a,b,c,d,e,f
            end
            gm.EntityFireBullets=apply
            context.cleanup(function() if rawget(gm,"EntityFireBullets")==apply then gm.EntityFireBullets=rawPrevious end end)
        end
    end
    local function prepare(...)
        local result=call(private,nil,...)
        if result==true and changedShots then local _,bullet=... changedShots[bullet]=true end
        return result
    end
    -- Always register an ordinary hook. Unknown libraries retain this safe fallback;
    -- known live registries also use it when another writer replaces our takeover.
    local fallbackId="nlvr."..context.name
    context.hook(event,function(...)
        if not live or replaying then return end
        if prepare(...)==false then return false end
    end)
    local plain=hook.GetTable()
    local ulib=type(hook.GetULibTable)=="function" and hook.GetULibTable()
    local heldLevels=type(ulib)=="table" and ulib[event]
    if heldLevels then for n=-2,2 do if type(heldLevels[n])~="table" then heldLevels=nil break end end end
    if not heldLevels then
        -- Capability probe uses a private event, never a gameplay hook. GetTable can
        -- be a detached copy even when it looks like the stock table.
        local probe=private..".registry_probe" local first,second={},{}
        hook.Add(probe,fallbackId,function() return first end)
        local probeRegistry=hook.GetTable()
        local saved=probeRegistry[probe]
        probeRegistry[probe]={[fallbackId]=function() return second end}
        local ok,value=pcall(call,probe,nil)
        probeRegistry[probe]=saved
        hook.Remove(probe,fallbackId)
        if not ok or value~=second then return end
    end
    local held=plain[event] or {}
    local owned=setmetatable({},{__index=held,__newindex=function(_,id,fn) held[id]=fn end})
    local ownedLevels
    local id="nlvr.weapons.dispatch"
    local function dispatch(...)
        if not live or replaying then return end
        local changed=prepare(...)
        if changed==false then return false end
        if not live then return end
        -- A rebuilt registry may contain a copy of this dispatcher. In that case
        -- the caller already owns iteration: prepare, then let its other hooks run
        -- once instead of recursively replaying the copied table.
        if plain[event]~=owned and (not ownedLevels or ulib[event]~=ownedLevels) then return end
        if plain[event]==owned then plain[event]=held end
        if ownedLevels and ulib[event]==ownedLevels then ulib[event]=heldLevels end
        replaying=true
        local ok,a,b,c,d,e,f=pcall(call,event,nil,...)
        replaying=false
        if live and plain[event]==held then plain[event]=owned end
        if live and ownedLevels and ulib[event]==heldLevels then ulib[event]=ownedLevels end
        if not ok then error(a,0) end
        if changed and changedShots then local _,bullet=... bullet.Tracer=0 end
        return a,b,c,d,e,f
    end
    rawset(owned,id,dispatch)
    if heldLevels then
        ownedLevels={}
        for n=-2,2 do
            local list=heldLevels[n]
            ownedLevels[n]=setmetatable({},{__index=list,__newindex=function(_,key,value) list[key]=value end})
        end
        rawset(ownedLevels[HOOK_HIGH or -1],id,{fn=dispatch,isstring=true})
        ulib[event]=ownedLevels
    end
    plain[event]=owned
    context.cleanup(function()
        live=false
        hook.Remove(event,fallbackId)
        rawset(owned,id,nil)
        for key,fn in pairs(held) do rawset(owned,key,fn) end
        if plain[event]==owned then plain[event]=held end
        if ownedLevels then
            for n=-2,2 do
                rawset(ownedLevels[n],id,nil)
                for key,entry in pairs(heldLevels[n]) do rawset(ownedLevels[n],key,entry) end
            end
            if ulib[event]==ownedLevels then ulib[event]=heldLevels end
        end
    end)
end
local ctx, api, distance, sent, draws, fires, lastFire, lastShot
local acknowledged,configSequence,configAt,configIdentity,configPending
local gripCurls = {}
local gripLatched = {}
local triggerLatched = {}
local function claimGrip(hand)
    if ctx.Input.Claim(hand,"grip",ctx.name) and ctx.Input[hand].grip then gripLatched[hand]=true end
end
local function filter(active)
    local skip = {[LocalPlayer()]=true}
    if active then
        skip[active.ent]=true
        if IsValid(active.model) then skip[active.model]=true end
    end
    for _,hand in pairs(ctx.Hand) do if hand.held and IsValid(hand.held.ent) then skip[hand.held.ent]=true end end
    -- P's hand proxies never transmit. Client arms and other client-only models have no solid hull.
    return function(ent) return not skip[ent] end
end
local function clear()
    local active = api and api.Active
    Model.Restore(active)
    if active and IsValid(active.model) then active.model:Remove() end
    if api then api.Active = nil end
    distance,sent=nil,nil
    acknowledged=false
    configIdentity,configPending=nil,false
end
local function update()
    local ply = LocalPlayer()
    local ent = IsValid(ply) and ply:Alive() and ply:GetActiveWeapon()
    if not IsValid(ent) then
        if api.Active then clear() ctx.Emit("weapon_changed", nil) end
        return
    end
    local class, hand = ent:GetClass(), ctx.Input.mainHand
    local active = api.Active
    local path = ent:GetWeaponWorldModel() or ""
    if class=="nlvr_hands" then path="" end
    if not active or active.ent ~= ent or active.hand ~= hand or active.path ~= path then
        clear()
        active = {ent = ent, class = class, kind = Math.Kind(class), hand = hand, twoHanded = false, path = path}
        api.Active = active
        Model.Prepare(active)
        if active.kind ~= "hands" and path ~= "" then
            active.model = ClientsideModel(path, RENDERGROUP_OPAQUE)
            if IsValid(active.model) then
                active.model:SetNoDraw(true)
                active.geometry=Model.Measure(active.model,class)
                active.model:SetSkin(ent:GetSkin())
                for i=0,ent:GetNumBodyGroups()-1 do active.model:SetBodygroup(i,ent:GetBodygroup(i)) end
            end
        end
        active.geometry=active.geometry or {muzzle=Vector(Math.Data(class).length or 0.1,0,0)}
        ctx.Emit("weapon_changed", active)
    end
    local state = ctx.Hand[hand]
    local handFrame = ctx.core.HandModelFrames and ctx.core.HandModelFrames[hand]
    if IsValid(active.model) and active.handFrame ~= handFrame then
        active.geometry = Model.Measure(active.model, class, handFrame, hand)
        active.handFrame = handFrame
    end
    local pose = state and state.shown
    active.valid = pose and pose.valid == true
    if not active.valid then return end
    local scale=ctx.Space.scale
    -- The core hand frame shares SteamVR's tip orientation. The rendered grip correction
    -- must never feed back and compound on the next model update.
    local aiming=state.target.aim and state.target.aim.valid and state.target.aim.ang or state.target.ang
    local angle=Math.GunAngle(aiming,ctx.Settings.gun_angle or 0)
    local off=ctx.Hand[Math.Opposite(hand)]
    local offPose=off and off.target
    local point=active.geometry.fore and LocalToWorld(active.geometry.fore*scale,Angle(),pose.pos,angle)
    local gripping=point and offPose and offPose.valid and ctx.Input.off.grip and ctx.Settings.foregrip~=0
        and not off.blocked and not off.held
    local own=ctx.Input.Owner("off","grip")
    local tolerance=active.twoHanded and 0.25 or 0.12
    active.twoHanded=gripping and (not own or own==ctx.name) and point:DistToSqr(offPose.pos)<=(scale*tolerance)^2 or false
    if active.twoHanded then
        angle=Math.Along(pose.pos,offPose.pos,angle:Up())
        point=LocalToWorld(active.geometry.fore*scale,Angle(),pose.pos,angle)
        claimGrip(Math.Opposite(hand))
        if ctx.Input.Claim("off","trigger",ctx.name) and ctx.Input.off.trigger then triggerLatched[Math.Opposite(hand)]=true end
        active.forePos=point
    else active.forePos=nil end
    active.aimAng=angle
    active.muzzle={pos=LocalToWorld(active.geometry.muzzle*scale,Angle(),pose.pos,angle),ang=angle}
    local kick=lastFire and math.max(0,1-(RealTime()-lastFire)/0.12)*3 or 0
    Model.Pose(active,pose.pos,angle,scale,kick)
    ctx.Debug.weapons={class=active.class,kind=active.kind,hand=hand,two_handed=active.twoHanded,
        model=IsValid(active.model) and active.model:GetModel() or "",model_pos=active.pos,model_ang=active.ang,
        grip_bone=active.geometry.bone,grip_correction=active.geometry.correction,grip_pos=active.grip,muzzle=active.muzzle,foregrip=point,draws=draws,fires=fires,kick=kick,
        measures=Model.measures or 0,measure_ms=Model.measureMs or 0,custom_draws=active.customDraws or 0,custom_fallback=active.customFailed==true,camera_override=active.cameraOverride~=nil,last_shot=lastShot}
end
local function claims()
    for _,hand in ipairs({"left","right"}) do
        if not ctx.Input[hand].trigger then triggerLatched[hand]=nil
        elseif triggerLatched[hand] then ctx.Input.Claim(hand,"trigger",ctx.name) end
        if not ctx.Input[hand].grip then gripLatched[hand]=nil
        elseif gripLatched[hand] then ctx.Input.Claim(hand,"grip",ctx.name) end
    end
    local a=api.Active
    if not a or a.kind=="hands" then return end
    claimGrip(a.hand)
    if ctx.Input.Claim("main","trigger",ctx.name) and ctx.Input.main.trigger then triggerLatched[a.hand]=true end
end
local function poseGrip(hand,state)
    if state.grip_curls == gripCurls[hand] then state.grip_curls = nil end
    local a=api.Active
    if not a or a.kind=="hands" then return end
    if hand==a.hand then
        state.grip_curls={0.65,ctx.Input.main.trigger and 0.65 or 0.3,0.68,0.68,0.68}
        if a.aimAng and (a.geometry.handAngle or a.geometry.correction) then
            local _,ang=LocalToWorld(Vector(),a.geometry.handAngle or a.geometry.correction,Vector(),a.aimAng)
            state.shown.ang=ang
        end
    elseif a.twoHanded and a.forePos then
        state.shown.pos=a.forePos state.shown.ang=a.aimAng
        local frame=ctx.core.HandModelFrames and ctx.core.HandModelFrames[hand]
        if frame and frame.grip and not frame.calibrated then
            local offset=WorldToLocal(frame.grip,Angle(),frame.pos,frame.ang)
            local world=LocalToWorld(offset*(ctx.Space.scale/40),Angle(),Vector(),a.aimAng)
            state.shown.pos=a.forePos-world
        end
        state.grip_curls={0.65,0.68,0.68,0.68,0.68}
    end
    gripCurls[hand] = state.grip_curls
end
local function sync()
    local a=api.Active
    if not a or not a.valid then return end
    local g=a.geometry
    -- Foregrip permission/offset is a profile, not the current grip state. The host
    -- independently decides engagement from tracked hand distance and its grip bit.
    local fore=g.fore or Vector()
    local enabled=g.fore~=nil and ctx.Settings.foregrip~=0
    local meleeTip=g.meleeTip or Vector()
    local identity=table.concat({a.class,a.hand,tostring(enabled),tostring(ctx.Settings.melee),
        g.muzzle.x,g.muzzle.y,g.muzzle.z,fore.x,fore.y,fore.z,meleeTip.x,meleeTip.y,meleeTip.z},":")
    local signature=identity..":"..tostring(ctx.Settings.gun_angle)
    if sent~=signature then
        configSequence=(configSequence+1)%65536 sent=signature configPending=true configAt=-math.huge
        if configIdentity~=identity then acknowledged=false end
        configIdentity=identity
    end
    if not configPending or RealTime()-configAt<0.1 then return end
    ctx.Net.Send(64,function(w)
        w.WriteString(a.class) w.WriteBool(a.hand=="left")
        for _,v in ipairs({g.muzzle,g.fore or Vector(),meleeTip}) do w.WriteFloat(v.x) w.WriteFloat(v.y) w.WriteFloat(v.z) end
        w.WriteBool(enabled)
        w.WriteFloat(ctx.Settings.gun_angle or 0) w.WriteBool(ctx.Settings.melee~=0)
        w.WriteUInt(configSequence,16)
    end)
    configAt=RealTime()
end
local function fired(class,src,dir,hit,tracer,flash)
    local a=api.Active
    if not a or a.class~=class then return end
    lastFire=RealTime() fires=fires+1
    if tracer then
        local effect=EffectData()
        effect:SetStart(src) effect:SetOrigin(hit) effect:SetScale(5000)
        -- No entity/attachment: the engine cannot substitute the local view model's muzzle.
        util.Effect(class=="weapon_ar2" and "AR2Tracer" or "Tracer",effect)
    end
    if flash then
        local effect=EffectData()
        effect:SetOrigin(src) effect:SetAngles(dir:Angle())
        effect:SetEntity(NULL) effect:SetAttachment(0) effect:SetFlags(0)
        effect:SetScale(class=="weapon_shotgun" and 1.5 or 1)
        -- This engine effect consumes Origin/Angles/Scale, with no attachment lookup.
        util.Effect("MuzzleEffect",effect,false)
        local light=DynamicLight(LocalPlayer():EntIndex()+8192)
        if light then
            light.pos,light.r,light.g,light.b=src,255,190,95
            light.brightness,light.Decay,light.Size,light.DieTime=2,1200,120,CurTime()+0.05
        end
    end
    ctx.Debug.weapons=ctx.Debug.weapons or {}
    lastShot={src=src,dir=dir,hit=hit,tracer=tracer,flash=flash}
    ctx.Debug.weapons.last_shot=lastShot
    ctx.Emit("weapon_fired",a)
end
function module.Start(context)
    -- The client core also runs without the engine weapon library (e.g. a menu realm).
    -- Leave the optional feature dormant rather than failing the head/hand session.
    if not weapons or type(weapons.Register)~="function" then return end
    ctx,distance,sent,draws,fires,lastFire,lastShot=context,nil,nil,0,0,nil,nil
    gripCurls = {}
    gripLatched = {}
    triggerLatched = {}
    acknowledged,configSequence,configAt,configIdentity,configPending=false,0,-math.huge,nil,false
    Math.Hands()
    api = {Kind = Math.Kind}
    ctx.core.Weapon = api
    ctx.hook("NLVRWeaponBullet",function(ent,bullet)
        local ply,a=LocalPlayer(),api.Active
        if not a or not a.valid or a.kind=="hands" or ent~=ply and ent~=ply:GetActiveWeapon() then return end
        if Math.Vector(bullet.Src) and bullet.Src:DistToSqr(ply:GetShootPos())<=25 then bullet.Tracer=0 return true end
    end)
    hookEvent(ctx,"EntityFireBullets","NLVRWeaponBullet")
    function api.Muzzle()
        local a = api.Active
        if a and a.kind~="hands" and a.valid and a.muzzle then return a.muzzle.pos, a.muzzle.ang end
    end
    function api.Ray()
        local pos, ang = api.Muzzle()
        if pos then return pos, ang:Forward() end
    end
    function api.ConvergeAt(value)
        distance = Math.Finite(value) and math.Clamp(value, 1, 32768) or nil
    end
    ctx.Net.On(65,function()
        local class=net.ReadString()
        local src=net.ReadVector()
        local dir=Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
        local hit=net.ReadVector()
        local tracer,flash=net.ReadBool(),net.ReadBool()
        if Math.Vector(src) and Math.Vector(dir) and Math.Vector(hit) then fired(class,src,dir,hit,tracer,flash) end
    end)
    ctx.Net.On(66,function()
        local class,token=net.ReadString(),net.ReadUInt(16)
        if api.Active and api.Active.class==class and token==configSequence then acknowledged,configPending=true,false end
    end)
    ctx.resolver(300,poseGrip)
    ctx.On("frame",function()
        update() claims()
        for _,hand in ipairs({"left","right"}) do if ctx.Hand[hand] then poseGrip(hand,ctx.Hand[hand]) end end
    end)
    ctx.mover(44, function(cmd)
        update()
        for _,hand in ipairs({"left","right"}) do if ctx.Hand[hand] then poseGrip(hand,ctx.Hand[hand]) end end
        claims() sync()
        local a = api.Active
        if not a or not a.valid or a.kind == "hands" then return end
        local origin, dir = api.Ray()
        local angle,target=Math.Target(LocalPlayer():EyePos(),origin,dir,distance,util.TraceLine,filter(a))
        angle.r=0 ctx.Aim(angle,ctx.name)
        ctx.Debug.weapons.aim_point,ctx.Debug.weapons.aim_ang=target,angle
        local buttons=cmd:GetButtons()
        -- Physical melee has no trigger swing; also discard an ordinary desktop attack.
        buttons=bit.band(buttons,bit.bnot(bit.bor(IN_ATTACK,IN_ATTACK2)))
        if acknowledged and ctx.Input.Owner("main","trigger")==ctx.name and ctx.Input.main.trigger and
            not (a.kind=="melee" and ctx.Settings.melee~=0) then buttons=bit.bor(buttons,IN_ATTACK) end
        local owner=ctx.Input.Owner("main","a")
        if acknowledged and (not owner or owner==ctx.name) and ctx.Input.main.a then buttons=bit.bor(buttons,IN_ATTACK2) end
        if acknowledged and a.twoHanded and ctx.Input.Owner("off","trigger")==ctx.name and ctx.Input.off.trigger then buttons=bit.bor(buttons,IN_ATTACK2) end
        ctx.Debug.weapons.host_ready=acknowledged
        cmd:SetButtons(buttons)
    end)
    ctx.hook("PreDrawTranslucentRenderables", function(depth, skybox)
        if depth or skybox then return end
        update()
        local a = api.Active
        if a and a.valid and IsValid(a.model) then
            Model.Draw(a) draws=draws+1
            if ctx.core.WeaponDrawObserver then ctx.core.WeaponDrawObserver(a) end
        end
    end)
    ctx.cleanup(function() clear() if ctx.core.Weapon == api then ctx.core.Weapon = nil end end)
end
function module.Stop() clear() if ctx then ctx.Debug.weapons=nil end end
return module
