-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

-- RTX Remix Flashlight Replacement
-- Replaces the Source engine flashlight with an RTX spotlight that follows the player's view

-- Configuration ConVars
local cv_enabled = CreateClientConVar("rtx_flashlight_enabled", "1", true, false, "Enable RTX flashlight replacement")
local cv_brightness = CreateClientConVar("rtx_flashlight_brightness", "1000", true, false, "Flashlight brightness (0-100)")
local cv_radius = CreateClientConVar("rtx_flashlight_radius", "20", true, false, "Flashlight sphere radius")
local cv_cone_angle = CreateClientConVar("rtx_flashlight_cone_angle", "25", true, false, "Flashlight cone angle in degrees")
local cv_cone_softness = CreateClientConVar("rtx_flashlight_cone_softness", "0.45", true, false, "Flashlight cone edge softness (0-1)")
local cv_color_r = CreateClientConVar("rtx_flashlight_color_r", "255", true, false, "Flashlight red color (0-255)")
local cv_color_g = CreateClientConVar("rtx_flashlight_color_g", "255", true, false, "Flashlight green color (0-255)")
local cv_color_b = CreateClientConVar("rtx_flashlight_color_b", "255", true, false, "Flashlight blue color (0-255)")
local cv_offset_forward = CreateClientConVar("rtx_flashlight_offset_forward", "-5", true, false, "Forward offset from player eyes")
local cv_offset_right = CreateClientConVar("rtx_flashlight_offset_right", "0", true, false, "Right offset from player eyes")
local cv_offset_up = CreateClientConVar("rtx_flashlight_offset_up", "0", true, false, "Up offset from player eyes")
local cv_volumetric = CreateClientConVar("rtx_flashlight_volumetric", "0.0", true, false, "Volumetric intensity multiplier")
local cv_debug = CreateClientConVar("rtx_flashlight_debug", "0", true, false, "Show debug info")

-- Automatic brightness (ADR 0208): the light follows the distance of what its beam lands on, so a
-- wall up close is not blown out and a far one does not go dark. Brightness stays the level at the
-- normal distance; rtx_flashlight_auto 0 leaves the light as it was before.
local cv_auto = CreateClientConVar("rtx_flashlight_auto", "1", true, false, "Adjust the flashlight's brightness to the distance of what it lights (0 = fixed brightness)")
local cv_auto_strength = CreateClientConVar("rtx_flashlight_auto_strength", "0.8", true, false, "Automatic brightness: how much of the change with distance it makes up (0-1)")
local cv_auto_distance = CreateClientConVar("rtx_flashlight_auto_distance", "256", true, false, "Automatic brightness: the distance at which Brightness applies unchanged")
local cv_auto_max = CreateClientConVar("rtx_flashlight_auto_max", "8", true, false, "Automatic brightness: the most it brightens the light for far surfaces")

-- The distance maths, shared with the dance light of the character motion importer (a copy there).
local LightGain = include("remixlua/cl/remixapi/cl_remix_light_gain.lua")
if not istable(LightGain) then LightGain = nil end

-- State tracking
local flashlightActive = false
local flashlightLightId = nil

-- Multiplayer: Track all player flashlights
local playerFlashlights = {} -- [player] = { active = bool, lightId = number, color = Color() }

local function DebugPrint(...)
    if cv_debug:GetBool() then
        print("[RTX Flashlight]", ...)
    end
end

-- Reusable tables to avoid GC stutter
local _vec_pos = { x = 0, y = 0, z = 0 }
local _vec_dir = { x = 0, y = 0, z = 0 }
local _vec_rad = { x = 0, y = 0, z = 0 }
local _shaping = { direction = _vec_dir, coneAngleDegrees = 0, coneSoftness = 0, focusExponent = 1.0 }
local _sphere = { position = _vec_pos, radius = 0, shaping = _shaping, volumetricRadianceScale = 0 }
local _base = { hash = 0, radiance = _vec_rad, isDynamic = true, ignoreViewModel = true }

local function vec3(x, y, z)
    return { x = x, y = y, z = z }
end

-- Defined below; CreateFlashlight and UpdateFlashlight call it.
local DestroyFlashlight
-- Defined below with the cached settings; CreateFlashlight calls them (ADR 0208).
local UpdateCachedSettings, MeasureAutoGain

