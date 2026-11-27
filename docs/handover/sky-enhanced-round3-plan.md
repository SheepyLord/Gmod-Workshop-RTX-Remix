# The Enhanced sky: fixes after the merge (round 3)

The Enhanced sky became the default sky on 2026-11-26 (`main` `5ebe20c7`, published as
`0.0.0-dev.20261127020943+3057e537`). The same evening the user reported, with a screenshot of the sun:

> 2. The sun has a black circle around it if not covered by cloud.
> 3. The mist is way too strong by default and there lacks a way to disable it.

(Point 1 of the same message, our night sky on the Enhanced sky, is a design for the user's decision first:
[sky-enhanced-night-plan.md](sky-enhanced-night-plan.md). No code for it in this round.)

Branch `sky-enhanced-3`, from `main` at `3d661b8f`. Two Codex tasks, S (the runtime) and H (the companion), then
Claude's tests in the PoC. Round 2's "Rules for both tasks" ([sky-enhanced-round2-plan.md](sky-enhanced-round2-plan.md))
hold, with one change: the runtime is stored by Claude after the tests, as before.

## Task S: no dark ring round the Sun or the Moon

**What players see.** In Enhanced, wherever no cloud covers the Sun, a broken black circle lines the disc's edge. The
PoC shows it in every Enhanced capture of the sun since round 1 (`out/sky2/D1-default`, `out/sky2/MR1-mist-ring`):
pixels at 0-6 of 255 in a ring of pixels at 250; Standard has none.

**The upscaler does it.** `out/sky2/MR2-mist-ring`, the sun at 60 degrees through a 10 degree view: with DLSS
(`r1_dlss_disc.png`) a dashed black circle lines the disc; with no upscaler (`r2_noupscaler_disc.png`) the same frame
has none; Standard (`r3_standard_disc.png`) has none. The full moon at midnight with DLSS (`r4_moon_disc.png`) shows a
few dark specks inside its upper left edge, none without an upscaler (`r5_moon_noupscaler_disc.png`).

**Why.** Camera rays get the library's disks through `numosSkyDisks` (`compositePrimarySky`,
`src/dxvk/shaders/rtx/pass/composite/composite_sky.slangh`). The library draws the Sun's disc at its physical
radiance (capped only at 6e4 in its own scale) with a rim one traced pixel wide (`evalSkyDisksYUp`,
`rimWidth = max(args.skyPixelAngle, 0.02 sin r)`, `submodules/numos/shaders/numos/lib/atmosphere_sky.slangh`). The
upscaler (DLSS, the PoC's and most players') rings on a one-pixel step of that contrast into black pixels. Standard
met the same in R17 and draws its disc with the centre held at 48 times the daylight and edges two pixels wide
(`evalSunDisc` and `evalSolarEclipse`, `src/dxvk/shaders/rtx/pass/atmosphere/atmosphere_sky.slangh`, and their
comments). The library's Moon disc has the same one-pixel rim (`evalMoonDisk`), against a night sky.

**What to build** (one patch, 0115, on the fork branch `claude/sky-enhanced`; the library stays unmodified):

1. Camera rays in Enhanced get discs whose edges do not ring. Suggested: call the library's disk evaluation with a
   copy of the arguments used for the disks only:
   - `skyPixelAngle` doubled, so each rim is two pixels wide;
   - the Sun's illuminance scaled so the disc's centre is at most 48 times the daylight (the brightest channel of
     `sunIlluminance`), keeping its colour, as Standard's `kSunDiscPeak`;
   - each moon held the same way against its own illuminance if its edge rings at night (check it: a full moon at
     midnight and a crescent at dusk).
   The air, the clouds, the lights and every other use of the arguments keep the real values. If the library's
   functions cannot be used this way, draw the Sun's disc in the host as Standard's `evalSunDisc` does, behind the
   library's moons (their coverage), and say why.
2. Mirror reflections (`geometry_resolver.slangh`, the PSR miss with `NUMOS_SKY_DISKS_ALL`) get the same disc, still
   behind the clouds as now (the library covers non-primary disks with its cloud dome LUT).
3. Unchanged: the disc behind thin cloud (dimmed by the cloud, as now), reddened at the horizon, behind a moon in an
   eclipse; the aureole round it; the sun rays and the rainbow; Standard (modes 0 and 1) has no diff.

