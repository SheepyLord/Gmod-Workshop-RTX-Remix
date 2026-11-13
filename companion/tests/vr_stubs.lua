-- Engine stand-ins, deliberately independent of the production transforms and sync codec.
local S = {}
local ffi = require("ffi")
function S.Math()
    local V, A = {}, {}
    V.__index, A.__index = V, A
    function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, V) end
    function Angle(p, y, r) return setmetatable({p = p or 0, y = y or 0, r = r or 0}, A) end
    V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
    V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
    V.__div = function(a, b) return a * (1 / b) end
    V.__unm = function(a) return a * -1 end
    function V:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
    function V:Length() return math.sqrt(self:Dot(self)) end
    function V:LengthSqr() return self:Dot(self) end
    function V:Cross(b) return Vector(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
    function V:DistToSqr(b) return (self - b):Dot(self - b) end
    function V:GetNormalized() return self / self:Length() end
    function A:Forward()
        local p, y = math.rad(self.p), math.rad(self.y)
        return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
    end
    function A:Right()
        local p, y, r = math.rad(self.p), math.rad(self.y), math.rad(self.r)
        return Vector(-math.sin(r) * math.sin(p) * math.cos(y) + math.cos(r) * math.sin(y),
            -math.sin(r) * math.sin(p) * math.sin(y) - math.cos(r) * math.cos(y), -math.sin(r) * math.cos(p))
    end
    function A:Up()
        local p, y, r = math.rad(self.p), math.rad(self.y), math.rad(self.r)
        return Vector(math.cos(r) * math.sin(p) * math.cos(y) + math.sin(r) * math.sin(y),
            math.cos(r) * math.sin(p) * math.sin(y) - math.sin(r) * math.cos(y), math.cos(r) * math.cos(p))
    end
    local function transform(v, a) return a:Forward() * v.x - a:Right() * v.y + a:Up() * v.z end
    local function inverse(v, a) return Vector(v:Dot(a:Forward()), -v:Dot(a:Right()), v:Dot(a:Up())) end
    local function angles(forward, left)
        return Angle(math.deg(math.atan2(-forward.z, math.sqrt(forward.x ^ 2 + forward.y ^ 2))),
            math.deg(math.atan2(forward.y, forward.x)),
            math.deg(math.atan2(left.z, forward.x * left.y - forward.y * left.x)))
    end
    function LocalToWorld(p, a, base, rotation)
        return base + transform(p, rotation), angles(transform(a:Forward(), rotation), transform(-a:Right(), rotation))
    end
    function WorldToLocal(p, a, base, rotation)
        return inverse(p - base, rotation), angles(inverse(a:Forward(), rotation), inverse(-a:Right(), rotation))
    end
end
function S.Wire()
    pcall(ffi.cdef, "typedef union { float f; unsigned char bytes[4]; } nlvr_test_float;")
    local io, bits, cursor = {}, {}, 1
    function io.WriteUInt(n, count) for i = 0, count - 1 do bits[#bits + 1] = math.floor(n / 2 ^ i) % 2 end end
    function io.ReadUInt(count)
        assert(cursor + count - 1 <= #bits, "Truncated wire data")
        local n = 0 for i = 0, count - 1 do n = n + bits[cursor] * 2 ^ i cursor = cursor + 1 end return n
    end
    function io.WriteFloat(n)
        local value = ffi.new("nlvr_test_float") value.f = n
        for i = 0, 3 do io.WriteUInt(value.bytes[i], 8) end
    end
    function io.ReadFloat()
        local value = ffi.new("nlvr_test_float")
        for i = 0, 3 do value.bytes[i] = io.ReadUInt(8) end
        return tonumber(value.f)
    end
    function io.WriteBool(b) io.WriteUInt(b and 1 or 0, 1) end
    function io.ReadBool() return io.ReadUInt(1) == 1 end
    function io.WriteVector(v) io.WriteFloat(v.x) io.WriteFloat(v.y) io.WriteFloat(v.z) end
    function io.ReadVector() return Vector(io.ReadFloat(), io.ReadFloat(), io.ReadFloat()) end
    function io.WriteAngle(a) io.WriteFloat(a.p) io.WriteFloat(a.y) io.WriteFloat(a.r) end
    function io.ReadAngle() return Angle(io.ReadFloat(), io.ReadFloat(), io.ReadFloat()) end
    function io.WriteString(s) for i = 1, #s do io.WriteUInt(s:byte(i), 8) end io.WriteUInt(0, 8) end
    function io.ReadString()
        local chars = {} local b = io.ReadUInt(8)
        while b ~= 0 do chars[#chars + 1] = string.char(b) b = io.ReadUInt(8) end
        return table.concat(chars)
    end
    function io.Length() return #bits end
    function io.Rewind() cursor = 1 end
    function io.Clear() bits, cursor = {}, 1 end
    function io.Truncate(n) for i = #bits, n + 1, -1 do bits[i] = nil end end
    return io
end
function S.Command()
    local cmd = {angles = Angle(), forward = 0, side = 0, up = 0, buttons = 0, wheel = 0}
    function cmd:GetViewAngles() return self.angles end
    function cmd:SetViewAngles(a) self.angles = a end
    function cmd:SetForwardMove(n) self.forward = n end
    function cmd:SetSideMove(n) self.side = n end
    function cmd:GetForwardMove() return self.forward end
    function cmd:GetSideMove() return self.side end
    function cmd:GetButtons() return self.buttons end
    function cmd:SetButtons(n) self.buttons = n end
    function cmd:KeyDown(n) return bit.band(self.buttons, n) ~= 0 end
    function cmd:AddKey(n) self.buttons = bit.bor(self.buttons, n) end
    function cmd:RemoveKey(n) self.buttons = bit.band(self.buttons, bit.bnot(n)) end
    function cmd:ClearButtons() self.buttons = 0 end
    function cmd:GetUpMove() return self.up end
    function cmd:SetUpMove(n) self.up = n end
    function cmd:GetMouseWheel() return self.wheel end
    function cmd:SetMouseWheel(n) self.wheel = n end
    function cmd:SelectWeapon(weapon) self.selected = weapon end -- queued command, not an immediate inventory change
    return cmd
end
function S.Move()
    local mv = {origin = Vector(), velocity = Vector(),forward=0,side=0,up=0,buttons=0,angles=Angle()}
    function mv:SetOrigin(v) self.origin = v end
    function mv:GetOrigin() return self.origin end
    function mv:SetVelocity(v) self.velocity = v end
    function mv:GetVelocity() return self.velocity end
    function mv:SetMoveAngles(a) self.angles=a end
    function mv:GetMoveAngles() return self.angles end
    function mv:SetForwardSpeed(v) self.forward=v end
    function mv:GetForwardSpeed() return self.forward end
    function mv:SetSideSpeed(v) self.side=v end
    function mv:GetSideSpeed() return self.side end
    function mv:SetUpSpeed(v) self.up=v end
    function mv:GetUpSpeed() return self.up end
    function mv:SetButtons(v) self.buttons=v end
    function mv:GetButtons() return self.buttons end
    return mv
end
function S.Traces()
    util.TraceLine = function() return {Hit = false, Fraction = 1, HitPos = Vector(), HitNormal = Vector(0, 0, 1)} end
    util.TraceHull = util.TraceLine
end
-- Explicit fixtures, not a simulation of weapon firing, SWEP inheritance or prediction.
S.NULL = {valid = false}
function S.Model(spec)
    spec = spec or {}
    local ent = {valid = true, pos = spec.pos or Vector(), ang = spec.ang or Angle(), model = spec.model or "",
        bones = spec.bones or {}, attachments = spec.attachments or {}}
    function ent:GetPos() return self.pos end
    function ent:SetPos(v) self.pos = v end
    function ent:GetAngles() return self.ang end
    function ent:SetAngles(a) self.ang = a end
    function ent:GetModel() return self.model end
    function ent:SetNoDraw(v) self.noDraw = v end
    function ent:GetNoDraw() return self.noDraw or false end
    function ent:SetupBones() self.bonesReady = true end
    function ent:LookupBone(name)
        for i, bone in ipairs(self.bones) do if bone.name == name then return i - 1 end end
    end
    function ent:GetBoneCount() return #self.bones end
    function ent:GetBoneName(id) return self.bones[id + 1] and self.bones[id + 1].name or "__INVALIDBONE__" end
    function ent:GetBonePosition(id)
        local bone = self.bones[id + 1]
        if not bone then return end
        if not self.bonesReady then return self.pos, self.ang end
        return LocalToWorld(bone.pos or Vector(), bone.ang or Angle(), self.pos, self.ang)
    end
    function ent:GetBoneMatrix(id)
        if not self.bonesReady or not self.bones[id + 1] then return end
        local pos, ang = self:GetBonePosition(id)
        -- Rigid fixture matrix: the fields consumed by placement code, with world-space values.
        return {GetTranslation = function() return pos end, GetAngles = function() return ang end}
    end
    function ent:LookupAttachment(name)
        if self.model == "" then return -1 end
        for i, attachment in ipairs(self.attachments) do if attachment.name == name then return i end end
        return 0
    end
    function ent:GetAttachment(id)
        local attachment = self.attachments[id]
        if not attachment then return end
        local pos, ang = LocalToWorld(attachment.pos or Vector(), attachment.ang or Angle(), self.pos, self.ang)
        return {Pos = pos, Ang = ang, Bone = attachment.bone or 0}
    end
    function ent:DrawModel() self.draws = (self.draws or 0) + 1 end
    function ent:Remove() self.valid = false end
    return ent
end
function S.ClientsideModels(fixtures)
    local created = {}
    function ClientsideModel(path, group)
        local spec = {} for key, value in pairs((fixtures or {})[path] or {}) do spec[key] = value end
        spec.model = path
        local ent = S.Model(spec) ent.renderGroup = group created[#created + 1] = ent return ent
    end
    return created
end
function S.Weapon(spec)
    spec = spec or {}
    local ent = S.Model(spec)
    ent.class, ent.clip1, ent.clip2 = spec.class or "weapon_test", spec.clip1 or 0, spec.clip2 or -1
    ent.maxClip1, ent.primary, ent.secondary = spec.maxClip1 or -1, spec.primary or -1, spec.secondary or -1
    ent.nextPrimary, ent.holdType, ent.scripted = spec.nextPrimary or 0, spec.holdType or "normal", spec.scripted == true
    function ent:GetClass() return self.class end
    function ent:IsWeapon() return true end
    function ent:Clip1() return self.clip1 end
    function ent:SetClip1(n) self.clip1 = n end -- SetClip1 does not enforce GetMaxClip1
    function ent:Clip2() return self.clip2 end
    function ent:SetClip2(n) self.clip2 = n end
    function ent:GetMaxClip1() return self.maxClip1 end
    function ent:GetPrimaryAmmoType() return self.primary end
    function ent:GetSecondaryAmmoType() return self.secondary end
    function ent:SetNextPrimaryFire(n) self.nextPrimary = n end
    function ent:GetNextPrimaryFire() return self.nextPrimary end
    function ent:GetWeaponWorldModel() return self.model end
    function ent:GetHoldType() return self.holdType end
    function ent:IsScripted() return self.scripted end
    function ent:GetOwner() return self.owner or S.NULL end
    return ent
end
function S.WeaponRegistry()
    local stored = {}
    weapons = {Register = function(definition, class) definition.ClassName = class stored[class] = definition end,
        GetStored = function(class) return stored[class] end}
    return stored
end
function S.Player(spec)
    spec = spec or {}
    local ply = {valid = true, inventory = {}, ammo = {}}
    local ammoTypes, classes = spec.ammoTypes or {}, spec.classes or {}
    local function ammoID(kind) return type(kind) == "string" and ammoTypes[kind:lower()] or kind end
    function ply:IsPlayer() return true end
    function ply:GetWeapons() local list = {} for i, ent in ipairs(self.inventory) do list[i] = ent end return list end
    function ply:GetWeapon(class)
        for _, ent in ipairs(self.inventory) do if ent:GetClass() == class then return ent end end return S.NULL
    end
    function ply:GetActiveWeapon() return self.active or S.NULL end
    function ply:GetAmmoCount(kind) return self.ammo[ammoID(kind)] or 0 end
    function ply:SetAmmo(n, kind)
        local id = ammoID(kind) if id and id >= 0 then self.ammo[id] = math.max(0, math.floor(n)) end
    end
    function ply:GiveAmmo(n, kind)
        local id = ammoID(kind) if not id or id < 0 then return 0 end
        local before = self:GetAmmoCount(id)
        self:SetAmmo(math.min(before + n, (spec.ammoMax or {})[id] or math.huge), id)
        return self:GetAmmoCount(id) - before
    end
    function ply:RemoveAmmo(n, kind) self:SetAmmo(self:GetAmmoCount(kind) - n, kind) end
    function ply:Give(class, noAmmo)
        if self:GetWeapon(class).valid then return S.NULL end
        local definition = classes[class] or weapons and weapons.GetStored(class)
        if not definition then return S.NULL end
        local primary, secondary = definition.Primary or {}, definition.Secondary or {}
        local ent = S.Weapon{class = class, model = definition.WorldModel, scripted = definition.scripted ~= false,
            maxClip1 = primary.ClipSize, clip1 = primary.ClipSize, clip2 = secondary.ClipSize,
            primary = ammoID(primary.Ammo), secondary = ammoID(secondary.Ammo), holdType = definition.HoldType}
        ent.owner = self self.inventory[#self.inventory + 1] = ent
        if not noAmmo then self:GiveAmmo(math.max(0, (primary.DefaultClip or 0) - math.max(0, ent:Clip1())), ent.primary) end
        return ent
    end
    function ply:SelectWeapon(class)
        local ent = self:GetWeapon(class) if ent.valid then self.active = ent end
    end
    function ply:StripWeapon(class)
        for i = #self.inventory, 1, -1 do
            local ent = self.inventory[i]
            if ent:GetClass() == class then
                if self.active == ent then self.active = nil end
                ent:Remove() table.remove(self.inventory, i)
            end
        end
    end
    for _, ent in ipairs(spec.weapons or {}) do ent.owner = ply ply.inventory[#ply.inventory + 1] = ent end
    ply.active = spec.active
    for kind, count in pairs(spec.ammo or {}) do ply:SetAmmo(count, kind) end
    return ply
end
function S.Bullet(data)
    local bullet = {Num = 1, Src = Vector(), Dir = Vector(), Spread = Vector(), Tracer = 1,
        Force = 1, Damage = 1, Distance = 56756, HullSize = 0, AmmoType = "", Inflictor = S.NULL, IgnoreEntity = S.NULL}
    for key, value in pairs(data or {}) do bullet[key] = value end
    return bullet -- EntityFireBullets receives this same mutable table; the caller drives hook.Run.
end
return S
