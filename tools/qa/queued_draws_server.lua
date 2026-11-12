-- QA (queued draws, ADR 0192): server Lua for tools/qa/queued_draws_session.py, sent with lua_run. The driver
-- puts the same NLQD settings table in front of it as for queued_draws_probe.lua.
-- "stress": twenty times a second, in front of the camera, two breakable props (a watermelon and a wooden
-- crate) that are broken at once into client-side gibs, three solid props removed after 0.1-0.4 s, and now
-- and then a door, opened and removed after 0.3-0.8 s. Each removal deletes a client entity whose draw may
-- still be queued for the render thread.
-- "lighting": a still scene at the same spot (one-bone props, a door and a ragdoll, all frozen), the same
-- every run, for a before/after comparison of prop lighting.
local settings = NLQD or {}
local center = settings.center or Entity(1):GetEyeTrace().HitPos
local yaw = settings.yaw or 180
local forward = Angle(0, yaw, 0):Forward()
local right = Angle(0, yaw - 90, 0):Forward()
-- The ground under the scene's centre: heights below are above it.
local ground = util.TraceLine({start = center + Vector(0, 0, 300), endpos = center - Vector(0, 0, 4000),
                               mask = MASK_SOLID_BRUSHONLY}).HitPos.z
center = Vector(center.x, center.y, ground)

local function spawn(class, model, pos, ang)
    local ent = ents.Create(class)
    if not IsValid(ent) then return nil end
    ent:SetModel(model)
    ent:SetPos(pos)
    ent:SetAngles(ang or angle_zero)
    return ent
end

local function door(pos, ang)
    local ent = spawn("prop_door_rotating", "models/props_c17/door01_left.mdl", pos, ang)
    if not IsValid(ent) then return nil end
    ent:SetKeyValue("hardware", "1")
    ent:SetKeyValue("distance", "90")
    ent:SetKeyValue("speed", "300")
    ent:SetKeyValue("returndelay", "-1")
    ent:Spawn()
    ent:Activate()
    return ent
end

local function freeze(ent)
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

if (settings.mode or "stress") == "stress" then
    -- Render load: frozen citizen ragdolls behind the churn, which studiorender skins on the CPU (r_forcehwskin 0)
    -- on the render thread, so a frame's queued draws last long enough that the main thread deletes entities
    -- whose draws are still waiting, as in the crashed VR sessions (their skinned hands, more work per frame).
    local placed = 0
    for i = 1, settings.load or 24 do
        local column, row = (i - 1) % 8, math.floor((i - 1) / 8)
        local pos = center + forward * (140 + row * 50) + right * ((column - 3.5) * 45)
        local rag = spawn("prop_ragdoll", "models/humans/group01/male_07.mdl", pos, Angle(0, yaw + 180, 0))
        if IsValid(rag) then
            rag:SetPos(Vector(pos.x, pos.y, ground - rag:OBBMins().z + 2))
            rag:Spawn()
            freeze(rag)
            placed = placed + 1
        end
    end
    print("NLQD server render load " .. placed .. " ragdolls")
    local BREAKABLE = {"models/props_junk/watermelon01.mdl", "models/props_junk/wood_crate001a.mdl"}
    local SOLID = {"models/hunter/blocks/cube025x025x025.mdl", "models/props_c17/oildrum001.mdl",
                   "models/props_junk/popcan01a.mdl"}
    local live, counts = {}, {spawned = 0, removed = 0, broken = 0, doors = 0}
    local function around(depth)
        return center + forward * math.Rand(-depth, depth) + right * math.Rand(-110, 110) + Vector(0, 0, math.Rand(20, 90))
    end
    local function prop(model)
        local ent = spawn("prop_physics", model, around(80), AngleRand())
        if not IsValid(ent) then return nil end
        ent:Spawn()
        counts.spawned = counts.spawned + 1
        return ent
    end
    timer.Create("nlqd_churn", 0.05, 0, function()
        local now = CurTime()
        for ent, dies in pairs(live) do
            if now >= dies then
                if IsValid(ent) then
                    ent:Remove()
                    counts.removed = counts.removed + 1
                end
                live[ent] = nil
            end
        end
        for _, model in ipairs(BREAKABLE) do
            local ent = prop(model)
            if IsValid(ent) then
                live[ent] = now + 1
                timer.Simple(0, function()
                    if IsValid(ent) then
                        ent:TakeDamage(1000, Entity(1), Entity(1))
                        counts.broken = counts.broken + 1
                    end
                end)
            end
        end
        for _, model in ipairs(SOLID) do
            local ent = prop(model)
            if IsValid(ent) then live[ent] = now + math.Rand(0.1, 0.4) end
        end
        if math.random() < 0.3 then
            local spot = around(40)
            local ent = door(Vector(spot.x, spot.y, ground + 1), Angle(0, math.Rand(0, 360), 0))
            if IsValid(ent) then
                ent:Fire("Open")
                counts.doors = counts.doors + 1
                live[ent] = now + math.Rand(0.3, 0.8)
            end
        end
    end)
    timer.Create("nlqd_report", 10, 0, function()
        print(string.format("NLQD server spawned %d removed %d broken %d doors %d live %d",
            counts.spawned, counts.removed, counts.broken, counts.doors, table.Count(live)))
    end)
    print("NLQD server stress started")
else
    -- A fixed scene: {class, model, units ahead, units right, height above the ground, yaw}, each frozen
    -- where it spawns, resting on the ground, so every run draws the same.
    local SCENE = {
        {"prop_physics", "models/props_c17/oildrum001.mdl", 0, -70, 0, 0},
        {"prop_physics", "models/props_junk/wood_crate001a.mdl", 10, -20, 0, 30},
        {"prop_physics", "models/props_junk/watermelon01.mdl", -30, 25, 0, 0},
        {"prop_physics", "models/hunter/blocks/cube025x025x025.mdl", -40, 55, 0, 45},
        {"prop_physics", "models/props_c17/furniturechair001a.mdl", 20, 75, 0, 200},
        {"prop_ragdoll", "models/humans/group01/male_07.mdl", 40, 10, 40, 160},
    }
    local placed = 0
    for _, row in ipairs(SCENE) do
        local pos = center + forward * row[3] + right * row[4]
        local ent = spawn(row[1], row[2], pos, Angle(0, yaw + row[6], 0))
        if IsValid(ent) then
            ent:SetPos(Vector(pos.x, pos.y, ground - ent:OBBMins().z + row[5]))
            ent:Spawn()
            freeze(ent)
            placed = placed + 1
        end
    end
    local ent = door(center + forward * 60 + right * -120 + Vector(0, 0, 1), Angle(0, yaw + 90, 0))
    print("NLQD server lighting scene " .. placed .. " props, door " .. tostring(IsValid(ent)) ..
        string.format(" ground %.1f", ground))
end
