-- Admin-only PoC fixture; native holds/actions and tool callbacks remain production code.
local ID, target, began, last, events = "vr_tools_probe", nil, nil, 0, {}
local targetPurpose, targetRemoval = "physgun", nil
local reviewCleanup
local oldPos, oldMove, original
local command
local controller, controlRelative, controllerCalls, controllerError
local rules = include("nlvr/modules/sh_tools_math.lua")
local serial = 0
local function emit(name, data)
    data = data or {} data.name, data.realm = name, "server"
    data.command_number = command and command.number
    local text = util.TableToJSON(data)
    if #text <= 3000 then print("NLVR_T " .. text) return end
    serial = serial + 1
    local encoded = util.Base64Encode(text):gsub("%s", "")
    local total = math.ceil(#encoded / 2800)
    for i = 1, total do print("NLVR_T_CHUNK server " .. serial .. " " .. i .. "/" .. total .. " " .. encoded:sub((i - 1) * 2800 + 1, i * 2800)) end
end
local function active(ply) return IsValid(ply) and NLVR_SV and NLVR_SV.Players[ply] end
local function removeTarget()
    -- Entity:Remove is deferred. Keep the cleanup marker with that target's callback,
    -- rather than briefly setting a shared flag around the Remove call.
    if targetRemoval then targetRemoval.fixture_cleanup = true end
    if IsValid(target) then target:Remove() end
    targetRemoval = nil
end
local function stopController()
    if IsValid(controller) then controller:StopMotionController() controller:Remove() end
    controller = nil
end
local function startController()
    stopController()
    local ply, phys = Entity(1), IsValid(target) and target:GetPhysicsObject()
    local state = active(ply)
    if not state or not IsValid(phys) then return end
    controlRelative = rules.Relative(phys:GetAngles(), state.hands.right.ang)
    controllerCalls, controllerError = 0, nil
    controller = ents.Create("base_anim")
    controller:SetNoDraw(true) controller:SetNotSolid(true) controller:SetPreventTransmit(player.GetAll(), true)
    controller.PhysicsSimulate = function(_, body, dt)
        local current = active(ply)
        if not current or not current.hands.right.valid or not IsValid(target) or not target:IsPlayerHolding() then return end
        local ok, err = pcall(function()
            local arrive = 0.05
            local velocity = body:GetVelocity()
            body:ComputeShadowControl{secondstoarrive = arrive, delta = dt,
                pos = body:GetPos() + velocity * arrive,
                angle = rules.Follow(controlRelative, current.hands.right.ang),
                maxangular = 100000, maxangulardamp = 1000000, maxspeed = 1000000,
                maxspeeddamp = 1000000, dampfactor = 1, teleportdistance = 0}
            controllerCalls = controllerCalls + 1
        end)
        if not ok then controllerError = tostring(err) end
    end
    controller:Spawn() controller:StartMotionController() controller:AddToMotionController(phys)
    emit("controller-created", {scripted = controller:IsScripted(), entity = controller:EntIndex()})
end
local function spawn(ply, expected)
    local weapon = NLVR_SV.Weapon(ply)
    if not weapon or weapon.kind == "hands" then return false end
    if expected and (ply:GetActiveWeapon():GetClass() ~= "gmod_tool" or ply:GetInfo("gmod_toolmode") ~= expected) then return false end
    -- After a menu click, wait for the declared level hand pose to reach W's server
    -- geometry. Spawning along its stale upward menu ray puts the picture target off-camera.
    if expected and weapon.muzzle.ang:Forward():Dot(Vector(1, 0, 0)) < 0.99 then return false end
    removeTarget()
    targetPurpose = expected or "physgun"
    target = ents.Create("prop_physics")
    target:SetModel("models/props_c17/oildrum001.mdl")
    target:SetPos(weapon.muzzle.pos + weapon.muzzle.ang:Forward() * 100)
    target:Spawn() target:Activate()
    local body = target:GetPhysicsObject()
    body:EnableGravity(true) body:EnableMotion(false)
    target:SetPos(weapon.muzzle.pos + weapon.muzzle.ang:Forward() * 100 - body:GetMassCenter())
    target:SetNWBool("nlvr_t_target", true)
    local identity, purpose = target:EntIndex(), targetPurpose
    local removal = {entity = identity, purpose = purpose, fixture_cleanup = false}
    targetRemoval = removal
    target:CallOnRemove(ID, function()
        local data = table.Copy(removal)
        data.time, data.class, data.tool = CurTime() - began,
            IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass(), ply:GetInfo("gmod_toolmode")
        emit("target-removed", data)
    end)
    emit("target", {entity = identity, purpose = purpose, time = CurTime() - began,
        class = ply:GetActiveWeapon():GetClass(), tool = ply:GetInfo("gmod_toolmode"), pos = target:GetPos(), muzzle = weapon.muzzle,
        model = target:GetModel(), mass_center = body:GetMassCenter(), gravity = body:IsGravityEnabled(), scale = active(ply).scale})
    return true
end
local function readyTarget(ply, attempt, expected)
    if not active(ply) then return end
    if spawn(ply, expected) then return end
    if attempt >= 30 then emit("target-failed", {reason = "expected weapon/tool geometry not ready", expected = expected, attempts = attempt}) return end
    if attempt == 1 or attempt % 10 == 0 then emit("target-wait", {attempt = attempt, class = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass()}) end
    timer.Simple(0.1, function() readyTarget(ply, attempt + 1, expected) end)
end
concommand.Add("nlvr_t_setup", function(ply)
    ply = Entity(1)
    if not active(ply) or began then return end
    oldPos, oldMove, began = ply:GetPos(), ply:GetMoveType(), CurTime()
    ply:Give("weapon_physgun") ply:Give("gmod_tool") ply:Give("weapon_crowbar")
    ply:SelectWeapon("weapon_physgun")
    local spin = GetConVar("phys_spinspeed")
    emit("controls", {spin = spin and spin:GetString(), rotation = ply:GetInfo("physgun_rotation_sensitivity"), wheel = ply:GetInfo("physgun_wheelspeed")})
    timer.Simple(0.4, function() readyTarget(ply, 1) end)
end)
local function done()
    local ply = Entity(1)
    stopController()
    if reviewCleanup then reviewCleanup() end
    removeTarget()
    for _, event in ipairs({"Think", "StartCommand", "OnPhysgunPickup", "PhysgunDrop", "OnPhysgunFreeze", "OnPhysgunReload", "PhysgunPickup"}) do hook.Remove(event, ID) end
    for _, name in ipairs({"nlvr_t_setup", "nlvr_t_done", "nlvr_t_tool_target"}) do concommand.Remove(name) end
    if IsValid(ply) and oldPos then ply:SetPos(oldPos) ply:SetMoveType(oldMove) end
    emit("stopped", {events = events, server_active = NLVR_SV ~= nil})
end
concommand.Add("nlvr_t_done", done)
concommand.Add("nlvr_t_tool_target", function(ply, _, args)
    ply = Entity(1) if not active(ply) then return end
    local expected = args[1]
    if expected ~= "remover" and expected ~= "colour" then return end
    readyTarget(ply, 1, expected)
end)
hook.Add("StartCommand", ID, function(ply, cmd)
    if not active(ply) or ply ~= Entity(1) then return end
    command = {number = cmd:CommandNumber(), tick = cmd:TickCount(), angles = cmd:GetViewAngles(), mouse_x = cmd:GetMouseX(), mouse_y = cmd:GetMouseY(), wheel = cmd:GetMouseWheel(), buttons = cmd:GetButtons()}
end)
for _, event in ipairs({"OnPhysgunPickup", "PhysgunDrop", "OnPhysgunFreeze", "OnPhysgunReload", "PhysgunPickup"}) do
    local name = event
    hook.Add(name, ID, function(...)
        events[name] = (events[name] or 0) + 1
        emit("hook", {event = name, count = events[name], time = began and CurTime() - began,
            phase = IsValid(target) and target:GetNWString("nlvr_t_phase")})
        if name == "OnPhysgunPickup" then
            local ply, ent = ...
            local state = active(ply)
            local body = IsValid(ent) and ent:GetPhysicsObject()
            if state and IsValid(body) and state.hands.right.valid then
                local trace = ply:GetEyeTrace()
                local contact = WorldToLocal(trace.HitPos, Angle(), body:GetPos(), body:GetAngles())
                emit("pickup-orientation", {time = CurTime() - began, entity = ent:EntIndex(),
                    body = body:GetAngles(), hand = state.hands.right.ang, contact = contact,
                    trace_match = trace.Entity == ent, body_pos = body:GetPos(), phase = ent:GetNWString("nlvr_t_phase")})
            end
        end
        if name == "OnPhysgunPickup" and T_TOOLS_MODE == "motion" then startController() end
        if name == "PhysgunDrop" then stopController() end
        if name == "OnPhysgunPickup" then
            local w = Entity(1):GetActiveWeapon()
            if IsValid(w) then
                for field, value in pairs(w:GetSaveTable(true)) do
                    if field:lower():find("ang") or field:lower():find("attach") or field:lower():find("rot") or field:lower():find("grab") then
                        emit("physgun-held-save", {field = field, value = tostring(value), value_type = type(value)})
                        if type(value) == "table" then
                            for child, member in pairs(value) do emit("physgun-held-save", {field = field .. "." .. tostring(child), value = tostring(member), value_type = type(member)}) end
                        end
                    end
                end
            end
        end
        -- Observe only. Native/gamemode/protection decisions are untouched.
    end)
end
hook.Add("Think", ID, function()
    local ply = Entity(1)
    if not began or not IsValid(ply) or CurTime() - last < 0.05 then return end
    last = CurTime()
    local state = active(ply)
    local weapon = ply:GetActiveWeapon()
    local phys = IsValid(target) and target:GetPhysicsObject()
    local data = {time = CurTime() - began, class = IsValid(weapon) and weapon:GetClass(),
        vr = state ~= nil, held = IsValid(target) and target:IsPlayerHolding(), exists = IsValid(target),
        target_entity = IsValid(target) and target:EntIndex(), target_purpose = targetPurpose,
        tool = ply:GetInfo("gmod_toolmode"), events = table.Copy(events), debug = NLVR_SV and NLVR_SV.Debug.tools, command = command,
        controller_calls = controllerCalls, controller_error = controllerError}
    if IsValid(target) then
        data.pos, data.ang, data.colour = target:GetPos(), target:GetAngles(), target:GetColor()
        data.motion = IsValid(phys) and phys:IsMotionEnabled()
        data.angular = IsValid(phys) and phys:GetAngleVelocity()
        data.velocity = IsValid(phys) and phys:GetVelocity()
        if IsValid(phys) then
            local ok, p = pcall(phys.GetShadowPos, phys)
            local aok, a = pcall(phys.GetShadowAngles, phys)
            if ok then data.shadow = {pos = p, ang = aok and a or nil} end
        end
    end
    if state then data.hand = state.hands.right end
    local geometry = state and NLVR_SV.Weapon(ply)
    data.muzzle, data.scale = geometry and geometry.muzzle, state and state.scale
    if IsValid(phys) then data.body_pos, data.mass_center, data.gravity = phys:GetPos(), phys:GetMassCenter(), phys:IsGravityEnabled() end
    if IsValid(weapon) and not original then
        original = true
        local save = weapon:GetSaveTable(true)
        for key, value in pairs(save) do emit("physgun-save", {field = key, value = tostring(value), value_type = type(value)}) end
    end
    emit("sample", data)
end)
