-- Runs the scope and screen-draw parts of the RTX fixes' ARC9 patch (packages/fixes/.../patcher/addons/cl_arc9.lua,
-- R25) under LuaJIT with a mocked patcher, runtime configuration, render API and an ARC9 weapon with an RT scope part.
-- Usage: luajit <this> <cl_arc9.lua> <scenario>. See the adjacent .md.
local source, scenario = ...

local convars = { rtx_patcher_arc9 = "1", rtx_patcher_arc9_dx_warning = "0", rtx_patcher_arc9_parts = "1",
    rtx_patcher_arc9_scopes = "1", rtx_patcher_arc9_scope_hash = "" }
local log = {}
local function note(text) log[#log + 1] = text end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function near(a, b, what) if math.abs(a - b) > 1e-3 then error((what or "value") .. ": expected " .. b .. ", got " .. a, 2) end end

CLIENT = true
ARC9 = { BadConfigStuff = { dx = { cause = function() return true end } } }
weapons = { GetStored = function() return nil end }
ents = { GetAll = function() return {} end }
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function CreateClientConVar(name, default)
    return { GetBool = function() return (convars[name] or default) ~= "0" end,
             GetInt = function() return tonumber(convars[name] or default) or 0 end,
             GetString = function() return convars[name] or default end }
end
local laterConvars = {}
function GetConVar(name) return laterConvars[name] end
bit = { bor = function(...) local r = 0 for _, v in ipairs({ ... }) do r = r + v end return r end,
        band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, MATERIAL_RT_DEPTH_NONE, MATERIAL_TRIANGLES = 8, 1, 2, 2
-- As in GMod: no IMAGE_FORMAT_BGRX8888 global.
IMAGE_FORMAT_RGBA8888 = 0

-- Vectors and angles: Source's axes for the angle (0, 0, 0): forward +x, right -y, up +z.
local vector = {}
vector.__index = vector
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector) end
function isvector(v) return getmetatable(v) == vector end
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
vector.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    return Vector(a.x * b, a.y * b, a.z * b)
end
vector.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
function vector:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function vector:Length() return math.sqrt(self:Dot(self)) end
function vector:Set(b) self.x, self.y, self.z = b.x, b.y, b.z end
function vector:SetUnpacked(x, y, z) self.x, self.y, self.z = x, y, z end
local angle = {}
angle.__index = angle
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, angle) end
function angle:Forward() return Vector(1, 0, 0) end
function angle:Right() return Vector(0, -1, 0) end
function angle:Up() return Vector(0, 0, 1) end
-- A bone matrix: a translation.
local matrix = {}
matrix.__index = matrix
function Matrix(x, y, z) return setmetatable({ offset = Vector(x, y, z) }, matrix) end
matrix.__mul = function(a, b)
    if getmetatable(b) == matrix then return Matrix(a.offset.x + b.offset.x, a.offset.y + b.offset.y, a.offset.z + b.offset.z) end
    return a.offset + b
end
function matrix:Unpack() local o = self.offset return 1, 0, 0, o.x, 0, 1, 0, o.y, 0, 0, 1, o.z, 0, 0, 0, 1 end
function matrix:GetScale() return Vector(1, 1, 1) end
function LerpVector(t, a, b) return a + (b - a) * t end
math.ease = { InBack = function(x) return x end }
color_white = { r = 255, g = 255, b = 255, a = 255 }
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function ErrorNoHalt() end

local frame, width, height = 7, 1600, 900
function FrameNumber() return frame end
function ScrW() return width end
function ScrH() return height end
function EyePos() return Vector(0, 0, 0) end
function EyeAngles() return Angle(0, 0, 0) end
function MainEyePos() return Vector(0, 0, 0) end
function MainEyeAngles() return Angle(0, 0, 0) end

