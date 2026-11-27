# 0270: The Enhanced sky draws its own Sun and Moon discs, and has a Mist setting

- Status: Accepted 2026-11-26, the fixes of the user's report the same evening, after the merge of
  [ADR 0267](0267-the-enhanced-sky-is-the-numos-library-as-a-second-sky.md) and
  [ADR 0268](0268-the-enhanced-sky-gets-sun-rays-an-editor-and-mist-choices.md).
- Runtime patch 0115, the companion. No loader (`winmm.dll`) change.
- Plan and briefs: [sky-enhanced-round3-plan.md](../handover/sky-enhanced-round3-plan.md). Reports:
  [the round](../handover/sky-enhanced-round3-report.md), [runtime](../handover/sky-enhanced-S-report.md),
  [companion](../handover/sky-enhanced-H-report.md).

## Context

The Enhanced sky became the default sky on 2026-11-26. The same evening the user reported, with a screenshot:

> 2. The sun has a black circle around it if not covered by cloud.
> 3. The mist is way too strong by default and there lacks a way to disable it.

In the PoC the black circle appears only with an upscaler: 138 pixels at 0-6 of 255 at the disc's edge with DLSS, none
without an upscaler, none in Standard. The library (pinned and unmodified, ADR 0267) draws the Sun at its physical
radiance with a rim one traced pixel wide; DLSS rings on that step into black pixels. Standard met the same in R17 and
draws its disc with the centre at most 48 times the daylight and edges two pixels wide. The library's Moon has the same
narrow rim (six dark specks at a full moon with DLSS).

The mist came from round 2's tuning of the default weather: ten times the library's aerosol at a fifth of its
absorption, a milky haze over the whole sky and, through the library's aerial perspective, over the map. The only
control chose how the mist on the map is drawn, not whether.

## Decision

1. **The runtime draws the discs Enhanced shows.** For camera rays and mirror reflections (PSR) the runtime evaluates
   the sky as the library's `evalSkyRadiance` does, with the same air, ground, stars and cloud dome, but its own Sun and
   Moon discs: edges two traced pixels wide; the Sun's centre the lesser of its physical radiance and 48 times its
   illuminance (Standard's `kSunDiscPeak`), one factor for all channels; each Moon shaded by the library and held
   against its own illuminance with a smooth knee from 24 to 48 times it. Diffuse and glossy gathers, lights, LUTs,
   aureoles, the sun rays and the rainbow keep the library's arguments. The library stays unmodified (runtime patch
   0115).
2. **A Mist setting for players** (a style setting of the Enhanced sky, so it holds in every weather and look):
   0 to 2, default 1, on the Sky and weather page and in the Enhanced sky editor. It scales the haze above the
   library's clean air (aerosol density 1.1) and the height fog's extinction of whatever is on screen; at 0 nothing of
   the mist is drawn on the map either. A fog preset the player chose in the Remix settings keeps its own strength.
3. **Mist on the map gets Off:** the map is clear and the sky keeps its haze. Saved choices 0 and 1 mean what they
   meant; Off is sent as the library's aerial perspective off with Remix fog paused, not as the runtime's own value 2.
4. **The default weather has less haze:** partly cloudy's aerosol density 10 at a fifth of the library's absorption
   became 2 at the library's own absorption. In the PoC the sky's mean colour saturation went from 0.11-0.13 to
   0.18-0.26 (0.27-0.36 with no mist at all), and a low sun keeps a warm glow. Every other weather keeps its numbers.

## Consequences

- No black ring at the Sun's or the Moon's edge with DLSS in the PoC (138 dark pixels to 0 at the Sun, 6 to 0 at the
  full Moon). The Sun's disc is dimmer than physical, as Standard's is; it still shows as white.
- The runtime now holds a copy of the library's sky composition for camera and reflection rays. A future pin of the
  library must compare `evalSkyRadiance` with `numosVisibleSky` (`numos_visible_discs.slangh`).
- Our night sky on Enhanced ([sky-enhanced-night-plan.md](../handover/sky-enhanced-night-plan.md)) builds on these
  discs: the solar eclipse's corona goes where the runtime draws the Sun.
- Sun rays are fainter in the cleaner default air; the rays setting and Mist above 1 bring them back.
