-- Appended to the standard acceptance probe; its lexical emit/capture/errors remain authoritative.
local L_ID, marks, captured, savedL = "nlvr_L_probe", {}, {}, {}
for _, n in ipairs({"move_dir", "turn", "height", "seated", "seated_offset", "teleport", "vignette", "dominant"}) do
    savedL["nl_vr_" .. n] = GetConVar("nl_vr_" .. n):GetString()
end
savedL.nl_vr_scale = GetConVar("nl_vr_scale"):GetString()
local defaults = {move_dir = 0, turn = 0, height = 0, seated = 0, seated_offset = 0.45, teleport = 1, vignette = 0.6, dominant = 0}
for n, v in pairs(defaults) do RunConsoleCommand("nl_vr_" .. n, tostring(v)) end
local function mark(label)
    if marks[label] then return end
    marks[label] = true
    local p = LocalPlayer()
    emit("L-movement", {label = label, case = L_CASE, test = nlvr.TestState(), position = p:GetPos(),
        velocity = p:GetVelocity(), duck = p:Crouching(), ground = p:OnGround(), move = NLVR and NLVR.Debug.move,
        raw = NLVR and NLVR.Frame and NLVR.Frame.hmd, head = NLVR and NLVR.Pose.head,
        scale_cv = GetConVar("nl_vr_scale"):GetString()})
end
local function once(label, condition, fn)
    if condition and not marks[label] then mark(label) if fn then fn() end end
end
local function pic(label)
    if not captured[label] then captured[label] = true capture("L-" .. label) end
end
local function check_movement()
    if phase ~= "active" then return end
    if not NLVR or not NLVR.Debug.move then return end
    if not marks.baseline then
        marks.baseline = true
        for n, v in pairs(savedL) do before[n] = v end
        -- Let only timeline controls drive this private test; ordinary mouse/keyboard input
        -- must not enter the command before the production movement module applies it.
        NLVR.Registry.entries[4].ctx.mover(-20, function(cmd)
            cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0)
        end)
    end
    local state = nlvr.TestState() local t = state and state.time or 0
    if L_CASE == "combined" and t >= 50 then
        once("combined-teleport-reset", true, function()
            NLVR.Space.Turn(-(NLVR.Space.yaw or 0)) RunConsoleCommand("nlvr_L_stage", "reset")
        end)
    end
    if L_CASE == "movement" or (L_CASE == "combined" and t < 50) then
        once("room-before", t >= 4.5)
        once("room-after", t >= 6.5)
        once("hand-before", t >= 7.8)
        once("hand-after", t >= 10.5)
        once("head-mode", t >= 11, function() RunConsoleCommand("nl_vr_move_dir", "1") end)
        once("head-before", t >= 11.8)
        once("head-after", t >= 14.5)
        once("sprint-before", t >= 14.8)
        once("sprint-after", t >= 16.5)
        once("jump", t >= 17.3)
        once("snap", t >= 19.8)
        once("smooth-mode", t >= 20.5, function() RunConsoleCommand("nl_vr_turn", "1") end)
        once("smooth-before", t >= 20.8)
        once("smooth-after", t >= 22.4)
        once("mouse", t >= 23, function()
            local fired = false
            NLVR.Registry.entries[4].ctx.mover(-10, function(cmd) if not fired and cmd:CommandNumber()>0 then fired = true cmd:SetMouseX(100) end end)
        end)
        once("mouse-after", t >= 23.5)
        once("physical-down", t >= 25.5)
        once("physical-hold", t >= 26.5)
        once("physical-up", t >= 27.5)
        once("toggle-down", t >= 31.6)
        once("toggle-physical", t >= 32.5)
        once("toggle-up", t >= 33.7)
        once("seat-on", t >= 34, function() RunConsoleCommand("nl_vr_seated", "1") end)
        once("seated", t >= 34.7)
        once("seat-off", t >= 35, function() RunConsoleCommand("nl_vr_seated", "0") end)
        once("calibrate", t >= 36, function() NLVR.Emit("calibrate") end)
        once("calibrated", t >= 36.6)
        once("flight", t >= 38, function() RunConsoleCommand("nlvr_L_stage", "noclip") end)
        once("flight-quarter", t >= 40)
        once("flight-threequarters", t >= 42.6)
        once("wall-setup", t >= 44, function()
            NLVR.Space.Turn(-(NLVR.Space.yaw or 0)) RunConsoleCommand("nlvr_L_stage", "wall")
        end)
        once("wall-before", t >= 44.7)
        once("wall-after", t >= 46.5)
        once("wall-open", t >= 47, function() RunConsoleCommand("nlvr_L_stage", "clear") end)
        once("wall-open-before", t >= 47.4)
        once("wall-open-after", t >= 48)
        once("index-teleport-reset", t >= 51, function() RunConsoleCommand("nlvr_L_stage", "reset") end)
        once("index-teleport", t >= 55)
        if t >= 8.6 and t < 9.5 then pic("vignette") end
        if t >= 25.5 and t < 26 then pic("crouch") end
        if t >= 45.8 and t < 46.2 then pic("wall") end
        if t >= 52.5 and t < 53 then pic("index-arc") end
    else
        if L_CASE == "combined" then t = t - 47 end
        once("blink-before", t >= 4.5)
        once("blink-after", t >= 8)
        once("shift-mode", t >= 10, function() RunConsoleCommand("nl_vr_teleport", "2") end)
        once("shift-before", t >= 10.5)
        once("shift-after", t >= 14)
        once("ledge-setup", t >= 16, function() RunConsoleCommand("nlvr_L_stage", "ledge") end)
        once("ledge-before", t >= 17.8)
        once("ledge-after", t >= 21.5)
        once("ceiling-setup", t >= 23, function() RunConsoleCommand("nlvr_L_stage", "ceiling") end)
        once("refused", t >= 26.5, function()
            NLVR.Net.Send(25, function(w) w.WriteUInt(60000, 16) w.WriteBool(false) w.WriteUInt(1, 2)
                w.WriteVector(LocalPlayer():GetPos() + Vector(190, -10, 0)) end)
        end)
        once("refused-server", t >= 28, function() RunConsoleCommand("nlvr_L_stage", "sample") end)
        once("blink-clear", t >= 32, function()
            RunConsoleCommand("nlvr_L_stage", "reset") RunConsoleCommand("nl_vr_teleport", "1") RunConsoleCommand("nl_vr_vignette", "0")
        end)
        once("blink-zero-after", t >= 37)
        if t >= 6 and t < 6.5 then pic("arc-green") end
        if t >= 18.8 and t < 19.2 then pic("mantle") end
        if t >= 25.5 and t < 26 then pic("arc-red") end
        if NLVR.Debug.move.fade == 1 and not NLVR.Debug.move.pending and
            NLVR.Debug.move.teleport and NLVR.Debug.move.teleport.success and t >= 36 and t < 37 then pic("blink-fade") end
    end
end
local subscribed = false
hook.Add("PreRender", L_ID, function()
    if phase == "flat-after" and not marks.cleanup then
        marks.cleanup = true
        for n, v in pairs(savedL) do RunConsoleCommand(n, v) end
        RunConsoleCommand("nlvr_L_stage", "cleanup")
        hook.Remove("PreRender", L_ID)
    elseif phase == "active" and NLVR and not subscribed then
        subscribed = true
        -- L registered its debug updater first. Sample immediately after it, never a
        -- previous PostRender state paired with a new native pose after a capture stall.
        NLVR.Registry.entries[4].ctx.On("before_overlay_paint", check_movement)
    end
end)
