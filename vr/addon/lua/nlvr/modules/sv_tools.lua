local module = {name = "tools", order = 48}
local Math = include("nlvr/modules/sh_tools_math.lua")
local Rotation = include("nlvr/modules/sv_tools_rotation.lua")
local current
function module.Start(ctx)
    if not ctx.Weapon then return end
    local holds, main, blocked = {}, {}, {}
    current = {ctx = ctx, holds = holds}
    local function receipt(ply, data)
        local hand, prop, target = Angle(), Angle(), Angle()
        if data then hand, prop, target = data.handAngle, data.phys:GetAngles(), data.target end
        ctx.Net.Send(ply, 96, function(w)
            w.WriteEntity(data and data.ent or NULL) w.WriteUInt(data and data.bone or 0, 8)
            w.WriteVector(data and data.localPoint or Vector()) w.WriteFloat(data and data.distance or 0)
            w.WriteAngle(hand) w.WriteAngle(prop) w.WriteAngle(target) w.WriteFloat(data and Math.AngleError(prop, target) or 0)
        end)
    end
    local function release(ply, drop)
        if holds[ply] then
            local data = holds[ply]
            holds[ply] = nil
            blocked[ply] = data.inputHand
            if data.control then data.control.Stop() end
            if drop and IsValid(data.ent) then data.ent:ForcePlayerDrop() end
            receipt(ply)
        end
        ctx.Debug.tools = ctx.Debug.tools or {} ctx.Debug.tools[ply:EntIndex()] = nil
    end
    current.release = release
    ctx.Net.On(97, function(ply)
        local hand = net.ReadBool() and "left" or "right"
        if main[ply] ~= hand then release(ply, true) end
        main[ply] = hand
    end)
    ctx.hook("OnPhysgunPickup", function(ply, ent)
        local state = ctx.Players[ply]
        local weapon = state and ctx.Weapon and ctx.Weapon(ply)
        local pose = state and state.hands[main[ply] or "right"]
        if not weapon or weapon.kind ~= "physgun" or not pose or not pose.valid or not IsValid(ent) then return end
        local trace = ply:GetEyeTrace()
        local bone = trace.Entity == ent and trace.PhysicsBone or 0
        local phys = ent:GetPhysicsObjectNum(bone)
        if not IsValid(phys) then return end
        -- A repeated pickup notification must not orphan the previous helper, even
        -- when an add-on/engine transition has not delivered the old drop hook yet.
        local previous = holds[ply]
        if previous then
            holds[ply] = nil
            if previous.control then previous.control.Stop() end
        end
        local point = trace.Entity == ent and trace.HitPos or phys:GetPos()
        local localPoint = WorldToLocal(point, Angle(), phys:GetPos(), phys:GetAngles())
        local data = {ent = ent, phys = phys, bone = bone, localPoint = localPoint,
            inputHand = main[ply] or "right",
            relative = Math.Relative(phys:GetAngles(), pose.ang), handAngle = pose.ang, target = phys:GetAngles(),
            distance = (point - weapon.muzzle.pos):Length()}
        local control, err = Rotation.New(ctx, ply, data, main[ply] or "right")
        if not control then
            MsgN("[nlvr] tools rotation: " .. tostring(err))
            blocked[ply] = data.inputHand
            -- The successful-pickup hook can precede the native held flag. Keep
            -- this failed hold owned until Tick, then force-drop after attachment.
            holds[ply] = data
            receipt(ply, data) return
        end
        data.control, holds[ply] = control, data
        receipt(ply, data)
        -- No return: successful native pickup is only observed, never approved here.
    end)
    ctx.hook("PhysgunDrop", function(ply) release(ply) end)
    ctx.On("OnStop", function(ply) release(ply, true) main[ply], blocked[ply] = nil, nil end)
    ctx.On("OnDeath", function(ply) release(ply, true) end)
    -- K also owns a StartCommand hook, under its own id, for reload/clip gating.
    -- This hook only prevents reacquisition from a trigger already consumed by a drop.
    ctx.hook("StartCommand", function(ply, cmd)
        local hand, state = blocked[ply], ctx.Players[ply]
        if not hand then return end
        local pose = state and state.hands[hand]
        if pose and pose.valid and bit.band(pose.buttons or 0, 2) == 0 and not cmd:KeyDown(IN_ATTACK) then
            blocked[ply] = nil
        else cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_ATTACK))) end
    end)
    ctx.hook("Tick", function()
        for ply, data in pairs(holds) do
            local state = ctx.Players[ply]
            local weapon = state and ctx.Weapon and ctx.Weapon(ply)
            local pose = state and state.hands[main[ply] or "right"]
            if not IsValid(ply) or not ply:Alive() or not weapon or weapon.kind ~= "physgun" or
                not pose or not pose.valid or not IsValid(data.ent) or not IsValid(data.phys) or not data.ent:IsPlayerHolding() or
                not data.control or not IsValid(data.control.entity) or data.control.failed then
                release(ply, true)
            else
                local point = LocalToWorld(data.localPoint, Angle(), data.phys:GetPos(), data.phys:GetAngles())
                data.distance = math.Clamp((point - weapon.muzzle.pos):Length(), state.scale * 0.1, 8192)
                data.handAngle, data.target = pose.ang, Math.Follow(data.relative, pose.ang)
                receipt(ply, data)
                ctx.Debug.tools = ctx.Debug.tools or {}
                ctx.Debug.tools[ply:EntIndex()] = {entity = data.ent:EntIndex(), distance = data.distance / state.scale,
                    hand = data.handAngle, prop = data.phys:GetAngles(), target = data.target,
                    difference = Math.AngleError(data.phys:GetAngles(), data.target), controller_calls = data.control.calls}
            end
        end
    end)
end
function module.Stop()
    if not current then return end
    local state = current current = nil
    -- The engine still owns the hold and its drop/freeze hooks; no detached physics body is created.
    for ply in pairs(state.holds) do
        if state.release then state.release(ply, true)
        elseif IsValid(state.holds[ply].ent) then state.holds[ply].ent:ForcePlayerDrop() end
    end
    state.ctx.Debug.tools = nil
end
return module
