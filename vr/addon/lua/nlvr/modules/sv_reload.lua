local module = {name = "reload", order = 46}
local R = include("nlvr/modules/sh_reload.lua")
local ctx, players, owners, fieldCache
local empty = {}
local function supported(w)
    local f=fieldCache[w]
    if not f then
        f={} local saved=w.GetSaveTable and w:GetSaveTable() or {}
        for _,k in ipairs({"m_bInReload","m_bMustReload","m_bNeedPump","m_bDelayedFire1","m_bDelayedFire2","m_flHolsterTime"}) do f[k]=saved[k]~=nil end
        fieldCache[w]=f
    end
    return f
end
local function field(w,k,v) if supported(w)[k] then w:SetSaveValue(k,v) end end
local function clearFlag(w,k)
    if supported(w)[k] and w:GetInternalVariable(k) then w:SetSaveValue(k,false) end
end
local function release(w,s)
    if IsValid(w) then
        if s.applied and w:GetNextPrimaryFire()==s.applied then w:SetNextPrimaryFire(math.max(CurTime(),s.prior or 0)) end
        end
    s.applied,s.soonest,s.prior,s.holdSince=nil,nil,nil,nil
end
local function gun(state,w)
    local s=state.guns[w]
    if not s then
        s={ejected=false,loaded=false,reserve=0,clip=w:Clip1(),owned=true}
        state.guns[w]=s owners[w]=state.ply supported(w)
    end
    return s
end
local function suspend(ply,forget,preserveCarry)
    local state=players and players[ply] if not state then return end
    for w,s in pairs(state.guns) do release(w,s) if forget then owners[w]=nil end end
    if forget then state.guns={} end
    if not preserveCarry then state.held=nil end
    state.physical,state.dirty=false,true
    local d=state.debug
    if d then d.holding,d.held,d.hold_since,d.command_primary,d.physical=false,state.held and state.held.token or 0,0,0,false if forget then d.ejected=false end end
end
local function heldPose(state,hand)
    local pose=state.hands[hand] local h=state.interact and state.interact[hand]
    if h and IsValid(h.phys) then return {valid=pose.valid,pos=h.phys:GetPos(),ang=pose.ang,buttons=pose.buttons} end
    return pose
end
local function allowed(ply,state)
    return ctx.Weapon and state.enabled and RealTime()-(state.configAt or -10)<=R.ACK_LEASE and ply:Alive() and not ply:InVehicle()
end
local function integer(n,bits)
    if not R.Finite(n) then return 0 end
    return math.Clamp(math.floor(n),-2^(bits-1),2^(bits-1)-1)
