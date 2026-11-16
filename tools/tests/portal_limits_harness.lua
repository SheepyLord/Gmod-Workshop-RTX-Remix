-- Runs the Seamless Portals entity's shipped files under LuaJIT with the engine stubbed (review finding 5): a portal
-- whose side count and size network vars hold what a crafted dupe restores (the duplicator calls the generated
-- setters, never ENT:SetSides or ENT:SetSize) builds a bounded physics hull and render mesh on the server and on
-- every client, keeps the tools' sizes as they were, and stores bounded values again when it is pasted.
-- Usage: luajit portal_limits_harness.lua <folder>, the folder holding sh_init.lua, init.lua and cl_init.lua
-- converted to plain Lua (test_portal_limits.py does that).
local folder = assert(arg[1], 'folder with the converted portal files')

local function fail(text) io.stderr:write('FAIL: ' .. text .. '\n') os.exit(1) end
local function check(ok, text) if not ok then fail(text) end end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local NAN, INF = 0 / 0, math.huge

-- Vectors that count themselves: a runaway loop (two billion sides) stops at the budget instead of eating memory.
local made, BUDGET = 0, 100000
local V = {}
function V.__index(v, k)
	if k == 'x' then return rawget(v, 1) elseif k == 'y' then return rawget(v, 2) elseif k == 'z' then return rawget(v, 3) end
	return V[k]
end
function Vector(x, y, z)
	made = made + 1
	if made > BUDGET then error('runaway: more than ' .. BUDGET .. ' vectors in one call', 0) end
	return setmetatable({ x or 0, y or 0, z or 0 }, V)
end
V.__mul = function(a, b)
	if type(b) == 'number' then return Vector(a[1] * b, a[2] * b, a[3] * b) end
	return Vector(a[1] * b[1], a[2] * b[2], a[3] * b[3])
