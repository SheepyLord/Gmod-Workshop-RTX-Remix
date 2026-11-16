-- Runs the RTX fixes' Remix light and sky editor Lua under LuaJIT with the engine stubbed (review findings 13, 14
-- and 22): the six light tools apply sandbox's spawn policy (sbox_maxsents, count, creator, prop-protection owner,
-- cleanup, undo) and keep every setting within the light's limits; dupes, the editor's apply message and the spawn
-- message's fallback do too; the stock-light and projected-texture wrappers and the light entity hand the Remix API
-- finite values only; the sky editor is admin-only, its dupes are refused to other players and clamped, and its
-- client clamps what reaches the atmosphere API.
-- Usage: luajit remix_light_limits_harness.lua <scenario> <folder>
-- Scenarios: stools, apply, sky, client. The folder holds the shipped files converted to plain Lua under the short
-- names test_remix_light_limits.py gives them (rt_shared.lua, stool_sphere.lua, sv_rtx.lua, ...).
local scenario, folder = arg[1], arg[2]
assert(scenario and folder, 'usage: remix_light_limits_harness.lua <scenario> <folder>')

local function fail(text) io.stderr:write('FAIL: ' .. text .. '\n') os.exit(1) end
local function check(ok, text) if not ok then fail(text) end return ok end
local NAN, INF = 0 / 0, math.huge
local function finite(v) return type(v) == 'number' and v == v and v ~= INF and v ~= -INF end
local function near(a, b) return finite(a) and math.abs(a - b) <= 1e-6 * math.max(1, math.abs(b)) end

-- Every number in a table, however deep, is finite.
local function allFinite(value, path, seen)
	if type(value) == 'number' then return check(finite(value), path .. ' is ' .. tostring(value)) end
	if type(value) ~= 'table' then return true end
	seen = seen or {}
	if seen[value] then return true end
	seen[value] = true
	for k, v in pairs(value) do allFinite(v, path .. '.' .. tostring(k), seen) end
	return true
end

local function load(name)
	local chunk, err = loadfile(folder .. '/' .. name)
	check(chunk, 'cannot load ' .. name .. ': ' .. tostring(err))
	return chunk()
end

-- Engine stand-ins ---------------------------------------------------------------------------------------------

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
	if type(a) == 'number' then a, b = b, a end
	if type(b) == 'number' then return Vector(a.x * b, a.y * b, a.z * b) end
	return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
function V:DistToSqr(o) local d = self - o return d.x * d.x + d.y * d.y + d.z * d.z end
function V:Distance(o) return math.sqrt(self:DistToSqr(o)) end
local A = {}
A.__index = A
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, A) end
A.__add = function(a, b) return Angle(a.p + b.p, a.y + b.y, a.r + b.r) end
function A:Forward()
	local p, y = math.rad(self.p), math.rad(self.y)
	return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function A:Right() local y = math.rad(self.y) return Vector(math.sin(y), -math.cos(y), 0) end
function A:Up() return Vector(0, 0, 1) end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function isvector(v) return getmetatable(v) == V end
function isangle(v) return getmetatable(v) == A end
function istable(v) return type(v) == 'table' end
function isstring(v) return type(v) == 'string' end
function isnumber(v) return type(v) == 'number' end
function isbool(v) return type(v) == 'boolean' end
function isfunction(v) return type(v) == 'function' end
function IsValid(v) return type(v) == 'table' and type(v.IsValid) == 'function' and v:IsValid() == true end
function math.Clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
function math.AngleDifference(a, b) return (a - b + 180) % 360 - 180 end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function AddCSLuaFile() end
function print() end   -- the entities announce themselves on every spawn
file = { Exists = function() return false end, Find = function() return {}, {} end }
BRANCH = 'x86-64'
local clock = 100
function CurTime() return clock end
local function advance(seconds) clock = clock + seconds end

-- The entity folder whose shared.lua an include("shared.lua") loads.
local currentShared
function include(name) if name == 'shared.lua' and currentShared then return load(currentShared) end end

local convars = {}
local function newConVar(name, value)
	local c = { name = name, value = tostring(value) }
	function c:GetBool() return (tonumber(self.value) or 0) ~= 0 end
	function c:GetFloat() return tonumber(self.value) or 0 end
	function c:GetInt() return math.floor(tonumber(self.value) or 0) end
	function c:GetString() return self.value end
	function c:SetString(v) self.value = tostring(v) end
	convars[name] = c
	return c
end
function CreateConVar(name, default) return convars[name] or newConVar(name, default) end
CreateClientConVar = CreateConVar
function GetConVar(name) return convars[name] end
function RunConsoleCommand(name, value) if convars[name] then convars[name].value = tostring(value) end end
newConVar('rtx_lightupdater', 0)
newConVar('rtx_api_map_lights_env_brightness_mult', 1)

local hooks = {}
hook = {
	Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end,
	Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
	Run = function() end,
}
timer = { Simple = function(_, fn) fn() end, Create = function() end }
concommand = { Add = function() end }
properties = { Add = function() end }
util = { CRC = function() return '12345' end, AddNetworkString = function() end,
	TraceLine = function(t) return { Hit = true, HitPos = Vector(100, 0, 0), HitNormal = Vector(0, 0, 1) } end }
function require() end

