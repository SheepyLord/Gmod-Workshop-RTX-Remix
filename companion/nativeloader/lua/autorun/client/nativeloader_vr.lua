-- V1's switch. No native module or nlvr/ file is loaded until an explicit request.
if SERVER then return end
if NativeLoaderVR and NativeLoaderVR.Stop then NativeLoaderVR.Stop() end
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N
local VR = {state = "off", detail = "", probe = {}, info = {}}
NativeLoaderVR = VR
VR.WristLabels = {N("Health"), N("Armour"), N("Ammo")}
local native, addon, poll
local nextPoll, pollErrors, pollError = 0, 0, nil
local function watch()
    hook.Add("PreRender", "nativeloader_vr_session", function()
        if RealTime() >= nextPoll then nextPoll = RealTime() + 0.1 poll() end
    end)
end
local TIMER, SHUTDOWN = "nativeloader_vr_session", "nativeloader_vr_session"
local scale = CreateClientConVar("nl_vr_scale", "40", true, false, "Game units per metre (restart VR after changing)", 10, 100)
CreateClientConVar("nl_vr_fov", "145", true, false, "Engine culling FOV; tested on the Index at 16:9", 100, 170)
local renderScale = CreateClientConVar("nl_vr_render_scale", "1", true, false, "Highest VR render scale; Auto may choose a lower one", 0.25, 1.5)
-- Settings live here while the add-on is dormant; active modules only read them.
for _, spec in ipairs({
    {"dominant", "0", "Dominant hand: 0 right, 1 left", 0, 1},
    {"move_dir", "0", "Smooth movement direction: 0 off hand, 1 head", 0, 1},
    {"turn", "0", "Turning: 0 snap, 1 smooth", 0, 1},
    {"snap_angle", "30", "Snap turn angle in degrees", 15, 90},
    {"turn_speed", "120", "Smooth turn speed in degrees per second", 30, 360},
    {"teleport", "1", "Teleport: 0 off, 1 blink, 2 shift", 0, 2},
    {"vignette", "0.6", "Movement and turning vignette strength; 0 disables it", 0, 1},
    {"seated", "0", "Enable seated mode", 0, 1},
    {"seated_offset", "0.45", "Seated height offset in metres", 0, 1},
    {"height", "0", "Calibrated eye height in metres (1.2 to 2.2); 0 uses nl_vr_scale", 0, 2.2},
    {"ghost_hands", "1", "Show the controller outline when a hand is blocked", 0, 1},
    {"gloves", "1", "Enable gravity gloves", 0, 1},
    {"climb", "1", "Enable climbing", 0, 1},
    {"melee", "1", "Enable physical melee", 0, 1},
    {"wrist_hud", "1", "Show the wrist HUD", 0, 1},
    {"physical_reload", "1", "Enable physical reload for HL2 weapons", 0, 1},
    {"foregrip", "1", "Enable two-handed weapon grip", 0, 1},
    {"ammo_counter", "1", "Show ammo beside the weapon hand", 0, 1},
    {"gun_angle", "0", "Gun pitch in the hand in degrees", -45, 45},
    {"quality", "0", "VR quality: 0 Auto; 1 Full (V1's preset) to 7 Floor", 0, 16},
    {"stereo", "0", "VR true stereo: path trace each eye with its own history (needs DLSS Ray Reconstruction)", 0, 1},
}) do
    CreateClientConVar("nl_vr_" .. spec[1], spec[2], true, false, spec[3], spec[4], spec[5])
end
local ERRORS = {
    module = N("The VR module is missing or could not load. Reinstall the RTX package, then restart Garry's Mod."),
    version = N("The VR module has an incompatible API. Update the RTX package and restart Garry's Mod."),
    runtime = N("This Remix runtime has no VR output. Update the RTX package and restart Garry's Mod."),
    addon = N("The VR add-on could not start. Reinstall the RTX package and try again."),
    server = N("VR works in single-player games only. Start a single-player game to use VR."),
    vrmod = N("Exit VRMod before starting RTX VR. Only one add-on can control the view."),
    gvrmod = N("Exit gVRMod before starting RTX VR. Only one add-on can control the view."),
    native = N("SteamVR could not start VR. Check the headset connection and SteamVR, then try again."),
    steamvr = N("SteamVR is not installed. Install SteamVR in Steam, connect the headset, then try again."),
    quit = N("SteamVR ended the VR session. The flat game's settings have been restored."),
    tracking = N("Waiting for headset tracking. Check that the base stations can see the headset."),
}
local STATES = {off = N("VR is off"), starting = N("Starting SteamVR..."), running = N("VR is running"),
    stopping = N("Stopping VR..."), failed = N("VR could not start")}