end
V.__unm = function(a) return Vector(-a[1], -a[2], -a[3]) end
V.__eq = function(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
function V:Mul(o) for i = 1, 3 do self[i] = self[i] * (type(o) == 'number' and o or o[i]) end return self end
local A = {}
A.__index = A
function Angle(p, y, r) return setmetatable({ p or 0, y or 0, r or 0 }, A) end
A.__add = function(a, b) return Angle(a[1] + b[1], a[2] + b[2], a[3] + b[3]) end

-- One call with a fresh vector budget; returns how many vectors it made.
local function bounded(text, fn, ...)
	made = 0
	local ok, err = pcall(fn, ...)
	check(ok, text .. ': ' .. tostring(err))
	return made
end

local function load(name)
	local chunk, err = loadfile(folder .. '/' .. name)
	check(chunk, 'cannot load ' .. name .. ': ' .. tostring(err))
	chunk()
end

-- GMod's math.Clamp: NaN passes it, as in the game.
function math.Clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
function IsValid(v) return type(v) == 'table' and v.valid ~= false end
function include() end
function AddCSLuaFile() end
file = { Exists = function() return false end }
SOLID_VPHYSICS, MOVETYPE_VPHYSICS, RENDERMODE_TRANSCOLOR, COLLISION_GROUP_WORLD, TRANSMIT_ALWAYS = 6, 6, 1, 20, 0
RENDERGROUP_OPAQUE, CONTENTS_GRATE = 1, 8
table.RemoveByValue = function() end
function string.Split(s, sep)
	local out = {}
	for part in string.gmatch(s, '[^' .. sep .. ']+') do out[#out + 1] = part end
	return out
end

-- A portal: its network vars, a physics object and a record of the hull it was given.
local function portal(sides, size)
	local p = { valid = true, dt = { SidesInternal = sides, SizeInternal = size or Vector(0, 0, 0) }, hulls = {} }
	local phys = { IsValid = function() return false end, EnableMotion = function() end, SetMaterial = function() end,
		SetMass = function() end, SetPos = function() end, SetAngles = function() end }
	function p:GetSidesInternal() return self.dt.SidesInternal end
	function p:SetSidesInternal(v) self.dt.SidesInternal = v end
	function p:GetSizeInternal() local s = self.dt.SizeInternal return setmetatable({ s[1], s[2], s[3] }, V) end
	function p:SetSizeInternal(v) self.dt.SizeInternal = setmetatable({ v[1], v[2], v[3] }, V) end
	function p:PhysicsInitConvex(points) self.hulls[#self.hulls + 1] = #points end
	function p:GetPhysicsObject() return phys end
	for _, name in ipairs({ 'SetMoveType', 'SetSolid', 'EnableCustomCollisions', 'SetRenderBounds', 'SetModel',
		'PhysicsInit', 'PhysWake', 'SetRenderMode', 'SetCollisionGroup', 'DrawShadow', 'SetAngles', 'SetPos' }) do
		p[name] = function() end
	end
	function p:GetAngles() return Angle() end
	function p:GetPos() return Vector() end
	function p:GetVelocity() return Vector() end
	function p:GetCreator() return nil end
	return setmetatable(p, { __index = ENT })
end
local function lastHull(p) return p.hulls[#p.hulls] end
local function within(size)
	return size[1] >= 1 and size[1] <= 2048 and size[2] >= 1 and size[2] <= 2048 and size[3] >= 1 and size[3] <= 256
end

-- The crafted side counts a dupe can hold, and what each must become.
local CRAFTED = { { 2147483647, 100 }, { 0, 3 }, { -5, 3 }, { NAN, 4 }, { INF, 4 }, { -INF, 4 }, { 1e300, 100 }, { 3.7, 3 } }

---------------------------------------------------------------------------------------------------- the server
CLIENT, SERVER = false, true
ENT = {}
SeamlessPortals = nil
load('sh_init.lua')
duplicator = { RegisterEntityModifier = function() end, StoreEntityModifier = function() end }
timer = { Simple = function() end }
ents = { FindByName = function() return {} end }
load('init.lua')
check(type(SeamlessPortals.LimitSides) == 'function' and type(ENT.GetSides) == 'function',
	'the side limit is shared (SeamlessPortals.LimitSides, ENT:GetSides)')

-- The tools' side counts keep their hulls: two points a side.
for _, sides in ipairs({ 3, 4, 50, 100 }) do
	local p = portal(4, Vector(50, 50, 8))
	p:SetSides(sides)
	p:UpdatePhysmesh()
	check(lastHull(p) == sides * 2, sides .. ' sides make a hull of ' .. sides * 2 .. ' points, not ' .. tostring(lastHull(p)))
end
-- ENT:SetSides with a crafted number stores a side count within the limits.
for _, case in ipairs(CRAFTED) do
	local p = portal(4, Vector(50, 50, 8))
	bounded('SetSides(' .. tostring(case[1]) .. ')', p.SetSides, p, case[1])
	check(p.dt.SidesInternal == case[2], 'SetSides(' .. tostring(case[1]) .. ') stores ' .. case[2] .. ', not ' .. tostring(p.dt.SidesInternal))
end

-- The duplicator's path: the raw network var, then a hull built from it on the server.
for _, case in ipairs(CRAFTED) do
	local p = portal(case[1], Vector(50, 50, 8))
	local vectors = bounded('UpdatePhysmesh with ' .. tostring(case[1]) .. ' sides', p.UpdatePhysmesh, p)
	check(lastHull(p) == case[2] * 2 and lastHull(p) <= 200,
		tostring(case[1]) .. ' sides from a dupe build a hull of ' .. case[2] * 2 .. ' points, not ' .. tostring(lastHull(p)))
	check(vectors <= 1000, tostring(case[1]) .. ' sides made ' .. vectors .. ' vectors')
	check(p:GetSides() == case[2], 'GetSides() of ' .. tostring(case[1]) .. ' is ' .. case[2])
end

-- Sizes: finite, within the limits, the default for what is not a number; the tools' sizes as they were.
local p = portal(4, Vector(1e30, -1e30, NAN))
local size = p:GetSize()
check(size[1] == 2048 and size[2] == 1 and size[3] == 8, 'GetSize() of (1e30, -1e30, NaN) is (2048, 1, 8), not ('
	.. tostring(size[1]) .. ', ' .. tostring(size[2]) .. ', ' .. tostring(size[3]) .. ')')
p.dt.SizeInternal = Vector(INF, NAN, -INF)
size = p:GetSize()
check(size[1] == 50 and size[2] == 50 and size[3] == 8, 'GetSize() of (inf, NaN, -inf) is the default (50, 50, 8)')
p.dt.SizeInternal = Vector(0, 0, 0)
check(within(p:GetSize()), 'a zero size reads within the limits (no division by zero in the teleport)')
for _, keep in ipairs({ { 500, 500, 100 }, { 999.9, 999.9, 8 }, { 33, 17, 8 }, { 1, 1, 1 }, { 2048, 2048, 8 } }) do
	p:SetSize(Vector(keep[1], keep[2], keep[3]))
	size = p:GetSize()
	check(near(size[1], keep[1]) and near(size[2], keep[2]) and near(size[3], keep[3]),
		'the size (' .. table.concat(keep, ', ') .. ') stays as it was')
end
local scaled = p:GetSize()
scaled:Mul(2)
check(p:GetSize()[1] == 2048, 'GetSize() hands out a new vector each time (callers scale it in place)')
-- ENT:SetSize stores a size within the limits.
p:SetSize(Vector(1e30, NAN, -5))
check(within(p.dt.SizeInternal) and p.dt.SizeInternal[2] == 50, 'SetSize stores (2048, 50, 1) for (1e30, NaN, -5)')
-- A Hammer portal of 4096 x 4096 units keeps its size.
p = portal(4)
p:KeyValue('size', '4096 4096 8')
size = p:GetSize()
check(size[1] == 2048 and size[2] == 2048 and size[3] == 8, 'a Hammer portal of 4096 x 4096 keeps its size')

-- A pasted portal: the dupe's values before Spawn, Initialize, the values again (duplicator.Paste restores the
-- network vars a second time), then PostEntityPaste stores values within the limits.
p = portal(2147483647, Vector(1e30, 1e30, 1e30))
bounded('Initialize of a crafted dupe', p.Initialize, p)
check(lastHull(p) == 200, 'the crafted portal spawns with a hull of 200 points, not ' .. tostring(lastHull(p)))
check(within(p.dt.SizeInternal), 'Initialize stores the size within the limits')
p.dt.SidesInternal, p.dt.SizeInternal = 2147483647, Vector(NAN, -1e30, 1e30)
bounded('PostEntityPaste of a crafted dupe', p.PostEntityPaste, p, nil, p, {})
check(p.dt.SidesInternal == 100, 'PostEntityPaste stores 100 sides, not ' .. tostring(p.dt.SidesInternal))
check(within(p.dt.SizeInternal) and p.dt.SizeInternal[1] == 50 and p.dt.SizeInternal[2] == 1 and p.dt.SizeInternal[3] == 256,
	'PostEntityPaste stores the size within the limits')
check(lastHull(p) == 200, 'and rebuilds the hull from them')
-- A portal nobody sized gets the default size; a sized one keeps it.
p = portal(4)
p:Initialize()
size = p.dt.SizeInternal
check(size[1] == 50 and size[2] == 50 and size[3] == 8, 'a new portal gets the default size (50, 50, 8)')
p = portal(50, Vector(33, 17, 8))
p:Initialize()
check(p.dt.SizeInternal[1] == 33 and p.dt.SizeInternal[2] == 17 and lastHull(p) == 100, 'a sized portal keeps its size and sides')

---------------------------------------------------------------------------------------------------- a client
CLIENT, SERVER = true, false
ENT = {}
SeamlessPortals = nil
local meshes = 0
local Msh = {}
Msh.__index = Msh
function Mesh() meshes = meshes + 1 return setmetatable({}, Msh) end
function Msh:BuildFromTriangles(t) self.vertices = #t end
function Msh:Draw() end
function CreateClientConVar() return { GetFloat = function() return 250 end } end
function Material(name) return { name = name } end
function GetRenderTarget(name) return { name = name } end
function ScrW() return 1920 end
function ScrH() return 1080 end
game = { SinglePlayer = function() return false end }
hook = { Add = function() end, Remove = function() end }
halo = { RenderedEntity = function() return nil end }
cam = { PushModelMatrix = function() end, PopModelMatrix = function() end }
render = { SetMaterial = function() end, CullMode = function() end }
load('sh_init.lua')
load('cl_init.lua')

-- The render mesh: one per side count within the limits, at most nine vertices a side.
for _, case in ipairs(CRAFTED) do
	local vectors = bounded('GetRenderMesh(' .. tostring(case[1]) .. ')', SeamlessPortals.GetRenderMesh, case[1])
	local m = SeamlessPortals.GetRenderMesh(case[1])
	check(m.vertices == case[2] * 9 and m.vertices <= 900,
		'GetRenderMesh(' .. tostring(case[1]) .. ') builds ' .. case[2] * 9 .. ' vertices, not ' .. tostring(m.vertices))
	check(vectors <= 2000, 'GetRenderMesh(' .. tostring(case[1]) .. ') made ' .. vectors .. ' vectors')
end
local keys = 0
for k in pairs(SeamlessPortals.PortalMeshes) do
	keys = keys + 1
	check(k == math.floor(k) and k >= 3 and k <= 100, 'meshes are kept by side counts within the limits, not ' .. tostring(k))
end
check(keys <= 98 and meshes == keys, 'one mesh per side count')

-- A client's Think rebuilds the hull from the raw network var, and its frame is drawn from the same limits.
p = portal(2147483647, Vector(1e30, NAN, 8))
p.GetWorldTransformMatrix = function() return { SetScale = function() end } end
bounded('a client Think of a crafted portal', p.Think, p)
check(lastHull(p) == 200, 'a client builds a hull of 200 points, not ' .. tostring(lastHull(p)))
bounded('drawing a crafted portal', p.DrawModelMesh, p, p:GetSize())

print('PASS: portal side counts and sizes stay within their limits')
