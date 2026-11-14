# The Moon by day: report (2026-11-14)

The user's request: "Enhance the skybox about the moon, the moon should be visible during the day given correct moon
phase." A QoL task from the coordinating session. Done by Claude on the branch `qol-moon` (worktree
`out\worktrees\q-moon`, from `main` at `bfbe2350`); package only: runtime patch 0090 and the companion, no loader
(`winmm.dll`) change. Not merged, nothing published, no game launched.
[ADR 0207](../decisions/0207-the-moon-by-day.md); facts in [RESEARCH.md](../RESEARCH.md) ("The Moon by day").

## What hid the Moon

The companion already placed the Moon by its phase (`sky_model.lua`: `phase` of a turn east of the sun), so a first
quarter stood high in the afternoon sky. The runtime's `evalSkyRadiance` drew the moons "only visible at night": the
disc's coverage was multiplied by `smoothstep(0, -0.09, sun.y)` (zero with the sun up), and the disc then replaced the
background where it covered.

## What changed

**Runtime patch 0090** (`Atmosphere: the Moon by day`, fork branch `claude/moon-by-day` at `aea5d31e` on `vr2`'s
`1097d701`):

- **The composite.** A moon's light (already dimmed by the air, `moonAirTrans`) is added to the sky's in-scatter in front
  of it; its coverage hides only what lies beyond it: the stars and the night sky image, the airglow layer and the halos
  (`beyondMoons`), earlier moons, the everyday sun disc. With the in-scatter faded out at night (sun 16 degrees down) this
  equals the old replace exactly; from 5 degrees down the twilight's in-scatter over the disc is under 1 % of its light.
- **The day's light.** By day each moon's light follows the real Moon's phase law: `rtx_moon_daylight.h` computes the real
  law (Allen) over the drawn Lunar-Lambert one, held from 150 degrees: 1 full, 0.40 gibbous, 0.25 quarter, 0.15
  crescent, 0.107 new; times the new `rtx.atmosphere.daytimeMoonBrightness` (default 1, 0-4, 0 = no moon by day). It
  reaches the shader as `moonDaytimeScale0-3`, one new 16-byte row of `AtmosphereArgs`, zeroed in the LUT cache key. The
  old fade band (sun 0 to 5.16 degrees down) now hands it over to 1, the night's look.
- **The horizon.** A disc is cut at the horizon (two pixels soft) unless `rtx.atmosphere.noHorizon`: a moon below it
  showed through the ground's haze, day or night.
- **Night-only, unchanged:** the halo, the clouds' moonlight, the Moon's ground light (the companion's
  `surfaceMoonBrightness` fade). **Eclipses:** `evalSolarEclipse` and its `moonMask`, the handover of the everyday sun
  disc and the lunar eclipse are unchanged; the everyday sun disc is now covered by a moon in front of it (only possible
  with eclipses off).
