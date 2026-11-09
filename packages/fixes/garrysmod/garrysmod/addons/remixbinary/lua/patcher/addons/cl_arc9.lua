if not CLIENT then return end
if not RTXPatcher then return end

-- ARC9 Weapon Base under RTX Remix (R24, the native-loader project).
--
-- 1. The DirectX warning. RTX sessions run Source at DirectX level 80, so ARC9 opened its "BAD GMOD SETTINGS"
--    window on the first deploy of any ARC9 weapon; its advice (-dxlevel 95) does not apply to a path-traced
--    renderer. Its DirectX check answers "fine" in RTX sessions: ARC9's own setting (arc9_ignore_dx) and every
--    other check it makes are left as they are.
-- 2. Parts dressed by sub-materials. Under RTX a client-side model's SetMaterial/SetSubMaterial does not change what
--    draws (R7), and ARC9 dresses parts that way: a sticker's model has no material of its own (the error material:
--    a white plate z-fighting with the receiver), and a gun screen charm puts its live screen on index 2. While ARC9
--    draws its custom models, those parts are drawn through render.MaterialOverrideByIndex instead, which does reach
--    the image; the sticker materials also go through the view model material pass, which makes them Remix decals.
-- 3. Gun screens. Their render target is black in the path-traced image; the companion's screen redraw draws them as
--    2D in the HUD pass, as it does the toolgun's screen.
local Patcher = RTXPatcher

local function createClientConVar(name, default, help)
    if CreateClientConVar then
        local convar = CreateClientConVar(name, default, true, false, help)
        if convar then return convar end
    end
    if GetConVar then
        local convar = GetConVar(name)
        if convar then return convar end
    end
    return {
        GetBool = function() return tostring(default) ~= "0" end,
        GetInt = function() return tonumber(default) or 0 end,
    }
end

local cvEnabled = createClientConVar("rtx_patcher_arc9", "1", "Enable ARC9 RTX Remix compatibility patches")
local cvDxWarning = createClientConVar("rtx_patcher_arc9_dx_warning", "0",
    "Show ARC9's DirectX level warning in RTX sessions (it does not apply to RTX Remix)")
local cvParts = createClientConVar("rtx_patcher_arc9_parts", "1",
    "Draw ARC9 stickers and gun screens with their materials in RTX sessions")

Patcher.ARC9 = Patcher.ARC9 or {}
local ARC9Patch = Patcher.ARC9
local GUNSCREEN = "effects/arc9/gunscreen"
local SCREEN_INDEX = 2
local materials = {}
local function material(name)
    local found = materials[name]
    if found == nil then
        found = Material(name)
        if found:IsError() then found = false end
        materials[name] = found
    end
    return found or nil
end

function ARC9Patch.IsReady()
    if type(ARC9) ~= "table" then return false, "ARC9 missing" end
    if type(ARC9.BadConfigStuff) ~= "table" then return false, "ARC9.BadConfigStuff missing" end
    if not weapons or type(weapons.GetStored) ~= "function" or not weapons.GetStored("arc9_base") then
        return false, "arc9_base missing"
    end
    return true, { base = weapons.GetStored("arc9_base") }
end

function ARC9Patch.PatchDirectXWarning()
    local dx = ARC9.BadConfigStuff and ARC9.BadConfigStuff.dx
    if type(dx) ~= "table" or type(dx.cause) ~= "function" then return false, "no DirectX check" end
    return Patcher.InterceptFunction(dx, "cause", {
        patchId = "arc9",
        id = "dx_warning",
        around = function(original, ...)
            if cvDxWarning:GetBool() then return original(...) end
            return false
        end
    })
end

local function category(atttbl, name)
    local value = istable(atttbl) and atttbl.Category
    if value == name then return true end
    if istable(value) then
        for _, item in ipairs(value) do if item == name then return true end end
    end
    return false
end

-- The material of each sub-material index a part is dressed with, from ARC9's own tables (a client-side model's
-- GetSubMaterial reads back nothing). Nil for an ordinary part.
function ARC9Patch.PartMaterials(weapon, model)
    local slottbl = model.slottbl
    if not istable(slottbl) or type(weapon.GetFinalAttTable) ~= "function" then return nil end
    local ok, atttbl = pcall(weapon.GetFinalAttTable, weapon, slottbl)
    if not ok or not istable(atttbl) then return nil end
    if slottbl.StickerModel and isstring(atttbl.StickerMaterial) then
        local sticker = material(atttbl.StickerMaterial)
        if not sticker then return nil end
        model.NLARC9Sticker = atttbl.StickerMaterial
        return { [0] = sticker, [1] = sticker, [2] = sticker }
    end
    if category(atttbl, "gunscreen") and isfunction(atttbl.DrawFunc) then
        model.NLARC9GunScreen = true
        local screen = material(GUNSCREEN)
        return screen and { [SCREEN_INDEX] = screen } or nil
    end
    return nil
end

-- The models ARC9 itself draws one by one in this DrawCustomModel call (weapons/arc9_base/cl_drawmodel.lua), or nil
-- when it draws none of them: no view model without an owner or for an NPC or a distant player, nothing for a world
-- model while an RT scope renders, and only the base model for a world model at LOD 2 (its parts keep a stale pose).
-- A preset icon (custompos) draws the preset's own models.
local function drawnModels(self, wm, custompos)
    local owner = self:GetOwner()
    local validOwner = IsValid(owner)
    if not wm and not validOwner then return nil end
    local lodOk, lod = pcall(self.ShouldLOD, self)
    lod = lodOk and tonumber(lod) or 0
    local npc = (validOwner and owner:IsNPC()) or lod > 0
    if not wm and npc then return nil end
    if wm and ARC9.RTScopeRender then return nil end
    local world = wm or custompos -- ARC9: "if custompos then wm = true end", after the checks above
    if world and lod >= 2 then return nil end
    local models = world and (custompos and self.CModel or self.WModel) or self.VModel
    return istable(models) and models or nil
