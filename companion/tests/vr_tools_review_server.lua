-- Appended in the ordinary private server fixture's lexical scope, never packaged.
local RID, review, button, originalCreate, originalShadow = "vr_tools_review", {}, nil, nil, nil
local useCalls = 0
local entityMeta = FindMetaTable("Entity")
local oldForce = entityMeta.ForcePlayerDrop
local forceObserver
forceObserver = function(ent, ...)
    if ent ~= target then return oldForce(ent, ...) end
    local phase, identity, before = ent:GetNWString("nlvr_t_phase"), ent:EntIndex(), ent:IsPlayerHolding()
    oldForce(ent, ...)
    emit("force-drop", {entity = identity, phase = phase, before = before, immediate = ent:IsPlayerHolding(), time = CurTime() - began})
    timer.Simple(0.15, function()
        emit("force-drop-confirm", {entity = identity, phase = phase, held = IsValid(ent) and ent:IsPlayerHolding(), time = CurTime() - began})
    end)
end
entityMeta.ForcePlayerDrop = forceObserver
local physicsMeta = FindMetaTable("PhysObj")
local oldPhysicsControl, lastParameters = physicsMeta.ComputeShadowControl, 0
local controlObserver
local function limit(name, fallback)
    local cv = GetConVar(name)
    return cv and cv:GetFloat() or fallback
end
controlObserver = function(body, params)
    local source = debug.getinfo(2, "S")
    if IsValid(target) and body == target:GetPhysicsObject() and source and source.source:find("sv_tools_rotation.lua", 1, true) and CurTime() - lastParameters >= 0.25 then
        lastParameters = CurTime()
        emit("review-shadow-parameters", {time = began and CurTime() - began, phase = review.phase,
            angular = params.maxangular, damping = params.maxangulardamp, arrive = params.secondstoarrive, factor = params.dampfactor,
            server_angular = limit("physgun_maxAngular", 5000),
            server_damping = limit("physgun_maxAngularDamping", 10000),
            server_arrive = limit("physgun_timeToArrive", 0.05), server_factor = limit("physgun_DampingFactor", 1)})
    end
    if T_TOOLS_MODE == "linear_trial" and IsValid(target) and body == target:GetPhysicsObject() then
        if review.linear == "zero" then params.maxspeed, params.maxspeeddamp = 0, 0
        elseif review.linear == "com" then params.pos = body:LocalToWorld(body:GetMassCenter()) + body:GetVelocity() * params.secondstoarrive end
    end
    return oldPhysicsControl(body, params)
end
physicsMeta.ComputeShadowControl = controlObserver
local function snapshot(name, extra)
    local ply, state = Entity(1), active(Entity(1))
    local data = extra or {}
    data.phase, data.time = review.phase, began and CurTime() - began
    data.held, data.exists = IsValid(target) and target:IsPlayerHolding(), IsValid(target)
    data.class = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass()
    data.command, data.use_calls = command, useCalls
    data.ducking, data.player_pos = ply:Crouching(), ply:GetPos()
    if IsValid(target) then
        local body = target:GetPhysicsObject()
        data.pos, data.ang, data.velocity = body:GetPos(), body:GetAngles(), body:GetVelocity()
        data.angular, data.mass_center, data.gravity = body:GetAngleVelocity(), body:GetMassCenter(), body:IsGravityEnabled()
    end
    if state then data.hand = state.hands.right end
    emit(name, data)
end
local function restoreFaults()
    if originalCreate then ents.Create = originalCreate originalCreate = nil end
    if originalShadow then FindMetaTable("PhysObj").ComputeShadowControl = originalShadow originalShadow = nil end
end
local function readyReviewTarget(ply, phase, attempt)
    if not active(ply) then return end
    local geometry = NLVR_SV.Weapon(ply)
    if geometry and geometry.kind == "physgun" and spawn(ply) then
        target:SetNWString("nlvr_t_phase", phase)
        snapshot("review-ready") return
    end
    if attempt >= 30 then snapshot("review-setup-failed") return end
    timer.Simple(0.1, function() readyReviewTarget(ply, phase, attempt + 1) end)
