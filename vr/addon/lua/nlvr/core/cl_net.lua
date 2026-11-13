local Network = {}
function Network.New(core, protocol)
    local self = {}
    local handlers, lastTick, scale, sequence, started = {}, nil, nil, 0, false
    local function start()
        net.Start(protocol.NAME) net.WriteUInt(protocol.START, 8) net.WriteFloat(core.Space.scale) net.SendToServer()
        scale, started = core.Space.scale, true
    end
    function self.Start()
        start()
        net.Receive(protocol.NAME, function(bits)
            if bits < 8 then return end
            local kind = net.ReadUInt(8)
            local record = handlers[kind]
            if record then core.Registry:Call(record[1], record[2]) end
        end)
    end
    function self.On(kind, fn)
        assert(protocol.ModuleType(kind), "Reserved VR message type")
        assert(not handlers[kind], "Duplicate VR message handler")
        local entry = assert(core.Registry.current)
        handlers[kind] = {entry, fn}
        core.Registry:Own(function() handlers[kind] = nil end, entry)
    end
    function self.Send(kind, writer)
        assert(protocol.ModuleType(kind), "Reserved VR message type")
        local packet = protocol.Packet(writer)
        net.Start(protocol.NAME) net.WriteUInt(kind, 8) packet.Write(net) net.SendToServer()
    end
    function self.Sync()
        local tick = engine.TickCount()
        if tick == lastTick or not core.Pose.head then return end
        lastTick = tick
        if scale ~= core.Space.scale then start() end
        sequence = (sequence + 1) % 4294967296
        local sample = {seq = sequence, head = core.Pose.head, hands = {}}
        for _, hand in ipairs({"left", "right"}) do
            local pose, controls = core.Pose[hand], core.Input[hand]
            local h = {valid = pose.valid, pos = pose.pos, ang = pose.ang, vel = pose.vel, angvel = pose.angvel,
                grip_force = controls.grip_force or 0, trigger_value = controls.trigger_value or 0, curls = controls.curls or {0, 0, 0, 0, 0}, buttons = 0}
            for name, mask in pairs(protocol.Buttons) do if controls[name] then h.buttons = h.buttons + mask end end
            sample.hands[hand] = h
        end
        net.Start(protocol.NAME) net.WriteUInt(protocol.SYNC, 8) protocol.WriteSync(net, sample) net.SendToServer()
        local debug = core.Debug.net
        if not debug then debug = {} core.Debug.net = debug end
        debug.sequence, debug.tick, debug.scale = sequence, tick, scale
    end
    function self.Stop()
        local ok, err = true, nil
        if started then ok, err = pcall(function()
            net.Start(protocol.NAME) net.WriteUInt(protocol.STOP, 8) net.SendToServer()
        end) end
        started, handlers = false, {}
        net.Receivers[protocol.NAME] = nil -- net has no RemoveReceiver; this is its documented receiver table
        if not ok then error(err) end -- cleanup is complete even if the game channel is already closing
    end
    return self
end
return Network
