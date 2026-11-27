-- NUMOS preset data: Copyright 2026 Kim2091 (Sparkles)
-- SPDX-License-Identifier: Apache-2.0
-- Numeric settings from NUMOS 41842c6, include/numos/settings_fields.inl and src/weather.cpp.
-- Keys are relative to rtx.atmosphere.numos. The twelve tables at the end are the GMod looks.
local defaults = {
    cloudCoverageMean = 0.54, cloudTypeMean = 0, cloudTypeSpread = 0.54, cloudDensity = 20,
    cloudBaseHeightMeters = 1300, cloudDepthMeters = 2000, cloudWindSpeed = 0.02, cloudWindDirection = 45,
    cloudLayer2Enable = false, cloudLayer2CoverageMean = 0.85, cloudLayer2BaseHeightMeters = 5500,
    cloudLayer2DepthMeters = 2000, cloudLayer2TypeMean = 0.6, cloudLayer2DensityScale = 0.65,
    cloudCirrusEnable = false, cloudCirrusCoverageMean = 0.6, cloudCirrusBaseHeightMeters = 9500,
    cloudCirrusOpticalDepth = 0.25, cloudCirrusStreakDirection = 30,
    nubis3ErosionStrength = 0.58, cloudBodyBillowSizeKm = 1.2, cloudBodyBillowGain = 0.65,
    cloudCurlStrengthKm = 0.12, cloudDiffuseSunStrength = 0,
    aerosolDensity = 1.1, aerosolTint = {1, 1, 1}, fogVisibilityMeters = 0,
    mieAbsorption = {0.0044, 0.0044, 0.0044},
    fogHeightFalloffMeters = 100, fogAlbedo = 0.9, fogAnisotropy = 0.3, lightningStrikesPerMinute = 0,
    aerialPerspectiveFroxelRangeMeters = 1000,
    cloudCoverageSpread = 0, cloudCellSizeKm = 3.65, cloudColor = {0.89, 0.92, 1},
    cloudColumnTopVariation = 0.45, cloudColumnFeather = 0.35, cloudLayer2Albedo = {1, 1, 1},
    cloudCirrusHaloStrength = 1, cloudEvolutionSpeed = 0.002, airDensity = 1, airTint = {1, 1, 1},
    ozoneDensity = 1, mieAnisotropy = 0.8, fogBaseHeightMeters = 0,
}

local function with(base, changes)
    local result = {}
    for key, value in pairs(base) do result[key] = value end
    for key, value in pairs(changes) do result[key] = value end
    return result
end

