-- SteamVR canvases only. No perspective geometry enters Remix's path tracer.
local O = {}
local function ring(w, h, inside, outside, colour)
    surface.SetDrawColor(unpack(colour))
    local cx, cy = w / 2, h / 2
    for i = 0, 63 do
        local a, b = i * math.pi / 32, (i + 1) * math.pi / 32
        surface.DrawPoly({{x = cx + math.cos(a) * cx * inside, y = cy + math.sin(a) * cy * inside},
            {x = cx + math.cos(a) * cx * outside, y = cy + math.sin(a) * cy * outside},
            {x = cx + math.cos(b) * cx * outside, y = cy + math.sin(b) * cy * outside},
            {x = cx + math.cos(b) * cx * inside, y = cy + math.sin(b) * cy * inside}})
    end
end
function O.New(ctx)
    local self, dots, target, comfort = {}, {}, nil, nil
    local strength, fade, good = 0, 0, false
    local function canvas(key, w, h, paint)
        return ctx.Overlay.New({key = key, width = w, height = h, paint = paint})
    end
    local function colour() return good and {60, 255, 140, 240} or {255, 70, 60, 240} end
    function self.Arc(arc, landing)
        if not arc then
            for _, dot in ipairs(dots) do dot:Show(false) end
            if target then target:Show(false) end
            return
        end
        good = landing ~= nil
        for i = 1, 3 do
            if not dots[i] then
                local key=i==1 and "teleport_arc" or "teleport_arc_"..i
                local w,h=unpack(ctx.Overlay.Sizes[key])
                dots[i] = canvas(key, w, h, function(_, width, height)
                    draw.NoTexture() ring(width, height, 0, 0.95, colour())
                end)
            end
            local point = arc.points[math.max(1, math.ceil(#arc.points * i / 3))]
            local pos, ang = ctx.ToTracking(point, ctx.Pose.head.ang)
            -- The reserved arc canvas is wide; its physical width keeps its vertical dot visible.
            dots[i]:Place("world", pos, ang, i == 1 and 0.11 or 0.035)
            dots[i]:Invalidate() dots[i]:Show(true)
        end
        if not target then
            local w, h = unpack(ctx.Overlay.Sizes.teleport_target)
            target = canvas("teleport_target", w, h, function(_, width, height)
                draw.NoTexture() ring(width, height, 0.7, 0.95, colour())
            end)
        end
        local at = landing or arc.target or arc.points[#arc.points]
        local pos, ang = ctx.ToTracking(at + Vector(0, 0, 0.6), Angle(90, 0, 0))
        target:Place("world", pos, ang, 0.42) target:Invalidate() target:Show(true)
    end
    function self.Comfort(amount, full)
        amount, full = math.Clamp(amount, 0, 1), math.Clamp(full, 0, 1)
        if amount < 0.001 and full < 0.001 and not comfort then return end
        if not comfort then
            local w, h = unpack(ctx.Overlay.Sizes.vignette)
            comfort = canvas("vignette", w, h, function(_, width, height)
                draw.NoTexture()
                -- Outside the ellipse is black too, including every corner of the headset frustum.
                local inner = 0.88 - strength * 0.45
                for i = 0, 15 do
                    local a, b = inner + (1.5 - inner) * i / 16, inner + (1.5 - inner) * (i + 1) / 16
                    ring(width, height, a, b, {0, 0, 0, math.floor(strength * 255 * math.min(1, (i + 1) / 5))})
                end
                if fade > 0 then surface.SetDrawColor(0, 0, 0, math.ceil(fade * 255)) surface.DrawRect(0, 0, width, height) end
            end)
            comfort:Place("head", Vector(0.1, 0, 0), Angle(), 1)
            comfort:SortOrder(100)
        end
        if math.abs(amount - strength) > 0.005 or full ~= fade then
            strength, fade = amount, full comfort:Invalidate()
        end
        comfort:Show(amount > 0.001 or full > 0.001)
    end
    return self
end
return O
