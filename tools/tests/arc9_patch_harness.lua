-- Runs the RTX fixes' ARC9 patch (packages/fixes/.../remixbinary/lua/patcher/addons/cl_arc9.lua, R24, ADR 0135) under
-- LuaJIT with a mocked patcher, ARC9 weapon and render API. Usage: luajit <this> <cl_arc9.lua> <scenario>. See the
-- adjacent .md.
local source, scenario = ...

local convars = { rtx_patcher_arc9 = "1", rtx_patcher_arc9_dx_warning = "0", rtx_patcher_arc9_parts = "1" }
local overrides, draws = {}, {}
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

CLIENT = true
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function CreateClientConVar(name, default)
    return { GetBool = function() return (convars[name] or default) ~= "0" end,
             GetInt = function() return tonumber(convars[name] or default) or 0 end }
end
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
local materials = {}
function Material(name)
    local found = materials[name]
    if not found then
        found = { name = name, IsError = function() return name:find("missing", 1, true) ~= nil end,
                  GetTexture = function() return { name = name .. "#texture" } end }
        materials[name] = found
    end
    return found
end
-- The overrides in force; a draw records them, so each part is checked against what it was drawn with.
local current = {}
render = { MaterialOverrideByIndex = function(index, mat)
    current[index] = mat and mat.name or nil
    overrides[#overrides + 1] = index .. "=" .. (mat and mat.name or "nil")
end }
local function inForce()
    local items = {}
    for index, name in pairs(current) do items[#items + 1] = index .. "=" .. name end
    table.sort(items)
    return #items > 0 and ("[" .. table.concat(items, ",") .. "]") or ""
end
ARC9 = { BadConfigStuff = { dx = { cause = function() return true end } } }
weapons = { GetStored = function() return nil end }
ents = { GetAll = function() return {} end }

local function part(name, fields)
    local model = { valid = true, name = name, NoDraw = false }
    for key, value in pairs(fields or {}) do model[key] = value end
    function model:DrawModel() draws[#draws + 1] = self.name .. (self.NoDraw and "!" or "") .. inForce() end
    return model
end
local function sticker(name, fields)
    fields = fields or {}
    fields.slottbl = { StickerModel = "models/items/arc9/sticker.mdl", att = { StickerMaterial = "stickers/" .. name } }
    return part(name, fields)
end
local function gunscreen(name)
    return part(name, { slottbl = { att = { Category = { "charm", "gunscreen" }, DrawFunc = function() end } } })
end

-- ARC9's DrawCustomModel as far as this patch depends on it (weapons/arc9_base/cl_drawmodel.lua): its early returns,
-- the model list, the parts its loop leaves out, and NoDraw.
local function arc9Draw(self, wm, custompos)
    local owner = self:GetOwner()
    if not wm and not IsValid(owner) then return "none" end
    local lod = self:ShouldLOD()
    local npc = (IsValid(owner) and owner:IsNPC()) or lod > 0
    if not wm and npc then return "none" end
    if wm and ARC9.RTScopeRender then return "none" end
    if custompos then wm = true end
    local list = wm and (custompos and self.CModel or self.WModel) or self.VModel
    if wm and lod >= 2 then draws[#draws + 1] = "base" return "base" end
    if self.fail then error("ARC9 failed", 0) end
    for _, model in ipairs(list or {}) do
        if not model.IsAnimationProxy and not model.charmparent and not model.NoDraw and not model.istranslucent then
            model:DrawModel()
        end
    end
    return "drawn", 2
end
local function weapon(options)
    local w = { valid = true, ARC9 = true, VModel = options.VModel, WModel = options.WModel, CModel = options.CModel,
                fail = options.fail }
    local owner = options.owner or { valid = true }
    function owner:IsNPC() return owner.npc == true end
    function w:GetOwner() return owner end
    function w:ShouldLOD() return options.lod or -1 end
    function w:GetFinalAttTable(slottbl) return slottbl.att end
    return w
end

local patch = dofile(source)
assert(istable(patch) and isfunction(patch.DrawCustomModel), "the patch module")
local function call(w, wm, custompos) return patch.DrawCustomModel(arc9Draw, w, wm, custompos) end
local function list(t) return table.concat(t, " ") end

if scenario == "view" then
    local logo, plain, screen = sticker("logo"), part("receiver"), gunscreen("counter")
    local w = weapon({ VModel = { plain, logo, screen } })
    local result, extra = call(w, false)
    eq(result, "drawn", "ARC9's results")
    eq(extra, 2, "every result")
    -- ARC9 drew the plain part; the dressed ones were skipped by it and drawn afterwards with their materials.
    eq(list(draws), "receiver logo[0=stickers/logo,1=stickers/logo,2=stickers/logo] counter[2=effects/arc9/gunscreen]")
    eq(inForce(), "", "every override is reset")
    eq(logo.NoDraw, false, "NoDraw put back")
    eq(screen.NoDraw, false, "NoDraw put back")
    -- A part hidden by ARC9 (a hidden bone) stays hidden.
    draws, overrides = {}, {}
    logo.hidden = true
    call(w, false)
    eq(list(draws), "receiver counter[2=effects/arc9/gunscreen]")
elseif scenario == "world-model-skipped" then
    -- No parts of a world model while an RT scope renders, and only the base model at LOD 2 (its parts keep a stale
    -- pose: drawn there, distant players' stickers would float where the gun last was).
    local w = weapon({ WModel = { sticker("logo") } })
    ARC9.RTScopeRender = true
    eq(call(w, true), "none")
    ARC9.RTScopeRender = nil
    local far = weapon({ WModel = { sticker("logo") }, lod = 2 })
    eq(call(far, true), "base")
    eq(list(draws), "base")
    eq(#overrides, 0, "nothing drawn by the patch")
    eq(far.WModel[1].NoDraw, false)
elseif scenario == "view-model-skipped" then
    -- No view model for an NPC, a player seen from afar, or a weapon without an owner.
    local npc = weapon({ VModel = { sticker("logo") }, owner = { valid = true, npc = true } })
    eq(call(npc, false), "none")
    local distant = weapon({ VModel = { sticker("logo") }, lod = 1 })
    eq(call(distant, false), "none")
    local dropped = weapon({ VModel = { sticker("logo") }, owner = { valid = false } })
    eq(call(dropped, false), "none")
    eq(#draws + #overrides, 0, "nothing drawn")
elseif scenario == "preset" then
    -- A preset icon (custompos) draws the preset's models, not the world model's.
    local w = weapon({ WModel = { sticker("world") }, CModel = { sticker("preset") } })
    call(w, true, { x = 0 })
    eq(list(draws), "preset[0=stickers/preset,1=stickers/preset,2=stickers/preset]")
    eq(inForce(), "")
elseif scenario == "left-to-arc9" then
    -- Parts ARC9's loop does not draw are left to it: animation proxies, charm models (their parent draws them),
    -- translucent parts (its translucent pass).
    local w = weapon({ VModel = { sticker("proxy", { IsAnimationProxy = true }), sticker("charm", { charmparent = {} }),
                                  sticker("glass", { istranslucent = true }) } })
    call(w, false)
    eq(#draws + #overrides, 0, list(draws) .. " | " .. list(overrides))
    for _, model in ipairs(w.VModel) do eq(model.NoDraw, false, model.name) end
elseif scenario == "error" then
    -- ARC9's error goes on as it was, after the parts' NoDraw is put back.
    local logo = sticker("logo")
    local w = weapon({ VModel = { logo }, fail = true })
    local ok, err = pcall(call, w, false)
    eq(ok, false)
    eq(err, "ARC9 failed", "ARC9's own message")
    eq(logo.NoDraw, false, "NoDraw put back")
elseif scenario == "off" then
    convars.rtx_patcher_arc9_parts = "0"
    local logo = sticker("logo")
    call(weapon({ VModel = { logo } }), false)
    eq(list(draws), "logo", "ARC9 draws it itself")
    eq(#overrides, 0)
elseif scenario == "screens-first" then
    -- The patch applies before the companion's screen redraw: its provider waits in the table the companion keeps.
    NativeLoaderScreens = nil
    local base = { DrawCustomModel = arc9Draw }
    registered.apply(nil, nil, { base = base })
    eq(RTXPatcher.State.arc9.screens, "offered to the companion's screen redraw")
    local provider = NativeLoaderScreens.providers.arc9_gunscreen
    assert(isfunction(provider), "the provider is in place")
    NativeLoaderScreens = NativeLoaderScreens or { providers = {} } -- the companion's own line
    eq(NativeLoaderScreens.providers.arc9_gunscreen, provider, "kept by the companion")
    -- One screen function and one texture function for every frame (the companion caches meshes per function).
    local screen = gunscreen("counter")
    screen.NLARC9GunScreen = true
    local w = weapon({ VModel = { screen } })
    local first, second = provider(nil, w), provider(nil, w)
    eq(first[1].screen, second[1].screen, "the same screen function")
    eq(first[1].texture, second[1].texture, "the same texture function")
    assert(first[1].screen("models/sherrifdoggo/gunscreen/GS_Screen.vmt"), "the screen's material")
    assert(not first[1].screen("models/sherrifdoggo/gunscreen/board"), "not another material")
    eq(first[1].texture().name, "effects/arc9/gunscreen#texture")
elseif scenario == "screens-after" then
    local got = {}
    NativeLoaderScreens = { providers = {}, Register = function(id, provider) got[id] = provider end }
    registered.apply(nil, nil, { base = { DrawCustomModel = arc9Draw } })
    eq(RTXPatcher.State.arc9.screens, "redrawn in 2D")
    assert(isfunction(got.arc9_gunscreen), "registered through the companion")
    eq(RTXPatcher.State.arc9.dxWarning, "hidden")
    eq(ARC9.BadConfigStuff.dx.cause(), false, "the DirectX check answers fine")
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
