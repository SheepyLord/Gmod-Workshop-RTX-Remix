-- Client entry point for both WU launches. The isolated PoC shares DATA with its listen server.
local dir = "nl_wu/"
local function read(path)
    return util.JSONToTable(file.Read(path, "DATA") or "", true, true)
end
local request = read(dir .. "run.json") or {}
local phase, token = request.phase, request.token
if NL_WU_ACTIVE and token and NL_WU_ACTIVE == token .. "/" .. tostring(phase) then return end
NL_WU_ACTIVE = tostring(token) .. "/" .. tostring(phase)
local old = "7c6d7e466389899bbdd2c9d614e1dacbf8a1a62bfa1b2af0083742553aeda89c"
local revised = "a95c9a34a5eec099b19769e8968b64fa2947e738d34fdb17711dd2ee170bde50"
local helena = "81b3caae0303d15a610ef213bd4c64366c9b9e2f6dda1eae2e5d5fa49a74c80b"
local digest = {v1 = "663b8b295a042f8e8f448a8d4f4734d1d74b5f062d1368d0340cd38ca1bbae5a",
    v2 = "2747fec1c9ae250309ab6c9a01100d0a10bf874173f9be4d893a0b1c4dd83c59"}
local gym = phase == "v1" and old or revised
local label = "Faelynn (Gym Uniform)"
local cache = "mmd_hotloader/"
local stage, failed, finished = "start", 0, false
local camera, baseline
local totalDeadline = RealTime() + 720

