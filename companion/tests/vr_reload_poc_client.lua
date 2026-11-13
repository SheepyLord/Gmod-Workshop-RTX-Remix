local seen, finished, offAt, lastPhase, lastRequest = false, false, nil, -1, -10
local captures, calibrated = {}, {}
local counterAt = -10
local flatMove
local prepared = false
local saved = {}
local tracedInput, originalTapped
for _, name in ipairs({"physical_reload", "ammo_counter", "foregrip", "scale", "height", "seated", "dominant", "gun_angle"}) do
    local cv = GetConVar("nl_vr_" .. name) saved[name] = cv and cv:GetString()
end
local function out(kind, data) data = data or {} data.kind = kind print("NLVR_K " .. util.TableToJSON(data)) end
local function xyz(v) return {v.x, v.y, v.z} end
local function pyr(a) return {a.p, a.y, a.r} end
weapons.Register({Base = "weapon_base", PrintName = "Reload fixture", Spawnable = false,
    WorldModel = "models/weapons/w_pistol.mdl", Primary = {ClipSize = 4, DefaultClip = 4, Ammo = "Pistol"},
    Secondary = {Ammo = "none", ClipSize = -1}}, "nlvr_k_swep")
hook.Add("PreRender", "nlvr_k_probe", function()
    -- After the shared flat baseline, before its Start at seven seconds. The
    -- native world scale latches at Start, so calibration cannot set it afterward.
    if not prepared and SysTime() - began >= 5 then
        prepared = true
        for name, value in pairs({physical_reload = CONFIG.reload_button and "0" or "1", ammo_counter = "1",
            foregrip = "0", scale = "40", height = "0", seated = "0", dominant = "0", gun_angle = "0"}) do
            RunConsoleCommand("nl_vr_" .. name, value)
        end
        out("settings-prepared", {saved = saved})
    end
    if NLVR and nlvr and nlvr.TestState then
        local s = nlvr.TestState()
        if not s then return end
        seen = true
        if CONFIG.reload_button and not tracedInput then
            tracedInput, originalTapped = NLVR.Input, NLVR.Input.Tapped
            for _, entry in ipairs(NLVR.Registry.entries) do
                if entry.module.name == "reload" then entry.ctx.mover(71, function(cmd)
                    local state = nlvr.TestState()
                    local t = state and state.time % 20
                    if t and t >= 2.6 and t <= 8 then
                        local a = NLVR.Weapon and NLVR.Weapon.Active
                        out("button-command", {time = state.time, class = a and a.class,
                            client_game_time = CurTime(), number = cmd:CommandNumber(), command_tick = cmd:TickCount(),
                            reload = cmd:KeyDown(IN_RELOAD), next_attack = LocalPlayer().GetInternalVariable and LocalPlayer():GetInternalVariable("m_flNextAttack"), frame = FrameNumber(), tick = engine.TickCount()})
                    end
                end) end
            end
            tracedInput.Tapped = function(hand, control)
                local tapped = originalTapped(hand, control)
                local state = nlvr.TestState()
                local t = state and state.time % 20
                if control == "b" and tracedInput.Resolve(hand) == tracedInput.mainHand and t and t >= 2.6 and t <= 8 then
                    local b, a = tracedInput.main, NLVR.Weapon and NLVR.Weapon.Active
                    out("button-input", {time = state.time, class = a and a.class, down = b.b,
                        pressed = b.pressed.b, released = b.released.b, held = b.held.b, tapped = tapped,
                        owner = tracedInput.Owner(hand, control), frame = FrameNumber(), tick = engine.TickCount()})
                end
                return tapped
            end
        end
        -- Keep the production CreateMove path: the shared flat camera fixture's
        -- button clearing is useful before/after VR but would erase real firing.
        flatMove = flatMove or hook.GetTable().CreateMove and hook.GetTable().CreateMove[ID]
        hook.Remove("CreateMove", ID)
        local span = CONFIG.reload_calibrate and 1.7 or 20
        local phase = math.floor(s.time / span)
        local class = CONFIG.reload_classes[phase + 1]
        if class and (phase ~= lastPhase or NLVR_K_ACK ~= phase and s.time - lastRequest > 0.25) then
            lastPhase, lastRequest = phase, s.time
            RunConsoleCommand("nlvr_k_phase", tostring(phase), class, tostring(s.time % span), tostring(SysTime()))
        end
        local a = NLVR.Weapon and NLVR.Weapon.Active
        local counter = NLVR.Overlay.Objects.ammo
        if counter and s.time - counterAt >= 0.25 then
            counterAt = s.time
            out("counter", {class = a and a.class, time = s.time, device = counter.device,
                handle = counter.handle,
                native = nlvr.OverlayInfo(counter.handle), visible = nlvr.OverlayVisible(counter.handle),
                paints = NLVR.Debug.reload and NLVR.Debug.reload.paints,
                values = NLVR.Debug.reload and NLVR.Debug.reload.counter_values,
                dropped = NLVR.Debug.reload and NLVR.Debug.reload.dropped,
                drop_physics = NLVR.Debug.reload and NLVR.Debug.reload.drop_physics,
                drop_pos = NLVR.Debug.reload and NLVR.Debug.reload.drop_pos,
                drop_life = NLVR.Debug.reload and NLVR.Debug.reload.drop_life,
                clip = a and a.ent:Clip1(), reserve = a and LocalPlayer():GetAmmoCount(a.ent:GetPrimaryAmmoType()),
                pos = xyz(counter.pos), ang = pyr(counter.ang), main_pos = a and xyz(NLVR.Pose[a.hand].raw.pos),
                main_ang = a and pyr(NLVR.Pose[a.hand].raw.ang)})
        end
        if CONFIG.reload_counter_motion and counter and a then
            for _, mark in ipairs({{8.5, "counter-moved"}, {13.5, "counter-returned"}}) do
                if s.time >= CONFIG.reload_motion_start + mark[1] and not captures[mark[2]] then
                    if nlvr.Capture(mark[2], 15) then
                        captures[mark[2]] = true out("capture", {class = a.class, label = mark[2], time = s.time,
                            ammo_handle = counter.handle, reload = NLVR.Debug.reload})
                    end
                end
            end
        end
        if a and a.class == class and IsValid(a.model) and not calibrated[class] and s.time % span > 0.7 then
            local data = include("nlvr/modules/sh_reload.lua").Guns[class]
            if data then
                local pos, ang = LocalToWorld(data.port, data.axis, a.model:GetPos(), a.model:GetAngles())
                local tp, ta = NLVR.ToTracking(pos, ang)
                local muzzle, aim = NLVR.Weapon.Muzzle()
                local _, frame = WorldToLocal(a.model:GetPos(), a.model:GetAngles(), muzzle, aim)
                local localMuzzle = WorldToLocal(muzzle, aim, a.model:GetPos(), a.model:GetAngles())
                out("calibration", {class = class, port_tracking = xyz(tp), port_angle = pyr(ta), model_pos = xyz(a.model:GetPos()),
                    model_ang = pyr(a.model:GetAngles()), main_tracking = xyz(NLVR.Pose[a.hand].raw.pos),
                    local_muzzle = localMuzzle and xyz(localMuzzle), model_frame = pyr(frame),
                    model_scale = a.model:GetModelScale()})
                calibrated[class] = true
                if CONFIG.reload_calibrate then
                    local request = nlvr.Capture(class .. "-calibration", 15)
                    if request then out("capture", {class = class, label = class .. "-calibration", time = s.time,
                        ammo_handle = counter and counter.handle}) end
                end
            end
        end
        if not CONFIG.reload_calibrate and class then
            local t = s.time % 20
            for _, capture in ipairs({{8.7, "held"}, {10.2, "well"}, {17, "after"}}) do
                local key = class .. "-" .. capture[2]
                if t >= capture[1] and not captures[key] then
                    local request = nlvr.Capture(key, 15)
                    if request then captures[key] = true out("capture", {class = class, label = key, time = s.time,
                        ammo_handle = counter and counter.handle, reload = NLVR.Debug.reload}) end
                end
            end
        end
    elseif seen and not finished then
        offAt = offAt or RealTime()
        if RealTime() - offAt > 1 then
            finished = true
            if tracedInput then tracedInput.Tapped = originalTapped tracedInput, originalTapped = nil, nil end
            if flatMove then hook.Add("CreateMove", ID, flatMove) end
            for name, value in pairs(saved) do if value then RunConsoleCommand("nl_vr_" .. name, value) end end
            local restoreAt = RealTime()
            hook.Add("Think", "nlvr_k_restore", function()
                if RealTime() - restoreAt < 0.2 then return end
                local after, differences = {}, {}
                for name, value in pairs(saved) do
                    after[name] = GetConVar("nl_vr_" .. name):GetString()
                    if value ~= after[name] then differences[name] = {value, after[name]} end
                end
                out("settings-restored", {before = saved, after = after, differences = differences})
                hook.Remove("Think", "nlvr_k_restore")
            end)
            RunConsoleCommand("nlvr_k_done") NLVR_K_ACK = nil hook.Remove("PreRender", "nlvr_k_probe")
            out("client-stopped", {global_absent = NLVR == nil})
        end
    end
end)
