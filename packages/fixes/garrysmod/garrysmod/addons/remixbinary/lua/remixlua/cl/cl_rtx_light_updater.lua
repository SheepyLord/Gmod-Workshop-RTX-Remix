-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
if not CLIENT then return end
require("niknaks")

local lights
local light_positions -- Cache calculated positions
local known_lights = {} -- Track all lights we've encountered
local all_discovered_lights = {} -- Track ALL lights found from NikNaks and dynamic scanning
local stash
local current_map_name
local showlights = CreateConVar( "rtx_lightupdater_show", 0,  FCVAR_ARCHIVE )
local updatelights = CreateConVar( "rtx_lightupdater", 0,  FCVAR_ARCHIVE )
local debugtext = CreateConVar( "rtx_lightupdater_debug", 0,  FCVAR_ARCHIVE )
local debugmoved = CreateConVar( "rtx_lightupdater_debug_moved", 0,  FCVAR_ARCHIVE )
local debugconsole = CreateConVar( "rtx_lightupdater_debug_console", 1,  FCVAR_ARCHIVE )
local debugmissing = CreateConVar( "rtx_lightupdater_debug_missing", 0,  FCVAR_ARCHIVE )
local forcemove = CreateConVar( "rtx_lightupdater_force_move", 0, FCVAR_NONE )
local dynamicscan = CreateConVar( "rtx_lightupdater_dynamic_scan", 1, FCVAR_ARCHIVE )
local dynamicupdate = CreateConVar( "rtx_lightupdater_dynamic_update", 1, FCVAR_ARCHIVE )
-- 1 draws every light's helper every frame, as before R28; 0 (default) uses the draw list on maps with many
-- lights; -1 on every map (not saved).
local drawall = CreateConVar( "rtx_lightupdater_all", 0, FCVAR_NONE )
-- Set whenever known_lights gains or loses a light: the draw list is built again (R28).
local lights_dirty = true

-- Cached world bounds and helpers (refreshed per map)
local cached_world_min, cached_world_max
local cached_bounds_valid = false
local outside_check_failed = false

-- Precomputed direction sets (built once)
local PRECOMP_SAMPLE_DIRECTIONS = {}
do
    -- Horizontal ring
    for i = 0, 7 do
        local angle = i * 45
        local x = math.cos(math.rad(angle))
        local y = math.sin(math.rad(angle))
        table.insert(PRECOMP_SAMPLE_DIRECTIONS, Vector(x, y, 0):GetNormalized())
    end
    -- Upper hemisphere
    for i = 0, 7 do
        local angle = i * 45
        local x = math.cos(math.rad(angle)) * 0.7
        local y = math.sin(math.rad(angle)) * 0.7
        local z = 0.5
        table.insert(PRECOMP_SAMPLE_DIRECTIONS, Vector(x, y, z):GetNormalized())
    end
    -- Lower hemisphere
    for i = 0, 7 do
        local angle = i * 45
        local x = math.cos(math.rad(angle)) * 0.7
        local y = math.sin(math.rad(angle)) * 0.7
        local z = -0.5
        table.insert(PRECOMP_SAMPLE_DIRECTIONS, Vector(x, y, z):GetNormalized())
    end
end

local PRECOMP_EMERGENCY_DIRECTIONS = {
    Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0),
    Vector(0, 0, 1), Vector(0, 0, -1),
    Vector(1, 1, 0):GetNormalized(), Vector(-1, -1, 0):GetNormalized(),
    Vector(1, -1, 0):GetNormalized(), Vector(-1, 1, 0):GetNormalized()
}

local PRECOMP_TINY_OFFSETS = {
    Vector(0.5, 0, 0), Vector(-0.5, 0, 0), Vector(0, 0.5, 0), Vector(0, -0.5, 0),
    Vector(0, 0, 0.5), Vector(0, 0, -0.5), Vector(0, 0, 0)
}

-- Throttling for dynamic updates
local next_dynamic_update = 0
local dynamic_update_interval = 0.15 -- seconds

local zero_angle = Angle(0, 0, 0)

local function shuffle(tbl)
	for i = #tbl, 2, -1 do
	  local j = math.random(i)
	  tbl[i], tbl[j] = tbl[j], tbl[i]
	end
	return tbl
end

local function TableConcat(t1,t2)
	for i=1,#t2 do
		t1[#t1+1] = t2[i]
	end
	return t1
end

-- Clean up existing model and reset data
local function CleanupModel()
	known_lights = {}
	all_discovered_lights = {}
	lights = nil
	light_positions = nil
    cached_world_min, cached_world_max = nil, nil
    cached_bounds_valid = false
    outside_check_failed = false
end

-- Generate unique ID for a light based on its position and type
local function GetLightID(light)
	if not light.origin then return nil end
	
	-- For dynamic entities, use entity index for more stable ID
	if light.entity and IsValid(light.entity) then
		return string.format("%s_%d", light.classname or "unknown", light.entity:EntIndex())
	else
		-- For static map lights, use position-based ID
		return string.format("%s_%.2f_%.2f_%.2f", light.classname or "unknown", 
			light.origin.x, light.origin.y, light.origin.z)
	end
end

-- Proper world bounds check using NikNaks BSP data
local function IsInWorld(pos)
	-- First, strict coordinate check to catch extreme values
	local max_coord = 8192 -- More conservative than 16384
	if math.abs(pos.x) > max_coord or math.abs(pos.y) > max_coord or math.abs(pos.z) > max_coord then
		return false
	end
	
    if not NikNaks or not NikNaks.CurrentMap then
		-- More conservative fallback if NikNaks unavailable
		local fallback_max = 4096
		return not (math.abs(pos.x) > fallback_max or math.abs(pos.y) > fallback_max or math.abs(pos.z) > fallback_max)
	end
	
    -- Use cached world bounds if available
    local worldMin, worldMax = cached_world_min, cached_world_max
    if not cached_bounds_valid then
        worldMin, worldMax = NikNaks.CurrentMap:GetBrushBounds()
        cached_world_min, cached_world_max = worldMin, worldMax
        cached_bounds_valid = worldMin ~= nil and worldMax ~= nil
    end
    
    -- Validate that we got valid bounds
    if not worldMin or not worldMax then
		-- Fallback to conservative bounds if BSP data is invalid
		local fallback_max = 4096
		return not (math.abs(pos.x) > fallback_max or math.abs(pos.y) > fallback_max or math.abs(pos.z) > fallback_max)
	end
	
	-- Add a safety margin to the world bounds (more conservative)
	local margin = 256 -- Stay well within bounds
	local safe_min = worldMin + Vector(margin, margin, margin)
	local safe_max = worldMax - Vector(margin, margin, margin)
	
	-- Check if position is within conservative bounds
	if pos.x < safe_min.x or pos.x > safe_max.x or
	   pos.y < safe_min.y or pos.y > safe_max.y or
	   pos.z < safe_min.z or pos.z > safe_max.z then
		return false
	end
	
	-- Use BSP leaf system to check if position is outside map
	local small_offset = 2 -- Small AABB around the point
	local test_min = pos - Vector(small_offset, small_offset, small_offset)
	local test_max = pos + Vector(small_offset, small_offset, small_offset)
	
    -- Check if any part of this small AABB is outside the map (fail closed once errors are observed)
    if not outside_check_failed and NikNaks.CurrentMap.IsAABBOutsideMap then
        local ok, result = pcall(function()
            return NikNaks.CurrentMap:IsAABBOutsideMap(test_min, test_max)
        end)
        if not ok then
            outside_check_failed = true
        elseif result then
            return false
        end
    end
	
	return true
end

-- Check if a position conflicts with static props
local function IsPositionInStaticProp(pos)
	if not NikNaks or not NikNaks.CurrentMap then
		return false
	end
	
	-- Check against static props in a small area around the position
	local check_radius = 8 -- Increased radius to catch more props
	local nearby_props = NikNaks.CurrentMap:FindStaticInSphere(pos, check_radius)
	
	for _, prop in ipairs(nearby_props) do
		-- Check ALL static props, not just ones with collision
		-- Many decorative props have no collision but still occupy visual space
		local prop_pos = prop:GetPos()
		local prop_mins, prop_maxs = prop:GetModelBounds()
		
		-- Add small padding to prop bounds to avoid placing too close
		local padding = Vector(2, 2, 2)
		
		-- Transform bounds to world space with padding
		local world_mins = prop_pos + prop_mins - padding
		local world_maxs = prop_pos + prop_maxs + padding
		
		-- Check if position is within the prop's bounds (with padding)
		if pos.x >= world_mins.x and pos.x <= world_maxs.x and
		   pos.y >= world_mins.y and pos.y <= world_maxs.y and
		   pos.z >= world_mins.z and pos.z <= world_maxs.z then
			return true
		end
	end
	
	return false
end

-- Enhanced position blocking check that includes static props
local function IsPositionBlocked(pos)
	-- Check if position is inside solid geometry (including props/models)
	local trace = util.TraceHull({
		start = pos,
		endpos = pos,
		mins = Vector(-2, -2, -2),
		maxs = Vector(2, 2, 2),
		mask = MASK_SOLID -- Includes both brushes and props/models
	})
	
	-- Also check static prop bounds directly (more accurate for complex props)
	local in_static_prop = IsPositionInStaticProp(pos)
	
	return trace.Hit or trace.StartSolid or in_static_prop
end

-- Additional validation for reasonable positioning
local function IsPositionReasonable(pos, light_origin)
	-- First check: Is it actually in the world?
	if not IsInWorld(pos) then
		return false
	end
	
	-- Don't allow positions too far from the original light (more conservative)
	local max_distance = 128 -- Reduced from 256 for more conservative positioning
	if light_origin and pos:Distance(light_origin) > max_distance then
		return false
	end
	
	-- Additional strict coordinate check
	local strict_max = 6144 -- Even stricter limit for reasonable positions
	if math.abs(pos.x) > strict_max or math.abs(pos.y) > strict_max or math.abs(pos.z) > strict_max then
		return false
	end
	
	-- Check if position is significantly below reasonable ground level
	-- Use BSP world bounds for more accurate ground estimation
	if NikNaks and NikNaks.CurrentMap then
        local worldMin, worldMax = cached_world_min, cached_world_max
        if not cached_bounds_valid then
            worldMin, worldMax = NikNaks.CurrentMap:GetBrushBounds()
            cached_world_min, cached_world_max = worldMin, worldMax
            cached_bounds_valid = worldMin ~= nil and worldMax ~= nil
        end
		if worldMin and worldMax then
			local reasonable_min_z = worldMin.z - 256 -- Reduced from 512
			local reasonable_max_z = worldMax.z + 256 -- Also check ceiling
			if pos.z < reasonable_min_z or pos.z > reasonable_max_z then
				return false
			end
		end
	else
		-- Stricter fallback ground check
		if pos.z < -1024 or pos.z > 1024 then
			return false
		end
	end
	
	return true
end

-- Check if a position is within a light's influence area
local function IsPositionInLightInfluence(pos, light)
	if not light.origin then return false end
	
	local distance = pos:Distance(light.origin)
	local light_range = tonumber(light.range) or tonumber(light._light) or 200 -- Default range if not specified
	
	-- Check basic distance first
	if distance > light_range then
		return false
	end
	
	-- For spot lights, be VERY lenient with extremely close positions
	if light.classname == "light_spot" then
		-- If extremely close (under 8 units), just accept it - assume it's in the cone
		if distance < 8 then
			return true
		end
		
		-- For farther positions, do cone checking but be more lenient
		local light_dir = light.angles:Forward()
		local to_pos = (pos - light.origin):GetNormalized()
		local cone_angle = tonumber(light.cone) or tonumber(light._cone) or 45 -- Default cone angle
		
		-- Calculate angle between light direction and position
		local dot_product = light_dir:Dot(to_pos)
		
		-- Ensure dot product is valid (prevent math errors)
		dot_product = math.Clamp(dot_product, -1, 1)
		
		local angle = math.deg(math.acos(dot_product))
		
		-- Be more lenient - use 90% of cone angle instead of 80%
		local cone_half_angle = cone_angle / 2
		local max_allowed_angle = cone_half_angle * 0.9 -- More lenient than before
		
		-- Check if within lenient cone bounds
		if angle > max_allowed_angle then
			return false
		end
	end
	
	return true
end

-- Adjust position to be within light's influence area
local function AdjustPositionForLightInfluence(pos, light)
	if not light.origin then return pos end
	
	-- If it's a spot light, position it EXTREMELY close and DIRECTLY in front
	if light.classname == "light_spot" then
		local light_dir = light.angles:Forward()
		
		-- Try EXTREMELY close distances - almost touching the light
		local ultra_close_distances = {2, 3, 4} -- Extremely close
		
		for _, distance in ipairs(ultra_close_distances) do
			-- Place EXACTLY on the cone axis
			local test_pos = light.origin + (light_dir * distance)
			
			-- Much more lenient validation for spot lights - just check if in world
			if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) then
				return test_pos
			end
		end
		
		-- Emergency: place at 1 unit if everything else fails
		local emergency_pos = light.origin + (light_dir * 1)
		if IsInWorld(emergency_pos) then
			return emergency_pos
		end
		
	else
		-- Keep existing logic for other lights
		local light_range = tonumber(light.range) or tonumber(light._light) or 200
		light_range = math.min(light_range, 64)
		
		local ideal_distance = math.min(light_range * 0.2, 12)
		local direction = (pos - light.origin):GetNormalized()
		
		if direction:Length() < 0.1 then
			direction = Vector(math.random(-100, 100), math.random(-100, 100), math.random(-50, 50))
			direction = direction:GetNormalized()
		end
		
		local test_distances = {ideal_distance * 0.5, ideal_distance, ideal_distance * 1.5}
		
		for _, distance in ipairs(test_distances) do
			local new_pos = light.origin + (direction * distance)
			if IsInWorld(new_pos) and IsPositionReasonable(new_pos, light.origin) and not IsPositionBlocked(new_pos) then
				return new_pos
			end
		end
	end
	
	-- If all adjustments failed, return original position
	return pos
