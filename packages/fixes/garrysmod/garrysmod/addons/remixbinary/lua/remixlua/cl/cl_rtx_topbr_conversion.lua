-- RTX Remix ToPBR Material Converter
-- Automatically converts Source Engine material properties to PBR materials in RTX Remix.
--
-- This module uses MaterialPipeline.ToPBR C++ module to:
-- - Read VTF texture files from Source Engine filesystem
-- - Extract pixel data and convert to Remix-compatible format
-- - Upload textures via RemixAPI CreateTexture
-- - Create PBR materials with proper roughness/metallic values
--
-- Console Commands:
-- - rtx_topbr_process - Process all tracked materials
-- - rtx_topbr_inspect <material> - Inspect a material's PBR properties
-- - rtx_topbr_stats - Show conversion statistics
-- - rtx_topbr_clear - Clear conversion cache
-- - rtx_topbr_debug <0/1> - Enable debug output
-- - rtx_topbr_help - Show help

if SERVER then return end

if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end

-- ConVars for configuration
-- NOTE: Material discovery is handled by RTXMaterialPipeline. ToPBR only processes individual materials.
CreateClientConVar("rtx_topbr_enabled", "0", true, false, "Enable ToPBR conversion stage")
-- The user's request of 2026-11-16 (the native loader's ADR 0229): what ToPBR converts. The native converter reads it
-- itself; while it is 0 or 1 it takes only the materials this file names (see "The player's range" below).
CreateClientConVar("rtx_topbr_scope", "0", true, false, "What ToPBR converts: 0 the map's own surfaces (default), 1 the map's surfaces and props, 2 everything it can convert")
CreateClientConVar("rtx_topbr_debug", "0", true, false, "Enable debug output")
CreateClientConVar("rtx_topbr_metallic", "0", true, false, "Compatibility flag; metallic comes only from authored maps or unmasked chrome")
CreateClientConVar("rtx_topbr_autodiscover", "1", true, false, "Auto-discover companion textures (_normal, _mask, _spec) not explicitly referenced in VMT")
CreateClientConVar("rtx_topbr_parse_commented_properties", "0", true, false, "Parse commented-out VMT properties (e.g., //$envmap) - useful for maps where they were disabled for vanilla Source")

-- Module table
RTXToPBR = RTXToPBR or {}

-- Initialization state
local isInitialized = false

--[[
    Safe ConVar access helpers
]]--
local function GetConVarBoolSafe(name, default)
    local cv = GetConVar(name)
    if cv then return cv:GetBool() end
    return default or false
end

local function GetConVarFloatSafe(name, default)
    local cv = GetConVar(name)
    if cv then return cv:GetFloat() end
    return default or 0
end

--[[
    Debug print helper
]]--
local function DebugPrint(...)
    if GetConVarBoolSafe("rtx_topbr_debug", false) then
        MsgC(Color(200, 200, 255), "[RTX ToPBR] ", Color(255, 255, 255), ...)
        MsgC(Color(255, 255, 255), "\n")
    end
end

--[[
    Initialize the MaterialPipeline.ToPBR C++ module
]]--
function RTXToPBR.Initialize()
    if isInitialized then
        return true
    end
    
    -- Check if MaterialPipeline.ToPBR is available (from C++ module)
    local processor = MaterialPipeline and MaterialPipeline.ToPBR
    if not processor then
        MsgC(Color(255, 100, 100), "[RTX ToPBR] MaterialPipeline.ToPBR not available - C++ module not loaded\n")
        return false
    end
    
    -- Helper to sync all ConVars to C++
    local function SyncConVarsToProcessor()
        if processor.SetEnabled then
            processor.SetEnabled(GetConVarBoolSafe("rtx_topbr_enabled", false))
        end
        processor.SetDebugOutput(GetConVarBoolSafe("rtx_topbr_debug", false))
        if processor.SetMetallicGeneration then
            processor.SetMetallicGeneration(GetConVarBoolSafe("rtx_topbr_metallic", false))
        end
        if processor.SetAutoDiscover then
            processor.SetAutoDiscover(GetConVarBoolSafe("rtx_topbr_autodiscover", true))
        end
        if processor.SetParseCommentedProperties then
            processor.SetParseCommentedProperties(GetConVarBoolSafe("rtx_topbr_parse_commented_properties", false))
        end
    end
    
    -- Check if already initialized by C++ (during RemixAPI init)
    if processor.IsInitialized and processor.IsInitialized() then
        isInitialized = true
        MsgC(Color(100, 255, 100), "[RTX ToPBR] MaterialPipeline.ToPBR already initialized by C++\n")
        SyncConVarsToProcessor()
        return true
    end
    
    -- Initialize the C++ converter (fallback if not already done)
    local success = processor.Initialize()
    if not success then
        MsgC(Color(255, 100, 100), "[RTX ToPBR] Failed to initialize MaterialPipeline.ToPBR\n")
        return false
    end
    
    SyncConVarsToProcessor()
    
    isInitialized = true
    MsgC(Color(100, 255, 100), "[RTX ToPBR] Initialized successfully\n")
    return true
end

-- Helper to get the processor (MaterialPipeline.ToPBR)
local function GetProcessor()
    return MaterialPipeline and MaterialPipeline.ToPBR
end

-- NOTE: Material discovery and continuous processing is handled by RTXMaterialPipeline.
-- ToPBR only provides ProcessMaterial(name) for the pipeline to call.
-- The functions below are utilities for inspection and configuration.

--[[
    Get material from what the player is looking at (trace)
]]--
function RTXToPBR.GetMaterialFromTrace()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil, nil end
    
    local tr = ply:GetEyeTrace()
    if not tr.Hit then return nil, nil end
    
    -- Try to get material from entity first (models)
    if IsValid(tr.Entity) and tr.Entity:GetClass() ~= "worldspawn" then
        local ent = tr.Entity
        local materials = ent:GetMaterials()
        if materials and #materials > 0 then
            -- Return first material and entity info
            return materials[1], {
                type = "entity",
                entity = ent,
                class = ent:GetClass(),
                model = ent:GetModel(),
                allMaterials = materials
            }
        end
    end
    
    -- Fall back to brush/world material
    if tr.HitTexture and tr.HitTexture ~= "" and tr.HitTexture ~= "**empty**" then
        return tr.HitTexture, {
            type = "brush",
            hitPos = tr.HitPos,
            hitNormal = tr.HitNormal
        }
    end
    
    return nil, nil
end

