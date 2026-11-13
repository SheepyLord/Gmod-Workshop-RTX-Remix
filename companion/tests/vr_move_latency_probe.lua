-- Appended inside the standard probe chunk, so emit/phase/restore remain its real receipts.
local LID, frames, lastNumber, installed = "nlvr_l_latency", {}, nil, false
local origin, rawOrigin, yaw, scale, commandRoll
local function vector(v) return {v.x, v.y, v.z} end
local function flush()
    if #frames > 0 then emit("L-latency", {frames = frames}) frames = {} end
end
local function undo()
    flush()
    hook.Remove("RenderScene",LID..".view")
end
hook.Add("PreRender", LID, function()
    if phase == "active" and NLVR and not installed and nlvr.TestState().time >= (L_LATENCY_FROM or 0) then
        installed = true
        local context
        for _, entry in ipairs(NLVR.Registry.entries) do if entry.module.name == "move" then context = entry.ctx end end
        context.mover(-20, function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) end)
        context.mover(10000, function(cmd) commandRoll = cmd:GetViewAngles().r end)
        hook.Add("RenderScene",LID..".view",function(position,angles)
            if phase~="active" then return end
            local view={origin=position,angles=angles}
            local f = NLVR and NLVR.Frame
            if view and f and f.hmd.valid and lastNumber ~= FrameNumber() then
                lastNumber = FrameNumber()
                local raw = f.hmd.pos
                if not origin then
                    origin, rawOrigin, yaw, scale = view.origin, Vector(raw.x, raw.y, raw.z), NLVR.Space.yaw, NLVR.Space.scale
                end
                local delta = raw - rawOrigin
                local rad = math.rad(yaw)
                local ideal = origin + Vector(math.cos(rad) * delta.x - math.sin(rad) * delta.y,
                    math.sin(rad) * delta.x + math.cos(rad) * delta.y, delta.z) * scale
                local t = nlvr.TestState().time - (L_LATENCY_OFFSET or 0)
                frames[#frames + 1] = {t = t, frame = lastNumber, sequence = f.sequence, tick = engine.TickCount(),
                    camera = vector(view.origin), ideal = vector(ideal), raw = vector(raw), feet = vector(LocalPlayer():GetPos()),
                    head_roll = f.hmd.ang.r, camera_roll = view.angles.r, command_roll = commandRoll,
                    player_roll = LocalPlayer():EyeAngles().r}
                if #frames >= 32 then flush() end
            end
        end)
        context.cleanup(undo)
    elseif installed and phase ~= "active" then
        undo()
        if phase == "flat-after" then
            local p = LocalPlayer()
            local view = hook.Run("CalcView", p, p:EyePos(), p:EyeAngles(), 90, 1, 10000)
            emit("L-roll-off", {player_roll = p:EyeAngles().r, flat_view_roll = view and view.angles.r})
            hook.Remove("PreRender", LID)
        end
    end
end)
