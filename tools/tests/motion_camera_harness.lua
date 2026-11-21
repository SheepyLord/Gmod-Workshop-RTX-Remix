-- The character motion importer's camera (cl_camera.lua) under a fake GMod API, no game: "Hide yourself
-- during camera motion" (ADR 0250). Each frame runs as GMod runs it: Think, CalcView, PreRender (the RTX
-- fixes' flashlight asks RTXFlashlightHidden there), RenderScene, the scene, PostRender.
--   luajit motion_camera_harness.lua <scenario> <cl_camera.lua>
-- Scenarios: play, untick, subject, ends, skipped, parts. Prints PASS <scenario>.
local scenario, path = arg[1], arg[2]
assert(scenario and path, "usage: motion_camera_harness.lua <scenario> <cl_camera.lua>")

local function fail(message) error(message, 2) end
local function check(condition, message) if not condition then fail(message) end end

CLIENT, SERVER = true, false
local now = 100
function SysTime() return now end
function CurTime() return now end
function RealTime() return now end
function FrameTime() return 1 / 60 end
function ScrW() return 1600 end
function ScrH() return 900 end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function IsValid(v) return type(v) == "table" and v.valid ~= false and v.IsValid ~= false end
function math.Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
NOTIFY_HINT, MOUSE_FIRST = 3, 107
input = { IsKeyDown = function() return false end, IsMouseDown = function() return false end }
gui = { IsGameUIVisible = function() return false end }
vgui = { CursorVisible = function() return false end, GetKeyboardFocus = function() return nil end }
notification = { AddLegacy = function() end }

-- Vectors and angles: enough for the camera's path, collision and transform.
local VectorMeta = {}
VectorMeta.__index = VectorMeta
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VectorMeta) end
function isvector(v) return getmetatable(v) == VectorMeta end
VectorMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VectorMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VectorMeta.__mul = function(a, s)
    if type(a) == "number" then a, s = s, a end
    return Vector(a.x * s, a.y * s, a.z * s)
end
VectorMeta.__div = function(a, s) return Vector(a.x / s, a.y / s, a.z / s) end
function VectorMeta:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function VectorMeta:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
function VectorMeta:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function VectorMeta:GetNormalized() local l = math.max(self:Length(), 1e-9) return self / l end
function VectorMeta:Rotate() end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
-- The camera's local key placed at the anchor (the rotation does not matter here).
function LocalToWorld(lpos, lang, pos) return pos + lpos, lang end
util = {
    TraceHull = function() return { Hit = false, StartSolid = false } end,
    TraceLine = function() return { Hit = false, StartSolid = false } end,
}

-- Convars by name.
local convars = {}
function CreateClientConVar(name, default)
    local cv = { value = tostring(default) }
    function cv:GetBool() local v = self.value return v ~= "0" and v ~= "" and v ~= "false" end
    function cv:GetFloat() return tonumber(self.value) or 0 end
    function cv:GetString() return self.value end
    convars[name] = cv
    return cv
end
function GetConVar(name) return convars[name] end
function RunConsoleCommand(name, value) if convars[name] then convars[name].value = tostring(value) end end
concommand = { Add = function() end }

