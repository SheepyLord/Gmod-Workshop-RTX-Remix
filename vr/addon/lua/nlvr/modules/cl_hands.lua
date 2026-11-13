-- World geometry only. No view-model, HUD, halo, render target or RenderView draws of the models.
local module = {name = "hands", order = 20}
local Pose = include("nlvr/modules/cl_hands_pose.lua")
local Frame = include("nlvr/core/cl_hand_model.lua")
local core, hands, signature, nextModelCheck, lastFrame, lastTime
local fallback = {model = "models/weapons/c_arms_citizen.mdl", skin = 0, body = "100000000"}
local function remove_models()
    for _, hand in pairs(hands or {}) do
        if IsValid(hand.model) then hand.model:Remove() end
        hand.model, hand.bones = nil, nil
        hand.frame,hand.anatomy,hand.profile,hand.skeleton,hand.tips,hand.renderCache=nil,nil,nil,nil,nil,nil
        hand.samples,hand.buffers,hand.nextSkeleton,hand.referenceReady=nil,nil,nil,nil
        hand.nextReference=nil
        hand.connection,hand.controllerRevision,hand.controllerValid=nil,nil,nil
        if core and core.HandModelFrames then core.HandModelFrames[hand.side]=nil end
    end
end
local function model_info()
    local player = LocalPlayer()
    if not IsValid(player) or not player.GetModel or not player_manager then return end
    local info = player_manager.TranslatePlayerHands(player_manager.TranslateToPlayerModelName(player:GetModel())) or fallback
    local path = info.model
    -- IsValidModel can return false clientside solely because the server has not precached it.
    -- Creation plus the required wrist is the useful validation for a client-only arms model.
    if type(path) ~= "string" or path == "" then info = fallback end
    return {model = info.model, skin = tonumber(info.skin) or 0, body = tostring(info.body or ""), fallback = info == fallback}
end
local function build_bones(hand, entity)
    if not hand.drawing or not hand.bones or not hand.shown then return end
    local began=SysTime and SysTime() or 0
    local wrist = entity:GetBoneMatrix(hand.bones.wrist)
    if not wrist then return end
    -- Read all matrices before replacing any: a hidden parent must never feed a child.
    local matrices = {}
    for id in pairs(hand.bones.names) do
        local matrix = entity:GetBoneMatrix(id)
        if matrix then matrices[id] = Matrix(matrix) end
    end
    local desired = Matrix()
    local position, rotation
    if hand.frame then position, rotation = Frame.Wrist(hand.frame, hand.shown, core.Space.scale)
    else
        position = hand.shown.pos
        local ignored
        ignored, rotation = LocalToWorld(Vector(), Angle(0, 0, -90), Vector(), hand.shown.ang)
    end
    desired:SetTranslation(position)
    desired:SetAngles(rotation)
    local scale = core.Space.scale / 40
    desired:Scale(Vector(scale, scale, scale))
    local transform = desired * wrist:GetInverse()
    local data=core.Frame and core.Frame.controllers and core.Frame.controllers[hand.side]
    local reference=hand.skeleton
    local skeletal=reference and Frame.SkeletalMatrices(matrices,hand.bones,hand.tips,reference,hand.shown,data,core.Space.scale,hand.frame,hand.side,hand.renderCache)
    if skeletal and skeletal[hand.bones.wrist] then transform=skeletal[hand.bones.wrist]*wrist:GetInverse() end
    local elbow = matrices[hand.bones.forearm or hand.bones.wrist]
    local collapsed = Matrix()
    collapsed:SetTranslation((transform * elbow):GetTranslation())
    collapsed:SetScale(Vector())
    local observer=core.HandDrawObserver
    local rendered=observer and {}
    for id, matrix in pairs(matrices) do
        local final=hand.bones.visible[id] and (skeletal and skeletal[id] or transform * matrix) or collapsed
        entity:SetBoneMatrix(id,final)
        if rendered then rendered[id]=final end
    end
    if observer then observer(hand.side,hand,rendered,hand.device) end
    hand.builds = (hand.builds or 0) + 1
    hand.buildMs=(hand.buildMs or 0)+((SysTime and SysTime() or 0)-began)*1000