-- Create the RTX flashlight light for any player
local function CreateFlashlight(ply, colorOverride)
    if not cv_enabled:GetBool() then return false end
    if not istable(RemixLight) then
        DebugPrint("RemixLight API not available")
        return false
    end
    
    ply = ply or LocalPlayer()
    if not IsValid(ply) then return false end
    
    -- R19 (the pre-release review's F-03): a second "on" for the same player (the join-time
    -- sync after a broadcast, or a repeated message) replaces the light instead of leaking it
    if playerFlashlights[ply] and playerFlashlights[ply].lightId then
        DestroyFlashlight(ply)
    end
    
    -- Get position and direction
    local eyePos = ply:EyePos()
    local eyeAngles = ply:EyeAngles()
    local forward = eyeAngles:Forward()
    local right = eyeAngles:Right()
    local up = eyeAngles:Up()
    
    -- Apply offset
    local offsetPos = eyePos
        + forward * cv_offset_forward:GetFloat()
        + right * cv_offset_right:GetFloat()
        + up * cv_offset_up:GetFloat()
    
    -- ADR 0208: automatic brightness measures where the beam lands now, so the light comes on at its
    -- level there instead of flashing at the fixed one first.
    UpdateCachedSettings()
    local autoGain, autoDistance = MeasureAutoGain(ply, eyePos, offsetPos, forward, right, up)

    -- Get color and brightness
    -- Use color override if provided (from network), otherwise use ConVars for local player
    local brightness = cv_brightness:GetFloat()
    local scale = brightness / 1000.0 * (autoGain or 1)
    local r, g, b
    if colorOverride then
        r = colorOverride.r * scale
        g = colorOverride.g * scale
        b = colorOverride.b * scale
    else
        r = math.Clamp(cv_color_r:GetInt(), 0, 255) * scale
        g = math.Clamp(cv_color_g:GetInt(), 0, 255) * scale
        b = math.Clamp(cv_color_b:GetInt(), 0, 255) * scale
    end
    
    -- Create light definition
    local hash = tonumber(util.CRC("rtx_flashlight_" .. ply:EntIndex())) or 99999
    local base = {
        hash = hash,
        radiance = vec3(r, g, b),
        isDynamic = true,
        ignoreViewModel = true,  -- Don't light view models
    }
    
    local sphere = {
        position = vec3(offsetPos.x, offsetPos.y, offsetPos.z),
        radius = cv_radius:GetFloat(),
        shaping = {
            direction = vec3(forward.x, forward.y, forward.z),
            coneAngleDegrees = cv_cone_angle:GetFloat(),
            coneSoftness = cv_cone_softness:GetFloat(),
            focusExponent = 1.0,
        },
        -- A boost lights far surfaces, not the haze beside the player (ADR 0208)
        volumetricRadianceScale = cv_volumetric:GetFloat() / math.max(1, autoGain or 1),
    }
    
    -- Create directly
    local lightId = nil
    if RemixLight.CreateSphere then
        lightId = RemixLight.CreateSphere(base, sphere, ply:EntIndex())
    end
    
    if lightId and lightId ~= 0 then
        -- Track for local player separately
        if ply == LocalPlayer() then
            flashlightLightId = lightId
            flashlightActive = true
        end
        
        -- Store the color used
        local storedColor = colorOverride or Color(
            cv_color_r:GetInt(),
            cv_color_g:GetInt(),
            cv_color_b:GetInt()
        )
        
        -- Track in multiplayer table
        playerFlashlights[ply] = {
            active = true,
            lightId = lightId,
            color = storedColor,
            hash = hash,
            -- Automatic brightness's state (ADR 0208): the gain now, the one it eases to, the distance
            gain = autoGain,
            target = autoGain,
            distance = autoDistance,
        }
        
        DebugPrint("Flashlight created for player", ply:Nick(), "with ID:", lightId)
        return true
    else
        DebugPrint("Failed to create flashlight")
        return false
    end
end

-- Cached settings (only read ConVars when they change)
local cachedSettings = {
    brightness = 15,
    radius = 80,
    coneAngle = 35,
    coneSoftness = 0.3,
    volumetric = 2.0,
    offsetForward = 10,
    offsetRight = 5,
    offsetUp = -3,
    auto = false,
    autoStrength = 0.8,
    autoDistance = 256,
    autoMax = 8,
    -- Below any CurTime, so the first call reads the ConVars even at the very start of a map.
    lastUpdate = -1,
}