--[[
    Inspect a specific material's PBR properties
]]--
function RTXToPBR.InspectMaterial(materialName)
    if not materialName or materialName == "" then
        MsgC(Color(255, 200, 100), "Usage: RTXToPBR.InspectMaterial(materialName)\n")
        return nil
    end
    
    if not RTXToPBR.Initialize() then
        return nil
    end
    
    local processor = GetProcessor()
    local props = processor.InspectMaterial(materialName)
    
    MsgC(Color(100, 200, 255), string.format("\n[RTX ToPBR] Material: %s\n", materialName))
    MsgC(Color(100, 200, 255), string.rep("=", 70) .. "\n")
    
    if not props then
        MsgC(Color(255, 100, 100), "  Failed to load material\n")
        return nil
    end
    
    -- =========================================================================
    -- Detected Format (most important info first!)
    -- =========================================================================
    local formatColor = Color(200, 200, 200)
    local formatStr = props.detectedFormat or "Source Engine (Standard)"
    
    if props.isExoPBR then
        formatColor = Color(100, 255, 200)
    elseif props.isGPBR then
        formatColor = Color(200, 100, 255)
    elseif props.isMWBPBR then
        formatColor = Color(150, 255, 150)
        formatStr = "MWB PBR Gen (Modern Warfare Base)"
    elseif props.isBFTPseudoPBR then
        formatColor = Color(255, 200, 100)
    end
    
    MsgC(formatColor, string.format("  ★ Detected Format: %s\n", formatStr))
    MsgC(Color(150, 150, 150), string.format("  Shader: %s\n", props.shaderName or "(unknown)"))
    
    -- =========================================================================
    -- Base Textures
    -- =========================================================================
    MsgC(Color(100, 200, 255), "\n  --- Textures ---\n")
    MsgC(Color(200, 200, 200), string.format("  Base Texture: %s\n", props.baseTexture or "(none)"))
    
    -- Bumpmap/Normal
    if props.hasBumpMap then
        local ssbumpStr = ""
        if props.isSSBump then
            ssbumpStr = " [SSBump→Normal]"
        end
        MsgC(Color(100, 255, 100), string.format("  ✓ Bumpmap: %s%s\n", props.bumpMap, ssbumpStr))
    else
        MsgC(Color(255, 200, 100), "  ✗ Bumpmap: (none)\n")
    end
    
    -- Phong exponent texture
    if props.hasPhongExponentTexture then
        MsgC(Color(100, 255, 100), string.format("  ✓ Phong Exponent Texture: %s\n", props.phongExponentTexture))
    end
    
    -- Envmap mask
    if props.hasEnvMapMask then
        MsgC(Color(100, 255, 100), string.format("  ✓ Envmap Mask: %s\n", props.envMapMask))
    end
    
    -- =========================================================================
    -- Format-specific info
    -- =========================================================================
    if props.isExoPBR then
        MsgC(Color(100, 255, 200), "\n  --- ExoPBR Format ---\n")
        if props.hasARMTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ ARM Texture: %s\n", props.armTexture))
        end
        if props.hasExoNormal then
            MsgC(Color(100, 255, 100), string.format("  ✓ ExoPBR Normal: %s\n", props.exoNormal))
        end
        if props.hasEmissionTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ Emission: %s\n", props.emissionTexture))
        end
    end
    
    if props.isGPBR then
        MsgC(Color(200, 100, 255), "\n  --- GPBR (Strata) Format ---\n")
        if props.hasMRAOTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ MRAO Texture: %s\n", props.mraoTexture))
        end
        if props.hasGPBREmission then
            MsgC(Color(100, 255, 100), string.format("  ✓ Emission: %s\n", props.gpbrEmission))
        end
    end
    
    if props.isMWBPBR then
        MsgC(Color(150, 255, 150), "\n  --- MWB PBR Gen Format ---\n")
        MsgC(Color(200, 200, 200), "  MWB encoding uses $phongexponenttexture for PBR data:\n")
        if props.hasBFTExponentTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ Exponent Texture: %s\n", props.bftExponentTexture))
            MsgC(Color(150, 150, 150), "    Red channel: pow(gloss, 4.0) → roughness via pow^0.25\n")
            MsgC(Color(150, 150, 150), "    Green channel: metallic value (direct)\n")
            MsgC(Color(150, 150, 150), "    Alpha channel: roughness for rimlight\n")
        end
        if props.hasBaseTexture then
            MsgC(Color(150, 150, 150), "  Base texture alpha may contain metallic mask\n")
        end
        MsgC(Color(200, 200, 200), "  Note: MWB converts PBR textures to Source Engine phong workflow\n")
    end
    
    if props.isBFTPseudoPBR then
        MsgC(Color(255, 200, 100), "\n  --- PseudoPBR (BlueFlyTrap/MWB) ---\n")
        if props.hasBFTExponentTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ Exponent Texture (roughness): %s\n", props.bftExponentTexture))
        end
        if props.isBFTMetallicLayer then
            MsgC(Color(255, 200, 100), "  ! Metallic Layer ($translucent + $phongalbedotint)\n")
        end
        if props.isBFTDiffuseLayer then
            MsgC(Color(255, 200, 100), "  ! Diffuse Layer (uses $blendTintByBaseAlpha)\n")
        end
        if props.hasBFTBlendTintByBaseAlpha then
            MsgC(Color(255, 150, 100), "  ! $blendTintByBaseAlpha detected (alpha = metallic mask)\n")
        end
        if props.hasBFTColor2 and props.bftColor2 then
            MsgC(Color(200, 200, 200), string.format("  $color2: [%.2f %.2f %.2f]\n", 
                props.bftColor2.r or 0, props.bftColor2.g or 0, props.bftColor2.b or 0))
        end
    end
    
    -- =========================================================================
    -- Auto-discovered textures
    -- =========================================================================
    local hasDiscovered = props.hasDiscoveredNormal or props.hasDiscoveredHeight or 
                          props.hasDiscoveredMask or props.hasDiscoveredAO
    if hasDiscovered then
        MsgC(Color(100, 200, 255), "\n  --- Auto-Discovered Textures ---\n")
        if props.hasDiscoveredNormal then
            MsgC(Color(100, 255, 100), string.format("  ✓ Normal: %s\n", props.discoveredNormal))
        end
        if props.hasDiscoveredHeight then
            MsgC(Color(100, 255, 100), string.format("  ✓ Height: %s\n", props.discoveredHeight))
        end
        if props.hasDiscoveredMask then
            MsgC(Color(100, 255, 100), string.format("  ✓ Mask/Spec: %s\n", props.discoveredMask))
        end
        if props.hasDiscoveredAO then
            MsgC(Color(100, 255, 100), string.format("  ✓ AO: %s\n", props.discoveredAO))
        end
    end
    
    -- =========================================================================
    -- Roughness Sources
    -- =========================================================================
    MsgC(Color(100, 200, 255), "\n  --- Roughness Sources ---\n")
    local roughnessSource = "Default (0.5)"
    
    if props.hasPhongExponentTexture then
        roughnessSource = "Phong Exponent Texture (best)"
    elseif props.normalMapAlphaEnvMapMask and props.hasBumpMap then
        roughnessSource = "Normal Map Alpha ($normalmapalphaenvmapmask)"
    elseif props.hasBaseAlphaEnvMapMask then
        roughnessSource = "Base Texture Alpha ($basealphaenvmapmask)"
    elseif props.hasBaseMapAlphaPhongMask then
        roughnessSource = "Base Texture Alpha ($basemapalphaphongmask)"
    elseif props.hasEnvMapMask then
        roughnessSource = "Envmap Mask Texture"
    elseif props.hasDiscoveredMask then
        roughnessSource = "Auto-discovered Mask/Spec"
    elseif props.hasPhong then
        roughnessSource = string.format("Phong Exponent (%.1f)", props.phongExponent or 0)
    end
    
    MsgC(Color(200, 200, 200), string.format("  Source: %s\n", roughnessSource))
    
    -- =========================================================================
    -- Calculated PBR Values
    -- =========================================================================
    MsgC(Color(100, 200, 255), "\n  --- Calculated PBR Values ---\n")
    MsgC(Color(200, 200, 200), string.format("  Roughness: %.2f\n", props.roughness or 0.5))
    MsgC(Color(200, 200, 200), string.format("  Metallic: %.2f\n", props.metallic or 0))
    
    if props.hasBaseTextureBrightness then
        MsgC(Color(150, 150, 150), string.format("  Base Texture Brightness: %.2f\n", props.baseTextureBrightness or 0))
    end
    
    -- =========================================================================
    -- Envmap Properties
    -- =========================================================================
    if props.hasEnvMap or props.hasEnvMapTint then
        MsgC(Color(100, 200, 255), "\n  --- Environment Map ---\n")
        if props.hasEnvMap then
            MsgC(Color(100, 255, 100), "  ✓ Has Envmap\n")
        end
        if props.hasEnvMapTint and props.envMapTint then
            MsgC(Color(200, 200, 200), string.format("  $envmaptint: [%.2f %.2f %.2f]\n", 
                props.envMapTint.r or 0, props.envMapTint.g or 0, props.envMapTint.b or 0))
        end
        if props.hasEnvMapContrast then
            MsgC(Color(200, 200, 200), string.format("  $envmapcontrast: %.2f\n", props.envMapContrast or 1))
        end
        if props.hasEnvMapSaturation then
            MsgC(Color(200, 200, 200), string.format("  $envmapsaturation: %.2f\n", props.envMapSaturation or 1))
        end
    end
    
    -- =========================================================================
    -- Phong Properties
    -- =========================================================================
    if props.hasPhong or props.hasPhongFresnelRanges or props.hasRimLight then
        MsgC(Color(100, 200, 255), "\n  --- Phong/Specular ---\n")
        if props.hasPhong then
            MsgC(Color(200, 200, 200), string.format("  Exponent: %.1f\n", props.phongExponent or 0))
        end
        if props.phongBoost and props.phongBoost > 0 then
            MsgC(Color(200, 200, 200), string.format("  Boost: %.2f\n", props.phongBoost))
        end
        if props.hasPhongFresnelRanges and props.phongFresnelRanges then
            MsgC(Color(200, 200, 200), string.format("  Fresnel: [%.2f %.2f %.2f]\n", 
                props.phongFresnelRanges[1] or 0, props.phongFresnelRanges[2] or 0, props.phongFresnelRanges[3] or 0))
        end
        if props.hasRimLight then
            MsgC(Color(200, 200, 200), string.format("  Rim Light: exp=%.1f boost=%.2f\n", 
                props.rimLightExponent or 0, props.rimLightBoost or 0))
        end
    end
    
    -- =========================================================================
    -- Material Flags
    -- =========================================================================
    local hasFlags = props.isSelfIllum or props.isTranslucent or props.isGlass
    if hasFlags then
        MsgC(Color(100, 200, 255), "\n  --- Flags ---\n")
        if props.isSelfIllum then
            MsgC(Color(255, 200, 100), "  ! Self-illuminated (emissive)\n")
            if props.hasSelfIllumMask then
                MsgC(Color(150, 150, 150), string.format("    Mask: %s\n", props.selfIllumMask))
            end
        end
        if props.isTranslucent then
            MsgC(Color(255, 200, 100), "  ! Translucent material\n")
        end
        if props.isGlass then
            MsgC(Color(100, 200, 255), "  ✓ GLASS MATERIAL (RTX Translucent shader, IOR 1.5)\n")
        end
    end
    
    -- =========================================================================
    -- Surface Properties
    -- =========================================================================
    if props.surfaceProp and props.surfaceProp ~= "" then
        MsgC(Color(100, 200, 255), "\n  --- Surface ---\n")
        MsgC(Color(150, 150, 150), string.format("  Surface Prop: %s\n", props.surfaceProp))
    end
    
    -- Parallax
    if props.hasParallaxMap then
        MsgC(Color(100, 200, 255), "\n  --- Parallax ---\n")
        MsgC(Color(100, 255, 100), string.format("  ✓ Parallax Map: %s\n", props.parallaxMap))
    end
    
    MsgC(Color(100, 200, 255), string.rep("=", 70) .. "\n\n")
    
    return props