-- Built-in weather starts with both upper layers clear. Overcast, Drizzle and Storm share a grey sheet.
-- The library's night is physically dim: at its own level the PoC's night was black (2026-11-26). Ten stops of night
-- gain gave a moonlit night with stars and lit cloud; six was still dark, thirteen looked like day.
--
-- Lamps in the near haze are off. On gm_construct they cost 16 ms a frame at 4K on average: 23-30 ms with them,
-- 10-12 without, Standard 10-13 (PoC, 2026-11-26, ten views in one launch). What they drew for it was a ceiling
-- lamp's soft cone and a doorway's glow in dense fog at night, and nothing in the other eight views. They can come
-- back when they cost a fraction of that.
-- The haze's scene shadow costs nothing and stays on: without it a white veil washes the map out.
-- Round 2 (2026-11-26): the lamps are the player's choice (Lamp glow in mist, off by default). What costs is the
-- number of lights a 64-pixel tile draws: on gm_construct in dense fog at night, 31 ms a frame at the library's 64,
-- 14.9 at 8, 13.3 at 4, 12.6 at 2, against 11.8 with no lamps; a high cutoff is cheap but ends each glow at a hard
-- edge. With the flashlight one view still cost 12 ms more at 4 a tile.
local mode = {
    common = {nightGainStops = 10, unitsPerMeter = 1 / 0.01905, aerialPerspective = true,
        timeCycleEnable = false, nightSkyStars = true, realMoonEnabled = false},
    high = {qualityLevel = 0, ["rays.quality"] = 0, aerialPerspectiveLocalLights = false,
        aerialPerspectiveLocalLightCutoff = 0.002, aerialPerspectiveLocalLightTileMaxCount = 4,
        aerialPerspectiveLocalLightMaxCount = 64, aerialPerspectiveLocalLightShadows = true, aerialPerspectiveLocalLightWindow = false},
    medium = {qualityLevel = 1, ["rays.quality"] = 1, aerialPerspectiveLocalLights = false,
        aerialPerspectiveLocalLightCutoff = 0.005, aerialPerspectiveLocalLightTileMaxCount = 4,
        aerialPerspectiveLocalLightMaxCount = 48, aerialPerspectiveLocalLightShadows = true, aerialPerspectiveLocalLightWindow = false},
    low = {qualityLevel = 2, ["rays.quality"] = 2, aerialPerspectiveLocalLights = false,
        aerialPerspectiveLocalLightCutoff = 0.01, aerialPerspectiveLocalLightTileMaxCount = 2,
        aerialPerspectiveLocalLightMaxCount = 32, aerialPerspectiveLocalLightShadows = false, aerialPerspectiveLocalLightWindow = false},
}
local sky = with(defaults, {cloudLayer2CoverageMean = 0, cloudCirrusCoverageMean = 0})
-- The sheet's base is at 800 m, and the near haze ends at 1 km by default. A view steeper than about 53 degrees
-- meets the deck inside that range, which drew a pale ring 35-40 degrees round the zenith in the PoC's storm
-- (2026-11-26). At 6 km the ring is gone and the storm's clouds show, for 0.4-0.9 ms; at 20 km storms turn a flat
-- blue-purple.
local sheet = with(sky, {
    aerialPerspectiveFroxelRangeMeters = 6000,
    cloudTypeMean = 1, cloudBaseHeightMeters = 800, fogHeightFalloffMeters = 600,
    nubis3ErosionStrength = 1, cloudBodyBillowSizeKm = 0.8, cloudBodyBillowGain = 0.8,
    cloudCurlStrengthKm = 0.25, cloudDiffuseSunStrength = 1,
    cloudLayer2Enable = true, cloudLayer2CoverageMean = 0.97, cloudLayer2DepthMeters = 600,
    cloudLayer2TypeMean = 0, cloudLayer2DensityScale = 0.5,
})
local base = {
    Clear = with(sky, {cloudCoverageMean = 0, aerosolDensity = 0.6}),
    PartlyCloudy = with(sky, {cloudCoverageMean = 0.45, cloudTypeMean = 0.7}),
    Overcast = with(sheet, {cloudCoverageMean = 0.6, cloudDensity = 25, cloudDepthMeters = 1800,
        fogVisibilityMeters = 40000, fogAlbedo = 0.5}),
    Haze = with(sky, {cloudCoverageMean = 0.2, cloudTypeMean = 0.6, aerosolDensity = 4,
        fogVisibilityMeters = 5000, fogHeightFalloffMeters = 800, fogAlbedo = 0.85}),
    Fog = with(sky, {cloudCoverageMean = 0.75, cloudTypeMean = 0, cloudTypeSpread = 0.1,
        cloudBaseHeightMeters = 400, cloudDepthMeters = 800, aerosolDensity = 2.5,
        fogVisibilityMeters = 300, fogHeightFalloffMeters = 150, fogAlbedo = 0.95, cloudWindSpeed = 0.006,
        cloudLayer2Enable = true, cloudLayer2CoverageMean = 0.92, cloudLayer2BaseHeightMeters = -20,
        cloudLayer2DepthMeters = 220, cloudLayer2TypeMean = 0, cloudLayer2DensityScale = 0.5}),
    Drizzle = with(sheet, {cloudCoverageMean = 0.58, cloudDensity = 25, cloudDepthMeters = 3500,
        cloudWindSpeed = 0.025, fogVisibilityMeters = 20000, fogAlbedo = 0.4}),
    Storm = with(sheet, {cloudCoverageMean = 0.65, cloudDensity = 30, cloudDepthMeters = 4000,
        cloudWindSpeed = 0.035, fogVisibilityMeters = 25000, fogAlbedo = 0.2, lightningStrikesPerMinute = 6}),
}

