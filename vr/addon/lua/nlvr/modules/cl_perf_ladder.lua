-- V6's quality ladder. Step 1 is V1's fixed preset, so the top step renders as V1 to V4 did.
local Ladder = {}
-- Highest quality first. Each step is a complete description: the runtime applies all of it.
local steps = {
    {name = "full",     render_scale = 1.00, dlss = 1, min_bounces = 1, max_bounces = 4, volumetrics = true,  fine_clouds = true},
    {name = "high",     render_scale = 1.00, dlss = 1, min_bounces = 1, max_bounces = 3, volumetrics = true,  fine_clouds = false},
    {name = "balanced", render_scale = 0.90, dlss = 1, min_bounces = 1, max_bounces = 3, volumetrics = true,  fine_clouds = false},
    {name = "fast",     render_scale = 0.80, dlss = 0, min_bounces = 1, max_bounces = 3, volumetrics = true,  fine_clouds = false},
    {name = "faster",   render_scale = 0.70, dlss = 0, min_bounces = 1, max_bounces = 2, volumetrics = false, fine_clouds = false},
    {name = "low",      render_scale = 0.60, dlss = 0, min_bounces = 1, max_bounces = 2, volumetrics = false, fine_clouds = false},
    {name = "floor",    render_scale = 0.50, dlss = 0, min_bounces = 0, max_bounces = 1, volumetrics = false, fine_clouds = false},
}
function Ladder.Count() return #steps end
-- The slider is a ceiling, never a floor: Auto may go below it, nothing goes above it.
function Ladder.Step(index, scaleCeiling)
    index = math.Clamp(math.floor(tonumber(index) or 1), 1, #steps)
    local step = steps[index]
    local ceiling = tonumber(scaleCeiling)
    if not ceiling or ceiling ~= ceiling then ceiling = 1 end
    return {name = step.name, index = index,
        render_scale = math.min(step.render_scale, math.Clamp(ceiling, 0.25, 1.5)),
        dlss = step.dlss, min_bounces = step.min_bounces, max_bounces = step.max_bounces,
        volumetrics = step.volumetrics, fine_clouds = step.fine_clouds}
end
-- Where Auto starts, from what the loader measured about the GPU. A card that would struggle
-- never spends its first seconds missing frames before the controller notices.
function Ladder.Start(tier, vramMib)
    local vram = tonumber(vramMib)
    -- V1 capped such cards at a 0.5 scale; the lowest step keeps that, and Auto climbs if it can.
    if tier == "low" or (vram and vram > 0 and vram < 12288) then return #steps end
    if tier == "medium" or (vram and vram > 0 and vram < 16384) then return 3 end
    return 1
end
return Ladder
