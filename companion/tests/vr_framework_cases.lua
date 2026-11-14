return function(e)
    local eq, close, cases = e.eq, e.close, {}
    local function vec(a, b) close((a - b):Length(), 0) end
    local function view()
        return hook.Run("CalcView", e.player, e.player.feet + e.player.offset, Angle(0, 90, 0), 90, 1, 9000)
    end
    local function done() NativeLoaderVR.Stop() e.clean() end
    function cases.f_competing_addon_lifecycle()
        local peers=assert(loadfile(e.root.."/companion/tests/vr_hook_addon.lua"))().New()
        for cycle=1,2 do
            hook.Run("Think") hook.Run("CalcView")
            e.running() hook.Run("Think")
            local cmd=e.standins.Command() cmd:SetForwardMove(40)
            hook.Run("CreateMove",cmd)
            local current=view() peers.ObserveView(current,NLVR.Pose.head.pos)
            NativeLoaderVR.Stop() hook.Run("Think")
            hook.Run("CalcView") hook.Run("CreateMove",e.standins.Command())
        end
        local result=peers.Check({movement=true})
        local missing={} for key,ok in pairs(result.checks) do if not ok then missing[#missing+1]=key end end
        assert(result.success,"competing add-on lifecycle was not exercised: "..table.concat(missing,","))
        peers.Remove() e.clean()
    end
    local function module(c, name)
        return c.Registry:Add({name = name or "test", order = 90, Start = function() end, Stop = function() end}).ctx
    end
    local function pose(pos)
        return {valid = true, pos = pos or e.player:EyePos(), ang = Angle(4, 5, 6), vel = Vector(7, 8, 9),
            angvel = Vector(0.1, 0.2, 0.3), grip_force = 0.5, trigger_value = 0.75, curls = {0, 0.25, 0.5, 0.75, 1}, buttons = 31}
    end
    local P = include("nlvr/sh_protocol.lua")
    function cases.f_review_refresh_cache()
        e.running() view() local c=NLVR local calls=0
        module(c).resolver(500,function() calls=calls+1 end)
        c.Refresh() eq(calls,2)
        for i=1,20 do c.Refresh() end
        eq(calls,2,"unchanged inputs run the resolvers once")
        e.step() c.Refresh() eq(calls,4)
        c.Space.Turn(1) eq(calls,6)
        done()
    end
    function cases.f_review_overlay_repaint()
        e.running() view() local c=NLVR
        local entry=c.Registry:Add({name="repaint_test",order=90,Start=function() end,Stop=function() end})
        c.Registry.current=entry
        e.api.OverlaySource=function() end
        local draws=0
        local o=c.Overlay.New{key="repaint",width=305,height=105,paint=function() draws=draws+1 end}
        c.Registry.current=nil
        c.Overlay.Paint() eq(draws,1) eq(o.handle,nil)
        o:Show(true) c.Overlay.Paint() eq(draws,2,"late native bind must repaint static canvas")
        c.Overlay.Paint() eq(draws,2,"no redundant paint in one frame")
        e.step() c.Overlay.Paint() eq(draws,3,"binding must survive deferred render-thread source registration")
        o:Show(false) e.time(4) e.step() c.Overlay.Paint() eq(o.handle,nil)
        o:Show(true) c.Overlay.Paint() eq(draws,4,"recreated handle needs its image too")
        done()
    end
    function cases.f_review_overlay_budget()
        local handles,requests,peakNative,peakRequests,nextHandle={},{},0,0,0
        local function count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
        local function source(handle)
            requests[handle]=true peakRequests=math.max(peakRequests,count(requests))
            assert(count(requests)<=16,"runtime pending-source cap exceeded")
        end
        e.api.OverlayCreate=function()
            assert(count(handles)<32,"native cap exceeded")
            nextHandle=nextHandle+1 handles[nextHandle]=true peakNative=math.max(peakNative,count(handles)) return nextHandle
        end
        e.api.OverlaySource=source
        e.api.OverlayDestroy=function(handle) source(handle) handles[handle]=nil end
        e.running() local c=NLVR
        c.Registry.current=c.Registry.entries[#c.Registry.entries]
        local objects={}
        for key,size in pairs(c.Overlay.Sizes) do
            if key~="wrist" then objects[#objects+1]=c.Overlay.New{key=key,width=size[1],height=size[2]} end
        end
        for _,o in ipairs(objects) do o:Show(true) end
        -- Drain exactly as applyOverlayRequests swaps the pending map each rendered frame.
        requests={} e.step() c.Overlay.Paint()
        local shown=0 for _,o in pairs(c.Overlay.Objects) do assert(o.visible,"worst-case role hidden: "..o.key) shown=shown+1 end
        assert(shown==21 and peakNative==21 and peakRequests<=16)
        print("worst overlays visible="..shown.." native_peak="..peakNative.." pending_peak="..peakRequests)
        for _,o in pairs(c.Overlay.Objects) do o:Show(false) end
        requests={} e.time(3) e.step() c.Overlay.Paint()
        requests={} e.step() c.Overlay.Paint()
        eq(count(handles),0,"hidden native handles retire after two seconds")
        -- The LRU and all-visible-limit paths use the same manager with a smaller test budget.
        c.Overlay.NativeLimit=2
        requests={} e.step()
        objects[1]:Show(true) objects[2]:Show(true) objects[3]:Show(true)
        eq(objects[3].visible,false) eq(count(handles),2)
        objects[1]:Show(false) e.time(3.1) objects[2]:Show(false)
        objects[3]:Show(true) eq(objects[1].handle,nil) assert(objects[3].visible)
        for _,entry in ipairs(c.Registry.entries) do assert(not entry.stopped,"overlay pressure stopped module") end
        c.Registry.current=nil done()
    end
    local function sample(seq) return {seq = seq or 1, head = pose(), hands = {left = pose(), right = pose()}} end
    function cases.f_space()
        e.running() view()
        local c = NLVR
        for i = 1, 200 do
            c.Space.yaw, c.Space.scale = (i * 97) % 360 - 180, 10 + i % 90
            c.Space.anchor, c.Space.seated = Vector(i / 100, -i / 300, 0.1), 0.45
            local p, a = Vector(i / 37, -i / 23, 1.7), Angle(15, i % 120, 8)
            local world, rotation = c.ToWorld(p, a)
            local back, angle = c.ToTracking(world, rotation)
            vec(p, back) close(a.p, angle.p) close(a.y, angle.y) close(a.r, angle.r)
        end
        c.Refresh() local before = c.Pose.head.pos
        for _, turn in ipairs({30, -90, 180, 360, -720, 45}) do c.Space.Turn(turn) vec(c.Pose.head.pos, before) end
        local delta = Vector(7, -8, 3)
        c.Space.Shift(delta) vec(c.Pose.head.pos, before)
        e.player.feet = e.player.feet + delta e.step() view() vec(c.Pose.head.pos, before)
        done()
    end
    function cases.f_poses()
        e.poses.left, e.poses.right = pose(Vector(0.5, 1, 1.2)), pose(Vector(1, 1, 1.2))
        e.running() view()
        local c = NLVR
        eq(c.Pose.main, c.Pose.right) eq(c.Pose.off, c.Pose.left)
        vec(c.Pose.left.vel, Vector(-320, 280, 360))
        vec(c.Pose.left.angvel, Vector(-0.2, 0.1, 0.3))
        local seen = {}
        local ctx = module(c)
        ctx.resolver(20, function(hand, state) seen[#seen + 1] = "p" .. hand state.shown.pos = state.shown.pos + Vector(1, 0, 0) end)
        ctx.resolver(10, function(hand, state) seen[#seen + 1] = "h" .. hand state.blocked = true end)
        c.Refresh() eq(table.concat(seen, ","), "hleft,pleft,hright,pright")
        vec(c.Hand.left.shown.pos - c.Hand.left.target.pos, Vector(1, 0, 0)) eq(c.Hand.left.blocked, true)
        local origin, ray = c.Ray("main") vec(origin, c.Pose.right.pos) vec(ray, c.Pose.right.ang:Forward())
        e.cv.nl_vr_dominant:SetString("1") eq(c.Pose.main, c.Pose.left) eq(c.Input.main, c.Input.left)
        done()
    end
    function cases.f_input()
        local input = include("nlvr/core/cl_input.lua").New()
        local actions = {right_grip = {active = true, state = true}, right_grip_force = {active = true, x = 0.8},
            left_stick = {active = true, x = 0.2, y = -0.5}, right_skeleton = {active = true, curls = {0, 0.2, 0.4, 0.6, 1}, splay = {1, 0.5, 0.1, 0}}}
        input.Update(actions, 0, false) eq(input.main, input.right) eq(input.off, input.left)
        eq(input.main.pressed.grip, true) close(input.main.grip_force, 0.8) close(input.off.stick.y, -0.5)
        eq(input.main.curls[5], 1) close(input.main.splay[2], 0.5)
        assert(input.Claim("main", "grip", "ui")) eq(input.Claim("right", "grip", "interact"), false)
        eq(input.Owner(input.main, "grip"), "ui") assert(input.Claim("main", "grip", "ui"))
        input.Update(actions, 0.4, false) eq(input.Owner("main", "grip"), nil)
        eq(input.main.pressed.grip, false) assert(input.Held("main", "grip", 0.3))
        actions.right_grip.state = false input.Update(actions, 0.5, true)
        eq(input.Tapped("right", "grip"), false) eq(input.off.released.grip, true)
        actions.right_grip.state = true input.Update(actions, 1, true)
        actions.right_grip.state = false input.Update(actions, 1.2, true) assert(input.Tapped("off", "grip"))
        input.Update({}, 1.3, true) eq(input.Tapped("off", "grip"), false)
        for role, controls in pairs(input.Mapping) do
            for _, name in ipairs({"grip", "trigger", "stick", "stick_click", "a", "b"}) do assert(controls[name], role .. name) end
        end
        eq(input.Mapping.off.b[1], "wrist_menu") eq(input.Mapping.main.stick[1], "turn")
    end
    function cases.f_settings()
        eq(next(e.callbacks), nil) e.running()
        local n = 0 for _ in pairs(NLVR.Settings) do n = n + 1 end eq(n, 22)
        -- V8's frame generation: on by default (V6's half rate), a switch.
        eq(NLVR.Settings.frame_generation, 1) e.cv.nl_vr_frame_generation:SetString("0") eq(NLVR.Settings.frame_generation, 0)
        e.cv.nl_vr_frame_generation:SetString("7") eq(NLVR.Settings.frame_generation, 1)
        -- V7's true stereo is a switch: off by default, and anything above 1 is on.
        eq(NLVR.Settings.stereo, 0) e.cv.nl_vr_stereo:SetString("5") eq(NLVR.Settings.stereo, 1) e.cv.nl_vr_stereo:SetString("0")
        -- V6's quality: 0 is Auto, a step number pins that rung, and the setting stays within 0-16.
        eq(NLVR.Settings.quality, 0) e.cv.nl_vr_quality:SetString("3") eq(NLVR.Settings.quality, 3)
        e.cv.nl_vr_quality:SetString("99") eq(NLVR.Settings.quality, 16) e.cv.nl_vr_quality:SetString("0")
        e.cv.nl_vr_seated:SetString("1") e.cv.nl_vr_seated_offset:SetString("0.7") close(NLVR.Space.seated, 0.7)
        e.cv.nl_vr_height:SetString("0.5") close(NLVR.Settings.height, 1.2)
        e.cv.nl_vr_snap_angle:SetString("200") eq(NLVR.Settings.snap_angle, 90)
        e.cv.nl_vr_wrist_hud:SetString("0") eq(NLVR.Overlay.Objects.wrist.visible, false)
        e.cv.nl_vr_dominant:SetString("1") eq(NLVR.Overlay.Objects.wrist.device, "right")
        done()
    end
    function cases.f_movers_aim()
        e.running() view() local c, order, enabled = NLVR, {}, true
        local ctx = module(c)
        ctx.mover(20, function(cmd) order[#order + 1] = 20 cmd:SetSideMove(15) end)
        ctx.mover(10, function(cmd)
            order[#order + 1] = 10 cmd:SetForwardMove(25)
            if enabled then assert(c.Aim(Angle(3, 7, 0), "weapon")) eq(c.Aim(Angle(), "other"), false) end
        end)
        local cmd = e.standins.Command() hook.Run("CreateMove", cmd)
        eq(table.concat(order, ","), "10,20") close(cmd:GetViewAngles().y, 7)
        vec(Angle(0, 7, 0):Forward() * cmd.forward + Angle(0, 7, 0):Right() * cmd.side,
            Angle(0, c.Pose.head.ang.y, 0):Forward() * 25 + Angle(0, c.Pose.head.ang.y, 0):Right() * 15)
        enabled = false e.step() hook.Run("CreateMove", cmd) close(cmd:GetViewAngles().y, c.Pose.head.ang.y)
        done()
    end
    function cases.f_movers_noclip()
        e.running() view() local c=NLVR
        MOVETYPE_NOCLIP=8
        e.player.GetMoveType=function() return MOVETYPE_NOCLIP end
        local pitch=45
        module(c).mover(10,function(cmd)
            cmd:SetForwardMove(125) cmd:SetSideMove(30) cmd:SetUpMove(40)
            assert(c.Aim(Angle(pitch, c.Pose.head.ang.y+35, 0), "weapon"))
        end)
        for _,p in ipairs({45,-45}) do
            pitch=p e.step()
            local cmd=e.standins.Command() hook.Run("CreateMove",cmd)
            local a=cmd:GetViewAngles() local h=Angle(c.Pose.head.ang.p,c.Pose.head.ang.y,0)
            vec(a:Forward()*cmd.forward+a:Right()*cmd.side+a:Up()*cmd.up,
                h:Forward()*125+h:Right()*30+h:Up()*40)
        end
        done()
    end
    function cases.f_module_failure()
        local oldInclude, stopped, calls = include, 0, 0
        include = function(path)
            if path ~= "nlvr/modules/cl_hands.lua" then return oldInclude(path) end
            return {name = "hands", order = 20, Stop = function() stopped = stopped + 1 end, Start = function(ctx)
                ctx.timer("test", 1, 0, function() end)
                ctx.On("test", function() error("dead listener invoked") end)
                ctx.hook("test", function() calls = calls + 1 error("one module fault") end)
            end}
        end
        e.running() hook.Run("test") hook.Run("test")
        eq(stopped, 1) eq(calls, 1) eq(NativeLoaderVR.state, "running") eq(e.timers["nlvr.hands.test"], nil)
        NLVR.Emit("test") done() eq(stopped, 1) include = oldInclude
    end
    function cases.f_movers_ladder_water()
        e.running() view() local c=NLVR
        MOVETYPE_LADDER=9
        local mode,pitch="ladder",45
        e.player.GetMoveType=function() return mode=="ladder" and MOVETYPE_LADDER or 2 end
        e.player.WaterLevel=function() return mode=="water" and 2 or 0 end
        module(c).mover(10,function(cmd)
            cmd:SetForwardMove(125) cmd:SetSideMove(30) cmd:SetUpMove(20)
            assert(c.Aim(Angle(pitch,c.Pose.head.ang.y+35,0),"weapon"))
        end)
        for _,m in ipairs({"ladder","water"}) do for _,p in ipairs({45,-45}) do
            mode,pitch=m,p e.step()
            local cmd=e.standins.Command() hook.Run("CreateMove",cmd)
            local a=cmd:GetViewAngles() local ground=Angle(0,c.Pose.head.ang.y,0)
            local intended=Angle(c.Pose.head.ang.p,c.Pose.head.ang.y,0)
            local world=intended:Forward()*125+intended:Right()*30+intended:Up()*20
            vec(a:Forward()*cmd.forward+a:Right()*cmd.side+a:Up()*cmd.up,world)
            local mv=e.standins.Move()
            mv:SetMoveAngles(a) mv:SetForwardSpeed(cmd.forward) mv:SetSideSpeed(cmd.side) mv:SetUpSpeed(cmd.up)
            hook.Run("SetupMove",e.player,mv,cmd)
            close(mv:GetMoveAngles().p,m=="ladder" and c.Pose.head.ang.p or 0)
            local basis=mv:GetMoveAngles()
            vec(basis:Forward()*mv.forward+basis:Right()*mv.side+basis:Up()*mv.up,world)
            close(cmd:GetViewAngles().p,p)
        end end
        done()
    end
    function cases.f_movers_armed_medium_parity()
        e.poses.hmd.ang=Angle(-45,0,0)
        e.running() view() local c=NLVR
        local mode,armed,gunPitch,side="water",false,45,0
        MOVETYPE_LADDER=9
        e.player.GetMoveType=function() return mode=="ladder" and MOVETYPE_LADDER or 2 end
        e.player.WaterLevel=function() return mode=="water" and 2 or 0 end
        module(c).mover(10,function(cmd)
            cmd:SetForwardMove(3) cmd:SetSideMove(side) cmd:SetUpMove(0)
            if armed then c.Aim(Angle(gunPitch,c.Pose.head.ang.y+35,0),"weapon") end
        end)
        for _,medium in ipairs({"water","ladder"}) do for _,s in ipairs({0,.02}) do
            mode,side=medium,s local baseline
            for _,kind in ipairs({0,45,-45}) do
                armed,gunPitch=kind~=0,kind e.step()
                local cmd=e.standins.Command() hook.Run("CreateMove",cmd)
                local a=cmd:GetViewAngles() local mv=e.standins.Move()
                mv:SetMoveAngles(a) mv:SetForwardSpeed(cmd.forward) mv:SetSideSpeed(cmd.side) mv:SetUpSpeed(cmd.up) mv:SetButtons(cmd:GetButtons())
                hook.Run("SetupMove",e.player,mv,cmd)
                local b=mv:GetMoveAngles() local world=b:Forward()*mv.forward+b:Right()*mv.side+b:Up()*mv.up
                local head=Angle(-45,c.Pose.head.ang.y,0)
                vec(world,head:Forward()*3+head:Right()*side)
                if baseline then vec(world,baseline) else baseline=world end
                if mode=="ladder" then
                    eq(bit.band(mv:GetButtons(),IN_MOVERIGHT or 1024)~=0,false,"small side input must stay in forward ladder sector")
                end
            end
        end end
        done()
    end
    function cases.f_ladder_sectors()
        local B=include("nlvr/core/sh_move_basis.lua") MOVETYPE_LADDER=9
        local kind=MOVETYPE_LADDER local ply={GetMoveType=function() return kind end}
        for _,pitch in ipairs({0,-45}) do for _,deg in ipairs({0,3,5,10,20,22.499,22.501,45,67.499,67.5,67.501,90}) do
            for _,sign in ipairs({-1,1}) do for _,forwardSign in ipairs({-1,1}) do
                local cmd=e.standins.Command() cmd:SetViewAngles(Angle(pitch,13,0))
                cmd:SetForwardMove(forwardSign*200*math.cos(math.rad(deg))) cmd:SetSideMove(sign*200*math.sin(math.rad(deg)))
                local world=B.Intent(ply,cmd)
                local side=deg>22.5 local forward=deg<67.5
                eq(bit.band(cmd:GetButtons(),sign>0 and 1024 or 512)~=0,side,"ladder sector side at "..deg)
                eq(bit.band(cmd:GetButtons(),forwardSign>0 and 8 or 16)~=0,forward,"ladder sector forward at "..deg)
                assert(world,"ladder intent missing")
            end end
        end end
        kind=6 local cmd=e.standins.Command() cmd:SetButtons(16+1024) cmd:SetForwardMove(10)
        eq(B.Intent(ply,cmd),nil) eq(cmd:GetButtons(),16+1024,"vehicle buttons changed")
    end
    function cases.f_noclip_water_basis()
        local B=include("nlvr/core/sh_move_basis.lua")
        for _,water in ipairs({2,3}) do
            local ply={GetMoveType=function() return MOVETYPE_NOCLIP end,WaterLevel=function() return water end}
            local cmd=e.standins.Command() cmd:SetViewAngles(Angle(-30,70,0))
            local mv=e.standins.Move() mv:SetMoveAngles(Angle(-30,70,0)) mv:SetForwardSpeed(200) mv:SetUpSpeed(10)
            eq(B.Apply(ply,mv,cmd,{valid=true,ang=Angle(-45,0,0)}),false,"water overrode noclip")
            close(mv:GetMoveAngles().p,-30) close(mv:GetForwardSpeed(),200) close(mv:GetUpSpeed(),10)
        end
    end
    function cases.f_ladder_tool_buttons()
        e.running() view() local c=NLVR local B=include("nlvr/core/sh_move_basis.lua") MOVETYPE_LADDER=9
        e.player.GetMoveType=function() return MOVETYPE_LADDER end
        local ctx=module(c)
        ctx.mover(30,function(cmd) cmd:SetForwardMove(200) B.Intent(e.player,cmd) end)
        ctx.mover(80,function(cmd) cmd:SetButtons(bit.bor(32,16)) end)
        local cmd=e.standins.Command() hook.Run("CreateMove",cmd)
        eq(cmd:GetButtons(),32+16,"core overwrote physgun pull after movement intent") done()
    end
    function cases.f_module_order()
        local oldInclude, order = include, {}
        local orders = {hands = 20, move = 30, ui = 40, interact = 50}
        include = function(path)
            local name = path:match("nlvr/modules/cl_(%w+)%.lua")
            if not orders[name] then return oldInclude(path) end
            return {name = name, order = orders[name], Start = function() order[#order + 1] = "+" .. name end,
                Stop = function() order[#order + 1] = "-" .. name end}
        end
        e.running() done()
        eq(table.concat(order, ","), "+hands,+move,+ui,+interact,-interact,-ui,-move,-hands") include = oldInclude
    end
    function cases.f_overlays()
        e.running() view() local c = NLVR local ctx = module(c)
        local objects, dimensions = {}, {}
        for name, size in pairs(c.Overlay.Sizes) do
            local key = size[1] .. "/" .. size[2]
            assert(size[1] % 2 == 1 and size[2] % 2 == 1 and not dimensions[key]) dimensions[key] = true
        end
        local original = e.api.OverlaySource
        e.api.OverlaySource = function() end
        c.Registry.current = c.Registry.entries[#c.Registry.entries]
        local draws = 0
        local panel = c.Overlay.New{key = "test", width = 301, height = 101, pos = Vector(2, 2, 1.6), ang = Angle(),
            metres = 1, paint = function() draws = draws + 1 end}
        panel:Show(true) c.Registry.current = nil
        c.Overlay.Paint() c.Overlay.Paint() eq(draws, 1)
        panel:Invalidate() c.Overlay.Paint() eq(draws, 2)
        local pos = c.ToWorld(panel.pos)
        local _, ang = c.ToWorld(panel.pos, panel.ang)
        local u, v, distance = c.Overlay.Hit(panel, pos - ang:Forward() * 80, ang:Forward())
        close(u, 0.5) close(v, 0.5) close(distance, 80)
        u, v = c.Overlay.Hit(panel, pos - ang:Forward() * 80 + ang:Right() * 10 + ang:Up() * 3, ang:Forward())
        close(u, 0.75) close(v, 0.5 - 3 / (40 * 101 / 301))
        eq(c.Overlay.Hit(panel, pos + ang:Forward() * 80, -ang:Forward()), nil)
        eq(c.Overlay.Hit(panel, pos - ang:Forward() * 80, ang:Right()), nil)
        eq(c.Overlay.Hit(panel, pos - ang:Forward() * 80 + ang:Right() * 80, ang:Forward()), nil)
        panel:Show(false) eq(c.Overlay.Hit(panel, pos - ang:Forward() * 80, ang:Forward()), nil)
        panel:Destroy() panel:Destroy() e.api.OverlaySource = original done()
    end
    function cases.f_overlay_refusals()
        e.running() local c = NLVR local ctx = module(c)
        c.Registry.current = c.Registry.entries[#c.Registry.entries]
        for _, spec in ipairs({{key = "wrist", width = 769, height = 257}, {key = "other", width = 769, height = 257},
            {key = "even", width = 300, height = 101}, {key = "huge", width = 5001, height = 101},
            {key = "float", width = 3.5, height = 101}}) do eq(pcall(c.Overlay.New, spec), false) end
        c.Registry.current = nil done()
    end
    function cases.f_overlay_attached()
        e.poses.left = pose(Vector(0.5, 0.2, 1.4))
        e.running() view() local c = NLVR
        module(c) c.Registry.current = c.Registry.entries[#c.Registry.entries]
        e.api.OverlaySource = function() end
        local panel = c.Overlay.New{key = "attached", width = 303, height = 103, device = "left",
            pos = Vector(0.1, 0.02, 0.05), ang = Angle(15, -20, 45), metres = 0.3}
        panel:Show(true) c.Registry.current = nil
        local p, a = LocalToWorld(panel.pos, panel.ang, e.poses.left.pos, e.poses.left.ang)
        p, a = c.ToWorld(p, a)
        local u, v, distance = c.Overlay.Hit(panel, p - a:Forward() * 10, a:Forward())
        close(u, 0.5) close(v, 0.5) close(distance, 10)
        e.poses.left.valid = false c.Refresh()
        eq(c.Overlay.Hit(panel, p - a:Forward() * 10, a:Forward()), nil)
        done()
    end
    function cases.f_protocol()
        local wire, s = e.standins.Wire(), sample(4294967295)
        wire.WriteUInt(P.SYNC, 8) P.WriteSync(wire, s) eq(wire.Length(), P.SYNC_BITS)
        wire.Rewind() eq(wire.ReadUInt(8), 3)
        local back = P.ReadSync(wire)
        eq(back.seq, s.seq) vec(back.head.pos, s.head.pos) eq(back.hands.left.buttons, 31)
        for i = 1, 5 do close(back.hands.right.curls[i], s.hands.right.curls[i]) end
        assert(P.ValidateSync(back, {}, e.player:EyePos(), 100))
        assert(P.ValidateSync(sample(0), {seq = 4294967295}, e.player:EyePos(), 100))
        eq(P.ValidateSync(sample(1), {seq = 1}, e.player:EyePos(), 100), false)
        wire.Truncate(100) wire.Rewind() eq(pcall(P.ReadSync, wire), false)
    end
    function cases.f_protocol_rejections()
        local function rejects(change, reason)
            local s = sample() change(s)
            local ok, why = P.ValidateSync(s, {}, e.player:EyePos(), 100) eq(ok, false) eq(why, reason)
        end
        rejects(function(s) s.seq = -1 end, "sequence")
        rejects(function(s) s.seq = 0 / 0 end, "sequence")
        for _, name in ipairs({"head", "left", "right"}) do
            local function part(s) return name == "head" and s.head or s.hands[name] end
            for _, field in ipairs({"pos", "ang"}) do
                rejects(function(s) part(s)[field][field == "ang" and "p" or "x"] = math.huge end, "finite")
            end
            rejects(function(s) part(s).pos = e.player:EyePos() + Vector(101, 0, 0) end, "reach")
            rejects(function(s) part(s).valid = "yes" end, "finite")
        end
        for _, hand in ipairs({"left", "right"}) do
            for _, field in ipairs({"vel", "angvel"}) do
                rejects(function(s) s.hands[hand][field].z = 0 / 0 end, "finite")
            end
            for _, field in ipairs({"grip_force", "trigger_value"}) do
                for _, value in ipairs({-1, 2, math.huge, 0 / 0}) do rejects(function(s) s.hands[hand][field] = value end, "axis") end
            end
            rejects(function(s) s.hands[hand].curls[5] = nil end, "curls")
            rejects(function(s) s.hands[hand].curls[2] = 2 end, "curls")
            rejects(function(s) s.hands[hand].buttons = 32 end, "buttons")
        end
    end
    local function server()
        local wire, messages = e.standins.Wire(), {}
        local receiver = net.Receivers
        net = wire net.Receivers = receiver
        net.Receive = function(name, fn) receiver[name] = fn end
        net.Start = function() wire.Clear() end
        net.Send = function(ply) messages[#messages + 1] = {ply = ply, bits = wire.Length()} end
        util.AddNetworkString = function() end
        local sv = include("nlvr/server.lua")
        return sv, wire, messages
    end
    local function sync(sv, wire, s, bits)
        wire.Clear() P.WriteSync(wire, s) wire.Rewind()
        return sv.Receive(P.SYNC, bits or P.SYNC_BITS, e.player)
    end
    function cases.f_server_ladder_water_basis()
        local sv,wire=server() assert(sv.Start(e.player,40)) assert(sync(sv,wire,sample(1)))
        local state=sv.Players[e.player]
        MOVETYPE_LADDER=9
        for _,mode in ipairs({"ladder","water"}) do for _,pitch in ipairs({45,-45}) do
            e.player.GetMoveType=function() return mode=="ladder" and MOVETYPE_LADDER or 2 end
            e.player.WaterLevel=function() return mode=="water" and 2 or 0 end
            local ground=Angle(0,state.head.ang.y,0)
            local world=ground:Forward()*125+ground:Right()*30+Vector(0,0,20)
            local cmd=e.standins.Command() local a=Angle(pitch,ground.y+35,0) cmd:SetViewAngles(a)
            local mv=e.standins.Move() mv:SetMoveAngles(a)
            mv:SetButtons(bit.bor(IN_FORWARD or 8,IN_MOVERIGHT or 1024)) -- intent already carried by the built command
            mv:SetForwardSpeed(world:Dot(a:Forward())) mv:SetSideSpeed(world:Dot(a:Right())) mv:SetUpSpeed(world:Dot(a:Up()))
            hook.Run("SetupMove",e.player,mv,cmd)
            close(mv:GetMoveAngles().p,mode=="ladder" and state.head.ang.p or 0)
            local basis=mv:GetMoveAngles()
            vec(basis:Forward()*mv.forward+basis:Right()*mv.side+basis:Up()*mv.up,world)
            assert(mode~="ladder" or bit.band(mv:GetButtons(),IN_FORWARD or 8)~=0,"ladder lost forward intent")
            close(cmd:GetViewAngles().p,pitch)
        end end
        sv.Stop()
    end
    function cases.f_server_ladder_yaw_intent()
        local sv,wire=server() assert(sv.Start(e.player,40)) assert(sync(sv,wire,sample(1)))
        local state=sv.Players[e.player] MOVETYPE_LADDER=9
        e.player.GetMoveType=function() return MOVETYPE_LADDER end
        e.player.WaterLevel=function() return 0 end
        for _,delta in ipairs({.05,1,5}) do for _,f in ipairs({200,3,.02,-3}) do for _,s in ipairs({0,.02,-.02}) do for _,p in ipairs({45,-45}) do
            state.head.ang=Angle(-45,delta,0) -- accepted sync is newer/older than command construction
            local world=Vector(f,-s,0) local a=Angle(p,35,0)
            local flags=bit.bor(f>0 and (IN_FORWARD or 8) or (IN_BACK or 16),s>0 and (IN_MOVERIGHT or 1024) or s<0 and (IN_MOVELEFT or 512) or 0)
            local cmd=e.standins.Command() cmd:SetViewAngles(a) cmd:SetButtons(flags)
            local mv=e.standins.Move() mv:SetButtons(flags) mv:SetMoveAngles(a)
            mv:SetForwardSpeed(world:Dot(a:Forward())) mv:SetSideSpeed(world:Dot(a:Right())) mv:SetUpSpeed(world:Dot(a:Up()))
            hook.Run("SetupMove",e.player,mv,cmd)
            eq(mv:GetButtons(),flags,"late head yaw invented a full-speed ladder direction")
            local b=mv:GetMoveAngles() vec(b:Forward()*mv.forward+b:Right()*mv.side+b:Up()*mv.up,world)
        end end end end
        sv.Stop()
    end
    function cases.f_server_sync()
        local sv, wire = server()
        assert(sv.Start(e.player, 40)) assert(NLVR_SV == sv)
        assert(sync(sv, wire, sample(1))) assert(sync(sv, wire, sample(2)))
        eq(sync(sv, wire, sample(3)), false) eq(sv.Debug.dropped.rate, 1)
        local state = sv.Players[e.player] eq(state.seq, 2) eq(#state.history.left, 2)
        e.time(1.1) assert(sync(sv, wire, sample(3))) eq(#state.history.left, 1)
        eq(sync(sv, wire, sample(2)), false) eq(sv.Debug.dropped.sequence, 1)
        e.time(2) eq(sync(sv, wire, sample(4), 50), false) eq(sv.Debug.dropped.length, 1)
        local bad = sample(4) bad.hands.left.pos.x = math.huge
        eq(sync(sv, wire, bad), false) eq(sv.Debug.dropped.finite, 1)
        sv.Stop(e.player) eq(NLVR_SV, nil)
        for event, entries in pairs(e.hooks) do eq(entries["nlvr.core"], nil, event) end
    end
    function cases.f_world_velocity()
        local sv,wire=server()
        assert(sv.Start(e.player,40))
        e.player.velocity=Vector(400,0,0)
        assert(sync(sv,wire,sample(1)))
        local state=sv.Players[e.player]
        vec(state.hands.left.vel,Vector(7,8,9))
        vec(state.hands.left.wvel,Vector(407,8,9))
        vec(state.history.left[1].pose.vel,Vector(7,8,9))
        local velocity=include("nlvr/modules/sv_interact_math.lua").Throw(state.history.left,CurTime(),40)
        vec(velocity,Vector(407,8,9))
        sv.Stop()
    end
    function cases.f_server_movers()
        local sv = server() assert(sv.Start(e.player, 40)) local order, events = {}, {}
        local ctx = module(sv)
        ctx.mover(30, function() order[#order + 1] = 30 return true end)
        ctx.mover(20, function(ply, mv, cmd) order[#order + 1] = 20 assert(cmd) mv:SetOrigin(Vector(4, 5, 6)) return true end)
        ctx.mover(10, function() order[#order + 1] = 10 end)
        for _, name in ipairs({"OnDeath", "OnSpawn", "OnStop"}) do
            local event = name ctx.On(event, function(ply) eq(ply, e.player) events[#events + 1] = event end)
        end
        local mv = e.standins.Move()
        hook.Run("SetupMove", e.player, mv, e.standins.Command()) eq(table.concat(order, ","), "10,20")
        eq(hook.Run("Move", e.player, mv), true) vec(mv:GetOrigin(), Vector(4, 5, 6))
        hook.Run("PlayerDeath", e.player) eq(sv.Players[e.player].active, true)
        hook.Run("PlayerSpawn", e.player) hook.Run("PlayerDisconnected", e.player)
        eq(table.concat(events, ","), "OnDeath,OnSpawn,OnStop") eq(NLVR_SV, nil)
    end
    function cases.f_server_send()
        local sv, wire, messages = server() assert(sv.Start(e.player, 40))
        local value = 2
        local function writer(w) w.WriteVector(Vector(value, 3, 4)) w.WriteString("held") end
        sv.Net.Send(e.player, 40, writer) eq(#messages, 1)
        sv.Net.Send(e.player, 40, writer) e.time(1) hook.Run("Tick") eq(#messages, 1)
        value = 4 sv.Net.Send(e.player, 40, writer) eq(#messages, 2)
        value = 5 sv.Net.Send(e.player, 40, writer) eq(#messages, 2)
        value = 6 sv.Net.Send(e.player, 40, writer) e.time(2) hook.Run("Tick") eq(#messages, 3)
        wire.Rewind() eq(wire.ReadUInt(8), 40) vec(wire.ReadVector(), Vector(6, 3, 4)) eq(wire.ReadString(), "held")
        sv.Stop()
    end
    function cases.f_stale_history()
        local sv, wire = server() assert(sv.Start(e.player, 40))
        assert(sync(sv, wire, sample())) e.time(1.1) hook.Run("Tick")
        local state = sv.Players[e.player]
        eq(#state.history.left, 0) eq(state.hands.left.valid, false) eq(state.head.valid, false)
        assert(sync(sv, wire, sample(2))) eq(state.hands.left.valid, true)
        sv.Stop()
    end
    function cases.f_failed_mover()
        e.running() view() local c, count = NLVR, 0
        local first, second = module(c, "bad_mover"), module(c, "next_mover")
        first.mover(1, function() error("mover stopped") end)
        second.mover(2, function() count = count + 1 end)
        hook.Run("CreateMove", e.standins.Command()) eq(count, 1) done()
        local sv = server() assert(sv.Start(e.player, 40)) count = 0
        first, second = module(sv, "bad_mover"), module(sv, "next_mover")
        first.mover(1, function() error("server mover stopped") end)
        second.mover(2, function() count = count + 1 return true end)
        hook.Run("SetupMove", e.player, e.standins.Move(), e.standins.Command()) eq(count, 1)
        sv.Stop()
    end
    function cases.f_module_packets()
        local P, wire = include("nlvr/sh_protocol.lua"), e.standins.Wire()
        local vector = Vector(1, 2, 3)
        local packet = P.Packet(function(w) w.WriteVector(vector) w.WriteString("hello") w.WriteUInt(5, 3) end)
        vector.x = 77 packet.Write(wire) wire.Rewind()
        vec(wire.ReadVector(), Vector(1, 2, 3)) eq(wire.ReadString(), "hello") eq(wire.ReadUInt(3), 5)
        eq(pcall(P.Packet, function(w) w.WriteString(string.rep("a", 4096)) end), false)
        eq(pcall(P.Packet, function(w) w.WriteFloat(math.huge) end), false)
        eq(pcall(P.Packet, function(w) w.WriteUInt(256, 8) end), false)
        eq(pcall(P.Packet, function(w) w.WriteString("a\0b") end), false)
        local sv, _, messages = server() assert(sv.Start(e.player, 40))
        sv.Net.Send(e.player, 40, function(w) w.WriteUInt(0, 8) end)
        sv.Net.Send(e.player, 41, function(w) w.WriteUInt(1, 8) end)
        for t = 1, 4 do
            e.time(t) sv.Net.Send(e.player, 40, function(w) w.WriteUInt(t, 8) end) hook.Run("Tick")
        end
        eq(#messages, 5) sv.Stop()
    end
    function cases.f_stub()
        local includes, previousInclude, strings = 0, include, 0
        local sv, wire = server()
        include = function(path) includes = includes + 1 return previousInclude(path) end
        util.AddNetworkString = function(name) eq(name, "nlvr") strings = strings + 1 end
        assert(loadfile(e.root .. "/companion/nativeloader/lua/autorun/server/nativeloader_vr_server.lua"))()
        eq(includes, 0) eq(strings, 1) eq(NLVR_SV, nil)
        local function request(kind, scale, bits)
            wire.Clear() wire.WriteUInt(kind, 8) if scale then wire.WriteFloat(scale) end
            local length = wire.Length() wire.Rewind() net.Receivers.nlvr(bits or length, e.player)
        end
        e.player.host = false local single = game.SinglePlayer game.SinglePlayer = function() return false end
        request(1, 40) eq(includes, 0)
        -- Single-player only (ADR 0197): a listen-server host is refused as well.
        e.player.host = true request(1, 40) eq(includes, 0)
        game.SinglePlayer = function() return true end
        request(1, 101) request(1, 0 / 0) request(1, 40, 24) eq(includes, 0)
        request(1, 40) assert(includes > 0) assert(NLVR_SV)
        request(2) eq(NLVR_SV, nil)
        for event, entries in pairs(e.hooks) do eq(entries["nlvr.core"], nil, event) end
        request(1, 40) assert(NLVR_SV) request(2) eq(NLVR_SV, nil)
        assert(net.Receivers.nlvr) -- exactly the permanent stub remains
        game.SinglePlayer, include = single, previousInclude
    end
    function cases.f_client_sync()
        local wire, sent, original = e.standins.Wire(), {}, net
        net = wire net.Receivers = {} net.Receive = function(name, fn) net.Receivers[name] = fn end
        net.Start = function() wire.Clear() end
        local received = {}
        net.SendToServer = function()
            wire.Rewind() local kind = wire.ReadUInt(8) sent[#sent + 1] = kind
            if kind == P.SYNC then received[#received + 1] = P.ReadSync(wire) end
        end
        e.running() eq(sent[1], P.START) view()
        hook.Run("CreateMove", e.standins.Command()) hook.Run("CreateMove", e.standins.Command())
        eq(#sent, 2) eq(sent[2], P.SYNC)
        e.step() hook.Run("CreateMove", e.standins.Command()) eq(#sent, 3)
        e.step() e.poses.hmd.valid = false hook.Run("CreateMove", e.standins.Command())
        eq(received[#received].head.valid, false)
        done() eq(sent[5], P.STOP) eq(next(net.Receivers), nil) net = original
    end
    function cases.f_network_cleanup_error()
        e.running() view()
        net.SendToServer = function() error("closing game channel") end
        done() eq(NLVR, nil) eq(net.Receivers.nlvr, nil)
    end
    function cases.f_createmove_frame_error()
        e.running() view()
        local messages, original = 0, net.SendToServer
        net.SendToServer = function() messages = messages + 1 end
        e.api.BeginFrame = function() return nil, "frame failure" end
        for i = 1, 30 do e.step() hook.Run("CreateMove", e.standins.Command()) end
        eq(NativeLoaderVR.state, "failed") e.clean()
        -- 29 valid held-frame syncs and one STOP; no sync after the fatal sample.
        eq(messages, 30) net.SendToServer = original
    end
    assert(loadfile(e.root.."/companion/tests/vr_view_ownership_cases.lua"))()(e,cases,{view=view})
    e.standins.Traces()
    assert(loadfile(e.root .. "/companion/tests/vr_v4_cases.lua"))()(e, cases,
        {module = module, server = server, view = view, done = done, vec = vec})
    assert(cases[e.scenario], "Unknown framework scenario " .. e.scenario)()
end
