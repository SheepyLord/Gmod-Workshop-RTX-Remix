-- Bone discovery, finger pose and the world-only collision fallback. No resources on include.
local P = {}
local function unit(value)
    return type(value) == "number" and value == value and math.Clamp(value, 0, 1) or 0
end
local function normalized(name) return (name or ""):lower():gsub("[^a-z0-9]", "") end
function P.Bones(entity, side)
    local bones = {names = {}, fingers = {}, visible = {}, count = 0, fingerCount = 0}
    local names, letter = {}, side == "left" and "l" or "r"
    for id = 0, entity:GetBoneCount() - 1 do
        local name = entity:GetBoneName(id)
        if name and name ~= "__INVALIDBONE__" then bones.names[id] = name names[normalized(name)] = id end
    end
    local function find(suffix)
        for _, prefix in ipairs({"valvebipedbip01", "bip01", ""}) do
            local id = names[prefix .. letter .. suffix]
            if id ~= nil then return id end
        end
    end
    bones.wrist, bones.forearm = find("hand"), find("forearm")
    for finger = 0, 4 do
        bones.fingers[finger + 1] = {}
        for joint = 0, 2 do
            local id = find("finger" .. finger .. (joint == 0 and "" or joint))
            bones.fingers[finger + 1][joint + 1] = id
            if id ~= nil then bones.fingerCount = bones.fingerCount + 1 end
        end
    end
    if bones.wrist ~= nil then
        for id in pairs(bones.names) do
            local parent, seen = id, {}
            while parent and parent >= 0 and not seen[parent] do
                if parent == bones.wrist or parent == bones.forearm then
                    bones.visible[id], bones.count = true, bones.count + 1 break
                end
                seen[parent], parent = true, entity:GetBoneParent(parent)
            end
        end
    end
    return bones
end
function P.Smooth(previous, priorSplay, input, grip, dt)
    local curls, splay, weight = {}, {}, 1 - math.exp(-math.min(math.max(dt, 0), 0.25) / 0.035)
    for i = 1, 5 do
        local target = unit((grip or input.curls or {})[i])
        curls[i] = previous and previous[i] + (target - previous[i]) * weight or target
    end
    for i = 1, 4 do
        local target = grip and 0 or unit((input.splay or {})[i])
        splay[i] = priorSplay and priorSplay[i] + (target - priorSplay[i]) * weight or target
    end
    return curls, splay
end
function P.Angles(finger, joint, curl, spread, side)
    local sign = side == "left" and 1 or -1
    local bend = (finger == 1 and ({40, 50, 55}) or ({75, 95, 70}))[joint] * unit(curl)
    local fan = joint == 1 and ((finger - 3.5) * 12 * unit(spread) * (1 - unit(curl))) or 0
    -- ValveBiped's thumb bends about pitch; the four fingers bend about yaw.
    -- Finger yaw is shared; thumb opposition is mirrored in its own joint's pitch basis.
    return finger == 1 and Angle(sign * bend, sign * fan, 0) or Angle(sign * fan, bend, 0)
end
function P.Apply(entity, bones, curls, splay, side)
    for finger = 1, 5 do
        for joint = 1, 3 do
            local id = bones.fingers[finger][joint]
            if id ~= nil then entity:ManipulateBoneAngles(id, P.Angles(finger, joint, curls[finger], splay[math.max(1, finger - 1)], side)) end
        end
    end
end
function P.Resolve(core, side, state)
    if not state.target.valid or not core.Pose.head or not core.Pose.head.valid or not util.TraceHull then return end
    local scale, head = core.Space.scale, core.Pose.head
    local shoulder = head.pos + Angle(0, head.ang.y, 0):Right() * (side == "left" and -0.18 or 0.18) * scale
        - Vector(0, 0, 0.18 * scale)
    local radius = 0.035 * scale
    local palmMin, palmMax = Vector(-radius, -radius, -radius), Vector(radius, radius, radius)
    local handMin, handMax = Vector(-radius, -radius, -radius), Vector(radius, radius, radius)
    -- Wrist-centred spheres let the fingers enter a wall. Cover an open hand's 18 cm reach,
    -- rotating the forward extension into a conservative world-aligned hull.
    local extension = state.target.ang:Forward() * (0.145 * scale)
    for _, axis in ipairs({"x", "y", "z"}) do
        handMin[axis] = handMin[axis] + math.min(0, extension[axis])
        handMax[axis] = handMax[axis] + math.max(0, extension[axis])
    end
    local function trace(a, b, mins, maxs)
        return util.TraceHull{start = a, endpos = b, mins = mins or palmMin,
            maxs = maxs or palmMax, mask = MASK_SOLID_BRUSHONLY, filter = LocalPlayer()}
    end
    local first = trace(head.pos, shoulder)
    if first.Hit then shoulder = first.HitPos + first.HitNormal * (0.005 * scale) end
    local hit = trace(shoulder, state.target.pos, handMin, handMax)
    if not first.StartSolid and (hit.StartSolid or hit.AllSolid) then
        local back = shoulder - state.target.ang:Forward() * (0.25 * scale)
        local probe = trace(back, back, handMin, handMax)
        if not probe.StartSolid and not probe.AllSolid and not probe.Hit then
            hit = trace(back, state.target.pos, handMin, handMax)
        end
    end
    local shown = state.target.pos
    if first.StartSolid or first.AllSolid or hit.StartSolid or hit.AllSolid then
        -- There is no known clear placement. A wrist at the eye fills both eye images.
        -- Keep the target/ray intact, but suppress this frame's world model even when a
        -- later server resolver supplies a position. The core resets validity next frame.
        state.shown.valid, state.blocked = false, true
        return
    elseif hit.Hit then shown = hit.HitPos + hit.HitNormal * (0.005 * scale) end
    -- Later resolvers may modify the shown vector in place; never alias a controller or head.
    state.shown.pos = Vector(shown.x, shown.y, shown.z)
    state.blocked = (shown - state.target.pos):Length() > 0.001 * scale
end
local contour = {{0.32,0.91},{0.28,0.65},{0.13,0.47},{0.12,0.41},{0.16,0.38},{0.22,0.40},{0.31,0.49},
    {0.29,0.21},{0.31,0.16},{0.35,0.15},{0.39,0.20},{0.42,0.41},{0.42,0.10},{0.45,0.06},{0.49,0.06},
    {0.52,0.10},{0.53,0.40},{0.57,0.14},{0.60,0.11},{0.64,0.13},{0.65,0.17},{0.64,0.43},
    {0.70,0.28},{0.74,0.26},{0.77,0.29},{0.77,0.34},{0.72,0.66},{0.67,0.78},{0.66,0.91}}
function P.Outline(side, w, h)
    surface.SetDrawColor(166, 224, 255, 220)
    for i, point in ipairs(contour) do
        local following = contour[i % #contour + 1]
        local x, nextX = point[1], following[1]
        if side == "right" then x, nextX = 1 - x, 1 - nextX end
        for offset = -1, 1 do surface.DrawLine(x * w + offset, point[2] * h, nextX * w + offset, following[2] * h) end
    end
end
return P
