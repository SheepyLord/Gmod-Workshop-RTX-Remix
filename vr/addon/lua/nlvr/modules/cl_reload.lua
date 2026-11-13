local module = {name = "reload", order = 46}
local R = include("nlvr/modules/sh_reload.lua")
local ctx, overlay, values, signature, heldModel, drops, ack, active, pending, queued, lastConfig, configAt, sentAt
local tapB, secondary, zone, lastPulse, paints, lastAction
local ejections
local discarded
local hapticOK, hapticError
local counterError, inflight, aGesture, bPhysical, lastFrameAt, requestSerial
local valueBuffer,lastClip,lastReserve,lastSecondary
local ammoLengths = {weapon_pistol = 0.12, weapon_357 = 0.07, weapon_smg1 = 0.16, weapon_ar2 = 0.14,
    weapon_shotgun = 0.065, weapon_crossbow = 0.5, weapon_rpg = 0.65}
local function physical(a)
    local p=LocalPlayer()
    return a and R.Guns[a.class]~=nil and ctx.Settings.physical_reload~=0 and p:Alive() and not p:InVehicle()
        and ack and ack.weapon==a.ent and ack.physical and RealTime()-ack.at<=R.ACK_LEASE or false
end
local function gesturePolicy(a)
    local p=LocalPlayer()
    return a and R.Guns[a.class] and ctx.Settings.physical_reload~=0 and p:Alive() and not p:InVehicle()
        and ack and ack.weapon==a.ent and ack.configured and RealTime()-ack.at<=R.SHORT_LAPSE or false
end
local function aPolicy(a)
    local p=LocalPlayer()
    if not a or not R.Guns[a.class] or R.Guns[a.class].kind~="clip" or ctx.Settings.physical_reload==0 or not p:Alive() or p:InVehicle() then return false end
    return not ack or ack.weapon~=a.ent or RealTime()-ack.at>R.ACK_LEASE or ack.configured
end
local function carryingAmmo(a)
    return gesturePolicy(a) and ack.token~=0 and not (discarded and discarded.weapon==ack.weapon and discarded.token==ack.token)
end
local function buttonReady(p)
    if ack and RealTime()-ack.at<=R.ACK_LEASE and ack.buttonReady==false then return false end
    -- Client datamap exposes an absolute deadline; server ACK uses its relative save value.
    local deadline=p.GetInternalVariable and p:GetInternalVariable("m_flNextAttack")
    if R.Finite(deadline) then return deadline<=CurTime() end
    if ack and RealTime()-ack.at<=R.ACK_LEASE then return ack.buttonReady end
    return true -- no live K server: preserve the ordinary engine input path
end
local function removeHeld()
    if ctx then for _, hand in pairs(ctx.Hand) do
        if hand.held and (hand.held.nlvr_reload or IsValid(heldModel) and hand.held.ent == heldModel) then
            hand.held, hand.grip_curls = nil, nil
        end
    end end
    if IsValid(heldModel) then heldModel:Remove() end heldModel = nil
end
local function queue(kind)
    if active and (not queued or kind==3) then
        if inflight and inflight.kind==kind and inflight.weapon==active.ent then return end
        requestSerial=requestSerial%65535+1
        queued={kind=kind,weapon=active.ent,token=ack and ack.token or 0,serial=requestSerial}
    end
end
local function ammoScale(data, model)
    if model.nlvrAmmoScale then return model.nlvrAmmoScale end
    if model.GetModelBounds then
        local low, high = model:GetModelBounds()
        local size = high - low
        local extent = math.max(size.x, size.y, size.z)
        if extent > 0.001 then
            model.nlvrAmmoExtent = extent
            model.nlvrAmmoScale = (ammoLengths[active and active.class] or 0.14) * ctx.Space.scale / extent
            return model.nlvrAmmoScale
        end
    end
    return (data.kind == "clip" and 0.45 or 1) * ctx.Space.scale / 40