end
local function report(ply,state,reason,action,forceOff)
    local now=RealTime() local w=ply:GetActiveWeapon() local valid=IsValid(w)
    local s=valid and state.guns[w] or empty
    local primary=valid and w:GetPrimaryAmmoType() or -1 local secondary=valid and w:GetSecondaryAmmoType() or -1
    state.reason=reason or state.reason or "ready"
    local d=state.debug
    local physical=not forceOff and allowed(ply,state) and valid and w:GetOwner()==ply and R.Guns[w:GetClass()]~=nil or false
    d.class,d.physical=valid and w:GetClass() or "",physical
    d.clip=valid and (R.Guns[w:GetClass()] and R.Guns[w:GetClass()].kind=="rpg" and (s.loaded and 1 or 0) or w:Clip1()) or -1
    d.reserve=primary>=0 and ply:GetAmmoCount(primary) or 0
    d.secondary=secondary>=0 and ply:GetAmmoCount(secondary) or -1
    d.ejected,d.holding,d.hold_since=s.ejected==true,s.applied~=nil,s.holdSince or 0
    d.command_primary=s.applied and s.applied-CurTime() or 0
    d.held=state.held and state.held.token or 0
    d.last_operation,d.last_insertion=state.reason,state.lastInsertion or "none"
    d.insertions,d.accepted,d.refused=state.insertions or 0,state.accepted or 0,state.refused or 0
    local p=ctx.Players[ply]
    d.zone=p and R.Zone(p.head,heldPose(p,R.Opposite(state.main)),p.scale) or false
    d.distance=state.distance or -1 d.guns=0 for _ in pairs(state.guns) do d.guns=d.guns+1 end
    local remaining=ply.GetInternalVariable and ply:GetInternalVariable("m_flNextAttack")
    local ready=not R.Finite(remaining) or remaining<=0
    local configured=not forceOff and state.enabled and ply:Alive() and not ply:InVehicle() and valid and w:GetOwner()==ply and R.Guns[w:GetClass()]~=nil and now-(state.configAt or -10)<=R.SHORT_LAPSE or false
    local reply=state.reply or empty
    local heartbeat=state.forceReply or now-(state.sentAt or -10)>=.5 or forceOff
    local v=state.wire
    local clip,reserve,secondaryWire=integer(d.clip,16),integer(d.reserve,24),integer(d.secondary,24)
    local changed=v.configured~=configured or v.serial~=(reply.serial or 0) or v.reply~=(reply.reason or "none") or v.ready~=ready or v.w~=w or v.physical~=physical or v.ejected~=d.ejected or v.loaded~=(s.loaded==true) or v.holding~=d.holding or v.since~=d.hold_since or v.token~=d.held or v.clip~=clip or v.reserve~=reserve or v.secondary~=secondaryWire or v.reason~=d.last_operation or v.insertion~=d.last_insertion or v.pulse~=(state.pulse or 0) or v.ejects~=(s.ejects or 0) or v.action~=(reply.kind or 7)
    if changed or heartbeat then
        v.ready,v.configured,v.serial,v.reply=ready,configured,reply.serial or 0,reply.reason or "none"
        v.w,v.physical,v.ejected,v.loaded,v.holding,v.since,v.token=w,physical,d.ejected,s.loaded==true,d.holding,d.hold_since,d.held
        v.clip,v.reserve,v.secondary,v.reason,v.insertion=clip,reserve,secondaryWire,d.last_operation,d.last_insertion
        v.pulse,v.ejects,v.action=state.pulse or 0,s.ejects or 0,reply.kind or 7
        state.lease=((state.lease or 0)+1)%65536 state.sentAt=now
        ctx.Net.Send(ply,R.STATE,function(n)
            n.WriteEntity(w) n.WriteBool(physical) n.WriteBool(v.ejected) n.WriteBool(v.loaded)
            n.WriteBool(v.holding) n.WriteFloat(v.since) n.WriteUInt(v.token,16)
            n.WriteInt(v.clip,16) n.WriteInt(v.reserve,24) n.WriteInt(v.secondary,24)
            n.WriteString(v.reason) n.WriteString(v.insertion)
            n.WriteUInt(v.pulse,16) n.WriteUInt(v.ejects,16) n.WriteUInt(v.action,3) n.WriteUInt(state.lease,16) n.WriteBool(v.ready) n.WriteBool(v.configured) n.WriteUInt(v.serial,16) n.WriteString(v.reply)
        end)
    end
    state.reportAt,state.dirty,state.forceReply=now,false,false
end
local function usable(ply, state, w)
    if not state.enabled or RealTime() - (state.configAt or -10) > R.ACK_LEASE then return false, "disabled" end
    if not IsValid(w) or ply:GetActiveWeapon() ~= w or w:GetOwner()~=ply or not R.Guns[w:GetClass()] then return false, "weapon" end
    if not ply:Alive() or ply:InVehicle() then return false, "player" end
    local p = ctx.Players[ply]
    if not p or not p.lastSync or CurTime() - p.lastSync > 0.25 then return false, "stale" end
    if not p.head.valid or not p.hands[state.main].valid or not p.hands[R.Opposite(state.main)].valid then return false, "tracking" end
    return true