local function emit(event, row)
    row = row or {}
    row.event, row.phase, row.run = event, phase, token
    local line = "NL_WU " .. util.TableToJSON(row, false)
    assert(#line < 500 and not line:find("[\r\n]"), "WU result exceeds the console line limit: " .. event)
    print(line)
end
local function check(ok, name)
    if not ok then failed = failed + 1 emit("mismatch", {check = name}) end
    return ok
end
local function stop(why)
    if finished then return end
    finished = true
    for _, event in ipairs({"Think", "CalcView", "PostRender"}) do hook.Remove(event, "NL.WU.Probe") end
    camera = nil
    local reason = why and tostring(why):gsub("[%c]", " "):sub(1, 180)
    emit("result", {ok = not why and failed == 0, mismatches = failed, stage = stage, reason = reason})
    print("NL_SHOT_DONE")
end
-- Poll from Think. A timeout records the last actual observation through its reporter.
local function waitFor(name, seconds, poll, report, optional)
    stage = name
    local untilTime = math.min(totalDeadline, RealTime() + seconds)
    repeat
        local ready, observed = poll()
        if ready then return observed end
        if RealTime() >= untilTime then
            if report and observed then report(observed) end
            if optional then check(false, name .. " timed out") return observed end
            error(name .. " timed out" .. (isstring(observed) and ": " .. observed or ""), 0)
        end
        coroutine.yield()
    until false
end
local function libraryState()
    if not mmdhl or not mmdhl.workshop or not mmdhl.library then return false, "Hotloader unavailable" end
    local w, rows, gyms = mmdhl.workshop, {}, 0
    local gymOK, controlOK = false, false
    for id, e in pairs(mmdhl.library.entries or {}) do
        local package = e.workshop and e.workshop.package or ""
        if id == old or id == revised or id == helena or e.name == label or package == request.package then
            rows[#rows + 1] = {asset = id, name = e.name, package = package}
            if id == old or id == revised or e.name == label then gyms = gyms + 1 end
            if package == request.package and id == gym and e.name == label then gymOK = true end
            if package == request.package and id == helena and e.name == "Helena (Dorm)" then controlOK = true end
        end
    end
    table.sort(rows, function(a, b) return a.asset < b.asset end)
    local state = {rows = rows, gyms = gyms, busy = w.Busy(), replacement = w.Replacement(old)}
    local function installed(id)
        local rec = w.state.assets[w.Key("character", id)]
        return rec and rec.installed and not rec.pending and not rec.hidden
    end
    return not state.busy and #rows == 2 and gyms == 1 and gymOK and controlOK and installed(gym) and installed(helena)
        and (phase ~= "v2" or state.replacement == revised), state
end
local function printLibrary(s)
    if not istable(s) then return end
    for _, row in ipairs(s.rows) do emit("entry", table.Copy(row)) end
    emit("library", {entries = #s.rows, gym_rows = s.gyms, busy = s.busy, replacement = s.replacement})
end
local function control()
    local rel = "assets/" .. helena .. "/manifest.json"
    local raw = file.Read(cache .. rel, "DATA") or ""
    local rec = mmdhl.workshop.state.assets["character:" .. helena]
    local sha = util.SHA256(raw)
    emit("helena", {asset = helena, bytes = #raw, sha256 = sha, recorded = rec.sums and rec.sums[rel]})
    check(#raw == 63247 and sha == digest[phase] and rec.sums and rec.sums[rel] == sha, "Helena manifest bytes and install record")
end
local function rigRow(r)
    return r and {key = r.key, asset = r.asset, role = r.role, model = r.model, scale = r.scaleMultiplier} or {}
end
local cachedRigs = {}
local function actorState()
    local p = LocalPlayer()
    local bodyModel = p:GetModel() or ""
    local handsModel = IsValid(p:GetHands()) and p:GetHands():GetModel() or ""
    local body, hands = rigRow(mmdhl.GetRigForModel(bodyModel)), rigRow(mmdhl.GetRigForModel(handsModel))
    local selected = GetConVar("cl_playermodel"):GetString()
    local approved = read(cache .. "approved.json") or {}
    local uses = (read(cache .. "recent.json") or {}).uses or {}
    local s = {body = body, hands = hands, bodyModel = bodyModel, handsModel = handsModel, selected = selected,
        attached = mmdhl.GetAsset(p), bodyKey = p:GetNW2String("MMDHLRig"), armsKey = p:GetNW2String("MMDHLArms"),
        published = {}, uses = uses}
    local stale, playerOK, handsOK = false, false, false
    for key, entry in pairs(approved.rigs or {}) do
        if entry.asset == old or entry.asset == revised then
            if not cachedRigs[key] then
                local raw = read(cache .. "rigs/" .. key .. "/rig.json")
                if raw and raw.key == key then cachedRigs[key] = rigRow(raw) end
            end
            local r = table.Copy(cachedRigs[key] or {})
            r.indexKey, r.indexAsset, r.arms = key, entry.asset, entry.arms
            s.published[#s.published + 1] = r
            if entry.role == "citizen" or entry.role == "player" or entry.role == "arms" then
                if entry.asset ~= gym or r.asset ~= gym then stale = true end
                if r.key == key and r.role == entry.role and math.abs((r.scale or 0) - 1.15) < .001 then
                    if entry.role == "citizen" then
                        local npc = list.Get("NPC")["mmd_" .. key:sub(1, 16)]
                        if npc and npc.MMDHLAsset == gym and npc.MMDHLRig == key and npc.Model == r.model then s.citizen = key end
                    elseif entry.role == "player" and key == body.key and entry.arms == hands.key then playerOK = true
                    elseif entry.role == "arms" and key == hands.key then handsOK = true end
                end
            end
        end
    end
    for _, pair in ipairs(uses) do
        if pair[1] == gym then s.used = pair[2] end
        if phase == "v2" and pair[1] == old then stale = true end
    end
    local ok = s.citizen and playerOK and handsOK and not stale and s.attached == gym
        and body.asset == gym and hands.asset == gym and body.key == s.bodyKey and hands.key == s.armsKey
        and selected == "mmd_" .. body.key:sub(1, 16) and player_manager.AllValidModels()[selected] == bodyModel
        and s.used and (not baseline or s.used >= baseline.used)
    return ok, s
end
local function printHistory(s, when)
    for _, entry in ipairs(s.published) do
        local row = table.Copy(entry) row.when = when emit("published", row)
    end
    for _, pair in ipairs(s.uses) do emit("recent", {when = when, asset = pair[1], used = pair[2]}) end
end
local function printActors(s)
    emit("player", {selector = s.selected, asset = s.attached, body_key = s.bodyKey, arms_key = s.armsKey,
        previous_selector = baseline and baseline.selector})
    for _, pair in ipairs({{"body", s.body, s.bodyModel}, {"hands", s.hands, s.handsModel}}) do
        local row = table.Copy(pair[2]) row.actual_model = pair[3] row.part = pair[1] emit("rendered", row)
    end
    emit("npc_entry", {key = s.citizen})
    printHistory(s, phase == "v1" and "choices" or "before_spawn")
end
local function menuSpawn(role)
    local options = mmdhl.GetGlobalSettings()
    options.role, options.gender, options.scaleMultiplier = role, "female", 1.17
    options.armsParts = mmdhl.GetArmsParts(gym)
    options.bodygroups = mmdhl.BodygroupSpawnState(gym)
    local saved, saveError = mmdhl.library.Update(gym, {spawn = {scaleMultiplier = options.scaleMultiplier}})
    assert(saved, tostring(saveError))
    local reply, err
    local ok, why = mmdhl.RequestSpawn(gym, options, function(state, message, index)
        if state == "ready" then reply = index elseif state == "error" then err = message end
    end)
    assert(ok, tostring(why))
    return waitFor("menu_" .. role, 85, function()
        if err then error(tostring(err), 0) end
        return reply and IsValid(Entity(reply)), reply and Entity(reply)
    end)
end
local function tagged(kind)
    for _, ent in ipairs(ents.FindByClass("npc_citizen")) do
        if ent:GetNW2String("NLWUSubject") == token .. "/" .. kind then return true, ent end
    end
    return false, "waiting for the " .. kind .. " Citizen"
end
local function spawnCitizen(key)
    RunConsoleCommand("nl_wu_aim")
    waitFor("aim", 15, function()
        local ply = LocalPlayer()
        local err = ply:GetNW2String("NLWUAimError", "") if err ~= "" then error(err, 0) end
        local tr = ply:GetEyeTrace()
        return ply:GetNW2String("NLWUAimed", "") == token .. "/" .. phase and tr.Hit
            and tr.HitPos:DistToSqr(ply:GetNW2Vector("NLWUGround", Vector(0, 0, 0))) < 16
    end)
    local placed
    if phase == "v1" then placed = menuSpawn("citizen")
    else
        assert(key, "no migrated Citizen in the NPC tab")
        RunConsoleCommand("gmod_spawnnpc", "mmd_" .. key:sub(1, 16), "none")
    end
    local ent = waitFor("spawned_citizen", 75, function() return tagged(phase) end)
    assert(not placed or placed == ent, "pose marker belongs to a different NPC")
    local ply = LocalPlayer()
    local front = (ent:GetPos() - ply:GetPos()):Dot(Angle(0, ply:EyeAngles().y, 0):Forward())
    emit("spawn", {class = ent:GetClass(), entity = ent:EntIndex(), forward = front, npc_key = key})
    check(front > 0, "Citizen in front of host")
    return ent
end

-- Measure the palette the Hotloader submitted this frame. Keep the side view live until the
-- external screenshotter acknowledges its ordinal, including across an in-place save load.
hook.Add("CalcView", "NL.WU.Probe", function()
    if not camera or not IsValid(camera.ent) then return end
    local center = camera.head or (camera.ent:GetPos() + Vector(0, 0, 55))
    local eye = center + Angle(0, 0, 0):Right() * 48
    camera.viewFrame = FrameNumber()
    return {origin = eye, angles = (center - eye):Angle(), fov = 32, znear = 1, drawviewer = true}
end)
local function sample()
    local c = camera
    if not c or c.measured or not IsValid(c.ent) or c.viewFrame ~= FrameNumber() then return end
    local ent = c.ent
    local rig = mmdhl.GetRig(ent)
    c.problem = "waiting for the Reference sequence and a newly presented palette"
    local seq = ent:GetSequenceName(ent:GetSequence()) or ""
    if not rig or seq:lower() ~= "reference" or math.abs(ent:GetCycle()) > .01 or mmdhl.GetInstance(ent) < 1
        or ent.MMDPresentationStopped or ent.MMDPresentationFrame ~= FrameNumber() or not ent.MMDRenderPose then return end
    local function point(name)
        local i = ent:LookupBone(name)
        local matrix = i and ent.MMDRenderPose[i + 1]
        return matrix and matrix:GetTranslation()
    end
    local head, left, right = point("ValveBiped.Bip01_Head1"), point("Eye_L"), point("Eye_R")
    if not (head and left and right) then c.problem = "head or eye matrix missing" return end
    c.head = head
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() then c.problem = "game UI covers the camera" return end
    c.since = c.since or RealTime()
    if RealTime() - c.since < .6 then return end
    local distance = ((left + right) * .5 - head):Length()
    c.measured = {view = c.kind, asset = mmdhl.GetAsset(ent), rig_asset = rig.asset, key = rig.key,
        role = rig.role, scale = rig.scaleMultiplier, sequence = seq, cycle = ent:GetCycle(),
        distance = distance, entity = ent:EntIndex(), model = ent:GetModel()}
    emit("head", table.Copy(c.measured))
    print("NL_SHOT wu_" .. c.kind .. "_head")
end
hook.Add("PostRender", "NL.WU.Probe", function()
    local ok, err = pcall(sample) if not ok then stop(err) end
end)
concommand.Add("nl_shot_taken", function(_, _, args)
    if camera and camera.measured and tonumber(args[1]) == camera.ordinal then camera.ack = true end
end)
local function photograph(ent, kind, expectedKey)
    camera = {ent = ent, kind = kind, ordinal = kind == "restored" and 2 or 1}
    local h = waitFor(kind .. "_head", 90, function()
        return camera.ack, camera.ack and camera.measured or camera.problem
    end)
    camera = nil
    local id = kind == "v2" and revised or old
    check(h.asset == id and h.rig_asset == id and h.role == "citizen", kind .. " Citizen asset")
    check(not expectedKey or h.key == expectedKey, kind .. " Citizen carrier key")
    check(math.abs((h.scale or 0) - 1.15) <= .001, kind .. " menu scale")
    check(math.abs(h.distance - (kind == "v2" and 2.607 or 2.756)) <= .03, kind .. " eye midpoint to head")
    return h
end

local function saveNames()
    return file.Find("saves/*.gms", "MOD") or {}
end
local function saveGame()
    local before = {} for _, name in ipairs(saveNames()) do before[name] = true end
    RunConsoleCommand("gm_save")
    local lastSize, since
    local path = waitFor("write_sandbox_save", 75, function()
        local found
        for _, name in ipairs(saveNames()) do if not before[name] then
            assert(not found, "more than one new Sandbox save")
            assert(not name:find('[/\\;%c"]'), "invalid local save filename")
            found = "saves/" .. name
        end end
        local size = found and file.Size(found, "MOD") or -1
        if size ~= lastSize then lastSize, since = size, RealTime() end
        return size > 0 and RealTime() - since >= 1, found
    end)
    local raw = assert(file.Read(path, "MOD"), "new Sandbox save unreadable")
    local saved = {path = path, bytes = #raw, sha256 = util.SHA256(raw)}
    emit("save", table.Copy(saved))
    return saved
end
local function restored()
    local ent = waitFor("saved_entity_modifier", 150, function() return tagged("restored") end)
    photograph(ent, "restored", baseline.citizen)
    check(not tagged("v2"), "save replaced the v2 test NPC")
    printLibrary(waitFor("library_after_load", 90, libraryState, printLibrary))
    file.Delete(dir .. "restoring.json")
end
local function run()
    assert(game.SinglePlayer() and game.GetMap() == "gm_flatgrass" and engine.ActiveGamemode() == "sandbox",
        "expected single-player Sandbox on gm_flatgrass")
    assert(isstring(token) and (phase == "v1" or phase == "v2") and isstring(request.package), "missing WU test request")
    if phase == "v2" then
        baseline = assert(read(dir .. "baseline.json"), "missing v1 baseline")
        assert(baseline.token == token, "v1 baseline belongs to another run")
    end
    waitFor("client", 60, function() return IsValid(LocalPlayer()) and mmdhl and mmdhl.GetRig end)
    local pending = read(dir .. "restoring.json")
    if phase == "v2" and pending and pending.token == token then
        failed = pending.mismatches or 0
        restored()
        return
    end
    printLibrary(waitFor("fixture_install", 180, libraryState, printLibrary))
    if phase == "v1" then
        local ent = spawnCitizen()
        assert(menuSpawn("player") == LocalPlayer(), "menu selected another player")
        local s = waitFor("v1_actor_choices", 120, actorState, printActors)
        local saved = saveGame()
        printActors(s)
        control()
        local npc = photograph(ent, "v1", s.citizen)
        local receipt = {token = token, selector = s.selected, citizen = npc.key, player = s.body.key,
            arms = s.hands.key, used = s.used, save = saved}
        file.Write(dir .. "baseline.json", util.TableToJSON(receipt))
        assert((read(dir .. "baseline.json") or {}).token == token, "v1 baseline write failed")
    else
        -- Read before spawning anything: a fresh spawn must not create the choices being tested.
        local s = waitFor("automatic_actor_migration", 120, actorState, nil, true)
        printActors(s)
        check(s.selected ~= baseline.selector and s.body.key ~= baseline.player and s.hands.key ~= baseline.arms
            and s.citizen ~= baseline.citizen, "new selector and carrier keys")
        if s.citizen then photograph(spawnCitizen(s.citizen), "v2", s.citizen)
        else error("migrated Citizen missing from NPC tab", 0) end
        local _, after = actorState()
        printHistory(after, "after_spawn")
        control()
        local saved = baseline.save
        assert(saved.path:match("^saves/[^/\\;%c\"]+%.gms$") and #saved.path < 240, "invalid v1 save path")
        local raw = file.Read(saved.path, "MOD")
        assert(raw and #raw == saved.bytes and util.SHA256(raw) == saved.sha256, "v1 save changed or missing")
        emit("load", table.Copy(saved))
        file.Write(dir .. "restoring.json", util.TableToJSON({token = token, mismatches = failed}))
        assert((read(dir .. "restoring.json") or {}).token == token, "save resume marker write failed")
        RunConsoleCommand("gm_load", saved.path)
        restored()
    end
end
local routine = coroutine.create(run)
local nextPoll = 0
hook.Add("Think", "NL.WU.Probe", function()
    if finished or RealTime() < nextPoll then return end
    nextPoll = RealTime() + .25
    local ok, why = coroutine.resume(routine)
    if not ok then stop(why)
    elseif coroutine.status(routine) == "dead" then stop() end
end)