end

-- Enhanced direction finding that accounts for static props
local function FindBestDirection(light_origin, max_distance, sample_directions)
	max_distance = max_distance or 32
	
	local best_direction = Vector(1, 0, 0)
	local best_distance = 0
	
	-- Get nearby static props to account for in space calculations
	local nearby_props = {}
	if NikNaks and NikNaks.CurrentMap then
		nearby_props = NikNaks.CurrentMap:FindStaticInSphere(light_origin, max_distance * 1.5)
	end
	
	-- Test each direction to find available space
	for _, direction in ipairs(sample_directions) do
		local trace = util.TraceLine({
			start = light_origin,
			endpos = light_origin + (direction * max_distance),
			mask = MASK_SOLID
		})
		
		local available_distance = trace.Fraction * max_distance
		
		-- Additional check: reduce available distance if ANY static props are in the way
		-- Check all props, not just ones with collision (decorative props matter too)
		for _, prop in ipairs(nearby_props) do
			local prop_pos = prop:GetPos()
			local prop_mins, prop_maxs = prop:GetModelBounds()
			
			-- Simple check: if prop center is roughly in this direction, reduce available space
			local to_prop = prop_pos - light_origin
			local dot = to_prop:GetNormalized():Dot(direction)
			
			if dot > 0.7 then -- Prop is roughly in this direction
				local prop_distance = to_prop:Length()
				local prop_radius = math.max(prop_maxs:Length(), 8) -- Rough prop size
				local blocked_distance = math.max(0, prop_distance - prop_radius - 4) -- Extra padding
				
				available_distance = math.min(available_distance, blocked_distance)
			end
		end
		
		-- Prefer directions with more available space
		if available_distance > best_distance then
			best_distance = available_distance
			best_direction = direction
		end
	end
	
	return best_direction, best_distance
end

-- Find a clear position using smart direction finding
local function FindClearPositionSmart(original_pos, light_data)
	local light_origin = light_data.light.origin or original_pos
	
	-- Immediately reject if the light itself is in an extreme location
	if not IsInWorld(light_origin) or not IsPositionReasonable(light_origin, light_origin) then
		-- Don't create updaters for lights that are themselves out of bounds
		return nil, false
	end
	
	-- Try the original position first (must be clear, in influence, in world, and reasonable)
	if IsInWorld(original_pos) and not IsPositionBlocked(original_pos) and IsPositionInLightInfluence(original_pos, light_data.light) and IsPositionReasonable(original_pos, light_origin) then
		return original_pos, false
	end
	
	-- Try adjusting for light influence first
	local influenced_pos = AdjustPositionForLightInfluence(original_pos, light_data.light)
	if influenced_pos and IsInWorld(influenced_pos) and not IsPositionBlocked(influenced_pos) and IsPositionInLightInfluence(influenced_pos, light_data.light) and IsPositionReasonable(influenced_pos, light_origin) then
		return influenced_pos, true
	end
	
    -- Use precomputed directions to avoid per-call allocation
    local sample_directions = PRECOMP_SAMPLE_DIRECTIONS
	
	-- Find the direction with the most empty space
	local best_direction, available_distance = FindBestDirection(light_origin, 32, sample_directions) -- Reduced from 64
	
	-- Try positions along the best direction at various distances
	local test_distances = {}
	
	-- Create a range of distances to test, prioritizing shorter distances
	-- but ensuring we stay within the available space
	local max_test_distance = math.min(available_distance * 0.6, 16) -- Reduced from 0.8 and 24
	
	if max_test_distance > 2 then
		for i = 2, max_test_distance, 2 do
			table.insert(test_distances, i)
		end
	else
		-- If very little space, try tiny distances
		test_distances = {1, 2, 3}
	end
	
	-- Test positions along the best direction
	for _, distance in ipairs(test_distances) do
		local test_pos = light_origin + (best_direction * distance)
		
		-- All conditions must be met, including strict bounds checking
		if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) and IsPositionInLightInfluence(test_pos, light_data.light) and IsPositionReasonable(test_pos, light_origin) then
			-- Verify line of sight back to light
			local trace = util.TraceLine({
				start = test_pos,
				endpos = light_origin,
				mask = MASK_SOLID
			})
			
			if trace.Fraction > 0.8 then -- Higher standard for smart positioning
				return test_pos, true
			end
		end
	end
	
	-- If best direction doesn't work, try the top 3 directions (with stricter limits)
	local direction_scores = {}
	for _, direction in ipairs(sample_directions) do
		local trace = util.TraceLine({
			start = light_origin,
			endpos = light_origin + (direction * 16), -- Reduced from 32
			mask = MASK_SOLID
		})
		table.insert(direction_scores, {direction = direction, score = trace.Fraction})
	end
	
	-- Sort by available space (descending)
	table.sort(direction_scores, function(a, b) return a.score > b.score end)
	
	-- Try the top 3 directions
	for i = 1, math.min(3, #direction_scores) do
		local direction = direction_scores[i].direction
		local max_dist = direction_scores[i].score * 16 * 0.6 -- Reduced distances
		
		for dist = 2, math.min(max_dist, 8), 2 do -- Much more conservative
			local test_pos = light_origin + (direction * dist)
			
			if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) and IsPositionReasonable(test_pos, light_origin) then
				-- Even if not in light influence, accept it as emergency positioning
				return test_pos, true
			end
		end
	end
	
	-- Last resort: try very close to light origin in the best direction
	for dist = 1, 4 do
		local test_pos = light_origin + (best_direction * dist)
		if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) and IsPositionReasonable(test_pos, light_origin) then
			return test_pos, true
		end
	end
	
	-- Fallback: if all strict validation fails, try more lenient approach
	-- This ensures we don't lose lights that were previously working
	-- Try very simple positioning with minimal validation
	for _, distance in ipairs({2, 4, 6, 8}) do
		for _, direction in ipairs(sample_directions) do
			local test_pos = light_origin + (direction * distance)
			
			-- Only check basic world bounds and collision - skip reasonable position check
			if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) then
				return test_pos, true
			end
		end
	end
	
	-- Final emergency: place at light origin if it's in world (even if not ideal)
	if IsInWorld(light_origin) then
		return light_origin, true
	end
	
	-- Complete failure: don't create an updater for this light
	if debugconsole:GetBool() then
		print("[gmRTX - Lightupdater] Failed to find any valid position for light at: " .. tostring(light_origin))
	end
	return nil, false
