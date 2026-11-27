# 0268: The Enhanced sky gets sun rays, an editor and mist choices

- Status: Accepted 2026-11-26 (the user's "Merge and publish", after the round's report), with
  [ADR 0267](0267-the-enhanced-sky-is-the-numos-library-as-a-second-sky.md), whose status records the user's answers
  at the merge: Enhanced the default sky, the credit lines, the library's own Remix menu translated. Proposed the same
  day for the user's decision.
- The user's word of 2026-11-26, after round 1: "Yes, please start round 2 and add more customization of the sky
  and cloud, not limited to presets. Codex agents can be ran in fast mode."
- Runtime patches 0109-0113, the companion. No loader (`winmm.dll`) change.
- Plan and briefs: [sky-enhanced-round2-plan.md](../handover/sky-enhanced-round2-plan.md). Reports:
  [the round](../handover/sky-enhanced-round2-report.md), [runtime](../handover/sky-enhanced-R2-report.md),
  [companion](../handover/sky-enhanced-E-report.md).

## Context

Round 1 (ADR 0267) put the sky library in as a second sky. What its tests left open:

- No sun rays in the sky: the library shades the air only in its first kilometre, and the sky beyond takes a table
  that knows no clouds.
- Each weather had one look, in a data table only Claude edits.
- In Enhanced the companion turned Remix volumetrics off and put the player's value back afterwards, from what Lua
  can read; a value changed only in the Remix menu was lost.
- Lamps in the library's haze cost 16 ms a frame on `gm_construct` and were turned off; nothing else lit fog.
- Hazy and smoggy read as fog, storms were flat, and the library has no rainbow.

## Decision

1. **Sun rays are a pass of ours on the library's cloud shadow map** (patches 0109 and 0113). For each sky pixel it
   integrates the sunlight the air scatters toward the camera beyond the library's near haze, once with the clouds'
   shadow and once without, using the library's own air, sunlight and phase functions, and the composite takes the
   difference from the sky. The library stays unmodified.
   - At strength 1 it is physical: it only removes light. Rays then show where the air is hazy and the sun is low.
   - Above 1 the removed light keeps its colour (one gain for the three channels) and leaves each channel at least a
     quarter of its value.
   - Camera rays only, at a reduced resolution with a history; no dispatch when nothing can shade the air.
2. **A sky editor, with the look as data the player owns.** Every setting that shapes the Enhanced sky is a control
   in the library's own units (46), grouped as clouds, cloud shape, a second layer, high ice clouds, wind, air, fog
   and storm. A look is one complete set of them.
   - Looks are kept by name as JSON files under `data/nativeloader_companion/sky_looks/`, shared as one line of text,
     and checked strictly (unknown, missing, duplicate or out-of-range keys refuse the whole look).
   - Starting points: the twelve weathers' looks, four of the library's presets and five of ours.
   - "My own look" replaces the weather's look; rain, snow and sand stay the weather's.
3. **Style settings apply in every weather and look:** sun rays, rainbow, night brightness, moonlight, starlight,
   star twinkle, cloud shadows, mist on the map, lamp glow in mist.
4. **The runtime decides what Remix volumetrics do in Enhanced** (`rtx.atmosphere.numos.volumetrics`, patch 0110),
   and nobody writes `rtx.volumetrics.enable` (this supersedes decision 7 of ADR 0267):
   - 0, the default: paused; the library's haze and fog run.
   - 1: Remix fog near the camera, up to its froxel range, with the library's haze beyond; the companion sends the
     look's fog to both.
   - 2: round 1's rule, kept for comparison.
5. **Lamps in the library's haze are the player's choice,** off by default, at most 4 lights a screen tile at High
   and Medium and 2 at Low.
6. **A rainbow** (patch 0111), computed in the Enhanced composite from the sun's light at the ground, shaded by the
   clouds where the rain is. The companion keeps how wet the air is from the weather's rain, drying over five minutes.
7. **The weathers' looks are retuned from PoC trials:** a bright aerosol haze for hazy days and a lighter one for
   fair weather (the library's air is far cleaner than a real day's), storms with breaks in clearer air, smog from
   the air.
8. **The adapter is released when the D3D9 device shuts down** (patch 0112).

## Consequences

- Five more runtime patches to carry, all inside the Enhanced paths; Standard's composite compiles to the same bytes.
  The shared volumetric attenuation routine of the ray tracing passes gains one test of a tag.
- The editor's settings are client console variables like the night sky editor's; a look file is small JSON.
- Rays and the rainbow depend on haze: in the library's clean air (density 1) neither the rays nor a hazy horizon
  show.
- Not done: rain shafts; storms that read dark away from the sun; our night sky editor's layers in Enhanced.

## Evidence

In [the round's report](../handover/sky-enhanced-round2-report.md): the PoC trials and verification runs, with
pictures and frame times.
