--[[
    View model materials (R24, the native-loader project).

    The material pipeline sweeps the map at load and an entity's materials when the entity is created. A weapon's
    view model is one entity for the whole life: its model changes with every weapon switch. Weapon bases (ARC9,
    TFA and the SWEP Construction Kit, CW 2.0, ArcCW) also draw attachments, stickers and charms as client-side
    models whose sub-materials are set after they are made. None of those reached the Lua fixers or the
    auto-categorisation, so an ARC9 sticker drew without its decal offset (z-fighting on the receiver), and so on.

    This checks the local player's view models, hands and the active weapon's attachment models twice a second and
    sends every material it has not seen yet through the same stages: the Lua fixers (RTXMaterialPipeline), the
    BlueFlyTrap fix and the auto-categorisation (decal, emissive, particle). Each material once per session.
]]
if not CLIENT then return end
if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end

local cvEnabled = CreateClientConVar("rtx_viewmodel_materials", "1", true, false,
    "Send view model and weapon attachment materials through the RTX material pipeline")

RTXViewModelMaterials = RTXViewModelMaterials or {}
local VMM = RTXViewModelMaterials

local seen = {}
local entityKeys = setmetatable({}, { __mode = "k" })
local stats = { materials = 0, entities = 0, checks = 0 }
local MAX_MATERIALS = 4096 -- a bound for a session that cycles through very many weapons

local function process(name)
    if not isstring(name) or name == "" then return end
    name = string.lower(name)
    if seen[name] or stats.materials >= MAX_MATERIALS then return end
    seen[name] = true
    stats.materials = stats.materials + 1
    if RTXMaterialPipeline and RTXMaterialPipeline.ProcessMaterial then
        pcall(RTXMaterialPipeline.ProcessMaterial, name)
    end
    if RTXFixBFT and RTXFixBFT.ProcessMaterial then
        pcall(RTXFixBFT.ProcessMaterial, name)
    end
    if RemixCategoryManager and RemixCategoryManager.AutoCategorizeMaterial then
        pcall(RemixCategoryManager.AutoCategorizeMaterial, name)
    end
end

-- Weapon-base patches send materials the pass cannot read from an entity (a client-side model's sub-materials
-- read back empty), such as ARC9's stickers.
VMM.ProcessMaterial = process

-- The sub-material indices that can change what an entity draws: one per material of its model (at most 32). The
-- key and the pass read the same ones, so a change at any of them sends the entity through again.
local function lastIndex(materials)
    return math.min(31, math.max(#materials, 1) - 1)
end

-- The entity's model and its overrides, as one string: a change sends the entity through again.
local function entityKey(ent, materials)
    local parts = { ent:GetModel() or "", ent:GetMaterial() or "" }
    for i = 0, lastIndex(materials) do
        local sub = ent:GetSubMaterial(i)
        if sub ~= "" then parts[#parts + 1] = i .. "=" .. sub end
    end
    return table.concat(parts, "|")
end

local function processEntity(ent)
    if not IsValid(ent) then return end
    local materials = ent:GetMaterials() or {}
    local key = entityKey(ent, materials)
    if entityKeys[ent] == key then return end
    entityKeys[ent] = key
    stats.entities = stats.entities + 1
    for _, name in ipairs(materials) do process(name) end
    for i = 0, lastIndex(materials) do
        local sub = ent:GetSubMaterial(i)
        if sub ~= "" then process(sub) end
    end
    local override = ent:GetMaterial()
    if override ~= "" then process(override) end
end

-- Attachment models of the weapon bases that draw them as client-side models.
function VMM.AttachmentModels(wep, out)
    out = out or {}
    if not IsValid(wep) then return out end
    if istable(wep.VModel) then -- ARC9: attachments, stickers, and charms hanging from them
        for _, model in ipairs(wep.VModel) do
            if IsValid(model) then
                out[#out + 1] = model
                if IsValid(model.charmmdl) then out[#out + 1] = model.charmmdl end
            end
        end
    end
    if istable(wep.VElements) then -- TFA (curmodel), the SWEP Construction Kit (modelEnt)
        for _, element in pairs(wep.VElements) do
            if istable(element) then
                if IsValid(element.curmodel) then out[#out + 1] = element.curmodel end
                if IsValid(element.modelEnt) then out[#out + 1] = element.modelEnt end
            end
        end
    end
    if istable(wep.AttachmentModelsVM) then -- CW 2.0
        for _, element in pairs(wep.AttachmentModelsVM) do
            if istable(element) and IsValid(element.ent) then out[#out + 1] = element.ent end
        end
    end
    if wep.ArcCW and istable(wep.VM) then -- ArcCW
        for _, element in pairs(wep.VM) do
            if istable(element) and IsValid(element.Model) then out[#out + 1] = element.Model end
        end
    end
    return out
end

function VMM.Check()
    if not cvEnabled:GetBool() then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    stats.checks = stats.checks + 1
    for index = 0, 2 do processEntity(ply:GetViewModel(index)) end
    processEntity(ply:GetHands())
    for _, model in ipairs(VMM.AttachmentModels(ply:GetActiveWeapon())) do processEntity(model) end
end

function VMM.GetStats()
    return { materials = stats.materials, entities = stats.entities, checks = stats.checks }
end

timer.Create("RTXViewModelMaterials", 0.5, 0, function()
    local ok, err = pcall(VMM.Check)
    if not ok then
        ErrorNoHalt("[RTX ViewModel] check failed: " .. tostring(err) .. "\n")
    end
end)

concommand.Add("rtx_viewmodel_materials_status", function()
    print("[RTX ViewModel] " .. util.TableToJSON(VMM.GetStats()))
end, nil, "Show how many view model and attachment materials went through the material pipeline")
