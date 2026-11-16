-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.Category     = NL("Seamless Portals")
ENT.PrintName    = NP("Seamless Portal")
ENT.Author       = "Mee"
ENT.Purpose      = NL("Seamlessly connects two locations")
ENT.Instructions = ""
ENT.Spawnable    = true
ENT.RenderGroup  = RENDERGROUP_OPAQUE

SeamlessPortals  = SeamlessPortals or {}

-- A portal's side count and size are network vars, and the duplicator restores a dupe's network vars as the
-- file has them, not through ENT:SetSides or ENT:SetSize: a pasted portal with two billion sides hung the
-- server and every client (review finding 5). So every reader takes them through these limits. A value that
-- is not a finite number falls back to the default (NaN fails every comparison, so math.Clamp keeps it).
local MIN_SIDES, MAX_SIDES, DEFAULT_SIDES = 3, 100, 4
-- The tools make portals up to 500 (the creator) and just under 1000 (the fitter) from the centre to an
-- edge, and up to 100 thick; a portal placed in Hammer may be larger, up to these.
local MAX_SIZE_XY, MAX_SIZE_Z = 2048, 256
local DEFAULT_SIZE = { 50, 50, 8 }

local function limited(value, low, high, fallback)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
	if value < low then return low end
	if value > high then return high end
	return value
end

function SeamlessPortals.LimitSides(sides)
	return math.floor(limited(sides, MIN_SIDES, MAX_SIDES, DEFAULT_SIDES))
end

function SeamlessPortals.LimitSize(size)
	local x, y, z
	if size then x, y, z = size[1], size[2], size[3] end
	return Vector(limited(x, 1, MAX_SIZE_XY, DEFAULT_SIZE[1]), limited(y, 1, MAX_SIZE_XY, DEFAULT_SIZE[2]),
		limited(z, 1, MAX_SIZE_Z, DEFAULT_SIZE[3]))
end

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "ExitPortal")
	self:NetworkVar("Vector", 0, "SizeInternal")
	self:NetworkVar("Bool", 0, "DisableBackface")
	self:NetworkVar("Int", 0, "SidesInternal")

	if self:GetSidesInternal() < 1 then
		self:SetSidesInternal(4)
	end
end

-- The number of sides, within the limits above.
function ENT:GetSides()
	return SeamlessPortals.LimitSides(self:GetSidesInternal())
end

function ENT:SetSides(sides)
	sides = SeamlessPortals.LimitSides(sides)
	local shouldUpdatePhysmesh = self:GetSides() ~= sides
	self:SetSidesInternal(sides)
	if shouldUpdatePhysmesh then self:UpdatePhysmesh() end
end

-- The size, within the limits above (a new Vector each call: callers scale it in place).
function ENT:GetSize()
	return SeamlessPortals.LimitSize(self:GetSizeInternal())
end

-- So the size is in source units (remember we are using sine/cosine)
local size_mult = Vector(math.sqrt(2), math.sqrt(2), 1)

-- Scale the phys mesh
function ENT:UpdatePhysmesh()
	local sizev = self:GetSize() * size_mult
	local finalMesh = {}
	local sides = self:GetSides()
	local angleMul = 360 / sides
	local degreeOffset = (sides * 90 + (sides % 4 != 0 and 0 or 45)) * (math.pi / 180)
	for side = 1, sides do
		local sidea = math.rad(side * angleMul) + degreeOffset
		local sidex = math.sin(sidea)
		local sidey = math.cos(sidea)
		local side1 = Vector(sidex, sidey, -1)
		local side2 = Vector(sidex, sidey,  0)
		table.insert(finalMesh, side1 * sizev)
		table.insert(finalMesh, side2 * sizev)
	end
	self:PhysicsInitConvex(finalMesh)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:EnableCustomCollisions(true)
	self:GetPhysicsObject():EnableMotion(false)
	self:GetPhysicsObject():SetMaterial("glass")
	self:GetPhysicsObject():SetMass(250)

	if CLIENT then
		self:SetRenderBounds(-sizev, sizev)
	end
end

SeamlessPortals.Portals = {}
SeamlessPortals.TransformPortal = function(a, b, pos, ang)
	if !IsValid(a) or !IsValid(b) then return Vector(), Angle() end
	local editedPos = Vector()
	local editedAng = Angle()

	if pos then
		editedPos = a:WorldToLocal(pos) * (b:GetSize()[1] / a:GetSize()[1])
		editedPos = b:LocalToWorld(Vector(editedPos[1], -editedPos[2], -editedPos[3]))
		editedPos = editedPos + b:GetUp() * 0.01 -- So you don't become trapped
	end

	if ang then
		local localAng = a:WorldToLocalAngles(ang)
		editedAng = b:LocalToWorldAngles(Angle(-localAng[1], -localAng[2], localAng[3] + 180))
	end

	-- Mirror portal
	if a == b then
		if pos then
			editedPos = a:LocalToWorld(a:WorldToLocal(pos) * Vector(1, 1, -1))
		end

		if ang then
			local localAng = a:WorldToLocalAngles(ang)
			editedAng = a:LocalToWorldAngles(Angle(-localAng[1], localAng[2], -localAng[3] + 180))
		end
	end

	return editedPos, editedAng
end

-- Only render the portals that are in the frustum, or should be rendered
SeamlessPortals.ShouldRender = function(portal, eyePos, eyeAngle, distance)
  if portal:IsDormant() then return false end
	local portalPos, portalUp, exitSize = portal:GetPos(), portal:GetUp(), portal:GetSize()
	local max, eye = math.max(exitSize[1], exitSize[2]), (eyePos - portalPos)
	-- (eyePos - portalPos):Dot(portalUp) > (-10 * max) -- true if behind the portal, false otherwise
	-- eyePos:DistToSqr(portalPos) < distance^2 * max -- true if close enough
	-- (eyePos - portalPos):Dot(eyeAngle:Forward()) < 50 * max -- true if looking at the portal, false otherwise
	if(eye:Dot(portalUp) <= -exitSize[3]) then return false end -- First condition is not met so bail put
	if(eye:LengthSqr() >= distance^2 * max) then return false end -- Second condition is not met so bail put
	return (eye:Dot(eyeAngle:Forward()) < max) -- Decides the return value of the function
end
