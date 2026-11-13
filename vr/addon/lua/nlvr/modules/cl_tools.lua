local module = {name = "tools", order = 48}
local Math = include("nlvr/modules/sh_tools_math.lua")
local Presentation = include("nlvr/modules/cl_tools_presentation.lua")
local current
function module.Start(ctx)
    -- Tool actions and the wheel require the weapon service; an absent dependency owns no input/resources.
    if not ctx.Weapon then return end
    local controls = include("nlvr/modules/cl_tools_controls.lua").New(ctx)
    local wheel = include("nlvr/modules/cl_tools_wheel.lua").New(ctx, controls)
    local tool, toolSignature, toolObject, held, carry, lastTick, lastStepTime, config, distanceDirection
    local toolPaints, toolAnchor = 0, nil
    local beamDebug, debug = {}, {physgun = {entity = 0}, wheel = wheel.Debug(), tool_paints = 0}
    local beamMaterial, beamColour = Material("cable/physbeam"), Color(255, 255, 255, 255)
    local beamPreference = GetConVar("physgun_drawbeams")
    local languagePreference = GetConVar("gmod_language")
    local toolDisplay, infoAt, infoMode, infoTool, infoStage, infoOperation, infoLanguage = nil, 0
    local anchorModel, anchorBone
    local beamModel, beamAttachment
    ctx.Debug.tools = debug
    local holding = false
    current = {ctx = ctx, wheel = wheel, controls = controls}
    local api = {WheelOpen = function() return wheel.open end}
    ctx.core.Tools = api
    for key, spec in pairs({Title = {30, 700}, Name = {22, 600}, Small = {18, 500}, Tiny = {14, 500}}) do
        surface.CreateFont("NLVRTools" .. key, {font = "Tahoma", size = spec[1], weight = spec[2], extended = true})
    end
    surface.CreateFont("NLVRToolsHL2", {font = "HalfLife2", size = 64, weight = 500})
    local function paintTool(_, width)
        if not toolObject then return end
        toolPaints = toolPaints + 1
        surface.SetDrawColor(10, 18, 28, 235) surface.DrawRect(0, 0, width, 133)
        draw.SimpleText(toolObject.name, "NLVRToolsName", 12, 5, Color(171, 225, 244))
        for i, text in ipairs(toolObject.lines) do
            surface.SetFont("NLVRToolsSmall")
            local font = surface.GetTextSize(text) > width - 24 and "NLVRToolsTiny" or "NLVRToolsSmall"
            draw.SimpleText(text, font, 12, 32 + (i - 1) * 30, color_white)
        end
    end
    ctx.Net.On(96, function()
        local entity, bone = net.ReadEntity(), net.ReadUInt(8)
        local point, distance = net.ReadVector(), net.ReadFloat()
        local handAngle, propAngle, targetAngle = net.ReadAngle(), net.ReadAngle(), net.ReadAngle()
        local error = net.ReadFloat()
        local inputHand = held and held.inputHand or ctx.Input.mainHand
        held = IsValid(entity) and {ent = entity, bone = bone, point = point, distance = distance,
            hand = handAngle, prop = propAngle, target = targetAngle, error = error, inputHand = ctx.Input.mainHand} or nil
        if not held then controls.Trigger(inputHand) end
    end)
    ctx.On("frame", function()
        controls.Frame()
        if not ctx.Weapon then
            held, holding = nil, false wheel.Close(false)
            if toolDisplay then toolDisplay.Show(false) end
            debug.physgun.entity, debug.tool, debug.tool_anchor = 0, nil, nil
            debug.wheel, debug.tool_paints = wheel.Debug(), toolPaints
            return
        end
        wheel.Frame()
        local player, active = LocalPlayer(), ctx.Weapon and ctx.Weapon.Active
        local alive = IsValid(player) and player:Alive()
        local pose = ctx.Pose[ctx.Input.mainHand]
        -- This reliable channel coalesces unchanged state. Silence while resting is not a drop.
        if held and (not IsValid(held.ent) or not alive or not active or active.kind ~= "physgun") then held = nil end
        holding = held and pose and pose.valid == true
        if ctx.Weapon then ctx.Weapon.ConvergeAt(holding and held.distance or nil) end
        if held then controls.Stick(ctx.Input.mainHand) end
        local visible = alive and active and active.kind == "toolgun" and IsValid(active.ent)
        if visible then
            local mode = player:GetInfo("gmod_toolmode")
            local object = active.ent.GetToolObject and active.ent:GetToolObject(mode)
            if object then
                local stage, operation = object:GetStage(), object:GetOperation()
                local lang = languagePreference and languagePreference.GetString and languagePreference:GetString() or ""
                if object ~= infoTool or mode ~= infoMode or stage ~= infoStage or operation ~= infoOperation or
                    lang ~= infoLanguage or RealTime() >= infoAt then
                    toolObject, toolSignature = Math.ToolInfo(mode, object, stage, operation, language.GetPhrase)
                    infoTool, infoMode, infoStage, infoOperation, infoLanguage = object, mode, stage, operation, lang
                    infoAt = RealTime() + 0.25
                    if tool and toolSignature ~= current.paintedSignature then tool:Invalidate() end
                    current.paintedSignature = toolSignature
                end
                if not tool then
                    local size = ctx.Overlay.Sizes.tool
                    tool = ctx.Overlay.New{key = "tool", name = "Tool information", width = size[1], height = size[2], paint = paintTool}
                    current.tool = tool
                    toolDisplay = Presentation.New(tool)
                    current.paintedSignature = toolSignature
                end
                local handPose, head = ctx.Hand[active.hand] and ctx.Hand[active.hand].shown, ctx.Pose.head
                if handPose and handPose.valid and head and head.valid then
                    -- Own the overlay point in the model's grip frame, without W's private placement data.
                    toolAnchor = handPose.pos
                    if IsValid(active.model) then
                        if active.model ~= anchorModel then anchorModel = active.model anchorBone = active.model:LookupBone("ValveBiped.Bip01_R_Hand") end
                        local matrix = anchorBone and active.model:GetBoneMatrix(anchorBone)
                        if matrix then toolAnchor = matrix:GetTranslation() end
                    end
                    local rotation = (toolAnchor - head.pos):Angle() rotation.r = 0
                    local pos = toolAnchor + rotation:Right() * (ctx.Space.scale * (active.hand == "left" and -0.19 or 0.19)) + Vector(0, 0, ctx.Space.scale * 0.08)
                    local p, a = ctx.ToTracking(pos, rotation)
                    toolDisplay.Place(p, a, 0.30) toolDisplay.Show(not wheel.open)
                else toolDisplay.Show(false) end
            else visible = false end
        end
        if not visible and toolDisplay then toolDisplay.Show(false) end
        local d = debug.physgun
        d.entity, d.tracked = held and held.ent:EntIndex() or 0, holding == true
        d.bone, d.distance = held and held.bone or nil, held and held.distance / ctx.Space.scale or nil
        d.hand, d.prop, d.target, d.difference = held and held.hand or nil, held and held.prop or nil, held and held.target or nil, held and held.error or nil
        debug.tool, debug.tool_anchor = visible and toolObject or nil, visible and toolAnchor or nil
        debug.tool_paints, debug.wheel = toolPaints, wheel.Debug()
    end)
    -- Before W's aim mover: update convergence in the frame, then the engine owns every attack.
    ctx.mover(80, function(cmd)
        local desired = ctx.Input.mainHand
        if desired ~= config then
            ctx.Net.Send(97, function(w) w.WriteBool(desired == "left") end) config = desired
        end
        if holding and ctx.Input.Owner("main", "stick") == ctx.name then
            local tick = engine.TickCount()
            if tick ~= lastTick then
                local now = CurTime()
                local dt = lastStepTime and now - lastStepTime or engine.TickInterval()
                distanceDirection, carry = Math.DistanceCommand(ctx.Input.main.stick.y, dt, carry)
                lastTick, lastStepTime = tick, now
            end
            local ply=LocalPlayer()
            local ladder=ply.GetMoveType and ply:GetMoveType()==MOVETYPE_LADDER
            if not ladder or distanceDirection and distanceDirection~=0 then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_USE))
            end
            if distanceDirection and distanceDirection > 0 then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_FORWARD))
            elseif distanceDirection and distanceDirection < 0 then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_BACK)) end
            cmd:SetMouseX(0) cmd:SetMouseY(0)
        else carry, lastTick, lastStepTime, distanceDirection = 0, nil, nil, nil end
    end)
    ctx.mover(950, wheel.Move)
    local function drawBeam(player, weapon, enabled, target, bone, offset)
        if player ~= LocalPlayer() or not ctx.Weapon or not ctx.Weapon.Active or ctx.Weapon.Active.kind ~= "physgun" then return end
        local origin, ang = ctx.Weapon.Muzzle()
        if not origin then return end
        local model = ctx.Weapon.Active.model
        if IsValid(model) then
            if model ~= beamModel then beamModel, beamAttachment = model, model:LookupAttachment("muzzle") end
            local attachment = model:GetAttachment(beamAttachment and beamAttachment > 0 and beamAttachment or 1)
            if attachment then origin = attachment.Pos end
        end
        if enabled then
            local endpoint
            if IsValid(target) then
                local phys = target:GetPhysicsObjectNum(bone)
                if IsValid(phys) then endpoint = LocalToWorld(offset, Angle(), phys:GetPos(), phys:GetAngles()) end
            end
            if not endpoint then
                local ray, direction = ctx.Weapon.Ray()
                if ray then endpoint = util.TraceLine{start = ray, endpos = ray + direction * 4096, filter = player}.HitPos end
            end
            if endpoint and (not beamPreference or beamPreference:GetBool()) then
                render.SetMaterial(beamMaterial)
                local colour = player:GetWeaponColor()
                beamColour.r, beamColour.g, beamColour.b = colour.x * 255, colour.y * 255, colour.z * 255
                render.DrawBeam(origin, endpoint, 1.5, 0, (endpoint - origin):Length() / 64, beamColour)
                beamDebug.origin, beamDebug.endpoint, beamDebug.frame = origin, endpoint, ctx.Frame and ctx.Frame.sequence
                debug.beam = beamDebug
            end
        end
    end
    current.beam = include("nlvr/modules/cl_tools_beam.lua").New(ctx, drawBeam)
    ctx.cleanup(function() module.Stop() end)
end
function module.Stop()
    if not current then return end
    local state = current current = nil
    state.wheel.Stop()
    if state.beam then state.beam.Stop() end
    state.controls.Stop()
    if state.tool then state.tool:Destroy() end
    if state.ctx.Weapon then state.ctx.Weapon.ConvergeAt(nil) end
    state.ctx.core.Tools, state.ctx.Debug.tools = nil, nil
end
return module