local function log(text) MsgN("[nativeloader] VR: " .. tostring(text)) end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function bounded(value, fallback, low, high)
    return finite(value) and math.Clamp(value, low, high) or fallback
end
local function loader_status()
    local ok, status = pcall(function()
        local text = file.Read("native-loader/status.json", "DATA")
        return text and util.JSONToTable(text)
    end)
    return ok and type(status) == "table" and status.schema == 1 and status or {}
end
VR.LoaderStatus = loader_status
-- V6: the step Start renders at, so the first frames need no resize; Auto moves on from there.
-- The ladder is the add-on's file, loaded only once VR is requested.
function VR.StartStep()
    local Ladder = include("nlvr/modules/cl_perf_ladder.lua")
    local pinned = GetConVar("nl_vr_quality")
    pinned = pinned and math.floor(pinned:GetFloat()) or 0
    if pinned > 0 then return math.min(pinned, Ladder.Count()), Ladder end
    local status = loader_status()
    local activation = type(status.activation) == "table" and status.activation or {}
    local tier = type(activation.performance_tier) == "table" and activation.performance_tier or {}
    local memory = type(activation.memory) == "table" and activation.memory or {}
    local vram = finite(tier.dedicated_vram_mib) and tier.dedicated_vram_mib > 0 and tier.dedicated_vram_mib or memory.vram_mib
    return Ladder.Start(tier.tier, vram), Ladder
end
-- Exported for diagnostics and the offline harness; no state or file writes.
function VR.GPUWarning(status)
    local activation = type(status.activation) == "table" and status.activation or {}
    local tier = type(activation.performance_tier) == "table" and activation.performance_tier or {}
    local memory = type(activation.memory) == "table" and activation.memory or {}
    local vram = finite(tier.dedicated_vram_mib) and tier.dedicated_vram_mib > 0 and tier.dedicated_vram_mib or memory.vram_mib
    return tier.tier == "low" or (finite(vram) and vram > 0 and vram < 12288)
end
local function conflict()
    local active = type(g_VR) == "table" and g_VR.active == true
    if not active and type(vrmod) == "table" and type(vrmod.IsPlayerInVR) == "function" then
        local ok, result = pcall(vrmod.IsPlayerInVR, LocalPlayer())
        active = ok and result == true
    end
    if active then
        -- gVRMod's API shares VRMod's g_VR.active; its own add-on path identifies the fork.
        return file.Exists("vrmod/core/cl_vrmod.lua", "LUA") and
            file.Exists("vrmod/ui/cl_panel2vr.lua", "LUA") and "gvrmod" or "vrmod"
    end
end
local function load_native()
    if native then return true end
    -- GMod's require tries a Lua fallback and prints a script error for an absent binary even
    -- inside pcall. Detect that ordinary missing-package case before asking the module loader.
    if type(nlvr) ~= "table" and not file.Exists("lua/bin/gmcl_nlvr_win64.dll", "GAME") then
        return false, "module", "gmcl_nlvr_win64.dll not found"
    end
    local ok, detail = pcall(require, "nlvr")
    if not ok or type(nlvr) ~= "table" then return false, "module", tostring(detail) end
    local api = nlvr
    local versionOK, version = pcall(api.Version)
    if not versionOK or version ~= 1 then return false, "version", tostring(version) end
    for _, name in ipairs({"Probe", "Start", "State", "Stop", "BeginFrame", "SetFrameCamera", "Info", "Events",
        "OverlayCreate", "OverlaySource", "OverlayAttach", "OverlayShow", "OverlayDestroy"}) do
        if type(api[name]) ~= "function" then return false, "version", "Missing nlvr." .. name end
    end
    native = api
    return true
