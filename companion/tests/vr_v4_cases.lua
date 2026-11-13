-- V4 scaffold checks against the actual framework, composed by vr_framework_cases.lua.
return function(e, cases, helpers)
    local eq, close = e.eq, e.close
    local P = include("nlvr/sh_protocol.lua")
    function cases.f_v4_protocol()
        for n = 16, 127 do assert(P.ModuleType(n), n) end
        for n = 128, 300 do eq(P.ModuleType(n), false) end
        for _, n in ipairs({-1, 0, 15, 64.5, math.huge, -math.huge, 0/0, "64", false}) do eq(P.ModuleType(n), false) end
        local seen = {}
        for _, range in pairs(P.Modules) do
            for n = range[1], range[2] do assert(not seen[n] and P.ModuleType(n)) seen[n] = true end
        end
        eq(P.Modules.weapons[1], 64) eq(P.Modules.weapons[2], 79)
        eq(P.Modules.reload[1], 80) eq(P.Modules.reload[2], 95)
        eq(P.Modules.tools[1], 96) eq(P.Modules.tools[2], 111)
        for n = 112, 127 do eq(seen[n], nil) end
    end
    function cases.f_v4_client_network()
        local wire, delivered, sent = e.standins.Wire(), {}, {}
        net = wire net.Receivers = {} net.Receive = function(name, fn) net.Receivers[name] = fn end
        net.Start = wire.Clear
        net.SendToServer = function() wire.Rewind() sent[#sent + 1] = wire.ReadUInt(8) end
        e.running() local c = NLVR helpers.module(c)
        c.Registry.current = c.Registry.entries[#c.Registry.entries]
        for n = 64, 127 do
            local kind = n
            c.Net.On(kind, function() delivered[kind] = net.ReadUInt(8) end)
            c.Net.Send(kind, function(w) w.WriteUInt(kind, 8) end) eq(sent[#sent], kind)
            wire.Clear() wire.WriteUInt(kind, 8) wire.WriteUInt(kind, 8) wire.Rewind() net.Receivers.nlvr(16)
            eq(delivered[kind], kind)
        end
        for _, kind in ipairs({15, 128, 255, 256}) do
            eq(pcall(c.Net.On, kind, function() end), false) eq(pcall(c.Net.Send, kind), false)
        end
        c.Registry.current = nil helpers.done()
    end
    function cases.f_v4_server_network()
        local sv, wire, messages = helpers.server() assert(sv.Start(e.player, 40)) helpers.module(sv)
        sv.Registry.current = sv.Registry.entries[#sv.Registry.entries]
        local delivered = {}
        for n = 64, 127 do
            local kind = n
            sv.Net.On(kind, function(ply) eq(ply, e.player) delivered[kind] = net.ReadUInt(8) end)
            wire.Clear() wire.WriteUInt(kind, 8) wire.Rewind() sv.Receive(kind, 16, e.player)
            eq(delivered[kind], kind)
            e.step() assert(sv.Net.Send(e.player, kind))
            wire.Rewind() eq(wire.ReadUInt(8), kind)
        end
        for _, kind in ipairs({15, 128, 255, 256}) do
            eq(pcall(sv.Net.On, kind, function() end), false) eq(pcall(sv.Net.Send, e.player, kind), false)
            eq(sv.Receive(kind, 8, e.player), false)
        end
        sv.Registry.current = nil sv.Stop(e.player) eq(NLVR_SV, nil)
    end
    function cases.f_v4_overlays()
        e.running() local c, dimensions = NLVR, {}
        local expected = {wheel = {1035, 1037}, tool = {643, 133}, settings = {1283, 963},
            flat_close = {131, 133}, keyboard = {1039, 391}}
        local count = 0
        for key, size in pairs(c.Overlay.Sizes) do
            count = count + 1 local pair = size[1] .. "x" .. size[2]
            eq(size[1] % 2, 1) eq(size[2] % 2, 1) eq(dimensions[pair], nil) dimensions[pair] = key
        end
        eq(count, 21) helpers.module(c) c.Registry.current = c.Registry.entries[#c.Registry.entries]
        e.api.OverlaySource = function() end
        for key, size in pairs(expected) do
            eq(c.Overlay.Sizes[key][1], size[1]) eq(c.Overlay.Sizes[key][2], size[2])
            eq(pcall(c.Overlay.New, {key = "wrong_" .. key, width = size[1], height = size[2]}), false)
            local o = c.Overlay.New{key = key, width = size[1], height = size[2]}
            eq(pcall(c.Overlay.New, {key = key, width = size[1], height = size[2]}), false)
            o:Destroy()
        end
        c.Registry.current = nil helpers.done()
    end
    function cases.f_v4_settings()
        local specs = {physical_reload = {1, 0, 1}, foregrip = {1, 0, 1}, ammo_counter = {1, 0, 1}, gun_angle = {0, -45, 45}}
        e.running() local c = NLVR
        for name, spec in pairs(specs) do
            eq(c.Settings[name], spec[1]) local cv = e.cv["nl_vr_" .. name]
            cv:SetString(tostring(spec[3] + 10)) eq(c.Settings[name], spec[3])
            cv:SetString(tostring(spec[2] - 10)) eq(c.Settings[name], spec[2])
            cv:SetString("nan") eq(c.Settings[name], spec[1])
        end
        e.cv.nl_vr_gun_angle:SetString("-17.5") close(c.Settings.gun_angle, -17.5)
        helpers.done()
    end
    function cases.f_v4_page()
        -- Re-read just the dormant page to inspect engine declarations, never loading native VR.
        local create, declared = CreateClientConVar, {}
        CreateClientConVar = function(name, default, save, user, help, low, high)
            declared[name] = {default, save, user, help, low, high} return create(name, default)
        end
        assert(loadfile(e.root .. "/companion/nativeloader/lua/autorun/client/nativeloader_vr.lua"))()
        CreateClientConVar = create
        local controls, helps, last, group = {}, {}, nil, nil
        local panel = {Button = function() return {} end, ComboBox = function() return {AddChoice = function() end} end}
        function panel:Help(label) group = label end
        function panel:CheckBox(label, name) controls[name] = {kind = "check", label = label, group = group} last = name end
        function panel:NumSlider(label, name, low, high, decimals)
            eq(label, "") controls[name] = {kind = "slider", low = low, high = high, decimals = decimals} last = name
        end
        function panel:ControlHelp(text) helps[last or "other"] = text end
        NativeLoaderVR.BuildOptions(panel)
        for _, name in ipairs({"physical_reload", "foregrip", "ammo_counter", "gun_angle"}) do
            local key = "nl_vr_" .. name local spec, control = declared[key], controls[key]
            assert(spec and control and helps[key] and not helps[key]:find("\n", 1, true))
            eq(spec[2], true) eq(spec[3], false) assert(#spec[4] > 0)
            eq(spec[1], name == "gun_angle" and "0" or "1")
            eq(spec[5], name == "gun_angle" and -45 or 0) eq(spec[6], name == "gun_angle" and 45 or 1)
            if name ~= "gun_angle" then eq(control.kind, "check") eq(control.group, "Weapons")
            else eq(control.kind, "slider") eq(control.low, -45) eq(control.high, 45) eq(control.decimals, 0) end
        end
        e.clean()
    end
    function cases.f_v4_stubs()
        -- Actual fixed lists, actual descriptors and both local game modes; the stubs own no resources.
        for _, single in ipairs({true, false}) do
            game.SinglePlayer = function() return single end
            e.running() local clientEntries = NLVR.Registry.entries
            local order = {} for _, entry in ipairs(clientEntries) do order[#order + 1] = entry.module.name end
            eq(table.concat(order, ","), "core,hud,hands,move,ui,weapons,reload,tools,interact")
            for _, entry in ipairs(clientEntries) do
                if entry.module.name == "weapons" or entry.module.name == "reload" or entry.module.name == "tools" then
                    eq(#entry.cleanups, 0) eq(entry.active, true)
                end
            end
            helpers.done()
            for _, entry in ipairs(clientEntries) do eq(entry.stopped, true) eq(entry.active, false) end
            local clientNet = net
            local sv = helpers.server() sv.Start(e.player, 40) local entries = sv.Registry.entries
            for i, name in ipairs({"weapons", "reload", "tools"}) do
                local found
                for _, entry in ipairs(entries) do if entry.module.name == name then found = entry end end
                assert(found and found.active) eq(found.module.order, 42 + i * 2) eq(#found.cleanups, 0)
            end
            sv.Stop(e.player) eq(NLVR_SV, nil)
            for _, entry in ipairs(entries) do eq(entry.stopped, true) end
            net = clientNet
        end
        e.clean()
    end
    function cases.f_v4_head_roll()
        e.poses.hmd.ang = Angle(12, 0, 30) e.running() helpers.view()
        local c = e.standins.Command() hook.Run("CreateMove", c)
        close(c:GetViewAngles().p, 12) close(c:GetViewAngles().y, 90) close(c:GetViewAngles().r, 0)
        close(NLVR.Pose.head.ang.r, 30) close(helpers.view().angles.r, 30)
        helpers.done()
    end
    function cases.f_v4_aim_movement()
        e.running() helpers.view() local c = NLVR local ctx = helpers.module(c)
        local yaw, forward, side, offset = 90, 100, 0, 90
        ctx.mover(10, function(cmd)
            cmd:SetViewAngles(Angle(5, yaw, 0)) cmd:SetForwardMove(forward) cmd:SetSideMove(side) cmd:SetUpMove(31)
            c.Aim(Angle(-8, yaw + offset, 0), "weapon")
        end)
        local cmd = e.standins.Command()
        for _, y in ipairs({0, 90, -179, 179}) do
            yaw = y
            for _, d in ipairs({90, -90, 0, 360, -280}) do
                offset = d
                for _, movement in ipairs({{100, 0}, {0, 100}, {37, -53}}) do
                    forward, side = unpack(movement) e.step() hook.Run("CreateMove", cmd)
                    local before = Angle(0, yaw, 0):Forward() * forward + Angle(0, yaw, 0):Right() * side
                    local a = Angle(0, cmd:GetViewAngles().y, 0)
                    helpers.vec(a:Forward() * cmd:GetForwardMove() + a:Right() * cmd:GetSideMove(), before)
                    close(cmd:GetForwardMove()^2 + cmd:GetSideMove()^2, forward^2 + side^2)
                    close(cmd:GetUpMove(), 31) close(cmd:GetViewAngles().p, -8)
                end
            end
        end
        helpers.done()
    end
end