-- Hooks in the order they were added; Run returns the first answer, as GMod's hook.Call does.
local hooks = {}
hook = {
    Add = function(event, name, fn)
        hooks[event] = hooks[event] or {}
        for _, entry in ipairs(hooks[event]) do
            if entry.name == name then entry.fn = fn return end
        end
        table.insert(hooks[event], { name = name, fn = fn })
    end,
    Run = function(event, ...)
        for _, entry in ipairs(hooks[event] or {}) do
            local a, b, c = entry.fn(...)
            if a ~= nil then return a, b, c end
        end
    end,
}
local function answers(event, ...)
    local out = {}
    for _, entry in ipairs(hooks[event] or {}) do out[#out + 1] = { entry.name, entry.fn(...) } end
    return out
end

-- Entities: a no-draw flag, children, a class, an index.
local byIndex, all = {}, {}
local function entity(class, index, pos)
    local e = { valid = true, class = class, index = index or -1, noDraw = false, children = {}, pos = pos or Vector(0, 0, 0) }
    function e:GetNoDraw() return self.noDraw end
    function e:SetNoDraw(value) self.noDraw = value == true end
    function e:GetChildren() return self.children end
    function e:GetClass() return self.class end
    function e:EntIndex() return self.index end
    function e:GetPos() return self.pos end
    function e:GetAngles() return Angle(0, 0, 0) end
    function e:WorldSpaceCenter() return self.pos + Vector(0, 0, 40) end
    function e:LookupBone() return nil end
    if index and index > 0 then byIndex[index] = e end
    all[#all + 1] = e
    return e
end
local function parent(child, owner) table.insert(owner.children, child) end
function Entity(index) return byIndex[index] or { valid = false } end
ents = { FindByClass = function(class)
    local out = {}
    for _, e in ipairs(all) do if e.class == class and IsValid(e) then out[#out + 1] = e end end
    return out
end }

-- The scene: you with a tool gun (parented, as carried weapons are), a worn model and a holstered
-- weapon the server keeps hidden; the RTX fixes' body and weapon copies (the weapon copy is parented to
-- you and has its own clientside model); two NPCs, the first one dancing with a camera path.
local ply = entity("player", 1, Vector(0, 0, 0))
local toolgun = entity("gmod_tool", 10)
local holstered = entity("weapon_crowbar", 11)
holstered.noDraw = true
local hat = entity("prop_dynamic", 12)
parent(toolgun, ply) parent(holstered, ply) parent(hat, ply)
local bodyCopy = entity("rtx_pseudoplayer")
local weaponCopy = entity("rtx_pseudoweapon")
local weaponCopyModel = entity("class C_BaseFlex")
parent(weaponCopy, ply) parent(weaponCopyModel, weaponCopy)
local npc = entity("npc_citizen", 20, Vector(180, 0, 0))
local other = entity("npc_citizen", 21, Vector(180, 140, 0))
local otherPlayer = entity("player", 2, Vector(0, 300, 0))
local ragdoll = nil
function ply:GetActiveWeapon() return toolgun end
function ply:GetRagdollEntity() return ragdoll end
function ply:IsTyping() return false end
function LocalPlayer() return ply end
local YOURS = { ply, toolgun, hat, bodyCopy, weaponCopy, weaponCopyModel }

-- net: a receiver reads the values the test queues.
local receivers, incoming = {}, {}
local function take() return table.remove(incoming, 1) end
net = { Receive = function(name, fn) receivers[name] = fn end, ReadUInt = take, ReadString = take, ReadVector = take,
    ReadFloat = take, ReadBool = take }
local function receive(name, ...)
    incoming = { ... }
    receivers[name](0)
    check(#incoming == 0, name .. ": " .. #incoming .. " values left unread")
end

dofile(path)
check(convars.mmd_vmd_npc_cam_hide_player and convars.mmd_vmd_npc_cam_hide_player.value == "1",
    "mmd_vmd_npc_cam_hide_player exists and is on by default")

-- A camera path in the NPC's frame: a static spot to its side, looking at it and at you.
local transfer = 0
local function play(anchor)
    transfer = transfer + 1
    receive("mmdvmd_camera_begin", transfer, anchor:EntIndex(), "probe", anchor:GetPos(), 0, 30, 0, 120, CurTime(),
        true, 4, true, false, 2)
    incoming = { transfer, 1, 2,
        0, 90, -160, 60, 5, 90, 0, 50,
        120, 90, -160, 60, 5, 90, 0, 50 }
    receivers["mmdvmd_camera_keys"](0)
    check(MMDVMDNPC.CameraAnimActive == true and MMDVMDNPC.CameraAnimEntIndex == anchor:EntIndex(),
        "the dance's camera path is entered")
end

-- One frame. Returns what it saw: the view, the flashlight's answer for you and for another player, and
-- which entities were hidden while the scene drew.
local function frame(options)
    options = options or {}
    now = now + 1 / 60
    hook.Run("Think")
    local view = hook.Run("CalcView", ply, Vector(0, 0, 64), Angle(0, 0, 0), 90)
    local seen = { view = view, flashlight = hook.Run("RTXFlashlightHidden", ply),
        otherFlashlight = hook.Run("RTXFlashlightHidden", otherPlayer), during = {}, after = {} }
    for _, answer in ipairs(answers("RenderScene", Vector(0, 0, 0), Angle(0, 0, 0), 90)) do
        check(answer[2] == nil, "RenderScene hook " .. answer[1] .. " returns nothing (a value replaces the scene)")
    end
    for _, e in ipairs(all) do seen.during[e] = e.noDraw end
    if not options.skipPostRender then hook.Run("PostRender") end
    for _, e in ipairs(all) do seen.after[e] = e.noDraw end
    return seen
end

local function hidden(seen, e) return seen.during[e] == true end
local function yours_hidden(seen, what)
    for _, e in ipairs(YOURS) do check(hidden(seen, e), what .. ": " .. e.class .. " hidden while the scene draws") end
    check(not hidden(seen, npc) and not hidden(seen, other) and not hidden(seen, otherPlayer), what .. ": nobody else hidden")
    check(seen.flashlight == true, what .. ": your flashlight kept dark")
    check(seen.otherFlashlight == nil, what .. ": another player's flashlight left alone")
    for _, e in ipairs(YOURS) do check(seen.after[e] == false, what .. ": " .. e.class .. " shown again after the frame") end
    check(seen.after[holstered] == true, what .. ": the holstered weapon stays as the server keeps it (hidden)")
end
local function yours_shown(seen, what)
    for _, e in ipairs(YOURS) do check(not hidden(seen, e), what .. ": " .. e.class .. " drawn") end
    check(seen.flashlight == nil, what .. ": your flashlight lit")
end
local function nothing_left(what)
    for _, e in ipairs(YOURS) do check(e.noDraw == false, what .. ": " .. e.class .. " not left hidden") end
    check(MMDVMDNPC.CameraHidesLocalPlayer() == false, what .. ": nothing hidden between frames")
    check(hook.Run("RTXFlashlightHidden", ply) == nil, what .. ": your flashlight lit between frames")
end

if scenario == "play" then
    -- First person: nothing hidden.
    yours_shown(frame(), "first person")
    play(npc)
    for i = 1, 3 do
        local seen = frame()
        check(seen.view and seen.view.drawviewer == true, "the camera's view (drawviewer kept: third person to the game)")
        yours_hidden(seen, "camera motion frame " .. i)
        nothing_left("between camera frames")
    end
    -- Stopped by the server (the dance stops, ends or the dancer is removed): the next frame shows you.
    receive("mmdvmd_camera_stop", npc:EntIndex())
    check(MMDVMDNPC.CameraAnimActive == false, "the stop leaves the camera path")
    local seen = frame()
    check(seen.view == nil, "first person again")
    yours_shown(seen, "after the stop")
    nothing_left("after the stop")
    -- Cancelled with the camera toggle (the hotkey or mmdvmd_camera_toggle) while the dance goes on.
    play(npc)
    yours_hidden(frame(), "the next dance's camera motion")
    MMDVMDNPC.ToggleCameraAnim()
    check(MMDVMDNPC.CameraAnimActive == false, "the toggle leaves the camera path")
    yours_shown(frame(), "after the toggle")
    nothing_left("after the toggle")
    -- Entered again with the toggle: hidden again.
    MMDVMDNPC.ToggleCameraAnim()
    yours_hidden(frame(), "entered again")
    -- The game shuts down (a map change) between PreRender and PostRender: nothing stays hidden.
    hook.Run("Think")
    hook.Run("CalcView", ply, Vector(0, 0, 64), Angle(0, 0, 0), 90)
    hook.Run("RenderScene", Vector(0, 0, 0), Angle(0, 0, 0), 90)
    check(ply.noDraw == true, "hidden mid-frame")
    hook.Run("ShutDown")
    for _, e in ipairs(YOURS) do check(e.noDraw == false, "shut down: " .. e.class .. " shown") end
    io.write("PASS play\n")

elseif scenario == "untick" then
    play(npc)
    yours_hidden(frame(), "on (default)")
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", "0")
    local seen = frame()
    check(seen.view ~= nil, "unticked mid-motion: the camera motion goes on")
    yours_shown(seen, "unticked mid-motion")
    nothing_left("unticked")
    RunConsoleCommand("mmd_vmd_npc_cam_hide_player", "1")
    yours_hidden(frame(), "ticked again mid-motion")
    io.write("PASS untick\n")

elseif scenario == "subject" then
    -- The debug window's camera preview orbits the entity of interest: with nothing selected, yourself.
    local track = { debug = true, entIndex = 1, keys = { { frame = 0, x = 90, y = -160, z = 60, p = 5, yw = 90, r = 0, fov = 50 } } }
    MMDVMDNPC.CameraDebugTracks["probe"] = track
    MMDVMDNPC.CameraDebugPreview = { motionID = "probe" }
    MMDVMDNPC.DebugFrame = { valid = true, ActiveFrame = 10 }
    local seen = frame()
    check(seen.view ~= nil, "the preview drives the view")
    yours_shown(seen, "a preview orbiting yourself keeps you")
    -- A selected NPC is the preview's subject: you are left out.
    MMDVMDNPC.TargetStatus = { ent = npc }
    seen = frame()
    check(seen.view ~= nil, "the preview on the NPC")
    yours_hidden(seen, "a preview orbiting the NPC")
    -- The window closes: the preview ends.
    MMDVMDNPC.DebugFrame = nil
    yours_shown(frame(), "after the preview")
    nothing_left("after the preview")
    io.write("PASS subject\n")

elseif scenario == "ends" then
    -- The dancer is removed under the camera: the camera fails and leaves the path; you are back.
    play(npc)
    yours_hidden(frame(), "before the removal")
    npc.valid = false
    local seen = frame()
    check(seen.view == nil and MMDVMDNPC.CameraAnimActive == false, "the camera motion fails without its dancer")
    yours_shown(seen, "after the failure")
    nothing_left("after the failure")
    io.write("PASS ends\n")

elseif scenario == "skipped" then
    -- Another add-on's PreRender skips the drawing, so PostRender never comes: the next Think, before the
    -- next CalcView, shows everything again.
    play(npc)
    local seen = frame({ skipPostRender = true })
    check(hidden(seen, ply), "hidden in the skipped frame")
    MMDVMDNPC.DeactivateCameraAnim()
    hook.Run("Think")
    for _, e in ipairs(YOURS) do check(e.noDraw == false, "the next Think shows " .. e.class) end
    yours_shown(frame(), "the frame after")
    nothing_left("the frame after")
    io.write("PASS skipped\n")

elseif scenario == "parts" then
    play(npc)
    -- Someone else hides your hat for the frame: it stays theirs, hidden, after the frame.
    hat.noDraw = true
    local seen = frame()
    check(seen.during[hat] == true and seen.after[hat] == true, "a part someone else hid stays hidden")
    hat.noDraw = false
    -- A death ragdoll is yours too; the dancer is never hidden, even if it hangs on you.
    ragdoll = entity("class C_HL2MPRagdoll")
    parent(npc, ply)
    seen = frame()
    check(hidden(seen, ragdoll) and seen.after[ragdoll] == false, "your death ragdoll is hidden for the frame")
    check(not hidden(seen, npc), "the camera's dancer is never hidden")
    -- Copies the RTX fixes make later are found within a second.
    local later = entity("rtx_pseudoplayer")
    now = now + 1.1
    seen = frame()
    check(hidden(seen, later) and seen.after[later] == false, "a body copy made later is hidden too")
    io.write("PASS parts\n")

else
    fail("unknown scenario " .. tostring(scenario))
end
