-- Server half of mmd_player_session.py: times what the Advanced MMD Animation Player does on the server
-- while the client half (mmd_player_probe.lua) clicks through it. Injected through console Lua into a
-- locked PoC session; never install as an autorun.
NLMP = NLMP or {}
local Q = NLMP
Q.wrapped = Q.wrapped or {}
Q.prof = { stats = {}, stack = {}, on = false, ticks = {} }
local P = Q.prof
local clock = SysTime

local function stat(name)
    local s = P.stats[name]
    if not s then
        s = { calls = 0, incl = 0, self = 0, max = 0 }
        P.stats[name] = s
    end
    return s
end

local function leave(frame, name, ...)
    local stack = P.stack
    -- A wrapped call that raised left its frame on the stack: drop frames above ours.
    for i = #stack, 1, -1 do
        if stack[i] == frame then
            for j = #stack, i, -1 do stack[j] = nil end
            break
        end
    end
    local dt = clock() - frame.start
    local parent = stack[#stack]
    if parent then parent.child = parent.child + dt end
    local s = stat(name)
    s.calls = s.calls + 1
    s.incl = s.incl + dt
    s.self = s.self + (dt - frame.child)
    if dt > s.max then s.max = dt end
    return ...
end

local function wrap_fn(fn, name)
    if not isfunction(fn) or Q.wrapped[fn] then return fn end
    local wrapped = function(...)
        if not P.on then return fn(...) end
        local frame = { start = clock(), child = 0 }
        P.stack[#P.stack + 1] = frame
        return leave(frame, name, fn(...))
    end
    Q.wrapped[wrapped] = true
    return wrapped
end

local function wrap_field(owner, key, name)
    if istable(owner) and isfunction(owner[key]) then owner[key] = wrap_fn(owner[key], name) end
end

-- What the add-on calls through tables at call time.
local SKIP = { L = true, LFormat = true }
for key, value in pairs(MMDVMDNPC or {}) do
    if isfunction(value) and not SKIP[key] then wrap_field(MMDVMDNPC, key, "MMDVMDNPC." .. key) end
end
for key, value in pairs(MMDVMDNPC and MMDVMDNPC.Actor or {}) do
    if isfunction(value) then wrap_field(MMDVMDNPC.Actor, key, "Actor." .. key) end
end
for name in pairs(net.Receivers) do
    if string.sub(name, 1, 7) == "mmdvmd_" then wrap_field(net.Receivers, name, "net:" .. name) end
end
for _, key in ipairs({ "Exists", "Time", "Size", "Find", "Read", "Open", "Write", "IsDir", "CreateDir", "Delete" }) do
    wrap_field(file, key, "file." .. key)
end
for _, key in ipairs({ "JSONToTable", "TableToJSON", "CRC", "Compress", "Decompress" }) do
    wrap_field(util, key, "util." .. key)
end
local entity = FindMetaTable("Entity")
for _, key in ipairs({ "ManipulateBoneAngles", "ManipulateBonePosition", "ManipulateBoneScale", "ManipulateBoneJiggle",
    "SetupBones", "InvalidateBoneCache", "GetSequenceName", "GetSequenceCount", "LookupSequence", "ResetSequence",
    "SetSequence", "SetFlexWeight", "GetFlexName", "GetFlexNum", "LookupBone", "GetBoneMatrix", "SetNW2Float",
    "SetNW2Bool", "SetNWBool", "GetBoneCount", "SetCycle", "FrameAdvance" }) do
    wrap_field(entity, key, "Entity:" .. key)
end
wrap_field(FindMetaTable("Player"), "ChatPrint", "Player:ChatPrint")
for _, key in ipairs({ "Start", "Send", "Broadcast" }) do wrap_field(net, key, "net." .. key) end
if mmdhl then
    for _, key in ipairs({ "GetMorphs", "SetMorphWeight", "GetMorphWeight", "GetRig", "IsMMD", "GetMorphGeometry" }) do
        wrap_field(mmdhl, key, "mmdhl." .. key)
    end
end
for event, listeners in pairs(hook.GetTable()) do
    for id, fn in pairs(table.Copy(listeners)) do
        if isstring(id) and string.find(id, "MMDVMDNPC", 1, true) then
            hook.Add(event, id, wrap_fn(fn, "hook:" .. event .. ":" .. id))
        end
    end
end

-- Tick intervals while recording (a stalled server frame is a long interval).
hook.Add("Tick", "NLMP.Ticks", function()
    if not P.on then return end
    local now = clock()
    if P.lastTick then P.ticks[#P.ticks + 1] = now - P.lastTick end
    P.lastTick = now
end)

local function report()
    local rows = {}
    for name, s in pairs(P.stats) do
        rows[#rows + 1] = { name = name, calls = s.calls, incl_ms = s.incl * 1000, self_ms = s.self * 1000, max_ms = s.max * 1000 }
    end
    table.sort(rows, function(a, b) return a.self_ms > b.self_ms end)
    local ticks = {}
    for _, dt in ipairs(P.ticks) do ticks[#ticks + 1] = dt * 1000 end
    table.sort(ticks, function(a, b) return a > b end)
    local top = {}
    for i = 1, math.min(8, #ticks) do top[i] = ticks[i] end
    return { stats = rows, tick_count = #ticks, longest_ticks_ms = top }
end

util.AddNetworkString("nlmp_cmd")
util.AddNetworkString("nlmp_reply")

local function reply(ply, kind, data)
    local text = util.TableToJSON(data or {}) or "{}"
    file.CreateDir("nlmp_probe")
    file.Write("nlmp_probe/server_" .. kind .. ".json", text)
    net.Start("nlmp_reply")
        net.WriteString(kind)
    net.Send(ply)
end

local function first_asset()
    local _, dirs = file.Find("mmd_hotloader/assets/*", "DATA")
    table.sort(dirs or {})
    return dirs and dirs[1] or nil
end

local function ground(pos)
    local tr = util.TraceLine({ start = pos + Vector(0, 0, 64), endpos = pos - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or pos
end

-- The player stays where the map put them, facing two imported characters spawned as NPCs in front.
local function setup(ply)
    game.ConsoleCommand("sv_cheats 1\n")
    game.ConsoleCommand("ai_disabled 1\n")
    local yaw = ply:EyeAngles().y
    local facing = Angle(0, yaw, 0)
    local forward, right = facing:Forward(), facing:Right()
    local origin = ply:GetPos()
    if not ply:HasWeapon("gmod_tool") then ply:Give("gmod_tool") end
    ply:SelectWeapon("gmod_tool")
    Q.npcs = {}
    local asset = first_asset()
    local positions = { ground(origin + forward * 180 - right * 70), ground(origin + forward * 180 + right * 70) }
    local pending = #positions
    local function spawned(index, ent, err)
        if IsValid(ent) then
            ent:SetPos(positions[index])
            ent:SetAngles(Angle(0, yaw + 180, 0))
            Q.npcs[index] = ent
        else
            print("NLMP_ERROR spawn " .. tostring(err))
        end
        pending = pending - 1
        if pending > 0 then return end
        local out = { asset = asset, npcs = {} }
        for i, npc in pairs(Q.npcs) do
            out.npcs[#out.npcs + 1] = { slot = i, index = npc:EntIndex(), model = npc:GetModel(), class = npc:GetClass(),
                mmd = mmdhl and mmdhl.IsMMD and mmdhl.IsMMD(npc) or false, bones = npc:GetBoneCount(),
                sequences = npc:GetSequenceCount(), flexes = npc:GetFlexNum() }
        end
        reply(ply, "setup", out)
    end
    for i, pos in ipairs(positions) do
        if asset and mmdhl and mmdhl.SpawnNPC then
            mmdhl.SpawnNPC(ply, asset, "citizen", { position = { pos.x, pos.y, pos.z }, weapon = "none" },
                function(ent, err) spawned(i, ent, err) end)
        else
            local npc = ents.Create("npc_citizen")
            npc:SetPos(pos)
            npc:Spawn()
            spawned(i, npc, "no imported character")
        end
    end
end

-- ---- The new options in the game (the feature phase) ----
-- Server jobs run as coroutines, one step a tick.
Q.jobs = {}
hook.Add("Tick", "NLMP.Jobs", function()
    for i = #Q.jobs, 1, -1 do
        local co = Q.jobs[i]
        local ok, err = coroutine.resume(co)
        if not ok then print("NLMP_ERROR job " .. tostring(err)) end
        if coroutine.status(co) == "dead" then table.remove(Q.jobs, i) end
    end
end)
local function sleep(seconds)
    local untilTime = CurTime() + seconds
    while CurTime() < untilTime do coroutine.yield() end
end
local function job(ply, kind, fn)
    Q.jobs[#Q.jobs + 1] = coroutine.create(function()
        local ok, result = pcall(fn)
        if not ok then print("NLMP_ERROR " .. kind .. " " .. tostring(result)) end
        reply(ply, kind, ok and result or { error = tostring(result) })
    end)
end

-- A four-second test dance: both upper arms swing out over frames 0 to 4 (a dance's speed, for the push strength) and
-- stay out to the last frame (120), so the pose the dance ends on differs from the reference pose (the end hold,
-- 2026-11-16); the eyes close from frame 30 to 90 (まばたき, an imported character's blink).
Q.motionID = "nlmp_probe_dance"
local PLAY = { startDelay = 2, pelvisZOffset = -2.5, eyeTrackMode = "off", musicEnabled = false, loopPlayback = false,
    buildFramesPerBatch = 64, playbackHz = 120 }
local function probe_motion()
    local function arm(source, mmd, z)
        return { m = mmd, g = source, k = { { 0, 0, 0, 0, 0, 0, 0 }, { 4, 0, 0, z, 0, 0, 0 }, { 120, 0, 0, z, 0, 0, 0 } } }
    end
    return { format = "mmd_vmd_npc_parent_corrected_axis_v1", fps = 30, frame_start = 0, frame_end = 120, frame_count = 121,
        display_name = "NLMP probe dance", bones = { arm("ValveBiped.Bip01_R_UpperArm", "右腕", -70), arm("ValveBiped.Bip01_L_UpperArm", "左腕", 70) },
        flexes = { { m = "まばたき", g = "blink", k = { { 0, 0 }, { 30, 1 }, { 90, 1 }, { 120, 0 } } } } }
end

local function colliders_of(ent)
    local out = {}
    for _, collider in ipairs(ents.FindByClass("mmd_vmd_npc_collider")) do
        if collider:GetOwner() == ent then out[#out + 1] = collider end
    end
    return out
end
local function vec(v) return v and { math.Round(v.x, 2), math.Round(v.y, 2), math.Round(v.z, 2) } or nil end
local function bones_of(ent)
    local out = {}
    for _, name in ipairs({ "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Pelvis" }) do
        local bone = ent:LookupBone(name)
        if bone then out[name] = vec(ent:GetBonePosition(bone)) end
    end
    return out
end
local function hit(tr) return tr.Hit and (IsValid(tr.Entity) and tr.Entity:GetClass() or (tr.HitWorld and "world" or "?")) or "none" end
local function morph_id(ent, original)
    for _, morph in ipairs(mmdhl and mmdhl.GetMorphs and mmdhl.GetMorphs(ent) or {}) do
        if morph.original == original then return MMDVMDNPC.MorphControllerID(ent, morph) end
    end
end

-- Followers, the box's collision state and traces while the dance holds its arms out, then after its stop.
local function collision_test(ply)
    local npc = Q.npcs[1]
    MMDVMDNPC.DebugTargets[ply] = npc
    local out = {}
    out.start_ok, out.start_err = MMDVMDNPC.StartPlaybackForPlayer(ply, Q.motionID, {}, PLAY)
    sleep(0.3)
    local state = MMDVMDNPC.Playbacks[npc]
    local colliders = colliders_of(npc)
    out.collision_record = state and state.collision ~= nil or false
    out.colliders = #colliders
    local flagged = 0
    for _, collider in ipairs(colliders) do if collider.MMDHLSceneExcluded then flagged = flagged + 1 end end
    out.colliders_excluded_from_mmd_scene = flagged
    out.group, out.debris = npc:GetCollisionGroup(), COLLISION_GROUP_DEBRIS
    local phys = npc:GetPhysicsObject()
    out.box_collides = IsValid(phys) and phys:IsCollisionEnabled() or nil
    sleep(3.2) -- the countdown (2 s), then about frame 36: inside the held pose
    state = MMDVMDNPC.Playbacks[npc]
    out.frame = state and (CurTime() - (state.started or CurTime())) * 30 or nil
    out.bones = bones_of(npc)
    local box_mins, box_maxs = npc:OBBMins(), npc:OBBMaxs()
    out.traces = {}
    for _, name in ipairs({ "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_L_Hand" }) do
        local bone = npc:LookupBone(name)
        local at = bone and npc:GetBonePosition(bone)
        if at then
            -- Through the hand, from above and below.
            out.traces[name] = hit(util.TraceLine({ start = at + Vector(0, 0, 24), endpos = at - Vector(0, 0, 24), filter = ply }))
            local localAt = npc:WorldToLocal(at)
            out.traces[name .. " inside the box"] = localAt.x >= box_mins.x and localAt.x <= box_maxs.x and localAt.y >= box_mins.y
                and localAt.y <= box_maxs.y and localAt.z >= box_mins.z and localAt.z <= box_maxs.z
        end
    end
    -- A player-sized hull walking into the box's corner, where no body part is.
    local corner = npc:LocalToWorld(Vector(box_maxs.x - 2, box_maxs.y - 2, (box_mins.z + box_maxs.z) * 0.25))
    out.traces.box_corner_player = hit(util.TraceHull({ start = corner + Vector(0, 0, 40), endpos = corner - Vector(0, 0, 4),
        mins = Vector(-2, -2, -2), maxs = Vector(2, 2, 2), mask = MASK_PLAYERSOLID, collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT, filter = ply }))
    -- A player-sized hull walking into the head.
    local head = npc:LookupBone("ValveBiped.Bip01_Head1")
    local headAt = head and npc:GetBonePosition(head)
    if headAt then
        local side = npc:GetRight()
        out.traces.head_player = hit(util.TraceHull({ start = headAt + side * 60, endpos = headAt - side * 60,
            mins = Vector(-2, -2, -2), maxs = Vector(2, 2, 2), mask = MASK_PLAYERSOLID, collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT, filter = ply }))
    end
    -- Each collider sits on its bone: the largest gap.
    local gap = 0
    for _, entry in ipairs(state and state.collision and state.collision.colliders or {}) do
        if IsValid(entry.ent) then gap = math.max(gap, entry.ent:GetPos():Distance(npc:GetBonePosition(entry.bone))) end
    end
    out.largest_collider_gap = math.Round(gap, 2)
    -- What the Model Hotloader's hair and clothing physics captured of the scene.
    out.mmd_scene = mmdhl and mmdhl.sceneDiagnostics and table.Copy(mmdhl.sceneDiagnostics) or nil
    -- A light prop, without gravity, put where the held-out right hand is: the hand's body pushes it away.
    local hand = npc:LookupBone("ValveBiped.Bip01_R_Hand")
    local handAt = hand and npc:GetBonePosition(hand)
    Q.handOut = handAt or Q.handOut -- where push_test puts a prop in the swing's way
    local left = npc:LookupBone("ValveBiped.Bip01_L_Hand")
    Q.leftOut = left and npc:GetBonePosition(left) or Q.leftOut
    if handAt then
        local can = ents.Create("prop_physics")
        can:SetModel("models/props_junk/popcan01a.mdl")
        can:SetPos(handAt)
        can:Spawn()
        local canPhys = can:GetPhysicsObject()
        if IsValid(canPhys) then
            canPhys:EnableGravity(false)
            canPhys:Wake()
        end
        sleep(0.6)
        out.prop_moved = math.Round(can:GetPos():Distance(handAt), 2)
        can:Remove()
    end
    MMDVMDNPC.StopPlayback(npc, true)
    sleep(0.3)
    phys = npc:GetPhysicsObject()
    out.after = { colliders = #colliders_of(npc), group = npc:GetCollisionGroup(), box_collides = IsValid(phys) and phys:IsCollisionEnabled() or nil }
    return out
end

-- The user's request of 2026-11-16: what the dancing body does to props at the player's push strength
-- (mmd_vmd_npc_ragdoll_push, set by the client half: percent of the ragdoll's weight) or, with old, with the bodies
-- as they were before (shadows the physics may not move: MMDVMDNPC.Actor.body_physics and apply_push replaced for that
-- run). The bodies' masses; props without gravity put during the countdown where the hands arrive at frame 4
-- (Q.handOut and Q.leftOut, from collision_test), so the swing meets them: a metal paint can at the right hand
-- (`swing`: how far it went and its top speed, in units) and a watermelon, which breaks, at the left (`melon`: whether
-- it broke); then a pop can put inside the held-out right hand (`inside`, as collision_test does).
local function float_prop(model, at)
    local prop = ents.Create("prop_physics")
    prop:SetModel(model)
    prop:SetPos(at)
    prop:Spawn()
    local phys = prop:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(false)
        phys:Wake()
    end
    return prop, phys
end
local function watch_prop(prop, phys, from, seconds)
    local top, untilTime = 0, CurTime() + seconds
    local mass = IsValid(phys) and math.Round(phys:GetMass(), 2) or nil
    while CurTime() < untilTime do
        if not IsValid(prop) then return { broke = true, top_speed = math.Round(top, 1), mass = mass } end
        if IsValid(phys) then top = math.max(top, phys:GetVelocity():Length()) end
        coroutine.yield()
    end
    return { broke = false, moved = math.Round(prop:GetPos():Distance(from), 2), top_speed = math.Round(top, 1), mass = mass }
end
local function push_test(ply, old)
    local npc = Q.npcs[1]
    local actor = MMDVMDNPC.Actor
    local savedBody, savedApply = actor.body_physics, actor.apply_push
    if old then
        actor.body_physics = function(collider)
            collider:MakePhysicsObjectAShadow(false, false)
            local phys = collider:GetPhysicsObject()
            if IsValid(phys) then phys:Wake() end
        end
        actor.apply_push = function(record, strength) record.strength = strength end
    end
    local out = { old = old == true, strength = actor.push_strength(ply) }
    local ok, err = pcall(function()
        out.start_ok, out.start_err = MMDVMDNPC.StartPlaybackForPlayer(ply, Q.motionID, {}, PLAY)
        sleep(0.3)
        local state = MMDVMDNPC.Playbacks[npc]
        out.body_masses = {}
        for _, entry in ipairs(state and state.collision and state.collision.colliders or {}) do
            local phys = IsValid(entry.ent) and entry.ent:GetPhysicsObject()
            if IsValid(phys) then out.body_masses[#out.body_masses + 1] = math.Round(phys:GetMass(), 2) end
        end
        if Q.handOut and Q.leftOut then
            local can, canPhys = float_prop("models/props_junk/metal_paintcan001a.mdl", Q.handOut)
            local melon = float_prop("models/props_junk/watermelon01.mdl", Q.leftOut)
            local startAt = state and tonumber(state.started) or CurTime()
            while CurTime() < startAt do coroutine.yield() end
            out.swing = watch_prop(can, canPhys, Q.handOut, 1.6) -- frames 0 to about 48
            out.melon = { broke = not IsValid(melon) }
            if IsValid(can) then can:Remove() end
            if IsValid(melon) then melon:Remove() end
        end
        local hand = npc:LookupBone("ValveBiped.Bip01_R_Hand")
        local handAt = hand and npc:GetBonePosition(hand)
        if handAt then
            local can, canPhys = float_prop("models/props_junk/popcan01a.mdl", handAt)
            out.inside = watch_prop(can, canPhys, handAt, 0.6)
            if IsValid(can) then can:Remove() end
        end
    end)
    actor.body_physics, actor.apply_push = savedBody, savedApply
    if not ok then out.error = tostring(err) end
    MMDVMDNPC.StopPlayback(npc, true)
    sleep(0.3)
    return out
end

-- The user's request of 2026-11-16: a dance that ends keeps its last pose for MMDVMDNPC.EndHoldSeconds, then the NPC
-- returns to the reference pose. The right hand (held out to the last frame) half a second before the end, one and
-- two and a half seconds after it, and after the stop; when the playback ended, to the tick.
local function endhold_test(ply)
    local npc = Q.npcs[1]
    local out = { hold_seconds = MMDVMDNPC.EndHoldSeconds }
    out.start_ok, out.start_err = MMDVMDNPC.StartPlaybackForPlayer(ply, Q.motionID, {}, PLAY)
    sleep(0.2)
    local state = MMDVMDNPC.Playbacks[npc]
    local built = state and state.built or {}
    local danceEnd = (state and tonumber(state.started) or CurTime())
        + ((tonumber(built.frame_end) or 120) - (tonumber(built.frame_start) or 0)) / math.max(1, tonumber(built.fps) or 30)
    local hand = npc:LookupBone("ValveBiped.Bip01_R_Hand")
    local function sample(label, at)
        while CurTime() < danceEnd + at do coroutine.yield() end
        out[label] = { t = math.Round(CurTime() - danceEnd, 2), playing = MMDVMDNPC.Playbacks[npc] ~= nil,
            hand = hand and vec(npc:GetBonePosition(hand)) or nil }
    end
    sample("before_end", -0.5)
    sample("hold_1s", 1)
    sample("hold_2_5s", 2.5)
    while CurTime() < danceEnd + 6 and MMDVMDNPC.Playbacks[npc] do coroutine.yield() end
    out.stopped_after_end = not MMDVMDNPC.Playbacks[npc] and math.Round(CurTime() - danceEnd, 3) or nil
    sleep(0.3)
    out.after_stop = { playing = MMDVMDNPC.Playbacks[npc] ~= nil, hand = hand and vec(npc:GetBonePosition(hand)) or nil }
    if MMDVMDNPC.Playbacks[npc] then MMDVMDNPC.StopPlayback(npc, true) end
    return out
end

-- An expression the dance does not drive (笑い) and one it drives (まばたき), with keep-expressions on or off.
local function flex_test(ply)
    local npc = Q.npcs[2]
    local smile, blink = morph_id(npc, "笑い"), morph_id(npc, "まばたき")
    local function weights()
        return { smile = smile and math.Round(MMDVMDNPC.GetModelFlexWeight(npc, smile), 3) or nil,
            blink = blink and math.Round(MMDVMDNPC.GetModelFlexWeight(npc, blink), 3) or nil }
    end
    local out = { smile_id = smile, blink_id = blink }
    MMDVMDNPC.SelectTargetForPlayer(ply, npc)
    if smile then MMDVMDNPC.SetModelFlexWeight(npc, smile, 0.6) end
    sleep(0.2)
    out.set = weights()
    MMDVMDNPC.SelectTargetForPlayer(ply, npc)
    sleep(0.2)
    out.after_select = weights()
    if smile then MMDVMDNPC.SetModelFlexWeight(npc, smile, 0.6) end
    sleep(0.2)
    out.start_ok, out.start_err = MMDVMDNPC.StartPlaybackForPlayer(ply, Q.motionID, {}, PLAY)
    sleep(0.3)
    out.at_start = weights()
    sleep(3.6) -- about frame 48: the eyes are closed
    out.dancing = weights()
    MMDVMDNPC.StopPlayback(npc, true)
    sleep(0.3)
    out.after_stop = weights()
    if smile then MMDVMDNPC.SetModelFlexWeight(npc, smile, 0) end
    return out
end

local function build_test(ply)
    local npc = Q.npcs[1]
    file.CreateDir(MMDVMDNPC.MotionRoot)
    file.Write(MMDVMDNPC.MotionPath(Q.motionID), util.TableToJSON(probe_motion()))
    MMDVMDNPC.ClearMotionCache()
    local path = MMDVMDNPC.BuiltPath(Q.motionID, npc:GetModel(), {})
    if file.Exists(path, "DATA") then file.Delete(path) end
    MMDVMDNPC.BuiltCache[path] = nil
    local out = { path = path }
    out.select_ok, out.select_err = MMDVMDNPC.SelectTargetForPlayer(ply, npc)
    out.build_ok, out.build_err = MMDVMDNPC.BeginBuildForPlayer(ply, Q.motionID, {}, PLAY)
    local began = CurTime()
    while not file.Exists(path, "DATA") and CurTime() - began < 120 do sleep(0.25) end
    out.built = file.Exists(path, "DATA")
    out.seconds = CurTime() - began
    return out
end

-- What the engine's bone followers are on this NPC: the functions, what CreateBoneFollowers makes and how
-- each follower relates to its NPC (owner, parent, GetBoneFollowers).
local function follower_probe()
    local npc = Q.npcs[1]
    local out = { create = npc.CreateBoneFollowers ~= nil, update = npc.UpdateBoneFollowers ~= nil,
        destroy = npc.DestroyBoneFollowers ~= nil, get = npc.GetBoneFollowers ~= nil, model = npc:GetModel(),
        physics_objects = npc:GetPhysicsObjectCount() }
    out.before = #ents.FindByClass("phys_bone_follower")
    out.create_ok, out.create_err = pcall(npc.CreateBoneFollowers, npc)
    out.create_err = out.create_err ~= nil and tostring(out.create_err) or nil
    sleep(0.1)
    out.after = #ents.FindByClass("phys_bone_follower")
    out.followers = {}
    for _, f in ipairs(ents.FindByClass("phys_bone_follower")) do
        local phys = f:GetPhysicsObject()
        out.followers[#out.followers + 1] = { owner = tostring(f:GetOwner()), parent = tostring(f:GetParent()), pos = vec(f:GetPos()),
            solid = f:GetSolid(), group = f:GetCollisionGroup(), phys = IsValid(phys), moving = IsValid(phys) and phys:IsMotionEnabled() or nil }
    end
    if npc.GetBoneFollowers then
        local ok, list = pcall(npc.GetBoneFollowers, npc)
        out.get_ok = ok
        if ok and istable(list) then
            out.get_count = #list
            local first = list[1]
            if istable(first) then
                out.get_first = {}
                for key, value in pairs(first) do out.get_first[tostring(key)] = tostring(value) end
            else
                out.get_first = tostring(first)
            end
        else
            out.get_value = tostring(list)
        end
    end
    if npc.UpdateBoneFollowers then out.update_ok, out.update_err = pcall(npc.UpdateBoneFollowers, npc) end
    out.update_err = out.update_err ~= nil and tostring(out.update_err) or nil
    if npc.DestroyBoneFollowers then out.destroy_ok = pcall(npc.DestroyBoneFollowers, npc) end
    sleep(0.1)
    out.after_destroy = #ents.FindByClass("phys_bone_follower")
    return out
end

local function debug_state(ply)
    local last = MMDVMDNPC.LastDebugFrame and MMDVMDNPC.LastDebugFrame[ply]
    return { frame = last and last.frame or nil, motion = last and last.motionID or nil, bones = bones_of(Q.npcs[1]) }
end

net.Receive("nlmp_cmd", function(_, ply)
    local cmd = net.ReadString()
    if cmd == "build" then job(ply, "build", function() return build_test(ply) end) return end
    if cmd == "collision" then job(ply, "collision", function() return collision_test(ply) end) return end
    if cmd == "followers" then job(ply, "followers", function() return follower_probe() end) return end
    if cmd == "flexes" then job(ply, "flexes", function() return flex_test(ply) end) return end
    if cmd == "push" then job(ply, "push", function() return push_test(ply, false) end) return end
    if cmd == "push_old" then job(ply, "push_old", function() return push_test(ply, true) end) return end
    if cmd == "endhold" then job(ply, "endhold", function() return endhold_test(ply) end) return end
    if cmd == "select1" then
        reply(ply, "select1", { ok = MMDVMDNPC.SelectTargetForPlayer(ply, Q.npcs[1]) })
        return
    end
    if cmd == "debug_state" then reply(ply, "debug_state", debug_state(ply)) return end
    if cmd == "cleanup" then
        local path = MMDVMDNPC.BuiltPath(Q.motionID, Q.npcs[1]:GetModel(), {})
        file.Delete(path)
        file.Delete(MMDVMDNPC.MotionPath(Q.motionID))
        reply(ply, "cleanup", {})
        return
    end
    if cmd == "setup" then
        setup(ply)
    elseif cmd == "begin" then
        P.stats, P.stack, P.ticks, P.lastTick = {}, {}, {}, nil
        P.on = true
    elseif cmd == "end" then
        P.on = false
        reply(ply, "window", report())
    elseif cmd == "wrap_tool" then
        local tool = ply:GetTool("mmd_vmd_npc")
        if tool then
            for _, key in ipairs({ "LeftClick", "RightClick", "Reload" }) do wrap_field(tool, key, "TOOL:" .. key) end
        end
        reply(ply, "wrap_tool", { tool = tool ~= nil })
    end
end)

print("NLMP_SERVER_READY")
