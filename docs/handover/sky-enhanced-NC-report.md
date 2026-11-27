# The Night sky editor in Enhanced, Task NC

**First PoC check.** At midnight on a clear map, open **Night sky editor → Stars** in Enhanced. Start with
**Night sky image**, set Constellations to 0, then raise it again. Switch to **Real stars** and back. The
catalogue and Milky Way should replace the image, the layer controls should keep their values, and
starlight on the ground and clouds should persist. Repeat facing reflective water and through broken cloud.
The [approved design](sky-enhanced-night-plan.md) assigns rendering, image calibration and reflections to NR.

## Star sources and option routing

Enhanced's archived client setting is `nativeloader_sky_enhanced_stars`. Its default `map` requests
`rtx.atmosphere.numos.nightSkyImage = True`. The other choice, `real`, requests False. The companion sends
this option only for its active Enhanced sky. Choosing it in Standard, in VR or on a map with its own sky
saves the preference for the next Enhanced session. It preserves map ownership and the player's time and
weather. Standard still uses `nativeloader_sky_stars`.

Enhanced receives the existing night editor options at their original names and scales. The runtime can
read them on entry and after a live edit with either star source. The companion continues to supply the
library's celestial frame, Moon and starlight settings. NR uses the new image switch to select the visible
stars while preserving physical starlight. The companion does not apply Standard's night glow or earthshine
to the NUMOS atmosphere. The page keeps those controls visible and labels their scope.

## Night sky editor controls

The numeric rows give the archived client convar and its default. A multiplier in the table applies to the
slider value before it is sent. Unqualified runtime names are under `rtx.atmosphere.`. Image controls
affect the picture when the active provider uses the image. Brightness
zero hides a layer, and the colour sliders run from grey at 0 through original colour at 1 to stronger
colour at 2.

| Control | Client setting or action | Standard | Enhanced |
|---|---|---|---|
| Go to night | `nativeloader_sky_time night` | Set the clock to 23:00 | Same clock |
| Time passes | `nativeloader_sky_time_passes` = 1 | Run or stop the clock | Same clock |
| Stars | `nativeloader_sky_enhanced_stars` = `map` | Save the Enhanced preference | Image (`map`) or catalogue stars and Milky Way (`real`) |
| Night sky | `nativeloader_sky_stars` = `map` | Image (`map`) or simulated stars (`procedural`) through `starMapEnable` | Keeps Standard's source setting for a later switch |
| All layers | `nativeloader_sky_night_image` = 1 | Overall image brightness, `starMapBrightness` ×0.12 | Same image control, also subject to Enhanced night and star gain |
| Stars | `nativeloader_sky_stars_brightness` = 1 | Star-layer brightness, `starMapStarBrightness` | Same layer |
| Star colour | `nativeloader_sky_stars_colour` = 1 | `starMapStarSaturation` | Same layer |
| Constellations | `nativeloader_sky_constellations_brightness` = 1 | `starMapConstellationBrightness` | Same layer |
| Constellation colour | `nativeloader_sky_constellations_colour` = 1 | `starMapConstellationSaturation` | Same layer |
| Milky Way | `nativeloader_sky_milky_way_brightness` = 1 | Galaxy-band brightness, `starMapGalaxyBrightness` | Same image band |
| Milky Way colour | `nativeloader_sky_milky_way_colour` = 1 | `starMapGalaxySaturation` | Same image band |
| Nebulae | `nativeloader_sky_nebulae_brightness` = 1 | `starMapNebulaBrightness` | Same layer |
| Nebula colour | `nativeloader_sky_nebulae_colour` = 1 | `starMapNebulaSaturation` | Same layer |
| Simulated brightness | `nativeloader_sky_simulated_brightness` = 1 | `starBrightness` ×0.5 | Standard-only effect. Enhanced has Starlight in its own editor |
| Simulated density | `nativeloader_sky_simulated_density` = 0.5 | `starDensity` | Standard-only effect |
| Simulated twinkle | `nativeloader_sky_simulated_twinkle` = 1 | `starTwinkleSpeed` | Standard-only effect. Real stars use Enhanced's Star twinkle |
| Moon brightness | `nativeloader_sky_moon_brightness` = 1 | `moon0.brightness` scales the disc and its light on the map | Disc gain in `numos.moonDiscGainStops`, log₂ of brightness with a floor of −16. Enhanced Moonlight controls light on the ground |
| Moon size | `nativeloader_sky_moon_size` = 1.6° | Apparent diameter through the historical `moon0.angularRadius` key | Same diameter through `numos.moon0.angularDiameter` |
| Moon glow | `nativeloader_sky_moon_glow` = 1 | `haloMoonBrightness` ×15 | Same glow control for the library's Moon |
| Earthshine | `nativeloader_sky_earthshine` = 1 | Dark-side brightness, `moon0.darkSideBrightness` ×0.005 | Standard-only effect. NUMOS computes earthshine from lunar phase |
| Shooting stars per minute | `nativeloader_sky_shooting_stars` = 1.2 | `shootingStarsPerMinute`, including 0 to stop | Same rate with either star source |
| Shooting-star brightness | `nativeloader_sky_shooting_star_brightness` = 1 | `shootingStarBrightness` | Same brightness |
| Night glow | `nativeloader_sky_night_glow` = 1 | Scales the weather's `nightSkyBrightness`, with the existing 0.05 factor under the Standard image | Keeps the Standard option current when the companion supplies a weather. Enhanced uses physical airglow and zodiacal light |
| Reset the night sky | `nativeloader_sky_night_reset` | Restores the numeric editor defaults | Also restores Enhanced's Stars choice to Night sky image |

