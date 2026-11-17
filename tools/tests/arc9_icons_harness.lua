-- Runs the load accelerator's real nlloadaccel/arc9_icons.lua (ADR 0240) under LuaJIT in a mocked realm: Material and
-- CreateMaterial (a material system that counts what it decodes), the IMaterial metatable, surface and render, convars,
-- hooks, util.CRC. An "ARC9 attachment file" is a chunk named lua/arc9/common/attachments_bulk/<x>.lua.
-- Usage: luajit <this> <repo> <scenario>. Prints "PASS <scenario>"; an error otherwise. See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/fs_accel/addon/lua/nlloadaccel/arc9_icons.lua"
local realPrint = print

local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function istable(v) return type(v) == "table" end

SERVER = scenario == "server"
CLIENT = not SERVER
FCVAR_ARCHIVE = 128
local convars = { nativeloader_load_accel_arc9 = scenario == "off" and "0" or nil,
    arc9_atts_generate_entities = scenario == "generate" and "1" or "0" }
function CreateConVar(name, default)
    if convars[name] == nil then convars[name] = default end
    return { GetBool = function() return convars[name] ~= "0" end }
end
function GetConVar(name)
    if convars[name] == nil then return nil end
    return { GetBool = function() return convars[name] ~= "0" end }
end
util = { CRC = function(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
    return tostring(h)
end }

-- The material system: a PNG Material decodes (counted); CreateMaterial makes or finds a material by name.
local Meta = {}
Meta.__index = Meta
local decoded, created, byName = {}, {}, {}
local function new(name, shader)
    return setmetatable({ name = name, shader = shader or "UnlitGeneric", values = {}, texture = nil, error = false }, Meta)
end
function Meta:GetTexture() return self.texture end
function Meta:SetTexture(_, value) self.texture = value self.setCount = (self.setCount or 0) + 1 end
function Meta:GetInt(key) return self.values[key] end
function Meta:SetInt(key, value) self.values[key] = value end
function Meta:GetString(key) return self.values[key] end
function Meta:GetFloat(key) return self.values[key] end
function Meta:GetVector() return nil end
function Meta:GetVector4D() return nil end
function Meta:GetVectorLinear() return nil end
function Meta:GetMatrix() return nil end
function Meta:GetKeyValues() return self.values end
function Meta:Width() return self.texture and 64 or 1 end
function Meta:Height() return self.texture and 64 or 1 end
function Meta:GetColor() return nil end
function Meta:IsError() return self.error end
function Meta:GetName() return self.name end
function Meta:GetShader() return self.shader end
function FindMetaTable(name) if name == "IMaterial" then return Meta end end
local nativeMaterial = function(path, params)
    decoded[#decoded + 1] = path .. "|" .. tostring(params)
    local mat = new((params or "") .. path)
    mat.texture = { name = "decoded:" .. path }
    mat.values["$flags"] = 48
    if path:find("missing", 1, true) then mat.error = true end
    return mat, 0.002
end
Material = nativeMaterial
function CreateMaterial(name, shader, values)
    if byName[name] then return byName[name] end
    local mat = new(name, shader)
    mat.texture = { name = values["$basetexture"] }
    mat.values["$flags"] = (values["$vertexcolor"] == 1 and 16 or 0) + (values["$vertexalpha"] == 1 and 32 or 0)
    byName[name] = mat
    created[#created + 1] = name
    return mat
end
local drawn = {}
surface = { SetMaterial = function(mat) drawn[#drawn + 1] = mat end }
render = {
    SetMaterial = function(mat) drawn[#drawn + 1] = mat end,
    MaterialOverride = function(mat) drawn[#drawn + 1] = mat end,
    ModelMaterialOverride = function(mat) drawn[#drawn + 1] = mat end,
    BrushMaterialOverride = function(mat) drawn[#drawn + 1] = mat end,
    WorldMaterialOverride = function(mat) drawn[#drawn + 1] = mat end,
    MaterialOverrideByIndex = function(_, mat) drawn[#drawn + 1] = mat end,
}
local hooks = {}
hook = { Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end }
local function run(event) for _, fn in pairs(hooks[event] or {}) do fn() end end
local printed = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(parts, " ")
end

dofile(SCRIPT)

-- What an attachment file asks for (or any other file: `chunk`), as ARC9's do: ATT.Icon = Material(...) (an assignment;
-- `return Material(...)` would be a tail call, which leaves no frame of the file on the stack).
local function ask(path, params, chunk)
    local code = params and string.format("local m = Material(%q, %q) return m", path, params) or
        string.format("local m = Material(%q) return m", path)
    return assert(loadstring(code, "@" .. (chunk or "lua/arc9/common/attachments_bulk/test_bulk.lua")))()
end
local function count(list, value)
    local n = 0
    for _, v in ipairs(list) do if v == value then n = n + 1 end end
    return n
end

if scenario == "client" or scenario == "guard" then
    if scenario == "guard" then
        -- The render guard wraps Material after this file: one more frame between the attachment file and the wrapper.
        local inner = Material
        Material = function(path, ...) return inner(path, ...) end
    end
    local icon = ask("entities/arc9_att_a.png", "mips smooth")
    eq(#decoded, 0, "an attachment's icon is not decoded at load")
    eq(icon:GetShader(), "UnlitGeneric")
    eq(rawget(icon, "values")["$flags"], 48, "the stand-in has a PNG material's flags")
    local again = ask("entities/arc9_att_a.png", "mips smooth")
    assert(rawequal(icon, again), "one stand-in per icon, as GMod's own cache")
    local other = ask("entities/arc9_att_a.png", "smooth")
    assert(not rawequal(icon, other), "other flags, another material")
    local missing = ask("entities/missing_icon.png", "mips smooth")
    local plain = ask("entities/arc9_att_b.png")
    eq(#decoded, 0)
    -- Not deferred: another file, a VMT, flags a texture cannot carry.
    ask("vgui/hud.png", "mips smooth", "lua/arc9/client/cl_hud.lua")
    ask("models/arc9/reticle", nil)
    ask("entities/arc9_att_c.png", "vertexlitgeneric")
    eq(#decoded, 3, "what is not an attachment's icon is GMod's own")
    -- First draw: decoded into the stand-in, once.
    surface.SetMaterial(icon)
    eq(#decoded, 4)
    eq(decoded[4], "entities/arc9_att_a.png|mips smooth")
    eq(rawget(icon, "texture").name, "decoded:entities/arc9_att_a.png")
    assert(rawequal(drawn[#drawn], icon), "the stand-in itself is drawn")
    surface.SetMaterial(icon)
    render.SetMaterial(icon)
    eq(#decoded, 4, "decoded once")
    -- Read before any draw: decoded first, then answered.
    eq(plain:GetTexture("$basetexture").name, "decoded:entities/arc9_att_b.png")
    eq(decoded[#decoded], "entities/arc9_att_b.png|nil")
    eq(plain:Width(), 64)
    render.MaterialOverrideByIndex(1, other)
    eq(decoded[#decoded], "entities/arc9_att_a.png|smooth")
    -- A missing icon is an error once decoded.
    eq(missing:IsError(), true)
    eq(icon:IsError(), false)
    eq(NLLOADACCEL_ICONS.standIns, 4)
    -- After the load, an attachment file's Material is GMod's own (a reload of ARC9's attachments decodes).
    run("InitPostEntity")
    assert(printed[#printed]:find("4 ARC9 attachment icons left to be decoded when first drawn", 1, true), printed[#printed])
    local before = #decoded
    ask("entities/arc9_att_d.png", "mips smooth")
    eq(#decoded, before + 1)
elseif scenario == "server" then
    local a = ask("entities/arc9_att_a.png", "mips smooth")
    local b = ask("entities/arc9_att_b.png", "mips smooth")
    assert(rawequal(a, b), "one material stands in for all of them on the server")
    eq(count(decoded, "entities/arc9_att_a.png|mips smooth"), 0, "no icon decoded on the server")
    eq(count(decoded, "vgui/white|nil"), 1, "the stand-in, once")
    eq(#created, 0)
    run("InitPostEntity")
    assert(printed[#printed]:find("2 ARC9 attachment icons not decoded (the server never draws them)", 1, true), printed[#printed])
elseif scenario == "generate" then
    -- ARC9's generated attachment entities read every icon's texture name while it loads: Material is GMod's own.
    ask("entities/arc9_att_a.png", "mips smooth")
    eq(#decoded, 1)
    eq(#created, 0)
elseif scenario == "off" then
    assert(rawequal(Material, nativeMaterial), "switched off: Material untouched")
    ask("entities/arc9_att_a.png", "mips smooth")
    eq(#decoded, 1)
else
    error("unknown scenario " .. tostring(scenario))
end
realPrint("PASS " .. scenario)