end

-- Helper function to calculate initial position for a light
local function CalculateInitialPosition(light)
	if not light.origin or not light.angles then return nil end
	
	-- For spot lights, position EXTREMELY close directly in front
	if light.classname == "light_spot" then
		local light_dir = light.angles:Forward()
		return light.origin + (light_dir * 2) -- EXTREMELY close - 2 units
	else
		-- For other lights, position slightly offset (original logic)
		return light.origin - (light.angles:Forward() * 8)
	end
end

-- Emergency positioning for lights that fail normal validation
local function FindEmergencyPosition(light)
	if not light.origin then return nil end
	
	local light_origin = light.origin
	
	-- Try extremely simple positions with minimal validation
	-- Try very close distances first
	local emergency_distances = {1, 2, 3, 4, 6, 8, 12, 16}
	
	for _, distance in ipairs(emergency_distances) do
        for _, direction in ipairs(PRECOMP_EMERGENCY_DIRECTIONS) do
			local test_pos = light_origin + (direction * distance)
			
			-- VERY minimal validation - just check it's not in solid geometry and somewhat reasonable
			local basic_max = 10000 -- Much more lenient coordinate check
			local coords_ok = math.abs(test_pos.x) < basic_max and math.abs(test_pos.y) < basic_max and math.abs(test_pos.z) < basic_max
			
			if coords_ok then
				-- Simple collision check only
				local trace = util.TraceHull({
					start = test_pos,
					endpos = test_pos,
					mins = Vector(-1, -1, -1), -- Smaller hull
					maxs = Vector(1, 1, 1),
					mask = MASK_SOLID
				})
				
				if not (trace.Hit or trace.StartSolid) then
					return test_pos
				end
			end
		end
	end
	
	-- Last resort: try positions directly at light origin with small offsets
    for _, offset in ipairs(PRECOMP_TINY_OFFSETS) do
		local test_pos = light_origin + offset
		
		-- Absolute minimal check - just make sure coordinates aren't completely insane
		if math.abs(test_pos.x) < 20000 and math.abs(test_pos.y) < 20000 and math.abs(test_pos.z) < 20000 then
			-- Don't even check collision for these emergency positions
			return test_pos
		end
	end
	return nil
end