**Checks.** Compile the changed shaders alone with the pinned Slang compiler, then `runtime\build_runtime.ps1
-NoImport -Install`. If the repository has a unit test of the disc's numbers (centre, rim, cap), extend it.

**Deliver.** The fork commit; in your worktree the patch, `runtime/base.json` (`pending_patches`), the section in
`runtime/README.md`, a CHANGELOG line for players, and `docs/handover/sky-enhanced-S-report.md`: what changed and why,
the numbers (the cap, the rim) and where they come from, what Claude should look at first in the game, what you built
and tested with the commands and their output, and what you could not do.

## Task H: a Mist setting that goes to Off, and less mist by default

**What players see.** In the default weather (partly cloudy) the Enhanced sky is milky white toward the horizon and
grey round the sun, and the map has a veil. The only mist control, "Mist on the map", chooses how the mist is drawn
(Enhanced mist, or Remix fog near you), not whether. PoC: `out/sky2/MR1-mist-ring` and `MR2-mist-ring`, gm_construct
at noon.

**Why.** Round 2 gave partly cloudy ten times the library's aerosol at a fifth of its absorption (a milky haze, for the
sun's glow and the rays; `enhanced_weather.lua`). The haze lies over the whole sky and, through the library's aerial
perspective, over the map.

**What to build** (companion only, `companion/nativeloader/lua`):

1. **Mist** (a style setting, so it holds in every weather and look): a slider from 0 to 2, default 1, on the Enhanced
   sky editor's "Light and mist" group, first in it, and on the Sky page under the Enhanced sky's own controls while
   Enhanced is chosen. It scales the mist of whatever weather or look is on screen before the companion sends it:
   - the aerosol above clean air: `aerosolDensity' = min(a, 1.1) + max(a - 1.1, 0) * s` (1.1 is the library's own
     clean air);
   - the height fog's extinction: `fogVisibilityMeters' = v / s` (`0`, no fog, at `s = 0` or when `v` is 0);
   - at `s = 0` nothing of the mist is drawn on the map either: `aerialPerspective` False.
   A fog the player chose on the Fog page (the Remix fog presets, `presetFog`) is theirs and is not scaled; the help
   line says so. Blends between weathers scale each step the same way.
2. **Mist on the map** gains a third choice, **Off**: no Enhanced mist on the map (`aerialPerspective` False) and no
   Remix fog near you; the sky keeps its haze. The runtime option `rtx.atmosphere.numos.volumetrics` has its own 2,
   which is not this: map the choice onto the runtime's options instead of sending it as it is, and keep saved values 0
   and 1 meaning what they mean today.
3. `E.pushSky` sends `aerialPerspective` from these two settings instead of always True (`mode.common`).
4. The weathers' numbers are Claude's: change `enhanced_weather.lua` only where this brief's section "The new default"
   says.
5. Texts in English and the six catalogs; tests in `tools/tests/test_companion_sky.py` (strength 0, 1 and 2 on a
   weather and on a blend, Off, a saved 0 or 1 unchanged, a Fog page preset left alone, the Sky page's slider and the
   editor's being one setting); the `.md` beside each changed script; a CHANGELOG line for players.

**Deliver.** Commits on your branch and `docs/handover/sky-enhanced-H-report.md`: each setting with its console
variable, range and default; what is sent at 0, 1 and 2 and with Off; the tests and their output; what Claude must
check in the game.

### The new default

Measured in the PoC (`out/sky2/MR2-mist-ring`, gm_construct, partly cloudy, noon): the sky's mean colour saturation
was 0.11-0.13 at today's default (haze 10 at a fifth of the library's absorption), 0.16-0.21 at haze 3, 0.18-0.26 at
haze 2 (both at the library's absorption) and 0.27-0.36 with no mist at all. Haze 2 keeps a warm glow round a low sun
(`h_low_haze2_sun.png`) and gives most of the blue back.

- `partlyCloudy`: `aerosolDensity` 10 -> **2**, `mieAbsorption` -> the library's own (`defaults.mieAbsorption`,
  0.0044 a kilometre). Its other numbers stay.
- Every other weather keeps its numbers: Hazy and Smoggy are meant to be hazy, Foggy foggy, and the rest already use
  the library's clean air or kilometres of visibility.
- Update the comment above `partlyCloudy` with the reason (the user's report; the numbers above).
