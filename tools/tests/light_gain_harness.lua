-- The distance gain shared by the RTX flashlight's automatic brightness (ADR 0208) and the dance light's
-- uniform lighting (ADR 0209), one copy in each package part. Pure maths, no game:
--   luajit light_gain_harness.lua <fixes cl_remix_light_gain.lua> <motion importer cl_light_gain.lua>
local fixesPath, motionPath = arg[1], arg[2]
assert(fixesPath and motionPath, "usage: light_gain_harness.lua <fixes copy> <motion importer copy>")

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
assert(read(fixesPath) == read(motionPath), "the two copies must be the same bytes: copy one over the other")

local function near(a, b, tolerance, what)
    assert(type(a) == "number" and math.abs(a - b) <= (tolerance or 1e-9) * math.max(1, math.abs(b)),
        (what or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

for _, path in ipairs({ fixesPath, motionPath }) do
    local G = dofile(path)
    assert(type(G) == "table" and G.VERSION == 1, "include() returns the table")

    -- Target: the inverse square at full strength, its root at half, nothing at 0; the normal distance is 1.
    near(G.Target(150, 150, 1, 2, 30, 1 / 64, 16), 1, nil, "the normal distance")
    near(G.Target(300, 150, 1, 2, 30, 1 / 64, 16), 4, nil, "twice as far, four times the light")
    near(G.Target(75, 150, 1, 2, 30, 1 / 64, 16), 0.25, nil, "half as far, a quarter")
    near(G.Target(300, 150, 0.5, 2, 30, 1 / 64, 16), 2, nil, "half strength: the square root")
    near(G.Target(3000, 150, 0, 2, 30, 1 / 64, 16), 1, nil, "strength 0 changes nothing")
    near(G.Target(300, 150, 1, 1, 30, 1 / 64, 16), 2, nil, "a light that fades as 1/d")
    -- The clamps, and the light's own size: nothing closer than `near` gets brighter.
    near(G.Target(1e6, 150, 1, 2, 30, 1 / 64, 16), 16, nil, "at most maxGain")
    near(G.Target(1, 150, 1, 2, 1, 1 / 64, 16), 1 / 64, nil, "at least minGain")
    near(G.Target(5, 150, 1, 2, 30, 1 / 1000, 16), (30 / 150) ^ 2, nil, "closer than the light's size counts as its size")
    near(G.Target(50, 60, 1, 1, 100, 0, 16), 1, nil, "a projected texture below 100 units does not fade")
    -- What is not a number never breaks the light.
    near(G.Target(0 / 0, 150, 1, 2, 30, 1 / 64, 16), 1, nil, "NaN distance")
    near(G.Target(100, 0, 1, 2, 30, 1 / 64, 16), 1, nil, "no reference")
    near(G.Target(100, 150, 0 / 0, 2, 30, 1 / 64, 16), 1, nil, "NaN strength counts as 0")
    near(G.Target(300, 150, 7, 2, 30, 1 / 64, 64), 4, nil, "strength is at most 1")
    near(G.Target(0 / 0, 150, 1, 2, 30, 2, 16), 2, nil, "a NaN distance still keeps within the clamps")

    -- EffectiveDistance: equal samples give their distance; a near one counts most; skipped and clamped samples.
    near(G.EffectiveDistance({ 200, 200, 200 }, 3, nil, 2, 1, 4096), 200, nil, "equal samples")
    local mixed = G.EffectiveDistance({ 50, 1000, 1000, 1000, 1000 }, 5, nil, 2, 1, 4096)
    near(mixed, math.sqrt(5 / (1 / 2500 + 4 / 1e6)), nil, "the inverse-square mean")
    assert(mixed < 120, "one near hit in five pulls the distance close")
    near(G.EffectiveDistance({ 100, 400 }, 2, { 3, 1 }, 2, 1, 4096), math.sqrt(4 / (3 / 1e4 + 1 / 16e4)), nil, "weights")
    near(G.EffectiveDistance({ 100, 400 }, 2, nil, 1, 1, 4096), 2 / (1 / 100 + 1 / 400), nil, "a 1/d light: the harmonic mean")
    near(G.EffectiveDistance({ false, 300, 0 / 0 }, 3, nil, 2, 1, 4096), 300, nil, "samples that are not numbers are skipped")
    near(G.EffectiveDistance({ 1, 9000 }, 2, nil, 2, 20, 1000), math.sqrt(2 / (1 / 400 + 1 / 1e6)), nil, "kept within near and far")
    assert(G.EffectiveDistance({ false, false }, 2, nil, 2, 1, 4096) == nil, "nothing measured: nil")

    -- Smooth: the first gain at once; down within `fall`, up within `rise`, in log space, never past the target.
    near(G.Smooth(nil, 0.3, 1 / 60, 0.08, 0.6), 0.3, nil, "no gain yet: the target")
    near(G.Smooth(2, 0.5, 0, 0.08, 0.6), 2, nil, "no time: unchanged")
    near(G.Smooth(2, 0.5, 1 / 60, 0, 0.6), 0.5, nil, "no fall time: at once")
    near(G.Smooth(4, 1, 0.08, 0.08, 0.6), math.exp(math.log(4) * math.exp(-1)), nil, "one fall time: 1/e of the way left")
    near(G.Smooth(1, 4, 0.6, 0.08, 0.6), math.exp(math.log(4) * (1 - math.exp(-1))), nil, "one rise time")
    local down, up = 8, 0.125
    for _ = 1, 12 do -- 0.2 s at 60 frames a second
        local nextDown = G.Smooth(down, 0.125, 1 / 60, 0.08, 0.6)
        local nextUp = G.Smooth(up, 8, 1 / 60, 0.08, 0.6)
        assert(nextDown <= down and nextDown >= 0.125 and nextUp >= up and nextUp <= 8, "monotone, never past the target")
        down, up = nextDown, nextUp
    end
    assert(math.log(8 / down) / math.log(64) > 0.9, "dimming is over 90 % done in 0.2 s")
    assert(math.log(up / 0.125) / math.log(64) < 0.3, "brightening under 30 % in 0.2 s")
    near(G.Smooth(2, 0 / 0, 1 / 60, 0.08, 0.6), 2, nil, "a NaN target leaves the gain")

    -- Jumped: a cut or a teleport, not motion.
    assert(not G.Jumped(5, 0.999, 150), "a few units and a degree is motion")
    assert(G.Jumped(200, 0.999, 150), "200 units in a frame at 150 is a cut")
    assert(not G.Jumped(200, 0.999, 1000), "but not for a subject 1000 units away")
    assert(G.Jumped(5, 0.9, 150), "a turn of 26 degrees in a frame is a cut")
    assert(G.Jumped(0 / 0, 1, 150), "an unknown move counts as a jump")

    -- Ring: unit directions, the axis first, then `count` at `angle` evenly around it.
    local ring = G.Ring(20, 6)
    assert(#ring == 7 and ring[1][1] == 1 and ring[1][2] == 0 and ring[1][3] == 0, "the axis first")
    for i = 2, 7 do
        local c = ring[i]
        near(c[1] * c[1] + c[2] * c[2] + c[3] * c[3], 1, 1e-12, "unit length")
        near(math.deg(math.acos(c[1])), 20, 1e-9, "20 degrees off the axis")
        local nextOne = ring[i == 7 and 2 or i + 1]
        near(math.deg(math.acos((c[2] * nextOne[2] + c[3] * nextOne[3]) / (math.sin(math.rad(20)) ^ 2))), 60, 1e-6,
            "evenly around")
    end

    -- Kelvin: 6600 K is white; warm is red-heavy and cool blue-heavy, both at the luminance of white.
    local r, g, b = G.Kelvin(6600)
    near(r, 1) near(g, 1) near(b, 1)
    for _, k in ipairs({ 1000, 1900, 2700, 3200, 4500, 5600, 8000, 12000, 40000 }) do
        r, g, b = G.Kelvin(k)
        near(0.2126 * r + 0.7152 * g + 0.0722 * b, 1, 1e-9, k .. " K keeps the luminance of white")
        if k < 6600 then assert(r > g and g > b, k .. " K is warm") else assert(b > r, k .. " K is cool") end
    end
    near(select(1, G.Kelvin(500)), select(1, G.Kelvin(1000)), nil, "below 1000 K counts as 1000 K")
    r, g, b = G.Kelvin(0 / 0)
    near(r, 1, nil, "NaN is white")
end
io.write("PASS light gain: both copies the same bytes; inverse-square target with strength, clamps and the light's size, " ..
    "effective distance, eased gain falling fast and rising gently, jumps, ring, colour temperature\n")