-- Add a new light to our tracking system
local function AddLight(light)
	local light_id = GetLightID(light)
	if not light_id then return false end
	
	-- Always add to discovered lights (even if we already have it or it fails)
	all_discovered_lights[light_id] = light
	
	-- Skip if we already have this light
	if known_lights[light_id] then return false end
	
	local original_pos = CalculateInitialPosition(light)
	if original_pos then
		local adjusted_pos, was_moved = FindClearPositionSmart(original_pos, {light = light})
		
		-- Only create light updater if we found a valid position
		if adjusted_pos then
			known_lights[light_id] = {
				light = light,
				original_pos = original_pos,
				pos = adjusted_pos,
				was_moved = was_moved,
				classname = light.classname
			}
			
			-- Add to legacy arrays for compatibility
			if not lights then lights = {} end
			if not light_positions then light_positions = {} end
			
			table.insert(lights, light)
			light_positions[#lights] = adjusted_pos
			lights_dirty = true
			
			return true
		else
			-- Automatically try emergency positioning as fallback
			local emergency_pos = FindEmergencyPosition(light)
			if emergency_pos then
				known_lights[light_id] = {
					light = light,
					original_pos = original_pos,
					pos = emergency_pos,
					was_moved = true, -- Mark as moved since it's emergency positioning
					classname = light.classname,
					emergency = true -- Mark as emergency positioned
				}
				
				-- Add to legacy arrays for compatibility
				if not lights then lights = {} end
				if not light_positions then light_positions = {} end
				
				table.insert(lights, light)
				light_positions[#lights] = emergency_pos
				lights_dirty = true
				
				return true
			end
		end
	end
	return false
end

-- Initialize or reinitialize lights data
local function InitializeLights()
	if not NikNaks or not NikNaks.CurrentMap then
		return false
	end
	
	local new_map_name = game.GetMap()
	if current_map_name ~= new_map_name then
		CleanupModel()
		current_map_name = new_map_name
	end
	
	if lights == nil then
		-- Find static map lights using NikNaks
		lights = NikNaks.CurrentMap:FindByClass( "light" ) or {}
		
		lights = TableConcat(lights, NikNaks.CurrentMap:FindByClass( "light_spot" ) or {})
		lights = TableConcat(lights, NikNaks.CurrentMap:FindByClass( "light_environment" ) or {})
		lights = TableConcat(lights, NikNaks.CurrentMap:FindByClass( "light_dynamic" ) or {})
		
		-- Find dynamic GMod light entities
		local gmod_lights = ents.FindByClass("gmod_light") or {}
		local gmod_lamps = ents.FindByClass("gmod_lamp") or {}
		
		-- Convert dynamic entities to light data format
		for _, ent in ipairs(gmod_lights) do
			if IsValid(ent) then
				local light_data = {
					origin = ent:GetPos(),
					angles = ent:GetAngles(),
					classname = "gmod_light",
					entity = ent -- Keep reference to the entity
				}
				table.insert(lights, light_data)
			end
		end
		
		for _, ent in ipairs(gmod_lamps) do
			if IsValid(ent) then
				local light_data = {
					origin = ent:GetPos(),
					angles = ent:GetAngles(),
					classname = "gmod_lamp",
					entity = ent -- Keep reference to the entity
				}
				table.insert(lights, light_data)
			end
		end
		
		-- Shuffle lights to randomize processing order for better distribution
		lights = shuffle(lights)
		
		local total_lights_found = #lights
		local lights_processed = 0
		local static_lights = total_lights_found - #gmod_lights - #gmod_lamps
		
		-- Pre-calculate all positions and add to known lights
		light_positions = {}
		for i, light in pairs(lights) do
			-- Add to all discovered lights first
			local light_id = GetLightID(light)
			if light_id then
				all_discovered_lights[light_id] = light
			end
			
			local original_pos = CalculateInitialPosition(light)
			if original_pos then
				local adjusted_pos, was_moved = FindClearPositionSmart(original_pos, {light = light})
				
				-- Only create light updater if we found a valid position
				if adjusted_pos then
					light_positions[i] = adjusted_pos
					lights_processed = lights_processed + 1
					
					-- Add to known lights tracking
					if light_id then
						known_lights[light_id] = {
							light = light,
							original_pos = original_pos,
							pos = adjusted_pos,
							was_moved = was_moved,
							classname = light.classname
						}
					end
				else
					-- Automatically try emergency positioning as fallback
					local emergency_pos = FindEmergencyPosition(light)
					if emergency_pos then
						light_positions[i] = emergency_pos
						lights_processed = lights_processed + 1
						
						-- Add to known lights tracking with emergency flag
						if light_id then
							known_lights[light_id] = {
								light = light,
								original_pos = original_pos,
								pos = emergency_pos,
								was_moved = true, -- Mark as moved since it's emergency positioning
								classname = light.classname,
								emergency = true -- Mark as emergency positioned
							}
						end
					end
				end
				-- If adjusted_pos is nil, we skip this light (don't create an updater)
			end
		end
		
		lights_dirty = true
		-- Report processing results
		if debugconsole:GetBool() or lights_processed < total_lights_found then
			if debugconsole:GetBool() then
				print("[gmRTX - Lightupdater] Processed " .. lights_processed .. " / " .. total_lights_found .. " lights")
				print("[gmRTX - Lightupdater] Found " .. static_lights .. " static lights, " .. #gmod_lights .. " gmod_lights, " .. #gmod_lamps .. " gmod_lamps")
			end
			if lights_processed < total_lights_found and debugconsole:GetBool() then
				print("[gmRTX - Lightupdater] " .. (total_lights_found - lights_processed) .. " lights were skipped (couldn't find valid positions)")
			end
		end
	end
	
	return true
end

-- Check for new dynamic lights and add them
local function ScanForNewDynamicLights()
	if not updatelights:GetBool() or not dynamicscan:GetBool() then return end
	
	local new_lights_added = 0
	
	-- Scan for new gmod_light entities
	local gmod_lights = ents.FindByClass("gmod_light") or {}
	for _, ent in ipairs(gmod_lights) do
		if IsValid(ent) then
			local light_data = {
				origin = ent:GetPos(),
				angles = ent:GetAngles(),
				classname = "gmod_light",
				entity = ent
			}
			
			if AddLight(light_data) then
				new_lights_added = new_lights_added + 1
			end
		end
	end
	
	-- Scan for new gmod_lamp entities
	local gmod_lamps = ents.FindByClass("gmod_lamp") or {}
	for _, ent in ipairs(gmod_lamps) do
		if IsValid(ent) then
			local light_data = {
				origin = ent:GetPos(),
				angles = ent:GetAngles(),
				classname = "gmod_lamp",
				entity = ent
			}
			
			if AddLight(light_data) then
				new_lights_added = new_lights_added + 1
			end
		end
	end
	
	-- Clean up updaters for removed dynamic lights
    local removed_lights = 0
    for light_id, light_data in pairs(known_lights) do
		if light_data.light.entity and not IsValid(light_data.light.entity) then
			-- Remove from tracking
			known_lights[light_id] = nil
			all_discovered_lights[light_id] = nil
			removed_lights = removed_lights + 1
			lights_dirty = true
		end
	end
	
	-- Report new lights found
	if new_lights_added > 0 and debugconsole:GetBool() then
		print("[gmRTX - Lightupdater] Added " .. new_lights_added .. " new dynamic lights")
	end
	
	if removed_lights > 0 and debugconsole:GetBool() then
		print("[gmRTX - Lightupdater] Removed " .. removed_lights .. " deleted dynamic lights")
	end
end

-- Timer to periodically scan for new dynamic lights
local next_dynamic_scan = 0
local dynamic_scan_interval = 2 -- Scan every 2 seconds

-- Force recalculate all light positions
local function ForceRecalculateAllLights()
	-- Clear the known lights cache to force recalculation
	local old_known_lights = known_lights
	local old_count = table.Count(old_known_lights)
	known_lights = {}
	all_discovered_lights = {}
	lights = nil
	light_positions = nil
	
	-- Force re-initialization of lights with new positions
	if InitializeLights() then
		
		local new_count = table.Count(known_lights)
		if debugconsole:GetBool() then
			print("[gmRTX - Lightupdater] Force moved all lights - " .. new_count .. " lights repositioned (was " .. old_count .. ")")
			
			if new_count < old_count then
				print("[gmRTX - Lightupdater] WARNING: Lost " .. (old_count - new_count) .. " light updaters during repositioning")
				print("[gmRTX - Lightupdater] Enable rtx_lightupdater_debug_console 1 for more details")
			end
		end
	else
		if debugconsole:GetBool() then
			print("[gmRTX - Lightupdater] Failed to force move lights - initialization failed")
		end
	end
end

local function MovetoPositions()
	if not updatelights:GetBool() then return end
	
	-- Check if force move is requested
	if forcemove:GetBool() then
		ForceRecalculateAllLights()
		forcemove:SetBool(false) -- Reset the cvar after force move
		return -- Skip normal processing this frame to allow recalculation
	end
	
	-- Initialize lights if needed (only runs once per map)
    if not InitializeLights() then return end

	-- Periodically scan for new dynamic lights
	local current_time = CurTime()
	if dynamicscan:GetBool() and current_time >= next_dynamic_scan then
		ScanForNewDynamicLights()
		next_dynamic_scan = current_time + dynamic_scan_interval
	end
	
    -- Rendering is handled in a dedicated render hook every frame
end

-- Dedicated Think hook for tracking dynamic entity movements
local function UpdateDynamicLightPositions()
	if not dynamicupdate:GetBool() or not updatelights:GetBool() then return end
	if not known_lights then return end
    local ct = CurTime()
    if ct < next_dynamic_update then return end
    next_dynamic_update = ct + dynamic_update_interval
	
	for light_id, light_data in pairs(known_lights) do
		-- Only check dynamic entities (ones with entity references)
		if light_data.light.entity and IsValid(light_data.light.entity) then
			local current_pos = light_data.light.entity:GetPos()
			local current_angles = light_data.light.entity:GetAngles()
			
            -- Use distance check for more reliable position comparison (add deadzone)
            local pos_changed = light_data.light.origin:DistToSqr(current_pos) > 9 -- > 3 units difference
			local angle_changed = false
			
			-- Check if angles have changed significantly
			if light_data.light.angles then
				local angle_diff = math.abs(light_data.light.angles.pitch - current_angles.pitch) + 
				                  math.abs(light_data.light.angles.yaw - current_angles.yaw) + 
				                  math.abs(light_data.light.angles.roll - current_angles.roll)
                angle_changed = angle_diff > 3 -- More than 3 degrees difference
			end
			
			-- Update if position or angles have changed
			if pos_changed or angle_changed then
				-- Update the light data
				light_data.light.origin = current_pos
				light_data.light.angles = current_angles
				
				-- Recalculate updater position
				local original_pos = CalculateInitialPosition(light_data.light)
				if original_pos then
					local adjusted_pos, was_moved = FindClearPositionSmart(original_pos, {light = light_data.light})
					if adjusted_pos then
						light_data.original_pos = original_pos
						light_data.pos = adjusted_pos
						light_data.was_moved = was_moved
					else
						-- Try emergency positioning if smart positioning fails
						local emergency_pos = FindEmergencyPosition(light_data.light)
						if emergency_pos then
							light_data.original_pos = original_pos
							light_data.pos = emergency_pos
							light_data.was_moved = true
							light_data.emergency = true
						end
					end
				end
			end
		end
	end
end

-- One persistent helper model per light, drawn only from the hook below. render.Model()
-- without an entity creates a ClientsideModel and removes it again on every call, so each
-- light ran every OnEntityCreated/EntityRemoved listener (and the timers they start) every
-- frame. Each light keeps its own entity, so the engine still lights each one at its own spot.
local helpers = {}
-- Position last given to each helper. Comparing against this instead of helper:GetPos() avoids
-- a new Vector per light per frame (the hook's main source of garbage).
local helperPos = {}

local function ReleaseHelpers()
    for id, helper in pairs(helpers) do
        if IsValid(helper) then helper:Remove() end
        helpers[id] = nil
        helperPos[id] = nil
    end
end

local function GetHelper(light_id, pos)
    local helper = helpers[light_id]
    if not IsValid(helper) then
        helper = ClientsideModel("models/editor/cone_helper.mdl", RENDERGROUP_OTHER)
        if not IsValid(helper) then return nil end
        helper:SetNoDraw(true)
        helper:SetAngles(zero_angle)
        helpers[light_id] = helper
        helperPos[light_id] = nil
    end
    if helperPos[light_id] ~= pos then
        helper:SetPos(pos)
        helperPos[light_id] = pos
    end
    return helper
end

-- R28 (native-loader ADR 0144): which helpers a frame draws.
--
-- A helper is drawn so that the engine sets lights for its draw and the Remix runtime sees them: the four
-- strongest of the map's lights in sight where the helper stands (r_worldlights), which are its own light and
-- that light's neighbours, texture lights and spot lights among them. With the package's settings
-- (rtx.suppressLightKeeping, rtx.antiCulling.light) the runtime drops a light the frame it is not set, except a
-- point light whose position is outside the view: that one it keeps for
-- rtx.antiCulling.light.numFramesToExtendLightLifetime (1000) frames after it was last set
-- (LightManager::garbageCollectionInternal; a spot light, which a texture light is for the runtime, and a
-- directional light always count as in view). So a helper is needed every frame when it may set a light that
-- no helper drawn every frame sets (a texture light), and while a point light that only it sets is in view;
-- otherwise only now and then. What a helper may set is worked out once a map from the map's world lights, by
-- the engine's rule with a margin (StudyHelper). Until that is done, and wherever it cannot be done, every
-- helper is drawn every frame, as before R28: that cost 6.5-10.7 us a light in this hook and about three times
-- that in the frame (40 ms a frame on a map with 1,126 lights).
--
-- One more rule of the runtime decides where a light may stop being set at all. A light set in the last frame
-- and not in this one is taken for a light that moved: a new point light within rtx.uniqueObjectDistance (300
-- units) inherits it, and the old one is erased (LightManager::dynamicLightMatching). A new point light is a
-- dynamic light that starts or moves: a muzzle flash, an explosion, a lamp being carried. So the lights within
-- that distance (and 150 units more) of the eye, and of every dynamic light this file can know of (the gmod_light
-- and gmod_lamp entities, and lights made with DynamicLight from Lua), count as in view: they never stop being set.
-- The engine's own dynamic lights farther from the eye cannot be seen from Lua (ADR 0144 says what that leaves).
local REFRESH_FRAMES = 120     -- a helper no light in view needs is still drawn at least this often
local VIEW_PAD = 96            -- units added around the view's sides (the light's own size, and some slack)
local VIEW_WIDEN = 1.15        -- the view's half-angles are widened by this factor
local MATCH_UNITS = 300        -- the runtime's rtx.uniqueObjectDistance: how far a "moved" light is looked for
local MATCH_PAD = 150          -- added to it: what a light or the eye moves before the next frame, and slack
local HOLD_FRAMES = 2          -- a light that left the view counts as in view this long: the runtime tests a
                               -- frame's lights with the view of the frame before
local DYNAMIC_FRAMES = 12      -- a light made from Lua counts as there this long after its last DynamicLight call
local DYNAMIC_MAX = 32         -- how many of them are followed
local BOUNDED_FROM = 256       -- the list is used where a map has at least this many lights (rtx_lightupdater_all 0)
local LOCAL_LIGHTS = 4         -- how many world lights the engine sets for a model (r_worldlights)
local LOCAL_MINIMUM = 0.0002   -- the engine's r_worldlightmin: a dimmer light is not set for a model
local SIGHT_MARGIN = 4         -- steady lights in sight, beyond the engine's count, that must outshine any other kind
local NEIGHBOURS_MAX = 48      -- how many of the strongest steady lights around a helper are remembered
local WORLD_LIGHTS_MAX = 20000 -- a map with more world lights is not studied: every helper every frame
local STUDY_SECONDS = 0.001    -- the least a frame spends on working out helpers' lights
local STUDY_SHARE = 0.05       -- and the share of a long frame it may spend

-- The draw list: one record per light. A steady point light also has a slot: its origin as plain numbers.
local order, order_source = {}, nil
local todo = {}
local slot_x, slot_y, slot_z, slot_seen, slot_shared, slot_held = {}, {}, {}, {}, {}, {}
local slot_count = 0
-- After the list is built again, that frame and the next draw every light, so each new light is set at once.
local warm_until = -1
local draw_stats = { lights = 0, steady = 0, bounded = 0, drawn = 0 }

-- What the list relies on in the runtime, as far as Lua can see it: the game folder's rtx.conf
-- (RemixConfig.GetConfigVariable reads that file, not the live value; a change made in the Remix menu and not
-- saved there is not seen, and rtx_lightupdater_all 1 is the switch for that).
local bounded_ok, bounded_note = true, nil
local refresh_frames, view_scale, match_units = REFRESH_FRAMES, 1, MATCH_UNITS

local function ReadRuntimeOptions()
    bounded_ok, bounded_note, refresh_frames, view_scale, match_units = true, nil, REFRESH_FRAMES, 1, MATCH_UNITS
    local config = RemixConfig
    if not config or not config.GetConfigVariable then return end
    local function option(name)
        local ok, value = pcall(config.GetConfigVariable, name)
        if ok and type(value) == "string" then
            value = string.lower(string.match(value, "^%s*(.-)%s*$"))
            if value ~= "" then return value end
        end
        return nil
    end
    local enable = option("rtx.antiCulling.light.enable")
    if enable == "false" or enable == "0" then
        bounded_ok, bounded_note = false, "rtx.antiCulling.light.enable is off in rtx.conf"
        return
    end
    local free = option("rtx.camera.enableFreeCamera")
    if free == "true" or free == "1" then
        bounded_ok, bounded_note = false, "rtx.camera.enableFreeCamera is on in rtx.conf"
        return
    end
    local frames = tonumber(option("rtx.antiCulling.light.numFramesToExtendLightLifetime") or "")
    if frames then
        if frames < 40 then
            bounded_ok, bounded_note = false, "rtx.antiCulling.light.numFramesToExtendLightLifetime is under 40 in rtx.conf"
            return
        end
        refresh_frames = math.min(REFRESH_FRAMES, math.floor(frames / 4))
    end
    local scale = tonumber(option("rtx.antiCulling.light.fovScale") or "")
    if scale and scale > 1 then
        if scale > 4 then
            bounded_ok, bounded_note = false, "rtx.antiCulling.light.fovScale is over 4 in rtx.conf"
            return
        end
        view_scale = scale
    end
    local match = tonumber(option("rtx.uniqueObjectDistance") or "")
    if match and match > MATCH_UNITS then
        if match > 4000 then
            bounded_ok, bounded_note = false, "rtx.uniqueObjectDistance is over 4000 in rtx.conf"
            return
        end
        match_units = match
    end
end

-- Dynamic lights made from Lua: every DynamicLight call is noted by the light's key, so that the lights near it
-- are kept set (see the top of this block). The object the game returns can be written, not read (light.pos is
-- nil), so the position is noted as it is written, through the object's metatable; where that cannot be done, an
-- entity with the light's key stands for the light (add-ons key a light by its entity's index). The wrapper is
-- installed once a game: a reload of this file finds it.
local lua_lights = rawget(_G, "RTXLightUpdaterDynamicLights")
if type(lua_lights) ~= "table" or type(lua_lights.lights) ~= "table" or type(lua_lights.count) ~= "number" then
    lua_lights = { lights = {}, count = 0, objects = setmetatable({}, { __mode = "k" }) }
    if type(DynamicLight) == "function" then
        local native, noted = DynamicLight, lua_lights
        local watched = false
        local function watch(light)
            local meta = debug.getmetatable(light)
            local set = type(meta) == "table" and rawget(meta, "__newindex")
            if type(set) ~= "function" then return end
            rawset(meta, "__newindex", function(object, field, value)
                if field == "pos" and isvector(value) then
                    local entry = noted.objects[object]
                    if entry then entry.x, entry.y, entry.z = value.x, value.y, value.z end
                end
                return set(object, field, value)
            end)
        end
        DynamicLight = function(key, ...)
            local light = native(key, ...)
            if light ~= nil and key ~= nil then
                if not watched then
                    watched = true
                    pcall(watch, light)
                end
                local entry = noted.lights[key]
                if entry then
                    entry.frame = FrameNumber()
                elseif noted.count < DYNAMIC_MAX then
                    entry = { frame = FrameNumber() }
                    noted.lights[key] = entry
                    noted.count = noted.count + 1
                end
                if entry then noted.objects[light] = entry end
            end
            return light
        end
        _G.RTXLightUpdaterDynamicLights = lua_lights
    end
end
-- The lamps among the lights (records with an entity), listed when the draw list is built.
local lamp_records, lamp_count = {}, 0

local function Finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- A map "light" that nothing switches or animates: no entity behind it, no name a map could address it by, no
-- light style. Only these are point lights whose colour and position never change.
local function IsSteadyPointLight(light)
    if not light or light.entity or light.classname ~= "light" or not light.origin then return false end
    local name, style = light.targetname, light.style
    if name ~= nil and name ~= "" then return false end
    if style ~= nil and style ~= 0 and style ~= "0" and style ~= "" then return false end
    local origin = light.origin
    return Finite(origin.x) and Finite(origin.y) and Finite(origin.z)
end

-- The map's world lights (what the engine lights models with) as plain arrays: nil before they are read for
-- this map, false when they cannot be used.
local world, world_map = nil, nil
local sight_out, sight_world = {}, nil
-- Per light id: where its helper stood when its lights were worked out, and what was found.
local study_cache, study_mark = {}, nil
local study_queue, study_next, study_total = {}, 1, 0
local study_frame = -1
-- Per cluster of the map: the clusters that can be seen from it (the map's PVS), as NikNaks reads them. Only
-- the last few are kept, and none once the study is done: a set has an entry for every cluster in sight.
local pvs_cache, pvs_count = {}, 0

local function OriginKey(x, y, z)
    return ((math.floor(x + 0.5) + 32768) * 65536 + (math.floor(y + 0.5) + 32768)) * 65536 + (math.floor(z + 0.5) + 32768)
end

local function ReadWorldLights()
    world, world_map = false, current_map_name
    study_cache, study_mark, pvs_cache, pvs_count = {}, nil, {}, 0
    sight_world = game.GetWorld and game.GetWorld() or nil
    local map = NikNaks and NikNaks.CurrentMap
    if not map or not map.GetWorldLights then return end
    local ok, list = pcall(function()
        local found
        if render.GetHDREnabled and render.GetHDREnabled() and map.GetWorldLightsHDR then
            found = map:GetWorldLightsHDR()
        end
        if type(found) ~= "table" or found[0] == nil then found = map:GetWorldLights() end
        return found
    end)
    if not ok or type(list) ~= "table" or list[0] == nil then return end
    local w = { count = 0, x = {}, y = {}, z = {}, pos = {}, gray = {}, radius = {}, c = {}, l = {}, q = {},
        surface = {}, steady = {}, slot = {}, kept = {}, cluster = {}, sky = {} }
    local count = 0
    for index = 0, WORLD_LIGHTS_MAX do
        local light = list[index]
        if not light then break end
        if index == WORLD_LIGHTS_MAX then return end
        local kind, origin, intensity = light.type, light.origin, light.intensity
        -- Anything but the six emit types means the lump is not the layout NikNaks reads: no study.
        if not Finite(kind) or kind < 0 or kind > 5 or kind % 1 ~= 0 or not origin or not intensity then return end
        if kind == 3 then
            -- The sun: set for a model that sees the sky along it.
            local normal = light.normal
            if normal and #w.sky < 4 then w.sky[#w.sky + 1] = normal end
        elseif kind <= 2 then
            local gray = 0.299 * intensity.x + 0.587 * intensity.y + 0.114 * intensity.z
            local x, y, z = origin.x, origin.y, origin.z
            if Finite(gray) and gray > 0 and Finite(x) and Finite(y) and Finite(z) then
                count = count + 1
                w.x[count], w.y[count], w.z[count], w.pos[count] = x, y, z, origin
                w.gray[count] = gray
                w.radius[count] = Finite(light.radius) and light.radius or 0
                w.c[count] = Finite(light.constant_attn) and light.constant_attn or 0
                w.l[count] = Finite(light.linear_attn) and light.linear_attn or 0
                w.q[count] = Finite(light.quadratic_attn) and light.quadratic_attn or 0
                w.surface[count] = kind == 0
                w.steady[count] = kind == 1 and light.style == 0
                w.slot[count], w.kept[count] = 0, false
                w.cluster[count] = Finite(light.cluster) and light.cluster or -1
            end
        end
    end
    w.count = count
    world = w
end

-- The engine's occlusion rule for a model's lights: no test within 8 units, else a ray against the world alone
-- that must come within 8 units of the light.
local sight_in = { mask = MASK_OPAQUE, output = sight_out, filter = function(ent) return ent == sight_world end }

local function Sees(from, index, distance)
    if distance < 8 then return true end
    sight_in.start, sight_in.endpos = from, world.pos[index]
    util.TraceLine(sight_in)
    return (1 - (sight_out.Fraction or 0)) * distance <= 8
end

local function SeesSky(from)
    local sky = world.sky
    for index = 1, #sky do
        sight_in.start, sight_in.endpos = from, from - sky[index] * 56000
        util.TraceLine(sight_in)
        if sight_out.HitSky then return true end
    end
    return false
end

-- The clusters a model standing at pos may take lights from: the engine's first test is that the light's
-- cluster is in the PVS of the model's leaf. Taken for the spot and six spots 12 units around it, since the
-- engine measures at the model's lighting origin. nil when that cannot be told (no visibility data, the spot in
-- no cluster): then every light counts, as it does for the engine.
local PVS_AROUND = { { 0, 0, 0 }, { 12, 0, 0 }, { -12, 0, 0 }, { 0, 12, 0 }, { 0, -12, 0 }, { 0, 0, 12 }, { 0, 0, -12 } }

local function VisibleSets(pos)
    local map = NikNaks.CurrentMap
    local sets, count = {}, 0
    for index = 1, #PVS_AROUND do
        local around = PVS_AROUND[index]
        local spot = index == 1 and pos or Vector(pos.x + around[1], pos.y + around[2], pos.z + around[3])
        local cluster = map:ClusterFromPoint(spot)
        if not Finite(cluster) or cluster < 0 then
            if index == 1 then return nil end
        else
            local set = pvs_cache[cluster]
            if set == nil then
                set = map:PVSForOrigin(spot)
                if type(set) ~= "table" then return nil end
                if pvs_count >= 64 then pvs_cache, pvs_count = {}, 0 end
                pvs_cache[cluster], pvs_count = set, pvs_count + 1
            end
            local known = false
            for at = 1, count do
                if sets[at] == set then known = true break end
            end
            if not known then
                count = count + 1
                sets[count] = set
            end
        end
    end
    return sets
end

local function InSets(sets, cluster)
    if not sets then return true end
    if cluster < 0 then return false end
    for at = 1, #sets do
        if sets[at][cluster] then return true end
    end
    return false
end

-- What the engine may set for a model standing at pos. The engine takes the LOCAL_LIGHTS strongest lights in
-- sight there (brightness by distance, none dimmer than LOCAL_MINIMUM), measured at a spot within some 30 units
-- of the model with its own occlusion test. So the answer here keeps a margin:
--   own: the helper's own light is among the two strongest there, its leaf can see the light's cluster and a
--     ray reaches it, so this helper sets it. For a light whose helper is drawn every frame (a spot light, a
--     named or styled light; own_world is its world light) this is all that is asked: such a light needs no
--     other helper.
--   unbounded: a light that no helper is known to set every frame (a texture light, a light whose helper could
--     not be placed or does not set it) may be among the engine's. It may unless LOCAL_LIGHTS + SIGHT_MARGIN
--     steady lights in sight are stronger than the strongest such light the helper's leaf can see (its PVS),
--     taken at its full brightness (no cone, no light style) and whether a ray reaches it or not. The same when
--     the helper sees the sky along the sun.
--   near: the strongest steady lights around, for the lights whose own helper does not set them.
local rank_light, rank_value = {}, {}

local function StudyHelper(pos, own_slot, own_world)
    local w = world
    local px, py, pz = pos.x, pos.y, pos.z
    local wx, wy, wz, gray, radius, slots, kept_light = w.x, w.y, w.z, w.gray, w.radius, w.slot, w.kept
    local wc, wl, wq, surface, cluster = w.c, w.l, w.q, w.surface, w.cluster
    local visible, sets = pcall(VisibleSets, pos)
    if not visible then sets = nil end
    local keep, kept = NEIGHBOURS_MAX, 0
    local least = LOCAL_MINIMUM / 4
    local threat, first, second = 0, 0, 0
    local own_index, own_value = nil, 0
    for index = 1, w.count do
        local dx, dy, dz = wx[index] - px, wy[index] - py, wz[index] - pz
        local d2 = dx * dx + dy * dy + dz * dz
        local reach = radius[index]
        if reach == 0 or d2 <= (reach + 64) * (reach + 64) then
            local ratio
            if surface[index] then
                ratio = 1 / (d2 > 1 and d2 or 1)
            else
                local fall = wc[index] + wl[index] * math.sqrt(d2) + wq[index] * d2
                ratio = fall > 1e-30 and 1 / fall or 1e30
            end
            local value = ratio * gray[index]
            if value >= least then
                if value > first then
                    first, second = value, first
                elseif value > second then
                    second = value
                end
                local slot = slots[index]
                if own_world then
                    if index == own_world then own_index, own_value = index, value end
                elseif slot == 0 then
                    if not kept_light[index] and value > threat and InSets(sets, cluster[index]) then threat = value end
                else
                    if slot == own_slot and value > own_value then own_index, own_value = index, value end
                    if kept < keep or value > rank_value[kept] then
                        local at = kept
                        if kept < keep then
                            kept = kept + 1
                            at = kept
                        end
                        while at > 1 and rank_value[at - 1] < value do
                            rank_value[at], rank_light[at] = rank_value[at - 1], rank_light[at - 1]
                            at = at - 1
                        end
                        rank_value[at], rank_light[at] = value, index
                    end
                end
            end
        end
    end
    local own = true
    if own_index then
        local dx, dy, dz = wx[own_index] - px, wy[own_index] - py, wz[own_index] - pz
        own = own_value >= second and InSets(sets, cluster[own_index])
            and Sees(pos, own_index, math.sqrt(dx * dx + dy * dy + dz * dz))
    end
    -- A light with a helper every frame: found too dim here to be told (own_index nil), it is not set by it.
    if own_world then return { x = px, y = py, z = pz, own = own and own_index ~= nil, owns = own_world } end
    local known = { x = px, y = py, z = pz, unbounded = false, own = own, near = {} }
    for at = 1, kept do known.near[at] = rank_light[at] end
    if threat > 0 then
        local need, seen = LOCAL_LIGHTS + SIGHT_MARGIN, 0
        for at = 1, kept do
            if rank_value[at] <= threat then break end
            local index = rank_light[at]
            local dx, dy, dz = wx[index] - px, wy[index] - py, wz[index] - pz
            if InSets(sets, cluster[index]) and Sees(pos, index, math.sqrt(dx * dx + dy * dy + dz * dz)) then
                seen = seen + 1
                if seen >= need then break end
            end
        end
        if seen < need then known.unbounded = true end
    end
    if not known.unbounded and #w.sky > 0 and SeesSky(pos) then known.unbounded = true end
    return known
end

-- Which world lights are steady lights with helpers, and which others their own helpers set: what was worked
-- out for the steady lights' helpers holds while this stays the same.
local function StudyMark()
    local slots, kept_light = world.slot, world.kept
    local count, sum = 0, 0
    for index = 1, world.count do
        if slots[index] ~= 0 then
            count, sum = count + 1, (sum + index * 31) % 2147483647
        elseif kept_light[index] then
            count, sum = count + 1, (sum + index * 17) % 2147483647
        end
    end
    return count .. ":" .. sum
end

-- Every steady light has been studied: which records are bounded, and what each waits for. A light whose own
-- helper does not set it is set by its neighbours' helpers, so each of those waits for it as well.
local function ResolveAll()
    local total, bounded = #order, 0
    for index = 1, total do
        local record = order[index]
        if record.steady then
            local known = study_cache[record.id]
            slot_shared[record.slot] = not (known and known.own)
        end
    end
    local slots = world.slot
    for index = 1, total do
        local record = order[index]
        record.bounded, record.needs = false, nil
        local known = record.steady and study_cache[record.id]
        if known and not known.unbounded then
            local needs, count = { record.slot }, 1
            local near = known.near
            for at = 1, #near do
                local slot = slots[near[at]]
                if slot and slot ~= 0 and slot ~= record.slot and slot_shared[slot] then
                    count = count + 1
                    needs[count] = slot
                end
            end
            record.needs, record.bounded = needs, true
            bounded = bounded + 1
        end
    end
    draw_stats.bounded = bounded
    study_mark = StudyMark()
end

local function Study(frame)
    if study_frame == frame or study_next > study_total or not world then return end
    study_frame = frame
    local spare = RealFrameTime and RealFrameTime() * STUDY_SHARE or 0
    local stop = SysTime() + math.min(math.max(STUDY_SECONDS, spare), 0.02)
    repeat
        local record = study_queue[study_next]
        study_queue[study_next] = nil
        study_next = study_next + 1
        local ok, known = pcall(StudyHelper, record.data.pos, record.slot, record.owns)
        -- A helper that could not be studied is drawn every frame, and its light counts as set by others.
        if not ok or not known then
            local pos = record.data.pos
            known = { x = pos.x, y = pos.y, z = pos.z, unbounded = true, own = false, near = {}, owns = record.owns }
        end
        study_cache[record.id] = known
        if record.owns then world.kept[record.owns] = known.own == true end
    until study_next > study_total or SysTime() >= stop
    if study_next > study_total then
        study_queue, study_next, study_total = {}, 1, 0
        pvs_cache, pvs_count = {}, 0
        ResolveAll()
    end
end

local function RebuildOrder()
    if world == nil or world_map ~= current_map_name then ReadWorldLights() end
    ReadRuntimeOptions()
    local count, steady = 0, 0
    local by_origin, owners = {}, {}
    for index = lamp_count, 1, -1 do lamp_records[index] = nil end
    lamp_count = 0
    for light_id, light_data in pairs(known_lights) do
        count = count + 1
        local record = order[count]
        if not record then
            record = {}
            order[count] = record
        end
        record.id, record.data = light_id, light_data
        if light_data.light and light_data.light.entity then
            lamp_count = lamp_count + 1
            lamp_records[lamp_count] = record
        end
        record.steady = IsSteadyPointLight(light_data.light) and light_data.pos ~= nil
        record.bounded, record.needs, record.slot, record.owns = false, nil, nil, nil
        if record.steady then
            steady = steady + 1
            local origin = light_data.light.origin
            slot_x[steady], slot_y[steady], slot_z[steady] = origin.x, origin.y, origin.z
            record.slot = steady
            record.turn = steady % refresh_frames
            by_origin[OriginKey(origin.x, origin.y, origin.z)] = steady
        else
            -- A map light whose helper is drawn every frame: a spot light, a named or styled light.
            local light = light_data.light
            local origin = light and not light.entity and light_data.pos and light.origin
            if origin and (light.classname == "light" or light.classname == "light_spot")
                and Finite(origin.x) and Finite(origin.y) and Finite(origin.z) then
                owners[OriginKey(origin.x, origin.y, origin.z)] = record
            end
        end
    end
    for index = #order, count + 1, -1 do order[index] = nil end
    for slot = slot_count, steady + 1, -1 do
        slot_x[slot], slot_y[slot], slot_z[slot], slot_seen[slot], slot_shared[slot] = nil, nil, nil, nil, nil
    end
    -- Slots are given anew: nothing is held over from the list before.
    for slot = 1, math.max(slot_count, steady) do slot_held[slot] = nil end
    slot_count = steady
    -- Lights that were removed or recalculated under a new id
    for id, helper in pairs(helpers) do
        if not known_lights[id] then
            if IsValid(helper) then helper:Remove() end
            helpers[id] = nil
            helperPos[id] = nil
        end
    end
    order_source, lights_dirty = known_lights, false
    draw_stats.lights, draw_stats.steady, draw_stats.bounded = count, steady, 0
    study_queue, study_next, study_total = {}, 1, 0
    if not world or not bounded_ok or steady == 0 then return end
    -- Which world light is which steady light's own. A map whose steady lights are mostly not found among its
    -- world lights is not what the study takes it for: every helper every frame.
    local matched, slots, steady_light, kept_light = 0, world.slot, world.steady, world.kept
    for index = 1, world.count do
        local key = OriginKey(world.x[index], world.y[index], world.z[index])
        local slot = steady_light[index] and by_origin[key] or 0
        slots[index], kept_light[index] = slot, false
        if slot ~= 0 then
            matched = matched + 1
        else
            -- The world light of a light whose helper is drawn every frame (the first one at its origin).
            local owner = owners[key]
            if owner and not owner.owns then owner.owns = index end
        end
    end
    if matched * 2 < steady then
        bounded_ok, bounded_note = false, "the map's world lights do not match its light entities"
        return
    end
    for id in pairs(study_cache) do
        if not known_lights[id] then study_cache[id] = nil end
    end
    -- First the lights with a helper every frame: whether that helper sets its light decides what the steady
    -- lights' helpers may be left to set.
    local pending, stale = 0, false
    for index = 1, count do
        local record = order[index]
        if record.owns then
            local known, pos = study_cache[record.id], record.data.pos
            if known and known.owns == record.owns and known.x == pos.x and known.y == pos.y and known.z == pos.z then
                kept_light[record.owns] = known.own == true
            else
                study_cache[record.id] = nil
                pending = pending + 1
                study_queue[pending] = record
                stale = true
            end
        end
    end
    -- (No mark yet: the first study is still going, under these same lights.)
    if stale or (study_mark ~= nil and study_mark ~= StudyMark()) then
        for index = 1, count do
            local record = order[index]
            if record.steady then study_cache[record.id] = nil end
        end
        study_mark = nil
    end
    for index = 1, count do
        local record = order[index]
        if record.steady then
            local known, pos = study_cache[record.id], record.data.pos
            if not (known and known.x == pos.x and known.y == pos.y and known.z == pos.z) then
                study_cache[record.id] = nil
                pending = pending + 1
                study_queue[pending] = record
            end
        end
    end
    study_total = pending
    if pending == 0 then ResolveAll() end
end

-- Fills todo with the indices of the records to draw now; returns how many. Plain numbers only, so the loop is
-- cheap for thousands of lights. The helpers nothing in view needs take their turn in every view of their
-- frame: a frame's first view can be a secondary one (a camera, a mirror) whose draws the runtime takes no
-- lights from.
local dynamic_x, dynamic_y, dynamic_z = {}, {}, {}

local function SelectLights()
    local count, total = 0, #order
    local eye, angles = EyePos(), EyeAngles()
    local forward, right, up = angles:Forward(), angles:Right(), angles:Up()
    local ex, ey, ez = eye.x, eye.y, eye.z
    local fx, fy, fz = forward.x, forward.y, forward.z
    local rx, ry, rz = right.x, right.y, right.z
    local ux, uy, uz = up.x, up.y, up.z
    local view = render.GetViewSetup and render.GetViewSetup() or nil
    local fov = view and tonumber(view.fov) or 90
    if fov < 10 then fov = 10 elseif fov > 170 then fov = 170 end
    local aspect = view and tonumber(view.aspect) or 0
    if aspect <= 0 then aspect = ScrW() / math.max(ScrH(), 1) end
    -- GMod's view setup gives the screen's own horizontal angle as fov and Source's 4:3 angle as fov_unscaled
    -- (106.26 and 90 on a 16:9 screen). Without fov_unscaled the angle is taken as the 4:3 one and widened for
    -- the screen, which can only make the view tested larger.
    local tan_h = math.tan(math.rad(fov) * 0.5)
    local unscaled = view and tonumber(view.fov_unscaled) or nil
    if unscaled and unscaled >= 10 and unscaled <= 170 then
        tan_h = math.max(tan_h, math.tan(math.rad(unscaled) * 0.5) * math.max(1, aspect / (4 / 3)))
    else
        tan_h = tan_h * math.max(1, aspect / (4 / 3))
    end
    local tan_v = tan_h / aspect
    if view_scale > 1 then
        -- rtx.antiCulling.light.fovScale: the runtime scales the view's vertical angle, up to 89 degrees a side.
        local scaled = math.tan(math.min(math.atan(tan_v) * view_scale, 1.55)) / tan_v
        tan_h, tan_v = tan_h * scaled, tan_v * scaled
    end
    tan_h, tan_v = tan_h * VIEW_WIDEN, tan_v * VIEW_WIDEN
    -- Beyond the view's far plane (a map's clip distance) a light is out of the runtime's view as well.
    local far = view and tonumber(view.zfar) or 0
    far = far > 0 and far * 1.05 + VIEW_PAD or math.huge
    local near = match_units + MATCH_PAD
    local near_sqr = near * near
    local frame = FrameNumber()
    -- The dynamic lights known here: the lamps among the lights, and lights made from Lua a moment ago.
    local dynamic = 0
    for index = 1, lamp_count do
        local entity = lamp_records[index].data.light.entity
        if IsValid(entity) then
            local pos = entity:GetPos()
            dynamic = dynamic + 1
            dynamic_x[dynamic], dynamic_y[dynamic], dynamic_z[dynamic] = pos.x, pos.y, pos.z
        end
    end
    if lua_lights.count > 0 then
        for key, entry in pairs(lua_lights.lights) do
            if frame - entry.frame > DYNAMIC_FRAMES or frame < entry.frame then
                lua_lights.lights[key] = nil
                lua_lights.count = lua_lights.count - 1
            elseif entry.x then
                dynamic = dynamic + 1
                dynamic_x[dynamic], dynamic_y[dynamic], dynamic_z[dynamic] = entry.x, entry.y, entry.z
            elseif type(key) == "number" then
                -- No position was seen being written: the entity the light is keyed by.
                local entity = Entity(key)
                if IsValid(entity) then
                    local pos = entity:GetPos()
                    dynamic = dynamic + 1
                    dynamic_x[dynamic], dynamic_y[dynamic], dynamic_z[dynamic] = pos.x, pos.y, pos.z
                end
            end
        end
    end
    -- Which steady point lights the runtime counts as in view now
    for slot = 1, slot_count do
        local dx, dy, dz = slot_x[slot] - ex, slot_y[slot] - ey, slot_z[slot] - ez
        local seen = true
        local depth = dx * fx + dy * fy + dz * fz
        if depth < -VIEW_PAD or depth > far then
            seen = false
        else
            local reach = depth > 0 and depth or 0
            local side = dx * rx + dy * ry + dz * rz
            local limit = reach * tan_h + VIEW_PAD
            if side > limit or side < -limit then
                seen = false
            else
                local height = dx * ux + dy * uy + dz * uz
                limit = reach * tan_v + VIEW_PAD
                if height > limit or height < -limit then seen = false end
            end
        end
        if not seen and dx * dx + dy * dy + dz * dz < near_sqr then seen = true end
        if not seen and dynamic > 0 then
            local x, y, z = slot_x[slot], slot_y[slot], slot_z[slot]
            for at = 1, dynamic do
                local ax, ay, az = x - dynamic_x[at], y - dynamic_y[at], z - dynamic_z[at]
                if ax * ax + ay * ay + az * az < near_sqr then
                    seen = true
                    break
                end
            end
        end
        if seen then
            slot_held[slot] = frame
        else
            local held = slot_held[slot]
            if held and frame - held <= HOLD_FRAMES and frame >= held then seen = true end
        end
        slot_seen[slot] = seen
    end
    local turn = frame % refresh_frames
    for index = 1, total do
        local record = order[index]
        local draw = true
        if record.bounded then
            draw = record.turn == turn
            if not draw then
                local needs = record.needs
                for at = 1, #needs do
                    if slot_seen[needs[at]] then
                        draw = true
                        break
                    end
                end
            end
        end
        if draw then
            count = count + 1
            todo[count] = index
        end
    end
    return count
end

-- Per-frame rendering of helper models
local function RenderLightUpdaters(bDrawingDepth, bDrawingSkybox)
    if bDrawingDepth or bDrawingSkybox then return end
    if not updatelights:GetBool() or not known_lights then return end
    -- Ensure lights are initialized
    if not InitializeLights() then return end
    local frame = FrameNumber()
    if lights_dirty or order_source ~= known_lights then
        RebuildOrder()
        warm_until = frame + 1
    end
    local total = #order
    if total == 0 then return end
    local count
    local mode = drawall:GetInt()
    if mode > 0 or not bounded_ok or frame <= warm_until or (mode == 0 and total < BOUNDED_FROM) then
        count = total
        for index = 1, total do todo[index] = index end
    else
        count = SelectLights()
    end
    draw_stats.drawn = count
    if count > 0 then
        local alpha = debugtext:GetBool() and 1 or 0.001
        local prevR, prevG, prevB = render.GetColorModulation()
        local prevBlend = render.GetBlend()
        render.SetColorModulation(1, 1, 1)
        render.SetBlend(alpha)
        for index = 1, count do
            local record = order[todo[index]]
            local helper = GetHelper(record.id, record.data.pos)
            if helper then helper:DrawModel() end
        end
        render.SetBlend(prevBlend or 1)
        if prevR and prevG and prevB then
            render.SetColorModulation(prevR, prevG, prevB)
        end
    end
    Study(frame)
end

concommand.Add("rtx_lightupdater_status", function()
    local pending = study_total - study_next + 1
    if pending < 0 then pending = 0 end
    print(string.format("[gmRTX - Lightupdater] %d lights, %d of them steady point lights: %d helpers are drawn only while a light they set is in view and on their turn, %d are still being worked out; %d helpers drawn in the last view",
        draw_stats.lights, draw_stats.steady, draw_stats.bounded, pending, draw_stats.drawn))
    if world then
        local kept, other = 0, 0
        for index = 1, world.count do
            if world.kept[index] then kept = kept + 1 elseif world.slot[index] == 0 then other = other + 1 end
        end
        print(string.format("[gmRTX - Lightupdater] %d world lights: %d more are set by their own helpers every frame, %d have none (texture lights and the like)",
            world.count, kept, other))
    end
    if drawall:GetInt() > 0 then
        print("[gmRTX - Lightupdater] rtx_lightupdater_all 1: every light every frame")
    elseif not bounded_ok then
        print("[gmRTX - Lightupdater] every light every frame: " .. tostring(bounded_note))
    elseif not world then
        print("[gmRTX - Lightupdater] every light every frame: the map's world lights could not be read")
    elseif drawall:GetInt() == 0 and draw_stats.lights < BOUNDED_FROM then
        print(string.format("[gmRTX - Lightupdater] every light every frame: the map has fewer than %d lights (rtx_lightupdater_all -1 uses the list all the same)", BOUNDED_FROM))
    else
        print("[gmRTX - Lightupdater] With the Remix free camera (developer menu) no light is kept outside the game's own view: rtx_lightupdater_all 1 while it is used")
    end
end, nil, "Print how many light updater helpers the last view drew")

-- Helper function to draw a circle on screen
local function DrawScreenCircle(center_x, center_y, radius, color, step)
	surface.SetDrawColor(color[1], color[2], color[3], color[4])
	step = step or 10
	for i = 0, 360, step do
		local x1 = center_x + math.cos(math.rad(i)) * radius
		local y1 = center_y + math.sin(math.rad(i)) * radius
		local x2 = center_x + math.cos(math.rad(i + step)) * radius
		local y2 = center_y + math.sin(math.rad(i + step)) * radius
		surface.DrawLine(x1, y1, x2, y2)
	end
end

-- Helper function to draw crosshair
local function DrawScreenCrosshair(center_x, center_y, size, color)
	surface.SetDrawColor(color[1], color[2], color[3], color[4])
	surface.DrawLine(center_x - size, center_y, center_x + size, center_y)
	surface.DrawLine(center_x, center_y - size, center_x, center_y + size)
end

-- Helper function to draw X marker
local function DrawScreenX(center_x, center_y, size, color)
	surface.SetDrawColor(color[1], color[2], color[3], color[4])
	surface.DrawLine(center_x - size, center_y - size, center_x + size, center_y + size)
	surface.DrawLine(center_x - size, center_y + size, center_x + size, center_y - size)
end

-- Draw visual indicators when show lights is enabled
local function DrawLightIndicators()
	if not showlights:GetBool() or not known_lights then return end
	
	for light_id, light_data in pairs(known_lights) do
		local screen_pos = light_data.pos:ToScreen()
		
		if screen_pos.visible then
			-- Use different colors for emergency, moved, vs original positions
			local outer_color, inner_color
			
			if light_data.emergency then
				-- Purple/magenta for emergency positioned lights
				outer_color = {255, 0, 255, 200} -- Magenta
				inner_color = {255, 100, 255, 200} -- Light magenta
			elseif light_data.was_moved then
				-- Orange for moved lights
				outer_color = {255, 100, 0, 200} -- Orange
				inner_color = {255, 200, 0, 200} -- Brighter orange
			else
				-- Cyan for original position lights
				outer_color = {0, 255, 255, 200} -- Cyan
				inner_color = {255, 255, 0, 200} -- Yellow
			end
			
			-- Draw outer circle
			DrawScreenCircle(screen_pos.x, screen_pos.y, 8, outer_color, 10)
			
			-- Draw inner circle
			DrawScreenCircle(screen_pos.x, screen_pos.y, 3, inner_color, 15)
			
			-- Draw crosshair
			DrawScreenCrosshair(screen_pos.x, screen_pos.y, 12, {255, 255, 255, 255})
		end
	end
end

-- Draw debug indicators for moved positions
local function DrawMovedPositionDebug()
	if not debugmoved:GetBool() or not known_lights then return end
	
	for light_id, light_data in pairs(known_lights) do
		if light_data.was_moved then
			local original_screen = light_data.original_pos:ToScreen()
			local adjusted_screen = light_data.pos:ToScreen()
			
			-- Draw line connecting original to adjusted position
			if original_screen.visible and adjusted_screen.visible then
				surface.SetDrawColor(255, 0, 0, 150) -- Red line
				surface.DrawLine(original_screen.x, original_screen.y, adjusted_screen.x, adjusted_screen.y)
			end
			
			-- Draw X marker at original position
			if original_screen.visible then
				DrawScreenX(original_screen.x, original_screen.y, 6, {255, 0, 0, 200})
			end
		end
	end
end

-- Draw debug text in proper HUD hook
local function DrawDebugText()
	if not debugtext:GetBool() or not known_lights then return end
	
	for light_id, light_data in pairs(known_lights) do
		local text_pos = light_data.pos + Vector(0, 0, 16)
		local screen_pos = text_pos:ToScreen()
		
		if screen_pos.visible then
			local class_text = light_data.classname or "light"
			if light_data.emergency then
				class_text = class_text .. NL(" (EMERGENCY)")
			elseif light_data.was_moved then
				class_text = class_text .. NL(" (MOVED)")
			end
			
			-- Add out of bounds warning
			local is_in_world = IsInWorld(light_data.pos)
			local is_reasonable = IsPositionReasonable(light_data.pos, light_data.light.origin)
			
			if not is_in_world or not is_reasonable then
				class_text = class_text .. NL(" (OUT OF BOUNDS)")
			end
			
			local text_color
			if light_data.emergency then
				text_color = Color(255, 0, 255, 255) -- Magenta for emergency
			elseif light_data.was_moved then
				text_color = Color(255, 150, 0, 255) -- Orange for moved
			else
				text_color = Color(255, 255, 0, 255) -- Yellow for normal
			end
			
			draw.SimpleText(
				class_text,
				"DermaDefault",
				screen_pos.x,
				screen_pos.y - 10,
				text_color,
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER
			)
			
			draw.SimpleText(
				string.format("%.0f %.0f %.0f", 
					light_data.pos.x, light_data.pos.y, light_data.pos.z
				),
				"DermaDefault",
				screen_pos.x,
				screen_pos.y + 10,
				Color(255, 255, 255, 255),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER
			)
			
			-- Additional debug info if out of bounds
			if not is_in_world or not is_reasonable then
				draw.SimpleText(
					NL("BOUNDS CHECK FAILED"),
					"DermaDefault",
					screen_pos.x,
					screen_pos.y + 30,
					Color(255, 0, 0, 255),
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER
				)
			end
		end
	end
end

-- Draw debug info for lights that don't have updaters
local function DrawMissingLightsDebug()
	if not debugmissing:GetBool() or not all_discovered_lights then return end
	
	-- Find lights that were discovered but don't have updaters
	for light_id, light in pairs(all_discovered_lights) do
		if not known_lights[light_id] and light.origin then
			local text_pos = light.origin + Vector(0, 0, 20)
			local screen_pos = text_pos:ToScreen()
			
			if screen_pos.visible then
				-- Draw a red X marker
				DrawScreenX(screen_pos.x, screen_pos.y, 8, {255, 0, 0, 200})
				
				-- Draw a red circle around it
				DrawScreenCircle(screen_pos.x, screen_pos.y, 12, {255, 0, 0, 200}, 20)
				
				-- Text showing it's missing
				local class_text = (light.classname or "light") .. NL(" (NO UPDATER)")
				draw.SimpleText(
					class_text,
					"DermaDefault",
					screen_pos.x,
					screen_pos.y - 15,
					Color(255, 0, 0, 255),
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER
				)
				
				-- Show coordinates
				draw.SimpleText(
					string.format("%.0f %.0f %.0f", 
						light.origin.x, light.origin.y, light.origin.z
					),
					"DermaDefault",
					screen_pos.x,
					screen_pos.y + 15,
					Color(255, 100, 100, 255),
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER
				)
			end
		end
	end
end

local function RTXLightUpdater()
	MovetoPositions()
end

-- Cleanup on disconnect/shutdown
local function Cleanup()
	CleanupModel()
	ReleaseHelpers()
	-- Reset force move cvar on cleanup
	forcemove:SetBool(false)
	-- Reset dynamic scan timer
	next_dynamic_scan = 0
end

-- Console command for easier access to force move
local function ForceMoveLightsCommand()
	forcemove:SetBool(true)
	if debugconsole:GetBool() then
		print("[gmRTX - Lightupdater] Force move requested - all light positions will be recalculated next frame")
	end
end

-- Console command for manual dynamic light scanning
local function ScanDynamicLightsCommand()
	ScanForNewDynamicLights()
	if debugconsole:GetBool() then
		print("[gmRTX - Lightupdater] Manual dynamic light scan completed")
	end
end

-- Console command for manual dynamic light position update
local function UpdateDynamicLightsCommand()
	UpdateDynamicLightPositions()
	if debugconsole:GetBool() then
		print("[gmRTX - Lightupdater] Manual dynamic light position update completed")
	end
end

-- Register console commands
concommand.Add("rtx_lightupdater_force_move_cmd", ForceMoveLightsCommand, nil, "Force recalculate all RTX light updater positions")
concommand.Add("rtx_lightupdater_scan_dynamic_cmd", ScanDynamicLightsCommand, nil, "Manually scan for new gmod_light and gmod_lamp entities")
concommand.Add("rtx_lightupdater_update_dynamic_cmd", UpdateDynamicLightsCommand, nil, "Manually update positions for moved dynamic lights")

-- Helper to add/remove optional hooks based on cvars
local function ToggleHook(enabled, hookName, id, fn)
	if enabled then
		hook.Add(hookName, id, fn)
	else
		hook.Remove(hookName, id)
	end
end

local function EvaluateOptionalHooks()
	local enabled = updatelights:GetBool()
	if not enabled then ReleaseHelpers() end

	-- Optional/non-core hooks
	ToggleHook(enabled and dynamicupdate:GetBool(), "Think", "RTXReady_DynamicLightUpdater", UpdateDynamicLightPositions)
	ToggleHook(enabled, "PostDrawTranslucentRenderables", "RTXReady_RenderLightUpdaters", RenderLightUpdaters)
	ToggleHook(enabled and showlights:GetBool(), "HUDPaint", "RTXReady_LightIndicators", DrawLightIndicators)
	ToggleHook(enabled and debugmoved:GetBool(), "HUDPaint", "RTXReady_MovedDebug", DrawMovedPositionDebug)
	ToggleHook(enabled and debugtext:GetBool(), "HUDPaint", "RTXReady_DebugText", DrawDebugText)
	ToggleHook(enabled and debugmissing:GetBool(), "HUDPaint", "RTXReady_MissingLightsDebug", DrawMissingLightsDebug)
end

-- Main/core hook remains always registered (checks master cvar internally)
hook.Add( "Think", "RTXReady_RTXLightUpdater", RTXLightUpdater)

-- Always keep cleanup and map reset hooks
hook.Add( "ShutDown", "RTXReady_Cleanup", Cleanup)
hook.Add( "OnEntityCreated", "RTXReady_MapCheck", function(ent)
	-- Reset when worldspawn is created (new map)
	if ent:GetClass() == "worldspawn" then
		CleanupModel()
		ReleaseHelpers()
	end
end)

-- React to cvar changes to add/remove optional hooks dynamically
cvars.AddChangeCallback("rtx_lightupdater", function()
	EvaluateOptionalHooks()
end, "RTXReady_HookToggle_updatelights")

cvars.AddChangeCallback("rtx_lightupdater_dynamic_update", function()
	EvaluateOptionalHooks()
end, "RTXReady_HookToggle_dynamicupdate")

cvars.AddChangeCallback("rtx_lightupdater_show", function()
	EvaluateOptionalHooks()
end, "RTXReady_HookToggle_show")

cvars.AddChangeCallback("rtx_lightupdater_debug_moved", function()
	EvaluateOptionalHooks()
end, "RTXReady_HookToggle_debugmoved")

cvars.AddChangeCallback("rtx_lightupdater_debug", function()
	EvaluateOptionalHooks()
end, "RTXReady_HookToggle_debugtext")

cvars.AddChangeCallback("rtx_lightupdater_debug_missing", function()
	EvaluateOptionalHooks()
end, "RTXReady_HookToggle_debugmissing")

-- Initial evaluation at load
EvaluateOptionalHooks()