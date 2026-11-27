# The Enhanced sky, round 3: the user's report after the merge (2026-11-26)

The Enhanced sky became the default sky on 2026-11-26 (`main` `5ebe20c7`). The same evening the user sent a
screenshot of the sun and three points:

> 1. Our night sky on the Enhanced sky. Plan how our own night sky could be integrated into the Enhanced sky, and show
>    the user the design before any code.
> 2. The sun has a black circle around it if not covered by cloud.
> 3. The mist is way too strong by default and there lacks a way to disable it.

Point 1 is a design, [sky-enhanced-night-plan.md](sky-enhanced-night-plan.md), which the user approved as recommended
("Yes, as recommended"); its tasks NR and NC follow this round. This report is points 2 and 3: plan
[sky-enhanced-round3-plan.md](sky-enhanced-round3-plan.md), tasks S (runtime, [report](sky-enhanced-S-report.md)) and
H (companion, [report](sky-enhanced-H-report.md)), both coded by Codex, reviewed and tested here.
[ADR 0270](../decisions/0270-the-enhanced-sky-draws-its-own-discs-and-has-a-mist-setting.md).

## The black circle round the Sun

**Found.** Every Enhanced picture of the sun the PoC had taken since round 1 has it; we missed it because those
pictures blow the sun out to white. Through a 10 degree view of the sun at 60 degrees (`out/sky2/MR2-mist-ring`):

| Picture | Pixels at 0-6 of 255 at the disc's edge |
|---|---|
| Enhanced, DLSS (published) | 138, a dashed circle |
| Enhanced, no upscaler | 0 |
| Standard, DLSS | 0 |
| Full moon at midnight, Enhanced, DLSS | 6 specks inside the upper left edge |

**Why.** The library draws the Sun at its physical radiance (capped only at 6e4 in its own scale) with a rim one traced
pixel wide, and DLSS rings on that step into black pixels. Standard met the same in R17 (`evalSunDisc`: the centre at
most 48 times the daylight, two-pixel edges). The library's Moon has the same one-pixel rim.

**Fixed** in runtime patch 0115 (task S): the runtime draws the discs for camera rays and mirror reflections itself,
the library unmodified. Edges two traced pixels wide; the Sun's centre the lesser of its physical value and 48 times
its illuminance; each Moon shaded by the library and held against its own light. Diffuse and glossy gathers, lights,
LUTs, aureoles, sun rays and the rainbow keep the library's own arguments.

**In the PoC** (`out/sky2/R3V-check`, the branch's package with 0115, DLSS on): 0 dark pixels at the Sun's edge
(was 138) and 0 at the full Moon's (was 6). The disc is a clean white circle in a soft glow; the moon's edge is crisp.
Sheet: `out/sky2/judged/round3/sun-ring-fixed.jpg`.

## The mist

**Found.** Round 2 gave partly cloudy, the default weather, ten times the library's aerosol at a fifth of its
absorption: a milky haze, for the sun's glow and the rays. In the PoC (gm_construct, noon, `out/sky2/MR1-mist-ring` and
`MR2-mist-ring`) the sky's mean colour saturation was 0.11-0.13 at that default, 0.16-0.21 at haze 3 and 0.18-0.26 at
haze 2 (both at the library's absorption), 0.27-0.36 with no mist. Haze 2 keeps a warm glow round a low sun. The only
mist control, Mist on the map, chose how the mist is drawn, not whether.

**Fixed** in the companion (task H):

- **Mist**, 0 to 2, default 1, on the Sky and weather page (while Enhanced is chosen, desktop only) and in the Enhanced
  sky editor's Light and mist, one setting (`nativeloader_sky_style_mist_strength`). It scales the haze above clean
  air (aerosol density 1.1) and the height fog's extinction of whatever weather or look is on screen; at 0 nothing of
  the mist is drawn on the map either. A fog preset chosen in the Remix settings keeps its own strength.
- **Mist on the map: Off** (saved value 2 of `nativeloader_sky_style_volumetrics`): the library's aerial perspective
  off and Remix fog paused; the sky keeps its haze. 0 and 1 mean what they meant.
- **Partly cloudy**: aerosol density 10 at a fifth of the absorption became 2 at the library's own.

**In the PoC** (`out/sky2/R3V-check`): the new default's sky is clearly bluer toward the sun and across the map; Mist 0
clears it to a deep blue with crisp clouds; Mist 2 brings a light haze back; Mist on the map Off leaves the far
buildings crisp under the same sky. Sheet: `out/sky2/judged/round3/mist-new.jpg`.

## Not checked

- The field game: the user's game ran the published package; the fixes were seen only in the PoC.
- Water and mirrors at a low sun in the game (task S checked the reflection path offline on the GPU against the
  library's own evaluation), a crescent at dusk, an eclipse.
- Frame time: the runtime's night task was building on the same machine during the PoC runs. The change is a few
  instructions per sky pixel.

## Seen in passing

On gm_construct a view steeply up shows the map's 3D skybox models as dark outlines high in the sky, in both skies
(`out/sky2/MR2-mist-ring/r1_dlss_up.png`, also round 2's night pictures). Not part of these fixes.

## State

- Branch `sky-enhanced-3`: the plan, the night design, tasks S and H merged, the runtime stored
  (`d3d9.dll` `0362625c`, built from fork `48e9ae0b4` with patches 0001-0115).