end
concommand.Add("nlvr_t_review_setup", function(_, _, args)
    local ply = Entity(1)
    if not active(ply) then return end
    restoreFaults()
    review = {phase = args[1]}
    ply:Give("weapon_physgun") ply:SelectWeapon("weapon_physgun")
    timer.Simple(0.3, function() readyReviewTarget(ply, args[1], 1) end)
end)
concommand.Add("nlvr_t_review_fault", function(_, _, args)
    local ply, state = Entity(1), active(Entity(1))
    if not state then return end
    snapshot("review-before-fault", {fault = args[1]})
    if args[1] == "tracking" then
        state.hands.right.valid = false
        local tick = hook.GetTable().Tick and hook.GetTable().Tick["nlvr.tools"]
        assert(tick, "tools Tick absent") tick()
    elseif args[1] == "controller" then
        local meta, body = FindMetaTable("PhysObj"), target:GetPhysicsObject()
        originalShadow = meta.ComputeShadowControl
        meta.ComputeShadowControl = function(phys, ...)
            if phys == body then
                meta.ComputeShadowControl = originalShadow originalShadow = nil
                error("intentional T review controller fault")
            end
            return originalShadow(phys, ...)
        end
    elseif args[1] == "creation" then
        originalCreate = ents.Create
        ents.Create = function(class, ...)
            local source = debug.getinfo(2, "S")
            if class == "base_anim" and source and source.source:find("sv_tools_rotation.lua", 1, true) then
                ents.Create = originalCreate originalCreate = nil
                return NULL
            end
            return originalCreate(class, ...)
        end
    elseif args[1] == "stop" then
        for _, entry in ipairs(NLVR_SV.Registry.entries) do
            if entry.module.name == "tools" then NLVR_SV.Registry:StopEntry(entry) break end
        end
    elseif args[1] == "death" then
        ply:Kill()
        timer.Simple(0.5, function()
            if IsValid(ply) then ply:Spawn() ply:SetMoveType(MOVETYPE_NOCLIP) ply:SetPos(oldPos) ply:SetEyeAngles(Angle()) end
        end)
    elseif args[1] == "player-api" then
        ply:DropObject()
    elseif args[1] == "entity-api" then
        if IsValid(target) then target:ForcePlayerDrop() end
    end
    snapshot("review-after-fault", {fault = args[1]})
    timer.Simple(0.3, function() snapshot("review-fault-confirm", {fault = args[1]}) end)
end)
concommand.Add("nlvr_t_review_button", function(_, _, args)
    local ply, state = Entity(1), active(Entity(1))
    if args[1] == "check" then snapshot("review-use-held") return end
    if args[1] == "remove" then
        if IsValid(button) then button:Remove() end
        snapshot("review-use-final") return
    end
    if not state then return end
    if IsValid(button) then button:Remove() end
    button = ents.Create("base_anim")
    button:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    button:SetPos(Vector(state.hands.right.pos.x + 1, state.hands.right.pos.y, state.head.pos.z - state.scale * 0.4))
    button:Spawn() button:SetMoveType(MOVETYPE_NONE) button:SetSolid(SOLID_BBOX)
    button:SetCollisionBounds(Vector(-2, -2, -2), Vector(2, 2, 2))
    button:SetUseType(SIMPLE_USE)
    button.Use = function(_, activator)
        if activator == ply then useCalls = useCalls + 1 snapshot("review-use") end
    end
    snapshot("review-use-ready")
end)
concommand.Add("nlvr_t_review_refuse", function(_, _, args)
    review.refuse = args[1] == "1"
    if review.refuse then review.switches = 0 else snapshot("review-refusal-result", {switches = review.switches or 0}) end
end)
concommand.Add("nlvr_t_review_linear", function(_, _, args)
    review.linear = args[1] snapshot("review-linear-mode", {mode = review.linear})
end)
hook.Add("PlayerSwitchWeapon", RID, function(ply, old, nextWeapon)
    if ply == Entity(1) and review.refuse and IsValid(nextWeapon) and nextWeapon:GetClass() == "weapon_crowbar" then
        review.switches = (review.switches or 0) + 1 snapshot("review-switch-refused", {switches = review.switches}) return true
    end
end)
local sampled = 0
hook.Add("Think", RID, function()
    if review.phase and CurTime() - sampled >= 0.05 then sampled = CurTime() snapshot("review-sample") end
end)
reviewCleanup = function()
    snapshot("review-stopped") restoreFaults()
    if physicsMeta.ComputeShadowControl == controlObserver then physicsMeta.ComputeShadowControl = oldPhysicsControl end
    if entityMeta.ForcePlayerDrop == forceObserver then entityMeta.ForcePlayerDrop = oldForce end
    if IsValid(button) then button:Remove() end
    hook.Remove("Think", RID) hook.Remove("PlayerSwitchWeapon", RID)
    for _, name in ipairs({"setup", "fault", "button", "refuse", "linear"}) do concommand.Remove("nlvr_t_review_" .. name) end
end
