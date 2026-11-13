-- The native physgun owns pickup, position, collision and freeze. This owns only its held angle.
local Math = include("nlvr/modules/sh_tools_math.lua")
local R = {}
local names = {"physgun_timeToArrive", "physgun_timeToArriveRagdoll", "physgun_maxAngular",
    "physgun_maxAngularDamping", "physgun_DampingFactor"}
local variables
local function value(name, fallback)
    if not variables then
        variables = {}
        for _, key in ipairs(names) do variables[key] = GetConVar(key) end
    end
    local cv = variables[name]
    local n = cv and cv:GetFloat() or fallback
    return Math.Finite(n) and math.max(0, n) or 0
end
function R.Parameters(phys, angle, dt, result, ragdoll)
    local arrive = math.max(0.001, value(ragdoll and "physgun_timeToArriveRagdoll" or "physgun_timeToArrive", ragdoll and 0.1 or 0.05))
    local origin = phys:GetPos()
    local p = result or {}
    p.secondstoarrive, p.delta, p.angle = arrive, dt, angle
    -- ComputeShadowControl's position is the object origin. Its velocity must be
    -- sampled at that point, not the COM, when a prop rotates around an offset COM.
    p.pos = origin + phys:GetVelocityAtPoint(origin) * arrive
    p.maxangular = value("physgun_maxAngular", 5000)
    p.maxangulardamp = value("physgun_maxAngularDamping", 10000)
    -- T supplies no linear force/damping; native physgun positioning remains alone.
    p.maxspeed, p.maxspeeddamp = 0, 0
    p.dampfactor, p.teleportdistance = value("physgun_DampingFactor", 1), 0
    return p
end
function R.New(ctx, ply, data, hand)
    local self = {calls = 0, parameters = {}}
    local offset, previous, zero, zeroAngle = Angle(), nil, Vector(), Angle()
    local function corrected(target, actual, dt, parameters)
        local changed = previous and Math.AngleError(previous, target) or 180
        if changed > 5 or parameters.maxangular <= 0 or parameters.dampfactor <= 0 then
            offset.p, offset.y, offset.r = 0, 0, 0
        end
        previous = previous or Angle()
        previous.p, previous.y, previous.r = target.p, target.y, target.r
        local error = Math.AngleError(actual, target)
        if parameters.maxangular > 0 and parameters.dampfactor > 0 and error > 0.03 and error <= 30 then
            -- Integral trim removes the native holder's measured steady angular
            -- residual. It changes only the goal, never the server's force limits.
            local axis = actual:Forward():Cross(target:Forward()) + actual:Right():Cross(target:Right()) + actual:Up():Cross(target:Up())
            if axis:Length() > 0.000001 then
                local candidate = Angle(offset.p, offset.y, offset.r)
                candidate:RotateAroundAxis(axis:GetNormalized(), math.min(error * 8 * math.min(dt, 0.05), 2))
                if Math.AngleError(candidate, zeroAngle) <= 30 then
                    offset.p, offset.y, offset.r = candidate.p, candidate.y, candidate.r
                end
            end
        end
        local _, result = LocalToWorld(zero, target, zero, offset)
        return result
    end
    local ragdoll = data.ent.GetClass and data.ent:GetClass() == "prop_ragdoll"
    local entity = ents.Create("base_anim")
    if not IsValid(entity) then return nil, "could not create physgun angle controller" end
    self.entity = entity
    function self.Stop()
        self.stopped = true
        if IsValid(entity) then entity:StopMotionController() entity:Remove() end
        self.entity = nil
    end
    entity:SetNoDraw(true) entity:SetNotSolid(true) entity:SetPreventTransmit(player.GetAll(), true)
    entity.PhysicsSimulate = function(_, phys, dt)
        local state = ctx.Players[ply]
        local pose = state and state.hands[hand]
        if self.stopped or self.failed or not IsValid(ply) or not ply:Alive() or not pose or not pose.valid or
            not IsValid(data.ent) or not data.ent:IsPlayerHolding() or not IsValid(phys) then return end
        local ok, err = pcall(function()
            local target = Math.Follow(data.relative, pose.ang)
            if ply:KeyDown(IN_SPEED) then target = Math.Snap(target, ply:GetInfoNum("gm_snapangles", 45)) end
            local parameters = R.Parameters(phys, target, dt, self.parameters, ragdoll)
            parameters.angle = corrected(target, phys:GetAngles(), dt, parameters)
            phys:ComputeShadowControl(parameters)
            self.calls = self.calls + 1
        end)
        if not ok then
            self.failed = tostring(err)
            -- Never destroy a controller/body from its physics callback. The owned Tick releases it.
            MsgN("[nlvr] tools rotation: " .. self.failed)
        end
    end
    local ok, err = pcall(function()
        entity:Spawn() entity:StartMotionController() entity:AddToMotionController(data.phys)
    end)
    if not ok then self.Stop() return nil, tostring(err) end
    return self
end
return R