local SETTINGS_CACHE_TIME = 0.1 -- Update cache every 0.1 seconds

UpdateCachedSettings = function()
    local currentTime = CurTime()
    if currentTime - cachedSettings.lastUpdate < SETTINGS_CACHE_TIME then return end
    
    cachedSettings.brightness = cv_brightness:GetFloat()
    cachedSettings.radius = cv_radius:GetFloat()
    cachedSettings.coneAngle = cv_cone_angle:GetFloat()
    cachedSettings.coneSoftness = cv_cone_softness:GetFloat()
    cachedSettings.volumetric = cv_volumetric:GetFloat()
    cachedSettings.offsetForward = cv_offset_forward:GetFloat()
    cachedSettings.offsetRight = cv_offset_right:GetFloat()
    cachedSettings.offsetUp = cv_offset_up:GetFloat()
    cachedSettings.auto = LightGain ~= nil and cv_auto:GetBool()
    cachedSettings.autoStrength = cv_auto_strength:GetFloat()
    cachedSettings.autoDistance = cv_auto_distance:GetFloat()
    cachedSettings.autoMax = cv_auto_max:GetFloat()
    cachedSettings.lastUpdate = currentTime
end

-- Automatic brightness (ADR 0208) -------------------------------------------------------------------
local AUTO_MIN_GAIN = 1 / 64
local AUTO_FALL, AUTO_RISE = 0.08, 0.6 -- seconds: it dims within a few frames and brightens gently
local AUTO_REMOTE_INTERVAL = 0.1 -- another player's light is measured ten times a second
local AUTO_RING = 6 -- directions around the beam's axis
local AUTO_WEIGHTS = { 2, 1, 1, 1, 1, 1, 1 } -- the axis counts twice
local _auto_samples, _auto_out, _auto_filter = {}, {}, {}
local _auto_dir, _auto_side, _auto_end = Vector(0, 0, 0), Vector(0, 0, 0), Vector(0, 0, 0)
local _auto_trace = { endpos = _auto_end, mask = MASK_OPAQUE_AND_NPCS, filter = _auto_filter, output = _auto_out }
local _auto_ring, _auto_ring_angle

