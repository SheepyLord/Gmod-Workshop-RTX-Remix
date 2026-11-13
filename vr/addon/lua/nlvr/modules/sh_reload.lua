-- Original model-local reload points, in Source units. Never supplied by a client.
local R = {CONFIG = 80, ACTION = 81, STATE = 82, INSERT_METRES = 0.06, SERVER_METRES = 0.16,
    ALIGN = math.cos(math.rad(55)), SERVER_ALIGN = math.cos(math.rad(75)), HOLD_SECONDS = 3600, ACK_LEASE = 1.5, ACK_READY = true, ACK_POLICY = true, ACTION_SERIAL = true, SHORT_LAPSE = 5, HOLD_MARK = 300}
R.Guns = {
    weapon_pistol = {kind = "clip", size = 18, port = Vector(4.7738, 1.7635, -4.7283), eject = Vector(4.7741, 1.7635, -6.7283),
        muzzle = Vector(-5.8739, 0.1912, 0.6025), axis = Angle(-89.9914, -178.6678, 0), ammo = "models/items/boxsrounds.mdl", sound = "Weapon_Pistol.Reload", frame = Angle(0.0086, 178.8701, -0.0002)},
    weapon_357 = {kind = "clip", size = 6, port = Vector(3.2435, 0.1597, 2.5), eject = Vector(1.2449, 0.1595, 2.4239),
        muzzle = Vector(14.196, 0.2707, 3.1072), axis = Angle(-2.1813, 0.0056, 0), ammo = "models/items/357ammo.mdl", sound = "Weapon_357.Reload", frame = Angle(2.1813, -0.0056, -0.0002)},
    weapon_smg1 = {kind = "clip", size = 45, port = Vector(-7.4083, -0.1603, -3.6786), eject = Vector(-7.4734, -0.1628, -5.6775),
        muzzle = Vector(8.143, 1.4672, 2.2887), axis = Angle(-88.1336, 2.2377, 0), ammo = "models/items/boxmrounds.mdl", sound = "Weapon_SMG1.Reload", frame = Angle(-1.865, -2.24, 0.0729)},
    weapon_ar2 = {kind = "clip", size = 30, port = Vector(12.3176, 0.3694, 0.1183), eject = Vector(12.3013, 0.3696, -1.8816),
        muzzle = Vector(-9.9536, -0.1197, 3.6376), axis = Angle(-89.5337, -0.7372, 0), ammo = "models/items/combine_rifle_cartridge01.mdl", sound = "Weapon_AR2.Reload", frame = Angle(-0.4663, -179.2594, -0.006)},
    weapon_shotgun = {kind = "shotgun", size = 6, port = Vector(12.9124, 0.3862, -1.2993), eject = Vector(13.2088, 0.3805, -3.2772),
        muzzle = Vector(-15.3398, 0.109, 0.9086), axis = Angle(-81.4746, 178.8912, 0), ammo = "models/weapons/shotgun_shell.mdl", sound = "Weapon_Shotgun.Reload", frame = Angle(8.5238, -178.8787, 0.1662)},
    weapon_crossbow = {kind = "crossbow", size = 1, port = Vector(9.6, 0, 3.7), eject = Vector(7.6, 0, 3.7),
        muzzle = Vector(22.9578, 2.1451, 3.6782), axis = Angle(0, 0, 0), ammo = "models/crossbow_bolt.mdl", sound = "Weapon_Crossbow.Reload", frame = Angle(0, 0, 0)},
    weapon_rpg = {kind = "rpg", size = 1, port = Vector(23.9, -1.2, 5.4), eject = Vector(25.8998, -1.2259, 5.3838),
        muzzle = Vector(-3.1461, -1.2099, 5.4482), axis = Angle(-0.4653, 179.2593, 0), ammo = "models/weapons/w_missile_closed.mdl", sound = "Weapon_RPG.Reload", frame = Angle(-0.4653, -179.2593, -0.006)},
}
function R.Opposite(hand) return hand == "left" and "right" or "left" end
function R.Finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
function R.Zone(head, off, scale)
    if not head or not head.valid or not off or not off.valid then return false end
    -- Head yaw only: looking up must not move the shoulders into the player's face.
    local p = WorldToLocal(off.pos, Angle(), head.pos, Angle(0, head.ang.y, 0)) / scale
    return p.x >= -0.42 and p.x <= -0.06 and math.abs(p.y) >= 0.12 and math.abs(p.y) <= 0.5
        and p.z >= -0.28 and p.z <= 0.18
end
function R.Point(model, data, key)
    if not IsValid(model) then return end
    return LocalToWorld(data[key or "port"] * (model.GetModelScale and model:GetModelScale() or 1), data.axis, model:GetPos(), model:GetAngles())
end
function R.ServerPort(weapon, data, muzzle, scale)
    if not muzzle or not muzzle.pos or not muzzle.ang then return end
    if data.frame then
        -- Trusted stock-model measurement: W's muzzle angles describe gun aim,
        -- rather than the authored attachment's sometimes rotated coordinate frame.
        local p, a = LocalToWorld(data.port - data.muzzle, data.axis, Vector(), data.frame)
        return LocalToWorld(p * ((scale or 40) / 40), a, muzzle.pos, muzzle.ang)
    end
    -- Use the stock model's local muzzle where available, never the client's model transform.
    local localPos, localAng = data.muzzle, data.axis
    local id = weapon:LookupAttachment("muzzle")
    local attachment = id and id > 0 and weapon:GetAttachment(id)
    if attachment then
        localPos, localAng = WorldToLocal(attachment.Pos, attachment.Ang, weapon:GetPos(), weapon:GetAngles())
    end
    local p, a = WorldToLocal(data.port, data.axis, localPos, localAng)
    return LocalToWorld(p * ((scale or 40) / 40), a, muzzle.pos, muzzle.ang)
end
function R.Close(off, port, angle, scale, server)
    if not off or not off.valid or not port or not angle then return false, "tracking" end
    local distance = (off.pos - port):Length() / scale
    if distance > (server and R.SERVER_METRES or R.INSERT_METRES) then return false, "too-far", distance end
    local dot = off.ang:Forward():Dot(angle:Forward())
    if dot < (server and R.SERVER_ALIGN or R.ALIGN) then return false, "alignment", distance end
    return true, "accepted", distance
end
function R.Transfer(data, clip, reserve, maxClip)
    local size = maxClip and maxClip > 0 and maxClip or data.size
    local add = math.max(0, math.min(reserve, size - math.max(0, clip), data.kind == "shotgun" and 1 or size))
    return math.max(0, clip) + add, add
end
return R
