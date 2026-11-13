-- Shared classification and placement maths. Including this file installs nothing.
local W = {}
local kinds = {nlvr_hands = "hands", weapon_crowbar = "melee", weapon_stunstick = "melee",
    weapon_frag = "grenade", weapon_bugbait = "grenade", weapon_physgun = "physgun", gmod_tool = "toolgun",
    weapon_pistol = "clip", weapon_357 = "clip", weapon_smg1 = "clip", weapon_ar2 = "clip",
    weapon_shotgun = "shotgun", weapon_crossbow = "crossbow", weapon_rpg = "rpg"}
function W.Kind(class) return kinds[class] or "swep" end
function W.GunAngle(ang, pitch)
    local _, rotation = LocalToWorld(Vector(), Angle(pitch or 0, 0, 0), Vector(), ang)
    return rotation
end
local data = {
    weapon_crowbar = {melee = true, reach = 0.08}, weapon_stunstick = {melee = true, reach = 0.06},
    weapon_pistol = {length = 0.20, axis = -1}, weapon_357 = {length = 0.30},
    weapon_smg1 = {length = 0.46, fore = 0.23}, weapon_ar2 = {length = 0.68, fore = 0.31, axis = -1},
    weapon_shotgun = {length = 0.78, fore = 0.36, axis = -1}, weapon_crossbow = {length = 0.67, fore = 0.32},
    weapon_annabelle = {length=.78,axis=-1},
    weapon_rpg = {length = 0.86, fore = 0.34, axis = -1}, weapon_physgun = {length = 0.66, fore = 0.27},
    weapon_physcannon = {length = 0.66}, gmod_tool = {length = 0.22}, gmod_camera = {length = 0.13},
    weapon_frag = {length = 0.08}, weapon_bugbait = {length = 0.10}, weapon_medkit = {length = 0.20}
}
function W.Data(class) return data[class] or {} end
local modelClass = { ["models/weapons/w_annabelle.mdl"]="weapon_annabelle", ["models/weapons/w_smg1.mdl"]="weapon_smg1", ["models/weapons/w_irifle.mdl"]="weapon_ar2",
    ["models/weapons/w_shotgun.mdl"]="weapon_shotgun", ["models/weapons/w_crossbow.mdl"]="weapon_crossbow",
    ["models/weapons/w_rocket_launcher.mdl"]="weapon_rpg", ["models/weapons/w_pistol.mdl"]="weapon_pistol",
    ["models/weapons/w_357.mdl"]="weapon_357", ["models/weapons/w_physics.mdl"]="weapon_physgun" }
-- Geometry belongs to the model, even when a Lua SWEP gives that model an unknown class.
local modelData={}
for path,class in pairs(modelClass) do
    local values={} for key,value in pairs(data[class]) do values[key]=value end
    modelData[path]=values
end
modelData["models/weapons/w_physics.mdl"].attachment=1
function W.ModelData(path) return modelData[(path or ""):lower()] or {} end
function W.Opposite(hand) return hand == "left" and "right" or "left" end
function W.Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function W.Vector(v) return v and W.Finite(v.x) and W.Finite(v.y) and W.Finite(v.z) end
function W.Angle(a) return a and W.Finite(a.p) and W.Finite(a.y) and W.Finite(a.r) end
function W.Unit(v, fallback) return v:Length() > 0.00001 and v / v:Length() or (fallback or Vector(1,0,0)) end
function W.Along(a, b, up)
    local dir = W.Unit(b-a)
    if math.abs(dir:Dot(up)) > 0.98 then up = math.abs(dir.z) > 0.98 and Vector(0,1,0) or Vector(0,0,1) end
    return dir:AngleEx(up)
end
-- Invert the model-local wrist, then put it at the desired world wrist. Bone index zero is valid.
function W.Place(gripPos, gripAng, pos, ang, scale)
    local inversePos, inverseAng = WorldToLocal(Vector(), Angle(), gripPos * (scale or 1), gripAng)
    return LocalToWorld(inversePos, inverseAng, pos, ang)
end
function W.Target(eye, origin, direction, distance, trace, filter)
    local point = origin + direction * (distance or 32768)
    if not distance then point = trace({start=origin,endpos=point,filter=filter,mask=MASK_SHOT}).HitPos end
    return (point-eye):Angle(), point
end
function W.SafeMuzzle(eye, pos, trace, filter, scale)
    local tr = trace({start=eye,endpos=pos,filter=filter,mask=MASK_SHOT})
    if tr.StartSolid or tr.AllSolid then return eye, true end
    if tr.Hit then return tr.HitPos + tr.HitNormal * (scale or 40) * 0.01, true end
    return pos, false
end
function W.Hands()
    -- Registration is lazy and persistent; instances are owned only by active VR players.
    weapons.Register({Base="weapon_base",PrintName="Hands",Spawnable=false,AdminOnly=false,
        ViewModel="",WorldModel="",DrawAmmo=false,DrawCrosshair=false,Slot=0,SlotPos=0,
        Weight=-1,AutoSwitchTo=false,AutoSwitchFrom=false,
        Primary={ClipSize=-1,DefaultClip=-1,Automatic=false,Ammo="none"},
        Secondary={ClipSize=-1,DefaultClip=-1,Automatic=false,Ammo="none"},
        Initialize=function(self) self:SetHoldType("normal") end,
        PrimaryAttack=function() end,SecondaryAttack=function() end,Reload=function() end,
        ShouldDropOnDie=function() return false end}, "nlvr_hands")
end

local modelGrips={
    ["models/weapons/w_pistol.mdl"]={2.61573058,0.06710428,-3.4442541},
    ["models/weapons/w_smg1.mdl"]={-6.94533372,0.978759587,-3.65959084},
    ["models/weapons/w_irifle.mdl"]={13.4547119,-0.216110975,-1.5642751},
    ["models/weapons/w_shotgun.mdl"]={14.7818937,-0.363812685,-2.78991246},
    ["models/weapons/w_crossbow.mdl"]={4.74892902,2.09351325,-0.476969779},
    ["models/weapons/w_annabelle.mdl"]={14.2706366,-1.27106971,-1.19465991},
    ["models/weapons/w_357.mdl"]={1.973084033,0.2304840684,-2.279544532},
    ["models/weapons/w_rocket_launcher.mdl"]={12.87458134,-1.878229022,1.390643418},
    ["models/weapons/w_grenade.mdl"]={-0.3914797306,-0.1399532557,3.768142052},
    ["models/weapons/w_bugbait.mdl"]={-0.01281952858,-0.0004997253418,0.2532570958},
    ["models/weapons/w_physics.mdl"]={2.814955413,1.43477869,0.9026197791},
    ["models/weapons/w_toolgun.mdl"]={1.934329074,0.297645092,-1.942374572},
    ["models/weapons/w_medkit.mdl"]={-0.1153583527,-3.256294727,0.1245521307},
    ["models/maxofs2d/camera.mdl"]={-2.045545101,-3.539099574,2.469807744},
}
function W.GripData(path) return modelGrips[(path or ""):lower()] end
return W
