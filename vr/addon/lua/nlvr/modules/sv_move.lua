local module = {name = "move", order = 10}
local M = include("nlvr/modules/cl_move_math.lua")
function module.Start(ctx)
    local SV = ctx.core
    local function state(ply)
        local vr = SV.Players[ply]
        if not vr then return end
        vr.move = vr.move or {received = Vector(), consumed = Vector(), applied_total = Vector(), blocked = false}
        return vr.move, vr
    end
    local function result(ply, s, success, reason, target)
        s.last = {success = success, reason = reason, target = target, id = s.request or 0}
        SV.Net.Send(ply, M.RESULT, function(w)
            w.WriteUInt(s.request or 0, 16) w.WriteBool(success) w.WriteString(reason) w.WriteVector(target or ply:GetPos())
        end)
    end
    ctx.Net.On(M.ROOM, function(ply)
        local s, vr = state(ply)
        local seq = net.ReadUInt(32)
        local total = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
        if not M.Vector(total) or math.abs(total.z) > 0.01 or total:Length() > 1000000 then return end
        if s.seq and ((seq - s.seq) % 4294967296 >= 2147483648 or seq == s.seq) then return end
        if (total - s.received):Length() > vr.scale * 2.5 then
            -- A pause/tracking discontinuity must not poison every later cumulative receipt.
            -- Discard the suspended displacement; never bank or apply an oversized step.
            s.consumed = total
            s.rebaselines = (s.rebaselines or 0) + 1
        end
        s.seq, s.received, s.time = seq, total, CurTime()
    end)
    ctx.Net.On(M.TELEPORT, function(ply)
        local s, vr = state(ply)
        local id, left, mode, proposed = net.ReadUInt(16), net.ReadBool(), net.ReadUInt(2), net.ReadVector()
        if s.teleport or (s.lastRequest and CurTime() - s.lastRequest < 0.25) then return end
        s.request, s.lastRequest = id, CurTime()
        if not M.Vector(proposed) or mode < 1 or mode > 2 then result(ply, s, false, "request") return end
        if not ply:Alive() or ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then result(ply, s, false, "movement") return end
        local hand = vr.hands[left and "left" or "right"]
        if not vr.head.valid or not hand.valid or not vr.lastSync or CurTime() - vr.lastSync > 0.25 then
            result(ply, s, false, "tracking") return
        end
        local arc = M.PlayerArc(ply, hand.pos, hand.ang:Forward(), vr.scale)
        local target, reason, route = M.Landing(ply, arc, vr.scale, ply:GetPos())
        if not target then result(ply, s, false, reason) return end
        if (target - proposed):Length() > vr.scale * 0.25 then result(ply, s, false, "changed") return end
        s.teleport = {target = target, route = route, began = CurTime(), deadline = RealTime() + 1.25,
            mode = mode, last = ply:GetPos()}
    end)
    -- Climbing reserves lower priorities; neither mover changes an engine movement permission.
    ctx.mover(20, function(ply, mv)
        local s = state(ply)
        local t = s.teleport
        if not t then return end
        if RealTime() > t.deadline then s.teleport = nil result(ply, s, false, "expired") return end
        if not ply:Alive() or ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then
            s.teleport = nil result(ply, s, false, "interrupted") return
        end
        t.moveTick = engine.TickCount()
        local fraction = (CurTime() - t.began) / (t.mode == 1 and M.BLINK_SECONDS or M.SHIFT_SECONDS)
        local destination = t.mode == 1 and (fraction >= 1 and t.target or mv:GetOrigin()) or M.Route(t.route, fraction)
        local mins, maxs = ply:GetHull()
        -- Revalidate every traversed segment if a door/prop moved after the request.
        local valid = true
        if t.mode == 1 and fraction >= 1 then
            for i = 2, #t.route do
                local hit = M.Trace(ply, t.route[i - 1], t.route[i], mins, maxs)
                if hit.Hit or hit.StartSolid or hit.AllSolid then valid = false break end
            end
        elseif t.mode == 2 then
            valid = M.SweepRoute(ply, t.route, t.fraction or 0, math.Clamp(fraction, 0, 1))
        end
        if not valid then s.teleport = nil result(ply, s, false, "blocked") return end
        local delta=destination-mv:GetOrigin()
        if delta:Length()>.0001 then SV.Emit("teleport_delta",ply,delta) end
        mv:SetOrigin(destination) mv:SetVelocity(Vector())
        t.last, t.fraction = destination, math.Clamp(fraction, 0, 1)
        if fraction >= 1 then
            s.teleport = nil s.consumed = s.received
            if t.mode == 1 then s.follow_epoch = ((s.follow_epoch or 0) + 1) % 65536 end
            result(ply, s, true, t.target.z - t.route[1].z > ply:GetStepSize() and "mantle" or "ok", t.target)
        end
        return true
    end)
    ctx.mover(50, function(ply, mv, cmd)
        if ply:GetMoveType() ~= MOVETYPE_NOCLIP or not ply:Alive() or ply:InVehicle() or not cmd then return end
        local s = state(ply) s.consumed = s.received
        local aim = cmd:GetViewAngles()
        local velocity = aim:Forward() * cmd:GetForwardMove() + aim:Right() * cmd:GetSideMove() + aim:Up() * cmd:GetUpMove()
        velocity = M.Limit(velocity, ply:GetRunSpeed())
        mv:SetVelocity(velocity) mv:SetOrigin(mv:GetOrigin() + velocity * engine.TickInterval())
        return true -- the engine already granted noclip; use an exact trigger-scaled speed
    end)
    ctx.mover(100, function(ply, mv)
        local s, vr = state(ply)
        s.roomTick = engine.TickCount()
        if not ply:Alive() or ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then
            s.consumed = s.received return
        end
        if not s.time or CurTime() - s.time > 0.25 then s.consumed = s.received return end
        local delta = M.Limit(s.received - s.consumed, vr.scale * 0.15)
        s.consumed = s.consumed + delta -- stopped movement is discarded, never banked for later
        if delta:Length() < 0.001 then return end
        local from = mv:GetOrigin()
        local to, stopped = M.Follow(ply, from, delta)
        mv:SetOrigin(to)
        s.blocked, s.position, s.applied = stopped, to, to - from
        s.applied_total = (s.applied_total or Vector()) + to - from
        -- Ordinary Source movement still supplies gravity, jump, friction, steps and doors.
    end)
    ctx.hook("FinishMove", function(ply, mv)
        local vr = SV.Players[ply]
        local s = vr and vr.move
        -- A higher-priority owner (climbing, teleport, flight) consumed this tick.
        -- Never release a bank of physical walking when that owner lets go.
        if s and s.roomTick ~= engine.TickCount() then s.consumed = s.received end
        if s and s.teleport and s.teleport.moveTick ~= engine.TickCount() then
            s.teleport = nil result(ply, s, false, "movement_owner")
        end
        if s then
            -- Absolute cumulative receipts survive coalescing/other modules' sends. The
            -- final origin includes ordinary movement, gravity and teleports, not just room.
            local origin, applied, velocity = mv:GetOrigin(), s.applied_total or Vector(), mv:GetVelocity()
            local mode, previous = ply:GetMoveType(), s.follow_last
            if previous and (previous.mode ~= mode or (origin - previous.origin):Length() > math.max(64, velocity:Length() * engine.TickInterval() * 2)) then
                s.follow_epoch = ((s.follow_epoch or 0) + 1) % 65536
            end
            local generation = s.follow_epoch or 0
            if previous and previous.mode == mode and previous.epoch == generation and previous.blocked == s.blocked and
                previous.origin:DistToSqr(origin) == 0 and previous.velocity:DistToSqr(velocity) == 0 and
                previous.applied:DistToSqr(applied) == 0 and previous.consumed:DistToSqr(s.consumed) == 0 then return end
            s.follow_last = {origin = Vector(origin.x, origin.y, origin.z), velocity = velocity, applied = applied,
                consumed = s.consumed, mode = mode, blocked = s.blocked, epoch = generation}
            local stamp, wall = CurTime(), SysTime()
            SV.Net.Send(ply, M.FOLLOW, function(w)
                w.WriteBool(s.blocked) w.WriteUInt(mode, 5)
                w.WriteDouble(stamp) w.WriteDouble(wall) w.WriteUInt(generation, 16)
                for _, v in ipairs({s.consumed, applied, origin}) do w.WriteFloat(v.x) w.WriteFloat(v.y) w.WriteFloat(v.z) end
            end)
        end
    end)
    local function reset(ply)
        local s = state(ply)
        if s then
            if s.teleport then s.teleport = nil result(ply, s, false, "interrupted") end
            s.consumed = s.received
            s.follow_epoch = ((s.follow_epoch or 0) + 1) % 65536
        end
    end
    ctx.On("OnDeath", reset) ctx.On("OnSpawn", reset)
    ctx.cleanup(function() for _, vr in pairs(SV.Players) do vr.move = nil end end)
end
function module.Stop() end
return module