end
local function stopped()
    -- Native-initiated stopping may be observed before Lua requested Stop. Never
    -- acknowledge off with the view producer still installed.
    if addon then
        local ok, err = pcall(addon.Stop)
        if not ok then log("Add-on cleanup: " .. tostring(err)) end
        addon = nil
    end
    timer.Remove(TIMER)
    hook.Remove("PreRender", TIMER)
    hook.Remove("ShutDown", SHUTDOWN)
    local reason, detail = VR.stopReason, VR.stopDetail
    VR.state, VR.reason, VR.detail, VR.info = reason and reason ~= "quit" and "failed" or "off", reason, detail or "", {}
    VR.sessionScale, VR.stopReason, VR.stopDetail, VR.capReported = nil, nil, nil, nil
end
function VR.Stop(reason, detail)
    if addon then
        local ok, err = pcall(addon.Stop)
        if not ok then log("Add-on cleanup: " .. tostring(err)) end
    end
    addon = nil
    if native then
        local ok, result, err = pcall(native.Stop)
        if not ok or result == false or (result == nil and err ~= nil) then
            log("Module cleanup: " .. tostring(err or result))
        end
    end
    VR.stopReason, VR.stopDetail = reason, detail or ""
    local ok, state = false, nil
    if native then ok, state = pcall(native.State) end
    if ok and state ~= "off" then
        VR.state, VR.detail = "stopping", detail or ""
        watch()
    else stopped() end
    if reason then log((ERRORS[reason] or reason) .. (detail and detail ~= "" and " " .. detail or "")) end
end
local function fail(reason, detail) VR.Stop(reason, tostring(detail or "")) return false end
function VR.CheckStatus()
    local ok, reason, detail = load_native()
    if not ok then return fail(reason, detail) end
    local probed, result, errorText = pcall(native.Probe)
    if probed and type(result) == "table" then VR.probe = result end
    if not probed or type(result) ~= "table" then return fail("native", errorText or result or "Probe returned nil") end
    return true
end
poll = function()
    local ok, state, detail = pcall(native.State)
    if not ok or state == nil then
        local message = tostring(detail or state or "State returned nil")
        if pollError ~= message then log(message) pollError = message end
        pollErrors = pollErrors + 1
        if pollErrors >= 10 then fail("native", message) end
        return
    end
    if VR.state == "stopping" then if state == "off" then stopped() end return end
    if state == "stopping" then VR.Stop("quit", detail) return end
    if state == "failed" then fail("native", detail) return end
    if state == "off" then VR.Stop("quit", detail) return end
    VR.state, VR.detail = state, detail or ""
    local infoOK, info, infoDetail = pcall(native.Info)
    if not infoOK or type(info) ~= "table" then
        local message = tostring(infoDetail or info or "Info returned nil")
        if pollError ~= message then log(message) pollError = message end
        pollErrors = pollErrors + 1 if pollErrors >= 10 then fail("native", message) end
        return
    end
    if info.frame_error and info.frame_error ~= "" then
        if pollError ~= info.frame_error then log(info.frame_error) pollError = info.frame_error end
        pollErrors = pollErrors + 1 if pollErrors >= 10 then fail("native", info.frame_error) end
        return
    end
    VR.info = info
    -- OpenVR is ready before the first traced frame. Install the view producer now, so that
    -- BeginFrame/SetFrameCamera can bootstrap that frame without waiting on its own output.
    if state == "running" or (state == "starting" and VR.info.sdk_ready == true) then
        if not addon then
            local loaded, result = pcall(include, "nlvr/client.lua")
            if not loaded or type(result) ~= "table" or type(result.Start) ~= "function" or type(result.Stop) ~= "function" then
                fail("addon", result) return
            end
            addon = result -- keep the cleanup even when Start raises halfway through
            local started, resultOK, errorText = pcall(addon.Start, native, function(err) fail("addon", err) end, VR.sessionScale)
            if not started or resultOK == false then fail("addon", errorText or resultOK) return end
        end
    end
    local eventsOK, events, eventsDetail = pcall(native.Events)
    if not eventsOK or type(events) ~= "table" then
        local message = tostring(eventsDetail or events or "Events returned nil")
        if pollError ~= message then log(message) pollError = message end
        pollErrors = pollErrors + 1 if pollErrors >= 10 then fail("native", message) end
        return
    end
    pollErrors, pollError = 0, nil
    for _, event in ipairs(type(events) == "table" and events or {}) do
        if event.type == "quit" then VR.Stop("quit") return end
        -- One reader owns native.Events. Fan out keyboard/dashboard events through F's registry.
        if NLVR then NLVR.Emit("native_event", event) end
    end
