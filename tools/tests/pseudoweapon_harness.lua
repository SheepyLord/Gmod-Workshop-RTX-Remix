-- ADR 0251, ADR 0252: the RTX fixes' weapon copy (lua/entities/rtx_pseudoweapon.lua) under LuaJIT with the game's API
-- stubbed. Its Think runs before the frame is rendered: it sets up the bones the copy follows and makes no draw or
-- render call, in first and third person, for a scripted weapon (which has DrawWorldModel) and an engine weapon. The
-- copy's own draw makes its private textures at its first draw after a weapon change, inside the frame, draws only with
-- them (also with the legacy rtx_pseudoweapon_unique_hashes 0), puts the material overrides back and registers the
-- materials as the player model's.
-- usage: luajit pseudoweapon_harness.lua <scenario> <rtx_pseudoweapon.lua>; prints PASS <scenario>.
local scenario, path = arg[1], arg[2]
local function check(ok, why) if not ok then error("FAIL " .. scenario .. ": " .. why, 2) end end
local function noop() end

-- GMod's Lua accepts C-style != and !; LuaJIT does not.
local source = assert(io.open(path, "rb")):read("*a")
source = source:gsub("!=", "~="):gsub("!(%s*[%w_%(])", "not %1")

local phase = "load"
local calls = { drawWorldModel = 0, drawModel = 0, playerBones = 0, weaponBones = 0, captures = 0, registered = {} }
local renderCalls = { think = 0, draw = 0 }
local overrides, overridesReset = {}, 0
local cvars = { rtx_pseudoweapon = 1, rtx_pseudoweapon_unique_hashes = 0, rtx_pseudoweapon_unique_hashes_downscale = 1 }
local function cvar(name)
    return { GetBool = function() return (cvars[name] or 0) ~= 0 end, GetInt = function() return cvars[name] or 0 end }