-- What automatic brightness wants for a light at origin shining along forward. Seven traces across
-- the beam start at the eyes (the light itself sits behind them, maybe inside a wall) and are
-- measured from the light; together they make one distance in which near hits count most, as a near
-- wall does on the screen. Glass, grates and water let them through, as they let the light through.
-- Returns the gain that keeps that distance as bright as the normal one, and the distance; nothing
-- when automatic brightness is off or no trace told anything.
MeasureAutoGain = function(ply, eyePos, origin, forward, right, up)
    if not LightGain or not cachedSettings.auto then return nil end
    local reference = math.max(1, cachedSettings.autoDistance)
    local strength = math.Clamp(cachedSettings.autoStrength, 0, 1)
    local maxGain = math.max(1, cachedSettings.autoMax)
    local near = math.max(1, cachedSettings.radius)
    -- No farther than where the gain reaches its maximum: beyond that nothing changes.
    local reach = reference
    if strength > 0 then reach = reference * maxGain ^ (1 / (2 * strength)) * 1.25 end
    reach = math.Clamp(reach, 512, 8192)
    local angle = math.Clamp(cachedSettings.coneAngle * 0.5, 2, 20)
    if angle ~= _auto_ring_angle then
        _auto_ring, _auto_ring_angle = LightGain.Ring(angle, AUTO_RING), angle
    end
    _auto_trace.start = eyePos
    -- Not the player, nor the vehicle they sit in (and the car a seat is parented to): its own hull
    -- would read as a wall up close and dim the light to nothing.
    _auto_filter[1], _auto_filter[2], _auto_filter[3] = ply, nil, nil
    if ply.InVehicle and ply:InVehicle() then
        local vehicle = ply:GetVehicle()
        if IsValid(vehicle) then
            _auto_filter[2] = vehicle
            local parent = vehicle:GetParent()
            if IsValid(parent) then _auto_filter[3] = parent end
        end
    end
    for i, c in ipairs(_auto_ring) do
        _auto_dir:Set(forward) _auto_dir:Mul(c[1])
        _auto_side:Set(right) _auto_side:Mul(c[2]) _auto_dir:Add(_auto_side)
        _auto_side:Set(up) _auto_side:Mul(c[3]) _auto_dir:Add(_auto_side)
        _auto_end:Set(_auto_dir) _auto_end:Mul(reach) _auto_end:Add(eyePos)
        util.TraceLine(_auto_trace)
        -- A trace that starts inside something (noclip in a wall) tells nothing about the beam.
        _auto_samples[i] = not _auto_out.StartSolid and _auto_out.HitPos:Distance(origin) or false
    end
    local distance = LightGain.EffectiveDistance(_auto_samples, #_auto_ring, AUTO_WEIGHTS, 2, near, reach)
    if not distance then return nil end
    return LightGain.Target(distance, reference, strength, 2, near, AUTO_MIN_GAIN, maxGain), distance
end

-- The light's gain this frame: measured every frame for your own light and ten times a second for
-- another player's, then eased toward, down within a few frames and up over about a second, so a
-- surface that comes close never flashes and a flickering measurement does not pump the light.
local lastAutoReport = 0
local function AutoGain(ply, flashData, eyePos, origin, forward, right, up)
    if not LightGain or not cachedSettings.auto then
        flashData.gain, flashData.target, flashData.distance = nil, nil, nil
        return 1
    end
    local now = RealTime()
    local own = ply == LocalPlayer()
    if own or not flashData.nextMeasure or now >= flashData.nextMeasure then
        flashData.nextMeasure = now + AUTO_REMOTE_INTERVAL
        local target, distance = MeasureAutoGain(ply, eyePos, origin, forward, right, up)
        if target then flashData.target, flashData.distance = target, distance end
    end
    if not flashData.target then return flashData.gain or 1 end
    flashData.gain = LightGain.Smooth(flashData.gain, flashData.target, RealFrameTime(), AUTO_FALL, AUTO_RISE)
    if own and cv_debug:GetBool() and now - lastAutoReport >= 1 then
        lastAutoReport = now
        DebugPrint(string.format("automatic brightness: beam at %.0f units, gain %.3f (easing to %.3f)",
            flashData.distance or 0, flashData.gain, flashData.target))
    end
    return flashData.gain
end

-- Update the RTX flashlight position and direction for a specific player
local function UpdateFlashlight(ply, posOverride, angOverride)
    ply = ply or LocalPlayer()
    
    local flashData = playerFlashlights[ply]
    if not flashData or not flashData.active or not flashData.lightId then return end
    if not istable(RemixLight) then return end
    if not IsValid(ply) then 
        -- Player is invalid, destroy the light
        DestroyFlashlight(ply)
        return 
    end
    
    -- Get current position and direction
    -- Use overrides if provided (for local player camera lock), otherwise calculate from entity
    local eyePos, eyeAngles
    if posOverride and angOverride then
        eyePos = posOverride
        eyeAngles = angOverride
    else
        eyePos = ply:EyePos()
        eyeAngles = ply:EyeAngles()
    end

    local forward = eyeAngles:Forward()
    local right = eyeAngles:Right()
    local up = eyeAngles:Up()
    
    -- Apply offset using cached settings
    local offsetPos = eyePos
        + forward * cachedSettings.offsetForward
        + right * cachedSettings.offsetRight
        + up * cachedSettings.offsetUp
    
    -- Get color and brightness
    -- Use stored color for this player, with current brightness settings, times automatic
    -- brightness's gain (ADR 0208; 1 when it is off)
    local gain = AutoGain(ply, flashData, eyePos, offsetPos, forward, right, up)
    local scale = cachedSettings.brightness / 1000.0 * gain
    local playerColor = flashData.color or Color(255, 240, 200)
    local r = playerColor.r * scale
    local g = playerColor.g * scale
    local b = playerColor.b * scale
    
    -- Update reusable tables
    _vec_rad.x = r
    _vec_rad.y = g
    _vec_rad.z = b
    
    _base.hash = flashData.hash or (tonumber(util.CRC("rtx_flashlight_" .. ply:EntIndex())) or 99999)
    -- _base.radiance is already _vec_rad
    _base.isDynamic = true -- Flashlight moves every frame, must be dynamic to avoid cache thrashing/ghosting
    
    _vec_pos.x = offsetPos.x
    _vec_pos.y = offsetPos.y
    _vec_pos.z = offsetPos.z
    
    _vec_dir.x = forward.x
    _vec_dir.y = forward.y
    _vec_dir.z = forward.z
    
    _shaping.coneAngleDegrees = cachedSettings.coneAngle
    _shaping.coneSoftness = cachedSettings.coneSoftness
    -- _shaping.direction is already _vec_dir
    
    _sphere.radius = cachedSettings.radius
    -- A boost lights far surfaces, not the haze beside the player: the haze stays at its set level
    -- (ADR 0208). Dimming dims it too.
    _sphere.volumetricRadianceScale = cachedSettings.volumetric / math.max(1, gain)
    -- _sphere.position is already _vec_pos
    -- _sphere.shaping is already _shaping
    
    -- Update directly
    if RemixLight.UpdateSphere then
        RemixLight.UpdateSphere(_base, _sphere, flashData.lightId)
    end
end

-- Destroy the RTX flashlight for a specific player
DestroyFlashlight = function(ply)
    ply = ply or LocalPlayer()
    
    local flashData = playerFlashlights[ply]
    if not flashData or not flashData.lightId then return end
    
    local lightIdToDestroy = flashData.lightId
    
    -- Set inactive FIRST to stop any pending updates
    flashData.active = false
    
    -- Update local player tracking
    if ply == LocalPlayer() then
        flashlightActive = false
        flashlightLightId = nil
    end
    
    -- Destroy directly
    if istable(RemixLight) and RemixLight.DestroyLight then
        RemixLight.DestroyLight(lightIdToDestroy)
    end
    
    playerFlashlights[ply] = nil
    
    DebugPrint("Flashlight destroyed for player", IsValid(ply) and ply:Nick() or "invalid", "ID:", lightIdToDestroy)
end

-- Toggle flashlight on/off for local player
local function ToggleFlashlight()
    if not cv_enabled:GetBool() then
        print("[RTX Flashlight] Disabled - enable with rtx_flashlight_enabled 1")
        return
    end
    
    -- Send toggle request to server for multiplayer sync with color data
    net.Start("rtx_flashlight_toggle")
    net.WriteUInt(cv_color_r:GetInt(), 8)
    net.WriteUInt(cv_color_g:GetInt(), 8)
    net.WriteUInt(cv_color_b:GetInt(), 8)
    net.SendToServer()
    
    -- Play sound locally (will be synced with server response)
    LocalPlayer():EmitSound("items/flashlight1.wav", 50, 100, 1, CHAN_ITEM)
end

-- RenderScene hook for low-latency updates
hook.Add("PreRender", "RTXFlashlight_Update", function(origin, angles, fov)
    -- Update cached settings periodically
    UpdateCachedSettings()
    
    local localPly = LocalPlayer()
    local useCamera = IsValid(localPly) and not localPly:ShouldDrawLocalPlayer()

    -- Update all active player flashlights
    for ply, flashData in pairs(playerFlashlights) do
        if IsValid(ply) and flashData.active then
            -- For local player in first person, use exact camera transform to prevent jitter
            if ply == localPly and useCamera then
                UpdateFlashlight(ply, origin, angles)
            else
                UpdateFlashlight(ply)
            end
        else
            -- Clean up invalid players
            if not IsValid(ply) then
                playerFlashlights[ply] = nil
            end
        end
    end
end)

-- Network: Receive flashlight state updates from server
net.Receive("rtx_flashlight_state", function()
    local ply = net.ReadEntity()
    local state = net.ReadBool()
    local r = net.ReadUInt(8)
    local g = net.ReadUInt(8)
    local b = net.ReadUInt(8)
    
    if not IsValid(ply) then return end
    
    if state then
        -- Turn on flashlight for this player with their color
        CreateFlashlight(ply, Color(r, g, b))
    else
        -- Turn off flashlight for this player
        DestroyFlashlight(ply)
    end
end)

-- Network: Receive color update from server (real-time adjustment)
net.Receive("rtx_flashlight_update_color", function()
    local ply = net.ReadEntity()
    local r = net.ReadUInt(8)
    local g = net.ReadUInt(8)
    local b = net.ReadUInt(8)
    
    if not IsValid(ply) then return end
    
    local flashData = playerFlashlights[ply]
    if flashData and flashData.active then
        -- Update stored color
        flashData.color = Color(r, g, b)
        -- Light will update on next frame via RenderScene hook
    end
end)

-- Cleanup on map change
hook.Add("OnReloaded", "RTXFlashlight_Cleanup", function()
    -- Clean up all player flashlights
    for ply, _ in pairs(playerFlashlights) do
        DestroyFlashlight(ply)
    end
    playerFlashlights = {}
end)

hook.Add("ShutDown", "RTXFlashlight_Cleanup", function()
    -- Clean up all player flashlights
    for ply, _ in pairs(playerFlashlights) do
        DestroyFlashlight(ply)
    end
    playerFlashlights = {}
end)

-- Console commands
concommand.Add("rtx_flashlight_toggle", function()
    ToggleFlashlight()
end, nil, "Toggle RTX flashlight on/off (bind this to a key)")

concommand.Add("rtx_flashlight_on", function()
    if not cv_enabled:GetBool() then
        print("[RTX Flashlight] Disabled - enable with rtx_flashlight_enabled 1")
        return
    end
    
    if not flashlightActive then
        net.Start("rtx_flashlight_toggle")
        net.WriteUInt(cv_color_r:GetInt(), 8)
        net.WriteUInt(cv_color_g:GetInt(), 8)
        net.WriteUInt(cv_color_b:GetInt(), 8)
        net.SendToServer()
        LocalPlayer():EmitSound("items/flashlight1.wav", 50, 100, 1, CHAN_ITEM)
    end
end, nil, "Turn RTX flashlight on")

concommand.Add("rtx_flashlight_off", function()
    if flashlightActive then
        net.Start("rtx_flashlight_toggle")
        net.WriteUInt(cv_color_r:GetInt(), 8)
        net.WriteUInt(cv_color_g:GetInt(), 8)
        net.WriteUInt(cv_color_b:GetInt(), 8)
        net.SendToServer()
        LocalPlayer():EmitSound("items/flashlight1.wav", 50, 100, 1, CHAN_ITEM)
    end
end, nil, "Turn RTX flashlight off")

concommand.Add("rtx_flashlight_reload", function()
    if flashlightActive then
        DestroyFlashlight()
        timer.Simple(0.1, function()
            CreateFlashlight()
        end)
        print("[RTX Flashlight] Reloaded")
    else
        print("[RTX Flashlight] Not active")
    end
end, nil, "Reload the flashlight")

-- Debug visualization
hook.Add("PostDrawTranslucentRenderables", "RTXFlashlight_Debug", function(depth, sky)
    if not cv_debug:GetBool() then return end
    if not flashlightActive then return end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local eyePos = ply:EyePos()
    local eyeAngles = ply:EyeAngles()
    local forward = eyeAngles:Forward()
    local right = eyeAngles:Right()
    local up = eyeAngles:Up()
    
    local offsetPos = eyePos
        + forward * cv_offset_forward:GetFloat()
        + right * cv_offset_right:GetFloat()
        + up * cv_offset_up:GetFloat()
    
    -- Draw debug beam
    render.SetMaterial(Material("cable/physbeam"))
    render.DrawBeam(offsetPos, offsetPos + forward * 512, 2, 0, 1, Color(255, 255, 0, 200))
    
    -- Draw position marker
    render.DrawWireframeSphere(offsetPos, cv_radius:GetFloat() * 0.1, 8, 8, Color(255, 255, 0, 150))

    -- Where automatic brightness found the beam to land (ADR 0208)
    local flashData = playerFlashlights[ply]
    if flashData and flashData.distance then
        render.DrawWireframeSphere(offsetPos + forward * flashData.distance, 6, 8, 8, Color(0, 255, 255, 200))
    end
end)

-- Tool menu integration
hook.Add("PopulateToolMenu", "RTXFlashlight_Menu", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix - API Lights", "Flashlight", NL("Flashlight"), "", "", function(panel)
        panel:ClearControls()
        
        panel:Help(NL("Light Properties"))
        panel:NumSlider(NL("Brightness"), "rtx_flashlight_brightness", 0, 100000, 1)
        panel:NumSlider(NL("Radius"), "rtx_flashlight_radius", 1, 200, 0)
        panel:NumSlider(NL("Cone Angle"), "rtx_flashlight_cone_angle", 5, 90, 0)
        panel:NumSlider(NL("Cone Softness"), "rtx_flashlight_cone_softness", 0, 1, 2)
        panel:NumSlider(NL("Volumetric Scale"), "rtx_flashlight_volumetric", 0, 5, 1)

        -- ADR 0208
        panel:Help(NL("Automatic Brightness"))
        panel:CheckBox(NL("Adjust brightness to distance"), "rtx_flashlight_auto")
        panel:ControlHelp(NL("Keeps what the flashlight lights evenly bright: dimmer up close, brighter far away. Brightness is the level at the normal distance."))
        panel:NumSlider(NL("Strength"), "rtx_flashlight_auto_strength", 0, 1, 2)
        panel:NumSlider(NL("Normal Distance"), "rtx_flashlight_auto_distance", 32, 2048, 0)
        panel:NumSlider(NL("Max Boost"), "rtx_flashlight_auto_max", 1, 16, 1)

        panel:Help(NL("Color"))
        
        -- Color picker
        local colorPicker = vgui.Create("DColorMixer", panel)
        colorPicker:SetPalette(true)
        colorPicker:SetAlphaBar(false)
        colorPicker:SetWangs(true)
        colorPicker:SetColor(Color(
            cv_color_r:GetInt(),
            cv_color_g:GetInt(),
            cv_color_b:GetInt()
        ))
        
        -- Update ConVars when color changes
        colorPicker.ValueChanged = function(self, col)
            RunConsoleCommand("rtx_flashlight_color_r", tostring(col.r))
            RunConsoleCommand("rtx_flashlight_color_g", tostring(col.g))
            RunConsoleCommand("rtx_flashlight_color_b", tostring(col.b))
        end
        
        panel:AddItem(colorPicker)

        panel:Help(NL("Position Offset"))
        panel:NumSlider(NL("Forward Offset"), "rtx_flashlight_offset_forward", -100, 100, 0)
        panel:NumSlider(NL("Right Offset"), "rtx_flashlight_offset_right", -100, 100, 0)
        panel:NumSlider(NL("Up Offset"), "rtx_flashlight_offset_up", -100, 100, 0)

        local btnReset = panel:Button(NL("Reset"), "")
        btnReset.DoClick = function()
            RunConsoleCommand("rtx_flashlight_brightness", "1000")
            RunConsoleCommand("rtx_flashlight_radius", "20")
            RunConsoleCommand("rtx_flashlight_cone_angle", "25")
            RunConsoleCommand("rtx_flashlight_cone_softness", "0.45")
            RunConsoleCommand("rtx_flashlight_color_r", "255")
            RunConsoleCommand("rtx_flashlight_color_g", "255")
            RunConsoleCommand("rtx_flashlight_color_b", "255")
            RunConsoleCommand("rtx_flashlight_offset_forward", "-5")
            RunConsoleCommand("rtx_flashlight_offset_right", "0")
            RunConsoleCommand("rtx_flashlight_offset_up", "0")
            RunConsoleCommand("rtx_flashlight_volumetric", "0.0")
            RunConsoleCommand("rtx_flashlight_auto", "1")
            RunConsoleCommand("rtx_flashlight_auto_strength", "0.8")
            RunConsoleCommand("rtx_flashlight_auto_distance", "256")
            RunConsoleCommand("rtx_flashlight_auto_max", "8")
        end
    end)
end)

