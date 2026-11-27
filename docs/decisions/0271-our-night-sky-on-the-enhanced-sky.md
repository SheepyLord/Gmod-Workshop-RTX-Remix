# 0271: Our night sky on the Enhanced sky

- Status: Accepted 2026-11-26: the user approved the design "as recommended" (the four answers below) before any code.
- The user, at the Enhanced sky's merge (ADR 0267): "Yes, and open this for later, we should adapt our own night sky
  with the enhanced night." The same evening: "Plan how our own night sky could be integrated into the Enhanced sky,
  and show the user the design before any code."
- Runtime patches 0116 and 0117, the companion. No loader (`winmm.dll`) change.
- Design and briefs: [sky-enhanced-night-plan.md](../handover/sky-enhanced-night-plan.md). Reports:
  [the night](../handover/sky-enhanced-night-report.md), [runtime](../handover/sky-enhanced-NR-report.md),
  [companion](../handover/sky-enhanced-NC-report.md).

## Context

The Enhanced sky (the NUMOS library, pinned and unmodified, ADR 0267) shipped with the library's own night: real stars
from the Hipparcos catalogue, the Milky Way from Gaia, physical airglow and zodiacal light, a Moon that lights the
clouds. Our Standard night is a picture with an editor (ADR 0227): the night sky image's stars, constellations,
Milky Way and nebulae, each with a brightness and a colour, shooting stars, a glow round the Moon, and a solar
eclipse with a chromosphere and corona. None of that showed in Enhanced.

## Decision

The library keeps what it does best (the air, the twilight, the Moon's light on the clouds and the map); our night
sky brings its look and its editor. The runtime draws our parts in the Enhanced sky's own composite and in mirror
reflections, as it draws the sun rays and the discs (ADR 0270); the library stays unmodified.

1. **Stars in Enhanced: our night sky image by default** (the user's answer 1), the library's real stars one choice
   away (`rtx.atmosphere.numos.nightSkyImage`, the Night sky editor's Stars choice, `nativeloader_sky_enhanced_stars`).
   While the image shows, the library's own stars and Milky Way are off; the starlight they scatter into the night air
   is put back, so the air is the same with either choice.
2. **The image** is drawn behind the air (the library's transmittance) and the clouds, hidden by the Moon, turning
   with the library's celestial frame, with Standard's twilight (stars and constellations from the Sun about 1 degree
   down, the Milky Way and nebulae at full darkness) and the editor's four layers. Its brightness is the library's
   Milky Way matched in light units (a measured factor) and then raised so the editor's defaults look as they do in
   Standard (the PoC matched Standard at +5 to +7 stops; +6 chosen); Night brightness and Starlight move it on top.
3. **The Moon: the library's**, which lights the clouds and the map, with our glow round it (the user's answer 2).
4. **Night glow: the library's physical airglow alone** (the user's answer 3); the editor's Night glow and the
   simulated stars and earthshine belong to Standard, and the page says so.
5. **Shooting stars and the solar eclipse's chromosphere and corona** as Standard draws them. A total solar eclipse
   dims the sunlight the library gets by the uncovered share of the Sun's disc, so the sky darkens and the stars show.
6. **One Night sky editor page for both skies.** VR keeps Standard.
7. **Sun dogs and the other ice halos in Enhanced: a separate study later** (the user's answer 4).

## Consequences

- The default Enhanced night looks like our Standard night above moonlit clouds and the library's twilight.
- The image costs nothing measurable over the real stars (PoC, one launch, 4K).
- A future pin of the library must recheck the starlight term put back for the night air
  (`src/renderer.cpp` at the pin) and the eclipse's dimming.