The common keys for simulated stars, earthshine, Moon size and brightness still receive the editor values
in Enhanced. Only the documented active mappings affect that sky. The four image layers, shooting-star
controls and Moon glow now reach Remix through the same path on both providers. With weather left to Remix,
the companion has no Standard weather airglow to scale.

## More PoC checks

- Watch the stars and constellations appear during early twilight, then the galaxy and nebulae in deeper
  darkness. Compare the image and real-star choices at midnight while adjusting Enhanced Night brightness
  and Starlight. Check the mean brightness of the Milky Way with NR's calibration.
- Try a full Moon and a crescent under moving cloud. Adjust Moon glow and disc brightness independently
  of the Moonlight setting on the ground. Raise the shooting-star rate briefly, check its reflection, and
  return the rate to zero. Changing Standard Night glow, simulated stars or Earthshine should preserve
  the Enhanced night lighting.
- Select Solar eclipse at night. The companion moves the clock to noon and places the new Moon at first
  contact (0%), inner contact (90%) or centre (100%). Check the corona, chromosphere, cloud cover and
  reflection with both star choices. Zero daytime Moon brightness still leaves the occulting body enabled.
  Contact timing uses the NUMOS Sun diameter in `rtx.conf`, read once per map on the first solar eclipse,
  or the library default of 0.545°. An Alt+X-only change to Sun size can shift intermediate contacts. At
  100% the directions coincide at any size.
- Choose simulated stars in Standard and the image in Enhanced. Switching to Standard or VR should
  show Standard's saved source. The image should return when the desktop Enhanced sky resumes.

## Offline checks

The [sky suite](../../tools/tests/test_companion_sky.py.md) checks every numeric editor option at its
native key, startup, live editing and reset, independent saved star choices, unowned maps, VR, physical
lighting settings, and four solar contact positions with different Sun and Moon sizes. Its existing
Standard parity fixture compares all 345 recorded writes.

- `python -m unittest discover -s tools/tests -p test_companion_sky.py -q` passed all 65 tests under LuaJIT.
- `python -X utf8 tools/companion_i18n.py update` and `python -X utf8 tools/companion_i18n.py check`
  reported 972 complete companion texts and 485 complete bundled add-on texts per language. Python wrote
  the fourteen new or revised messages per language with explicit UTF-8. A readback verified all six
  languages and all 8,742 translations. None had a replacement character or more ASCII question marks
  than its English source.
- `tools\test.ps1 -Config Release` finished with **All checks passed**. CTest passed 35/35. The Python
  suites ran 29 gmapack tests (1 skipped), 26 Steam tests (1 skipped) and 2,268 tools tests (8 skipped).
  The first run hit Windows error 5 while the runtime-package test renamed a synthetic staging directory.
  `python -m unittest discover -s tests -p test_package_runtime.py -k test_force_replaces_only_a_package_folder`
  from `tools/` passed in isolation, followed by the complete passing rerun on the same package inputs.

The last native build finished on **2026-11-27 at 05:06:53 UTC**. CTest finished at 05:07:47 UTC
and the full Release suite finished at **05:16:16 UTC**.

Visual calibration, in-game appearance, reflections and GPU cost remain with NR and the reviewer. No game
session ran for NC. The six translations are agent-written and await human review.