end
function VR.Start(options)
    if VR.state == "starting" or VR.state == "running" or VR.state == "stopping" then return false end
    local player = LocalPlayer()
    if not IsValid(player) or not game.SinglePlayer() then return fail("server") end
    local other = conflict()
    if other then return fail(other) end
    local ok, reason, detail = load_native()
    if not ok then return fail(reason, detail) end
    local probeOK, probe = pcall(native.Probe)
    if probeOK and type(probe) == "table" then VR.probe = probe end
    if VR.probe.runtime_api ~= 4 then return fail("runtime") end
    if VR.probe.steamvr_installed == false then return fail("steamvr") end
    options = type(options) == "table" and options or {}
    -- V6: render at the step Auto starts from (or the pinned one); the slider is its ceiling.
    local index, Ladder = VR.StartStep()
    local step = Ladder.Step(index, bounded(renderScale:GetFloat(), 1, 0.25, 1.5))
    options.scale = bounded(scale:GetFloat(), 40, 10, 100)
    options.render_scale = step.render_scale
    VR.sessionScale = options.scale -- the camera must use the same scale as the runtime, even if edited during startup
    VR.state, VR.reason, VR.detail, VR.info = "starting", nil, "", {}
    VR.stopReason, VR.stopDetail = nil, nil
    nextPoll, pollErrors, pollError = 0, 0, nil
    -- Install shutdown before launching the worker: also covers a failed/unfinished start.
    hook.Add("ShutDown", SHUTDOWN, function() VR.Stop() end)
    local started, success, err = pcall(native.Start, options)
    if not started or success ~= true then return fail("native", err or success) end
    watch()
    log("Starting SteamVR")
    return true
end
concommand.Add("nl_vr_start", function(_, _, args)
    VR.Start(args and args[1] and {timeline = args[1]} or nil)
end)
function VR.Recenter() if addon and addon.Recenter then addon.Recenter() end end
concommand.Add("nl_vr_recenter", function() VR.Recenter() end)
concommand.Add("nl_vr_exit", function() VR.Stop() log("Exited VR; flat settings restored") end)

-- Also used by the active add-on; marking these here keeps one translated companion namespace.
VR.UILabels = {}
for _, source in ipairs({N("Wrist menu"), N("Spawn menu"), N("Context menu"), N("Flat screen"), N("VR settings"),
    N("Calibrate height"), N("Recentre VR"), N("Exit VR"), N("Enter text"),
    N("Keyboard"), N("Shift"), N("Space"), N("Backspace"), N("Enter"), N("Close"), N("Tab"),
    N("Left"), N("Right"), N("Home"), N("End"), N("Delete"),
    N("This menu is unavailable in this gamemode."),
    N("The flat screen needs a newer VR module and Remix runtime. Update the RTX package.")}) do
    VR.UILabels[source] = source
end
function VR.Calibrate()
    if NLVR then NLVR.Emit("height_calibrate") return true end
    return false
end
function VR.OpenBindings()
    if not native or not native.OpenBindingUI or VR.state ~= "running" then return false end
    local ok, result, detail = pcall(native.OpenBindingUI)
    if not ok or result == false or (result == nil and detail) then log(tostring(detail or result)) return false end
    return true
