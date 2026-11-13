-- A narrow SteamVR billboard, never path-traced scene geometry.
local Laser = {}
function Laser.New(ctx)
    local object
    local function create()
        local size = ctx.Overlay.Sizes.laser
        object = ctx.Overlay.New{key = "laser", name = "VR pointer", width = size[1], height = size[2],
            paint = function(_, w, h)
                surface.SetDrawColor(80, 200, 255, 210) surface.DrawRect(w / 2 - 1, 8, 2, h - 8)
                surface.SetDrawColor(225, 250, 255, 255) surface.DrawRect(w / 2 - 4, 0, 8, 8)
            end}
        object:SortOrder(100)
    end
    local self = {}
    function self.Update(hit, origin, direction, opened)
        if not opened or not origin or not ctx.Pose.head then if object then object:Show(false) end return end
        if not object then create() end
        local length = math.max(0.01, hit and hit.distance or ctx.Space.scale * 1.3)
        local midpoint = origin + direction * (length / 2)
        local normal = midpoint - ctx.Pose.head.pos
        normal = normal - direction * normal:Dot(direction)
        if normal:Length() < 0.001 then normal = ctx.Pose.head.ang:Right() end
        local ang = normal:GetNormalized():AngleEx(direction)
        local pos, rotation = ctx.ToTracking(midpoint, ang)
        object:Place("world", pos, rotation, length / ctx.Space.scale * object.width / object.height)
        object:Show(true)
    end
    function self.Stop() if object then object:Destroy() object = nil end end
    return self
end
return Laser
