-- Dormant switch: no nlvr include, hooks or timers until this server's own player opts in.
util.AddNetworkString("nlvr")
local server
local function eligible(ply)
    return IsValid(ply) and ply:IsPlayer() and (game.SinglePlayer() or ply:IsListenServerHost())
end
net.Receive("nlvr", function(bits, ply)
    if not eligible(ply) or bits < 8 then return end
    local kind = net.ReadUInt(8)
    if kind == 1 then
        if bits ~= 40 then return end
        local scale = net.ReadFloat()
        if scale ~= scale or scale < 10 or scale > 100 then return end
        if not server then
            local ok, result = pcall(include, "nlvr/server.lua")
            if not ok or type(result) ~= "table" then MsgN("[nlvr] server load: " .. tostring(result)) return end
            server = result
            server.OnEmpty = function() server = nil end
        end
        local ok, err = pcall(server.Start, ply, scale)
        if not ok then
            MsgN("[nlvr] server start: " .. tostring(err))
            server.Stop(ply)
        end
    elseif kind == 2 then
        if bits == 8 and server then server.Stop(ply) end
    elseif server then
        server.Receive(kind, bits, ply)
    end
end)