end
CLIENT, SERVER = true, false
EF_BONEMERGE, MOVETYPE_NONE, OBS_MODE_NONE = 1, 0, 0
RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, IMAGE_FORMAT_RGBA8888 = 0, 0, 0
hook = { Add = noop }
util = { CRC = function(text) return tostring(#text) end }
CreateConVar, CreateClientConVar, AddCSLuaFile = noop, noop, noop
GetConVar = cvar
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Render calls, counted by phase; the copy's own draw is the only place they belong.
local function counted(fn)
    return function(...)
        renderCalls[phase] = (renderCalls[phase] or 0) + 1
        if fn then return fn(...) end
    end
end
render = setmetatable({
    Capture = counted(function() calls.captures = calls.captures + 1 return "png" end),
    MaterialOverrideByIndex = counted(function(index, material)
        if index == nil then overrides, overridesReset = {}, overridesReset + 1 else overrides[index] = material end
    end),
}, { __index = function(t, key) local fn = counted() rawset(t, key, fn) return fn end })
cam = { Start2D = counted(), End2D = counted() }
draw = { TexturedQuad = counted() }
surface = { GetTextureID = function() return 1 end }
function GetRenderTargetEx(name, w, h)
    return { name = name, Width = function() return w end, Height = function() return h end }
end
local function texture(name)
    return { Download = noop, Width = function() return 512 end, Height = function() return 256 end,
        GetName = function() return name end }
end
local function material(name, shader)
    local m = { name = name }
    function m:GetTexture() return texture(name .. "_tex") end
    function m:SetTexture(_, tex) self.tex = tex end
    function m:GetName() return name end
    function m:GetShader() return shader or "VertexLitGeneric" end
    function m:GetKeyValues() return { ["$basetexture"] = name } end
    return m
end
local created = {}
function Material(name) return material(name) end
function CreateMaterial(name, shader) local m = material(name, shader) created[name] = m return m end
file = { Exists = function() return false end,
    Open = function() return { Write = noop, Close = noop } end }
RemixCategoryManager = { RegisterPlayerProxyMaterial = function(name)
    calls.registered[name] = (calls.registered[name] or 0) + 1
    return calls.registered[name] >= 2 -- its hashes are known from the second draw on
end }

local function model()
    local m = { valid = true }
    function m:IsValid() return self.valid end
    for _, name in ipairs({ "SetParent", "AddEffects", "RemoveEffects", "SetModel", "SetRenderMode", "SetColor",
            "SetNoDraw", "SetModelScale", "SetMoveType", "SetRenderOrigin", "SetRenderAngles" }) do m[name] = noop end
    function m:Remove() self.valid = false end
    function m:GetMaterials() return { "models/weapons/w_toolgun/body", "models/weapons/w_toolgun/screen" } end
    function m:DrawModel()
        calls.drawModel = calls.drawModel + 1
        calls.drawnWith = 0
        for _ in pairs(overrides) do calls.drawnWith = calls.drawnWith + 1 end
    end
    return m
end
local copyModel
function ClientsideModel() copyModel = model() return copyModel end

local thirdPerson = scenario == "third_lua" or scenario == "third_engine"
local luaWeapon = scenario ~= "first_engine" and scenario ~= "third_engine"
local weapon = model()
weapon.class = "gmod_tool"
function weapon:GetClass() return self.class end
function weapon:GetModel() return "models/weapons/w_toolgun.mdl" end
function weapon:GetWeaponWorldModel() return "models/weapons/w_toolgun.mdl" end
function weapon:GetParent() return nil end
function weapon:GetParentAttachment() return 0 end
function weapon:GetRenderOrigin() return nil end
function weapon:GetRenderAngles() return nil end
function weapon:GetModelScale() return 1 end
function weapon:SetupBones() calls.weaponBones = calls.weaponBones + 1 end
if luaWeapon then
    -- A Lua weapon's DrawWorldModel draws its model; an engine weapon has none (the copy's pcall caught that).
    function weapon:DrawWorldModel() calls.drawWorldModel = calls.drawWorldModel + 1 self:DrawModel() end
end
local player = {}
function player:GetActiveWeapon() return weapon end
function player:Alive() return true end
function player:GetObserverMode() return OBS_MODE_NONE end
function player:GetViewEntity() return player end
function player:ShouldDrawLocalPlayer() return thirdPerson end
function player:SetupBones() calls.playerBones = calls.playerBones + 1 end
function LocalPlayer() return player end

ENT = {}
assert(loadstring(source, "=rtx_pseudoweapon.lua"))()
-- The entity: the stub model's methods, and the file's Initialize and Think.
local ent = setmetatable(model(), { __index = ENT })
phase = "think"
ent:Initialize()
for _ = 1, 3 do ent:Think() end

check(calls.drawWorldModel == 0, "Think called the weapon's DrawWorldModel " .. calls.drawWorldModel .. " times")
check(calls.drawModel == 0, "Think drew a model " .. calls.drawModel .. " times")
check(renderCalls.think == 0, "Think made " .. renderCalls.think .. " render calls before the frame")
check(calls.playerBones >= 3 and calls.weaponBones >= 3,
    "Think did not set up the bones the copy follows (player " .. calls.playerBones .. ", weapon " .. calls.weaponBones .. ")")

if scenario == "draw" then
    check(copyModel and copyModel.RenderOverride, "the copy's model has no draw of its own")
    phase = "draw"
    copyModel.RenderOverride(copyModel)
    check(calls.captures == 2, "the first draw made " .. calls.captures .. " private textures, not 2")
    check(created["pseudoweaponmaterial1_9"] and created["pseudoweaponmaterial2_9"],
        "the private materials were not made (legacy unique hashes 0)")
    check(calls.drawModel == 1 and calls.drawnWith == 2, "the copy was not drawn with its two private materials")
    check(overridesReset == 1 and next(overrides) == nil, "the material overrides were not put back after the draw")
    copyModel.RenderOverride(copyModel)
    copyModel.RenderOverride(copyModel)
    check(calls.captures == 2, "a later draw made the private textures again")
    check(calls.registered["pseudoweaponmaterial1_9"] == 2 and calls.registered["pseudoweaponmaterial2_9"] == 2,
        "the materials were not registered until their hashes were known, then left alone")
    -- A weapon change asks for new textures, made at the next draw and not before.
    weapon.class = "weapon_crowbar"
    phase = "think"
    ent:Think()
    check(renderCalls.think == 0, "Think made render calls after a weapon change")
    phase = "draw"
    copyModel.RenderOverride(copyModel)
    check(calls.captures == 4, "the next draw after a weapon change did not make the new textures")
end
print("PASS " .. scenario)