end

--[[
    Get conversion statistics
]]--
function RTXToPBR.GetStats()
    local processor = GetProcessor()
    if not processor then
        return {
            materialsProcessed = 0,
            texturesUploaded = 0,
            materialsWithNormals = 0,
            materialsWithRoughness = 0,
            failedConversions = 0
        }
    end
    
    return processor.GetStats()
end

--[[
    Clear conversion cache
]]--
local gameAssets, gameKey, gameParts, gameSlot, gameSubmitted, gameNext = nil, nil, nil, 1, {}, 0
-- R23: submitted materials whose native view still says "waiting", and how many this batch had.
local gamePending, gamePendingCount, gameBatchTotal = {}, 0, 0
function RTXToPBR.ClearCache()
    local processor = GetProcessor()
    if processor then
        processor.ClearCache()
    end
    gameAssets, gameKey, gameParts, gameSlot, gameSubmitted, gameNext = nil, nil, nil, 1, {}, 0
    gamePending, gamePendingCount, gameBatchTotal = {}, 0, 0
    MsgC(Color(100, 255, 100), "[RTX ToPBR] Cache cleared\n")
end

--[[
    Set debug output
]]--
function RTXToPBR.SetDebugOutput(enabled)
    local processor = GetProcessor()
    if processor then
        processor.SetDebugOutput(enabled)
    end
end

-- NOTE: Continuous processing (StartContinuousProcessing, StopContinuousProcessing, IsContinuousProcessing)
-- has been REMOVED. All material discovery and continuous processing is now handled by RTXMaterialPipeline.
-- Use rtx_mat_continuous and rtx_mat_continuous_interval convars to control pipeline processing.

