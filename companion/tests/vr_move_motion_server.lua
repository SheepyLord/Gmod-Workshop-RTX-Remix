-- Test only; injected through the same admin-console/lock path as the fixture.
local ID, rows = "nlvr_l_motion_server", {}
local function flush()
    if #rows > 0 then
        local text = util.TableToJSON({kind = "L-server-motion", frames = rows})
        -- This compact per-tick record stays below the Source line bound in small batches.
        print("NLVR_Q " .. text) rows = {}
    end
end
local function v(p) return {p.x, p.y, p.z} end
hook.Add("FinishMove", ID, function(ply, mv)
    if ply ~= Entity(1) then return end
    rows[#rows + 1] = {time = SysTime(), game_time = CurTime(), tick = engine.TickCount(),
        origin = v(mv:GetOrigin()), velocity = v(mv:GetVelocity()), mode = ply:GetMoveType()}
    if #rows >= 8 then flush() end
end)
concommand.Add("nlvr_motion_done", function()
    flush() hook.Remove("FinishMove", ID) concommand.Remove("nlvr_motion_done")
end)