end
local function create_model(hand, info)
    local entity = ClientsideModel(info.model, RENDERGROUP_OPAQUE)
    if not IsValid(entity) then return false end
    hand.model = entity -- cleanup owns it even if configuration fails
    hand.renderCache={}
    entity:SetNoDraw(true)
    entity:SetSkin(info.skin)
    entity:SetBodyGroups(info.body)
    entity:SetSequence(0)
    entity:SetCycle(0)
    -- c_arms exposes its count before its name cache is populated. Build once before discovery.
    entity:SetupBones()
    hand.bones = Pose.Bones(entity, hand.side)
    if not hand.bones.wrist then entity:Remove() hand.model, hand.bones = nil, nil return false end
    hand.frame = Frame.Measure(entity, hand.bones)
    hand.bones.curlAxes = Frame.CurlAxes(entity, hand.bones, hand.frame, hand.side)
    if hand.frame then
        hand.frame.grip,hand.frame.tube=Frame.Grip(entity, hand.bones, hand.frame, hand.side)
        hand.anatomy=hand.frame
        local data=core.Frame and core.Frame.controllers and core.Frame.controllers[hand.side]
        hand.frame=Frame.Fit(hand.anatomy,data)
    end
    core.HandModelFrames[hand.side] = hand.frame
    hand.tips=Frame.Tips(entity,hand.bones,info.body,info.skin)
    entity:AddCallback("BuildBonePositions", function(ent) build_bones(hand, ent) end)
    return true
end
local function models(now)
    if now < nextModelCheck then return end
    nextModelCheck = now + 0.25
    local info = model_info()
    if not info then return end
    local key = info.model .. ":" .. info.skin .. ":" .. info.body
    if signature == key and IsValid(hands.left.model) and IsValid(hands.right.model) then return end
    remove_models()
    for _, side in ipairs({"left", "right"}) do
        local hand = hands[side]
        local created = create_model(hand, info)
        hand.fallback = not created or info.fallback == true
        if not created then create_model(hand, fallback) end
    end
    signature = key
end
local function outline(hand)
    if hand.overlay then return hand.overlay end
    local key = "ghost_" .. hand.side
    local size = core.Overlay.Sizes[key]
    hand.overlay = core.Overlay.New{key = key, name = "RTX VR " .. hand.side .. " ghost hand",
        width = size[1], height = size[2], metres = 0.16, alpha = 0.24,
        paint = function(_, w, h) Pose.Outline(hand.side, w, h) hand.paints = (hand.paints or 0) + 1 end}
    return hand.overlay
end
local function update_ghost(hand, state)
    local head = core.Pose.head
    local show = state and state.target.valid and state.blocked and core.Settings.ghost_hands == 1 and head and head.valid
    if show then
        local object = outline(hand)
        local p = core.ToTracking(state.target.pos)
        local delta = state.target.pos - head.pos
        local ang = delta:Length() > 0.001 and delta:Angle() or head.ang
        local _, a = core.ToTracking(state.target.pos, ang)
        object:Place("world", p, a, 0.16)
        if not object.visible then object:Show(true) end
    elseif hand.overlay and (hand.overlay.visible or hand.overlay.wanted) then hand.overlay:Show(false) end
end
local function debug_hand(out, hand, state)
    out.model, out.fallback = IsValid(hand.model) and hand.model:GetModel() or "", hand.fallback == true
    out.bones, out.finger_bones = hand.bones and hand.bones.count or 0, hand.bones and hand.bones.fingerCount or 0
    for i = 1, 5 do out.curls[i] = hand.curls and hand.curls[i] end
    for i = 1, 4 do out.splay[i] = hand.splay and hand.splay[i] end
    out.grip = state and state.grip_curls ~= nil or false
    out.distance = state and (state.shown.pos - state.target.pos):Length() or 0
    out.blocked, out.valid = state and state.blocked == true or false, state and state.shown.valid == true or false
    out.ghost, out.paints = hand.overlay and hand.overlay.visible or false, hand.paints or 0
    out.builds, out.draws = hand.builds or 0, hand.draws or 0
    out.palm_frame = hand.frame
    out.tip_locals = hand.tips
    out.skeletal_source=hand.skeleton and hand.skeleton.source
    out.skeleton_reads,out.skeleton_changes,out.grasp_refits=hand.reads or 0,hand.changes or 0,hand.refits or 0
    out.skeleton_time=hand.skeleton and hand.skeleton.sample_time
    out.skeleton_ms=hand.sampleMs or 0
    out.build_ms=hand.buildMs or 0
    out.skeleton_failures=hand.sampleFailures or 0

