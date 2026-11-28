-- Installed only in the WU PoC's temporary add-on. The client probe drives the two launches.
if SERVER then AddCSLuaFile() AddCSLuaFile("nl_wu/probe.lua") end
if not game.SinglePlayer() or game.GetMap() ~= "gm_flatgrass" then return end
local request = util.JSONToTable(file.Read("nl_wu/run.json", "DATA") or "")
if not request or not isstring(request.token) or (request.phase ~= "v1" and request.phase ~= "v2") then return end
if CLIENT then
    -- Same-map Sandbox normally pastes in place. If gm_load creates a fresh realm, continue at
    -- the saved actor, with the second screenshot still due to the same poc_session process.
    hook.Add("InitPostEntity", "NL.WU.ResumeSave", function()
        local pending = util.JSONToTable(file.Read("nl_wu/restoring.json", "DATA") or "")
        if request.phase == "v2" and pending and pending.token == request.token then include("nl_wu/probe.lua") end
    end)
    return
end

local waiting, subject, model, sequence
local facing = Angle(0, 0, 0)
local function pose(ent, kind)
    subject = ent
    model, sequence = nil, nil
    ent:SetMoveType(MOVETYPE_NONE)
    ent:SetSchedule(SCHED_WAIT_FOR_SCRIPT)
    ent:SetNW2String("NLWUSubject", request.token .. "/" .. kind)
end

-- Aim the host at level ground ahead. The menu's normal spawn request then uses the host's
-- authoritative eye trace, including its ordinary position, facing and spawn permission checks.
concommand.Add("nl_wu_aim", function(ply)
    if not IsValid(ply) or ply ~= Entity(1) then return end
    local forward = Angle(0, ply:EyeAngles().y, 0):Forward()
    for _, distance in ipairs({120, 90, 150}) do
        local ahead = ply:GetPos() + forward * distance
        local floor = util.TraceLine({start = ahead + Vector(0, 0, 64), endpos = ahead - Vector(0, 0, 192),
            mask = MASK_SOLID_BRUSHONLY})
        if floor.Hit and not floor.StartSolid and floor.HitNormal.z > .98 then
            local aim = (floor.HitPos - ply:EyePos()):Angle()
            local trace = util.TraceLine({start = ply:EyePos(), endpos = floor.HitPos - Vector(0, 0, 1), filter = ply})
            if trace.Hit and trace.HitPos:DistToSqr(floor.HitPos) < 9 then
                ply:SetEyeAngles(aim)
                waiting = true
                ply:SetNW2Vector("NLWUGround", floor.HitPos)
                ply:SetNW2String("NLWUAimed", request.token .. "/" .. request.phase)
                return
            end
        end
    end
    ply:SetNW2String("NLWUAimError", "No clear level ground in front of the host")
end)

hook.Add("MMDHLActorCreated", "NL.WU.Citizen", function(ent, rig)
    if request.phase ~= "v1" or not waiting or rig.role ~= "citizen" or ent:GetClass() ~= "npc_citizen" then return end
    waiting = false
    pose(ent, request.phase)
    duplicator.StoreEntityModifier(ent, "NLWUSavedCitizen", {token = request.token})
end)

hook.Add("PlayerSpawnedNPC", "NL.WU.NPCTab", function(_, ent)
    if request.phase == "v2" and waiting and ent:GetClass() == "npc_citizen" then
        waiting = false
        timer.Simple(0, function() if IsValid(ent) then pose(ent, "v2") end end)
    end
end)

-- Only Sandbox restoring this run's actual saved entity can set the restored marker. Its asset
-- and rig are supplied by the Hotloader's own persistence path.
duplicator.RegisterEntityModifier("NLWUSavedCitizen", function(_, ent, data)
    if request.phase == "v2" and IsValid(ent) and ent:GetClass() == "npc_citizen"
        and istable(data) and data.token == request.token then
        pose(ent, "restored")
    end
end)

hook.Add("Think", "NL.WU.Reference", function()
    if not IsValid(subject) then return end
    if subject:GetModel() ~= model or not sequence or sequence < 0 then
        model = subject:GetModel()
        sequence = subject:LookupSequence("Reference")
    end
    if not sequence or sequence < 0 then return end
    subject:SetAngles(facing)
    if subject:GetSequence() ~= sequence then subject:ResetSequence(sequence) end
    subject:SetCycle(0)
    subject:SetPlaybackRate(0)
    for i = 0, subject:GetNumPoseParameters() - 1 do
        subject:SetPoseParameter(subject:GetPoseParameterName(i), 0)
    end
end)
