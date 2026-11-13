local Core = {}
function Core.New(protocol)
    local moveBasis=include("nlvr/core/sh_move_basis.lua")
    local SV = {Players = {}, Debug = {accepted = 0, dropped = {}}, REACH = protocol.REACH * 40, Net = {}}
    local registry, live, events, movers, handlers, ordinal = nil, false, {}, {}, {}, 0
    local pending, sent, sentTick, packetOrder = {}, {}, {}, 0
    local function tick() return engine.TickCount() end
    function SV.Reach(ply) return SV.REACH * (SV.Players[ply] and SV.Players[ply].scale or 40) / 40 end
    local function drop(reason)
        SV.Debug.dropped[reason] = (SV.Debug.dropped[reason] or 0) + 1
        return false
    end
    local function lifecycle(phase)
        local hooks, dropped = 0, 0
        for _, entries in pairs(hook.GetTable()) do
            for id in pairs(entries) do if tostring(id):match("^nlvr%.") then hooks = hooks + 1 end end
        end
        for _, count in pairs(SV.Debug.dropped) do dropped = dropped + count end
        MsgN(string.format("[nlvr] server %s active=%s hooks=%d receiver=%s accepted=%d dropped=%d",
            phase, tostring(NLVR_SV == SV), hooks, tostring(net.Receivers[protocol.NAME] ~= nil), SV.Debug.accepted, dropped))
    end
    local function own(fn, entry) registry:Own(fn, entry) end
    function SV._On(entry, name, fn)
        events[name] = events[name] or {}
        local record = {entry, fn}
        table.insert(events[name], record)
        own(function() table.RemoveByValue(events[name], record) end, entry)
    end
    function SV.On(name, fn) return SV._On(assert(registry.current), name, fn) end
    function SV.Emit(name, ...)
        local copy = {}
        for i, record in ipairs(events[name] or {}) do copy[i] = record end
        for _, record in ipairs(copy) do registry:Call(record[1], record[2], ...) end
    end
    for _, name in ipairs({"OnStart", "OnStop", "OnSync", "OnDeath", "OnSpawn"}) do
        local event = name
        SV[event] = function(fn) return SV.On(event, fn) end
    end
    function SV._Mover(entry, priority, fn)
        ordinal = ordinal + 1
        local record = {entry = entry, priority = priority, fn = fn, ordinal = ordinal}
        movers[#movers + 1] = record
        table.sort(movers, function(a, b) return a.priority == b.priority and a.ordinal < b.ordinal or a.priority < b.priority end)
        own(function() table.RemoveByValue(movers, record) end, entry)
    end
    function SV.mover(priority, fn) return SV._Mover(assert(registry.current), priority, fn) end
    function SV.Net.On(kind, fn)
        assert(protocol.ModuleType(kind), "Reserved VR message type")
        assert(not handlers[kind], "Duplicate VR message handler")
        local entry = assert(registry.current)
        handlers[kind] = {entry, fn}
        own(function() handlers[kind] = nil end, entry)
    end
    local function flush(ply)
        if sentTick[ply] == tick() then return end
        local kind, packet
        for candidate, value in pairs(pending[ply] or {}) do
            if sent[ply][candidate] == value.signature then pending[ply][candidate] = nil
            elseif not packet or value.order < packet.order then kind, packet = candidate, value end
        end
        if packet then
            net.Start(protocol.NAME) net.WriteUInt(kind, 8) packet.Write(net) net.Send(ply)
            sent[ply][kind], sentTick[ply], pending[ply][kind] = packet.signature, tick(), nil
        end
    end
    local function maintain()
        local now = CurTime()
        for ply, state in pairs(SV.Players) do
            for _, hand in ipairs({"left", "right"}) do
                local history = state.history[hand]
                while history[1] and now - history[1].time > protocol.HISTORY_SECONDS do table.remove(history, 1) end
            end
            if state.lastSync and now - state.lastSync > protocol.HISTORY_SECONDS then
                state.head.valid, state.hands.left.valid, state.hands.right.valid = false, false, false
            end
            flush(ply)
        end
    end
    function SV.Net.Send(ply, kind, writer)
        assert(protocol.ModuleType(kind), "Reserved VR message type")
        if not SV.Players[ply] then return false end
        local packet = protocol.Packet(writer)
        packetOrder = packetOrder + 1
        packet.order = pending[ply][kind] and pending[ply][kind].order or packetOrder
        pending[ply][kind] = packet -- latest changed state replaces an unsent intermediate state
        flush(ply)
        return true
    end
    local function movement(ply, mv, cmd, isMove)
        local state = SV.Players[ply]
        if not state then return end
        if not isMove then
            moveBasis.Apply(ply,mv,cmd,state.head)
            state.moveTick, state.moveHandled = tick(), false
            local copy = {} for i, mover in ipairs(movers) do copy[i] = mover end
            for _, mover in ipairs(copy) do
                if registry:Call(mover.entry, mover.fn, ply, mv, cmd) == true then state.moveHandled = true break end
            end
        elseif state.moveTick == tick() and state.moveHandled then return true end
    end
    local function load()
        if live then return end
        live, events, movers, handlers = true, {}, {}, {}
        registry = include("nlvr/core/sh_modules.lua").New(SV, function(err) MsgN("[nlvr] server core: " .. err) SV.Stop() end)
        SV.Registry, NLVR_SV = registry, SV
        registry:Add({name = "core", order = 0, Stop = function() end, Start = function(ctx)
            ctx.hook("SetupMove", function(ply, mv, cmd) movement(ply, mv, cmd, false) end)
            ctx.hook("Move", function(ply, mv) return movement(ply, mv, nil, true) end)
            ctx.hook("Tick", maintain)
            ctx.hook("PlayerDisconnected", SV.Stop)
            ctx.hook("PlayerDeath", function(ply) if SV.Players[ply] then SV.Emit("OnDeath", ply, SV.Players[ply]) end end)
            ctx.hook("PlayerSpawn", function(ply) if SV.Players[ply] then SV.Emit("OnSpawn", ply, SV.Players[ply]) end end)
            ctx.hook("ShutDown", function() SV.Stop() end)
        end})
        for _, module in ipairs(SV.Modules) do registry:Add(module) end
        registry:Start()
    end
    function SV.Start(ply, scale)
        if not IsValid(ply) or not ply:IsPlayer() or not game.SinglePlayer() or not protocol.Scale(scale) then return false end
        if SV.Players[ply] then SV.Players[ply].scale = scale return true end
        load()
        local state = {active = true, scale = scale, head = {valid = false}, hands = {left = {valid = false}, right = {valid = false}},
            history = {left = {}, right = {}}, since = CurTime()}
        SV.Players[ply], pending[ply], sent[ply] = state, {}, {}
        SV.Emit("OnStart", ply, state)
        lifecycle("started")
        return true
    end
    function SV.Stop(ply)
        local function one(player)
            local state = SV.Players[player]
            if not state then return end
            state.active = false SV.Emit("OnStop", player, state)
            SV.Players[player], pending[player], sent[player], sentTick[player] = nil, nil, nil, nil
        end
        if ply then one(ply) else
            local players = {} for player in pairs(SV.Players) do players[#players + 1] = player end
            for _, player in ipairs(players) do one(player) end
        end
        if live and not next(SV.Players) then
            live = false registry:Stop()
            events, movers, handlers = {}, {}, {}
            if NLVR_SV == SV then NLVR_SV = nil end
            lifecycle("stopped")
            if SV.OnEmpty then SV.OnEmpty() end
        end
    end
    function SV.Receive(kind, bits, ply)
        local state = SV.Players[ply]
        if not state then return drop("inactive") end
        if not IsValid(ply) or not ply:IsPlayer() or not game.SinglePlayer() then return drop("player") end
        if kind == protocol.SYNC then
            local current = tick()
            if state.syncTick ~= current then state.syncTick, state.syncCount = current, 0 end
            state.syncCount = state.syncCount + 1
            if state.syncCount > 2 then return drop("rate") end
            if bits ~= protocol.SYNC_BITS then return drop("length") end
            local ok, sample = pcall(protocol.ReadSync, net)
            if not ok then return drop("decode") end
            local valid, reason = protocol.ValidateSync(sample, state, ply:EyePos(), SV.Reach(ply))
            if not valid then return drop(reason) end
            -- Preserve tracking-relative velocity for gestures/melee. Only physical
            -- following, holding and throwing opt into authoritative world motion.
            local motor=ply:GetVelocity()
            for _,pose in ipairs({sample.head,sample.hands.left,sample.hands.right}) do pose.wvel=(pose.vel or Vector())+motor end
            state.head, state.hands, state.seq = sample.head, sample.hands, sample.seq
            local now = CurTime()
            state.lastSync = now
            for _, hand in ipairs({"left", "right"}) do
                local history = state.history[hand]
                history[#history + 1] = {time = now, pose = sample.hands[hand], seq = sample.seq}
                while history[1] and (now - history[1].time > protocol.HISTORY_SECONDS or #history > 1024) do table.remove(history, 1) end
            end
            SV.Debug.accepted = SV.Debug.accepted + 1
            SV.Emit("OnSync", ply, state, sample)
            return true
        end
        if not protocol.ModuleType(kind) or bits > 32776 then return drop("type") end
        if state.messageTick ~= tick() then state.messageTick, state.messageCount = tick(), 0 end
        state.messageCount = state.messageCount + 1
        if state.messageCount > 64 then return drop("module-rate") end
        local handler = handlers[kind]
        if handler then registry:Call(handler[1], handler[2], ply) end
    end
    return SV
end
return Core
