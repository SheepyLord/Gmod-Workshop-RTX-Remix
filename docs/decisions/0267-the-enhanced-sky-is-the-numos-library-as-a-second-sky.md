# 0267: The Enhanced sky is the NUMOS library as a second sky

- Status: Accepted 2026-11-26 (the user's "Merge and publish", after round 2,
  [ADR 0268](0268-the-enhanced-sky-gets-sun-rays-an-editor-and-mist-choices.md)), with the user's answers to its open
  questions given at the merge (see Open, for the user). One of them changes decision 6: "publish the Enhanced sky as
  the default choice, on by default, with Standard unchanged". Proposed the same day for the user's decision.
- The user's request of 2026-11-25: "Keep the current implementation as default and implement an improved sky /
  cloud / sunray system that can be switched to."
- Runtime patches 0107 and 0108, the companion, the runtime part of the package. No loader (`winmm.dll`) change.
- Plan and briefs: [sky-enhanced-plan.md](../handover/sky-enhanced-plan.md). Reports:
  [the round](../handover/sky-enhanced-report.md), [runtime](../handover/sky-enhanced-R-report.md),
  [companion](../handover/sky-enhanced-C-report.md), [package](../handover/sky-enhanced-P-report.md).

## Context

Today's sky (ADR 0031, 0109, 0110) has ray-marched clouds, a cirrus layer, halos and twelve weathers. Its own records
name what it lacks:

- The clouds are "about ten times thinner optically than real ones" (ADR 0109), and their brightness is a tuned
  falloff, so bases stay pale.
- Every cloud takes one sun colour and dims together at sunset.
- The sky's air does not know the clouds, so nothing draws sun rays in it, and the haze is too thin to show them.
- The clouds are marched for every pixel every frame and smoothed by a fixed blend.

The sky library `Kim2091/numos-sky` (Apache-2.0) is a later form of the atmosphere code our runtime's fork began
with. It has those parts: clouds at real optical depth with multiple scattering, the sun's colour by height, a sparse
march with a history, a cloud shadow map that reaches the horizon, cirrus with its shadow and halo, and a haze system
with lit fog. Its author has written its integration into NVIDIA's runtime as one commit.

What the user decided on 2026-11-25:

- SourcePT, the project their reference pictures came from, is off limits: "without using or citing their code".
- The library "may be used": merged or taken as a dependency, with its licence notices.
- All four parts belong to the first version: dense clouds, sun rays in the sky, lit mist on the map, extras.
- The Enhanced sky gets quality levels, and its own look per weather.
- VR stays on the Standard sky.

## Decision

1. **A second sky, not a replacement.** `rtx.skyMode` 2 is the Enhanced sky, drawn by the library. Mode 1 stays
   today's sky and the default; mode 0 stays the game's own sky. Today's sky's shader sources are not edited.
2. **The library is pinned and unmodified:** `41842c69`, recorded as a clone in `runtime/base.json` like DLSS and
   SHaRC. An update is a new pin, on the user's word.
3. **The adapter is a port of the library's own integration commit** (`Kim2091/dxvk-remix` `1532c782`), as runtime
   patch 0108.
   - Both skies' shader names are kept apart by a build step. It writes a prefixed copy of the library's host
     headers for the ray tracing passes, so no ray tracing pass is compiled twice.
   - The library's settings are registered under `rtx.atmosphere.numos.`, so today's options keep their names,
     defaults and meaning.
4. **Nothing is written into the game folder.** The adapter's preset files, their folder option and its marker file
   are left out. The eleven built-in weathers stay in memory.
5. **The library's own Remix menu pages are left out.** A release build refuses a menu text without its six
   translations, and the pages have about 790. The companion's Sky page is the control.
6. **The companion's Sky page** gains "Sky quality: Standard / Enhanced", off by default, and a detail level. (At
   the merge the user made Enhanced the default; see Status.)
   - In Enhanced it maps its weathers, clock, Moon, wind and fog onto the library's settings. The values are a data
     table (`enhanced_weather.lua`).
   - In Standard it sends exactly what it sent before.
7. **In Enhanced the library's haze replaces Remix volumetrics.** The companion turns volumetrics off on entry and
   puts the recorded value back on leaving.
8. **While a VR session runs, mode 2 renders as mode 1.**
9. **The package carries the library's files** beside `d3d9.dll`, in a `numos` folder: its 41 compiled passes, the
   night sky data with its credits, and `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md` and `licenses/`.

## Consequences

- **Two skies to carry.** Ours to maintain: the adapter patch, the prefix step, and the companion's mapping. A new
  pin means checking those three.
- **Size.** `d3d9.dll` grows from 510.3 to 532.8 MB, and the package by 44 MiB.
- **A different night in Enhanced.** The library draws its own Moon and stars. Our night sky editor, sun dogs and
  arcs, the solar eclipse's corona, shooting stars and the sky without a horizon stay with Standard.
- **Lamp glow and fog change in Enhanced,** since the haze replaces Remix volumetrics there.
- **The notices we ship name the library's author and the authors of the original atmosphere code.** Our runtime
  carries that original code already.
- **Not in this round:** rays across the far sky beyond the haze's range, rain shafts and a rainbow. The library
  has none of the three.

## Evidence

In [the round's report](../handover/sky-enhanced-report.md): the PoC comparisons of Standard before and after, the
four judged scenes in Enhanced with their frame times, and what is still wrong.

## Open, for the user

1. Whether Enhanced may ship with a different night sky, or stays a daylight choice until ours is rebuilt on it.
2. Whether to add the credit line the library's README asks for, beyond the notices its licence requires.
3. Whether the library's own menu is wanted at all.
4. Whether rays across the far sky, rain shafts and a rainbow are built next, on top of the library's shadow map.

The user's answers at the merge (2026-11-26):

- **The default:** "Merge both rounds and publish the Enhanced sky as the default choice, on by default, with
  Standard unchanged." `nativeloader_sky_enhanced` defaults to 1. Standard is one choice away, and VR still shows it.
- **1, the night:** "Yes, and open this for later, we should adapt our own night sky with the enhanced night."
  Enhanced ships with the library's own night; bringing our night sky to it is an open item on the roadmap.
- **2, the credit line:** "Yes, please update the credit lines." The line the library's README asks for, "Sky and
  clouds: NUMOS by Kim2091 (Sparkles)", is in the repository's README and the Remix menu's About panel. Not on the
  Workshop page: the user has no item's page edited, since an edit sends the item to Steam's review.
- **3, the menu:** "yes please add and translate the NUMOS sky's remix men[u]." The library's pages come into the
  Remix menu, translated into the six languages (round 2's task M, runtime patch 0114). Their edits land on the layer
  the companion writes, so the companion's next change of weather or look sets them again; no menu control writes a
  file into the game folder (decision 4 holds).
- **4:** round 2 built the rays and the rainbow
  ([ADR 0268](0268-the-enhanced-sky-gets-sun-rays-an-editor-and-mist-choices.md)); rain shafts are not built.
