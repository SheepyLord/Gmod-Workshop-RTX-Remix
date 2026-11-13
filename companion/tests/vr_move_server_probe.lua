-- Test fixture only, sent as admin console Lua by vr_move_session.py after both shared locks.
local ID, props = "nlvr_L_fixture", {}
local base
-- Select actual open, flat map ground. The stock spawn corridor has an east wall;
-- unrestricted distance tests must not accidentally measure that collision instead.
for _, xy in ipairs({{-1000, -1000}, {-512, -512}, {-1536, -512}, {-768, 0}}) do
    local floor = util.TraceLine({start = Vector(xy[1], xy[2], 1000), endpos = Vector(xy[1], xy[2], -1000),
        mask = MASK_PLAYERSOLID, filter = Entity(1)})
    local at, clear = floor.HitPos + Vector(0, 0, 1), floor.Hit and floor.HitNormal.z > 0.99
    for _, segment in ipairs({{Vector(), Vector(900, 0, 0)}, {Vector(40, 0, 0), Vector(40, 450, 0)},
        {Vector(40, 450, 0), Vector(900, 450, 0)}}) do
        local hit = util.TraceHull({start = at + segment[1], endpos = at + segment[2],
            mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID, filter = Entity(1)})
        clear = clear and not (hit.Hit or hit.StartSolid or hit.AllSolid)
    end
    if clear then base = at break end
end
assert(base, "No open movement fixture on gm_construct")
local function clear()
    for _, ent in ipairs(props) do if IsValid(ent) then ent:Remove() end end
    props = {}
end
local function block(p, offset, model)
    local ent = ents.Create("prop_physics")
    ent:SetModel(model) ent:SetPos(p:GetPos() + offset) ent:Spawn()
    local phys = ent:GetPhysicsObject() if IsValid(phys) then phys:EnableMotion(false) end
    props[#props + 1] = ent
    return ent
end
local function emit(label, p)
    print("NLVR_Q " .. util.TableToJSON({kind = "L-server", label = label, position = p:GetPos(), base = base,
        movement = NLVR_SV and NLVR_SV.Players[p] and NLVR_SV.Players[p].move, time = CurTime()}))
end
concommand.Add("nlvr_L_stage", function(p, _, a)
    if not IsValid(p) then p = Entity(1) end
    if not IsValid(p) or not (game.SinglePlayer() or p:IsListenServerHost()) then return end
    local stage = a[1]
    if stage == "start" or stage == "reset" then
        clear() p:SetMoveType(MOVETYPE_WALK) p:SetPos(base) p:SetVelocity(-p:GetVelocity()) p:SetEyeAngles(Angle())
    elseif stage == "noclip" then
        clear() p:SetMoveType(MOVETYPE_NOCLIP)
    elseif stage == "wall" then
        -- The actual BSP wall at x=1024, independently found in the first run. The
        -- 32-unit hull must stop at x=1008; no synthetic prop collision is assumed.
        clear() p:SetMoveType(MOVETYPE_WALK) p:SetPos(Vector(984, -657, -143)) p:SetVelocity(-p:GetVelocity())
    elseif stage == "ledge" then
        clear() p:SetMoveType(MOVETYPE_WALK) p:SetPos(base) p:SetVelocity(-p:GetVelocity())
        block(p, Vector(190, -10, 24), "models/hunter/blocks/cube2x2x1.mdl")
    elseif stage == "ceiling" then
        clear() p:SetMoveType(MOVETYPE_WALK) p:SetPos(base) p:SetVelocity(-p:GetVelocity())
        block(p, Vector(190, -10, 52), "models/hunter/blocks/cube4x4x025.mdl")
    elseif stage == "clear" then clear() p:SetPos(base) p:SetVelocity(-p:GetVelocity())
    elseif stage == "cleanup" then clear() hook.Remove("FinishMove", ID) concommand.Remove("nlvr_L_stage") end
    emit(stage, p)
end)
local nextLog = 0
hook.Add("FinishMove", ID, function(p, mv)
    if not NLVR_SV or not NLVR_SV.Players[p] then return end
    local movement = NLVR_SV.Players[p].move
    if CurTime() < nextLog and not (movement and movement.teleport) then return end
    nextLog = CurTime() + 0.2
    print("NLVR_Q " .. util.TableToJSON({kind = "L-server-move", position = mv:GetOrigin(), velocity = mv:GetVelocity(),
        movement = NLVR_SV.Players[p].move, duck = p:Crouching(), ground = p:OnGround(), time = CurTime()}))
end)
Entity(1):ConCommand("nlvr_L_stage start")