end
function VR.BuildOptions(panel)
    -- Minimal diagnostic panel stand-ins may implement only the V1 controls.
    if not panel.ComboBox or not panel.CheckBox then return end
    local function choice(title, cvar, choices)
        panel:Help(L(title))
        local box = panel:ComboBox("", cvar)
        for i, label in ipairs(choices) do box:AddChoice(L(label), i - 1) end
    end
    local function slider(title, cvar, low, high, decimals)
        panel:Help(L(title))
        local control=panel:NumSlider("", cvar, low, high, decimals)
        if not control then return end
        -- Derma's scratch/text synchronization can echo 0.60 for an unchanged 0.6.
        -- Leave the player's exact value alone until its numeric value changes.
        for _,part in ipairs({control.Scratch,control.TextArea}) do
            local changed=part.ConVarChanged
            if changed then
                part.ConVarChanged=function(self,value)
                    local current=GetConVar(cvar)
                    if current and tonumber(current:GetString())==tonumber(value) then return end
                    return changed(self,value)
                end
            end
        end
    end
    panel:Help(L("Quality"))
    choice(N("Quality step"), "nl_vr_quality",
        {N("Auto"), N("Full"), N("High"), N("Balanced"), N("Fast"), N("Faster"), N("Low"), N("Floor")})
    panel:ControlHelp(L("Auto keeps VR at half the headset's refresh rate, and SteamVR's Motion Smoothing fills in the rest. A fixed step stays where you set it."))
    panel:CheckBox(L("True stereo"), "nl_vr_stereo")
    panel:ControlHelp(L("Path traces each eye with its own history instead of turning one picture into both eyes. It costs about a quarter more GPU time, so Auto may choose a lower step, and it needs DLSS Ray Reconstruction."))
    panel:Help(L("Controls and comfort"))
    choice(N("Dominant hand"), "nl_vr_dominant", {N("Right hand"), N("Left hand")})
    choice(N("Movement direction"), "nl_vr_move_dir", {N("Off hand"), N("Head")})
    choice(N("Turning"), "nl_vr_turn", {N("Snap turn"), N("Smooth turn")})
    slider(N("Snap angle (degrees)"), "nl_vr_snap_angle", 15, 90, 0)
    slider(N("Turn speed (degrees per second)"), "nl_vr_turn_speed", 30, 360, 0)
    choice(N("Teleport"), "nl_vr_teleport", {N("Off"), N("Blink"), N("Shift")})
    slider(N("Movement vignette"), "nl_vr_vignette", 0, 1, 2)
    panel:ControlHelp(L("The vignette shades the edge of your view while moving or turning. Zero turns it off."))
    panel:CheckBox(L("Seated mode"), "nl_vr_seated")
    slider(N("Seated height offset (metres)"), "nl_vr_seated_offset", 0, 1, 2)
    local calibrate = panel:Button(L("Calibrate height")) calibrate.DoClick = VR.Calibrate
    panel:ControlHelp(L("Start VR, stand straight, then calibrate. Your tracked eye height sets world scale. To reset, set nl_vr_height to 0."))
    panel:ControlHelp(L("A changed height calibration takes effect after Exit VR and Start VR."))
    panel:Help(L("Hands and HUD"))
    panel:CheckBox(L("Ghost hands"), "nl_vr_ghost_hands")
    panel:ControlHelp(L("Show an outline at the real controller when the visible hand stops against something."))
    panel:CheckBox(L("Wrist HUD"), "nl_vr_wrist_hud")
    panel:Help(L("Physical interaction"))
    panel:CheckBox(L("Gravity gloves"), "nl_vr_gloves")
    panel:CheckBox(L("Climbing"), "nl_vr_climb")
    panel:CheckBox(L("Physical melee"), "nl_vr_melee")
    panel:ControlHelp(L("Grip grabs. Point, grip and flick to pull a loose object. Grip a ledge to climb. Fast hands and held objects can strike."))
    panel:ControlHelp(L("Turn on Keep corpses in the game's options to make NPC bodies grabbable in VR."))
    panel:Help(L("Weapons"))
    panel:CheckBox(L("Physical reload"), "nl_vr_physical_reload")
    panel:ControlHelp(L("Eject with A, take ammo over your shoulder, then insert it into HL2 weapons. Other weapons reload on a B tap."))
    panel:CheckBox(L("Foregrip"), "nl_vr_foregrip")
    panel:ControlHelp(L("Grip near a rifle's foregrip with the off hand to aim with both hands."))
    panel:CheckBox(L("Ammo on the gun"), "nl_vr_ammo_counter")
    panel:ControlHelp(L("Show the clip and reserve ammo beside the weapon hand."))
    slider(N("Gun angle (degrees)"), "nl_vr_gun_angle", -45, 45, 0)
    panel:ControlHelp(L("Adjust the gun's pitch in your hand."))
    local bindings = panel:Button(L("SteamVR controller bindings")) bindings.DoClick = VR.OpenBindings
    panel:ControlHelp(L("Start VR before opening SteamVR's binding editor. The off hand's B opens the wrist menu; point with the main hand and click with its trigger. Its stick scrolls."))