-- Real-time color update when ConVars change
local lastColorUpdate = 0
local COLOR_UPDATE_DELAY = 0.05 -- Throttle to 20 updates per second max

local function SendColorUpdate()
    local currentTime = CurTime()
    if currentTime - lastColorUpdate < COLOR_UPDATE_DELAY then return end
    
    -- Only send if our flashlight is active
    if not flashlightActive then return end
    
    lastColorUpdate = currentTime
    
    -- Send color update to server
    net.Start("rtx_flashlight_update_color")
    net.WriteUInt(cv_color_r:GetInt(), 8)
    net.WriteUInt(cv_color_g:GetInt(), 8)
    net.WriteUInt(cv_color_b:GetInt(), 8)
    net.SendToServer()
    
    -- Update local flashlight color immediately
    local flashData = playerFlashlights[LocalPlayer()]
    if flashData then
        flashData.color = Color(cv_color_r:GetInt(), cv_color_g:GetInt(), cv_color_b:GetInt())
    end
end

-- Add ConVar change callbacks for real-time updates
cvars.AddChangeCallback("rtx_flashlight_color_r", SendColorUpdate, "rtx_flashlight_color_update")
cvars.AddChangeCallback("rtx_flashlight_color_g", SendColorUpdate, "rtx_flashlight_color_update")
cvars.AddChangeCallback("rtx_flashlight_color_b", SendColorUpdate, "rtx_flashlight_color_update")   