end
local function action(ply)
    local kind, w, token = net.ReadUInt(2), net.ReadEntity(), net.ReadUInt(16)
    local serial=net.ReadUInt(16)
    local state = players[ply]
    if not state then return end
    local reply=state.reply
    if reply and reply.serial==serial and reply.weapon==w and reply.kind==kind and reply.reason~="rate" then
        state.forceReply=true report(ply,state) return
    end
    local ok, reason = usable(ply, state, w)
    if ok and (state.actionTick == engine.TickCount() or RealTime() - (state.actionAt or -10) < 0.08) then ok, reason = false, "rate" end
    if ok then
        state.actionTick, state.actionAt = engine.TickCount(), RealTime()
        local p, data, s = ctx.Players[ply], R.Guns[w:GetClass()], gun(state, w)
        local off = R.Opposite(state.main)
        local pose = heldPose(p, off)
        local grip = bit.band(p.hands[off].buttons or 0, 1) ~= 0
        local reserve = ply:GetAmmoCount(w:GetPrimaryAmmoType())
        if data.kind ~= "rpg" and w:Clip1() > 0 and s.ejected then s.ejected=false release(w,s) end
        if kind == 0 then
            if data.kind ~= "clip" then ok, reason = false, "no-magazine"
            elseif s.ejected then ok, reason = false, "ejected"
            else
                -- SetAmmo deliberately preserves rounds even at the engine's pickup reserve cap.
                ply:SetAmmo(reserve + math.max(0, w:Clip1()), w:GetPrimaryAmmoType()) w:SetClip1(0) s.ejected = true
                state.ejectSerial = (state.ejectSerial or 0) % 65535 + 1
                s.ejects = state.ejectSerial
                reason = "ejected"
            end
        elseif kind == 1 then
            if state.held then ok, reason = false, "already-holding"
            elseif ctx.Holding and IsValid(ctx.Holding(ply, off)) then ok, reason = false, "occupied"
            elseif not grip or not R.Zone(p.head, pose, p.scale) then ok, reason = false, "zone"
            elseif reserve <= 0 then ok, reason = false, "reserve"
            else
                state.serial = (state.serial or 0) % 65535 + 1
                state.held = {weapon = w, token = state.serial, since = RealTime()}
                reason = "taken"
            end
        elseif kind == 2 then
            if not state.held or state.held.weapon ~= w or token ~= state.held.token then ok, reason = false, "token"
            elseif RealTime() - state.held.since > 30 then ok, reason = false, "stale-ammo" state.held = nil
            elseif not grip then ok, reason = false, "grip"
            elseif reserve <= 0 then ok, reason = false, "reserve"
            elseif ctx.Holding and IsValid(ctx.Holding(ply, off)) then ok, reason = false, "occupied"
            elseif data.kind == "clip" and not s.ejected then ok, reason = false, "magazine-present"
            elseif data.kind == "rpg" and s.loaded then ok, reason = false, "full"
            else
                local weaponPose = ctx.Weapon and ctx.Weapon(ply)
                local port, angle = R.ServerPort(w, data, weaponPose and weaponPose.muzzle, p.scale)
                ok, reason, state.distance = R.Close(pose, port, angle, p.scale, true)
                if ok then
                    local skip = {ply, w}
                    for _, hand in ipairs({"left", "right"}) do
                        local h = p.interact and p.interact[hand]
                        if h and IsValid(h.proxy) then skip[#skip + 1] = h.proxy end
                    end
                    local tr = util.TraceLine({start = pose.pos, endpos = port, filter = skip, mask = MASK_SOLID})
                    if tr.Hit or tr.StartSolid or tr.AllSolid then ok, reason = false, "obstructed" end
                end
                if ok then
                    local clip, add = R.Transfer(data, w:Clip1(), reserve, w:GetMaxClip1())
                    if data.kind ~= "rpg" and add <= 0 then ok, reason = false, "full"
                    else
                        if data.kind ~= "rpg" then w:SetClip1(clip) ply:RemoveAmmo(add, w:GetPrimaryAmmoType()) end
                        -- RPG has no clip: its own PrimaryAttack consumes one reserve rocket.
                        s.loaded, s.ejected, state.held = true, false, nil
                        field(w, "m_bInReload", false) field(w, "m_bMustReload", false)
                        if data.kind == "shotgun" and w:Clip1() == 1 then field(w, "m_bNeedPump", false) end
                        field(w, "m_bDelayedFire1", false) field(w, "m_bDelayedFire2", false)
                        release(w, s) sound.Play(data.sound, port)
                        state.pulse = ((state.pulse or 0) + 1) % 65536
                        state.insertions = (state.insertions or 0) + 1
                        reason = "inserted"
                    end
                end
            end
        else state.held = nil reason = "dropped" end
    end
    if kind == 2 then state.lastInsertion = reason end
    if ok then state.accepted = (state.accepted or 0) + 1 else state.refused = (state.refused or 0) + 1 end
    state.reply={serial=serial,weapon=w,kind=kind,reason=reason}
    state.forceReply=true
    report(ply, state, reason, kind)
end
function module.Start(context)
    if not context.Weapon then return end
    ctx,players,owners,fieldCache=context,{},setmetatable({},{__mode="k"}),setmetatable({},{__mode="k"})
    for _,data in pairs(R.Guns) do if util.PrecacheModel then util.PrecacheModel(data.ammo) end end
    ctx.Debug.reload={}
    local function add(w,ply)
        local state=players[ply]
        if state and IsValid(w) and R.Guns[w:GetClass()] then gun(state,w).owned=true state.dirty=true end
    end
    ctx.On("OnStart",function(ply)
        local state={ply=ply,enabled=false,physical=false,main="right",guns={},debug={},wire={}}
        players[ply]=state ctx.Debug.reload[ply:EntIndex()]=state.debug
        for _,w in ipairs(ply:GetWeapons()) do add(w,ply) end
    end)
    ctx.On("OnStop",function(ply) local state=players[ply] if state then suspend(ply,true) report(ply,state,"stopped",nil,true) end players[ply]=nil ctx.Debug.reload[ply:EntIndex()]=nil end)
    ctx.On("OnDeath",function(ply) suspend(ply,true) end)
    ctx.On("OnSpawn",function(ply) suspend(ply,false) for _,w in ipairs(ply:GetWeapons()) do add(w,ply) end end)
    ctx.hook("WeaponEquip",add)
    ctx.hook("PlayerDroppedWeapon",function(ply,w)
        local state=players[ply] local s=state and state.guns[w]
        if s then release(w,s) s.owned=false state.dirty=true end
    end)
    ctx.hook("EntityRemoved",function(w)
        local ply=owners[w] local state=ply and players[ply]
        if state and state.guns[w] then release(w,state.guns[w]) state.guns[w]=nil state.dirty=true end
        owners[w],fieldCache[w]=nil,nil
    end)
    ctx.Net.On(R.CONFIG,function(ply)
        local enabled,left=net.ReadBool(),net.ReadBool() local state=players[ply] if not state then return end
        local main=left and "left" or "right"
        if enabled~=state.enabled or main~=state.main then suspend(ply,false) end
        state.enabled,state.main,state.configAt=enabled,main,RealTime()
        report(ply,state)
    end)
    ctx.Net.On(R.ACTION,action)
    ctx.hook("StartCommand",function(ply,cmd)
        local state=players[ply] if not state then return end
        local enabled=allowed(ply,state) local active=ply:GetActiveWeapon() local now,gameNow=RealTime(),CurTime()
        if enabled~=state.control then
            if not enabled then
                local grace=ctx.Weapon and state.enabled and ply:Alive() and not ply:InVehicle() and now-(state.configAt or -10)<=R.SHORT_LAPSE
                suspend(ply,false,grace)
            end
            state.control,state.dirty=enabled,true
            for _,s in pairs(state.guns) do s.checkAt=nil end
        end
        if state.active~=active then state.held,state.active,state.dirty=nil,active,true end
        local count=0
        for w,s in pairs(state.guns) do
            if not IsValid(w) then release(w,s) state.guns[w],owners[w]=nil,nil state.dirty=true
            else
                local owned=w:GetOwner()==ply
                if not owned then if s.owned then release(w,s) s.owned=false state.dirty=true end
                else
                    s.owned=true count=count+1
                    local data=R.Guns[w:GetClass()] local clip,reserve=w:Clip1(),ply:GetAmmoCount(w:GetPrimaryAmmoType())
                    local changed=clip~=s.clip or reserve~=s.reserve
                    if changed then state.dirty=true end
                    if data.kind=="rpg" and (reserve<=0 or reserve<s.reserve) then s.loaded=false end
                    if data.kind~="rpg" and clip>0 and s.ejected then s.ejected=false release(w,s) end
                    s.clip,s.reserve=clip,reserve
                    if enabled then
                        -- ItemHolsterFrame ignores the primary deadline: refresh every stock gun.
                        if not s.holsterAt or gameNow-s.holsterAt>=.5 then field(w,"m_flHolsterTime",0) s.holsterAt=gameNow end
                        if w==active then
                            cmd:RemoveKey(IN_RELOAD)
                            if changed or not s.checkAt or now-s.checkAt>=.1 then
                                clearFlag(w,"m_bInReload") clearFlag(w,"m_bMustReload") s.checkAt=now
                            end
                        end
                        if not s.applied and w:GetNextPrimaryFire()-gameNow>R.HOLD_MARK then
                            s.applied,s.prior,s.holdSince=w:GetNextPrimaryFire(),gameNow,gameNow
                        end
                        local needs=data.kind=="rpg" and not s.loaded or data.kind~="rpg" and clip<=0 or s.ejected
                        if needs then
                            local observed=w:GetNextPrimaryFire()
                            if not s.applied or observed~=s.applied or observed<=gameNow+1 then
                                local prior=observed-gameNow>R.HOLD_MARK and gameNow or observed
                                if not s.applied then s.prior=prior else s.prior=math.max(s.prior or 0,prior) end
                                s.holdSince=s.holdSince or gameNow
                                w:SetNextPrimaryFire(math.max(gameNow+R.HOLD_SECONDS,s.prior or 0));s.applied=w:GetNextPrimaryFire()

                            end
                        else release(w,s) end
                    else release(w,s) end
                end
            end
        end
        local off=ctx.Players[ply].hands[R.Opposite(state.main)]
        local carryGrace=state.enabled and ply:Alive() and not ply:InVehicle() and now-(state.configAt or -10)<=R.SHORT_LAPSE
        if state.held then
            if off.valid then state.held.invalidAt=nil else state.held.invalidAt=state.held.invalidAt or now end
            local stalePose=state.held.invalidAt and now-state.held.invalidAt>R.SHORT_LAPSE
            if (not enabled and not carryGrace) or now-state.held.since>30 or stalePose or off.valid and bit.band(off.buttons or 0,1)==0 then state.held=nil state.dirty=true end
        end
        state.debug.guns=count
        if state.dirty or not state.reportAt or now-state.reportAt>=.1 then report(ply,state) end
        local current=state.guns[active]
        state.debug.command_primary=current and current.applied and current.applied-gameNow or 0
    end)
end
function module.Stop()
    if players then for ply,state in pairs(players) do suspend(ply,true) pcall(report,ply,state,"stopped",nil,true) end end
    if ctx then ctx.Debug.reload=nil end
    ctx,players,owners,fieldCache=nil,nil,nil,nil
end
return module
