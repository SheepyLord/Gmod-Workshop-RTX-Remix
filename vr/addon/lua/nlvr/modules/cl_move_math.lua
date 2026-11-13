-- Pure movement rules, shared by the two move modules; including this installs nothing.
local M = {ROOM = 24, TELEPORT = 25, RESULT = 26, FOLLOW = 27, RANGE = 8, MANTLE = 1.5,
    ARC_STEP = 0.04, ARC_STEPS = 48, SHIFT_SECONDS = 0.15, BLINK_SECONDS = 0.075}
function M.Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function M.Vector(v) return v and M.Finite(v.x) and M.Finite(v.y) and M.Finite(v.z) end
function M.Flat(v) return Vector(v.x, v.y, 0) end
function M.Rotate(v, yaw)
    local s, c = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
    return Vector(c * v.x - s * v.y, s * v.x + c * v.y, v.z)
end
function M.Limit(v, maximum)
    local length = v:Length()
    return length > maximum and v * (maximum / length) or v
end
function M.Stick(x, y)
    local n = math.sqrt(x * x + y * y)
    if n <= 0.2 then return 0, 0 end
    local amount = math.min(1, (n - 0.2) / 0.8)
    return x / n * amount, y / n * amount
end
function M.Crouch(height, standing, previous)
    if not M.Finite(height) or not M.Finite(standing) or standing <= 0 then return false end
    return height < standing * (previous and 0.78 or 0.68)
end
function M.CrouchOffset(eyeHeight, standing, duck)
    return math.Clamp(eyeHeight - duck, 0, math.max(0, standing - duck))
end
function M.Calibration(height, eyeUnits)
    if not M.Finite(height) or height < 1.2 or height > 2.2 or not M.Finite(eyeUnits) then return nil end
    return math.Clamp(eyeUnits / height, 10, 100)
end
function M.Vignette(speed, turnSpeed, maximum)
    return math.Clamp(maximum or 0, 0, 1) * math.Clamp(math.max(speed / 180, math.abs(turnSpeed) / 90), 0, 1)
end
function M.Turn(x, latched, smooth, angle, speed, dt)
    if math.abs(x) < 0.35 then return 0, false end
    if smooth then return -x * speed * dt, true end
    if math.abs(x) >= 0.7 and not latched then return x > 0 and -angle or angle, true end
    return 0, latched