end

local function number(value, format)
    return finite(value) and string.format(format or "%.1f", value) or "?"
end
local function yesno(value)
    if value == nil then return L("Not checked") end
    return value and L("Yes") or L("No")
end
local function size(w, h) return number(w, "%.0f") .. " x " .. number(h, "%.0f") end
local STEPS = {full = N("Full"), high = N("High"), balanced = N("Balanced"), fast = N("Fast"),
    faster = N("Faster"), low = N("Low"), floor = N("Floor")}
local REASONS = {gpu = N("chosen for this GPU"), hand = N("set by hand"), auto = N("back to Auto"),
    down = N("frames were missed"), up = N("frames have headroom")}
local function status_lines()
    local info, probe = VR.info, VR.probe
    local text = {L(STATES[VR.state] or STATES.failed)}
    if VR.reason then text[#text + 1] = L(ERRORS[VR.reason] or ERRORS.native) end
    if VR.detail ~= "" then text[#text + 1] = VR.detail end -- native error name/extension: keep exact
    local ui = NLVR and NLVR.Debug and NLVR.Debug.ui
    local calibration = NLVR and NLVR.Move and NLVR.Move.calibration
    if calibration and calibration.restart then
        text[#text + 1] = L("Height calibrated. Exit VR, then Start VR to use the new world scale.")
    end
    if ui and ui.keyboard == "unavailable" then text[#text + 1] = L("Enter text") .. ": " .. tostring(ui.keyboard_detail or "?") end
    text[#text + 1] = string.format(L("SteamVR installed: %s; running: %s"),
        yesno(VR.state == "running" or probe.steamvr_installed), yesno(VR.state == "running" or probe.steamvr_running))
    if VR.state == "running" then
        text[#text + 1] = string.format(L("Headset: %s; %s Hz; recommended per eye: %s"),
            tostring(info.model or "?"), number(info.refresh), size(info.eye_width, info.eye_height))
        local cap = GetConVar("fps_max")
        cap = cap and cap:GetFloat()
        if finite(cap) and cap > 0 and finite(info.refresh) and cap < info.refresh then
            text[#text + 1] = string.format(L("fps_max is %s, below the headset's %s Hz. Type fps_max %s in the game console."),
                number(cap, "%g"), number(info.refresh, "%g"), number(info.refresh, "%g"))
        end
        -- Device activity and compositor field names are to be confirmed with VR-D at integration.
        local devices = type(info.devices) == "table" and info.devices or {}
        text[#text + 1] = string.format(L("Controllers tracked: left %s; right %s"), yesno(devices.left), yesno(devices.right))
        local perf = NLVR and NLVR.Debug and NLVR.Debug.perf
        if perf and perf.step_name then
            text[#text + 1] = string.format(L("Quality: %s, %s"), L(STEPS[perf.step_name] or perf.step_name),
                L(REASONS[perf.reason] or REASONS.gpu))
            text[#text + 1] = string.format(L("Frame rate: %s of %s per second; GPU: %s of %s ms"),
                number(perf.rate), number(perf.target_rate), number(perf.gpu_ms), number(perf.budget_ms))
            if perf.error then text[#text + 1] = L("The runtime refused a quality step.") .. " " .. tostring(perf.error) end
            if perf.cpu_limited then
                text[#text + 1] = L("Frames are being missed while the GPU has room. A lower step would not help, so the step stays.")
            end
            text[#text + 1] = string.format(L("Stereo: %s"), info.stereoActive == 1 and L("each eye path traced") or
                L("one picture turned into both eyes"))
            if perf.stereo and info.stereoActive ~= 1 and (perf.changes or 0) > 0 then
                text[#text + 1] = L("True stereo needs DLSS Ray Reconstruction and the physical sky, so one picture is turned into both eyes.")
            end
        end
        text[#text + 1] = string.format(L("Compositor: GPU %s ms; CPU %s ms"), number(info.compositor_gpu_ms), number(info.compositor_cpu_ms))
        local presents = info.presents
        local function percent(value)
            return finite(presents) and presents > 0 and finite(value) and number(100 * value / presents) or "?"
        end
        text[#text + 1] = string.format(L("Reprojected: %s%%; dropped: %s%% (cumulative)"), percent(info.reprojected), percent(info.dropped))
        text[#text + 1] = string.format(L("Runtime GPU (ms): total %s; trace %s; upscale %s; warp %s; other %s"),
            number(info.gpuMsTotal), number(info.gpuMsPathTrace), number(info.gpuMsUpscale), number(info.gpuMsWarp), number(info.gpuMsOther))
        text[#text + 1] = string.format(L("Centre: %s; traced: %s; submitted per eye: %s"),
            size(info.centreWidth, info.centreHeight), size(info.renderWidth, info.renderHeight), size(info.eyeWidth, info.eyeHeight))
        text[#text + 1] = string.format(L("Frames submitted: %s; submit errors: %s; poses matched / unmatched: %s / %s"),
            number(info.framesSubmitted, "%.0f"), number(info.submitErrors, "%.0f"), number(info.posesMatched, "%.0f"), number(info.posesUnmatched, "%.0f"))
    end
    return table.concat(text, "\n\n")
end
VR.StatusText = status_lines
local function build(panel)
    i18n.PreparePanel(panel)
    local start = panel:Button(L("Start VR"))
    start.DoClick = function() VR.Start() end
    local stop = panel:Button(L("Exit VR"))
    stop.DoClick = function() VR.Stop() end
    local recenter = panel:Button(L("Recentre VR"))
    recenter.DoClick = function() VR.Recenter() end
    local check = panel:Button(L("Check status"))
    check.DoClick = function() VR.CheckStatus() end
    panel:Help(L("Checking status loads only the VR module. SteamVR starts when you press Start VR; this may take several seconds."))
    local status = panel:Help(status_lines())
    local warning = panel:Help("")
    panel:Help(L("Auto quality is on unless you choose a step under Quality. For RTX, 80 or 90 Hz is recommended."))
    -- GUI Scaler enlarges fonts after this builder; Source's slider label stays 114 pixels wide.
    -- Always use a full-width title, including short English labels that only overflow at 4K.
    panel:Help(L("World scale"))
    panel:NumSlider("", "nl_vr_scale", 10, 100, 2)
    panel:ControlHelp(L("Game units per metre. Default 40 fits a 72-unit model to a 1.8 m person. Restart VR after changing."))
    panel:Help(L("Render scale"))
    panel:NumSlider("", "nl_vr_render_scale", 0.25, 1.5, 2)
    panel:ControlHelp(L("The highest render scale VR may use, on SteamVR's recommended eye size. Auto may choose a lower one. Changes take effect at once."))
    panel:Help(L("Culling FOV"))
    panel:NumSlider("", "nl_vr_fov", 100, 170, 0)
    panel:ControlHelp(L("Engine visibility setting, default 145 degrees, tested on the Index at 16:9. The headset supplies the rendered projection."))
    panel:Help(L("Use nl_vr_start and nl_vr_exit in the console. VR works in single-player games only."))
    VR.BuildOptions(panel)
    local nextUpdate = 0
    -- This belongs to the visible page, not a global frame hook or an idle timer.
    status.Think = function(self)
        if RealTime() < nextUpdate then return end
        -- IsVisible checks only this panel's flag. Hidden spawn-menu ancestors must stop status IO too.
        local owner = panel
        while IsValid(owner) do
            if not owner:IsVisible() then return end
            owner = owner:GetParent()
        end
        nextUpdate = RealTime() + 0.5
        self:SetText(status_lines())
        self:SizeToContents()
        warning:SetText(VR.GPUWarning(loader_status()) and L("VR may be slow on this GPU: less than 12 GB VRAM or a low performance tier. You can still start VR; Auto starts at its lowest step.") or "")
        warning:SizeToContents()
        start:SetEnabled(VR.state == "off" or VR.state == "failed")
        stop:SetEnabled(VR.state ~= "off")
    end
end
hook.Add("PopulateToolMenu", "nativeloader_vr", function()
    spawnmenu.AddToolMenuOption("RTX Remix", "VR", "NativeLoaderVR", L("VR settings"), "", "", build)
end)
