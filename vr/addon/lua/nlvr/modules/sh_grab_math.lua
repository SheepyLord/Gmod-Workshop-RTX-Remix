-- Hold maths shared by the server's grab controller and the client's held-object prediction (V8, ADR 0203).
-- Game units and seconds. Spin is radians/s on world axes unless a name says local. Pure: no hooks,
-- entities or resources on include.
local G = {}
G.PALM = 0.035                -- metres from the palm frame to where a held surface rests
G.TRACK_METRES, G.TRACK_DEGREES = 0.04, 12 -- a hold within these follows the hand (client prediction)
G.STRENGTH, G.TORQUE = 900, 150          -- a hand's force (N) and a wrist's torque (N m)
G.MAX_ACCEL, G.MAX_SPIN_ACCEL = 150, 400  -- m/s^2 and rad/s^2: no hold moves faster than a flicked hand
G.ARRIVE = 2 / 66                          -- seconds to close a position or angle error (two ticks)
G.SPEED, G.SPIN = 20, 40                   -- m/s and rad/s caps
-- Closing an error (not following the hand) is capped, so a body pressed on a wall or a ragdoll bone held
-- back by its joints is never driven hard into them. Ragdoll bones close more gently still.
G.CORRECT, G.CORRECT_SPIN = 3, 10          -- m/s and rad/s
G.LINKED_CORRECT, G.LINKED_SPIN, G.LINKED_ARRIVE = 2, 6, 3 / 66
local DEG, RAD = 180 / math.pi, math.pi / 180

function G.Limit(v, maximum)
    local length = v:Length()
    return length > maximum and v * (maximum / length) or v
end
function G.Cross(a, b) return Vector(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function unit(v)
    local length = v:Length()
    if length < 1e-9 then return nil end
    return v / length
end
-- Source's basis of an angle: X forward, Y left, Z up (a right-handed frame).
function G.Axes(a) return a:Forward(), -a:Right(), a:Up() end
function G.AngleFromAxes(X, Y, Z)
    return Angle(math.deg(math.atan2(-X.z, math.sqrt(X.x * X.x + X.y * X.y))), math.deg(math.atan2(X.y, X.x)),
        math.deg(math.atan2(Y.z, Z.z)))
end
function G.Quat(a)
    local X, Y, Z = G.Axes(a)
    local m11, m12, m13, m21, m22, m23, m31, m32, m33 = X.x, Y.x, Z.x, X.y, Y.y, Z.y, X.z, Y.z, Z.z
    local trace = m11 + m22 + m33
    if trace > 0 then
        local s = math.sqrt(trace + 1) * 2
        return {0.25 * s, (m32 - m23) / s, (m13 - m31) / s, (m21 - m12) / s}
    elseif m11 > m22 and m11 > m33 then
        local s = math.sqrt(1 + m11 - m22 - m33) * 2
        return {(m32 - m23) / s, 0.25 * s, (m12 + m21) / s, (m13 + m31) / s}
    elseif m22 > m33 then
        local s = math.sqrt(1 + m22 - m11 - m33) * 2
        return {(m13 - m31) / s, (m12 + m21) / s, 0.25 * s, (m23 + m32) / s}
    end
    local s = math.sqrt(1 + m33 - m11 - m22) * 2
    return {(m21 - m12) / s, (m13 + m31) / s, (m23 + m32) / s, 0.25 * s}
end
local function multiply(a, b)
    return {a[1] * b[1] - a[2] * b[2] - a[3] * b[3] - a[4] * b[4], a[1] * b[2] + a[2] * b[1] + a[3] * b[4] - a[4] * b[3],
        a[1] * b[3] - a[2] * b[4] + a[3] * b[1] + a[4] * b[2], a[1] * b[4] + a[2] * b[3] - a[3] * b[2] + a[4] * b[1]}
end
local function fromQuat(q)
    local w, x, y, z = q[1], q[2], q[3], q[4]
    local X = Vector(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y))
    local Y = Vector(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x))
    local Z = Vector(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y))
    return G.AngleFromAxes(X, Y, Z)
end
-- The rotation (axis times angle, radians, world axes) that turns `from` into `to`, the short way.
function G.RotationError(from, to)
    local a, b = G.Quat(from), G.Quat(to)
    local q = multiply(b, {a[1], -a[2], -a[3], -a[4]})
    if q[1] < 0 then q = {-q[1], -q[2], -q[3], -q[4]} end
    local s = math.sqrt(q[2] * q[2] + q[3] * q[3] + q[4] * q[4])
    if s < 1e-9 then return Vector(2 * q[2], 2 * q[3], 2 * q[4]) end
    return Vector(q[2], q[3], q[4]) * (2 * math.atan2(s, q[1]) / s)
end
-- `a` turned by a rotation vector (radians, world axes).
function G.Rotate(a, rotation)
    local angle = rotation:Length()
    if angle < 1e-12 then return Angle(a.p, a.y, a.r) end
    local s = math.sin(angle / 2) / angle
    return fromQuat(multiply({math.cos(angle / 2), rotation.x * s, rotation.y * s, rotation.z * s}, G.Quat(a)))
end
-- PhysObj spin is degrees/s on the body's own axes; the controller works in world radians/s.
function G.WorldSpin(localDegrees, a)
    local X, Y, Z = G.Axes(a)
    return (X * localDegrees.x + Y * localDegrees.y + Z * localDegrees.z) * RAD