end
local function dropModel(data, pos, ang)
    if not pos then return end
    local m = ents.CreateClientProp(data.ammo)
    if not IsValid(m) then return end
    m:SetPos(pos) m:SetAngles(ang) m:SetNoDraw(true)
    local scale = ammoScale(data, m)
    if m.SetModelScale then m:SetModelScale(scale, 0) end
    m:Spawn()
    local phys = m:GetPhysicsObject()
    -- Small stock ammunition meshes need not ship a .phy. Keep them physical
    -- with a cosmetic box rather than leaving an ejected item floating in place.
    if not IsValid(phys) and m.PhysicsInitBox and m.GetModelBounds then
        local low, high = m:GetModelBounds()
        m:PhysicsInitBox(low * scale, high * scale) phys = m:GetPhysicsObject()
    end
    if m.SetCollisionGroup then m:SetCollisionGroup(COLLISION_GROUP_DEBRIS) end
    if IsValid(phys) then
        phys:EnableMotion(true) phys:EnableGravity(true) phys:SetVelocity(Vector(0, 0, -35)) phys:Wake()
    end
    drops[#drops + 1] = {model = m, untilTime = CurTime() + 10}
end
local function ammoValues(active)
    if not active or not IsValid(active.ent) then return end
    local w, p = active.ent, LocalPlayer()
    local primary, secondaryType = w:GetPrimaryAmmoType(), w:GetSecondaryAmmoType()
    if primary < 0 and secondaryType < 0 then return end
    local clip = w:Clip1()
    if active.kind == "rpg" and ack and ack.weapon == w and physical(active) then clip = ack.loaded and 1 or 0 end
    local reserve = primary >= 0 and p:GetAmmoCount(primary) or -1
    if active.kind == "rpg" and clip >= 0 then reserve = math.max(0, reserve - clip) end
    valueBuffer[1],valueBuffer[2],valueBuffer[3]=clip,reserve,secondaryType>=0 and p:GetAmmoCount(secondaryType) or -1
    return valueBuffer
end
local function counter()
    local active = ctx.Weapon and ctx.Weapon.Active
    values = ammoValues(active)
    local wheel = ctx.Overlay.Objects.wheel
    local show = values and ctx.Settings.ammo_counter ~= 0 and not (wheel and wheel.visible)
        and active and IsValid(active.model) and ctx.Pose.head and ctx.Pose.head.valid
    if not show then if overlay and overlay.visible then overlay:Show(false) end return end
    if not overlay then
        local size = ctx.Overlay.Sizes.ammo
        overlay = ctx.Overlay.New{key = "ammo", name = "Weapon ammunition", width = size[1], height = size[2],
            device = active.hand, metres = 0.16, clear = {12, 18, 26, 235}, paint = function(_, width)
                if counterError then return end
                local ok,err=pcall(function()
                if not values then return end
                paints = paints + 1
                local primary = values[1] >= 0 and tostring(values[1]) .. " / " .. tostring(values[2]) or tostring(values[2])
                draw.SimpleText(primary, "NLVRAmmoValue", width / 2, 8, color_white, TEXT_ALIGN_CENTER)
                if values[3] >= 0 then draw.SimpleText("+ " .. values[3], "NLVRAmmoSecondary", width / 2, 82,
                    Color(164, 213, 229), TEXT_ALIGN_CENTER) end
                end)
                if not ok then counterError=tostring(err) end
            end}
    end
    if values[1]~=lastClip or values[2]~=lastReserve or values[3]~=lastSecondary then
        overlay:Invalidate() lastClip,lastReserve,lastSecondary=values[1],values[2],values[3]
    end
    local data = R.Guns[active.class]
    local beside = Vector(0, active.hand == "right" and 4.4 or -4.4, 3.2) -- 11 cm inward, 8 cm above
    if data and data.frame then beside = WorldToLocal(beside, Angle(), Vector(), data.frame) end
    local offset = ((data and data.port or Vector()) + beside) * (active.model.GetModelScale and active.model:GetModelScale() or 1)
    local position = LocalToWorld(offset, Angle(), active.model:GetPos(), active.model:GetAngles())
    local angle = (position - ctx.Pose.head.pos):Angle()
    local tracking, rotation = ctx.ToTracking(position, angle)
    local raw = ctx.Pose[active.hand] and ctx.Pose[active.hand].raw
    if raw then
        local pos, ang = WorldToLocal(tracking, rotation, raw.pos, raw.ang)
        overlay:Place(active.hand, pos, ang, 0.16)
        if not overlay.visible then overlay:Show(true) end
    elseif overlay.visible then overlay:Show(false) end
end
local function safeCounter()
    if not counterError then
        local ok,err=pcall(counter)
        if not ok then counterError=tostring(err) end
    end
    if counterError then
        local o=overlay or ctx.Overlay.Objects.ammo
        if o then pcall(o.Destroy,o) end
        overlay=nil
        ctx.Debug.reload=ctx.Debug.reload or {}
        ctx.Debug.reload.counter_error=counterError
    end
end
function module.Start(context)
    -- Reload points and control ownership require W. A failed/absent weapon module
    -- must leave ordinary reload alone rather than register half of this feature.
    if not context.Weapon then return end
    ctx, drops, ack, pending, queued, ejections = context, {}, nil, nil, nil, {}
    discarded, counterError, inflight = nil, nil, nil
    aGesture,bPhysical,lastFrameAt,requestSerial=nil,nil,RealTime(),0
    valueBuffer,lastClip,lastReserve,lastSecondary={},nil,nil,nil
    hapticOK, hapticError = nil, nil
    active, lastConfig, configAt, sentAt, lastPulse, paints, signature = nil, nil, -10, -10, 0, 0, nil
    tapB, secondary, lastAction = false, false, "ready"
    surface.CreateFont("NLVRAmmoValue", {font = "Tahoma", size = 60, weight = 700, extended = true})
    surface.CreateFont("NLVRAmmoSecondary", {font = "Tahoma", size = 33, weight = 600, extended = true})
    ctx.Net.On(R.STATE, function()
        local s = {weapon = net.ReadEntity(), physical = net.ReadBool(), ejected = net.ReadBool(), loaded = net.ReadBool(),
            holding = net.ReadBool(), holdSince = net.ReadFloat(), token = net.ReadUInt(16),
            clip = net.ReadInt(16), reserve = net.ReadInt(24), secondary = net.ReadInt(24),
            reason = net.ReadString(), insertion = net.ReadString(), pulse = net.ReadUInt(16),
            ejects = net.ReadUInt(16), action = net.ReadUInt(3), lease = net.ReadUInt(16), buttonReady = net.ReadBool(), configured = net.ReadBool(), replySerial=net.ReadUInt(16), replyReason=net.ReadString(), at = RealTime()}
        local data = active and R.Guns[active.class]
        if active and s.weapon == active.ent then
            if s.ejected and s.ejects ~= (ejections[s.weapon] or 0) and data then
                local pos, ang = R.Point(active.model, data, "eject") dropModel(data, pos, ang)
            end
            ejections[s.weapon] = s.ejects
            if pending and (s.reason == "taken" or RealTime() - pending.since > 1 or s.reason == "reserve") then pending = nil end
            if s.pulse ~= lastPulse and s.pulse ~= 0 and ctx.native.Haptic then
                hapticOK, hapticError = ctx.native.Haptic(ctx.Input.offHand, 0.035, 140, 0.45)
            end
            lastPulse = s.pulse
        end
        if inflight and inflight.weapon==s.weapon and inflight.serial==s.replySerial then
            if s.replyReason=="rate" then inflight.retryAt=RealTime()+.12
            else inflight=nil end
        end
        ack, lastAction = s, s.reason
        if s.token == 0 then discarded = nil end
    end)
    -- P resolves first (200), W's foregrip pose last (300). Carried ammo is an
    -- occupied shown hand, so approaching a rifle cannot turn it into a foregrip.
    ctx.resolver(250, function(hand, shown)
        local carrying=active and carryingAmmo(active)
        if hand == ctx.Input.offHand and carrying and ctx.Input.off.grip then
            -- A grant can arrive before our next frame creates the visual model.
            -- Occupy the hand now, before W's earlier frame callback claims a foregrip.
            shown.held = {ent = heldModel, bone = 0, nlvr_reload = true}
            shown.grip_curls = {0.7, 0.85, 0.85, 0.85, 0.85}
        end
    end)
    ctx.On("frame", function()
        if not ctx.Weapon then error("Weapon module stopped; physical reload released") end
        local gap=RealTime()-(lastFrameAt or RealTime()) lastFrameAt=RealTime()
        if aGesture and aGesture.finished then aGesture=nil end
        local nextActive = ctx.Weapon and ctx.Weapon.Active
        if not nextActive or not active or nextActive.ent ~= active.ent or nextActive.hand ~= active.hand then
            pending, queued, ack, tapB = nil, nil, nil, false removeHeld()
        end
        active = nextActive
        secondary, zone = false, false
        local dropPhysics, dropPosition, dropLife = 0, nil, nil
        for i = #drops, 1, -1 do
            if CurTime() >= drops[i].untilTime or not IsValid(drops[i].model) then
                if IsValid(drops[i].model) then drops[i].model:Remove() end table.remove(drops, i)
            else
                if IsValid(drops[i].model:GetPhysicsObject()) then dropPhysics = dropPhysics + 1 end
                local pos = drops[i].model:GetPos()
                dropPosition, dropLife = {pos.x, pos.y, pos.z}, drops[i].untilTime - CurTime()
            end
        end
        local p = LocalPlayer()
        if not active or not IsValid(active.ent) or not p:Alive() then
            pending, queued, ack, tapB = nil, nil, nil, false removeHeld()
            local d=ctx.Debug.reload or {} ctx.Debug.reload=d
            d.physical,d.held,d.holding,d.zone,d.paints=false,0,false,false,paints
            d.last_insertion,d.last_operation="none",lastAction
            return
        end
        local input, main, off = ctx.Input, ctx.Input.mainHand, ctx.Input.offHand
        local enabled, data = physical(active), R.Guns[active.class]
        local policy=gesturePolicy(active)
        if input.main.pressed.a then aGesture={weapon=active.ent,hand=main,owned=aPolicy(active),cancelled=false} end
        if aGesture and aGesture.owned then
            input.Claim(aGesture.hand,"a",ctx.name)
            if gap>.5 or not enabled or aGesture.weapon~=active.ent or aGesture.hand~=main then aGesture.cancelled=true end
            secondary=not aGesture.cancelled and input.Held(main,"a",.3)
            if input.main.released.a then
                if not aGesture.cancelled and (input.main.held.a or 0)<.3 then queue(0) end
                aGesture.finished=true
            end
        elseif aPolicy(active) and not input.main.a then input.Claim(main,"a",ctx.name) end
        if input.main.pressed.b then bPhysical=policy end
        -- Render frames can run between user commands. Retain a tap until one
        -- mover consumes it, while re-establishing the claim each input frame.
        if tapB and (enabled or tapB.weapon ~= active.ent or tapB.hand ~= main) then tapB = false end
        if input.Tapped(main, "b") and (input.main.held.b or 0) < 0.3 and not enabled and not bPhysical then
            tapB = {weapon = active.ent, hand = main}
        end
        if tapB and not input.Claim(main, "b", ctx.name) then tapB = false end
        local carrying=carryingAmmo(active)
        if enabled or carrying then
            local pose = ctx.Hand[off] and ctx.Hand[off].shown or ctx.Pose[off]
            zone = R.Zone(ctx.Pose.head, pose, ctx.Space.scale)
            -- Token rendering/ownership has a bounded short-lapse grace; inventory
            -- gestures still require a fresh physical-active acknowledgement.
            local shown=ctx.Hand[off]
            local interaction=ctx.Debug.interact and ctx.Debug.interact[off]
            local owner=input.Owner(off,"grip")
            local free=not (shown and shown.held and not shown.held.nlvr_reload)
                and not (interaction and (interaction.climbing or interaction.pulling or (interaction.gloves_target or 0)>0 or (interaction.held or 0)>0))
                and (not owner or owner==ctx.name)
            if free and (zone or carrying or pending) and input.Claim(off, "grip", ctx.name) then
                if enabled and input.off.grip and zone and not carrying and not pending and p:GetAmmoCount(active.ent:GetPrimaryAmmoType()) > 0
                    and not (ctx.Hand[off] and ctx.Hand[off].held) then
                    pending = {since = RealTime()} queue(1)
                end
                if enabled and pending and not carrying and input.off.grip and zone and RealTime() - sentAt > 0.18 then queue(1) end
                if carrying and input.off.grip then
                    if not IsValid(heldModel) then
                        heldModel = ClientsideModel(data.ammo, RENDERGROUP_OPAQUE)
                        if IsValid(heldModel) then heldModel:SetNoDraw(true) end
                    end
                    if IsValid(heldModel) and pose and pose.valid then
                        heldModel:SetPos(pose.pos) heldModel:SetAngles(pose.ang)
                        if heldModel.SetModelScale then heldModel:SetModelScale(ammoScale(data, heldModel), 0) end
                    end
                    local port, angle = R.Point(active.model, data)
                    if enabled and R.Close(pose, port, angle, ctx.Space.scale, false) and RealTime() - sentAt > 0.15 then queue(2) end
                elseif carrying then
                    if pose and pose.valid then dropModel(data, pose.pos, pose.ang) end
                    discarded = {weapon = ack.weapon, token = ack.token}
                    queue(3) removeHeld()
                end
                if not input.off.grip then pending = nil end
            end
            if not carrying then removeHeld() end
        else pending = nil removeHeld() end
        local d=ctx.Debug.reload or {} ctx.Debug.reload=d
        d.class,d.physical=active.class,enabled==true
        d.ejected,d.clip,d.reserve=ack and ack.ejected or false,active.ent:Clip1(),p:GetAmmoCount(active.ent:GetPrimaryAmmoType())
        d.hold_since,d.hold_time=ack and ack.holdSince or 0,ack and ack.holding and CurTime()-ack.holdSince or 0
        d.holding,d.zone,d.held=ack and ack.holding or false,zone,ack and ack.token or 0
        d.last_insertion,d.last_operation=ack and ack.insertion or "none",lastAction
        d.paints,d.dropped,d.secondary=paints,#drops,secondary
        d.haptic_ok,d.haptic_error,d.counter_values=hapticOK,hapticError,values
        d.held_metres=IsValid(heldModel) and heldModel.nlvrAmmoExtent and heldModel:GetModelScale()*heldModel.nlvrAmmoExtent/ctx.Space.scale or 0
        d.drop_physics,d.drop_pos,d.drop_life=dropPhysics,dropPosition,dropLife

    end)
    ctx.mover(70, function(cmd)
        local enabled = ctx.Settings.physical_reload ~= 0
        local config = tostring(enabled) .. ctx.Input.mainHand
        if config ~= lastConfig or RealTime() - configAt > 0.5 then
            ctx.Net.Send(R.CONFIG, function(n) n.WriteBool(enabled) n.WriteBool(ctx.Input.mainHand == "left") end)
            lastConfig, configAt = config, RealTime()
        end
        if active and IsValid(active.ent) then
            if gesturePolicy(active) then cmd:RemoveKey(IN_RELOAD) end
            if tapB and tapB.weapon == active.ent and tapB.hand == ctx.Input.mainHand and not physical(active)
                and ctx.Input.Owner("main", "b") == ctx.name and
                buttonReady(LocalPlayer()) then
                cmd:AddKey(IN_RELOAD)
                -- Extra/prediction samples have zero command number or tick.
                -- Keep their predicted bit, but consume only a networked command.
                if (not cmd.CommandNumber or cmd:CommandNumber() ~= 0) and
                    (not cmd.TickCount or cmd:TickCount() ~= 0) then tapB = false end
            end
            if aPolicy(active) or (aGesture and aGesture.owned and aGesture.hand==ctx.Input.mainHand) then
                local foregrip = active.twoHanded and ctx.Input.Owner("off", "trigger") == "weapons" and ctx.Input.off.trigger
                cmd:RemoveKey(IN_ATTACK2) if secondary or foregrip then cmd:AddKey(IN_ATTACK2) end
            end
        end
        local now=RealTime()
        if inflight and (inflight.weapon~=active.ent or now>inflight.expires) then inflight=nil lastAction="action-timeout" end
        if not inflight and queued and physical(active) then
            inflight,queued=queued,nil inflight.expires=now+5 inflight.retryAt=now
        end
        if inflight and physical(active) and now>=inflight.retryAt and now-sentAt>=.12 then
            local q=inflight sentAt=now q.retryAt=now+.25
            ctx.Net.Send(R.ACTION,function(n) n.WriteUInt(q.kind,2) n.WriteEntity(q.weapon) n.WriteUInt(q.token,16) n.WriteUInt(q.serial,16) end)
        end

    end)
    ctx.On("before_overlay_paint", safeCounter)
    ctx.hook("PreDrawTranslucentRenderables", function(depth, sky)
        if depth or sky then return end
        if IsValid(heldModel) then heldModel:DrawModel() end
        for _, drop in ipairs(drops) do if IsValid(drop.model) then drop.model:DrawModel() end end
    end)
end
function module.Stop()
    local context = ctx
    inflight,aGesture,bPhysical,valueBuffer=nil,nil,nil,nil
    removeHeld()
    if drops then for _, drop in ipairs(drops) do if IsValid(drop.model) then drop.model:Remove() end end end
    if overlay then overlay:Destroy() end
    if ctx then ctx.Debug.reload = nil end
    ctx, overlay, values, drops, ack, active, queued, pending = nil, nil, nil, nil, nil, nil, nil, nil
    -- Also runs when only K fails and the rest of VR continues. A closing game
    -- channel must not prevent model/overlay cleanup; the server lease is the fallback.
    if context then pcall(context.Net.Send, R.CONFIG, function(n)
        n.WriteBool(false) n.WriteBool(context.Input.mainHand == "left")
    end) end
end
return module
