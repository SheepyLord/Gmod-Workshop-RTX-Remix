-- Coalesce submillimetre tracking motion against the last submitted transform.
local Presentation = {}
local function difference(a, b) return (a - b + 180) % 360 - 180 end
function Presentation.New(overlay)
    local self, visible, placed = {}, nil, false
    local position, angle, width = Vector(), Angle(), nil
    function self.Show(value)
        value = value == true
        if value ~= visible then visible = value overlay:Show(value) end
    end
    function self.Place(p, a, metres)
        local x, y, z = p.x - position.x, p.y - position.y, p.z - position.z
        local pitch, yaw, roll = difference(a.p, angle.p), difference(a.y, angle.y), difference(a.r, angle.r)
        if not placed or x * x + y * y + z * z > 0.001 * 0.001 or
            pitch * pitch + yaw * yaw + roll * roll > 0.1 * 0.1 or metres ~= width then
            position.x, position.y, position.z = p.x, p.y, p.z
            angle.p, angle.y, angle.r, width, placed = a.p, a.y, a.r, metres, true
            overlay:Place("world", p, a, metres)
        end
    end
    return self
end
return Presentation