-- Console Commands
concommand.Add("rtx_topbr_inspect", function(ply, cmd, args)
    if not args[1] or args[1] == "" then
        -- No material specified - try to get from what player is looking at
        local matName, traceInfo = RTXToPBR.GetMaterialFromTrace()
        
        if not matName then
            MsgC(Color(255, 200, 100), "Usage: rtx_topbr_inspect [material_name]\n")
            MsgC(Color(255, 200, 100), "  If no material specified, looks at what you're aiming at.\n")
            MsgC(Color(255, 200, 100), "Example: rtx_topbr_inspect concrete/concretefloor001a\n")
            return
        end
        
        -- Show trace info
        if traceInfo then
            if traceInfo.type == "entity" then
                MsgC(Color(100, 200, 255), string.format("[RTX ToPBR] Looking at entity: %s\n", traceInfo.class or "unknown"))
                if traceInfo.model then
                    MsgC(Color(150, 150, 150), string.format("  Model: %s\n", traceInfo.model))
                end
                if traceInfo.allMaterials and #traceInfo.allMaterials > 1 then
                    MsgC(Color(150, 150, 150), string.format("  Entity has %d materials. Showing first one.\n", #traceInfo.allMaterials))
                    MsgC(Color(150, 150, 150), "  All materials:\n")
                    for i, mat in ipairs(traceInfo.allMaterials) do
                        MsgC(Color(120, 120, 120), string.format("    [%d] %s\n", i, mat))
                    end
                end
            elseif traceInfo.type == "brush" then
                MsgC(Color(100, 200, 255), "[RTX ToPBR] Looking at brush/world surface\n")
            end
        end
        
        RTXToPBR.InspectMaterial(matName)
    else
        RTXToPBR.InspectMaterial(args[1])
    end
end, nil, "Inspect a material's PBR properties. If no material specified, inspects what you're looking at.")

concommand.Add("rtx_topbr_stats", function()
    local stats = RTXToPBR.GetStats()
    MsgC(Color(100, 200, 255), "[RTX ToPBR] Conversion Statistics:\n")
    MsgC(Color(200, 200, 200), string.format("  Materials processed: %d\n", stats.materialsProcessed or 0))
    MsgC(Color(200, 200, 200), string.format("  Textures uploaded: %d\n", stats.texturesUploaded or 0))
    MsgC(Color(200, 200, 200), string.format("  Materials with normals: %d\n", stats.materialsWithNormals or 0))
    MsgC(Color(200, 200, 200), string.format("  Materials with roughness: %d\n", stats.materialsWithRoughness or 0))
    MsgC(Color(200, 200, 200), string.format("  Failed conversions: %d\n", stats.failedConversions or 0))
    
    print(string.format("[RTX ToPBR] max client snapshot %.3f ms, max worker job %.3f ms", stats.snapshotMaxMs or 0, stats.decodeMaxMs or 0))

    -- ADR 0229: the player's range and how many material names the native converter holds for it.
    local scopeProcessor = GetProcessor()
    if scopeProcessor and scopeProcessor.GetScope then
        local restricted, held, setting = scopeProcessor.GetScope()
        local ranges = {[0] = "the map's own surfaces", [1] = "the map's surfaces and props", [2] = "everything"}
        print(string.format("[RTX ToPBR] range: rtx_topbr_scope %d (%s), %s, %d material names held",
            setting or 0, ranges[setting or 0] or "the map's own surfaces", restricted and "restricted" or "unrestricted", held or 0))
    end

    -- Background processing status
    local p = GetProcessor()
    local isProcessing = p and p.IsProcessingInBackground and p.IsProcessingInBackground() or false
    local queuedCount = p and p.GetQueuedMaterialCount and p.GetQueuedMaterialCount() or 0
    local lastProcessed = p and p.GetLastProcessedCount and p.GetLastProcessedCount() or 0
    
    MsgC(Color(100, 200, 255), "\n  Background Processing:\n")
    if isProcessing then
        MsgC(Color(100, 255, 100), string.format("  ✓ ACTIVE - %d materials in queue, %d processed this run\n", queuedCount, lastProcessed))
    else
        MsgC(Color(200, 200, 200), string.format("  Idle - %d processed in last run\n", lastProcessed))
    end
    

end, nil, "Show PBR conversion statistics")

concommand.Add("rtx_topbr_clear", function()
    RTXToPBR.ClearCache()
end, nil, "Clear PBR conversion cache")

-- These are convars, not commands with the same name (Source refuses duplicates).
for _, pair in ipairs({{"rtx_topbr_debug", "SetDebugOutput"},
    {"rtx_topbr_metallic", "SetMetallicGeneration"},
    {"rtx_topbr_autodiscover", "SetAutoDiscover"},
    {"rtx_topbr_parse_commented_properties", "SetParseCommentedProperties"}}) do
    cvars.AddChangeCallback(pair[1], function(_, _, value)
        local p = GetProcessor()
        if p and p[pair[2]] then p[pair[2]](tobool(value)) end
    end, "RTXToPBR_" .. pair[1])
end

hook.Add("Think", "RTXToPBR_Snapshots", function()
    local p = GetProcessor()
    if p and p.PumpSnapshots then p.PumpSnapshots() end
end)

concommand.Add("rtx_topbr_process", function()
    local p = GetProcessor()
    if RTXToPBR.EnsureScope then RTXToPBR.EnsureScope() end
    if p and p.QueueMaterialsForProcessing then p.QueueMaterialsForProcessing() end
end)

concommand.Add("rtx_topbr_help", function()
    MsgC(Color(100, 200, 255), "\n[RTX ToPBR] Runtime PBR Material Converter\n")
    MsgC(Color(100, 200, 255), string.rep("=", 70) .. "\n")
    MsgC(Color(255, 255, 255), [[
This module converts Source Engine materials to PBR materials in RTX Remix.
It is experimental and off by default: rtx_topbr_enabled 1 (Map and prop PBR
in the RTX Remix menu) turns it on. It writes rtx-remix/mods/~gmod_topbr,
which Remix ranks after every other mod, so a real PBR mod for a texture
always wins over it. Characters imported with the Model Hotloader use
Imported game PBR (rtx_topbr_game_maps) instead.

What it converts is rtx_topbr_scope: 0 the map's own surfaces (walls,
floors, ceilings, displacements, brush entities; the default), 1 also the
map's props, 2 everything it can convert.

Materials are found by RTXMaterialPipeline (cl_material_pipeline.lua) as
they are drawn; turning ToPBR on also queues the materials already drawn.
The console line "Published N fallback materials" says how many show.

ToPBR Configuration Commands:
  rtx_topbr_inspect [material] - Inspect material's PBR properties
                                 (no argument = look at what you're aiming at)
  rtx_topbr_stats             - Show conversion statistics and the range
  rtx_topbr_scope 0/1/2       - Map surfaces / with props / everything
  rtx_topbr_clear             - Clear conversion cache
  rtx_topbr_debug 1/0         - Enable/disable debug output
  rtx_topbr_metallic 1/0      - Compatibility flag (darkness inference removed)
  rtx_topbr_autodiscover 1/0  - Enable/disable auto-discovery of 
                                companion textures (_normal, _mask, _spec)
  rtx_topbr_parse_commented_properties 1/0
                              - Enable/disable parsing of commented-out
                                VMT properties (e.g., //"$envmap")
  rtx_topbr_help              - Show this help

SUPPORTED PBR FORMATS:
- ExoPBR (screenspace_general_8tex shader with ARM textures)
- GPBR/Strata ("PBR" shader with MRAO textures)
- PseudoPBR (BlueFlyTrap/MWB phong-based PBR encoding)
- Standard Source Engine materials (phong, envmap, etc.)

Roughness Priority (phong materials are handled first):
1. $phongexponenttexture (best quality)
2. $basemapalphaphongmask / $normalmapalphaenvmapmask
3. $envmapmask texture
4. Auto-discovered _mask/_spec textures
5. Base texture alpha with envmap

Note: Dark envmap materials (chrome balls, etc.) use low roughness
for reflections by default. Darkness alone no longer makes a material metallic. Explicit community
PBR channels and unmasked chrome remain supported.

]])
    MsgC(Color(100, 200, 255), string.rep("=", 60) .. "\n\n")
end, nil, "Show ToPBR help information")

-- =============================================================================
-- The player's range (the user's request of 2026-11-16, the native loader's ADR 0229)
-- =============================================================================
-- rtx_topbr_scope 0 (default): the map's own surfaces, every material its BSP names (world brushes, displacements,
-- brush entities, overlays). 1: also the map's props (its static props' models, and the physics, dynamic and door
-- props there are). 2: everything the converter can convert, as before. The native converter reads the setting and,
-- for 0 and 1, takes only the names sent here; a narrower range clears the cache, so what a wider one converted
-- leaves the published layer.
local SCOPE_PROP_CLASSES = {"prop_physics*", "prop_dynamic*", "prop_door*"}
local scopeMap, scopeModels, scopeEntities, scopeNextScan = nil, {}, setmetatable({}, {__mode = "k"}), 0

local function ScopeSetting()
    local cv = GetConVar("rtx_topbr_scope")
    local value = cv and cv:GetInt() or 0
    if value == 1 or value == 2 then return value end
    return 0
end
RTXToPBR.ScopeSetting = ScopeSetting

local function MapSurfaceNames(add)
    local world = game.GetWorld()
    if IsValid(world) then
        for _, name in ipairs(world:GetMaterials() or {}) do add(name) end
    end
    -- The BSP's whole texture list also has the brush entities' and overlays' materials.
    local bsp = NikNaks and NikNaks.CurrentMap
    if bsp and bsp.GetTextures then
        local ok, textures = pcall(bsp.GetTextures, bsp)
        if ok and istable(textures) then
            for _, name in ipairs(textures) do add(name) end
        end
    end
end

local function ModelNames(model, add)
    if not isstring(model) or model == "" or scopeModels[model] then return end
    scopeModels[model] = true
    local names = RTXMaterialPipeline and RTXMaterialPipeline.ModelMaterialNames and RTXMaterialPipeline.ModelMaterialNames(model)
    for _, name in ipairs(names or {}) do add(name) end
end

-- Props: each static prop model once, each prop entity when first seen or when its model changed.
local function PropNames(add)
    local bsp = NikNaks and NikNaks.CurrentMap
    if bsp and bsp.GetStaticPropModels then
        local ok, models = pcall(bsp.GetStaticPropModels, bsp)
        if ok and istable(models) then
            for _, model in ipairs(models) do ModelNames(model, add) end
        end
    end
    for _, pattern in ipairs(SCOPE_PROP_CLASSES) do
        for _, ent in ipairs(ents.FindByClass(pattern)) do
            local model = IsValid(ent) and ent:GetModel() or nil
            if model and scopeEntities[ent] ~= model then
                scopeEntities[ent] = model
                for _, name in ipairs(ent:GetMaterials() or {}) do add(name) end
                for index = 0, 31 do
                    local sub = ent:GetSubMaterial(index)
                    if sub and sub ~= "" then add(sub) end
                end
            end
        end
    end
end

-- Sends the names the range takes (fresh: the native list is emptied first). Returns how many names were sent.
local function SendScope(fresh)
    local p = GetProcessor()
    if not (p and p.AllowScopeMaterials and p.ClearScope) then return 0 end
    if fresh then
        p.ClearScope()
        scopeModels, scopeEntities = {}, setmetatable({}, {__mode = "k"})
        scopeMap = game.GetMap()
    end
    local setting = ScopeSetting()
    if setting == 2 then return 0 end -- every material; the names wait for a narrower range
    local names, seen = {}, {}
    local function add(name)
        if isstring(name) and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    if fresh then MapSurfaceNames(add) end
    if setting == 1 then PropNames(add) end
    if #names > 0 then p.AllowScopeMaterials(names) end
    return #names
end

local function QueueIfEnabled()
    local p = GetProcessor()
    if p and p.QueueMaterialsForProcessing and GetConVarBoolSafe("rtx_topbr_enabled", false) then
        p.QueueMaterialsForProcessing()
    end
end

-- The map's names once per map, before anything is queued.
local function EnsureScope()
    if scopeMap ~= game.GetMap() then SendScope(true) end
end
RTXToPBR.EnsureScope = EnsureScope

hook.Add("InitPostEntity", "RTXToPBR_Scope", function()
    SendScope(true)
    QueueIfEnabled()
    -- NikNaks may read the BSP later than the first frame; its texture list then completes the map's names.
    timer.Simple(10, function()
        if SendScope(true) > 0 then QueueIfEnabled() end
    end)
end)

-- With props in range, new props are named every two seconds.
hook.Add("Think", "RTXToPBR_ScopeProps", function()
    if ScopeSetting() ~= 1 or RealTime() < scopeNextScan then return end
    scopeNextScan = RealTime() + 2
    if scopeMap ~= game.GetMap() then return end
    if SendScope(false) > 0 then QueueIfEnabled() end
end)

cvars.AddChangeCallback("rtx_topbr_scope", function(_, old)
    local before, after = math.Clamp(math.floor(tonumber(old) or 0), 0, 2), ScopeSetting()
    if after < before then RTXToPBR.ClearCache() end
    SendScope(true)
    QueueIfEnabled()
end, "RTXToPBRScope")

-- Sync rtx_topbr_enabled ConVar to C++ when changed at runtime
cvars.AddChangeCallback("rtx_topbr_enabled", function(_, _, new)
    local processor = GetProcessor()
    if processor and processor.SetEnabled then
        processor.SetEnabled(tobool(new))
        -- Issue 6 (ADR 0212): the materials already drawn convert now; no map reload needed.
        if tobool(new) and processor.QueueMaterialsForProcessing then
            EnsureScope()
            processor.QueueMaterialsForProcessing()
        end
    end
end, "RTXToPBREnabled")

-- NOTE: Auto-processing and continuous processing hooks have been REMOVED.
-- All material discovery and processing timing is now handled by RTXMaterialPipeline.
-- ToPBR is called as Stage 3 of the unified pipeline.

-- Startup message
MsgC(Color(100, 255, 100), "[RTX ToPBR] Runtime PBR Converter loaded.\n")
MsgC(Color(200, 200, 200), "  Processing controlled by RTXMaterialPipeline.\n")
if MaterialPipeline and MaterialPipeline.ToPBR then
    MsgC(Color(200, 200, 200), "  C++ MaterialPipeline.ToPBR module available.\n")
    -- Sync enabled state immediately at load time so a saved rtx_topbr_enabled=0
    -- takes effect before the C++ worker thread processes any queued materials
    if MaterialPipeline.ToPBR.SetEnabled then
        MaterialPipeline.ToPBR.SetEnabled(GetConVarBoolSafe("rtx_topbr_enabled", false))
    end
else
    MsgC(Color(255, 200, 100), "  C++ MaterialPipeline.ToPBR module not loaded - waiting for binary module.\n")
end
MsgC(Color(200, 200, 200), "  Use 'rtx_topbr_help' for usage information.\n")


-- The source path is local-only hotloader data; no network or importer hook is needed.
CreateClientConVar("rtx_topbr_game_maps", "1", true, false, "Use shipped packed game PBR maps on imported characters")
local function syncGameMaps()
    local p = GetProcessor()
    if p and p.SetGameEnabled then p.SetGameEnabled(GetConVarBoolSafe("rtx_topbr_game_maps", true)) end
end
cvars.AddChangeCallback("rtx_topbr_game_maps", syncGameMaps, "RTXToPBRGameMaps")
hook.Add("Think", "RTXToPBR_GameMaps", function()
    local p = GetProcessor()
    if not p or not p.QueueGameMaterial then return end
    syncGameMaps()
    if not GetConVarBoolSafe("rtx_topbr_game_maps", true) then return end
    if not gameAssets then
        if RealTime() < gameNext then return end
        gameAssets = mmdhl and mmdhl.assets or {}
        gameKey, gameParts, gameSlot = nil, nil, 1
    end
    for _ = 1, 8 do
        if gameParts and gameParts[gameSlot] then
            local slot = gameSlot
            local part = gameParts[slot]
            gameSlot = slot + 1
            local entry = mmdhl and mmdhl.library and mmdhl.library.entries[gameKey]
            local original = entry and entry.info and entry.info.materials and entry.info.materials[slot]
            local name = istable(part) and part.path
            local source = entry and entry.source
            local base = original and original.base
            if isstring(name) and not gameSubmitted[name] then
                -- Native restores only recorded, validated maps for the live texture identity.
                if p.QueueGameMaterial(name, isstring(source) and source or "", isstring(base) and base or "") then
                    gameSubmitted[name] = true
                    if not gamePending[name] then
                        gamePending[name], gamePendingCount, gameBatchTotal = true, gamePendingCount + 1, gameBatchTotal + 1
                    end
                end
            end
        else
            if gameKey and gameAssets[gameKey] == nil then gameKey = nil end
            local info
            gameKey, info = next(gameAssets, gameKey)
            if not gameKey then
                gameAssets, gameParts, gameNext = nil, nil, RealTime() + 5
                break
            end
            gameParts, gameSlot = istable(info) and info.materials or {}, 1
        end
    end
end)

-- R23 (the user's item 3): how many imported game materials are still converting, for the companion's
-- progress notice. Returns pending, total of the current batch; the batch ends when none is pending.
-- At most 4 calls a second are useful: each pending material is one native view read.
function RTXGamePBRProgress()
    local p = GetProcessor()
    if gamePendingCount > 0 and p and p.GetGameMaterial then
        for name in pairs(gamePending) do
            local ok, view = pcall(p.GetGameMaterial, name)
            if not ok or not istable(view) or view.state ~= "waiting" then
                gamePending[name], gamePendingCount = nil, gamePendingCount - 1
            end
        end
    end
    if gamePendingCount <= 0 then gamePending, gamePendingCount, gameBatchTotal = {}, 0, 0 end
    return gamePendingCount, gameBatchTotal
end

-- BEGIN R12 IMPORTED GAME PBR PANEL
do
-- GPL-2.0. Imported-game PBR choices, shared by the actual base texture.
if SERVER or not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
RTXGamePBRPanel = RTXGamePBRPanel or {}
local P = RTXGamePBRPanel
local i18n = file.Exists("nativeloader/i18n.lua", "LUA") and include("nativeloader/i18n.lua") or nil
-- New panel phrases live in the GPL part; use the bundle catalog first.
local panelPhrases = {
    ["zh-CN"] = {
        ["For characters imported with the Model Hotloader: uses the PBR maps their game shipped beside the model. For maps and props, see Map and prop PBR (ToPBR)."] = "用于通过 Model Hotloader 导入的角色：使用其游戏随模型附带的 PBR 贴图。地图和道具请见“地图和道具 PBR（ToPBR）”。",
        ["Character"] = "角色",
        ["Selected maps use another game layout."] = "所选贴图使用另一种游戏格式。",
        ["Imported game PBR"] = "导入的游戏 PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "看向角色后列出材质。选择适用于所有共用此纹理的角色。",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "手工制作的 Remix 替换优先。脸和眼睛保护仍然有效。",
        ["Select a material"] = "选择材质",
        ["Map family"] = "贴图组",
        ["Normal map"] = "法线贴图",
        ["Packed map"] = "打包贴图",
        ["Emission map"] = "自发光贴图",
        ["Game layout"] = "游戏格式",
        ["List looked-at character"] = "列出所看角色",
        ["Use selected family"] = "使用所选贴图组",
        ["Use individual maps"] = "使用单独贴图",
        ["No game maps for this texture"] = "此纹理不使用游戏贴图",
        ["Return to automatic"] = "恢复自动",
        ["None"] = "无",
        ["waiting"] = "等待中",
        ["automatic"] = "自动",
        ["cached"] = "已缓存",
        ["override"] = "手动覆盖",
        ["none"] = "无",
        ["error"] = "错误",
        ["Each material shows the PBR Remix draws for it: a Remix mod such as a character's PBR pack, an Advanced Material Editor profile, or the game maps set up here."] = "每个材质都显示 Remix 为其绘制的 PBR：Remix 模组（如角色的 PBR 包）、高级材质编辑器配置，或在此设置的游戏贴图。",
        ["Remix mod: %s"] = "Remix 模组：%s",
        ["Advanced Material Editor profile"] = "高级材质编辑器配置",
        ["Game maps: %s"] = "游戏贴图：%s",
        ["Game maps"] = "游戏贴图",
        ["No PBR"] = "无 PBR",
        ["Not drawn yet"] = "尚未绘制",
        ["In effect: %s"] = "当前生效：%s",
        ["Texture hash %s"] = "纹理哈希 %s",
        ["No character: spawn one, or look at one and list it."] = "没有角色：生成一个，或看向一个角色后列出。",
        ["values only"] = "仅数值",
        ["albedo"] = "反照率",
        ["normal"] = "法线",
        ["roughness"] = "粗糙度",
        ["metallic"] = "金属度",
        ["height"] = "高度",
        ["emission"] = "自发光",
    },
    ["zh-TW"] = {
        ["For characters imported with the Model Hotloader: uses the PBR maps their game shipped beside the model. For maps and props, see Map and prop PBR (ToPBR)."] = "用於透過 Model Hotloader 匯入的角色：使用其遊戲隨模型附帶的 PBR 貼圖。地圖和道具請見「地圖和道具 PBR（ToPBR）」。",
        ["Character"] = "角色",
        ["Selected maps use another game layout."] = "所選貼圖使用另一種遊戲格式。",
        ["Imported game PBR"] = "匯入的遊戲 PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "看向角色後列出材質。選擇適用於所有共用此紋理的角色。",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "手工製作的 Remix 替換優先。臉和眼睛保護仍然有效。",
        ["Select a material"] = "選擇材質",
        ["Map family"] = "貼圖組",
        ["Normal map"] = "法線貼圖",
        ["Packed map"] = "打包貼圖",
        ["Emission map"] = "自發光貼圖",
        ["Game layout"] = "遊戲格式",
        ["List looked-at character"] = "列出所看角色",
        ["Use selected family"] = "使用所選貼圖組",
        ["Use individual maps"] = "使用個別貼圖",
        ["No game maps for this texture"] = "此紋理不使用遊戲貼圖",
        ["Return to automatic"] = "恢復自動",
        ["None"] = "無",
        ["waiting"] = "等待中",
        ["automatic"] = "自動",
        ["cached"] = "已快取",
        ["override"] = "手動覆寫",
        ["none"] = "無",
        ["error"] = "錯誤",
        ["Each material shows the PBR Remix draws for it: a Remix mod such as a character's PBR pack, an Advanced Material Editor profile, or the game maps set up here."] = "每個材質都顯示 Remix 為其繪製的 PBR：Remix 模組（如角色的 PBR 包）、高階材質編輯器設定檔，或在此設定的遊戲貼圖。",
        ["Remix mod: %s"] = "Remix 模組：%s",
        ["Advanced Material Editor profile"] = "高階材質編輯器設定檔",
        ["Game maps: %s"] = "遊戲貼圖：%s",
        ["Game maps"] = "遊戲貼圖",
        ["No PBR"] = "無 PBR",
        ["Not drawn yet"] = "尚未繪製",
        ["In effect: %s"] = "目前生效：%s",
        ["Texture hash %s"] = "紋理雜湊 %s",
        ["No character: spawn one, or look at one and list it."] = "沒有角色：生成一個，或看向一個角色後列出。",
        ["values only"] = "僅數值",
        ["albedo"] = "反照率",
        ["normal"] = "法線",
        ["roughness"] = "粗糙度",
        ["metallic"] = "金屬度",
        ["height"] = "高度",
        ["emission"] = "自發光",
    },
    ["ja"] = {
        ["For characters imported with the Model Hotloader: uses the PBR maps their game shipped beside the model. For maps and props, see Map and prop PBR (ToPBR)."] = "Model Hotloader で取り込んだキャラクター用：そのゲームがモデルと一緒に収録している PBR マップを使います。マップとプロップは「マップとプロップの PBR (ToPBR)」を参照してください。",
        ["Character"] = "キャラクター",
        ["Selected maps use another game layout."] = "選択したマップは別のゲーム形式です。",
        ["Imported game PBR"] = "インポートしたゲームの PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "キャラクターを見て材質を一覧表示します。同じテクスチャを使う全キャラクターに適用されます。",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "作成済みの Remix 置換が優先されます。顔と目の保護は有効です。",
        ["Select a material"] = "材質を選択",
        ["Map family"] = "マップの組",
        ["Normal map"] = "法線マップ",
        ["Packed map"] = "パックマップ",
        ["Emission map"] = "発光マップ",
        ["Game layout"] = "ゲーム形式",
        ["List looked-at character"] = "見ているキャラを一覧表示",
        ["Use selected family"] = "選択した組を使用",
        ["Use individual maps"] = "個別のマップを使用",
        ["No game maps for this texture"] = "このテクスチャのゲームマップを無効化",
        ["Return to automatic"] = "自動に戻す",
        ["None"] = "なし",
        ["waiting"] = "待機中",
        ["automatic"] = "自動",
        ["cached"] = "キャッシュ済み",
        ["override"] = "手動設定",
        ["none"] = "なし",
        ["error"] = "エラー",
        ["Each material shows the PBR Remix draws for it: a Remix mod such as a character's PBR pack, an Advanced Material Editor profile, or the game maps set up here."] = "各マテリアルには Remix が描画する PBR が表示されます：Remix MOD（キャラクターの PBR パックなど）、高機能マテリアルエディターのプロファイル、またはここで設定するゲームのマップです。",
        ["Remix mod: %s"] = "Remix MOD：%s",
        ["Advanced Material Editor profile"] = "高機能マテリアルエディターのプロファイル",
        ["Game maps: %s"] = "ゲームのマップ：%s",
        ["Game maps"] = "ゲームのマップ",
        ["No PBR"] = "PBR なし",
        ["Not drawn yet"] = "まだ描画されていません",
        ["In effect: %s"] = "適用中：%s",
        ["Texture hash %s"] = "テクスチャハッシュ %s",
        ["No character: spawn one, or look at one and list it."] = "キャラクターがいません：スポーンするか、キャラクターを見て一覧表示してください。",
        ["values only"] = "数値のみ",
        ["albedo"] = "アルベド",
        ["normal"] = "法線",
        ["roughness"] = "粗さ",
        ["metallic"] = "金属度",
        ["height"] = "高さ",
        ["emission"] = "発光",
    },
    ["ko"] = {
        ["For characters imported with the Model Hotloader: uses the PBR maps their game shipped beside the model. For maps and props, see Map and prop PBR (ToPBR)."] = "Model Hotloader로 가져온 캐릭터용: 게임이 모델 옆에 함께 제공한 PBR 맵을 사용합니다. 맵과 프롭은 '맵과 프롭 PBR (ToPBR)'을 참고하세요.",
        ["Character"] = "캐릭터",
        ["Selected maps use another game layout."] = "선택한 맵은 다른 게임 형식입니다.",
        ["Imported game PBR"] = "가져온 게임 PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "캐릭터를 바라본 뒤 재질을 나열하세요. 같은 텍스처를 쓰는 모든 캐릭터에 적용됩니다.",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "제작된 Remix 교체가 우선합니다. 얼굴과 눈 보호는 유지됩니다.",
        ["Select a material"] = "재질 선택",
        ["Map family"] = "맵 그룹",
        ["Normal map"] = "노멀 맵",
        ["Packed map"] = "패킹 맵",
        ["Emission map"] = "발광 맵",
        ["Game layout"] = "게임 형식",
        ["List looked-at character"] = "바라보는 캐릭터 나열",
        ["Use selected family"] = "선택한 그룹 사용",
        ["Use individual maps"] = "개별 맵 사용",
        ["No game maps for this texture"] = "이 텍스처의 게임 맵 끄기",
        ["Return to automatic"] = "자동으로 복귀",
        ["None"] = "없음",
        ["waiting"] = "대기 중",
        ["automatic"] = "자동",
        ["cached"] = "캐시됨",
        ["override"] = "수동 설정",
        ["none"] = "없음",
        ["error"] = "오류",
        ["Each material shows the PBR Remix draws for it: a Remix mod such as a character's PBR pack, an Advanced Material Editor profile, or the game maps set up here."] = "각 재질에는 Remix가 그리는 PBR이 표시됩니다: Remix 모드(캐릭터의 PBR 팩 등), 고급 재질 편집기 프로필, 또는 여기서 설정한 게임 맵.",
        ["Remix mod: %s"] = "Remix 모드: %s",
        ["Advanced Material Editor profile"] = "고급 재질 편집기 프로필",
        ["Game maps: %s"] = "게임 맵: %s",
        ["Game maps"] = "게임 맵",
        ["No PBR"] = "PBR 없음",
        ["Not drawn yet"] = "아직 그려지지 않음",
        ["In effect: %s"] = "적용 중: %s",
        ["Texture hash %s"] = "텍스처 해시 %s",
        ["No character: spawn one, or look at one and list it."] = "캐릭터 없음: 하나를 스폰하거나, 캐릭터를 바라본 뒤 나열하세요.",
        ["values only"] = "값만",
        ["albedo"] = "알베도",
        ["normal"] = "노멀",
        ["roughness"] = "거칠기",
        ["metallic"] = "금속성",
        ["height"] = "높이",
        ["emission"] = "발광",
    },
    ["fr"] = {
        ["For characters imported with the Model Hotloader: uses the PBR maps their game shipped beside the model. For maps and props, see Map and prop PBR (ToPBR)."] = "Pour les personnages importés avec Model Hotloader : utilise les textures PBR que leur jeu fournit à côté du modèle. Pour les cartes et objets, voir PBR des cartes et objets (ToPBR).",
        ["Character"] = "Personnage",
        ["Selected maps use another game layout."] = "Ces cartes utilisent un autre format de jeu.",
        ["Imported game PBR"] = "PBR des jeux importés",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "Visez un personnage, puis listez ses matériaux. Les choix concernent tous les personnages partageant cette texture.",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "Les remplacements Remix créés ont priorité. La protection du visage et des yeux reste active.",
        ["Select a material"] = "Choisir un matériau",
        ["Map family"] = "Famille de cartes",
        ["Normal map"] = "Carte normale",
        ["Packed map"] = "Carte groupée",
        ["Emission map"] = "Carte émissive",
        ["Game layout"] = "Format du jeu",
        ["List looked-at character"] = "Lister le personnage visé",
        ["Use selected family"] = "Utiliser cette famille",
        ["Use individual maps"] = "Utiliser des cartes séparées",
        ["No game maps for this texture"] = "Aucune carte de jeu pour cette texture",
        ["Return to automatic"] = "Revenir au mode automatique",
        ["None"] = "Aucune",
        ["waiting"] = "en attente",
        ["automatic"] = "automatique",
        ["cached"] = "en cache",
        ["override"] = "personnalisé",
        ["none"] = "aucune",
        ["error"] = "erreur",
        ["Each material shows the PBR Remix draws for it: a Remix mod such as a character's PBR pack, an Advanced Material Editor profile, or the game maps set up here."] = "Chaque matériau indique le PBR que Remix dessine pour lui : un mod Remix comme le pack PBR d'un personnage, un profil de l'Éditeur de matériaux avancé, ou les maps du jeu réglées ici.",
        ["Remix mod: %s"] = "Mod Remix : %s",
        ["Advanced Material Editor profile"] = "Profil de l'Éditeur de matériaux avancé",
        ["Game maps: %s"] = "Maps du jeu : %s",
        ["Game maps"] = "Maps du jeu",
        ["No PBR"] = "Pas de PBR",
        ["Not drawn yet"] = "Pas encore dessiné",
        ["In effect: %s"] = "En vigueur : %s",
        ["Texture hash %s"] = "Hachage de texture %s",
        ["No character: spawn one, or look at one and list it."] = "Aucun personnage : faites-en apparaître un, ou visez-en un et listez-le.",
        ["values only"] = "valeurs seules",
        ["albedo"] = "albédo",
        ["normal"] = "normale",
        ["roughness"] = "rugosité",
        ["metallic"] = "métallique",
        ["height"] = "hauteur",
        ["emission"] = "émission",
    },
    ["ru"] = {
        ["For characters imported with the Model Hotloader: uses the PBR maps their game shipped beside the model. For maps and props, see Map and prop PBR (ToPBR)."] = "Для персонажей, импортированных через Model Hotloader: использует PBR-текстуры, которые их игра поставляет рядом с моделью. Для карт и объектов см. «PBR карт и объектов (ToPBR)».",
        ["Character"] = "Персонаж",
        ["Selected maps use another game layout."] = "Выбранные карты используют другой формат игры.",
        ["Imported game PBR"] = "PBR импортированных игр",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "Посмотрите на персонажа и откройте список материалов. Выбор применяется ко всем персонажам с этой текстурой.",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "Авторские замены Remix имеют приоритет. Защита лица и глаз сохраняется.",
        ["Select a material"] = "Выберите материал",
        ["Map family"] = "Набор карт",
        ["Normal map"] = "Карта нормалей",
        ["Packed map"] = "Упакованная карта",
        ["Emission map"] = "Карта свечения",
        ["Game layout"] = "Формат игры",
        ["List looked-at character"] = "Материалы выбранного персонажа",
        ["Use selected family"] = "Применить набор",
        ["Use individual maps"] = "Применить отдельные карты",
        ["No game maps for this texture"] = "Без игровых карт для этой текстуры",
        ["Return to automatic"] = "Вернуть автоматический выбор",
        ["None"] = "Нет",
        ["waiting"] = "ожидание",
        ["automatic"] = "автоматически",
        ["cached"] = "из кеша",
        ["override"] = "переопределение",
        ["none"] = "нет",
        ["error"] = "ошибка",
        ["Each material shows the PBR Remix draws for it: a Remix mod such as a character's PBR pack, an Advanced Material Editor profile, or the game maps set up here."] = "Для каждого материала показан PBR, который рисует Remix: мод Remix (например, PBR-пакет персонажа), профиль Расширенного редактора материалов или карты игры, настроенные здесь.",
        ["Remix mod: %s"] = "Мод Remix: %s",
        ["Advanced Material Editor profile"] = "Профиль Расширенного редактора материалов",
        ["Game maps: %s"] = "Карты игры: %s",
        ["Game maps"] = "Карты игры",
        ["No PBR"] = "Нет PBR",
        ["Not drawn yet"] = "Ещё не отрисован",
        ["In effect: %s"] = "Действует: %s",
        ["Texture hash %s"] = "Хеш текстуры %s",
        ["No character: spawn one, or look at one and list it."] = "Нет персонажа: создайте его или посмотрите на него и выведите список.",
        ["values only"] = "только значения",
        ["albedo"] = "альбедо",
        ["normal"] = "нормали",
        ["roughness"] = "шероховатость",
        ["metallic"] = "металличность",
        ["height"] = "высота",
        ["emission"] = "свечение",
    },
}
local function L(text)
    local translated = i18n and i18n.A(text) or text
    if translated ~= text then return translated end
    local cv = GetConVar("nativeloader_language")
    local code = cv and cv:GetString() or ""
    if code == "" then local game = GetConVar("gmod_language") code = game and game:GetString() or "en" end
    code = ({zh="zh-CN", ["zh-cn"]="zh-CN", ["zh-tw"]="zh-TW"})[code] or code
    local phrases = panelPhrases[code]
    return phrases and phrases[text] or text
end
local function processor() return MaterialPipeline and MaterialPipeline.ToPBR end
local actionErrors = {}

function P.Materials(ent)
    local id = IsValid(ent) and mmdhl and mmdhl.GetAsset and mmdhl.GetAsset(ent)
    local asset = id and mmdhl.assets and mmdhl.assets[id]
    local entry = id and mmdhl.library and mmdhl.library.entries and mmdhl.library.entries[id]
    local rows = {}
    for slot, part in ipairs(asset and asset.materials or {}) do
        local original = entry and entry.info and entry.info.materials and entry.info.materials[slot] or {}
        if isstring(part.path) then rows[#rows + 1] = {name=part.path, source=entry and entry.source or "",
            base=original.base or "", label=original.name or part.name or original.base or part.path} end
    end
    return rows
end
function P.Targets()
    local targets = {}
    for _, ent in ipairs(mmdhl and mmdhl.Entities and mmdhl.Entities() or {}) do
        if #targets >= 128 then break end
        if IsValid(ent) and not (mmdhl.PresentationSuppressed and mmdhl.PresentationSuppressed(ent)) and #P.Materials(ent) > 0 then
            local id = mmdhl.GetAsset(ent)
            local entry = mmdhl.library and mmdhl.library.entries and mmdhl.library.entries[id]
            local asset = mmdhl.assets[id]
            local label = entry and (entry.name or entry.info and entry.info.name) or asset and asset.name
            if not isstring(label) or label == "" then label = L("Character") end
            if mmdhl.names and mmdhl.names.Display then label = mmdhl.names.Display(label, id) end
            targets[#targets + 1] = {entity=ent, label=label}
        end
    end
    return targets
end
function P.Action(row, action, maps)
    local p = processor()
    if not p or not p.GameMaterialAction or not row then return false end
    maps = maps or {}
    if action == "maps" and p.GetGameMaterial then
        local function path(value) return (value or ""):gsub("\\", "/"):lower() end
        for _, choice in ipairs(p.GetGameMaterial(row.name).choices or {}) do
            if choice.layout ~= (maps.layout or 0) then
                for _, selected in ipairs({maps.normal or "", maps.packed or "", maps.emission or ""}) do
                    if selected ~= "" then
                        for _, known in ipairs({choice.normal or "", choice.packed or "", choice.emission or ""}) do
                            if path(selected) == path(known) then
                                actionErrors[row.name] = L("Selected maps use another game layout.")
                                return false
                            end
                        end
                    end
                end
            end
        end
    end
    actionErrors[row.name] = nil
    return p.GameMaterialAction(row.name, row.source, row.base, action,
        maps.normal or "", maps.packed or "", maps.emission or "", maps.layout or 0)
end
function P.State(row)
    local p = processor()
    local view = p and p.GetGameMaterial and p.GetGameMaterial(row.name) or {state="waiting", identity=""}
    if actionErrors[row.name] then view.error = actionErrors[row.name] end
    return view
end

-- What Remix draws for a material (the user's report of 2026-11-16: the page named only the game maps, so every
-- material of a character whose PBR comes from a Remix mod read "none"): the material's live texture hash, and the mod
-- in rtx-remix/mods that supplies that hash, from the Advanced Material Editor's index of the mods in the runtime's own
-- order (AdvMat.RTX.Enhance.Lookup). A material that has not been drawn has no hash yet.
local MAP_INPUTS = {{"inputs:diffuse_texture", "albedo"}, {"inputs:normalmap_texture", "normal"},
    {"inputs:reflectionroughness_texture", "roughness"}, {"inputs:metallic_texture", "metallic"},
    {"inputs:height_texture", "height"}, {"inputs:emissive_mask_texture", "emission"}}
function P.Effective(row)
    local info = {}
    local remix = RemixMaterial
    if remix and remix.GetTextureHash then
        local ok, number, hex = pcall(remix.GetTextureHash, row.name)
        if ok and (tonumber(number) or 0) ~= 0 and isstring(hex) and hex ~= "" then info.hash = hex end
    end
    local index = AdvMat and AdvMat.RTX and AdvMat.RTX.Enhance
    if not info.hash or not (index and index.Lookup) then return info end
    local ok, look = pcall(index.Lookup, {info.hash})
    local entry = ok and istable(look) and look.effective or nil
    if not entry then return info end
    info.mod, info.own, info.automatic = entry.folder, entry.own == true, entry.automatic == true
    info.maps = {}
    local inputs = istable(entry.material) and istable(entry.material.inputs) and entry.material.inputs or {}
    for _, pair in ipairs(MAP_INPUTS) do
        local opinion = inputs[pair[1]]
        if istable(opinion) and isstring(opinion.asset) and opinion.asset ~= "" then info.maps[#info.maps + 1] = L(pair[2]) end
    end
    return info
end
-- One line for what a material shows under RTX, the group the page's summary counts it in, and for a mod the maps it
-- has (a row puts the source and its maps on lines of their own).
function P.Describe(info, view)
    view = view or {}
    if info.mod and not info.automatic then
        local source = info.own and L("Advanced Material Editor profile") or string.format(L("Remix mod: %s"), info.mod)
        local detail = info.maps and #info.maps > 0 and table.concat(info.maps, ", ") or L("values only")
        return source .. " (" .. detail .. ")", source, detail
    end
    if info.automatic or view.state == "automatic" or view.state == "cached" or view.state == "override" then
        local family = isstring(view.family) and view.family ~= "" and view.family or L(view.state or "automatic")
        return string.format(L("Game maps: %s"), family), L("Game maps")
    end
    if info.hash then return L("No PBR"), L("No PBR") end
    return L("Not drawn yet"), L("Not drawn yet")
end
-- A material's picture for its row: its base texture in an interface material (a model material draws nothing in a
-- 2D image), only for a drawn material, whose texture is loaded already: nothing unseen is loaded for a picture.
local pictures, pictureCount = {}, 0
local function picture(row)
    local known = pictures[row.name]
    if known ~= nil then return known or nil end
    local ok, mat = pcall(Material, row.name)
    local texture = ok and mat and not mat:IsError() and mat:GetTexture("$basetexture")
    if not texture or texture:IsError() then pictures[row.name] = false return nil end
    pictureCount = pictureCount + 1
    local made = CreateMaterial("rtx_gamepbr_picture_" .. pictureCount, "UnlitGeneric", {["$basetexture"] = texture:GetName()})
    pictures[row.name] = made or false
    return made
end
local function entityKey(ent)
    return tostring(ent.EntIndex and ent:EntIndex() or ent) .. ":" .. tostring(ent.GetCreationID and ent:GetCreationID() or 0)
end

function P.Build(panel)
    panel:Clear()
    panel:CheckBox(L("Imported game PBR"), "rtx_topbr_game_maps")
    -- Issue 6 (ADR 0212): which of the two PBR pages is which.
    panel:Help(L("For characters imported with the Model Hotloader: uses the PBR maps their game shipped beside the model. For maps and props, see Map and prop PBR (ToPBR)."))
    panel:Help(L("Look at a character, then list its materials. Choices apply to every character sharing the same texture."))
    panel:Help(L("Authored Remix replacements take priority. Face and eye protection stays active."))
    panel:Help(L("Each material shows the PBR Remix draws for it: a Remix mod such as a character's PBR pack, an Advanced Material Editor profile, or the game maps set up here."))
    local characters = panel:ComboBox(L("Character"))
    local summary = panel:Help("")
    local list = vgui.Create("DScrollPanel", panel)
    list:SetTall(240) panel:AddItem(list)
    local current, selected, signature, family, files = nil, nil, nil, nil, nil
    local rows, rowUpdates = {}, {}
    local status = panel:Help(L("Select a material"))
    local families = panel:ComboBox(L("Map family"))
    local normal = panel:ComboBox(L("Normal map"))
    local packed = panel:ComboBox(L("Packed map"))
    local emission = panel:ComboBox(L("Emission map"))
    local layout = panel:ComboBox(L("Game layout"))
    for i, name in ipairs({"Wuthering Waves", "Endfield", "Silver Palace"}) do layout:AddChoice(name, i-1) end
    layout:ChooseOptionID(1)
    local function lookedAt()
        local ply = LocalPlayer()
        local trace = IsValid(ply) and (ply.GetEyeTraceNoCursor and ply:GetEyeTraceNoCursor() or ply:GetEyeTrace())
        local ent = trace and trace.Entity
        return IsValid(ent) and #P.Materials(ent) > 0 and ent or nil
    end
    local function rebuild(target)
        list:Clear() rows, rowUpdates = {}, {}
        current = IsValid(target) and target or nil
        selected, signature, family, files = nil, nil, nil, nil
        local default, seen
        for _, row in ipairs(P.Materials(current)) do
            rows[#rows + 1] = row
            local button = list:Add("DButton")
            button:Dock(TOP) button:SetTall(64) button:DockMargin(0, 0, 0, 4)
            button:SetText("")
            local image = vgui.Create("DImage", button) image:Dock(LEFT) image:SetWide(60)
            local label = vgui.Create("DLabel", button) label:Dock(FILL) label:DockMargin(6, 0, 0, 0) label:SetWrap(true) label:SetDark(true)
            local pictured = false
            local function update()
                local info = P.Effective(row)
                local text, group, detail = P.Describe(info, P.State(row))
                if info.hash and not pictured then
                    pictured = true
                    local made = picture(row)
                    if made then image:SetMaterial(made) end
                end
                -- Short lines (a wrapped line lost its first letter in the game's labels).
                local lines = {tostring(row.label), detail and group or text}
                if detail then lines[#lines + 1] = detail end
                if info.hash then lines[#lines + 1] = info.hash end
                label:SetText(table.concat(lines, "\n"))
                return info, group
            end
            rowUpdates[#rowUpdates + 1] = update
            local info = update()
            button.DoClick = function()
                selected, signature, family, files = row, nil, nil, nil
                P.Action(row, "options")
            end
            -- The first drawn material, else the first the native view has seen.
            if not default and info.hash then default = button end
            if not seen and (P.State(row).identity or "") ~= "" then seen = button end
        end
        default = default or seen
        if default then default.DoClick() list:ScrollToChild(default) else status:SetText(L("Select a material")) end
        if not current then summary:SetText(L("No character: spawn one, or look at one and list it.")) end
    end
    -- The characters in the game. The spawn menu builds this page once, so the list follows them while it stays
    -- built: a character spawned later appears, a removed one goes, and the page never lists a removed one.
    local targetsKey, filling = nil, false
    local function fillCharacters(prefer)
        local targets = P.Targets()
        local want = IsValid(prefer) and prefer or current
        local keys, index = {}, nil
        for number, target in ipairs(targets) do
            keys[#keys + 1] = entityKey(target.entity) .. "=" .. tostring(target.label)
            if target.entity == want then index = number end
        end
        index = index or (#targets > 0 and 1 or nil)
        local key = table.concat(keys, ",") .. "|" .. tostring(index)
        if key ~= targetsKey then
            targetsKey = key
            filling = true
            characters:Clear()
            for _, target in ipairs(targets) do characters:AddChoice(target.label, target.entity) end
            if index then characters:ChooseOptionID(index) end
            filling = false
        end
        return index and targets[index].entity or nil
    end
    characters.OnSelect = function(_, _, _, target) if not filling then rebuild(target) end end
    -- The character looked at, or the one shown when the eyes are on no character (the spawn menu is usually open).
    local refresh = panel:Button(L("List looked-at character")) refresh.DoClick = function() rebuild(fillCharacters(lookedAt())) end
    families.OnSelect = function(_, _, _, data) family = data if data then layout:ChooseOptionID(data.layout + 1) end end
    local function chosen(combo) local _, data = combo:GetSelected() return data or "" end
    local useFamily = panel:Button(L("Use selected family"))
    useFamily.DoClick = function() if family then P.Action(selected, "maps", family) end end
    local useFiles = panel:Button(L("Use individual maps"))
    useFiles.DoClick = function()
        local _, gameLayout = layout:GetSelected()
        P.Action(selected, "maps", {normal=chosen(normal), packed=chosen(packed), emission=chosen(emission), layout=gameLayout or 0})
    end
    local none = panel:Button(L("No game maps for this texture")) none.DoClick = function() P.Action(selected, "none") end
    local automatic = panel:Button(L("Return to automatic")) automatic.DoClick = function() P.Action(selected, "automatic") end
    local nextPoll = 0
    if not panel.RTXGamePBRThinkInstalled then
        panel.RTXGamePBRThinkInstalled = true
        panel.RTXGamePBRBaseThink = panel.Think
    end
    panel.Think = function(self)
        if self.RTXGamePBRBaseThink then self:RTXGamePBRBaseThink() end
        if RealTime() < nextPoll then return end
        nextPoll = RealTime() + .5
        local wanted = fillCharacters()
        if wanted ~= current then rebuild(wanted) end
        local counts, order = {}, {}
        for _, update in ipairs(rowUpdates) do
            local _, group = update()
            if not counts[group] then counts[group] = 0 order[#order + 1] = group end
            counts[group] = counts[group] + 1
        end
        if current then
            local lines = {}
            for _, group in ipairs(order) do lines[#lines + 1] = string.format("%d × %s", counts[group], group) end
            summary:SetText(table.concat(lines, "\n"))
        end
        if not selected then return end
        local view = P.State(selected)
        local info = P.Effective(selected)
        status:SetText(tostring(selected.label) .. "\n" .. string.format(L("In effect: %s"), (P.Describe(info, view))) .. "\n" ..
            (info.hash and string.format(L("Texture hash %s"), info.hash) or L("Not drawn yet")) .. "\n" ..
            L("Game maps") .. ": " .. L(view.state or "waiting") .. (isstring(view.family) and view.family ~= "" and (" " .. view.family) or "") ..
            (view.error and ("\n" .. view.error) or ""))
        local key = tostring(selected.name) .. ":" .. #(view.choices or {}) .. ":" .. #(view.files or {})
        if signature == key then return end
        signature = key families:Clear() normal:Clear() packed:Clear() emission:Clear()
        for index, choice in ipairs(view.choices or {}) do
            families:AddChoice(choice.name, choice)
            if choice.name == view.family then families:ChooseOptionID(index) end
        end
        for _, combo in ipairs({normal, packed, emission}) do
            combo:AddChoice(L("None"), "")
            for _, path in ipairs(view.files or {}) do combo:AddChoice(path, path) end
            combo:ChooseOptionID(1)
        end
    end
    rebuild(fillCharacters(lookedAt()))
end
hook.Add("PopulateToolMenu", "RTXImportedGamePBR", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix", "RTX_ImportedGamePBR", L("Imported game PBR"), "", "", P.Build)
end)
concommand.Add("rtx_topbr_game_editor", function()
    local frame = vgui.Create("DFrame") frame:SetSize(math.min(620, ScrW()-40), math.min(820, ScrH()-40)) frame:Center()
    P.Frame = frame
    frame:SetTitle(L("Imported game PBR")) frame:MakePopup()
    local scroll = vgui.Create("DScrollPanel", frame) scroll:Dock(FILL)
    local panel = vgui.Create("DForm", scroll) panel:SetName(L("Imported game PBR")) panel:Dock(TOP) P.Build(panel)
end)

end
-- END R12 IMPORTED GAME PBR PANEL

return RTXToPBR
