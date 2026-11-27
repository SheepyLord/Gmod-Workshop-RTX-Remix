# Our night sky on the Enhanced sky: report (2026-11-27)

The user, at the Enhanced sky's merge on 2026-11-26: "Yes, and open this for later, we should adapt our own night sky
with the enhanced night." The same evening: "Plan how our own night sky could be integrated into the Enhanced sky, and
show the user the design before any code." The design, [sky-enhanced-night-plan.md](sky-enhanced-night-plan.md), was
shown with pictures of both nights, and the user answered "Yes, as recommended": our night sky image by default with
the library's real stars one choice away; the library's Moon with our glow; the library's airglow alone; sun dogs and
the other ice halos a separate study later. [ADR 0271](../decisions/0271-our-night-sky-on-the-enhanced-sky.md).

Coded by Codex in three tasks, reviewed and tested here: NC (the companion, [report](sky-enhanced-NC-report.md)), NR
(runtime patch 0116, [report](sky-enhanced-NR-report.md)) and NR2 (runtime patch 0117, the same report's NR2 section),
after round 3's fixes ([sky-enhanced-round3-report.md](sky-enhanced-round3-report.md)), whose disc drawing the night
builds on.

## What changed

- **The night sky image in Enhanced** (patch 0116): the image's four layers (stars, constellations, Milky Way,
  nebulae) with the Night sky editor's brightness and colour for each, drawn in the Enhanced composite and in mirror
  reflections, behind the air and the clouds, hidden by the Moon, turning with the library's celestial frame, with
  Standard's twilight. The choice `rtx.atmosphere.numos.nightSkyImage` (default True) turns the library's own stars
  and Milky Way off while the image shows and puts back the starlight they scatter into the night air (identical
  in-scatter for both choices, measured on the library's own bake).
- **Shooting stars, the Moon's glow, the eclipse's chromosphere and corona** as Standard draws them.
- **Brightness** (patches 0116, 0117): the image's Milky Way matched to the library's (Gaia) in light units, measured
  at 99.98 % at a traced pixel's footprint; then +6 stops (64 times), because at the physical match the image read
  almost black in the PoC where Standard shows it bright. The library's real stars stay physical.
- **A solar eclipse in Enhanced** (patch 0117): the library dims the Sun only for its real Moon, so a total eclipse
  kept a day sky. The runtime now dims the sunlight the library gets by the uncovered share of the Sun's disc; the
  library's star gate follows. Offline at totality with the Sun 40 degrees up: sky, clouds and sunlight at 0.060 % of
  clear daylight.
- **The companion** (task NC): the Night sky editor serves both skies; a **Stars** choice (Night sky image / Real
  stars, `nativeloader_sky_enhanced_stars`, default `map`); the editor's values reach the runtime in Enhanced; the
  controls that act only in Standard say so; the solar eclipse control places the Enhanced Moon over the Sun with the
  library's own sun size.

## In the PoC

gm_construct from the spawn, 4K, DLSS, the branch's package (`out/sky2/NIGHT1` with patch 0116,
`out/sky2/NIGHT2-gain` the brightness sweep, `out/sky2/NIGHT3` with 0117; sheets in `out/sky2/judged/night/`):

- **Clear moonless midnight:** Enhanced with the image looks as Standard does (nebulae, constellations, the galaxy
  band). With 0116 alone it was almost black: the sweep through the Starlight setting matched Standard between +5 and
  +7 stops (mean sky-region value 0.017/0.018 at 0, 0.050/0.068 at +5, 0.066/0.094 at +7, Standard 0.067/0.075).
- **Real stars:** the library's physical night, as before.
- **Partly cloudy:** clouds cover the image. **Full moon:** the library's Moon with our glow over the image. **Dusk:**
  the image fades in as in Standard, the stars first, the nebulae at full darkness.
- **Shooting stars** at 15 a minute: a streak in one of four frames.
- **Total solar eclipse:** a dark sky with stars and the image, a black Moon and a white corona (Standard's corona has
  longer streamers). With 0116 alone the sky had stayed day-blue.
- **Frame time** (one launch, medians): Enhanced with the image 7.0-10.0 ms, with real stars 7.4-10.2, Standard
  10.8-13.6. The image costs nothing measurable over the real stars.
- No error in the game's Lua or the Remix log beyond the known shader-model lines.

## Not checked

- The field game; a Radeon card; VR (it keeps Standard).
- Water or a mirror at night in the game (Codex checked the reflection path offline against the camera's).
- An eclipse's partial phases in the game (the offline test covers ingress); a crescent Moon's glow.
- The Night sky editor page in use at 4K (built and exercised offline by the companion's tests).

## State

- Branch `sky-enhanced-3`: NC, NR and NR2 merged; the runtime stored (`d3d9.dll` `e533151a`, built from fork
  `d3a4cea74` with patches 0001-0117).
