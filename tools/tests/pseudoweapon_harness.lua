-- ADR 0251: the RTX fixes' weapon copy (lua/entities/rtx_pseudoweapon.lua) under LuaJIT with the game's API stubbed.
-- Its Think runs before the frame is rendered: it sets up the bones the copy follows and draws nothing, in first person
-- and in third person, for a Lua weapon (which has DrawWorldModel) and an engine weapon (which has not).
-- usage: luajit pseudoweapon_harness.lua <scenario> <rtx_pseudoweapon.lua>; prints PASS <scenario>.
local scenario, path = arg[1], arg[2]
local function check(ok, why) if not ok then error("FAIL " .. scenario .. ": " .. why, 2) end end
local function noop() end

-- GMod's Lua accepts C-style != and !; LuaJIT does not.
local source = assert(io.open(path, "rb")):read("*a")
source = source:gsub("!=", "~="):gsub("!(%s*[%w_%(])", "not %1")

local calls = { drawWorldModel = 0, drawModel = 0, playerBones = 0, weaponBones = 0 }
local cvars = { rtx_pseudoweapon = 1, rtx_pseudoweapon_unique_hashes = 0, rtx_pseudoweapon_unique_hashes_downscale = 1 }
local function cvar(name)
    return { GetBool = function() return (cvars[name] or 0) ~= 0 end, GetInt = function() return cvars[name] or 0 end }
end
CLIENT, SERVER = true, false
EF_BONEMERGE, MOVETYPE_NONE, OBS_MODE_NONE = 1, 0, 0
file = { Exists = function() return false end }
hook = { Add = noop }
util = { CRC = function(text) return tostring(#text) end }
CreateConVar, CreateClientConVar, AddCSLuaFile = noop, noop, noop
GetConVar = cvar
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local function model()
    local m = { valid = true }
    function m:IsValid() return self.valid end
    for _, name in ipairs({ "SetParent", "AddEffects", "RemoveEffects", "SetModel", "SetRenderMode", "SetColor",
            "SetNoDraw", "SetModelScale", "SetMoveType", "SetRenderOrigin", "SetRenderAngles" }) do m[name] = noop end
    function m:Remove() self.valid = false end
    function m:GetMaterials() return {} end
    function m:DrawModel() calls.drawModel = calls.drawModel + 1 end
    return m
end
function ClientsideModel() return model() end

local thirdPerson = scenario == "third_lua" or scenario == "third_engine"
local luaWeapon = scenario == "first_lua" or scenario == "third_lua"
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
ent:Initialize()
for _ = 1, 3 do ent:Think() end

check(calls.drawWorldModel == 0, "Think called the weapon's DrawWorldModel " .. calls.drawWorldModel .. " times")
check(calls.drawModel == 0, "Think drew a model " .. calls.drawModel .. " times")
check(calls.playerBones >= 3 and calls.weaponBones >= 3,
    "Think did not set up the bones the copy follows (player " .. calls.playerBones .. ", weapon " .. calls.weaponBones .. ")")
print("PASS " .. scenario)
