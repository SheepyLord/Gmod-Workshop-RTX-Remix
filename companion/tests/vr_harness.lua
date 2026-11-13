local root, scenario, library = ...
local function eq(actual, expected, why)
    assert(actual == expected, (why or "") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function close(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
SERVER, CLIENT = false, true
math.Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
local clock, requires, includes, repaints, attached, overlayDestroyed, stopCalls = 0, 0, {}, 0, nil, 0, 0
local painted, rtDepth, camDepth = {}, 0, 0
local cv, callbacks = {}, {}
cvars = {AddChangeCallback = function(name, fn, id) callbacks[name] = callbacks[name] or {} callbacks[name][id] = fn end,
    RemoveChangeCallback = function(name, id) if callbacks[name] then callbacks[name][id] = nil end end}
function CreateClientConVar(name, value)
    if not cv[name] then
        local value = tostring(value)
        cv[name] = {GetString = function() return value end, GetFloat = function() return tonumber(value) or 0 end,
            SetString = function(self, v)
                assert(not self.engine, "ConVar:SetString cannot write an engine convar")
                local old = value value = tostring(v)
                for _, fn in pairs(callbacks[name] or {}) do fn(name, old, value) end
            end,
            _engineValue = function(v) value = tostring(v) end}
    end
    return cv[name]
end
GetConVar = function(name) return cv[name] end
for name, value in pairs({fps_max = "60.000", cl_drawhud = "1", r_drawviewmodel = "1", rtx_pseudoplayer = "1"}) do
    CreateClientConVar(name, value)
    cv[name].engine = name ~= "rtx_pseudoplayer" -- the proxy switch is Lua-created; only the three engine vars reject setters
end
local vec = {}
vec.__index = vec
vec.__mul = function(a, n) return Vector(a.x * n, a.y * n, a.z * n) end
vec.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vec.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vec.__div = function(a, n) return Vector(a.x / n, a.y / n, a.z / n) end
vec.__unm = function(a) return a * -1 end
function vec:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function vec:Length() return math.sqrt(self:Dot(self)) end
function vec:DistToSqr(b) return (self - b):Dot(self - b) end
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vec) end
function Angle(p, y, r) return {p = p or 0, y = y or 0, r = r or 0} end
function LocalToWorld(pos, ang, origin, rotation)
    local s, c = math.sin(math.rad(rotation.y)), math.cos(math.rad(rotation.y))
    return origin + Vector(c * pos.x - s * pos.y, s * pos.x + c * pos.y, pos.z),
        Angle(ang.p, ang.y + rotation.y, ang.r)
end
function WorldToLocal(pos, ang, origin, rotation)
    local p, a = LocalToWorld(pos - origin, ang, Vector(), Angle(0, -rotation.y, 0))
    return p, a
end
table.RemoveByValue = function(t, value) for i = #t, 1, -1 do if t[i] == value then table.remove(t, i) end end end
CurTime = function() return clock end
engine = {TickCount = function() return math.floor(clock * 66) end}
net = {Receivers = {}, Start = function() end, WriteUInt = function() end, WriteFloat = function() end,
    WriteBool = function() end, SendToServer = function() end}
net.Receive = function(name, fn) net.Receivers[name] = fn end
local standins = assert(loadfile(root .. "/companion/tests/vr_stubs.lua"))()
standins.Math()
local weapon = {valid = true, clip = 12, ammo = 1}
function weapon:Clip1() return self.clip end
function weapon:GetPrimaryAmmoType() return self.ammo end
local player = {valid = true, health = 100, armour = 25, reserve = 45, yaw = 90,
    feet = Vector(100, 200, 10), offset = Vector(0, 0, 64), host = true, weapon = weapon}
function player:IsListenServerHost() return self.host end
function player:EyeAngles() return Angle(0, self.yaw, 0) end
function player:GetPos() return self.feet end
function player:GetVelocity() return self.velocity or Vector() end
function player:GetMoveType() return 2 end
function player:WaterLevel() return 0 end
function player:GetCurrentViewOffset() return self.offset end
function player:Health() return self.health end
function player:Armor() return self.armour end
function player:GetActiveWeapon() return self.weapon end
function player:GetAmmoCount() return self.reserve end
function player:IsPlayer() return true end
function player:EyePos() return self.feet + self.offset end
LocalPlayer = function() return player end
IsValid = function(object) return type(object) == "table" and object.valid ~= false end
local singlePlayer = true
game = {SinglePlayer = function() return singlePlayer end}
RealTime = function() return clock end
local logged = {}
MsgN = function(text) logged[#logged + 1] = tostring(text) end
local status = {schema = 1, activation = {performance_tier = {tier = "high", dedicated_vram_mib = 32768}}}
local exists = {}
exists["lua/bin/gmcl_nlvr_win64.dll"] = scenario ~= "missing_module"
local statusReads = 0
file = {Read = function() statusReads = statusReads + 1 return "status" end, Exists = function(path) return exists[path] == true end}
util = {JSONToTable = function() return status end}
local hooks, timers, commands = {}, {}, {}
hook = assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New(library or "stock",hooks)
if library=="ulib" then assert(type(hook.GetULibTable)=="function","core suite did not install ULib mode") end
local originalCall, originalRun = hook.Call, hook.Run
timer = {Create = function(id, delay, count, fn) timers[id] = fn end, Remove = function(id) timers[id] = nil end}
concommand = {Add = function(id, fn) commands[id] = fn end}
local builder
spawnmenu = {AddToolMenuOption = function(tab, category, id, label, command, config, build)
    eq(tab, "RTX Remix") eq(category, "VR") builder = build
end}
local i18n = {L = function(text) return text end, N = function(text) return text end, PreparePanel = function() end}
NATIVELOADER_I18N = i18n
local page = root .. "/companion/nativeloader/lua/autorun/client/nativeloader_vr.lua"
local addon = root .. "/vr/addon/lua/nlvr/client.lua"
local moduleState, detail, startOptions = "off", "", nil
qualitySteps = {}
local probe = {runtime_api = 4, steamvr_installed = true, steamvr_running = false, openvr_dll = "openvr_api.dll"}
local info = {model = "Valve Index", refresh = 90, eye_width = 2016, eye_height = 2240, overlayUpdates = 1,
    devices = {left = true, right = false}, compositor_gpu_ms = 11.25, compositor_cpu_ms = 1.5,
    presents = 200, reprojected = 80, dropped = 2, gpuMsTotal = 12.3, gpuMsPathTrace = 10,
    gpuMsUpscale = 1.3, gpuMsWarp = 0.5, gpuMsOther = 0.5, centreWidth = 2200, centreHeight = 2240,
    renderWidth = 1100, renderHeight = 1120, eyeWidth = 2016, eyeHeight = 2240,
    framesSubmitted = 123, submitErrors = 0, posesMatched = 120, posesUnmatched = 3}
local poses = {sequence = 1, hmd = {valid = true, pos = Vector(1, 2, 1.6), ang = Angle(10, 0, 5)}}
function FrameNumber() return poses and poses.sequence or 0 end
local events, cameras, frameCalls = {}, {}, 0
local api = {
    Version = function() return 1 end, Probe = function() return probe end,
    Start = function(options) startOptions = options moduleState = "starting" return true end,
    State = function() return moduleState, detail end,
    Stop = function() stopCalls = stopCalls + 1 moduleState = "off" end,
    Info = function() return info end, Events = function() local copy = events events = {} return copy end,
    BeginFrame = function() frameCalls = frameCalls + 1 return poses end,
    SetFrameCamera = function(sequence, origin, angles) cameras[#cameras + 1] = {sequence, origin, angles} end,
    OverlayCreate = function() return 19 end,
    OverlaySource = function(handle, w, h) eq(handle, 19) eq(w, 769) eq(h, 257) end,
    OverlayAttach = function(handle, device, pos, ang, width) attached = {handle, device, pos, ang, width} end,
    OverlayShow = function() end, OverlayDestroy = function() overlayDestroyed = overlayDestroyed + 1 end,
    SetQuality = function(step) qualitySteps[#qualitySteps + 1] = step return true end,
}
require = function(name)
    eq(name, "nlvr") requires = requires + 1
    if scenario == "require_error" then error("module dependency failed") end
    nlvr = api
end
function include(path)
    includes[path] = (includes[path] or 0) + 1
    if path == "nativeloader/i18n.lua" then return i18n end
    assert(path:match("^nlvr/"), path)
    if scenario == "missing_addon" and path == "nlvr/client.lua" then error("Could not include nlvr/client.lua") end
    return assert(loadfile(root .. "/vr/addon/lua/" .. path))()
end
RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, IMAGE_FORMAT_RGBA8888 = 8, 2, 0
TEXT_ALIGN_CENTER, color_white = 1, {255, 255, 255}
function Color(...) return {...} end
GetRenderTargetEx = function(name, w, h, mode, depth, flags, rtFlags, format)
    eq(mode, 8) eq(depth, 2) eq(flags, 0) eq(rtFlags, 0) eq(format, 0)
    if scenario == "guard_refused" then w, h = 1, 1 end
    return {Width = function() return w end, Height = function() return h end}
end
surface = {CreateFont = function() end, SetDrawColor = function() end, DrawRect = function() end}
render = {PushRenderTarget = function() rtDepth = rtDepth + 1 end,
    PopRenderTarget = function() rtDepth = rtDepth - 1 end,
    Clear = function() repaints = repaints + 1 end}
cam = {Start2D = function() camDepth = camDepth + 1 end, End2D = function() camDepth = camDepth - 1 end}
draw = {SimpleText = function(text) painted[#painted + 1] = text end}
local function poll()
    clock = clock + 0.11
    local fn = hooks.PreRender and hooks.PreRender.nativeloader_vr_session
    assert(fn, "session timer missing") fn()
end
local function running()
    local before = includes["nlvr/client.lua"]
    assert(NativeLoaderVR.Start()) eq(NativeLoaderVR.state, "starting")
    eq(includes["nlvr/client.lua"], before, "no add-on while starting")
    moduleState = "running" poll()
end
local function clean()
    eq(timers.nativeloader_vr_session, nil, "no off timer")
    eq(hooks.PreRender and hooks.PreRender.nativeloader_vr_session, nil, "no off poll hook")
    eq(hook.Call, originalCall, "dispatch restored") eq(hook.Run, originalRun)
    for _, event in ipairs({"PreRender", "CalcView", "PostRender", "OnEntityCreated", "PreDrawViewModel", "PreDrawPlayerHands", "ShouldDrawLocalPlayer"}) do
        eq(hooks[event] and hooks[event]["nlvr.core"], nil, "session hook " .. event)
    end
    for event, entries in pairs(hooks) do for id in pairs(entries) do assert(not tostring(id):match("^nlvr%."), event .. ":" .. id) end end
    for name, entries in pairs(callbacks) do eq(next(entries), nil, "callback removed " .. name) end
    eq(net.Receivers.nlvr, nil) eq(NLVR, nil)
    eq(hooks.ShutDown and hooks.ShutDown.nativeloader_vr_session, nil)
    eq(cv.fps_max:GetString(), "60.000", "fps exact restore")
    eq(cv.cl_drawhud:GetString(), "1") eq(cv.r_drawviewmodel:GetString(), "1") eq(cv.rtx_pseudoplayer:GetString(), "1")
end
assert(loadfile(page))()
local VR = NativeLoaderVR
local cases = {}
function cases.options_no_format_write()
    CreateClientConVar("nl_vr_vignette","0.6")
    local sliders={}
    local panel={Help=function() end,ControlHelp=function() end,CheckBox=function() end,
        ComboBox=function() return {AddChoice=function() end} end,Button=function() return {} end}
    function panel:NumSlider(_,name)
        local function part() return {ConVarChanged=function(_,v) if cv[name] then cv[name]:SetString(v) end end} end
        local slider={Scratch=part(),TextArea=part()};sliders[name]=slider return slider
    end
    NativeLoaderVR.BuildOptions(panel)
    local slider=sliders.nl_vr_vignette
    slider.Scratch:ConVarChanged("0.60") slider.TextArea:ConVarChanged("0.60")
    eq(cv.nl_vr_vignette:GetString(),"0.6","opening settings must not rewrite numeric formatting")
    slider.Scratch:ConVarChanged("0.75")
    eq(cv.nl_vr_vignette:GetString(),"0.75","a real numeric edit still writes")
end
function cases.idle()
    eq(requires, 0) eq(includes["nlvr/client.lua"], nil) clean()
    for event in pairs(hooks) do eq(event, "PopulateToolMenu", "only menu hook before Start") end
    hook.Run("PopulateToolMenu")
    local controls = {}
    local sliders = 0
    local shown = false
    local parent = {visible = false, IsVisible = function(self) return self.visible end, GetParent = function() return nil end}
    local panel = {IsVisible = function() return shown end, GetParent = function() return parent end,
        NumSlider = function(_, text) eq(text, "", "no fixed-width slider labels at 4K") sliders = sliders + 1 end,
        ControlHelp = function() end}
    local function control(_, text)
        local c = {text = text, SetText = function(self, value) self.text = value end,
            SizeToContents = function() end, SetEnabled = function() end}
        controls[#controls + 1] = c return c
    end
    panel.Button, panel.Help = control, control
    builder(panel)
    eq(sliders, 3)
    for _, c in ipairs(controls) do if c.Think then c:Think() end end
    eq(statusReads, 0)
    shown = true
    for _, c in ipairs(controls) do if c.Think then c:Think() end end
    eq(statusReads, 0, "a hidden spawn-menu ancestor prevents status IO")
    parent.visible = true
    for _, c in ipairs(controls) do if c.Think then c:Think() end end
    eq(statusReads, 1, "visible page refresh")
    parent.visible, clock = false, 1
    for _, c in ipairs(controls) do if c.Think then c:Think() end end
    eq(statusReads, 1, "closing the spawn menu stops status IO")
    eq(requires, 0, "opening page does not require module") clean()
end
function cases.probe()
    assert(VR.CheckStatus()) eq(requires, 1) eq(moduleState, "off") clean()
    eq(VR.probe.steamvr_installed, true)
end
function cases.missing_module()
    eq(VR.Start(), false) eq(VR.reason, "module") clean()
    eq(requires, 0, "no fallback include/script error when binary is absent")
    assert(VR.StatusText():find("Reinstall the RTX package", 1, true))
end
function cases.require_error() eq(VR.Start(), false) eq(VR.reason, "module") clean() end
function cases.version()
    api.Version = function() return 2 end
    eq(VR.Start(), false) eq(VR.reason, "version") clean()
end
function cases.runtime()
    probe.runtime_api = nil eq(VR.Start(), false) eq(VR.reason, "runtime") clean()
end
function cases.missing_steamvr()
    probe.steamvr_installed = false
    eq(VR.Start(), false) eq(VR.reason, "steamvr") eq(startOptions, nil)
    assert(VR.StatusText():find("Install SteamVR in Steam", 1, true)) clean()
end
function cases.remote()
    singlePlayer, player.host = false, false
    eq(VR.Start(), false) eq(VR.reason, "server") eq(requires, 0) clean()
end
function cases.host()
    -- VR is single-player only (ADR 0197): the listen-server host is refused like any other server.
    singlePlayer, player.host = false, true
    eq(VR.Start(), false) eq(VR.reason, "server") eq(requires, 0) clean()
end
function cases.vrmod()
    g_VR = {active = true} eq(VR.Start(), false) eq(VR.reason, "vrmod") eq(requires, 0) clean()
end
function cases.gvrmod()
    g_VR = {active = true} exists["vrmod/core/cl_vrmod.lua"], exists["vrmod/ui/cl_panel2vr.lua"] = true, true
    eq(VR.Start(), false) eq(VR.reason, "gvrmod") eq(requires, 0) clean()
end
function cases.inactive_vrmod() g_VR = {active = false} running() VR.Stop() clean() end
function cases.api_vrmod()
    vrmod = {IsPlayerInVR = function() return true end} eq(VR.Start(), false) eq(VR.reason, "vrmod") clean()
end
function cases.start_exit()
    running() eq(cv.fps_max:GetString(), "60.000") eq(cv.cl_drawhud:GetString(), "1")
    eq(includes["nlvr/client.lua"], 1) eq(VR.Start(), false)
    eq(attached[2], "left") close(attached[3].z, 0.065) close(attached[5], 0.23)
    VR.Stop() eq(overlayDestroyed, 1) clean()
    VR.Stop() clean() -- idempotent
    running() VR.Stop() clean() eq(overlayDestroyed, 2)
end
function cases.start_cancel() assert(VR.Start()) commands.nl_vr_exit() clean() eq(includes["nlvr/client.lua"], nil) end
function cases.sdk_ready()
    assert(VR.Start()) eq(includes["nlvr/client.lua"], nil)
    info.sdk_ready = true
    poll() eq(VR.state, "starting") eq(includes["nlvr/client.lua"], 1)
    local view = hook.Run("CalcView", player, player.feet + player.offset, Angle(0, 90, 0), 90, 2, 8000)
    assert(view) eq(#cameras, 1, "first pose can bootstrap the starting renderer")
    moduleState = "running" poll() eq(includes["nlvr/client.lua"], 1)
    VR.Stop() clean()
end
function cases.async_stop()
    running()
    api.Stop = function() moduleState = "stopping" end
    VR.Stop() eq(VR.state, "stopping") eq(VR.Start(), false)
    assert(hooks.PreRender.nativeloader_vr_session, "wait for actual SDK unload acknowledgement")
    moduleState = "off" poll() eq(VR.state, "off") clean()
end
function cases.cap_warning()
    running()
    assert(VR.StatusText():find("Type fps_max 90 in the game console.", 1, true))
    eq(cv.fps_max:GetString(), "60.000", "warning never bypasses blocked commands")
    VR.Stop() clean()
end
function cases.native_return_error()
    running()
    api.SetFrameCamera = function() return nil, "rejected camera" end
    hook.Run("CalcView", player, player.feet + player.offset, Angle(0, 90, 0), 90, 2, 8000)
    eq(VR.state, "running", "one failed camera retains the session")
    VR.Stop() clean()
end
function cases.failure()
    assert(VR.Start()) moduleState, detail = "failed", "VRInitError_Init_HmdNotFound" poll()
    eq(VR.state, "failed") assert(VR.detail:find("HmdNotFound", 1, true)) clean()
end
function cases.failure_running()
    running() moduleState, detail = "failed", "Runtime stopped" poll()
    eq(VR.state, "failed") clean()
end
function cases.start_error()
    api.Start = function() error("worker failed") end
    eq(VR.Start(), false) eq(VR.state, "failed") clean()
end
function cases.missing_addon()
    running() eq(VR.reason, "addon") eq(VR.state, "failed") clean()
end
function cases.guard_refused() running() eq(VR.reason, "addon") clean() end
function cases.overlay_error()
    api.OverlayCreate = function() return nil end running() eq(VR.reason, "addon") clean()
end
function cases.quit() running() events = {{type = "quit"}} poll() eq(VR.reason, "quit") eq(VR.state, "off") clean() end
function cases.off() running() moduleState = "off" poll() eq(VR.reason, "quit") clean() end
function cases.shutdown() running() hook.Run("ShutDown") clean() end
function cases.shutdown_starting() assert(VR.Start()) hook.Run("ShutDown") clean() end
function cases.hot_reload() running() assert(loadfile(page))() clean() end
function cases.frame_error()
    running() api.BeginFrame = function() error("tracking lost connection") end
    hook.Run("PreRender") eq(VR.reason, "addon") clean()
end
function cases.paint_error()
    running() draw.SimpleText = function() error("font draw failed") end
    hook.Run("PostRender") eq(rtDepth, 0) eq(camDepth, 0) eq(VR.reason, "addon") clean()
end
function cases.tracking()
    running() hook.Run("PreRender")
    local view = hook.Run("CalcView", player, player.feet + player.offset, Angle(0,90,0), 90, 2, 8000)
    close(view.origin.x, 20) close(view.origin.y, 240) close(view.origin.z, 74)
    close(view.angles.p, 10) close(view.angles.y, 90) close(view.angles.r, 5)
    eq(view.fov, 145) eq(view.znear, 2) eq(view.zfar, 8000) eq(view.drawviewer, false)
    eq(cameras[1][1], 1) eq(frameCalls, 1)
    player.feet = Vector(110, 220, 15)
    poses = {sequence = 2, hmd = {valid = false}}
    hook.Run("PreRender") view = hook.Run("CalcView", player, player.feet + player.offset, Angle(0,90,0), 90, 1, 9000)
    close(view.origin.x, 30) close(view.origin.z, 79) eq(cameras[2][1], 2)
    VR.Stop() clean()
end
function cases.no_tracking()
    poses.hmd.valid = false running() hook.Run("PreRender")
    eq(hook.Run("CalcView", player, Vector(), Angle(), 90, 1, 9000), nil) eq(#cameras, 0)
    poses = nil hook.Run("PreRender") VR.Stop() clean()
end
function cases.scale_latched()
    assert(VR.Start())
    eq(startOptions.scale, 40)
    cv.nl_vr_scale:SetString("70")
    moduleState = "running" poll() hook.Run("PreRender")
    local view = hook.Run("CalcView", player, player.feet + player.offset, Angle(0,90,0), 90, 1, 9000)
    close(view.origin.z, 74) -- uses 40, like the runtime, rather than the new setting 70
    cv.nl_vr_fov:SetString("nan")
    view = hook.Run("CalcView", player, player.feet + player.offset, Angle(0,90,0), 90, 1, 9000)
    assert(view.fov == view.fov)
    VR.Stop() clean() eq(cv.nl_vr_scale:GetString(), "70", "VR-owned setting may persist")
end
function cases.hud()
    local draws = 0
    for _, event in ipairs({"HUDPaint", "HUDPaintBackground", "PreDrawHUD", "PostDrawHUD", "DrawOverlay", "RenderScreenspaceEffects"}) do
        hook.Add(event, "third_party", function() draws = draws + 1 end)
    end
    running()
    for _, event in ipairs({"HUDPaint", "HUDPaintBackground", "PreDrawHUD", "PostDrawHUD", "DrawOverlay", "RenderScreenspaceEffects"}) do
        hook.Run(event) hook.Call(event, {[event] = function() draws = draws + 1 end})
    end
    eq(draws, 18) eq(hook.Run("HUDShouldDraw", "CHudHealth"), nil)
    eq(hook.Run("PreDrawViewModel"), true) eq(hook.Run("ShouldDrawLocalPlayer"), false)
    hook.Add("VGUIMousePressed", "desktop", function() return "desktop works" end)
    eq(hook.Run("VGUIMousePressed"), "desktop works")
    VR.Stop() clean() hook.Run("HUDPaint") eq(draws, 19)
end
function cases.notifications()
    local function panel(class, visible)
        return {ClassName = class, visible = visible, children = {}, GetChildren = function(self) return self.children end,
            IsVisible = function(self) return self.visible end, SetVisible = function(self, value) self.visible = value end}
    end
    local world = panel("World", true)
    local previous, hidden = panel("NoticePanel", true), panel("NoticePanel", false)
    local menu = panel("DFrame", true)
    world.children = {previous, hidden, menu}
    vgui = {GetWorldPanel = function() return world end, Create = function(class) return panel(class, true) end}
    local create = vgui.Create
    running() eq(vgui.Create, create) eq(previous.visible, true) eq(hidden.visible, false) eq(menu.visible, true)
    local fresh = vgui.Create("NoticePanel") eq(fresh.visible, true)
    local console = vgui.Create("DFrame") eq(console.visible, true)
    VR.Stop() clean() eq(vgui.Create, create) eq(previous.visible, true) eq(hidden.visible, false) eq(fresh.visible, true)
end
function cases.proxies()
    local function entity(class, hidden)
        return {hidden = hidden, children = {}, GetClass = function() return class end,
            GetTable = function(self) return self end, GetChildren = function(self) return self.children end,
            GetNoDraw = function(self) return self.hidden end, SetNoDraw = function(self, value) self.hidden = value end}
    end
    local body, gun, alreadyHidden, prop = entity("rtx_pseudoplayer", false), entity("rtx_pseudoweapon", false),
        entity("rtx_pseudoplayer", true), entity("prop_physics", false)
    local child = entity("class C_BaseFlex", false)
    gun.children = {child}
    local think = function() error("proxy must not draw its world weapon while VR runs") end
    gun.Think = think
    ents = {FindByClass = function(class)
        if class == "rtx_pseudoplayer" then return {body, alreadyHidden} end
        return {gun}
    end}
    running() eq(body.hidden, true) eq(gun.hidden, true) eq(alreadyHidden.hidden, true)
    eq(child.hidden, true) assert(gun.Think ~= think)
    eq(cv.rtx_pseudoplayer:GetString(), "1", "no pseudoplayer convar/shadow callback")
    local fresh = entity("rtx_pseudoweapon", false)
    hook.Run("OnEntityCreated", fresh) hook.Run("OnEntityCreated", prop) hook.Run("PreRender")
    eq(fresh.hidden, true) eq(prop.hidden, false)
    VR.Stop() clean() eq(body.hidden, false) eq(gun.hidden, false) eq(alreadyHidden.hidden, true) eq(fresh.hidden, false)
    eq(child.hidden, false) eq(gun.Think, think) eq(body.Think, nil)
    api.OverlayCreate = function() return nil end
    running() clean() eq(body.hidden, false) eq(gun.hidden, false) eq(alreadyHidden.hidden, true)
    eq(child.hidden, false) eq(gun.Think, think)
end
function cases.wrist()
    render.Clear = function(r, g, b, a, depth, stencil)
        eq(r, 12) eq(g, 18) eq(b, 26) eq(a, 235) eq(depth, false) eq(stencil, false)
        repaints = repaints + 1
    end
    running() hook.Run("PostRender") eq(repaints, 1)
    eq(table.concat(painted, "|"), "Health|100|Armour|25|Ammo|12 / 45")
    for _ = 1, 1000 do hook.Run("PostRender") end eq(repaints, 1)
    player.health = 90 hook.Run("PostRender") eq(repaints, 2)
    player.armour = 10 hook.Run("PostRender") eq(repaints, 3)
    weapon.clip = 11 hook.Run("PostRender") eq(repaints, 4)
    player.reserve = 44 hook.Run("PostRender") eq(repaints, 5)
    player.weapon = nil hook.Run("PostRender") eq(repaints, 6)
    eq(painted[#painted], "-") eq(rtDepth, 0) eq(camDepth, 0)
    VR.Stop() hook.Run("PostRender") eq(repaints, 6) clean()
end
function cases.gpu()
    eq(VR.GPUWarning({}), false)
    for _, pair in ipairs({{8192, true}, {12287, true}, {12288, false}, {32768, false}, {0, false}, {-1, false}, {0/0, false}, {math.huge, false}}) do
        eq(VR.GPUWarning({activation = {memory = {vram_mib = pair[1]}}}), pair[2])
    end
    eq(VR.GPUWarning({activation = {performance_tier = {dedicated_vram_mib = 0}, memory = {vram_mib = 8192}}}), true)
    status.activation.performance_tier = {tier = "low", dedicated_vram_mib = 32768}
    assert(VR.Start({timeline = "fixture.json", no_submit = true}))
    eq(startOptions.render_scale, 0.5) eq(startOptions.scale, 40)
    eq(startOptions.timeline, "fixture.json") eq(startOptions.no_submit, true) VR.Stop() clean()
end
function cases.metrics()
    running() local text = VR.StatusText()
    for _, needle in ipairs({"Valve Index", "90.0 Hz", "2016 x 2240", "40.0%", "1.0%", "11.3", "12.3", "123"}) do
        assert(text:find(needle, 1, true), "missing metric " .. needle)
    end
    info.presents = 0 poll() assert(VR.StatusText():find("Reprojected: ?%", 1, true)) VR.Stop() clean()
end
function cases.uncapped()
    cv.fps_max._engineValue("0") running() eq(cv.fps_max:GetString(), "0") VR.Stop() eq(cv.fps_max:GetString(), "0")
    cv.fps_max._engineValue("144") running() eq(cv.fps_max:GetString(), "144") VR.Stop() eq(cv.fps_max:GetString(), "144")
end
function cases.authoritative_view()
    local before, late = 0, 0
    hook.Add("CalcView", "competing", function() before=before+1 return {origin=Vector(9999,9999,9999)} end)
    hook.Add("CalcView", "removed_during_vr", function() end)
    local prior = hooks.CalcView
    running() hook.Run("PreRender")
    hook.Add("CalcView", "late", function() late=late+1 return {origin=Vector(8888,8888,8888)} end)
    hook.Remove("CalcView", "removed_during_vr")
    local view=hook.Call("CalcView", {CalcView=function() error("gamemode must not override the head") end},
        player, player.feet + player.offset, Angle(0,90,0), 90, 1, 9000)
    close(view.origin.x,20) eq(before,0) eq(late,0)
    local owned=hooks.CalcView
    VR.Stop() clean() eq(hooks.CalcView,prior) eq(hooks.CalcView.removed_during_vr,nil)
    assert(hooks.CalcView.competing and hooks.CalcView.late)
    owned.cached_after_exit=function() end
    assert(prior.cached_after_exit, "a cached temporary table must not raise after Stop")
end
function cases.predicted_origin()
    running() hook.Run("PreRender")
    local origin=player.feet + player.offset + Vector(7,8,9)
    local view=hook.Run("CalcView",player,origin,Angle(0,90,0),90,1,9000)
    close(view.origin.x,27) close(view.origin.y,248) close(view.origin.z,83)
    local repeated=hook.Run("CalcView",player,Vector(999,999,999),Angle(0,-90,0),90,2,500)
    eq(repeated,view) eq(#cameras,1,"only the first camera for this sequence is pushed")
    player.offset=Vector(0,0,28) poses.sequence=2 hook.Run("PreRender")
    view=hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    close(view.origin.z,74) eq(#cameras,2,"duck view offset removed once")
    VR.Stop() clean()
end
function cases.frame_once()
    local number=100
    FrameNumber=function() return number end
    running() hook.Run("PreRender") hook.Run("PreRender") eq(frameCalls,1)
    number=101 hook.Run("PreRender") eq(frameCalls,2)
    VR.Stop() clean()
end
function cases.calcview_before_prerender()
    running()
    local view=hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    close(view.origin.z,74) eq(frameCalls,1) eq(#cameras,1)
    hook.Run("PreRender") eq(frameCalls,1,"PreRender shares the pose sampled for CalcView")
    poses.sequence=2
    view=hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    hook.Run("PreRender") eq(frameCalls,2) eq(#cameras,2)
    VR.Stop() clean()
end

function cases.review_nil_camera()
    local n=1 FrameNumber=function() return n end
    running()
    local first=hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    api.BeginFrame=function() return nil end n=2
    local held=hook.Run("CalcView",player,Vector(999,999,999),Angle(20,-90,0),90,1,9000)
    eq(held,first) eq(#cameras,1,"no unposed flat camera or duplicate push")
    VR.Stop() clean()
end
function cases.review2_busy_camera()
    local n=1 FrameNumber=function() return n end running()
    local first=hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    local push=api.SetFrameCamera
    api.SetFrameCamera=function() return nil,"nlvr is busy starting or stopping" end
    poses.sequence=2 n=2
    eq(hook.Run("CalcView",player,Vector(999,999,999),Angle(0,90,0),90,1,9000),first)
    for i=1,40 do hook.Run("CalcView",player,Vector(999,999,999),Angle(0,90,0),90,1,9000) end
    eq(VR.state,"running","one busy result must preserve the session")
    api.SetFrameCamera=push poses.sequence=3 n=3
    assert(hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)~=first)
    api.SetFrameCamera=function() return nil,"camera fault" end
    for i=4,33 do poses.sequence=i n=i hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000) end
    eq(VR.state,"failed") clean()
end
function cases.review2_overlay_ack()
    info.overlayUpdates=0 running()
    for i=1,5 do hook.Run("PostRender") end
    eq(repaints,5,"repaint an unchanged HUD until its texture reaches the runtime")
    info.overlayUpdates=1
    for i=1,5 do hook.Run("PostRender") end
    eq(repaints,5,"stop repainting after the runtime acknowledgement")
    api.Info=function() error("acknowledged wrist must not poll native Info every frame") end
    hook.Run("PostRender")
    VR.Stop() clean()
end
function cases.review2_overlay_info_error()
    info.overlayUpdates=0 running()
    api.Info=function() return nil,"wrist Info failed" end
    for i=1,30 do hook.Run("PostRender") end
    eq(VR.state,"failed") assert(VR.detail:find("wrist Info failed",1,true)) clean()
    local count=0 for _,text in ipairs(logged) do if text:find("VR wrist: wrist Info failed",1,true) then count=count+1 end end
    eq(count,1,"log the changed Info error once")
end
function cases.review_return_failures()
    local n=1 FrameNumber=function() return n end running()
    hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    api.BeginFrame=function() return nil,"compositor failure" end
    for i=2,31 do n=i hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000) end
    eq(VR.state,"failed") assert(VR.detail:find("compositor failure",1,true)) clean()
    local count=0 for _, text in ipairs(logged) do if text:find("VR frame: compositor failure",1,true) then count=count+1 end end
    eq(count,1,"log a stable frame error only when it changes")
end
function cases.review_paused_poll()
    running() events={{type="quit"}}
    clock=clock+1
    hook.Run("PreRender") -- no timer tick or simulation-time advance
    eq(VR.state,"off") clean()
end
function cases.review_native_stopping()
    running()
    moduleState="stopping" detail="native quit"
    poll()
    moduleState="off"
    if VR.state=="stopping" then poll() end
    eq(VR.state,"off") clean()
end
function cases.review_page_nil()
    for _, name in ipairs({"State", "Info", "Events"}) do
        running()
        local original=api[name]
        api[name]=function() return nil,"lost " .. name end
        for i=1,10 do poll() end
        assert(VR.detail:find("lost " .. name,1,true))
        api[name]=original
        if VR.state=="stopping" then poll() end -- off must still be acknowledged
        eq(VR.state,"failed") clean()
    end
end
function cases.review_overlay_nil()
    api.OverlaySource=function() return nil,"overlay refused" end
    running() eq(VR.state,"failed") assert(VR.detail:find("overlay refused",1,true)) clean()
end
function cases.review_recenter()
    running() hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    VR.Recenter() poses.sequence=2 poses.hmd.pos=Vector(2,3,1.6) poses.hmd.ang=Angle(0,20,0)
    local view=hook.Run("CalcView",player,player.feet+player.offset,Angle(0,90,0),90,1,9000)
    close(view.origin.x,100) close(view.origin.y,200) close(view.origin.z,74) close(view.angles.y,90)
    VR.Stop() clean()
end
if scenario:match("^f_") then
    assert(loadfile(root .. "/companion/tests/vr_framework_cases.lua"))()({root = root, scenario = scenario,
        root = root, eq = eq, close = close, api = api, player = player, cv = cv, callbacks = callbacks, hooks = hooks,
        timers = timers, standins = standins, running = running, clean = clean, logged = logged,
        time = function(value) clock = value end,
        step = function() poses.sequence = poses.sequence + 1 clock = clock + 0.02 end,
        poses = poses, settings = function() return callbacks end})
else assert(cases[scenario], "Unknown scenario " .. tostring(scenario))() end
print("PASS " .. scenario)