end
-- A continuous segmented ballistic curve: never skip a collision between drawn points.
function M.Arc(origin, direction, scale, trace)
    local points = {origin}
    local velocity = direction * (6 * scale) + Vector(0, 0, 2 * scale)
    for i = 1, M.ARC_STEPS do
        local t = i * M.ARC_STEP
        local nextPoint = origin + velocity * t - Vector(0, 0, 0.5 * 9.81 * scale * t * t)
        local hit = trace(points[#points], nextPoint)
        points[#points + 1] = hit.Hit and hit.HitPos or nextPoint
        if hit.StartSolid or hit.AllSolid then return {points = points, reason = "solid", hit = hit} end
        if hit.Hit then return {points = points, hit = hit, target = hit.HitPos} end
        if (nextPoint - origin):Length() > M.RANGE * scale then break end
    end
    return {points = points, reason = "no_floor"}
end
function M.Hull(ply)
    if ply:Crouching() then return ply:GetHullDuck() end
    return ply:GetHull()
end
function M.Trace(ply, start, finish, mins, maxs)
    local filter = ply
    if NLVR_SV and NLVR_SV.BodyTrace then
        filter = function(ent) return NLVR_SV.BodyTrace(ply, ent) end
    elseif NLVR and NLVR.BodyTrace then
        filter = function(ent) return NLVR.BodyTrace(ply, ent) end
    end
    return util.TraceHull({start = start, endpos = finish, mins = mins, maxs = maxs,
        filter = filter, mask = MASK_PLAYERSOLID, collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT})
end
function M.PlayerArc(ply, origin, direction, scale)
    return M.Arc(origin, direction, scale, function(a, b)
        return M.Trace(ply, a, b, Vector(-1, -1, -1), Vector(1, 1, 1))
    end)
end
local function blocked(t) return t.StartSolid or t.AllSolid or t.Hit end
-- Route a standing hull up, across and down. The same route is swept during a shift.
-- This admits an open ledge, but rejects an arc through a slit or over a closed ceiling.
function M.Landing(ply, arc, scale, from)
    if not arc.target or not arc.hit or not arc.hit.Hit then return nil, arc.reason or "no_floor" end
    if not M.Vector(arc.target) or not M.Vector(arc.hit.HitNormal) then return nil, "finite" end
    if arc.hit.HitNormal.z < 0.7 then return nil, "slope" end
    local target = arc.target + Vector(0, 0, 1)
    if (target - from):Length() > M.RANGE * scale then return nil, "range" end
    if target.z - from.z > M.MANTLE * scale then return nil, "height" end
    local mins, maxs = ply:GetHull() -- teleport always requires standing room
    if blocked(M.Trace(ply, target, target, mins, maxs)) then return nil, "hull" end
    local floor = M.Trace(ply, target, target - Vector(0, 0, 4), mins, maxs)
    if not floor.Hit or floor.StartSolid or floor.HitNormal.z < 0.7 then return nil, "floor" end
    target = floor.HitPos + Vector(0, 0, 0.25)
    -- A clear ordinary corridor needs no artificial step up (and no bob during a shift).
    -- In particular, a doorway that fits the standing hull must remain usable.
    if not blocked(M.Trace(ply, from, target, mins, maxs)) then return target, "ok", {from, target} end
    local top = math.max(from.z, target.z) + math.max(2, ply:GetStepSize())
    local route = {from, Vector(from.x, from.y, top), Vector(target.x, target.y, top), target}
    for i = 2, #route do
        if blocked(M.Trace(ply, route[i - 1], route[i], mins, maxs)) then return nil, "path" end
    end
    return target, "ok", route
end
function M.Route(route, fraction)
    local lengths, total = {}, 0
    for i = 2, #route do lengths[i] = (route[i] - route[i - 1]):Length() total = total + lengths[i] end
    local at = math.Clamp(fraction, 0, 1) * total
    for i = 2, #route do
        if at <= lengths[i] then return route[i - 1] + (route[i] - route[i - 1]) * (lengths[i] > 0 and at / lengths[i] or 0) end
        at = at - lengths[i]
    end
    return route[#route]
end
function M.SweepRoute(ply, route, first, last)
    local total = 0
    for i = 2, #route do total = total + (route[i] - route[i - 1]):Length() end
    local from, at, mins, maxs = M.Route(route, first), 0, ply:GetHull()
    for i = 2, #route do
        at = at + (route[i] - route[i - 1]):Length()
        local fraction = total > 0 and at / total or 1
        if fraction > first and fraction < last then
            local hit = M.Trace(ply, from, route[i], mins, maxs)
            if hit.Hit or hit.StartSolid or hit.AllSolid then return false end
            from = route[i]
        end
    end
    local hit = M.Trace(ply, from, M.Route(route, last), mins, maxs)
    return not (hit.Hit or hit.StartSolid or hit.AllSolid)
end
-- Room walking is a hull sweep, slide and ordinary step. Vertical step displacement lifts the eyes.
function M.Follow(ply, from, delta)
    local mins, maxs = M.Hull(ply)
    local direct = M.Trace(ply, from, from + delta, mins, maxs)
    if direct.StartSolid or direct.AllSolid then return from, true end
    if not direct.Hit then return from + delta, false end
    local best = direct.HitPos
    local rest = delta * (1 - (direct.Fraction or 0))
    local slide = rest - direct.HitNormal * rest:Dot(direct.HitNormal)
    local along = M.Trace(ply, best, best + slide, mins, maxs)
    if not along.StartSolid then best = along.Hit and along.HitPos or best + slide end
    if ply:OnGround() then
        local up = from + Vector(0, 0, ply:GetStepSize())
        if not blocked(M.Trace(ply, from, up, mins, maxs)) then
            local across = M.Trace(ply, up, up + delta, mins, maxs)
            local endpos = across.Hit and across.HitPos or up + delta
            local down = M.Trace(ply, endpos, endpos - Vector(0, 0, ply:GetStepSize() + 2), mins, maxs)
            if down.Hit and not down.StartSolid and down.HitNormal.z >= 0.7 and
                M.Flat(down.HitPos - from):Length() > M.Flat(best - from):Length() then best = down.HitPos end
        end
    end
    return best, M.Flat(from + delta - best):Length() > 0.01
end
return M