end
function G.LocalSpin(world, a)
    local X, Y, Z = G.Axes(a)
    return Vector(world:Dot(X), world:Dot(Y), world:Dot(Z)) * DEG
end
-- How hard a hand can move a body: light bodies follow at once, heavy ones lag (ADR 0169's mass lag kept).
-- inertia: the body's largest principal moment in kg units^2 (PhysObj:GetInertia), or nil. linked: one bone
-- of a ragdoll or another jointed body.
function G.Limits(mass, inertia, scale, linked)
    mass = math.max(tonumber(mass) or 1, 0.05)
    local moment = math.max(tonumber(inertia) or 0, mass * (0.05 * scale) ^ 2)
    return {accel = math.min(G.MAX_ACCEL, G.STRENGTH / mass) * scale,
        spinAccel = math.min(G.MAX_SPIN_ACCEL, G.TORQUE * scale * scale / moment),
        speed = G.SPEED * scale, spin = G.SPIN, arrive = linked and G.LINKED_ARRIVE or G.ARRIVE,
        correct = (linked and G.LINKED_CORRECT or G.CORRECT) * scale, correctSpin = linked and G.LINKED_SPIN or G.CORRECT_SPIN}
end
local function approach(error, arrive, accel, dt, cap)
    local distance = error:Length()
    local wanted = error / math.max(arrive, dt)
    -- Never faster than it can stop in whole ticks while braking at under half its strength: the closing
    -- tail (error / arrive) then needs at most the full strength, so a hold never overshoots.
    local b = 0.45 * accel
    local brake = -b * dt / 2 + math.sqrt((b * dt / 2) ^ 2 + 2 * b * distance)
    local speed = wanted:Length()
    local limit = math.min(brake, cap or math.huge)
    if speed > limit and speed > 0 then wanted = wanted * (limit / speed) end
    return wanted, distance
end
-- One hold step. body and goal: {pos, ang, vel, spin}; goal.vel and goal.spin are how the goal moves with
-- the hand. Returns the velocity and spin changes (world) and the position and angle errors (units, radians).
function G.Step(body, goal, limits, dt)
    local toward, distance = approach(goal.pos - body.pos, limits.arrive, limits.accel, dt, limits.correct)
    local dv = G.Limit(G.Limit(goal.vel + toward, limits.speed) - body.vel, limits.accel * dt)
    local turn = G.RotationError(body.ang, goal.ang)
    local spinToward, angle = approach(turn, limits.arrive, limits.spinAccel, dt, limits.correctSpin)
    local dw = G.Limit(G.Limit(goal.spin + spinToward, limits.spin) - body.spin, limits.spinAccel * dt)
    return dv, dw, distance, angle
end
-- The body's pose in a hand's frame, and back.
function G.Relation(bodyPos, bodyAng, anchorPos, anchorAng)
    local pos, ang = WorldToLocal(bodyPos, bodyAng, anchorPos, anchorAng)
    return {pos = pos, ang = ang}
end
function G.OneHand(rel, anchor) return LocalToWorld(rel.pos, rel.ang, anchor.pos, anchor.ang) end
-- Where a touched point should come to rest: where it is, or at the palm's surface if it is farther.
function G.Snap(point, palm, distance)
    local offset = point - palm
    local length = offset:Length()
    if length <= distance then return point end
    return palm + offset * (distance / length)
end
-- Two hands on one body: the line between them, rolled by the average of both hands' up (then forward).
function G.PairFrame(a, b)
    local line = b.pos - a.pos
    local X = unit(line)
    if not X then return nil end
    local Z
    for _, reference in ipairs({a.ang:Up() + b.ang:Up(), a.ang:Forward() + b.ang:Forward(), Vector(0, 0, 1), Vector(1, 0, 0)}) do
        Z = unit(reference - X * reference:Dot(X))
        if Z and (reference - X * reference:Dot(X)):Length() > 0.05 * reference:Length() then break end
    end
    local Y = G.Cross(Z, X)
    return (a.pos + b.pos) * 0.5, G.AngleFromAxes(X, Y, Z), line:Length()
end
function G.TwoHand(two, a, b)
    local mid, ang = G.PairFrame(a, b)
    if not mid then return end
    return LocalToWorld(two.pos, two.ang, mid, ang)
end
-- How the pair frame moves: the midpoint's velocity, and the line's swing plus the hands' mean roll about it.
function G.PairMotion(a, b)
    local line = b.pos - a.pos
    local length2 = line:Dot(line)
    local vel = (a.vel + b.vel) * 0.5
    if length2 < 1e-9 then return vel, (a.spin + b.spin) * 0.5 end
    local X = line / math.sqrt(length2)
    local swing = G.Cross(line, b.vel - a.vel) / length2
    return vel, swing + X * ((a.spin + b.spin) * 0.5):Dot(X)
end
-- The world pose a rendered body should show: the mode's pose plus a decaying offset (k from 1 to 0).
function G.Blend(pos, ang, offsetPos, offsetTurn, k)
    if k <= 0 then return pos, ang end
    return pos + offsetPos * k, G.Rotate(ang, offsetTurn * k)
end
return G
