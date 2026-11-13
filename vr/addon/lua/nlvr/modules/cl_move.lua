local module = {name = "move", order = 30}
local M = include("nlvr/modules/cl_move_math.lua")
local Basis=include("nlvr/core/sh_move_basis.lua")
function module.Start(ctx)
    -- Movement cannot safely run in an environment without collision queries (e.g. an
    -- isolated camera consumer). Leave the framework's existing camera contract intact.
    if not util.TraceHull or not LocalPlayer().Alive then return end
    local C, input, settings = ctx.core, ctx.Input, ctx.Settings
    local total, lastRaw, lastSequence, roomSeq, roomTick = Vector(), nil, nil, 0, nil
    local turnLatch, downLatch, toggle, physical = false, false, false, false
    local arc, landing, pending, lastTeleport, blockedUntil, fadeUntil = nil, nil, nil, nil, 0, 0
    local opaqueUntil = 0
    local request, lastCommand, lastTurn, standing, desiredSpeed, turnRate = 0, nil, RealTime(), nil, 0, 0
    local roomSpeed, sampledAt = 0, RealTime()
    local visuals = include("nlvr/modules/cl_move_overlay.lua").New(ctx)
    local api = {}
    local headDebug, targetDebug = {}, {}
    local debug = {position = {}, space = {anchor = {}}, room = {}}
    C.Debug.move = debug
    local function xyz(out, v) out[1], out[2], out[3] = v.x, v.y, v.z end
    local prediction = include("nlvr/modules/cl_move_predict.lua").New()
    C.Move = api
    ctx.cleanup(function() if C.Move == api then C.Move = nil end end)
    local function viewFeet(base)
        local ply = LocalPlayer()
        return prediction.Feet(ply, base, total, IsValid(ply) and ply:Alive() and not ply:InVehicle() and
            (ply:GetMoveType() == MOVETYPE_WALK or ply:GetMoveType() == MOVETYPE_NOCLIP))
    end
    C.ViewFeet = viewFeet
    ctx.cleanup(function() if C.ViewFeet == viewFeet then C.ViewFeet = nil end end)
    local function own(hand, control)
        local owner = input.Owner(hand, control)
        return not owner or owner == ctx.name
    end
    local function eyes(ply) return ply:GetViewOffset().z end
    local function stance()
        local base = settings.seated == 1 and settings.seated_offset or 0
        local raw = C.Frame and C.Frame.hmd
        local height = raw and (raw.pos.z - C.Space.anchor.z + base) * C.Space.scale or eyes(LocalPlayer())
        -- Blend away the virtual offset as the person crouches; changing the physical
        -- duck flag must never pop the camera upward. Deeper physical bends remain tracked.
        local duck = toggle and M.CrouchOffset(height, eyes(LocalPlayer()), LocalPlayer():GetViewOffsetDucked().z) / C.Space.scale or 0
        C.Space.seated = base - duck
        C.Refresh()
    end
    local function calibration()
        local raw = C.Frame and C.Frame.hmd
        local ply = LocalPlayer()
        if not raw or not raw.valid or not IsValid(ply) then return false, "tracking" end
        local height = raw.pos.z - C.Space.anchor.z
        local scale = M.Calibration(height, eyes(ply))
        if not scale then return false, "height" end
        -- The native runtime latches world units at Start. Keep stereo and Lua at one scale;
        -- persist the new pair for the next Start instead of changing only the Lua half.
        RunConsoleCommand("nl_vr_height", tostring(height))
        RunConsoleCommand("nl_vr_scale", tostring(scale))
        standing = height
        api.calibration = {height = height, scale = scale, restart = math.abs(scale - C.Space.scale) > 0.001}
        C.Emit("calibrated", api.calibration)
        return true, api.calibration
    end
    api.Calibrate = calibration
    ctx.On("calibrate", calibration)
    ctx.On("height_calibrate", calibration)
    local function heightSetting()
        local cv = GetConVar("nl_vr_scale")
        api.calibration = {height = settings.height, scale = settings.height > 0 and
            M.Calibration(settings.height, eyes(LocalPlayer())) or (cv and cv:GetFloat() or C.Space.scale)}
        api.calibration.restart = math.abs(api.calibration.scale - C.Space.scale) > 0.001
    end
    heightSetting()
    ctx.On("setting", function(name)
        if name == "height" then
            heightSetting()
            if settings.height > 0 then RunConsoleCommand("nl_vr_scale", tostring(api.calibration.scale)) end
        elseif name == "dominant" or name == "teleport" then
            arc, landing, turnLatch, downLatch = nil, nil, false, false visuals.Arc(nil)
        end
    end)
    ctx.Net.On(M.RESULT, function()
        local id, success, reason, target = net.ReadUInt(16), net.ReadBool(), net.ReadString(), net.ReadVector()
        if not pending or id ~= pending.id or not M.Vector(target) then return end
        lastTeleport = {id = id, success = success, reason = reason, target = {target.x, target.y, target.z}, at = RealTime()}
        if pending.mode == 1 then opaqueUntil = RealTime() + 0.08 fadeUntil = opaqueUntil + 0.12 end
        pending = nil C.Emit("teleport", lastTeleport)
    end)
    ctx.Net.On(M.FOLLOW, function()
        local blocked, mode = net.ReadBool(), net.ReadUInt(5)
        local stamp, wall, generation = net.ReadDouble(), net.ReadDouble(), net.ReadUInt(16)
        local function readVector() return Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat()) end
        local consumed, applied, position = readVector(), readVector(), readVector()
        if not prediction.Receive(consumed, applied, position, mode, blocked, stamp, wall, generation) then return end
        C.MoveRevision=(C.MoveRevision or 0)+1
        if blocked then blockedUntil = RealTime() + 0.12 end
        api.follow = {blocked = blocked, position = {position.x, position.y, position.z},
            consumed = {consumed.x, consumed.y, consumed.z}, applied_total = {applied.x, applied.y, applied.z},
            motor_buffer_seconds = prediction.bufferSeconds}
        C.Refresh()
    end)
    local function sample()
        local raw = C.Frame and C.Frame.hmd
        if not raw or not raw.valid then lastRaw, roomSpeed = nil, 0 return end
        if C.Frame.sequence == lastSequence then return end
        lastSequence = C.Frame.sequence
        roomSpeed = 0
        local paused=game.SinglePlayer() and gui and gui.IsGameUIVisible and gui.IsGameUIVisible()
        if not paused and lastRaw and LocalPlayer():Alive() and not LocalPlayer():InVehicle() and LocalPlayer():GetMoveType() == MOVETYPE_WALK then
            local delta = M.Flat(raw.pos - lastRaw)
            if delta:Length() <= 0.25 then
                total = total + M.Rotate(delta, C.Space.yaw or 0) * C.Space.scale
                roomSpeed = delta:Length() * C.Space.scale / math.max(RealTime() - sampledAt, 0.001)
            end
        end
        sampledAt = RealTime()
        lastRaw = Vector(raw.pos.x, raw.pos.y, raw.pos.z)
        standing = standing or (settings.height > 0 and settings.height or raw.pos.z - C.Space.anchor.z)
        -- The tracking delta is consumed once as input; ViewFeet adds the unprocessed
        -- portion for this rendered pose, without waiting for the next server tick.
        C.Space.anchor = Vector(raw.pos.x, raw.pos.y, C.Space.anchor.z)
        physical = settings.seated ~= 1 and M.Crouch(raw.pos.z - C.Space.anchor.z,
            settings.height > 0 and settings.height or standing, physical)
        stance()
    end
    ctx.On("frame", sample)
    local function buttons(cmd, mask) cmd:SetButtons(bit.bor(cmd:GetButtons(), mask)) end
    local function move(cmd)
        local ply, head = LocalPlayer(), C.Pose.head
        if not IsValid(ply) or not head or not head.valid then arc, landing = nil, nil visuals.Arc(nil) return end
        sample()
        local number = cmd:CommandNumber()
        local fresh = number ~= lastCommand
        local now, elapsed = RealTime(), math.Clamp(RealTime() - lastTurn, 0, 0.05)
        if fresh then lastCommand, lastTurn = number, now end
        local disabled = not ply:Alive() or ply:InVehicle()
        desiredSpeed, turnRate = 0, 0
        if disabled then arc, landing = nil, nil visuals.Arc(nil) return end
        if fresh and own("main", "stick") then
            local stick = input.main.stick
            if math.abs(stick.x) > math.abs(stick.y) then
                local degrees
                degrees, turnLatch = M.Turn(stick.x, turnLatch, settings.turn == 1,
                    settings.snap_angle, settings.turn_speed, elapsed)
                if degrees ~= 0 then
                    local before = C.Pose.head.pos
                    C.Space.Turn(degrees) turnRate = degrees / math.max(elapsed, 0.001)
                    api.turn = {degrees = degrees, error = (C.Pose.head.pos - before):Length()}
                end
            elseif math.abs(stick.x) < 0.35 then turnLatch = false end
            if stick.y < -0.7 and not downLatch then toggle = not toggle downLatch = true end
            if stick.y > -0.35 then downLatch = false end
        end
        if fresh and cmd:GetMouseX() ~= 0 and not vgui.CursorVisible() then
            local yaw = GetConVar("m_yaw"):GetFloat()
            local before = C.Pose.head.pos
            local degrees = -cmd:GetMouseX() * yaw
            C.Space.Turn(degrees) turnRate = turnRate + degrees / math.max(elapsed, 0.001)
            api.turn = {degrees = degrees, error = (C.Pose.head.pos - before):Length(), mouse = true}
        end
        stance() cmd:SetViewAngles(Angle(C.Pose.head.ang.p, C.Pose.head.ang.y, 0))
        if toggle or physical then buttons(cmd, IN_DUCK) end
        if own("off", "a") and input.off.a then buttons(cmd, IN_JUMP) end
        if own("off", "stick_click") and input.off.stick_click then buttons(cmd, IN_SPEED) end
        local sprint = bit.band(cmd:GetButtons(), IN_SPEED) ~= 0
        if own("off", "stick") then
            local x, y = M.Stick(input.off.stick.x, input.off.stick.y)
            local noclip=ply:GetMoveType()==MOVETYPE_NOCLIP
            local swimming=not noclip and ply.WaterLevel and ply:WaterLevel()>=2
            local ladder=ply:GetMoveType()==MOVETYPE_LADDER
            local pose = C.Pose[(swimming or ladder or settings.move_dir == 1) and "head" or "off"]
            if pose and pose.valid and (x ~= 0 or y ~= 0) then
                local speed = sprint and ply:GetRunSpeed() or ply:GetWalkSpeed()
                local direction = Angle(swimming and pose.ang.p or 0, pose.ang.y, 0)
                local velocity = (direction:Forward() * y + direction:Right() * x) * speed
                if swimming then
                    local aim=cmd:GetViewAngles()
                    cmd:SetForwardMove(velocity:Dot(aim:Forward())) cmd:SetSideMove(velocity:Dot(aim:Right())) cmd:SetUpMove(velocity:Dot(aim:Up()))
                elseif ply:GetMoveType() == MOVETYPE_NOCLIP then
                    local hand = C.Pose.off
                    if hand and hand.valid and own("off", "trigger_value") and own("off", "trigger") then
                        speed = ply:GetRunSpeed() * input.off.trigger_value
                        velocity = (hand.ang:Forward() * y + hand.ang:Right() * x) * speed
                    else velocity = Vector() end
                    local aim = cmd:GetViewAngles()
                    cmd:SetForwardMove(velocity:Dot(aim:Forward())) cmd:SetSideMove(velocity:Dot(aim:Right()))
                    cmd:SetUpMove(velocity:Dot(aim:Up()))
                else
                    local aim = Angle(0, cmd:GetViewAngles().y, 0)
                    cmd:SetForwardMove(velocity:Dot(aim:Forward())) cmd:SetSideMove(velocity:Dot(aim:Right()))
                end
                desiredSpeed = velocity:Length()
            end
        end
        if engine.TickCount() ~= roomTick then
            roomTick, roomSeq = engine.TickCount(), (roomSeq + 1) % 4294967296
            -- Cumulative distance can exceed Source's bounded net vector-coordinate range.
            ctx.Net.Send(M.ROOM, function(w)
                w.WriteUInt(roomSeq, 32) w.WriteFloat(total.x) w.WriteFloat(total.y) w.WriteFloat(total.z)
            end)
        end
        local wantsArc = settings.teleport > 0 and own("main", "stick") and input.main.stick.y > 0.7 and
            math.abs(input.main.stick.x) < 0.5 and ply:GetMoveType() == MOVETYPE_WALK and not pending
        if wantsArc then
            local origin, direction = C.Ray("main")
            if origin then
                arc = M.PlayerArc(ply, origin, direction, C.Space.scale)
                landing, api.targetReason = M.Landing(ply, arc, C.Space.scale, ply:GetPos())
                visuals.Arc(arc, landing)
            else arc, landing = nil, nil visuals.Arc(nil) end
        elseif arc then
            -- Claims, mode changes, horizontal turns and invalid tracking cancel rather than release.
            if landing and settings.teleport > 0 and own("main", "stick") and input.main.stick.y > -0.35 and
                math.abs(input.main.stick.x) < 0.5 and not pending then
                request = (request + 1) % 65536
                pending = {id = request, mode = settings.teleport, at = now}
                local target = landing
                ctx.Net.Send(M.TELEPORT, function(w)
                    w.WriteUInt(request, 16) w.WriteBool(input.mainHand == "left")
                    w.WriteUInt(pending.mode, 2) w.WriteVector(target)
                end)
            end
            arc, landing = nil, nil visuals.Arc(nil)
        end
        -- Movement buttons precede tool distance commands; core never rewrites them later.
        Basis.Intent(ply,cmd)
    end
    ctx.mover(0, move)
    ctx.On("before_overlay_paint", function()
        local now = RealTime()
        if pending and now - pending.at > 1.5 then
            lastTeleport = {id = pending.id, success = false, reason = "timeout"} pending = nil
        end
        local strength = M.Vignette(math.max(desiredSpeed, roomSpeed), turnRate, settings.vignette)
        local fade = math.Clamp((fadeUntil - now) / 0.12, 0, 1)
        if now < opaqueUntil then fade = 1 end
        if pending then if pending.mode == 1 then fade = 1 else strength = math.max(strength, 0.8) end end
        if prediction.blocked or now < blockedUntil or (api.follow and api.follow.blocked and roomSpeed > 0.1) then fade = 1 end
        -- Sweep from the engine eye as well: a tracked head beyond a thin ceiling must
        -- remain hidden even after its endpoint has emerged from the solid on the far side.
        local head, ply = C.Pose.head, LocalPlayer()
        local eyeBlocked = false
        if head and head.valid and ply:Alive() and ply:GetMoveType() == MOVETYPE_WALK then
            local trace = M.Trace(ply, ply:EyePos(), head.pos, Vector(-2, -2, -2), Vector(2, 2, 2))
            eyeBlocked = trace.Hit or trace.StartSolid or trace.AllSolid or false
            if eyeBlocked then fade = 1 end
        end
        visuals.Comfort(strength, fade)
        local p, a, feet = C.Pose.head, C.Space.anchor, IsValid(ply) and ply:GetPos() or Vector()
        xyz(debug.position, feet) xyz(debug.space.anchor, a) xyz(debug.room, total)
        if p then xyz(headDebug, p.pos) end
        if landing then xyz(targetDebug, landing) end
        debug.head, debug.target = p and headDebug, landing and targetDebug
        debug.space.yaw, debug.space.scale, debug.space.seated = C.Space.yaw, C.Space.scale, C.Space.seated
        debug.follow, debug.turn, debug.speed = api.follow, api.turn, desiredSpeed
        debug.physical_crouch, debug.crouch_toggle, debug.crouched = physical, toggle, physical or toggle
        debug.vignette, debug.fade, debug.eye_blocked = strength, fade, eyeBlocked
        debug.target_reason, debug.teleport, debug.pending = api.targetReason, lastTeleport, pending ~= nil
        debug.calibration = api.calibration
        turnRate = 0
    end)
end
function module.Stop() end
return module
