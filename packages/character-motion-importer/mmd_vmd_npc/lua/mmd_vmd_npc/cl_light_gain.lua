-- Distance gain for a light that keeps what it lights at a steady brightness: the RTX flashlight's
-- automatic brightness (ADR 0208) and the dance light's uniform lighting (ADR 0209).
--
-- Written for this project's RTX package (MIT). The same file ships in two package parts so that
-- neither depends on the other: the RTX fixes (lua/remixlua/cl/remixapi/cl_remix_light_gain.lua)
-- and the character motion importer (lua/mmd_vmd_npc/cl_light_gain.lua). The repository's
-- tools/tests/light_gain_harness.lua checks that both copies are the same bytes.
--
-- Pure maths: no hooks, no state, no game calls; include() returns the table.
--
-- A light whose output falls off as distance^-falloff lights a surface at distance d as brightly as
-- one at the reference distance when its intensity is multiplied by (d / reference)^falloff. A Remix
-- sphere light falls off with the square (its irradiance is pi * radiance * (radius / d)^2), Source's
-- projected texture with its default attenuation (linear 100) as 100 / d beyond 100 units.

local Gain = { VERSION = 1 }

local exp, log, cos, sin, rad, pi = math.exp, math.log, math.cos, math.sin, math.rad, math.pi

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- The gain for a light whose subject is `distance` away, so that it gets the light it would get at
-- `reference` with gain 1.
--   strength: 0 (no change with distance) to 1 (the same brightness at every distance)
--   falloff:  the light's distance exponent (2 for a Remix sphere light)
--   near:     closer than this nothing gets brighter (the light's own size)
--   minGain, maxGain: the result is kept between them
function Gain.Target(distance, reference, strength, falloff, near, minGain, maxGain)
    local lo = finite(minGain) and minGain > 0 and minGain or 0
    local hi = finite(maxGain) and maxGain > 0 and maxGain or math.huge
    if lo > hi then lo = hi end
    if not finite(distance) or not finite(reference) or reference <= 0 then return clamp(1, lo, hi) end
    near = finite(near) and near > 0 and near or 1
    strength = clamp(finite(strength) and strength or 0, 0, 1)
    falloff = finite(falloff) and falloff > 0 and falloff or 2
    local gain = (math.max(distance, near) / math.max(reference, near)) ^ (falloff * strength)
    return clamp(gain, lo, hi)
end

-- The one distance at which a surface would get as much light as the samples get together: the
-- inverse-power mean, so a near sample counts most, as a near wall does on the screen. Samples that
-- are not numbers (a trace that started in a solid) are skipped; each is kept within [near, far].
-- Returns nil when no sample counts.
function Gain.EffectiveDistance(samples, count, weights, falloff, near, far)
    falloff = finite(falloff) and falloff > 0 and falloff or 2
    near = finite(near) and near > 0 and near or 1
    far = finite(far) and far > near and far or near
    local total, light = 0, 0
    for i = 1, count do
        local d = samples[i]
        local w = weights and weights[i] or 1
        if finite(d) and finite(w) and w > 0 then
            d = clamp(d, near, far)
            total = total + w
            light = light + w * d ^ -falloff
        end
    end
    if total <= 0 or light <= 0 then return nil end
    return (total / light) ^ (1 / falloff)
end

-- Moves the gain toward the target in log space: within `fall` seconds when it drops, so a surface
-- that comes close never flashes, and within `rise` seconds when it climbs, so a flickering
-- measurement does not pump the light. No current gain yet: the target at once.
function Gain.Smooth(current, target, dt, fall, rise)
    if not finite(target) or target <= 0 then return current end
    if not finite(current) or current <= 0 then return target end
    if not finite(dt) or dt <= 0 then return current end
    local from, to = log(current), log(target)
    local tau = to < from and fall or rise
    if not finite(tau) or tau <= 0 then return target end
    return exp(to + (from - to) * exp(-dt / tau))
end

-- Whether the light jumped (a camera cut, a teleport) rather than moved since the last frame: then
-- the gain is set to its target at once. moved: units the light moved; turnCos: the cosine of the
-- angle it turned; distance: how far its subject is.
function Gain.Jumped(moved, turnCos, distance)
    if not finite(moved) or not finite(turnCos) then return true end
    local reach = finite(distance) and distance > 0 and distance or 0
    return moved > math.max(32, 0.25 * reach) or turnCos < 0.94 -- about 20 degrees
end

-- Directions to sample around a light's axis, as coefficients of its forward, right and up vectors:
-- the axis first, then `count` directions `angle` degrees off it, evenly around it.
function Gain.Ring(angle, count)
    local out = { { 1, 0, 0 } }
    local a = rad(finite(angle) and angle or 0)
    local c, s = cos(a), sin(a)
    for i = 0, (count or 0) - 1 do
        local phi = 2 * pi * i / count
        out[#out + 1] = { c, s * cos(phi), s * sin(phi) }
    end
    return out
end

-- A colour temperature in kelvin as red, green and blue factors with the luminance of white
-- (Rec. 709 weights), so a warmer or cooler light is no darker. A curve fit of the black body's
-- colour, 1000-40000 K; 6600 K is white.
function Gain.Kelvin(kelvin)
    local t = clamp(finite(kelvin) and kelvin or 6600, 1000, 40000) / 100
    local r, g, b
    if t <= 66 then
        r = 255
        g = 99.4708025861 * log(t) - 161.1195681661
    else
        r = 329.698727446 * (t - 60) ^ -0.1332047592
        g = 288.1221695283 * (t - 60) ^ -0.0755148492
    end
    if t >= 66 then
        b = 255
    elseif t <= 19 then
        b = 0
    else
        b = 138.5177312231 * log(t - 10) - 305.0447927307
    end
    r, g, b = clamp(r, 0, 255) / 255, clamp(g, 0, 255) / 255, clamp(b, 0, 255) / 255
    local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if luminance <= 0 then return 1, 1, 1 end
    return r / luminance, g / luminance, b / luminance
end

return Gain