end

-- Wraps DrawCustomModel: dressed parts are skipped by ARC9 (NoDraw for the call) and drawn here afterwards, at the
-- pose ARC9 gave them, with their materials. ARC9's DrawFunc (the gun screen's render target) still runs. Parts
-- ARC9 does not draw in its loop are left to it: animation proxies, charm models (their parent draws them) and
-- translucent parts (its translucent pass draws them).
local sentToPass = {}
function ARC9Patch.DrawCustomModel(original, self, wm, custompos, ...)
    if not cvParts:GetBool() then return original(self, wm, custompos, ...) end
    local models = drawnModels(self, wm, custompos)
    local dressed
    if models then
        for _, model in ipairs(models) do
            if IsValid(model) and not model.NoDraw and not model.IsAnimationProxy and not model.charmparent
                and not model.istranslucent then
                -- ARC9 makes new part models whenever the weapon is customized: the answer is kept on the model.
                local subs = model.NLARC9Subs
                if subs == nil then
                    subs = ARC9Patch.PartMaterials(self, model) or false
                    model.NLARC9Subs = subs
                end
                if subs then
                    dressed = dressed or {}
                    dressed[#dressed + 1] = { model = model, subs = subs }
                    model.NoDraw = true
                end
            end
        end
    end
    if not dressed then return original(self, wm, custompos, ...) end
    local results = { pcall(original, self, wm, custompos, ...) }
    for _, item in ipairs(dressed) do item.model.NoDraw = false end
    for _, item in ipairs(dressed) do
        local model = item.model
        if IsValid(model) and not model.hidden then
            for index, mat in pairs(item.subs) do render.MaterialOverrideByIndex(index, mat) end
            model:DrawModel()
            for index in pairs(item.subs) do render.MaterialOverrideByIndex(index, nil) end
        end
        local sticker = model.NLARC9Sticker
        if sticker and not sentToPass[sticker] and RTXViewModelMaterials and RTXViewModelMaterials.ProcessMaterial then
            sentToPass[sticker] = true
            pcall(RTXViewModelMaterials.ProcessMaterial, sticker)
        end
    end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-- The screen's mesh and its live texture, one function each (the companion caches a model's screen meshes per
-- function: new closures every frame would read the model's meshes again every frame).
local function isGunScreen(name)
    return (string.lower(name):gsub("%.vmt$", "")) == "models/sherrifdoggo/gunscreen/gs_screen"
end
local function gunScreenTexture()
    local screen = material(GUNSCREEN)
    return screen and screen:GetTexture("$basetexture") or nil
end
local function screenProvider(player, weapon)
    if not cvEnabled:GetBool() or not cvParts:GetBool() then return nil end
    if not IsValid(weapon) or not weapon.ARC9 or not istable(weapon.VModel) then return nil end
    local out
    for _, model in ipairs(weapon.VModel) do
        if IsValid(model) and model.NLARC9GunScreen and not model.hidden then
            out = out or {}
            out[#out + 1] = { model = model, screen = isGunScreen, texture = gunScreenTexture }
        end
    end
    return out
end

-- The companion's screen redraw keeps a table that is already there, so the provider is in place whichever of the
-- two loads first.
local function offerScreens()
    NativeLoaderScreens = istable(NativeLoaderScreens) and NativeLoaderScreens or {}
    NativeLoaderScreens.providers = istable(NativeLoaderScreens.providers) and NativeLoaderScreens.providers or {}
    if isfunction(NativeLoaderScreens.Register) then
        NativeLoaderScreens.Register("arc9_gunscreen", screenProvider)
        return "redrawn in 2D"
    end
    NativeLoaderScreens.providers.arc9_gunscreen = screenProvider
    return "offered to the companion's screen redraw"
end

local function patchWeaponTable(tbl, id)
    if type(tbl) ~= "table" or type(tbl.DrawCustomModel) ~= "function" then return false, "no DrawCustomModel" end
    return Patcher.InterceptFunction(tbl, "DrawCustomModel", {
        patchId = "arc9",
        id = id,
        around = ARC9Patch.DrawCustomModel
    })
end

Patcher.RegisterPatch({
    id = "arc9",
    label = "ARC9 Weapon Base",
    side = "client",
    enabled = function() return cvEnabled:GetBool() end,
    depends = ARC9Patch.IsReady,
    apply = function(_, _, context)
        local dxOk, dxErr = ARC9Patch.PatchDirectXWarning()
        if not dxOk then Patcher.Debug("arc9", "DirectX warning not patched: " .. tostring(dxErr)) end
        -- New weapons copy the base's functions when they are made; weapons already made keep their own copies.
        local partsOk, partsErr = patchWeaponTable(context.base, "parts_base")
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent.ARC9 and ent:IsWeapon() then
                patchWeaponTable(ent:GetTable(), "parts_" .. ent:EntIndex())
            end
        end
        local screens = offerScreens()
        Patcher.State.arc9 = {
            dxWarning = dxOk and "hidden" or tostring(dxErr),
            parts = partsOk and "drawn with their materials" or tostring(partsErr),
            screens = screens,
        }
    end,
    retryInterval = 1,
    maxAttempts = 120
})

return ARC9Patch
