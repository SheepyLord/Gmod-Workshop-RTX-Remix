# The Enhanced sky below the horizon: report (2026-11-27)

The user, after the Enhanced night was published: "Nice work. Please improve the look of the horizon and fix the
no-horizon mode for the enhanced sky mode. Currently the horizon looks a bit off." Their screenshot showed a map whose
floor ends: beyond it, below the horizon, one flat pale wall of fog under a straight line, the clouds stopping above
it. [ADR 0272](../decisions/0272-the-enhanced-sky-below-the-horizon.md).

Plan and briefs: [sky-enhanced-horizon-plan.md](sky-enhanced-horizon-plan.md). Coded by Codex in two tasks, reviewed
and tested here: HR (runtime patches 0118 and 0119, the companion's checkbox) and HR2 (patch 0120), both in
[sky-enhanced-HR-report.md](sky-enhanced-HR-report.md).

## What was wrong

- **The fog wall.** The library's haze for a camera ray that left the map counted the height fog from the near
  field's range to 2000 km. Below the fog's base its density grows (clamped only ten scale heights down), so for every
  ray below the horizon the column never ended and the pixel was the fog's own flat colour: grey at noon,
  orange-brown with a low sun, black at night, under a perfectly straight line. What the library draws there itself,
  the air in front of a lit ground with the clouds' shadows, was hidden by it.
- **No horizon** did nothing in Enhanced: no part of the Enhanced path read the option, and the companion greyed the
  checkbox out there and dropped the setting.

## What changed

- **The ground below the horizon** (patch 0118): a ray below the planet's limb, from the camera or a mirror, ends on
  the library's ground at the sky's ground level, lit by the Sun, the Moons and the sky with the clouds' shadow, and
  the haze ends there. A pixel across the limb is antialiased. With the haze off nothing changes.
- **Patch 0120**, after the first PoC test: the clouds' shadow on that ground is looked up where the ground really is
  (0119 intersected a second sphere at the clouds' eye height, which a moved cloud deck could miss), and near the limb,
  where one traced pixel spans several shadow texels, the direct light is held to the shadow under the ray's origin,
  so sunlit gaps in a deck no longer draw a bright strip along the horizon. A mirror's ray that leaves below the
  horizon is shaded at once from the library's far air and fog: the 32 bytes per pixel that 0118 kept for it
  (63 to 253 MiB at 3840x2160) are gone.
- **No horizon in Enhanced** (patch 0119), as ADR 0139 has it in Standard: below eye level the mirror's air with the
  true angle to the Sun and the Moons (a host bake of 512 by 128 texels that reproduces the library's own table bit
  for bit above the horizon), the clouds of the opposite side from a second library renderer looking the other way
  (point-reflected camera, the main renderer's wind, evolution, clock and measured ground each frame), the mirror's
  far haze, the night sky image, the stars, shooting stars and the Moons lit in every direction; the Sun still sets.
  Both decks fade into the horizon's air over the last half degree. Off, none of it exists.
- **The companion** sends No horizon in both skies and keeps its checkbox enabled in Enhanced.

## In the PoC

gm_flatgrass, 3840x2160 with DLSS. Scenes `out/sky2/capture/horizon-edge.json`, `horizon-edge2.json` (from the air
near the map's edge, R26's place (12500, 0, 14000), about 510 m above the floor), `horizon-flooredge.json` (from the
floor; its trace fell back to the spawn, so it looks over the floor's far edge from about 11 m above the grass plane)
and `horizon-ft.json` (frame times). Runs in `<repo>/out/sky2`: `HZ1-*` the published package, `HZ2-*` patch 0118,
`HZ3-*` 0118 and 0119, `HZ4-*` 0118 to 0120. Crops and sheets in `out/sky2/judged/horizon/`.

- **From the air, No horizon off:** below the horizon a lit plain with the clouds' shadows fades into the haze, at noon
  and with the Sun 8 degrees up; at night a dark moonlit plain under the sky image. The fog wall is gone.
- **From the floor:** the ground past the map's edge meets the sky in the haze. With 0118 and 0119 an overcast sky
  showed a bright strip there (sRGB luminance 165 to 183 under a sky of 148); with 0120 the sky's 143 falls smoothly to
  the ground's 103.
- **No horizon in Enhanced:** detailed clouds below the map at noon, an overcast below, one aureole round a low Sun
  with the warm band at eye level, the night image all the way down, and no seam at eye level in any of them.
- **Standard** is unchanged: its pictures differ from the published package's only where clouds drift.
- **Frame time** (`HZ4-ft`, one launch, medians in ms, Enhanced off and on twice in interleaved order):

  | View | Enhanced | Enhanced, No horizon | Standard | Standard, No horizon |
  |---|---|---|---|---|
  | Level | 8.28, 9.67 | 10.51, 10.63 | 8.77 | 10.30 |
  | 15 degrees down | 7.96, 8.79 | 10.51, 10.53 | 8.61 | 10.28 |
  | 50 degrees down | 4.70, 4.83 | 7.10, 7.40 | 5.42 | 6.81 |

  No horizon costs Enhanced 1.6 to 2.5 ms (Standard 1.4 to 1.7 ms). The ground below the horizon with No horizon off
  costs nothing measurable. Codex measured the second renderer's video memory headlessly: 488 MiB at DLSS Quality,
  356 MiB at Performance, freed when No horizon goes off.

## Not checked

- The field game; a Radeon card; VR (it keeps Standard).
- A mirror or water facing the void in the game (Codex checked the path headlessly).
- The speckled haze on the distant walls of the user's screenshot: not seen on gm_flatgrass. That map's name would
  let it be tested.
- A floating island's underside: with No horizon on, the library's near field still holds its dense fog below the
  ground level (ADR 0272's limits).

## State

- Branch `sky-enhanced-4`: the plan, HR and HR2 merged; the runtime stored (`d3d9.dll` `cf41a48e`, built from fork
  `1b6b6ea99` with patches 0001-0120).
