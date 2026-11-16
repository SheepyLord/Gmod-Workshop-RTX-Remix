-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
local function NLP(key, text)
    if bundle_i18n then bundle_i18n.RegisterPhrase(key, text)
    elseif CLIENT then language.Add(key, text) end
end
TOOL.Category		= "RTX Remix"
TOOL.Name			= "#tool.remix_rt_light_disk.name"
TOOL.Command		= nil
TOOL.ConfigName		= ""

-- Client ConVars
TOOL.ClientConVar["radius"]			= "20"
TOOL.ClientConVar["brightness"]		= "1"
TOOL.ClientConVar["volumetric"]		= "1"
TOOL.ClientConVar["color_r"]		= "255"
TOOL.ClientConVar["color_g"]		= "220"
TOOL.ClientConVar["color_b"]		= "180"
TOOL.ClientConVar["freeze"]			= "1"
TOOL.ClientConVar["xradius"]		= "20"
TOOL.ClientConVar["yradius"]		= "20"
TOOL.ClientConVar["yaw"]			= "0"
TOOL.ClientConVar["pitch"]			= "-90"

if CLIENT then
    NLP("tool.remix_rt_light_disk.name", NN("API Light - Disk"))
    NLP("tool.remix_rt_light_disk.desc", NN("Spawn and edit Disk/Ellipse Area Lights"))
    NLP("tool.remix_rt_light_disk.0", NN("Left-click: Spawn | Right-click: Update"))
end

local function computeRadianceVector(r, g, b, brightness)
    local scale = math.max(0, brightness or 1)
    return Vector((r/12)*scale, (g/12)*scale, (b/12)*scale)
end

-- The light's settings from this tool's convars (an update also sets the direction). A client can put
-- anything in its convars, so they go through RemixRTLight.Apply (remix_rt_light), which keeps each within
-- the light's limits.
local function lightValues(tool, withDirection)
    local values = {
        rtx_light_type = "disk",
        rtx_light_radius = tool:GetClientNumber("radius", 20),
        rtx_light_brightness = tool:GetClientNumber("brightness", 1),
        rtx_light_volumetric = tool:GetClientNumber("volumetric", 1),
        rtx_light_xradius = tool:GetClientNumber("xradius", 20),
        rtx_light_yradius = tool:GetClientNumber("yradius", 20),
        rtx_light_color_r = tool:GetClientNumber("color_r", 255),
        rtx_light_color_g = tool:GetClientNumber("color_g", 220),
        rtx_light_color_b = tool:GetClientNumber("color_b", 180),
    }
    if withDirection then
        values.rtx_light_dir_yaw = tool:GetClientNumber("yaw", 0)
        values.rtx_light_dir_pitch = tool:GetClientNumber("pitch", -90)
    end
    return values
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    if not trace.HitPos or not RemixRTLight then return false end

    local pos = trace.HitPos + (trace.HitNormal or Vector(0,0,1)) * 16
    local ang = Angle(0, ply:EyeAngles().y, 0)

    -- sbox_maxsents, creator, prop-protection owner, cleanup and undo, as the spawn menu gives a SENT.
    local ent = RemixRTLight.Spawn(ply, pos, ang, "Remix Disk Light")
    if not IsValid(ent) then return false end
    RemixRTLight.Apply(ent, lightValues(self, false))

    if self:GetClientNumber("freeze") ~= 0 then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    if not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    if ent:GetClass() ~= "remix_rt_light" or not RemixRTLight then return false end

    RemixRTLight.Apply(ent, lightValues(self, true))

    return true
end

function TOOL:Reload(trace)
    return false
end

function TOOL:Think()
end

function TOOL.BuildCPanel(panel)
    panel:Help(NL("Spawn and edit Disk/Ellipse Area Lights"))


    panel:NumSlider(NL("Brightness"), "remix_rt_light_disk_brightness", 0, 10000, 2)
    panel:NumSlider(NL("Volumetrics"), "remix_rt_light_disk_volumetric", 0, 5, 2)
    
    panel:NumSlider(NL("X Radius"), "remix_rt_light_disk_xradius", 1, 2000, 0)
    panel:NumSlider(NL("Y Radius"), "remix_rt_light_disk_yradius", 1, 2000, 0)
    
    panel:AddControl("Color", {
        Label = NL("Color"),
        Red = "remix_rt_light_disk_color_r",
        Green = "remix_rt_light_disk_color_g",
        Blue = "remix_rt_light_disk_color_b",
        ShowAlpha = 0,
        ShowHSV = 1,
        ShowRGB = 1,
        Multiplier = 1
    })
    
    panel:CheckBox(NL("Freeze on Spawn"), "remix_rt_light_disk_freeze")
end


if bundle_i18n then
    bundle_i18n.RegisterPhrase("Remix Disk Light", NN("Remix Disk Light"))
end