local registered
RTXPatcher = {
    State = {},
    Debug = function() end,
    RegisterPatch = function(patch) registered = patch end,
    InterceptFunction = function(tbl, key, spec)
        local original = tbl[key]
        tbl[key] = function(...) return spec.around(original, ...) end
        return true
    end,
}
if scenario ~= "no-runtime" then
    RemixConfig = { SetConfigVariable = function(key, value) note("config " .. key .. "=" .. value) return true end }
end
function GetRenderTargetEx(name, w, h, size, depth, flags, rtFlags, format)
    note(string.format("target %s %dx%d size=%d depth=%d flags=%d format=%d", name, w, h, size, depth, flags, format))
    local target = { name = name }
    function target:Width() return w end
    function target:Height() return h end
    function target:GetName() return name end
    return target
end
function CreateMaterial(name, shader, params)
    local m = { name = name, shader = shader, params = params }
    function m:SetTexture(key, texture) note("texture " .. name .. " " .. tostring(texture and texture.name)) end
    return m
end
local flagsOf = {}
function Material(name)
    return { name = name, IsError = function() return false end, GetInt = function(_, key) return key == "$flags" and (flagsOf[name] or 0) or nil end,
             GetTexture = function() return { name = name .. "#texture", IsError = function() return false end } end }