end
local function update()
    local number, now = FrameNumber(), RealTime()
    if lastFrame ~= number then
        local dt = lastTime and math.max(0, now - lastTime) or 0
        lastFrame, lastTime = number, now
        models(now)
        for _, side in ipairs({"left", "right"}) do
            local hand, state = hands[side], core.Hand[side]
            local data=core.Frame and core.Frame.controllers and core.Frame.controllers[side]
            local connection=(data and data.model or "")..":"..(data and data.device or "")
            local descriptor=hand.connection~=connection or hand.controllerRevision~=(data and data.revision) or hand.controllerValid~=(data and data.valid)
            local profile=hand.profile
            if descriptor then
                profile=connection..":"..tostring(data and data.valid)..":"..tostring(data and data.aim and data.aim.pos)..":"..
                    tostring(data and data.aim and data.aim.ang)..":"..tostring(data and data.hand and data.hand.pos)..":"..tostring(data and data.hand and data.hand.ang)
                hand.controllerRevision=data and data.revision hand.controllerValid=data and data.valid
            end
            if hand.profile~=profile then
                hand.frame=Frame.Fit(hand.anatomy,data) hand.profile=profile
                if hand.connection~=connection then hand.samples,hand.buffers={},{} hand.skeleton=nil end
                hand.connection=connection
                hand.samples,hand.buffers=hand.samples or {},hand.buffers or {}
                hand.nextSkeleton,hand.referenceReady=0,false
                hand.nextReference=0
                local reference=hand.samples.grip_limit
                if reference and reference.valid and hand.anatomy and data and data.valid then
                    hand.frame=Frame.ReferenceFrame(hand.frame,reference,data) hand.referenceReady=true hand.refits=(hand.refits or 0)+1
                end
                core.HandModelFrames[side]=hand.frame
            end
            if core.Native.Skeleton and data and data.valid and now>=(hand.nextSkeleton or 0) then
                hand.nextSkeleton=now -- once per rendered frame; buffers and stable grasp are reused
                hand.samples=hand.samples or {} hand.buffers=hand.buffers or {}
                local function read(kind)
                    local began=SysTime and SysTime() or 0
                    hand.buffers[kind]=hand.buffers[kind] or {}
                    hand.samples[kind]=hand.samples[kind] or {}
                    hand.reads=(hand.reads or 0)+1
                    local sample=core.Native.Skeleton(side,kind,hand.buffers[kind])
                    if Frame.StoreSample(hand.samples[kind],sample) then hand.changes=(hand.changes or 0)+1 end
                    if not sample or not sample.valid then hand.sampleFailures=(hand.sampleFailures or 0)+1 end
                    hand.sampleMs=(hand.sampleMs or 0)+((SysTime and SysTime() or 0)-began)*1000
                    return hand.samples[kind].valid and hand.samples[kind] or nil
                end
                if not hand.referenceReady and now>=(hand.nextReference or 0) then
                    hand.nextReference=now+.5
                    local reference=read("grip_limit")
                    if reference and hand.anatomy and data and data.valid then
                        hand.frame=Frame.ReferenceFrame(Frame.Fit(hand.anatomy,data),reference,data)
                        hand.referenceReady=true hand.refits=(hand.refits or 0)+1
                        core.HandModelFrames[side]=hand.frame
                    end
                end
                if state and state.grip_curls then
                    local reference=hand.samples.grip_limit
                    if reference and reference.valid then hand.skeleton=reference end
                else hand.skeleton=read("with_controller") or hand.skeleton end
            end
            hand.curls, hand.splay = Pose.Smooth(hand.curls, hand.splay, core.Input[side], state and state.grip_curls, dt)
            if IsValid(hand.model) then Frame.Apply(hand.model, hand.bones, hand.curls, hand.splay, side) end
        end
    end
end
local function present()
    update()
    for _, side in ipairs({"left", "right"}) do
        local hand, state = hands[side], core.Hand[side]
        update_ghost(hand, state)
        debug_hand(core.Debug.hands[side], hand, state)
    end
end
function module.Start(ctx)
    core, hands, signature, nextModelCheck, lastFrame, lastTime = ctx.core,
        {left = {side = "left"}, right = {side = "right"}}, nil, 0, nil, nil
    core.HandModelFrames = {}
    core.Debug.hands = {left = {curls = {}, splay = {}}, right = {curls = {}, splay = {}}}
    ctx.cleanup(remove_models)
    ctx.resolver(10, function(side, state) Pose.Resolve(core, side, state) end)
    ctx.On("before_overlay_paint", present)
    -- The fixes' renderer does not dispatch the ordinary opaque callback in this path.
    -- This is still world 3D, before translucent geometry; models themselves stay opaque.
    ctx.hook("PreDrawTranslucentRenderables", function(depth, skybox)
        if depth or skybox then return end
        update()
        for _, side in ipairs({"left", "right"}) do
            local hand, state = hands[side], core.Hand[side]
            if IsValid(hand.model) and state and state.shown.valid then
                hand.shown = state.shown
                hand.device=state.target.device or (core.Debug.frames and core.Debug.frames[side] and core.Debug.frames[side].raw)
                hand.model:SetPos(state.shown.pos)
                hand.model:SetAngles(state.shown.ang)
                hand.model:InvalidateBoneCache()
                hand.drawing = true
                local ok, err = pcall(function() hand.model:SetupBones() hand.model:DrawModel() end)
                hand.drawing = false
                if not ok then error(err) end
                hand.draws = (hand.draws or 0) + 1
            end
        end
    end)
end
function module.Stop()
    remove_models()
    for _, hand in pairs(hands or {}) do if hand.overlay then hand.overlay:Destroy() end end
    if core then core.Debug.hands = nil core.HandModelFrames = nil end
    core, hands = nil, nil
end
return module