-- Tune a weather here, in the library's units. Cloud wind is km/s and its bearing is degrees. Host rain, snow and
-- sand stay in weather_presets.lua.
--
-- Visibility is the library's physical fog: the distance in real metres at which contrast falls to 2 %. It hides the
-- sky as real fog does. The first PoC captures (2026-11-26) used the Standard sky's short distances, 400-530 m in
-- rain and storms, and showed a flat grey with no cloud. Only fog, a blizzard and a sandstorm keep a short distance
-- now; rain and storms get kilometres, and the rain itself comes from the host's particles.
return { defaults = defaults, mode = mode, presets = {
    clear = with(base.Clear, {fogVisibilityMeters = 30000}),
    -- Round 2 (2026-11-26): the nearest cumulus was a smooth mass. Deeper erosion, finer billows and more curl give it
    -- crisp cauliflower edges (PoC trial pc3). The library's air is far cleaner than a real fair day's (an aerosol
    -- optical depth of about 0.01 at density 1, where a fair day has 0.05 to 0.2); density 10 with a fifth of the
    -- library's absorption keeps the sky blue, gives a low sun its glow and lets its rays show.
    partlyCloudy = with(base.PartlyCloudy, {fogVisibilityMeters = 20000,
        cloudCirrusEnable = true, cloudCirrusCoverageMean = 0.45, cloudCirrusOpticalDepth = 0.33,
        cloudCirrusStreakDirection = 110, nubis3ErosionStrength = 0.9, cloudBodyBillowGain = 0.78,
        cloudCurlStrengthKm = 0.2, aerosolDensity = 10, mieAbsorption = {0.00088, 0.00088, 0.00088}}),
    overcast = with(base.Overcast, {fogVisibilityMeters = 12000}),
    -- Round 2: a hazy day is the aerosol's, not dense height fog's. Fog over the map hid the sky in a grey wall while a
    -- blue sky lit the ground. Density 40 with a tenth of the library's absorption gives a milky, bright haze, a wide
    -- glow round the sun and, with a low sun behind clouds or buildings, strong rays (PoC trials hq40pf, lq40p).
    hazy = with(base.Haze, {aerosolDensity = 40, mieAbsorption = {0.00044, 0.00044, 0.00044},
        aerosolTint = {1, 0.97, 0.92}, fogVisibilityMeters = 20000, fogAnisotropy = 0.7, fogAlbedo = 0.95}),
    foggy = with(base.Fog, {fogVisibilityMeters = 400}),
    drizzle = with(base.Drizzle, {fogVisibilityMeters = 8000}),
    -- Round 2: in clearer air the storm's own clouds show, light in their shadows keeps rain clouds from going black
    -- (PoC trial rs2), and the thunderstorm's deck gets gaps, broader cells and a slate colour, so a dark mass meets
    -- bright breaks (trial u7). Looking away from the sun a closed deck still reads as overcast: the picture's
    -- exposure follows the sky.
    rainstorm = with(base.Storm, {fogVisibilityMeters = 12000, cloudDiffuseSunStrength = 0.6,
        cloudLayer2DensityScale = 0.3, lightningStrikesPerMinute = 4}),
    thunderstorm = with(base.Storm, {fogVisibilityMeters = 30000, fogAlbedo = 0.5, cloudCoverageMean = 0.9,
        cloudCoverageSpread = 0.5, cloudDensity = 45, cloudCellSizeKm = 5.5, cloudDiffuseSunStrength = 0.4,
        cloudLayer2DensityScale = 0.25, cloudColor = {0.72, 0.75, 0.82}, lightningStrikesPerMinute = 12}),
    snow = with(base.Overcast, {fogVisibilityMeters = 3000, fogAlbedo = 0.98, cloudWindSpeed = 0.012}),
    blizzard = with(base.Fog, {fogVisibilityMeters = 500, fogAlbedo = 0.98, cloudWindSpeed = 0.045}),
    sandstorm = with(base.Haze, {fogVisibilityMeters = 600, aerosolDensity = 8,
        aerosolTint = {1, 0.79, 0.50}, fogAlbedo = 0.75, cloudWindSpeed = 0.04}),
    -- Round 2: the library's aerosol is very clean (an optical depth of about 0.01 at density 1), so smog needs a
    -- density of tens; at the library's own absorption that much reads as smog: brown-grey, the sun dimmed (trial
    -- smog60). The fog thins with height so the sky above is not a wall.
    smoggy = with(base.Haze, {fogVisibilityMeters = 8000, fogHeightFalloffMeters = 300, aerosolDensity = 60,
        aerosolTint = {0.85, 0.78, 0.70}, fogAlbedo = 0.6, cloudWindSpeed = 0.007}),
} }