- The Remix menu: Daytime Brightness under Moons, Global Lighting; both new texts translated in the six catalogs;
  `RtxOptions.md`; `tests/rtx/unit/test_moon_daylight.cpp` (registered in the unit tests' `meson.build`).
- Exported alone (`format-patch -1 --start-number 90 --zero-commit`), built and imported by `build_runtime.ps1`:
  `d3d9.dll` **418,989,056 bytes, SHA-256 `fb0e2b21d057a76ee0572c57d5e33311a94e048ed5c54758102a61b6ec5b2ee0`**
  (61,729,712 bytes xz in Git LFS), `base.json`'s `packaged` record and [runtime/README.md](../../runtime/README.md).
  On the same branch the crash fixes (patches 0091 and 0092, [crash-0xc0000005-report.md](crash-0xc0000005-report.md))
  were then built with it, and that 0001-0092 build replaced this import: `d3d9.dll` SHA-256
  `e242dfdb08486fd97012e3af89b2955fc4f9a11e992902e383cbb844cc857531`.

**The companion** ([`nativeloader_sky.lua`](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md)): **Moon by
day** (`nativeloader_sky_moon_day`, 1, held to 0-4), a slider under Moon in the Sky and weather panel, sends the option
with the sky; its help line says what 1 and 0 mean; the status line names it; the reset puts it back. Both texts
translated in the six catalogs (agent-written, noted in [companion/i18n/README.md](../../companion/i18n/README.md)).

## Why a daytime factor, and why 1

The drawn Moon's full face matches a real full Moon (0.035 against 0.038 of the sun's illuminance per steradian), but
its partial phases are far too bright: a quarter gives 37 % of full where the real Moon gives 9 %, a crescent 13 % where
the real gives 1.9 %. At night the disc reads near white either way; by day, against the runtime's own sky
(rebuilt offline by [`tools/sky/moon_daylight.py`](../../tools/sky/moon_daylight.py.md)), it made partial phases 0.4 to
5 times brighter than the sky around them. With the real law by day the Moon shows 9 to 69 % brighter than the sky
around it with the sun above 10 degrees (crescents 9-31 %, quarters 9-69 %, gibbous 16-60 %), within 0-15 % of a real
Moon, and nearly vanishes in the horizon's haze or near the sun. 10 % is five times what the eye needs on an even field,
so the default is the physical 1; the slider raises it for a bolder Moon. No constant factor could stand in for the
phase law (the table and the alternatives are in ADR 0207).

## Tests

- `tools\test.ps1 -Config Release`: passes ("All checks passed"): repo conventions, 35 of 35 CTests, the `tools` Python
  tests 1,903 (2 skipped), `gmapack` 29 and `steam` 26 (1 skipped each).
- [`test_moon_daylight.py`](../../tools/tests/test_moon_daylight.py.md): the phase-law unit test compiled from patch 0090
  with MSVC and run (1,520 checks: the closed forms against a brute-force disc sum, the companion's phases, monotonic,
  symmetric); the composite, option, arguments, `RtxOptions.md` and catalogs in the patch; the estimate's sky and
  contrast.
- [`test_companion_sky.py`](../../tools/tests/test_companion_sky.py.md): the moon by day goes to Remix (1 at the start,
  the slider's value held to 0-4, the map's sun still followed, the status line, the reset).
- The runtime build itself: the tree verified against the base and the patches, every sky shader compiled again,
  `test_moon_daylight.exe` from the build passes; `i18n/tools/embed.py` 3,360 of 3,360 messages in each language (glyphs
  checked), `update_strings.py --check`, `test_embed.py`.

## In-game checks still needed

No game was launched (the task's rule). The checks are listed in [TESTING.md](../TESTING.md) ("The Moon by day"): the
Moon at noon (a waxing crescent faint in the east; a full Moon below the horizon, nothing in the haze), an afternoon first
quarter (a pale half disc, the blue through its dark half, behind clouds, in reflections), dusk (a smooth brightening, no
step, the night's look from the sun's 5 degrees down), night (unchanged), both eclipses (unchanged; no lit disc on the
sun), the sky without a horizon (a moon below it drawn; without it, none), and the slider at 0 and 4 and the Remix menu
entry.

## Open

- **The tone mapper.** The estimate compares linear luminances; how pale the Moon reads on screen after auto exposure and
  the tone curve is for the in-game look. If it reads too faint, the default could be raised (the slider shows how far).
- **The multiple-scattering LUT's bottom row** samples exactly on the ground and holds nothing (or only the ground's
  bounce, if the GPU fuses the subtraction): the day sky is 6-11 % darker than its physics in the estimate. Found on the
  way, not changed (it would change every sky); RESEARCH.md has the analysis.
- A second runtime job arrived after this report's build: the 0xC0000005 fixes, patches 0091 and 0092. The imported DLL
  now holds 0001-0092 ([crash-0xc0000005-report.md](crash-0xc0000005-report.md)).