end
local current = {}
local failCamera = false
render = {
    MaterialOverrideByIndex = function(index, mat) current[index] = mat and mat.name or nil end,
    PushRenderTarget = function(t) note("push " .. t.name) end,
    PopRenderTarget = function() note("pop") end,
    Clear = function() note("clear") end,
    SetMaterial = function(m) note("material " .. m.name) end,
    GetViewSetup = function() return { fov = 90 } end,
    DrawScreenQuad = function() note("screen quad") end,
    DrawScreenQuadEx = function() note("screen quad ex") end,
    UpdateScreenEffectTexture = function() note("screen read") end,
}
cam = {
    Start3D = function(origin, angles, fov, x, y, w, h, near, far)
        if not origin then
            note(string.format("camera view fov=%.4f near=%s far=%s", fov, tostring(near), tostring(far)))
            return
        end
        note(string.format("camera origin=(%.2f,%.2f,%.2f) fov=%.4f viewport=%d,%d,%d,%d near=%d far=%d",
            origin.x, origin.y, origin.z, fov, x, y, w, h, near, far))
    end,
    End3D = function() note("camera end") end,
    Start2D = function() note("2d") end,
    End2D = function() note("2d end") end,
    IgnoreZ = function(on) note("ignorez " .. tostring(on)) end,
}
local vertices
mesh = {
    Begin = function(kind, count)
        if failCamera and count == 1 then error("mesh failed") end
        vertices = {} note("mesh " .. count)
    end,
    Position = function(p) vertices[#vertices + 1] = { p = Vector(p.x, p.y, p.z) } end,
    TexCoord = function(_, u, v) vertices[#vertices].u, vertices[#vertices].v = u, v end,
    Color = function() end,
    AdvanceVertex = function() end,
    End = function() note("mesh end " .. #vertices) end,
}
local lensTriangle = {
    { pos = Vector(0, 0, 0), u = 0, v = 0, weights = { { bone = 0, weight = 1 } } },
    { pos = Vector(0, -1, 0.5), u = 1, v = 0, weights = { { bone = 0, weight = 1 } } },
    { pos = Vector(0, 1, -0.5), u = 0, v = 1, weights = { { bone = 0, weight = 1 } } },
}
util = {
    GetModelMeshes = function(path, lod, mask)
        note("meshes " .. path .. " mask=" .. tostring(mask))
        return { { material = "models/scope/body", triangles = {} }, { material = "Models/Scope/Lens", triangles = lensTriangle } },
               { [0] = { matrix = Matrix(0, 0, 0) } }
    end,
    TableToJSON = function() return "{}" end,
}
local hooks = {}
hook = { Add = function(event, name, fn) hooks[event .. "/" .. name] = fn end }
concommand = { Add = function() end }
local polys = {}
surface = {
    SetMaterial = function(m) note("surface " .. m.name) end,
    SetDrawColor = function(r, g, b, a) note("color " .. a) end,
    DrawPoly = function(t) polys[#polys + 1] = t end,
    DrawRect = function() note("rect") end,
    DrawTexturedRect = function() note("textured rect") end,
}

-- An RT scope part (the ELCAN: its lens at sub-material 3) and an ordinary one.
local function part(name, fields)
    local model = { valid = true, name = name, NoDraw = false }
    for key, value in pairs(fields or {}) do model[key] = value end
    function model:DrawModel()
        local items = {}
        for index, mat in pairs(current) do items[#items + 1] = index .. "=" .. mat end
        table.sort(items)
        note("draw " .. self.name .. (#items > 0 and ("[" .. table.concat(items, ",") .. "]") or ""))
    end
    function model:GetModel() return "models/scope/elcan.mdl" end
    function model:GetSkin() return 0 end
    function model:GetNumBodyGroups() return 2 end
    function model:GetBodygroupCount(id) return id == 0 and 2 or 3 end
    function model:GetBodygroup(id) return id == 0 and 1 or 2 end
    function model:GetMaterials() return { "models/scope/body", "models/scope/rim", "models/scope/glass", "models/scope/lens" } end
    function model:GetBoneMatrix() return Matrix(10, 0, 0) end
    function model:GetPos() return Vector(10, 0, 0) end
    function model:GetAngles() return Angle(0, 0, 0) end
    function model:GetModelBounds() return Vector(-2, -1, -1), Vector(4, 1, 1) end
    function model:GetRenderBounds() return Vector(-2, -1, -1), Vector(4, 1, 1) end
    return model
end
local scope = part("elcan", { slottbl = { att = { RTScope = true, RTScopeSubmatIndex = 3, ScopeScreenRatio = 0.5,
    RTScopeReticle = Material("reticles/elcan") } } })
local receiver = part("receiver", { slottbl = { att = {} } })

local function arc9Draw(self, wm)
    for _, model in ipairs(self.VModel) do
        if not model.NoDraw then model:DrawModel() end
    end
    self.RTScopeModel = scope -- as ARC9's loop does for the active sight's RT scope
    return "drawn"
end
local w = { valid = true, ARC9 = true, VModel = { receiver, scope }, ViewModelFOV = 90, CustomizeDelta = 0 }
local owner = { valid = true, IsNPC = function() return false end }
function w:GetOwner() return owner end
function w:ShouldLOD() return 0 end
function w:GetFinalAttTable(slottbl) return slottbl.att end
function w:IsScoping() return scope.slottbl.att end
function w:GetRTScopeMagnification() return 2 end
function w:ScaleFOVByWidthRatio(fov, ratio) return math.deg(math.atan(math.tan(math.rad(fov) * 0.5) * ratio)) * 2 end
function w:WidescreenFix(fov) return fov end
function w:GetSightDelta() return 1 end
function w:GetSight() return { Scale = 1 } end
function w:ShouldDoScope() return true end

local patch = dofile(source)
assert(istable(patch) and isfunction(patch.RenderRT), "the patch module")
local function list() return table.concat(log, " | ") end
local function find(prefix)
    for _, line in ipairs(log) do if line:sub(1, #prefix) == prefix then return line end end
end

local expectedFov = w:ScaleFOVByWidthRatio(90, 0.75) / 2
-- The view model reaches 14 units ahead (the parts' bounds at 10 units): the runtime draws it at a quarter of that, so
-- the camera starts at ARC9's own 8 units.
local cameraLine = string.format("camera origin=(8.00,0.00,0.00) fov=%.4f viewport=0,0,508,508 near=4 far=30000", expectedFov)

if scenario == "lens" then
    local arc9Rendered = false
    patch.RenderRT(function() arc9Rendered = true end, w, false, 2)
    eq(arc9Rendered, false, "ARC9's own render-target picture")
    local view = w.NLARC9ScopeView
    near(view.fov, expectedFov, "scope fov")
    eq(view.frame, frame)
    assert(find("config rtx.raytracedRenderTargetTextures=0x9F721457A944740A"), "the target's hash given to the runtime: " .. list())
    assert(find("target nativeloader_arc9_scope_v1 1016x508 size=8 depth=1 flags=780 format=16"), list())
    assert(find("target nativeloader_arc9_scope_black_v1 16x16 size=8 depth=2 flags=780 format=0"), list())
    assert(find("clear"), "the black target cleared: " .. list())
    scope.RTScopeDrawingRN = true
    log = {}
    eq(patch.DrawCustomModel(arc9Draw, w, false), "drawn")
    -- ARC9 drew the receiver; the scope was drawn after it with its lens black, then the camera and the lens copy.
    eq(list(), table.concat({ "draw receiver", "draw elcan[3=nativeloader_arc9_scope_black]",
        "meshes models/scope/elcan.mdl mask=5", "push nativeloader_arc9_scope_v1", cameraLine,
        "material nativeloader_arc9_scope_camera", "mesh 1", "mesh end 3", "camera end", "pop",
        "material nativeloader_arc9_scope_lens", "mesh 1", "mesh end 3" }, " | "))
    eq(next(current), nil, "every override reset")
    eq(scope.NoDraw, false, "NoDraw put back")
    -- The lens copy: the lens at the bone's pose, 0.1 towards the eye, its coordinates its place on the screen in ARC9's
    -- square (a 900-pixel square in the middle of a 1600 x 900 screen).
    near(vertices[1].p.x, 9.9, "lifted towards the eye")
    near(vertices[1].u, 0.5, "centre u")
    near(vertices[1].v, 0.5, "centre v")
    -- (10, -1, 0.5): x = (1 + 0.1) * 800 = 880, y = (1 - 0.5 * 16/9 / 10) * 450 = 410.
    near(vertices[2].u, (880 - 350) / 900, "u")
    near(vertices[2].v, 410 / 900, "v")
    eq(w.NLARC9Lens.frame, frame)
    -- The reticle, from ARC9's own DrawRTReticle call: its square 1.5 units ahead of (8, 0, 0), half size 2.
    log = {}
    patch.DrawRTReticle(function() error("ARC9's own reticle drawing") end, w, scope, scope.slottbl.att)
    eq(scope.RTScopeDrawingRN, true, "looked through")
    assert(find("surface nativeloader_arc9_scope_reticle"), list())
    eq(log[1], "2d")
    eq(log[#log], "2d end")
    eq(#polys, 1, "one lens triangle")
    near(polys[1][1].u, 0.5, "reticle centre u")
    near(polys[1][1].v, 0.5, "reticle centre v")
    -- (880, 410) is the ray (1, -0.1, 0.05): it meets the square's plane at 9.5 units, 0.95 right and 0.475 up.
    near(polys[1][2].u, (0.95 + 2) / 4, "reticle u")
    near(polys[1][2].v, (2 - 0.475) / 4, "reticle v")
    eq(patch.Scope.stats.error, nil)
elseif scenario == "not-looking" then
    -- Not looked through: the lens is black and nothing else is drawn.
    patch.RenderRT(function() end, w, false, 2)
    scope.RTScopeDrawingRN = false
    log = {}
    patch.DrawCustomModel(arc9Draw, w, false)
    eq(list(), "draw receiver | draw elcan[3=nativeloader_arc9_scope_black]")
    -- A stale view (an earlier frame) draws nothing either.
    scope.RTScopeDrawingRN = true
    frame = frame + 1
    log = {}
    patch.DrawCustomModel(arc9Draw, w, false)
    eq(list(), "draw receiver | draw elcan[3=nativeloader_arc9_scope_black]")
elseif scenario == "off" or scenario == "no-runtime" then
    -- ARC9's own scopes: its RenderRT and DrawRTReticle run, its loop draws the scope, nothing is made.
    if scenario == "off" then convars.rtx_patcher_arc9_scopes = "0" end
    local ran = {}
    patch.RenderRT(function() ran[#ran + 1] = "RenderRT" end, w, false, 2)
    patch.DrawRTReticle(function() ran[#ran + 1] = "DrawRTReticle" end, w, scope, {})
    eq(table.concat(ran, " "), "RenderRT DrawRTReticle")
    log = {}
    patch.DrawCustomModel(arc9Draw, w, false)
    eq(list(), "draw receiver | draw elcan")
    eq(patch.Scope.ready, nil, "no target made")
elseif scenario == "own-picture" then
    -- ARC9's own scope picture (scopes off): the screen is read first, so the RTX runtime ends path tracing on it
    -- before ARC9 binds its full-frame target and draws 2D; not at the hip, not with the patch off.
    convars.rtx_patcher_arc9_scopes = "0"
    local function arc9Reticle() note("ARC9 reticle") end
    patch.DrawRTReticle(arc9Reticle, w, scope, {})
    eq(list(), "screen read | ARC9 reticle")
    log = {}
    w.GetSightDelta = function() return 0 end
    patch.DrawRTReticle(arc9Reticle, w, scope, {})
    eq(list(), "ARC9 reticle", "at the hip")
    log = {}
    laterConvars.arc9_fx_rt_alwaysdraw = { GetBool = function() return true end }
    patch.DrawRTReticle(arc9Reticle, w, scope, {})
    eq(list(), "screen read | ARC9 reticle", "always drawn")
    log = {}
    convars.rtx_patcher_arc9 = "0"
    patch.DrawRTReticle(arc9Reticle, w, scope, {})
    eq(list(), "ARC9 reticle", "the patch off")
elseif scenario == "cheap" then
    -- A cheap sight (ARC9's own answer: collimators, 1x, arc9_cheapscopes): the lens shows ARC9's (zoomed) view 1:1,
    -- the view's own vertical field of view.
    patch.RenderRT(function() error("ARC9's own picture") end, w, true)
    near(w.NLARC9ScopeView.fov, w:ScaleFOVByWidthRatio(90, 900 / 1600), "1:1")
elseif scenario == "blur" then
    -- The sight blur and its mask never run in RTX sessions; with the patch off, ARC9's do.
    local ran = 0
    patch.NoBlur(function() ran = ran + 1 end, w)
    eq(ran, 0, "skipped")
    convars.rtx_patcher_arc9 = "0"
    patch.NoBlur(function() ran = ran + 1 end, w)
    eq(ran, 1, "ARC9's own with the patch off")
elseif scenario == "screen-draws" then
    -- ARC9's 2D draws before the view model (customization background, blur) are skipped, and put back after.
    local function arc9Pre()
        surface.DrawRect(0, 0, 10, 10)
        surface.DrawTexturedRect(0, 0, 10, 10)
        render.DrawScreenQuad()
        return nil
    end
    local rect = surface.DrawRect
    patch.PreDrawViewModel(arc9Pre, w)
    eq(list(), "", "nothing drawn")
    eq(surface.DrawRect, rect, "put back")
    -- An error inside ARC9's still puts them back.
    eq(pcall(patch.PreDrawViewModel, function() error("ARC9 failed") end, w), false)
    eq(surface.DrawRect, rect, "put back after an error")
    convars.rtx_patcher_arc9 = "0"
    patch.PreDrawViewModel(arc9Pre, w)
    eq(list(), "rect | textured rect | screen quad", "ARC9's own with the patch off")
elseif scenario == "screen-reads" then
    -- ARC9's screen copies before the view model (its sight blur's, its blur's) are skipped too, and put back after.
    local function arc9Pre()
        render.UpdateScreenEffectTexture()
        render.CopyTexture("screen", "arc9_prevm")
        render.UpdateFullScreenDepthTexture()
        render.CopyRenderTargetToTexture("x")
        return "pre"
    end
    local reads = { "UpdateScreenEffectTexture", "UpdateFullScreenDepthTexture", "UpdateRefractTexture",
        "UpdatePowerOfTwoTexture", "CopyRenderTargetToTexture", "CopyTexture" }
    for _, name in ipairs(reads) do render[name] = function() note(name) end end
    local own = render.UpdateScreenEffectTexture
    eq(patch.PreDrawViewModel(arc9Pre, w), "pre", "ARC9's answer")
    eq(list(), "", "nothing read")
    eq(render.UpdateScreenEffectTexture, own, "put back")
    convars.rtx_patcher_arc9 = "0"
    patch.PreDrawViewModel(arc9Pre, w)
    eq(list(), "UpdateScreenEffectTexture | CopyTexture | UpdateFullScreenDepthTexture | CopyRenderTargetToTexture",
        "ARC9's own with the patch off")
elseif scenario == "translucent-pass" then
    -- The view model's translucent parts are drawn without the screen copy before them; a world model's pass is ARC9's.
    render.UpdatePowerOfTwoTexture = function() note("power of two") end
    local function arc9Pass(self, wm)
        render.UpdatePowerOfTwoTexture()
        note("translucent " .. tostring(wm))
        return "pass"
    end
    eq(patch.DrawTranslucentPass(arc9Pass, w, false, false), "pass")
    eq(list(), "translucent false")
    log = {}
    patch.DrawTranslucentPass(arc9Pass, w, true)
    eq(list(), "power of two | translucent true")
    log = {}
    eq(pcall(patch.DrawTranslucentPass, function() error("ARC9 failed") end, w, false), false)
    render.UpdatePowerOfTwoTexture()
    eq(list(), "power of two", "put back after an error")
elseif scenario == "after-view-model" then
    -- The screen is read once in PreDrawEffects (after every view model draw) in a frame whose ARC9 screen copy was
    -- skipped: not twice, not in a frame without ARC9's PreDrawViewModel, not in ARC9's own scope view or a preset's
    -- camera, not with the patch off. ARC9's PostDrawViewModel reads nothing.
    local effects = hooks["PreDrawEffects/rtx_patcher_arc9_after_view_models"]
    assert(effects == patch.EndPathTracing, "the PreDrawEffects hook")
    local function arc9() end
    patch.PreDrawViewModel(arc9, w)
    patch.PostDrawViewModel(arc9, w)
    patch.PreDrawViewModel(arc9, w) -- the translucent pass
    patch.PostDrawViewModel(arc9, w)
    eq(list(), "", "nothing read before the view models are all drawn")
    effects()
    eq(list(), "screen read")
    effects()
    eq(list(), "screen read", "once a frame")
    log = {}
    frame = frame + 1
    effects()
    eq(list(), "", "a frame without ARC9's view model")
    for _, field in ipairs({ "RTScopeRender", "PresetCam" }) do
        log = {}
        frame = frame + 1
        patch.PreDrawViewModel(arc9, w)
        ARC9[field] = true
        effects()
        eq(list(), "", field)
        ARC9[field] = nil
    end
    log = {}
    frame = frame + 1
    convars.rtx_patcher_arc9 = "0"
    patch.PreDrawViewModel(arc9, w)
    effects()
    eq(list(), "", "the patch off")
elseif scenario == "deferred" then
    -- ARC9's holosights (from its PostDrawViewModel) and the view model's flares (DrawLightFlare with vm set) are kept
    -- from the last of the frame's two passes and drawn after the read in PreDrawEffects, with the view model's camera;
    -- a world model's flare is drawn at once; the weapon's own DoHolosight is put back.
    local effects = hooks["PreDrawEffects/rtx_patcher_arc9_after_view_models"]
    local holo = part("holo", {})
    local function ownHolosight(self, model) note("holosight " .. model.name) end
    w.DoHolosight = ownHolosight
    local function arc9Post(self) self:DoHolosight(holo, {}) return "post" end
    local function arc9Flare(self, pos, ang, col, size, vm) note("flare " .. tostring(vm) .. " " .. pos.x) end
    for pass = 1, 2 do
        patch.PreDrawViewModel(function() end, w)
        local pos = Vector(pass, 0, 0)
        patch.DrawLightFlare(arc9Flare, w, pos, Angle(0, 0, 0), color_white, 1, true, false, Vector(0, 0, 1))
        pos.x = 99 -- ARC9 reusing its vector: the kept copy is unchanged
        eq(patch.PostDrawViewModel(arc9Post, w), "post")
    end
    eq(list(), "", "nothing drawn inside the passes")
    eq(rawget(w, "DoHolosight"), ownHolosight, "the weapon's own DoHolosight put back")
    patch.DrawLightFlare(arc9Flare, w, Vector(9, 0, 0), Angle(0, 0, 0), color_white, 1, false)
    eq(list(), "flare false 9", "a world model's flare at once")
    log = {}
    effects()
    eq(list(), "screen read | camera view fov=90.0000 near=1 far=10000 | holosight holo | flare true 2 | camera end")
    log = {}
    frame = frame + 1
    effects()
    eq(list(), "", "drawn once")
    -- An error in ARC9's PostDrawViewModel still puts DoHolosight back.
    patch.PreDrawViewModel(function() end, w)
    eq(pcall(patch.PostDrawViewModel, function() error("ARC9 failed") end, w), false)
    eq(rawget(w, "DoHolosight"), ownHolosight, "put back after an error")
elseif scenario == "vm-attachments" then
    -- The view model's render bounds reach far past the gun; its attachment points (the muzzle at 40 units) mark the
    -- front: 40 x 0.25 + 2 = 12 units. One 5000 units away is not where the gun is.
    local vm = part("vm", {})
    function vm:GetRenderBounds() return Vector(-32, -162, -507), Vector(171, 130, 32) end
    function vm:GetPos() return Vector(0, 0, 0) end
    function vm:GetAttachments() return { { id = 1, name = "muzzle" }, { id = 2, name = "far" } } end
    function vm:GetAttachment(id)
        return id == 1 and { Pos = Vector(40, 0, -2), Ang = Angle(0, 0, 0) } or { Pos = Vector(5000, 0, 0), Ang = Angle(0, 0, 0) }
    end
    function w:GetVM() return vm end
    patch.RenderRT(function() end, w, false, 2)
    scope.RTScopeDrawingRN = true
    log = {}
    patch.DrawCustomModel(arc9Draw, w, false)
    local twelve = (cameraLine:gsub("origin=%(8%.00", "origin=(12.00"))
    assert(find(twelve), "the camera 12 units ahead: " .. list())
elseif scenario == "far-part" then
    -- A part ARC9 has not placed this frame (far from the eye), or one it does not draw: not the gun's front.
    local far = part("far", { slottbl = { att = {} } })
    function far:GetPos() return Vector(5000, 0, 0) end
    local skipped = part("skipped", { slottbl = { att = {} } })
    function skipped:GetPos() return Vector(60, 0, 0) end
    w.VModel = { receiver, scope, far, skipped }
    patch.RenderRT(function() end, w, false, 2)
    scope.RTScopeDrawingRN = true
    log = {}
    local function arc9DrawSkipping(self, wm)
        skipped.NoDraw = true -- as ARC9 marks a part it does not draw
        return arc9Draw(self, wm)
    end
    patch.DrawCustomModel(arc9DrawSkipping, w, false)
    assert(find(cameraLine), "the camera at ARC9's 8 units: " .. list())
elseif scenario == "own-lens" then
    -- A scope in the weapon's own view model: its lens black while the engine draws it, then the copy.
    w.RTScope, w.RTScopeSubmatIndex = true, 3
    function w:GetVM() return scope end
    w.RTScopeModel = scope
    scope.RTScopeDrawingRN = true
    patch.RenderRT(function() end, w, false, 2)
    log = {}
    patch.PreDrawViewModel(function() end, w)
    scope:DrawModel() -- the engine's view model draw
    patch.ViewModelDrawn(function() note("ARC9 ViewModelDrawn") end, w)
    patch.PostDrawViewModel(function() end, w)
    eq(log[1], "draw elcan[3=nativeloader_arc9_scope_black]")
    eq(log[2], "ARC9 ViewModelDrawn")
    assert(find("material nativeloader_arc9_scope_lens"), list())
    eq(next(current), nil, "the override cleared")
    eq(w.NLARC9OwnLens, nil)
    -- PreDrawViewModel answering true (the view model hidden): nothing is overridden.
    patch.PreDrawViewModel(function() return true end, w)
    eq(next(current), nil, "nothing overridden")
elseif scenario == "always-draw" then
    -- ARC9 makes arc9_fx_rt_alwaysdraw after this file loads: it is read when needed.
    patch.RenderRT(function() end, w, false, 2)
    w.GetSightDelta = function() return 0 end
    patch.DrawRTReticle(function() end, w, scope, scope.slottbl.att)
    eq(scope.RTScopeDrawingRN, false, "not looked through")
    laterConvars.arc9_fx_rt_alwaysdraw = { GetBool = function() return true end }
    patch.DrawRTReticle(function() end, w, scope, scope.slottbl.att)
    eq(scope.RTScopeDrawingRN, true, "always drawn")
elseif scenario == "additive" then
    -- An additive reticle ($additive is a flag in $flags): the additive material.
    flagsOf["reticles/elcan"] = 128 + 2048
    patch.RenderRT(function() end, w, false, 2)
    scope.RTScopeDrawingRN = true
    patch.DrawCustomModel(arc9Draw, w, false)
    log = {}
    patch.DrawRTReticle(function() end, w, scope, scope.slottbl.att)
    assert(find("surface nativeloader_arc9_scope_reticle_add"), list())
elseif scenario == "camera-error" then
    -- The camera's draw fails: the camera is ended and the target popped all the same, the error is kept.
    patch.RenderRT(function() end, w, false, 2)
    scope.RTScopeDrawingRN = true
    failCamera = true
    log = {}
    eq(patch.DrawCustomModel(arc9Draw, w, false), "drawn")
    eq(list(), table.concat({ "draw receiver", "draw elcan[3=nativeloader_arc9_scope_black]",
        "meshes models/scope/elcan.mdl mask=5", "push nativeloader_arc9_scope_v1", cameraLine, "material nativeloader_arc9_scope_camera",
        "camera end", "pop" }, " | "))
    assert(patch.Scope.stats.error and patch.Scope.stats.error:find("mesh failed"), "the error kept")
elseif scenario == "hash-override" then
    convars.rtx_patcher_arc9_scope_hash = "0xABCDEF0123456789"
    patch.RenderRT(function() end, w, false, 2)
    assert(find("config rtx.raytracedRenderTargetTextures=0xABCDEF0123456789"), list())
elseif scenario == "apply" then
    -- Every function the scopes need is intercepted on the base, and a missing one is no failure of the rest.
    local base = { DrawCustomModel = arc9Draw, RenderRT = function() end, DrawRTReticle = function() end,
        PreDrawViewModel = function() end, ViewModelDrawn = function() end,
        PostDrawViewModel = function() end, DrawTranslucentPass = function() render.UpdatePowerOfTwoTexture() end,
        RenderDoFMask = function() note("mask") end }
    registered.apply(nil, nil, { base = base })
    eq(RTXPatcher.State.arc9.parts, "drawn with their materials")
    base.RenderDoFMask(base)
    eq(find("mask"), nil, "the mask is skipped")
    eq(base.RenderDoF, nil, "an ARC9 without RenderDoF")
    render.UpdatePowerOfTwoTexture = function() note("power of two") end
    base.DrawTranslucentPass(base, false)
    eq(find("power of two"), nil, "the translucent pass is intercepted")
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
