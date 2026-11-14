# 0207: The Moon by day

- Status: Accepted 2026-11-14 (QoL item; the in-game checks are the user's, see the report)
- Decided by: the agent, on the user's request: "Enhance the skybox about the moon, the moon should be visible during
  the day given correct moon phase." How bright the day's Moon is, and the companion's slider, were the agent's choice,
  made from the runtime's own formulas offline ([`moon_daylight.py`](../../tools/sky/moon_daylight.py.md)); the
  coordinating session reviews the branch.
- Runtime patch: `runtime/patches/0090-Atmosphere-the-Moon-by-day.patch` ([runtime/README.md](../../runtime/README.md));
  report: [moon-by-day-report.md](../handover/moon-by-day-report.md).

## Context

The companion's sky ([ADR 0031](0031-physical-sky-time-and-weather.md), [ADR 0032](0032-real-moon-stars-eclipses-and-fog-presets.md))
already puts the Moon where its phase says: `phase` of a turn east of the sun along the ecliptic, so a first quarter
rises at noon and stands high in the afternoon, a waning Moon in the morning sky. The runtime hid it there.
`evalSkyRadiance` (`atmosphere_sky.slangh`) drew the moons "only visible at night": each disc's coverage was multiplied
by `smoothstep(0, -0.09, sun.y)`, zero while the sun is up, and the disc then replaced the background where it covered:
`radiance = mix(radiance, moon, coverage)`.

A real Moon lies beyond the air. What reaches the eye from its direction is the air's in-scatter in front of it plus the
Moon's light dimmed by that air; only what lies beyond the Moon is hidden. By day the in-scatter is the blue sky, so the
unlit part of the disc is the sky's blue and the lit part a pale disc. The runtime's disc already carries the air's
transmittance (`moonAirTrans`, the Kasten-Young air mass of the cloud and moon paths) and lights the textured Moon
physically: the sun's illuminance times brightness / pi times the albedo times a Lunar-Lambert term (0.75
Lommel-Seeliger + 0.25 Lambert). Adding that disc to the day sky shows how it would look. Against the runtime's own sky
(the sky-view LUT's march, rebuilt offline with the weather presets' air, aerosol and sun; RESEARCH.md, "The Moon by
day") its full Moon is right: 0.035 of the sun's illuminance per steradian at the disc's mean, where the real full Moon,
geometric albedo 0.12, has 0.038. Its partial phases are not: the Lunar-Lambert term keeps a quarter at 37 % of full and
a crescent (phase 0.15) at 13 %, where the real Moon, whose rough surface shadows itself and whose full face has the
opposition surge, gives 9.1 % and 1.9 % (Allen's phase law, `0.026 a + 4e-9 a^4` magnitudes). At night that hardly
shows: the disc is thousands of times brighter than the night sky around it, and the night's exposure draws it near white
whatever its phase law. By day it would: under partly cloudy skies on a summer afternoon a crescent drawn so is 0.6 to 2.1 times brighter than the sky
around it, a quarter 0.4 to 2.8 times, a white sticker, where a real one is 8 to 64 % brighter (the table below).

## Decision

1. **A moon's light is added to the sky in front of it; its disc hides only what lies beyond it** (patch 0090,
   `evalSkyRadiance`). Beyond it, as the sky has treated them: the stars and the night sky image (the star layer,
   composited after the clouds by the moons' coverage), the airglow layer and the halos (`beyondMoons`), the moons before
   it in array order (later ones in front), and the everyday sun disc. With the sky's in-scatter faded out (R18's
   `atmosphereFade`, the sun 16 degrees down) the sum is exactly the old replace composite, so the night is unchanged.
   Between there and sunset the twilight's own light now lies over the disc instead of under it: under 1 % of the disc's
   light from the sun's 5 degrees down on (its sky there is 0.001 against a lit part of 0.33-0.41), more above, where
   the old disc was still fading in and all but transparent.
2. **The disc is whole at any hour; by day its light follows the real Moon's phase law.** The CPU
   (`rtx_moon_daylight.h`) computes, for each moon's phase, the real law over the drawn one, `realMoonLight(a) /
   drawnMoonLight(a)` (the latter the closed forms of the Lommel-Seeliger and Lambert disc integrals, checked against a
   brute-force sum in `test_moon_daylight.cpp`), held from 150 degrees, where Allen's fit ends and the drawn sliver
   vanishes faster than the fitted law: 1 at full, 0.40 gibbous, 0.25 quarter, 0.15 crescent, 0.107 at new. It times
   `rtx.atmosphere.daytimeMoonBrightness` and goes to the shader as `moonDaytimeScale0-3`, one new 16-byte row of
   `AtmosphereArgs` (four floats, so the struct's alignment stays 4), which `normalizeForSkyLutCache` zeroes: no bake
   reads it. The shader hands the scale over to 1, the night's look, with the old fade (`smoothstep(0, -0.09, sun.y)`, 0
   with the sun up, 1 from 5.16 degrees down). The earthshine is scaled with it, so by day it is about a thousandth of
   the sky or less, invisible as it should be.
3. **`rtx.atmosphere.daytimeMoonBrightness`** (float, default 1, 0 to 4): the day's Moon as a multiple of the real one;
   0 is no moon by day, the old look. The default is the physical one; the numbers below say it is visible.
4. **The horizon hides a disc below it** (two pixels soft, as the eclipse's edges), as it hides the stars. The lower half
   of the sky is the ground's haze and the moon showed through it, day or night. With `rtx.atmosphere.noHorizon`
   ([ADR 0139](0139-the-sky-without-a-horizon.md)) the moons show where they are, as before.
5. **The halo, the clouds' moonlight and the Moon's ground light stay night-only.** The halo is a stylised glow tuned for
   the night's exposure and would add 2 % of the sky by day; the clouds and the ground are lit by the sun then; the
   companion's `surfaceMoonBrightness` fade is unchanged.
6. **The everyday sun disc lies beyond the moons.** A solar eclipse hands it over to its own disc before the Moon touches
   it (`solarEclipseApproach`), so with eclipses on nothing changes; with eclipses off a Moon set in front of the sun now
   covers it instead of letting it shine through. The eclipse's own path (`evalSolarEclipse`, its `moonMask`), the stars
   at totality and the lunar eclipse are unchanged; at totality the Moon also hides the airglow behind it.
7. **The companion: Moon by day** (`nativeloader_sky_moon_day`, a saved client setting, 1, held to 0-4), a slider under
   Moon in the Sky and weather panel, sends the option with the rest of the sky (like the moon's phase it is a sky
   setting: changing it takes a map's own sky over). The status line names it; the reset puts it back. The dev menu has
   it as Daytime Brightness under Moons, Global Lighting. Translated in the companion's and the runtime's six catalogs.

### The numbers

Summer at latitude 40, partly cloudy (the companion's default weather), the lit part's mean luminance over the sky's
where the Moon stands; luminances in the runtime's units, the sun's illuminance 19 (`moon_daylight.py`):

| Time | Moon | Sun, Moon height | Sky | Shown (this decision) | Night's look by day | Real Moon |
|---|---|---|---|---|---|---|
| 07:00 | last quarter | 26, 52 | 0.18 | 0.53 | 2.14 | 0.49 |
| 09:00 | waning crescent | 49, 66 | 0.24 | 0.23 | 1.55 | 0.20 |
| 13:00 | waxing crescent | 69, 47 | 0.32 | 0.16 | 1.12 | 0.14 |
| 13:00 | first quarter | 69, 13 | 0.71 | 0.09 | 0.37 | 0.08 |
| 14:30 | first quarter | 54, 30 | 0.36 | 0.25 | 0.99 | 0.23 |
| 16:00 | first quarter | 37, 45 | 0.23 | 0.41 | 1.64 | 0.38 |
| 18:00 | waxing gibbous | 15, 32 | 0.26 | 0.60 | 1.52 | 0.59 |
| 19:00 | first quarter | 4, 53 | 0.08 | 1.26 | 5.08 | 1.17 |

Clear and hazy skies give the same within 15 %. So by default the day's Moon is a pale disc 10 to 70 % brighter than
the blue around it while the sun is up, more at dusk, and it nearly vanishes in the haze near the horizon (a crescent 8
degrees up at 14:30: 2 %) or near the sun, as the real one does. 10 % is five times what the eye needs on an even field
(the Weber fraction of a large target, 1-2 %). The tone mapper's shoulder compresses that somewhat at the sky's bright
end, which the slider answers. No single constant would do instead of the phase law: matching the quarter (0.25) would
leave a crescent 1.7 times too bright and a gibbous Moon 0.6 times too dim.

## Alternatives

- **The night's disc, unscaled, by day.** The brief's first sketch: the physics of the composite is right, but the
  drawn phase law makes partial phases up to five times brighter than the sky around them (the table's night column),
  a sticker rather than the daytime Moon.
- **The real phase law day and night.** One law everywhere, but the night's Moon would change (a quarter at a quarter of
  its light now), which the request did not ask for; at night the disc reads near white either way.
- **A constant daytime factor.** See the numbers: wrong by up to a factor of two at the companion's phases.
- **Keeping the old fade as a translucent disc.** Hiding part of the sky's in-scatter behind a disc that lies beyond the
  air is not what a sky does, and at dusk it showed a ghost.
- **Leaving a moon below the horizon.** It showed through the ground's haze; the stars there already fade out.

## Consequences

- The runtime: patch 0090; `d3d9.dll` 418,989,056 bytes (+520 KB of shader code), SHA-256
  `fb0e2b21d057a76ee0572c57d5e33311a94e048ed5c54758102a61b6ec5b2ee0` (on the same branch replaced by the 0001-0092
  build of [ADR 0216](0216-the-runtimes-pipeline-handle-race-and-in-present-message-dispatch-fixed.md),
  `e242dfdb...`). Every sky pixel now runs the moons' disc test by
  day too (a dot product and an early return per enabled moon); nothing else is added, no texture, no pass.
- Nights are unchanged once the sun is 16 degrees down, and to within 1 % of the disc's light from 5 degrees down. A moon
  below the horizon is hidden at night too.
- The in-game checks are open (the report lists them): the Moon at noon (crescents up and faint), a first quarter in the
  afternoon, dusk, night, both eclipses, and the sky without a horizon.
- Found on the way, not changed: the multiple-scattering LUT's bottom row samples exactly on the ground, where the
  planet test finds the ground at distance 0 in every direction, so that row holds nothing (RESEARCH.md); the day sky is
  6 to 11 % darker than its physics in the estimate. A fix would change every sky; it is left for a decision of its own.
