-- Test only: record actual rendered views, both engine feet paths and the latest FOLLOW.
local ID, installed, rows, lastFrame = "nlvr_l_motion", false, {}, nil
local function v(p) return {p.x, p.y, p.z} end
local function flush()
    if #rows > 0 then emit("L-motion", {frames = rows}) rows = {} end
end
local function restore()
    flush()
    hook.Remove("RenderScene",ID..".view")
end
local flight, cleared = false, false
hook.Add("PreRender", ID, function()
    if phase == "active" and NLVR and not installed and nlvr.TestState().time >= (M_FROM or 0) then
        installed = true
        if M_FROM then RunConsoleCommand("nlvr_L_stage", "reset") end
        local ctx
        for _, e in ipairs(NLVR.Registry.entries) do if e.module.name == "move" then ctx = e.ctx end end
        ctx.mover(-20, function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) end)
        hook.Add("RenderScene",ID..".view",function(position,angles)
            if phase~="active" then return end
            local result={origin=position,angles=angles}
            if result and NLVR and lastFrame ~= FrameNumber() then
                lastFrame = FrameNumber()
                local ply = LocalPlayer()
                rows[#rows + 1] = {time = SysTime(), game_time = CurTime(), t = nlvr.TestState().time - (M_OFFSET or 0),
                    frame = lastFrame, sequence = NLVR.Frame.sequence, camera = v(result.origin),
                    engine = v(ply:GetPos()), base = v(NLVR.Feet),
                    network = ply.GetNetworkOrigin and v(ply:GetNetworkOrigin()) or nil,
                    follow = NLVR.Debug.move and NLVR.Debug.move.follow, mode = ply:GetMoveType()}
                if #rows >= 32 then flush() end
            end
        end)
        ctx.cleanup(restore)
    end
    if phase == "active" and installed and not flight and nlvr.TestState().time - (M_OFFSET or 0) >= (M_FLIGHT_AT or 11.2) then
        flight = true RunConsoleCommand("nlvr_L_stage", "reset") RunConsoleCommand("nlvr_L_stage", "noclip")
    elseif phase == "flat-after" and not cleared then
        cleared = true restore()
        if not M_HAS_BASE_PROBE then RunConsoleCommand("nlvr_L_stage", "cleanup") end
        RunConsoleCommand("nlvr_motion_done") hook.Remove("PreRender", ID)
    end
end)