-- What a spawn policy did: the cleanup and undo entries it made.
local cleanups, undos, building = {}, {}, nil
cleanup = { Add = function(ply, kind, ent) cleanups[#cleanups + 1] = { ply = ply, kind = kind, ent = ent } end }
undo = {
	Create = function(name) building = { name = name, entities = {} } end,
	AddEntity = function(ent) building.entities[#building.entities + 1] = ent end,
	SetPlayer = function(ply) building.ply = ply end,
	Finish = function(text) building.text = text undos[#undos + 1] = building building = nil end,
}
local stored = {}
duplicator = { StoreEntityModifier = function(ent, name, data) stored[name] = data end,
	RegisterEntityModifier = function() end }

-- Entities: the engine's methods, the class's ENT table first. The NW setters refuse what the engine refuses.
local E = {}
function E:IsValid() return self.valid end
function E:IsPlayer() return false end
function E:GetClass() return self.class end
function E:EntIndex() return self.index end
function E:SetPos(p) self.pos = p end
function E:GetPos() return self.pos end
function E:SetAngles(a) self.ang = a end
function E:GetAngles() return self.ang end
function E:Spawn() if self.Initialize then self:Initialize() end end
function E:Remove() self.removed = true end
function E:GetPhysicsObject() return self.phys end
function E:SetCreator(p) self.creator = p end
function E:CPPISetOwner(p) self.cppiOwner = p end
for _, name in ipairs({ 'Activate', 'SetModel', 'PhysicsInit', 'SetMoveType', 'SetSolid', 'SetNoDraw', 'DrawShadow',
	'SetBodygroup', 'SetMaterial', 'NextThink', 'DrawModel' }) do E[name] = function() end end
local function nwGet(self, k, d) local v = self.nw[k] if v == nil then return d end return v end
function E:SetNWFloat(k, v) check(type(v) == 'number', 'SetNWFloat(' .. k .. ') with a ' .. type(v)) self.nw[k] = v end
function E:SetNWInt(k, v) check(type(v) == 'number', 'SetNWInt(' .. k .. ') with a ' .. type(v)) self.nw[k] = v end
function E:SetNWBool(k, v) self.nw[k] = v and true or false end
function E:SetNWString(k, v)
	check(type(v) == 'string' or type(v) == 'number', 'SetNWString(' .. k .. ') with a ' .. type(v)) self.nw[k] = tostring(v)
end
function E:SetNWVector(k, v) check(isvector(v), 'SetNWVector(' .. k .. ') with a ' .. type(v)) self.nw[k] = v end
function E:SetNWAngle(k, v) check(isangle(v), 'SetNWAngle(' .. k .. ') with a ' .. type(v)) self.nw[k] = v end
E.GetNWFloat, E.GetNWInt, E.GetNWBool, E.GetNWString, E.GetNWVector, E.GetNWAngle = nwGet, nwGet, nwGet, nwGet, nwGet, nwGet

local classes, created, nextIndex = {}, {}, 10
local function newEntity(class, fields)
	nextIndex = nextIndex + 1
	local e = { valid = true, class = class, index = nextIndex, nw = {}, pos = Vector(), ang = Angle() }
	e.phys = { IsValid = function() return true end, EnableMotion = function() end, EnableGravity = function() end,
		Wake = function() end, IsAsleep = function() return true end }
	for k, v in pairs(fields or {}) do e[k] = v end
	local ENTTABLE = classes[class]
	return setmetatable(e, { __index = function(_, k)
		if ENTTABLE and ENTTABLE[k] ~= nil then return ENTTABLE[k] end
		return E[k]
	end })
end
ents = {
	Create = function(class) local e = newEntity(class) created[#created + 1] = e return e end,
	FindByClass = function() return {} end, GetAll = function() return {} end,
}
local byIndex = {}
function Entity(i) return byIndex[i] or { IsValid = function() return false end } end

local function newPlayer(name, admin)
	local p = newEntity('player', { name = name, admin = admin, limitOK = true, limitChecks = 0, counts = {} })
	function p:IsPlayer() return true end
	function p:IsAdmin() return self.admin end
	function p:EyeAngles() return Angle(0, 90, 0) end
	function p:EyePos() return Vector(0, 0, 64) end
	function p:GetAimVector() return Vector(1, 0, 0) end
	function p:CheckLimit(kind) self.limitChecks = self.limitChecks + 1 self.limitKind = kind return self.limitOK end
	function p:AddCount(kind, ent) self.counts[#self.counts + 1] = { kind = kind, ent = ent } end
	return p
end

-- Loads an entity's server or client file with its shared file, as GMod does, into classes[class].
local function loadEntity(class, shared, file)
	ENT = {}
	currentShared = shared
	load(file)
	classes[class] = ENT
	return ENT
end

-- The light's limits as the shipped shared file states them, checked against what a light holds.
local function checkLight(ent, text)
	for key, limit in pairs(RemixRTLight.LIMITS) do
		local v = ent.nw[key]
		if v ~= nil then
			check(finite(v) and v >= limit[1] and v <= limit[2],
				text .. ': ' .. key .. ' = ' .. tostring(v) .. ' is outside ' .. limit[1] .. '..' .. limit[2])
		end
	end
	for key, limit in pairs(RemixRTLight.VECTOR_LIMITS) do
		local v = ent.nw[key]
		if v ~= nil then
			for _, c in ipairs({ 'x', 'y', 'z' }) do
				check(finite(v[c]) and v[c] >= limit[1] and v[c] <= limit[2], text .. ': ' .. key .. '.' .. c .. ' = ' .. tostring(v[c]))
			end
		end
	end
	for key in pairs(RemixRTLight.ANGLE_LIMITS) do
		if ent.nw[key] ~= nil then allFinite(ent.nw[key], text .. ': ' .. key) end
	end
	for key, limit in pairs(RemixRTLight.INT_LIMITS) do
		local v = ent.nw[key]
		if v ~= nil then check(finite(v) and v == math.floor(v) and v >= limit[1] and v <= limit[2], text .. ': ' .. key .. ' = ' .. tostring(v)) end
	end
	check(RemixRTLight.TYPES[ent.nw.rtx_light_type], text .. ': the type ' .. tostring(ent.nw.rtx_light_type) .. ' is not a light type')
end

-- What a client can put in its tool convars.
local CRAFTED_CONVARS = {
	radius = '-1e39', brightness = '1e39', volumetric = 'nan', color_r = '1e39', color_g = '-5', color_b = 'nan',
	freeze = '0', shape_enabled = '1', cone = '1e9', softness = '-5', focus = 'inf', yaw = 'nan', pitch = '-inf',
	xsize = '1e39', ysize = 'nan', xradius = '-inf', yradius = '0', axislen = 'nan', distantang = 'inf',
	light_type = 'bogus', bone_id = 'nan', offset_x = '1e39', offset_y = '0', offset_z = 'nan',
	angle_p = 'inf', angle_y = '0', angle_r = '0',
}

local ToolBase = {}
function ToolBase:GetOwner() return self.owner end
-- GMod: GetInfoNum of the client's convar, the default when it does not parse.
function ToolBase:GetClientNumber(name, default)
	local raw = self.convars[name]
	if raw == nil then raw = self.tool.ClientConVar[name] end
	local n = tonumber(raw)
	if n == nil then return tonumber(default) or 0 end
	return n
end
function ToolBase:GetClientInfo(name) return self.convars[name] or self.tool.ClientConVar[name] or '' end
local function loadTool(file)
	TOOL = { ClientConVar = {} }
	load(file)
	local t = TOOL
	setmetatable(t, { __index = ToolBase })
	return t
end
local function useTool(t, owner, convars) return setmetatable({ owner = owner, convars = convars or {}, tool = t }, { __index = t }) end

local TOOLS = {
	{ file = 'stool_sphere.lua', undo = 'Remix Sphere Light', type = 'sphere' },
	{ file = 'stool_rect.lua', undo = 'Remix Rect Light', type = 'rect' },
	{ file = 'stool_disk.lua', undo = 'Remix Disk Light', type = 'disk' },
	{ file = 'stool_cylinder.lua', undo = 'Remix Cylinder Light', type = 'cylinder' },
	{ file = 'stool_distant.lua', undo = 'Remix Distant Light', type = 'distant' },
	{ file = 'stool_bonemerge.lua', undo = 'Remix Bonemerged Light', type = 'sphere', bonemerge = true },
}

local function newParent()
	local parent = newEntity('prop_physics')
	function parent:GetBoneCount() return 10 end
	function parent:GetBoneMatrix() return { GetTranslation = function() return Vector(1, 2, 3) end,
		GetAngles = function() return Angle(0, 0, 0) end } end
	byIndex[parent.index] = parent
	return parent
end

local function serverLight()
	CLIENT, SERVER = false, true
	loadEntity('remix_rt_light', 'rt_shared.lua', 'rt_init.lua')
	check(type(RemixRTLight) == 'table' and type(RemixRTLight.Spawn) == 'function' and type(RemixRTLight.Apply) == 'function',
		'the light entity shares its spawn policy and limits (RemixRTLight.Spawn, RemixRTLight.Apply)')
end

-- Scenarios ------------------------------------------------------------------------------------------------------

local scenarios = {}

-- Finding 14 (and 13's tool path): each tool asks sbox_maxsents first, then counts the light, names its creator and
-- prop-protection owner, adds it to the player's cleanup and undo; whatever its convars hold, the light's settings
-- stay within the limits; the tools' own ranges are kept.
function scenarios.stools()
	serverLight()
	check(classes.remix_rt_light.Think == nil, 'the light has no server Think: it only scheduled itself for every tick')
	for _, info in ipairs(TOOLS) do
		local t = loadTool(info.file)
		local ply = newPlayer('p', false)
		local trace = { HitPos = Vector(0, 0, 0), HitNormal = Vector(0, 0, 1) }
		if info.bonemerge then trace.Entity = newParent() end

		-- At the limit: no light, nothing counted.
		ply.limitOK = false
		created, cleanups, undos = {}, {}, {}
		check(useTool(t, ply):LeftClick(trace) == false, info.file .. ': a player at sbox_maxsents spawns nothing')
		check(#created == 0 and ply.limitChecks == 1 and ply.limitKind == 'sents', info.file .. ': asks sbox_maxsents before making a light')
		check(#ply.counts == 0 and #cleanups == 0 and #undos == 0, info.file .. ': a refused light is not counted')

		-- Under the limit: the spawn menu's policy, with crafted convars.
		ply.limitOK = true
		check(useTool(t, ply, CRAFTED_CONVARS):LeftClick(trace) == true, info.file .. ': a player under the limit spawns a light')
		local ent = created[1]
		check(#created == 1 and ent.class == 'remix_rt_light', info.file .. ': one light')
		check(#ply.counts == 1 and ply.counts[1].kind == 'sents' and ply.counts[1].ent == ent, info.file .. ': counted against sbox_maxsents')
		check(ent.creator == ply and ent.cppiOwner == ply, info.file .. ': the light names its creator and prop-protection owner')
		check(#cleanups == 1 and cleanups[1].ply == ply and cleanups[1].kind == 'sents' and cleanups[1].ent == ent,
			info.file .. ': in the player\'s cleanup')
		check(#undos == 1 and undos[1].name == info.undo and undos[1].ply == ply and undos[1].entities[1] == ent,
			info.file .. ': in the player\'s undo as ' .. info.undo)
		checkLight(ent, info.file .. ' with crafted convars')
		check(ent.nw.rtx_light_type == info.type, info.file .. ': the type is ' .. info.type)
		check(ent.nw.rtx_light_radius == 1 and ent.nw.rtx_light_brightness == 10000 and ent.nw.rtx_light_volumetric == 1,
			info.file .. ': radius -1e39, brightness 1e39 and volumetric NaN give 1, 10000 and the default 1')
		check(ent.nw.rtx_light_color_r == 255 and ent.nw.rtx_light_color_g == 0 and ent.nw.rtx_light_color_b == 180,
			info.file .. ': the colour 1e39, -5, NaN gives 255, 0 and the default 180')
		if info.bonemerge then
			check(ent.nw.rtx_light_is_bonemerged == true and ent.nw.rtx_light_parent_id == trace.Entity.index
				and ent.nw.rtx_light_bone_id == 0, 'bonemerge: attached to the parent at bone 0 for a bone id of NaN')
			check(ent.nw.rtx_light_offset_pos.x == 0 and ent.nw.rtx_light_offset_pos.z == 0,
				'bonemerge: an offset with a NaN in it is left as it was')
		end

		-- The tools' own ranges stay: a radius and sizes up to the sliders' 2000, brightness up to 10000.
		created = {}
		local normal = { radius = '1500', brightness = '5000', volumetric = '2.5', color_r = '10', color_g = '20',
			color_b = '30', xsize = '1800', ysize = '1700', xradius = '1600', yradius = '1500', axislen = '1900',
			distantang = '2.5', cone = '45', softness = '0.5', focus = '3', shape_enabled = '1', light_type = 'rect',
			offset_x = '50', offset_y = '-60', offset_z = '70', angle_p = '10', angle_y = '20', angle_r = '30' }
		useTool(t, ply, normal):LeftClick(trace)
		ent = created[1]
		check(ent.nw.rtx_light_radius == 1500 and ent.nw.rtx_light_brightness == 5000 and ent.nw.rtx_light_volumetric == 2.5,
			info.file .. ': radius 1500, brightness 5000 and volumetric 2.5 are kept')
		check(ent.nw.rtx_light_color_r == 10 and ent.nw.rtx_light_color_g == 20 and ent.nw.rtx_light_color_b == 30,
			info.file .. ': the colour is kept')
		if info.type == 'rect' then check(ent.nw.rtx_light_xsize == 1800 and ent.nw.rtx_light_ysize == 1700, 'rect: sizes kept') end
		if info.type == 'disk' then check(ent.nw.rtx_light_xradius == 1600 and ent.nw.rtx_light_yradius == 1500, 'disk: radii kept') end
		if info.type == 'cylinder' then check(ent.nw.rtx_light_axis_len == 1900, 'cylinder: axis kept') end
		if info.type == 'distant' then check(ent.nw.rtx_light_distant_angle == 2.5, 'distant: angle kept') end
		if info.bonemerge then
			check(ent.nw.rtx_light_type == 'rect', 'bonemerge: the chosen type is kept')
			local o, a = ent.nw.rtx_light_offset_pos, ent.nw.rtx_light_offset_ang
			check(o.x == 50 and o.y == -60 and o.z == 70 and a.p == 10 and a.y == 20 and a.r == 30, 'bonemerge: offsets kept')
		end

		-- An update (right click; bonemerge has none) is limited too.
		if not info.bonemerge then
			check(useTool(t, ply, CRAFTED_CONVARS):RightClick({ Entity = ent }) == true, info.file .. ': updates a light')
			checkLight(ent, info.file .. ' updated with crafted convars')
			check(ent.nw.rtx_light_radius == 1 and ent.nw.rtx_light_volumetric == 2.5,
				info.file .. ': an update limits the radius and leaves a NaN setting as it was')
		end
	end

	-- Without prop protection there is no CPPI: the rest of the policy still holds.
	E.CPPISetOwner = nil
	created, cleanups = {}, {}
	local ply = newPlayer('q', false)
	useTool(loadTool('stool_sphere.lua'), ply):LeftClick({ HitPos = Vector(), HitNormal = Vector(0, 0, 1) })
	check(#created == 1 and created[1].creator == ply and #cleanups == 1 and #ply.counts == 1, 'the policy holds without CPPI')
end

-- Findings 13 and 14: a dupe, the editor's apply message and the spawn message's fallback.
function scenarios.apply()
	serverLight()
	local light = ents.Create('remix_rt_light')
	light:Spawn()

	-- A crafted dupe: wrong kinds, NaN, infinities, huge numbers. Nothing raises, everything stays in its limits.
	local crafted = {
		rtx_light_type = { 'table' }, rtx_light_radius = '50', rtx_light_brightness = NAN, rtx_light_volumetric = 1e39,
		rtx_light_shape_enabled = 'yes', rtx_light_shape_cone = -INF, rtx_light_xsize = true, rtx_light_color_r = -1e39,
		rtx_light_color_g = INF, rtx_light_is_bonemerged = false, rtx_light_parent_id = 'abc', rtx_light_bone_id = NAN,
		rtx_light_offset_pos = 5, rtx_light_offset_ang = { p = 'x', y = 0, r = 0 }, rtx_light_dir_yaw = 1e39,
		rtx_light_col = { x = 1e39, y = NAN, z = 1 }, rtx_light_dome_tex = string.rep('a', 1000),
	}
	light.EntityMods = { RemixRTLightData = crafted }
	light:PostEntityPaste(nil, light, {})
	checkLight(light, 'a crafted dupe')
	check(light.nw.rtx_light_type == 'sphere' and light.nw.rtx_light_radius == 20 and light.nw.rtx_light_brightness == 1
		and light.nw.rtx_light_volumetric == 5 and light.nw.rtx_light_shape_cone == 90 and light.nw.rtx_light_xsize == 40
		and light.nw.rtx_light_color_r == 0 and light.nw.rtx_light_color_g == 220 and light.nw.rtx_light_dir_yaw == 360
		and light.nw.rtx_light_parent_id == -1 and light.nw.rtx_light_bone_id == -1,
		'a crafted dupe: wrong kinds and NaN are left as they were, the rest clamped')
	check(light.nw.rtx_light_col == nil and #light.nw.rtx_light_dome_tex == 256, 'a crafted dupe: no broken colour, a short texture name')

	-- A genuine dupe comes back exactly.
	local source = ents.Create('remix_rt_light')
	source:Spawn()
	RemixRTLight.Apply(source, { rtx_light_type = 'disk', rtx_light_radius = 1234, rtx_light_brightness = 777,
		rtx_light_xradius = 1999, rtx_light_shape_enabled = true, rtx_light_is_bonemerged = true, rtx_light_parent_id = 42,
		rtx_light_bone_id = 3, rtx_light_offset_pos = Vector(1, -2, 3), rtx_light_offset_ang = Angle(4, 5, 6) })
	source:PreEntityCopy()
	local copy = ents.Create('remix_rt_light')
	copy:Spawn()
	copy.EntityMods = { RemixRTLightData = stored.RemixRTLightData }
	copy:PostEntityPaste(newPlayer('p', false), copy, {})
	for key, value in pairs(source.nw) do
		local got = copy.nw[key]
		if isvector(value) or isangle(value) then
			check(getmetatable(got) == getmetatable(value) and allFinite(got, key), 'a genuine dupe keeps ' .. key)
			for _, c in ipairs(isvector(value) and { 'x', 'y', 'z' } or { 'p', 'y', 'r' }) do
				check(got[c] == value[c], 'a genuine dupe keeps ' .. key .. '.' .. c)
			end
		else
			check(got == value, 'a genuine dupe keeps ' .. key .. ' (' .. tostring(value) .. ', got ' .. tostring(got) .. ')')
		end
	end

	-- The editor's apply message (admins only) changes what it always could, within the limits.
	NATIVELOADER_VERIFIED_MULTIPLAYER = true
	local receivers, incoming = {}, {}
	net = { Receive = function(name, fn) receivers[name] = fn end, ReadEntity = function() return table.remove(incoming, 1) end,
		ReadTable = function() return table.remove(incoming, 1) end }
	scripted_ents = { GetStored = function() return { t = classes.remix_rt_light } end,
		GetMember = function(_, name) return classes.remix_rt_light[name] end }
	load('sv_rtx.lua')
	local function send(name, ply, ...) incoming = { ... } check(receivers[name], 'no receiver for ' .. name)(0, ply) end
	local edited = ents.Create('remix_rt_light')
	edited:Spawn()
	send('remix_rt_light_apply', newPlayer('p', false), edited, { rtx_light_radius = 50 })
	check(edited.nw.rtx_light_radius == 20, 'a player who is not an admin changes nothing')
	send('remix_rt_light_apply', newPlayer('a', true), edited, { rtx_light_radius = 1e39, rtx_light_brightness = NAN,
		rtx_light_type = 'CYLINDER', rtx_light_color_b = -3, rtx_light_col = { x = '5', y = 6, z = 1e9 },
		rtx_light_shape_enabled = true, rtx_light_parent_id = 5, rtx_light_is_bonemerged = true,
		rtx_light_offset_pos = { x = 1, y = 2, z = 3 }, rtx_light_dir_pitch = 10 })
	checkLight(edited, 'an editor message')
	check(edited.nw.rtx_light_radius == 2000 and edited.nw.rtx_light_brightness == 1 and edited.nw.rtx_light_type == 'cylinder'
		and edited.nw.rtx_light_color_b == 0 and edited.nw.rtx_light_shape_enabled == true,
		'an editor message: clamped, NaN left as it was, the type lowercased')
	local col = edited.nw.rtx_light_col
	check(col and col.x == 5 and col.y == 6 and col.z == 10000, 'an editor message: the colour vector clamped')
	check(edited.nw.rtx_light_parent_id == -1 and edited.nw.rtx_light_is_bonemerged == false
		and edited.nw.rtx_light_offset_pos.x == 0 and edited.nw.rtx_light_dir_pitch == -90,
		'an editor message changes only the settings the editor always could')
	send('remix_rt_light_apply', newPlayer('a', true), edited, { rtx_light_radius = 1500, rtx_light_xsize = 1800 })
	check(edited.nw.rtx_light_radius == 1500 and edited.nw.rtx_light_xsize == 1800,
		'the editor\'s slider range (radius and sizes to 2000) is kept by the server')

	-- The spawn message: sandbox's Spawn_SENT when there is one, else admins only under the same policy as the tools.
	local spawned = {}
	Spawn_SENT = function(ply, class) spawned[#spawned + 1] = { ply = ply, class = class } end
	local p = newPlayer('p', false)
	send('remix_spawn_rt_light', p)
	check(#spawned == 1 and spawned[1].ply == p and spawned[1].class == 'remix_rt_light', 'sandbox spawns through Spawn_SENT')
	Spawn_SENT = nil
	created, cleanups, undos = {}, {}, {}
	advance(1)
	send('remix_spawn_rt_light', p)
	check(#created == 0, 'without sandbox, a player who is not an admin spawns nothing')
	local admin = newPlayer('a', true)
	admin.limitOK = false
	advance(1)
	send('remix_spawn_rt_light', admin)
	check(#created == 0 and admin.limitChecks == 1, 'without sandbox, the limit is asked where the gamemode has one')
	admin.limitOK = true
	advance(1)
	send('remix_spawn_rt_light', admin)
	local ent = created[1]
	check(#created == 1 and ent.creator == admin and ent.cppiOwner == admin and #admin.counts == 1
		and #cleanups == 1 and cleanups[1].kind == 'sents' and #undos == 1 and undos[1].text == 'Remix RT Light',
		'without sandbox, an admin\'s light is counted, owned, in the cleanup and in the undo')
end

-- Finding 22: the sky editor is admin-only; a dupe is refused to other players and clamped; the apply message is
-- clamped; a client clamps what reaches the atmosphere API.
function scenarios.sky()
	CLIENT, SERVER = false, true
	local SKY = loadEntity('remix_sky_editor', 'sky_shared.lua', 'sky_init.lua')
	check(SKY.AdminOnly == true and SKY.Spawnable == true, 'the sky editor is spawnable by admins only (ENT.AdminOnly)')
	check(type(RemixSkyEditor) == 'table' and type(RemixSkyEditor.Apply) == 'function', 'the sky editor shares its limits')
	local function checkSky(ent, text)
		for key, limit in pairs(RemixSkyEditor.LIMITS) do
			local v = ent.nw[key]
			check(finite(v) and v >= limit[1] and v <= limit[2], text .. ': ' .. key .. ' = ' .. tostring(v))
		end
	end
	local crafted = { sky_planet_radius = 0, sky_sun_intensity = 1e30, sky_altitude = NAN, sky_mie_anisotropy = -INF,
		sky_ozone_width = 'x', sky_illum_r = -1e30, sky_rayleigh_b = 1e30, sky_sun_disc = false }

	local sky = ents.Create('remix_sky_editor')
	sky:Spawn()
	sky.EntityMods = { RemixSkyEditorData = crafted }
	sky:PostEntityPaste(newPlayer('p', false), sky, {})
	check(sky.removed == true and sky.nw.sky_planet_radius == 6371 and sky.nw.sky_sun_disc == true,
		'a player who is not an admin cannot paste a sky editor; nothing of the dupe is applied')
	for _, by in ipairs({ newPlayer('a', true), false }) do
		sky = ents.Create('remix_sky_editor')
		sky:Spawn()
		sky.EntityMods = { RemixSkyEditorData = crafted }
		sky:PostEntityPaste(by or nil, sky, {})
		local who = by and 'an admin\'s paste' or 'a server restore'
		check(not sky.removed, who .. ' keeps the sky editor')
		checkSky(sky, who)
		check(sky.nw.sky_planet_radius == 1000 and sky.nw.sky_sun_intensity == 100 and sky.nw.sky_altitude == 100
			and sky.nw.sky_mie_anisotropy == 0.97 and sky.nw.sky_ozone_width == 15 and sky.nw.sky_illum_r == 0
			and sky.nw.sky_rayleigh_b == 0.1 and sky.nw.sky_sun_disc == false, who .. ': 0, 1e30 and -1e30 clamped, NaN and text left')
	end

	-- The apply message (admins only), through the same limits.
	NATIVELOADER_VERIFIED_MULTIPLAYER = true
	local receivers, incoming = {}, {}
	net = { Receive = function(name, fn) receivers[name] = fn end, ReadEntity = function() return table.remove(incoming, 1) end,
		ReadTable = function() return table.remove(incoming, 1) end }
	load('sv_rtx.lua')
	sky = ents.Create('remix_sky_editor')
	sky:Spawn()
	incoming = { sky, { sky_sun_intensity = 50 } }
	receivers.remix_sky_editor_apply(0, newPlayer('p', false))
	check(sky.nw.sky_sun_intensity == 1.0, 'a player who is not an admin changes nothing')
	incoming = { sky, { sky_sun_intensity = 1e30, sky_planet_radius = NAN, sky_ozone_r = -1, sky_sun_size = 2 } }
	receivers.remix_sky_editor_apply(0, newPlayer('a', true))
	checkSky(sky, 'an admin\'s apply message')
	check(sky.nw.sky_sun_intensity == 100 and sky.nw.sky_planet_radius == 6371 and sky.nw.sky_ozone_r == 0
		and sky.nw.sky_sun_size == 2, 'an admin\'s apply message: clamped, NaN left as it was')

	-- A client: whatever the networked values and angles, the atmosphere API gets finite values within the limits.
	CLIENT, SERVER = true, false
	local calls = {}
	RemixAtmosphere = setmetatable({ MODE_PHYSICAL = 1, MODE_SKYBOX = 0 }, { __index = function(t, name)
		local fn = function(...) calls[#calls + 1] = { name = name, args = { ... } } end
		rawset(t, name, fn)
		return fn
	end })
	loadEntity('remix_sky_editor', 'sky_shared.lua', 'sky_cl_init.lua')
	local client = newEntity('remix_sky_editor', { ang = Angle(NAN, INF, 0) })
	function ents.FindByClass() return { client } end
	client.nw = { sky_sun_intensity = NAN, sky_planet_radius = 0, sky_altitude = 1e30, sky_mie_anisotropy = -1e30,
		sky_rayleigh_r = INF, sky_ozone_alt = -INF, sky_illum_g = 1e39 }
	client:Initialize()
	client:Think()
	local seen = {}
	for _, call in ipairs(calls) do
		seen[call.name] = call.args
		allFinite(call.args, 'RemixAtmosphere.' .. call.name)
	end
	check(seen.SetPlanetRadius and seen.SetPlanetRadius[1] == 1000 and seen.SetAltitude[1] == 100000
		and seen.SetSunIntensity[1] == 1.0 and seen.SetMieAnisotropy[1] == -1 and seen.SetRayleighScattering[1] == 0.0058
		and seen.SetOzoneLayer[1] == 25 and seen.SetSunIlluminance[2] == 100,
		'a client clamps the sky\'s values and puts the default in for what is not a number')
	check(seen.SetSunElevation == nil and seen.SetSunRotation == nil, 'a sun angle that is not a number is not sent')
	calls = {}
	client.ang = Angle(-15, 30, 0)
	client.nw = { sky_planet_radius = 3389.5, sky_sun_intensity = 2 }
	client:Think()
	seen = {}
	for _, call in ipairs(calls) do seen[call.name] = call.args end
	check(seen.SetSunElevation and seen.SetSunElevation[1] == 15 and seen.SetSunRotation[1] == 60
		and seen.SetPlanetRadius[1] == 3389.5 and seen.SetSunIntensity[1] == 2, 'a client passes a valid sky through unchanged')
end

-- Finding 13: what the stock-light and projected-texture wrappers and the light entity hand the Remix API.
function scenarios.client()
	CLIENT, SERVER = true, false
	local calls = {}
	local nextId = 0
	RemixLight = setmetatable({}, { __index = function(t, name)
		local fn = function(base, info, id)
			nextId = nextId + 1
			calls[#calls + 1] = { name = name, base = base, info = info, id = id }
			return nextId
		end
		rawset(t, name, fn)
		return fn
	end })
	local function lastCall() return calls[#calls] end
	local function checkLightCall(call, text)
		check(call, text .. ': no Remix light call')
		allFinite(call.base, text .. ' base')
		allFinite(call.info, text .. ' info')
		local r = call.base.radiance
		check(r.x >= 0 and r.y >= 0 and r.z >= 0, text .. ': negative radiance')
		local info = call.info
		for _, key in ipairs({ 'radius', 'xRadius', 'yRadius', 'xSize', 'ySize', 'axisLength', 'angularDiameterDegrees' }) do
			if info[key] ~= nil then check(info[key] >= 0, text .. ': negative ' .. key) end
		end
		if info.shaping then
			check(info.shaping.coneAngleDegrees >= 0 and info.shaping.coneAngleDegrees <= 180, text .. ': cone angle out of range')
		end
	end

	-- The stock light and lamp wrapper.
	load('light_wrapper.lua')
	local function light(class, fields)
		local e = newEntity(class, fields)
		e.color = e.color or { r = 255, g = 0, b = 0 }
		function e:GetColor() return self.color end
		function e:IsDormant() return false end
		function e:GetNoDraw() return false end
		function e:GetOn() return true end
		function e:GetBrightness() return self.brightness end
		if class == 'gmod_light' then function e:GetLightSize() return self.size end
		else
			function e:GetDistance() return self.distance end
			function e:GetLightFOV() return self.fov end
		end
		return e
	end
	local created_ = hooks.OnEntityCreated.RTXLightWrapper_EntityCreated
	for _, case in ipairs({ { INF, 256 }, { NAN, 256 }, { 1e39, 256 }, { -5, 256 }, { 2, -5 }, { 2, INF }, { 2, NAN }, { 2, 1e39 } }) do
		created_(light('gmod_light', { brightness = case[1], size = case[2] }))
		checkLightCall(lastCall(), 'gmod_light brightness ' .. tostring(case[1]) .. ' size ' .. tostring(case[2]))
	end
	local r256 = math.pow(256, 0.1) * 1.5
	created_(light('gmod_light', { brightness = 2, size = 256 }))
	local call = lastCall()
	check(near(call.base.radiance.x, 255) and call.base.radiance.y == 0 and near(call.info.radius, r256),
		'a normal light (brightness 2, size 256) is as it was')
	created_(light('gmod_light', { brightness = 20, size = 1024 }))
	check(near(lastCall().base.radiance.x, 2550), 'the light tool\'s brightness 20 is kept')
	for _, case in ipairs({ { INF, NAN, INF }, { NAN, -1, NAN }, { 1e39, 1e39, 0 }, { 4, 1024, 1e9 } }) do
		created_(light('gmod_lamp', { brightness = case[1], distance = case[2], fov = case[3] }))
		call = lastCall()
		checkLightCall(call, 'gmod_lamp ' .. table.concat({ tostring(case[1]), tostring(case[2]), tostring(case[3]) }, ' '))
		check(call.info.shaping.coneAngleDegrees >= 5 and call.info.shaping.coneAngleDegrees <= 85, 'a lamp cone within 5..85')
	end
	created_(light('gmod_lamp', { brightness = 4, distance = 1024, fov = 90, color = { r = 255, g = 255, b = 255 } }))
	call = lastCall()
	check(near(call.base.radiance.x, 255) and call.info.shaping.coneAngleDegrees == 45
		and near(call.info.radius, math.pow(1024, 0.1) * 5), 'a normal lamp is as it was')
	-- An update of a wrapped light with values that turned bad.
	local bad = light('gmod_light', { brightness = 2, size = 256 })
	created_(bad)
	bad.brightness, bad.size = NAN, INF
	bad.color = { r = 0, g = 255, b = 0 }
	advance(1)
	local before = #calls
	hooks.PreRender.RTXLightWrapper_UpdateLights()
	check(#calls > before, 'a changed light is updated')
	for i = before + 1, #calls do checkLightCall(calls[i], 'an update of a light gone bad') end

	-- The projected-texture wrapper.
	local made = {}
	ProjectedTexture = function()
		local pt = { valid = true, color = { r = 255, g = 255, b = 255 }, brightness = 1, fov = 90, farz = 1500 }
		function pt:IsValid() return self.valid end
		function pt:GetPos() return Vector(0, 0, 0) end
		function pt:GetAngles() return Angle(0, 0, 0) end
		function pt:GetColor() return self.color end
		function pt:GetBrightness() return self.brightness end
		function pt:GetHorizontalFOV() return self.fov end
		function pt:GetFarZ() return self.farz end
		made[#made + 1] = pt
		return pt
	end
	load('pt_wrapper.lua')
	local normal = ProjectedTexture()
	hooks.Think.RTXProjectedTexture_Update()
	call = lastCall()
	check(call and near(call.base.radiance.x, 1275) and near(call.info.radius, 1.5) and call.info.shaping.coneAngleDegrees == 45,
		'a normal projected texture is as it was')
	normal.valid = false
	hooks.Think.RTXProjectedTexture_Update()
	for _, case in ipairs({ { INF, NAN, INF, { r = NAN, g = 1e39, b = -5 } }, { NAN, 0, NAN, { r = 1, g = 2, b = 3 } },
		{ 1e39, 1e9, -1e39, { r = 255, g = 255, b = 255 } } }) do
		local pt = ProjectedTexture()
		pt.brightness, pt.fov, pt.farz, pt.color = case[1], case[2], case[3], case[4]
		before = #calls
		hooks.Think.RTXProjectedTexture_Update()
		check(#calls > before, 'a projected texture gets a Remix light')
		call = lastCall()
		checkLightCall(call, 'a crafted projected texture')
		check(call.info.radius <= 32.768 and call.info.shaping.coneAngleDegrees >= 0.5
			and call.info.shaping.coneAngleDegrees <= 89.5, 'a projected texture\'s reach and cone are bounded')
		pt.valid = false
		hooks.Think.RTXProjectedTexture_Update()
	end

	-- The light entity on a client: every networked number reaches the Remix API within the limits.
	loadEntity('remix_rt_light', 'rt_shared.lua', 'rt_cl_init.lua')
	local crafted = { rtx_light_radius = NAN, rtx_light_brightness = 1e39, rtx_light_volumetric = -INF,
		rtx_light_color_r = INF, rtx_light_color_g = -1e39, rtx_light_color_b = NAN, rtx_light_shape_enabled = true,
		rtx_light_shape_cone = 1e9, rtx_light_shape_softness = NAN, rtx_light_shape_focus = INF, rtx_light_xsize = -1e39,
		rtx_light_ysize = NAN, rtx_light_xradius = INF, rtx_light_yradius = 1e39, rtx_light_axis_len = NAN,
		rtx_light_distant_angle = 1e39, rtx_light_col = Vector(NAN, 1e39, -5) }
	for _, lt in ipairs({ 'sphere', 'rect', 'disk', 'cylinder', 'distant' }) do
		local ent = newEntity('remix_rt_light')
		for k, v in pairs(crafted) do ent.nw[k] = v end
		ent.nw.rtx_light_type = lt
		before = #calls
		ent:Think()
		check(#calls >= before + 2, lt .. ': the light is created and updated')
		for i = before + 1, #calls do checkLightCall(calls[i], lt .. ' light ' .. calls[i].name) end
		check(calls[before + 1].name:find('^Create') and calls[#calls].name:find('^Update'), lt .. ': create, then update')
		local info = calls[#calls].info
		if lt == 'sphere' then check(info.radius == 20 and info.shaping.coneAngleDegrees == 180, 'sphere: NaN radius gives 20, cone 180') end
		if lt == 'rect' then check(info.xSize == 1 and info.ySize == 40, 'rect: sizes clamped') end
		if lt == 'disk' then check(info.xRadius == 20 and info.yRadius == 2000, 'disk: radii clamped') end
		if lt == 'cylinder' then check(info.axisLength == 40 and info.radius == 20, 'cylinder: axis and radius clamped') end
		if lt == 'distant' then check(info.angularDiameterDegrees == 10, 'distant: angle clamped') end
		local r = calls[#calls].base.radiance
		check(near(r.x, 255 / 12 * 10000) and r.y == 0 and near(r.z, 180 / 12 * 10000), lt .. ': radiance from clamped colour and brightness')
	end
	-- A bonemerged light whose offsets are not numbers stays where its bone is.
	local parent = newParent()
	local ent = newEntity('remix_rt_light')
	ent.nw = { rtx_light_type = 'sphere', rtx_light_is_bonemerged = true, rtx_light_parent_id = parent.index,
		rtx_light_bone_id = 2, rtx_light_offset_pos = Vector(NAN, INF, 1e39), rtx_light_offset_ang = Angle(NAN, 0, 0) }
	before = #calls
	ent:Think()
	allFinite(ent.pos, 'a bonemerged light\'s position')
	allFinite(ent.ang, 'a bonemerged light\'s angles')
	check(ent.pos.x == 1 and ent.pos.y == 2 and ent.pos.z == 3, 'a broken offset leaves the light at its bone')
	for i = before + 1, #calls do checkLightCall(calls[i], 'a bonemerged light') end
	-- A valid light is passed through as it is.
	ent = newEntity('remix_rt_light')
	ent.nw = { rtx_light_type = 'sphere', rtx_light_radius = 1500, rtx_light_brightness = 12, rtx_light_color_r = 120,
		rtx_light_color_g = 60, rtx_light_color_b = 30, rtx_light_volumetric = 2 }
	ent:Think()
	call = lastCall()
	check(call.info.radius == 1500 and call.info.volumetricRadianceScale == 2 and near(call.base.radiance.x, 120)
		and near(call.base.radiance.y, 60), 'a valid light is passed through unchanged')
end

local run = scenarios[scenario]
check(run, 'unknown scenario ' .. tostring(scenario))
run()
io.write('PASS ' .. scenario .. '\n')
