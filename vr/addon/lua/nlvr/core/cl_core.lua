-- V1's view and restoration, with module-owned services for V2/V3. Included only at Start VR.
local Core = {}
function Core.New(native, onError, units)
    local protocol = include("nlvr/sh_protocol.lua")
    local moveBasis=include("nlvr/core/sh_move_basis.lua")
    assert(protocol.Scale(units), "Invalid session world scale")
    local C = {Native = native, Frame = nil, Pose = {}, Hand = {}, Debug = {}, Settings = {},
        Space = {anchor = Vector(), yaw = nil, scale = units, seated = 0}}
    local registry, events, movers, resolvers, ordinal = nil, {}, {}, {}, 0
    local running, lastHead, renderFrame, recenter = true, nil, nil, false
    local cameraSequence, cameraView, attemptFrame, aim
    local failures, lastError, cameraFailures, cameraError = 0, nil, 0, nil
    local viewOwner
    local proxies, pending = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    local refreshKey, refreshIndex, refreshChanged, resolverRevision = {}, 0, false, 0
    local transformFeet, refreshedFeet
    local ID = "nlvr.core"
    local function rotate(v, degrees)
        local s, c = math.sin(math.rad(degrees)), math.cos(math.rad(degrees))
        return Vector(c * v.x - s * v.y, s * v.x + c * v.y, v.z)
    end
    local function feet()
        if transformFeet then return transformFeet end
        local base = C.Feet or LocalPlayer():GetPos()
        return C.ViewFeet and C.ViewFeet(base) or base
    end
    local function snapshot(list) local copy = {} for i, value in ipairs(list) do copy[i] = value end return copy end
    function C.Fail(message) if running then onError(tostring(message)) end end
    function C.ToWorld(pos, ang)
        return LocalToWorld((pos - C.Space.anchor + Vector(0, 0, C.Space.seated)) * C.Space.scale,
            ang or Angle(), feet(), Angle(0, C.Space.yaw or 0, 0))
    end
    function C.ToTracking(pos, ang)
        local p, a = WorldToLocal(pos, ang or Angle(), feet(), Angle(0, C.Space.yaw or 0, 0))
        return p / C.Space.scale + C.Space.anchor - Vector(0, 0, C.Space.seated), a
    end
    function C.Space.Turn(degrees)
        assert(protocol.Finite(degrees), "Invalid play-space turn")
        local head = lastHead and lastHead.pos or C.Space.anchor
        local old = C.Space.yaw or 0
        C.Space.yaw = (old + degrees + 180) % 360 - 180
        C.Space.anchor = head - rotate(head - C.Space.anchor, old - C.Space.yaw)
        C.Refresh()
    end
    function C.Space.Shift(delta)
        assert(protocol.Finite(delta.x) and protocol.Finite(delta.y) and protocol.Finite(delta.z), "Invalid play-space shift")
        -- The caller moves the predicted/server feet by delta world game units. Compensate the anchor
        -- and advance the cached floor once: walking the hull under the head must not move the view.
        C.Space.anchor = C.Space.anchor + rotate(delta, -(C.Space.yaw or 0)) / C.Space.scale
        C.Feet = feet() + delta
        C.Refresh()
    end
    function C._On(entry, name, fn)
        events[name] = events[name] or {}
        local record = {entry, fn}
        table.insert(events[name], record)
        registry:Own(function() table.RemoveByValue(events[name], record) end, entry)
    end
    function C.On(name, fn) return C._On(assert(registry.current), name, fn) end
    function C.Emit(name, ...)
        local copy = {} for i, record in ipairs(events[name] or {}) do copy[i] = record end
        for _, record in ipairs(copy) do registry:Call(record[1], record[2], ...) end
    end
    local function ordered(list, entry, priority, fn)
        ordinal = ordinal + 1
        local record = {entry = entry, priority = priority, ordinal = ordinal, fn = fn}
        list[#list + 1] = record
        table.sort(list, function(a, b) return a.priority == b.priority and a.ordinal < b.ordinal or a.priority < b.priority end)
        registry:Own(function() table.RemoveByValue(list, record) end, entry)
        return record
    end
    function C._Mover(entry, priority, fn) return ordered(movers, entry, priority, fn) end
    function C._Resolver(entry, priority, fn)
        resolverRevision=resolverRevision+1
        return ordered(resolvers, entry, priority, fn)
    end
    function C.Aim(angles, owner)
        assert(owner and protocol.Finite(angles.p) and protocol.Finite(angles.y) and protocol.Finite(angles.r), "Invalid VR aim")
        if aim and aim.tick == engine.TickCount() and aim.owner ~= owner then return false end
        aim = {ang = Angle(angles.p, angles.y, angles.r), owner = owner, tick = engine.TickCount()}
        return true
    end
    function C.Ray(hand)
        local pose = C.Pose[C.Input.Resolve(hand)]
        if not pose or not pose.valid then return end
        local aimPose = pose.aim or pose
        return aimPose.pos, aimPose.ang:Forward()
    end
    function C.Refresh(rendering)
        if not lastHead then return end
        -- Keep the pose/frame boundary here for C's raw/aim/hand frame composition.
        -- Repeated mover/view/setting calls with identical inputs must not repeat hull traces.
        refreshIndex,refreshChanged=0,false
        local function key(value)
            refreshIndex=refreshIndex+1
            if refreshKey[refreshIndex]~=value then refreshKey[refreshIndex],refreshChanged=value,true end
        end
        key(FrameNumber()) key(resolverRevision) key(C.HandRevision or 0) key(C.MoveRevision or 0)
        key(C.Space.yaw) key(C.Space.scale) key(C.Space.seated)
        key(C.Space.anchor.x) key(C.Space.anchor.y) key(C.Space.anchor.z)
        local base=C.Feet or LocalPlayer():GetPos()
        key(base.x) key(base.y) key(base.z) key(C.Input.mainHand)
        for _,name in ipairs({"hmd","left","right"}) do
            local p=C.Frame and C.Frame[name]
            key(p and p.valid or false)
            if p then
                for _,field in ipairs({"pos","ang","vel","angvel"}) do
                    local v=p[field]
                    if field=="ang" then key(v and v.p or 0) key(v and v.y or 0) key(v and v.r or 0)
                    else key(v and v.x or 0) key(v and v.y or 0) key(v and v.z or 0) end
                end
            end
        end
        -- Motor interpolation advances between CreateMove and CalcView in the same frame.
        -- At the view boundary it is a changed input, shared by camera and both hands.
        local currentFeet=rendering and feet() or nil
        if currentFeet and refreshedFeet and currentFeet:DistToSqr(refreshedFeet)>.00000001 then refreshChanged=true end
        if not refreshChanged then return end
        local previousTransform=transformFeet
        transformFeet=currentFeet or feet()
        refreshedFeet=transformFeet
        for _, name in ipairs({"head", "left", "right"}) do
            local raw = C.Frame and C.Frame[name == "head" and "hmd" or name]
            local source = name == "head" and lastHead or raw
            local valid = raw and raw.valid == true or false
            source = source and source.valid and source or {pos = lastHead.pos, ang = lastHead.ang}
            local pos, ang = C.ToWorld(source.pos, source.ang)
            C.Pose[name] = {valid = valid, pos = pos, ang = ang,
                vel = rotate(source.vel or Vector(), C.Space.yaw or 0) * C.Space.scale,
                angvel = rotate(source.angvel or Vector(), C.Space.yaw or 0), raw = raw or source}
        end
        C.Frames.Apply()
        C.Pose.main, C.Pose.off = C.Pose[C.Input.mainHand], C.Pose[C.Input.offHand]
        for _, hand in ipairs({"left", "right"}) do
            local previous = C.Hand[hand] or {}
            local target = C.Pose[hand]
            local shown = {valid = target.valid, pos = Vector(target.pos.x, target.pos.y, target.pos.z),
                ang = Angle(target.ang.p, target.ang.y, target.ang.r), vel = target.vel, angvel = target.angvel, raw = target.raw}
            local state = {target = target, shown = shown, blocked = false, held = previous.held, grip_curls = previous.grip_curls}
            for _, resolver in ipairs(snapshot(resolvers)) do registry:Call(resolver.entry, resolver.fn, hand, state) end
            C.Hand[hand] = state
        end
        transformFeet=previousTransform
    end
    local function begin_frame()
        local number = FrameNumber()
        if number == renderFrame then return end
        renderFrame = number
        local nextFrame, detail = native.BeginFrame()
        if detail then
            local message = tostring(detail)
            if message ~= lastError then MsgN("[nativeloader] VR frame: " .. message) lastError = message end
            failures = failures + 1
            if failures >= 30 then C.Fail(message) return end
        else failures, lastError = 0, nil end
        C.Frame = nextFrame or C.Frame
        if C.Frame and C.Frame.hmd and C.Frame.hmd.valid then lastHead = C.Frame.hmd end
        local actions, actionError = {}, nil
        if native.Actions then actions, actionError = native.Actions() end
        if actionError then error(actionError) end
        C.Input.Update(actions or {}, RealTime(), C.Settings.dominant == 1)
        C.Refresh()
        C.Emit("frame", C.Frame)
    end
    local function paused_proxy_think(entity) entity:NextThink(CurTime()) return true end
    local function hide_entity(entity, root)
        if not IsValid(entity) then return end
        local entry = proxies[entity]
        if not entry then entry = {noDraw = entity:GetNoDraw()} proxies[entity] = entry end
        if root and not entry.root then
            entry.root, entry.think = true, rawget(entity:GetTable(), "Think")
            entity.Think = paused_proxy_think
        end
        if not entity:GetNoDraw() then entity:SetNoDraw(true) end
        for _, child in ipairs(entity:GetChildren()) do hide_entity(child, false) end
    end
    local function hide_proxy(entity)
        if not IsValid(entity) then return end
        if entity:GetClass() == "rtx_pseudoplayer" or entity:GetClass() == "rtx_pseudoweapon" then hide_entity(entity, true) end
    end
    local function restore_view()
        if viewOwner then viewOwner.Stop() viewOwner=nil end
    end
    local function view(player, origin, angles, _, near, far)
        if not running or not IsValid(player) then return end
        begin_frame()
        if not running or not C.Frame or not lastHead then return end
        if cameraSequence == C.Frame.sequence or attemptFrame == renderFrame then return cameraView end
        attemptFrame = renderFrame
        if recenter then
            C.Space.anchor = Vector(lastHead.pos.x, lastHead.pos.y, 0)
            C.Space.yaw, recenter = angles.y - lastHead.ang.y, false
        end
        if not C.Space.yaw then C.Space.yaw = angles.y - lastHead.ang.y end
        C.Feet = origin - player:GetCurrentViewOffset()
        C.Refresh(true)
        local position, rotation = C.Pose.head.pos, C.Pose.head.ang
        local culling = GetConVar("nl_vr_fov"):GetFloat()
        if not protocol.Finite(culling) then culling = 145 end
        local nextView = {origin = position, angles = rotation, fov = math.Clamp(culling, 100, 170), znear = near, zfar = far, drawviewer = false}
        local pushed, detail = native.SetFrameCamera(C.Frame.sequence, position, rotation)
        if pushed == false or (pushed == nil and detail ~= nil) then
            local message = tostring(detail or "SetFrameCamera failed")
            if message ~= cameraError then MsgN("[nativeloader] VR camera: " .. message) cameraError = message end
            cameraFailures = cameraFailures + 1
            if cameraFailures >= 30 then C.Fail(message) end
            return cameraView
        end
        cameraFailures, cameraError = 0, nil
        cameraSequence, cameraView = C.Frame.sequence, nextView
        return cameraView
    end
    local settings = {dominant = {0, 0, 1}, move_dir = {0, 0, 1}, turn = {0, 0, 1}, snap_angle = {30, 15, 90},
        turn_speed = {120, 30, 360}, teleport = {1, 0, 2}, vignette = {0.6, 0, 1}, seated = {0, 0, 1},
        seated_offset = {0.45, 0, 1}, height = {0, 0, 2.2}, ghost_hands = {1, 0, 1}, gloves = {1, 0, 1},
        climb = {1, 0, 1}, melee = {1, 0, 1}, wrist_hud = {1, 0, 1},
        physical_reload = {1, 0, 1}, foregrip = {1, 0, 1}, ammo_counter = {1, 0, 1}, gun_angle = {0, -45, 45},
        quality = {0, 0, 16}, stereo = {0, 0, 1}, frame_generation = {1, 0, 1}}
    local function setting(name, spec)
        local cv = GetConVar("nl_vr_" .. name)
        local value = cv and cv:GetFloat() or spec[1]
        if not protocol.Finite(value) then value = spec[1] end
        value = math.Clamp(value, spec[2], spec[3])
        if name == "height" and value > 0 then value = math.max(1.2, value) end
        C.Settings[name] = value
        C.Input.Mirror(C.Settings.dominant == 1)
        C.Space.seated = C.Settings.seated == 1 and (C.Settings.seated_offset or 0.45) or 0
        C.Refresh()
        C.Emit("setting", name, value)
    end
    C.Input = include("nlvr/core/cl_input.lua").New()
    C.Frames = include("nlvr/core/cl_frames.lua").New(C)
    registry = include("nlvr/core/sh_modules.lua").New(C, C.Fail)
    C.Registry = registry
    C.Overlay = include("nlvr/core/cl_overlay.lua").New(C)
    C.Net = include("nlvr/core/cl_net.lua").New(C, protocol)
    registry:Add({name = "core", order = 0, Start = function(ctx)
        for name, spec in pairs(settings) do
            local key, limits = name, spec
            setting(key, limits)
            cvars.AddChangeCallback("nl_vr_" .. key, function() if running then setting(key, limits) end end, ID)
            ctx.cleanup(function() cvars.RemoveChangeCallback("nl_vr_" .. key, ID) end)
        end
        ctx.cleanup(C.Net.Stop) C.Net.Start()
        ctx.hook("PreDrawViewModel", function() return true end)
        ctx.hook("PreDrawPlayerHands", function() return true end)
        ctx.hook("ShouldDrawLocalPlayer", function() return false end)
        if ents and ents.FindByClass then
            for _, class in ipairs({"rtx_pseudoplayer", "rtx_pseudoweapon"}) do
                for _, entity in ipairs(ents.FindByClass(class)) do hide_proxy(entity) end
            end
        end
        ctx.hook("OnEntityCreated", function(entity) pending[entity] = true end)
        ctx.hook("PreRender", function()
            assert(viewOwner and viewOwner.Check(),
                "The hook library or CalcView registry changed during VR")
            for entity in pairs(pending) do hide_proxy(entity) pending[entity] = nil end
            for entity, entry in pairs(proxies) do
                if IsValid(entity) then
                    if entry.root then hide_entity(entity, true)
                    elseif not entity:GetNoDraw() then entity:SetNoDraw(true) end
                end
            end
            begin_frame()
        end)
        local owner,detail=include("nlvr/core/cl_view_hooks.lua").Take(ctx,view)
        assert(owner,detail) viewOwner=owner
        ctx.cleanup(restore_view)
        ctx.hook("PostRender", C.Overlay.Paint)
        ctx.hook("SetupMove",function(ply,mv,cmd)
            if ply==LocalPlayer() then moveBasis.Apply(ply,mv,cmd,C.Pose.head) end
        end)
        ctx.hook("CreateMove", function(cmd)
            C.Feet = LocalPlayer():GetPos()
            begin_frame()
            if not running then return end
            if not C.Space.yaw and lastHead then C.Space.yaw = cmd:GetViewAngles().y - lastHead.ang.y end
            C.Refresh()
            if C.Pose.head then cmd:SetViewAngles(Angle(C.Pose.head.ang.p, C.Pose.head.ang.y, 0)) end
            for _, mover in ipairs(snapshot(movers)) do registry:Call(mover.entry, mover.fn, cmd) end
            if aim and aim.tick == engine.TickCount() then
                -- Movers express forward/right movement in the command's current yaw. Preserve that
                -- world direction when weapon convergence replaces the head's aim (Source right is -Y).
                local previous=cmd:GetViewAngles()
                local forward, side = cmd:GetForwardMove(), cmd:GetSideMove()
                local player=LocalPlayer() local move=player:GetMoveType()
                if move==MOVETYPE_NOCLIP or move==MOVETYPE_LADDER or (move~=MOVETYPE_NOCLIP and player:WaterLevel()>=2) then
                    local world=previous:Forward()*forward+previous:Right()*side+previous:Up()*cmd:GetUpMove()
                    cmd:SetForwardMove(world:Dot(aim.ang:Forward()))
                    cmd:SetSideMove(world:Dot(aim.ang:Right()))
                    cmd:SetUpMove(world:Dot(aim.ang:Up()))
                else
                    local delta = math.rad(aim.ang.y - previous.y)
                    local s, c = math.sin(delta), math.cos(delta)
                    cmd:SetForwardMove(forward * c - side * s)
                    cmd:SetSideMove(side * c + forward * s)
                end
                cmd:SetViewAngles(aim.ang)
            else
                aim=nil
            end
            C.Net.Sync()
        end)
    end, Stop = function()
        for entity, entry in pairs(proxies) do
            if IsValid(entity) then
                if entry.root and rawget(entity:GetTable(), "Think") == paused_proxy_think then entity.Think = entry.think end
                pcall(entity.SetNoDraw, entity, entry.noDraw)
            end
        end
    end})
    function C.Recenter() recenter = true end
    function C.Start(modules)
        NLVR = C
        for _, module in ipairs(modules) do registry:Add(module) end
        registry:Start()
        return true
    end
    function C.Stop()
        if not running then return end
        running = false registry:Stop() C.Overlay.Destroy()
        C.Frame, C.Pose, C.Hand, C.Debug, aim = nil, {}, {}, {}, nil
        if NLVR == C then NLVR = nil end
    end
    return C
end
return Core
