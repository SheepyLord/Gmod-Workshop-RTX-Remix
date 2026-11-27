# The Enhanced sky: the plan for round 2

The user saw [round 1](sky-enhanced-report.md) on 2026-11-26 and answered: "Yes, please start round 2 and add more
customization of the sky and cloud, not limited to presets. Codex agents can be ran in fast mode."

This file is the plan for the second round and the brief for its two coding tasks. Round 1's
[plan](sky-enhanced-plan.md) still holds where this file does not say otherwise: what the user decided, the contract
table, and its "Rules for both tasks".

`<repo>` below is the main checkout. Research notes and the library's clone are in its scratch folder
`<repo>/out/sky2` (not tracked).

## What round 2 delivers

1. **Sun rays across the sky.** Round 1 showed none through cloud gaps, at any haze range.
2. **A sky the player shapes freely.** An editor for the Enhanced sky: clouds, the upper layers, the air, fog, light
   and rays, each on its own control, with looks kept by name. The twelve weathers stay as starting points.
3. **Mist that works with lamps.** Remix volumetrics pause by themselves in Enhanced, and the player can choose Remix
   fog near the camera with the library's haze beyond it.
4. **A rainbow,** when the sun lights rain.
5. **Round 1's known problems** that belong to code: the night's gain and the lamps' switch sent with the mode, the
   volumetrics restore, one more device object left at exit.
6. **Each weather's look,** tuned in the game by Claude: storms, hazy and smoggy, the cold cast, the lamps' cost.

Not in this round: rain shafts, our night sky editor's layers in Enhanced, VR, a field test (the field game is on
Steam's main branch, where the loader does not start yet).

## The contract between the tasks, added to round 1's

Both tasks code against these names. Change one only by telling Claude in your report. Every key is under
`rtx.atmosphere.numos.`, so `RemixConfig` takes it without a change of the fixes' module.

| Key | Type and default | Meaning |
|---|---|---|
| `rays.enable` | bool, True | The sky ray pass runs in mode 2 |
| `rays.strength` | float 0 to 4, 1 | 1 is physical. It scales what the clouds' shadow takes from the air's light; 0 shows the sky as round 1 did |
| `rays.quality` | int, -1 | -1 follows `qualityLevel`; 0 High, 1 Medium, 2 Low, in the library's order |
| `rays.debugView` | int, 0 | 0 off. Views for the review, listed in task R2 |
| `rainbow.strength` | float 0 to 4, 0 | How much rain is in the sunlit air. 0 draws nothing. The companion sets it from the weather |
| `volumetrics` | int, 0 | What Remix volumetrics do in mode 2. 0: paused, the library's haze and fog run. 1: Remix volumetrics near the camera, the library's haze and fog beyond their range. 2: round 1's rule: while `rtx.volumetrics.enable` is on they replace the haze and the fog |

In every value of `volumetrics` the runtime writes no option. `rtx.volumetrics.enable` keeps the player's value, and
in modes 0 and 1 it means what it means today.

## Task R2: the runtime

**Goal.** In mode 2 the sun's rays show where clouds shade the air, Remix volumetrics follow the new option, and a
rainbow can be drawn. With `rtx.skyMode` 0 or 1 the runtime renders and costs exactly what it does at patch 0108.

**Where.** As in round 1's task R:

- Code: the live runtime worktree `<repo>/out/worktrees/r17/out/runtime-src`, on the fork branch
  `claude/sky-enhanced`, now at `1370af0d2` (patch 0108) with its finished Release build. Read that tree's own
  `CLAUDE.md` again.
- Patches and records: this repository, in the worktree `<repo>/out/worktrees/sky2r` on branch `sky-enhanced-r`,
  which now holds the whole of round 1 (it was moved up to the round's branch).

One fork commit and one runtime patch for each part below, from 0109 on, in this order. A part that is not finished
is left out whole: its commit is not made.

### Part 1: sun rays across the sky (patch 0109)

**What round 1 showed.** A sky pixel takes the library's near haze up to its range (1 km, or 6 km under a cloud
sheet), then the sky-view table, which knows no clouds. So no shaft shows through a gap in the clouds, with any range
and with three times the aerosol. The library's cloud shadow map reaches the horizon, and its host header gives the
clouds' transmittance toward the sun at a point.

**What to build.** A pass of ours on the host side. For a sky pixel it integrates the sunlight the air scatters
toward the camera along the view ray, once with the clouds' shadow and once without, and the composite's Enhanced
variant adds the difference to the sky. The library stays unmodified.

**It must hold:**

1. **Physical at strength 1.** Use the library's own air: its scattering and extinction at each point (Rayleigh, the
   aerosol, the height fog), the sun's light arriving at that point through the air, its phase functions, its units.
   Call its host functions; do not copy constants out of it. At strength 1 the pass only removes light.
2. **No shadow counted twice.** The library already shades the air in its near haze, within that haze's range, and
   the air in front of a cloud on the screen. Read how it does both. Then either leave those spans to it or correct
   them, so that the sum is your shadowed integral. Say in the report which you did and why.
3. **Where it shows.** Open sky between clouds and below a cloud deck toward the horizon; the sky seen through thin
   cloud, by the cloud's own transmittance; the air in front of far clouds. Surfaces need nothing: the library's far
   table already has the shadow.
4. **Camera rays only.** Reflections and other secondary rays keep round 1's sky.
5. **Steady.** No bands in a still view, no crawl or flicker when the camera turns, no smear while the clouds
   drift, no light leaking over a roof's or a tree's edge. March with a jittered start; keep a history, reprojected
   as the far sky moves; filter; and fill up from a reduced resolution with the scene's depth in mind. It runs
   before upscaling, on the jittered render resolution, and must be right under DLSS, DLSS Ray Reconstruction and
   frame generation.
6. **Cheap.** At a 1920x1080 render resolution on an RTX 5090: 0.5 ms at High at most, less at Medium and Low. No
   dispatch at all when the mode is not 2, when `rays.enable` is off, when the strength is 0, when no cloud can
   shade the air (no cloud layer and no cirrus), or when the sun is too far below the horizon to light the air.
7. **The Moon** may be left out: the sun's rays only.

**Options.** The contract's four keys. Add what the pass needs beside them (range, step counts, the history's
weight), documented in the option reference. `rays.debugView`:

- 1: the ray term alone, as a positive brightness;
- 2: the unshadowed light of the same span;
- 3: the share of the span in shadow;
- 4: where the march starts and ends.

**Tests.** The runtime's unit suite, with new tests for what needs no GPU: the option mapping, the skip conditions,
the quality levels.

### Part 2: what Remix volumetrics do in Enhanced (patch 0110)

Round 1's companion turned `rtx.volumetrics.enable` off in Enhanced and put the recorded value back afterwards. It
cannot read a value changed only in the Remix menu. The runtime decides now, and nobody writes the option.

- `volumetrics` 0, the default: in mode 2 Remix volumetrics do not run and do not composite, as if they were off, and
  the library's haze and fog run. Every place on the frame path that asks whether volumetrics are on must agree.
- `volumetrics` 1: Remix volumetrics run as in mode 1 while `rtx.volumetrics.enable` is on, and the library's haze
  and fog start where their range ends. The library has an input for it: `FrameInputs::volumetricsHandoffWorldUnits`
  (`include/numos/renderer.h`, and `docs/aerial-perspective-v2.md`). Read how the library uses it. The air must not
  be counted twice inside the range or left out beyond it. With `rtx.volumetrics.enable` off this is value 0.
- `volumetrics` 2: round 1's rule, unchanged.
- Leaving mode 2, or changing the option, gives Remix volumetrics a clean start: no flash of an old history.
- Unit tests for the decision, with VR on and off (in VR mode 2 is mode 1).

### Part 3: a rainbow (patch 0111)

Start it only when parts 1 and 2 are built, tested and committed.

- Drawn in the composite's Enhanced variant when `rainbow.strength` is above 0: the primary bow at 42 degrees from
  the point opposite the sun, red outside; the secondary at about 51 degrees, fainter and reversed; the sky darker
  between them and a little brighter inside the primary.
- Its light is the sun's as it arrives at the ground at that moment, so a low sun gives a red bow. Take it from the
  library, not from a constant.
- It shows only where the sun lights the rain: use the clouds' shadow at a few points along the view ray, at the
  distance where the rain is. A bow under a broken sky is a broken bow.
- Over the sky, and over surfaces far enough for rain to hang in front of them. Nothing in front of near surfaces.
- No bow when the sun is higher than the bow's radius.
- No new data file: compute the colours.
- Options beside the contract's key as needed, such as the rain's distance and depth.

### Part 4, if time is left: the device object at exit (patch 0112)

At exit the runtime reports 52 device objects not disposed of, against 51 at patch 0106. Find the one the Enhanced
sky leaves, and release it.

### Deliver

- The fork branch with your commits, and the built tree: `runtime\build_runtime.ps1 -NoImport -Install` passes, as
  in round 1.
- In `sky2r`: the patches, `runtime/base.json` (`pending_patches`), the option reference regenerated, the section
  in `runtime/README.md`, a CHANGELOG line for each part, and your report,
  `docs/handover/sky-enhanced-R2-report.md`:
  - how the ray pass works: the march, where it starts and ends, the history, the fill;
  - how no shadow is counted twice;
  - every new option key, with its default;
  - what Claude should look at first in the game for each part, and with which debug view;
  - the cost you expect, and why;
  - what you built and tested, with the commands and their output;
  - what you could not do.

## Task E: the companion's sky editor

**Goal.** In Enhanced the player shapes the sky freely and keeps looks by name, and the companion's part of round 1's
known problems is fixed. With Sky quality at Standard the companion still sends exactly what it sends today.

**Where.** This repository, in the worktree `<repo>/out/worktrees/sky2c` on branch `sky-enhanced-c`, which now holds
the whole of round 1. No runtime build is needed: code against both contracts and the library's settings
(`<repo>/out/sky2/scratch/list_settings.py <repo>/out/sky2/scratch/numos-sky/include/numos/settings_fields.inl
--desc <pattern>` prints a setting's range and description).

### Part 1: looks, and the editor page

A **look** is one complete set of the keys a row of `enhanced_weather.lua` holds: what the sky is made of. Today each
weather has one. The player gets a third page on the RTX Remix tab, beside Sky and Night sky editor: the Enhanced sky
editor.

- **My own look.** A saved setting, off by default. Off: each weather shows its own look, as today. On: the editor's
  values replace the weather's look. Rain, snow and sand still come from the weather, and the page says so.
- **Every control is a saved setting of its own,** in the pattern of the night sky editor: a data table with the
  setting's name, default, range, decimals and the library key. The defaults are the default weather's look.
- **Moving a control, or loading a look, turns My own look on.**
- **Start from.** A list of the twelve weathers' looks, the built-in looks and the player's saved looks. Choosing one
  copies it into the controls.
- **Built-in looks** are data, in a file of their own beside `enhanced_weather.lua`. Start with four from the
  library's presets that our weathers do not use: Fair, Cloudy, Altostratus, Cirrus (`src/weather.cpp` of the
  library's clone). Claude adds more in the game.
- **Save as, and delete,** for the player's looks: one JSON file a look under
  `data/nativeloader_companion/sky_looks/`, the file's name made from the look's name by a strict rule (letters,
  digits, `-` and `_` only, a length limit). A look file that does not parse, or holds an unknown key or a value out
  of range, is refused whole and named in the console.
- **Share as text,** if it stays small: copy the look to the clipboard as one line, and load one from a pasted line,
  with the same checks.
- **Reset** puts the controls back to the current weather's look.
- **Changes show at once** while a control moves. Turning My own look on or off, and loading a look, blend over two
  seconds. The slow variation of cover and wind goes on over a look as it does over a weather.
- **With Sky quality at Standard** the page says its settings are the Enhanced sky's, and offers the switch. In VR it
  says what the Sky page says.

**Which controls.** Every setting of the library that changes what the sky looks like and that a player can
understand, each in the library's own unit, with a label and a help line in plain words. About forty. Leave out
performance, debug, scale and deprecated settings, and what the Sky page already owns (the time, the sun's place,
the Moon's phase). In these groups:

| Group | Library keys to cover |
|---|---|
| Clouds | `cloudCoverageMean`, `cloudCoverageSpread`, `cloudTypeMean`, `cloudTypeSpread`, `cloudDensity`, `cloudBaseHeightMeters`, `cloudDepthMeters`, `cloudCellSizeKm`, `cloudColor` |
| Cloud shape | `nubis3ErosionStrength`, `cloudBodyBillowSizeKm`, `cloudBodyBillowGain`, `cloudCurlStrengthKm`, `cloudColumnTopVariation`, `cloudColumnFeather`, `cloudDiffuseSunStrength` |
| A second layer | `cloudLayer2Enable` and its coverage, height, depth, type, density and albedo |
| High clouds | `cloudCirrusEnable` and its coverage, height, optical depth, streak direction, halo strength |
| Wind | `cloudWindSpeed`, `cloudWindDirection`, `cloudEvolutionSpeed` |
| Air | `aerosolDensity`, `aerosolTint`, `airDensity`, `airTint`, `ozoneDensity`, `mieAnisotropy` |
| Fog | `fogVisibilityMeters`, `fogHeightFalloffMeters`, `fogBaseHeightMeters`, `fogAlbedo`, `fogAnisotropy` |
| Storm | `lightningStrikesPerMinute` |

- The list is yours to finish: add a key that belongs, leave out one that does nothing visible, and say which in the
  report.
- Take each range from the library's own limits and from what its presets and our weathers use, not wider than is
  useful. Visibility needs a control a player can aim with: most of its useful range lies between 50 m and 50 km.
- A key the weathers' looks do not hold yet joins them, at the library's default.

### Part 2: style settings, apart from looks

These apply in every weather and every look, are saved settings of their own, and sit in a group at the top of the
editor page.

| Setting | What it drives |
|---|---|
| Sun rays | `rays.enable` and `rays.strength`: 0 to 2, default 1 |
| Rainbow | A multiple, 0 to 2, default 1, of what the weather gives (part 4) |
| Night brightness | `nightGainStops`, default 10 (round 1's tuned value) |
| Moonlight, stars | `moonlightGainStops`, `starGainStops`, `starScintillation` |
| Clouds' shadow | `cloudShadowStrength` |
| Mist on the map | The contract's `volumetrics`: "Enhanced mist" (0, the default) or "Remix fog near you" (1) |

- **The Night sky editor's Moon size and Moon brightness** apply to both skies from now on: map them onto
  `moon0.angularDiameter` and `moonDiscGainStops`. The Night sky editor page says which of its settings Enhanced
  follows.
- **"Remix fog near you":** the companion sends the fog of the current look to Remix volumetrics as well, so both
  agree: the reverse of `presetFog` in `enhanced_sky.lua`. A fog preset the player chose on the Remix settings page
  still wins.

### Part 3: the mode's own data

- `enhanced_weather.lua` gains a table for what belongs to the mode and not to a weather. It is sent whenever the
  Enhanced sky shows, also with the weather left to Remix. The night's gain and the lamps' switch move there, out of
  the weathers.
- The table has a common part and a part for each detail level (High, Medium, Low): the library's `qualityLevel`,
  `rays.quality`, and the lamps in the haze with their limits (`aerialPerspectiveLocalLights`, `...LocalLightCutoff`,
  `...LocalLightTileMaxCount`, `...LocalLightMaxCount`, `...LocalLightShadows`, `...LocalLightWindow`). Claude tunes
  the values in the game. Start with the lamps off at every level.
- A style setting of the player wins over the table.

### Part 4: the rainbow's rain

- The companion keeps how wet the air is, 0 to 1: it follows the rain of the current weather (drizzle, rain,
  thunderstorm; not snow or sand) and falls off over about five minutes after the rain stops.
- It sends that, times the player's Rainbow setting, as `rainbow.strength`. The runtime decides where the sun lights
  it.

### Part 5: no more writes of `rtx.volumetrics.enable`

- In Enhanced the companion sends the contract's `volumetrics` and leaves `rtx.volumetrics.enable` alone.
- A value round 1's code saved in `nativeloader_sky_volumetrics_saved` is put back once and cleared.

### Part 6: texts, tests, documents

- Every new text in the six languages (`companion/i18n`), by the catalogs' own tools and glossaries.
- Tests in the pattern of `tools/tests/test_companion_sky.py`: the Standard path's calls unchanged; a look replaces
  a weather's keys and nothing else; the checks on a look file; the style settings; the mode's table at each detail
  level; the rainbow's rain; no write of `rtx.volumetrics.enable`.
- A new Lua file in the package needs its path in the render guard's bundled list
  (`_nativeloader_guard.lua`), or `test_render_guard_addons` fails.
- Then `tools\test.ps1 -Config Release` from `sky2c`, until it passes.

### Deliver

Commits on `sky-enhanced-c`, and your report, `docs/handover/sky-enhanced-E-report.md`:

- the page: each control with its setting, range, default and library key, and each key you added or left out;
- how a look is stored and checked;
- the style settings and the mode's table;
- the tests and their output;
- what Claude must check in the game, and what you could not do.

## Rules for both tasks

Round 1's rules hold. In short:

- **No game sessions.** Do not start Garry's Mod, the PoC or the field install. Claude does every test in the game.
- **Off limits:** SourcePT, its local checkout, OpenRemix. Never open them.
- **The library** stays at its pin and unmodified. Keep every copyright and licence header.
- **Today's sky** is not touched: its shader sources have no diff, and modes 0 and 1 behave as at patch 0108.
- **No loader change:** nothing under `loader/`.
- **Nothing outward:** no push, no pull request, no Workshop upload, no tag, and no merge into `main`.
- **Commits:** on your own branch only, as the repository's git config identity, with no co-author trailer.
- **No LFS import:** do not run `tools\inputs.py import` for the runtime. Builds are `-NoImport`. Claude stores the
  runtime once, after the tests in the game.
- **Builds** may run at any time in this round. Say in your last message when your last build ended: Claude measures
  frame times only after it.
- **Paths:** tracked files, commit messages and reports name no user account and give no absolute local path
  (AGENTS.md rule 10).
- **Scratch:** temporary files go under the repository's `out\`. Delete large build copies you no longer need.
- **Documentation duties** of AGENTS.md apply. Shared documents (CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING)
  get additive edits only. Leave ADRs to Claude.
- **If you are blocked,** write what blocks you in your report and stop. Do not work around a rule.

## What Claude does

- While the tasks run: finds the lamps' limits that make their glow affordable, tries Remix fog under the Enhanced
  sky, and tunes the weathers that look wrong, all in the PoC with round 1's build.
- Reviews each task's diff and report, and merges them into `sky-enhanced`.
- Tests in the PoC: Standard unchanged again; the rays in the low-sun and storm scenes, with their debug views and
  their cost; the three values of `volumetrics` on a real map with lamps; the rainbow; the editor's page at 4K, a
  look saved, loaded and refused.
- Fills the mode's table and the built-in looks.
- Stores the runtime, runs the gate, writes the decision record and the round's report, and shows the round to the
  user.

## Task R3: the sun rays after the first tests

Added on 2026-11-26, after Claude's first PoC run of patches 0109-0112 (run `R2-rays` in `<repo>/out/sky2`; its sheets
are `<repo>/out/sky2/judged/R2/rays-*.jpg`). Same place, rules and delivery as task R2. Amend patch 0109 or add a patch
0113, whichever keeps the series clearer, and say which.

**What the PoC showed.** 4K output, DLSS Performance (1920x1080 render), RTX 5090, sky quality High. Each sky was taken
at strength 0, 1 and 3 and in debug views 1 and 3.

- **The pass works.** Debug views 1 and 3 show clean shafts radiating from the sun through gaps in broken cumulus, and
  converging toward the anti-solar point behind the camera.
- **Its cost is below what a frame time can show:** strength 1 against strength 0 differed by -0.4 to +0.2 ms over
  eleven views. The detail levels could not be told apart either.
- **At strength 1 the rays are faint.** In the library's clean air (aerosol 1.1) they cannot be seen. With aerosol 8
  to 10 and the sun 10 to 18 degrees up, faint shafts show beside the sun. Physical; Claude tunes the air.
- **Above strength 1 the darkening clips.** At strength 3 the open sky beside the clouds near the sun turns a
  saturated electric blue in irregular patches. The subtraction is clamped at zero per channel, so where the removed
  light exceeds the red and green of the sky, only blue survives.
- **The ray term has a structured noise.** Debug views 1 and 3 show a fine diagonal hatching over the whole sky, in a
  still view and while the camera turns at 8 degrees a second. It does not show at strength 1. At the strengths
  players can choose (up to 2), it will.
- **A thin bright line runs along the horizon** in debug view 1, in every view with a horizon, still and turning.

**What to change.**

1. **Darken without clipping.** Above strength 1, scale the removed light with one factor for all three channels, so
   its colour is kept, and never take a channel below a floor share of its own value. At strength 1 the result is
   what 0109 gives wherever that floor does not bite. Choose the floor and say why.
2. **Remove the hatching.** The ray term must be smooth at strength 2: in a still view after a second, and while the
   camera turns at 8 degrees a second. Find the cause (the per-texel jitter sequence, the history clamp, the fill) and
   fix it within the 0.5 ms budget at High. The renderer's blue noise is already bound for the library.
3. **The horizon line.** Find what draws it. Fix it if it reaches the normal picture at strength 2.
4. Run the unit suite and the build as in task R2.

**Deliver.** In `docs/handover/sky-enhanced-R2-report.md`, a new section "R3": the floor and the factor, the cause of
the hatching and its fix, the horizon line, and what Claude should look at first.

## Task E2: the editor after the first tests

Added on 2026-11-26, after Claude's first PoC runs of task E's editor (`R2-ui`) and the trial looks (`R2-tune-a`;
sheets in `<repo>/out/sky2/judged/R2/`). Same place, rules and delivery as task E, with one change: do not run
`tools\test.ps1`. Run the sky suite and the catalogs' check (`companion_i18n.py update` and `check`); Claude runs the
gate at the end, while the PoC measures frame times now.

**What the PoC showed.** The page works at 3840x2160: every group, label and help line reads, the buttons and the
look list work, the visibility slider aims well.

**What to change.**

1. **Haze density reaches a hazy day.** The library's aerosol has an optical depth of about 0.01 straight up at
   density 1, so the slider's 0 to 10 never gives a hazy sky: the trials needed 20 to 80. Make the range 0 to 100,
   with the low end given room on the track as visibility's is (densities 0 to 10 are the common ones), and say in
   the help line what 1, 10 and 50 look like (clean air, a soft glow round the sun, a white haze).
2. **Lamp glow in the mist, as a choice.** A style setting in "Light and mist", off by default: "Lamp glow in mist",
   with a help line that says it costs frame time near many lamps and with the flashlight. On, it sends
   `aerialPerspectiveLocalLights` True; off, False. It wins over the mode table's value. Claude sets the per-level
   limits in the mode table.
3. **No empty band at the top.** In Enhanced, the page shows an empty band above "My own look" where the Standard
   notice and the switch button were, until something lays the page out again. Lay it out when they hide.
4. **Smaller colour pickers.** Each colour control shows a full colour mixer, about eight lines tall. Make each one
   compact: a swatch and the RGB entry on one row, the mixer opening on demand, or a mixer half the height. Your
   choice; say which.
5. **Five more built-in looks,** after the four from the library, with these names and values (the editor's keys over
   the built-in baseline, as the other four are written). Claude tunes the values afterwards; the names are final.

   ```lua
   {name = N("Mackerel sky"), values = {cloudCoverageMean = 0.08, cloudTypeMean = 0.7, cloudLayer2Enable = true,
       cloudLayer2CoverageMean = 0.62, cloudLayer2BaseHeightMeters = 4500, cloudLayer2DepthMeters = 450,
       cloudLayer2TypeMean = 0.9, cloudLayer2DensityScale = 0.4, cloudCirrusEnable = true,
       cloudCirrusCoverageMean = 0.25, cloudCirrusOpticalDepth = 0.33, cloudCirrusStreakDirection = 110,
       fogVisibilityMeters = 20000}},
   {name = N("Towering cumulus"), values = {cloudCoverageMean = 0.33, cloudTypeMean = 1, cloudTypeSpread = 0.2,
       cloudDensity = 30, cloudBaseHeightMeters = 1000, cloudDepthMeters = 5000, cloudCellSizeKm = 4.8,
       nubis3ErosionStrength = 0.8, cloudColumnTopVariation = 0.85, cloudCirrusEnable = true,
       cloudCirrusCoverageMean = 0.15, cloudCirrusOpticalDepth = 0.33, cloudCirrusStreakDirection = 110,
       fogVisibilityMeters = 20000}},
   {name = N("Humid summer"), values = {cloudCoverageMean = 0.55, cloudTypeMean = 0.85, cloudCirrusEnable = true,
       cloudCirrusCoverageMean = 0.1, cloudCirrusOpticalDepth = 0.33, cloudCirrusStreakDirection = 110,
       aerosolDensity = 2.6, fogVisibilityMeters = 30000, fogHeightFalloffMeters = 900, fogAlbedo = 0.97,
       fogAnisotropy = 0.7}},
   {name = N("High cirrus"), values = {cloudCoverageMean = 0.06, cloudTypeMean = 0.7, cloudLayer2Enable = true,
       cloudLayer2CoverageMean = 0.3, cloudLayer2BaseHeightMeters = 6000, cloudLayer2DepthMeters = 400,
       cloudLayer2TypeMean = 0.8, cloudLayer2DensityScale = 0.3, cloudCirrusEnable = true,
       cloudCirrusCoverageMean = 0.85, cloudCirrusOpticalDepth = 0.55, cloudCirrusStreakDirection = 70,
       fogVisibilityMeters = 20000}},
   {name = N("After the rain"), values = {cloudCoverageMean = 0.58, cloudTypeMean = 1, cloudTypeSpread = 0.3,
       cloudDensity = 36, cloudBaseHeightMeters = 900, cloudDepthMeters = 4500, cloudCellSizeKm = 4.5,
       nubis3ErosionStrength = 0.9, cloudBodyBillowGain = 0.75, cloudDiffuseSunStrength = 0.25,
       aerosolDensity = 1.6, fogVisibilityMeters = 25000, fogHeightFalloffMeters = 700, fogAnisotropy = 0.7,
       aerialPerspectiveFroxelRangeMeters = 6000}},
   ```

6. **Leave `enhanced_weather.lua`'s weather tables alone:** Claude is tuning them on the round's branch. Add only
   what item 2 needs, if anything.
7. Every new text in the six languages; the tests for items 1 to 5.

**Deliver.** Commits on `sky-enhanced-c` and a new section "E2" in `docs/handover/sky-enhanced-E-report.md`.

## Task E3: a haze that can be bright

Added on 2026-11-26, after the second haze trials (`R2-tune-b`, sheets `<repo>/out/sky2/judged/R2/tune-haze2-*.jpg`).
Same place, rules and delivery as task E2 (no `tools\test.ps1`).

**What the PoC showed.** A hazy sky needs aerosol density 20 to 80. At the library's own absorption (`mieAbsorption`
4.4e-3 per km, more than its scattering of 4.0e-3) that much aerosol turns the sky a dark grey, like smog. With a
tenth of that absorption the same density gives the milky, bright haze of a humid summer day. So the haze's darkness
must be a setting of the look, as the fog's brightness already is.

**What to change.**

1. **"Haze darkness" in the Air group,** after Haze density. It sets the library's `mieAbsorption`. Players see one
   slider; choose how it reads (a multiple of the library's default is one way: 1 dusky as the library has it, 0.1
   milky and bright, 3 smoky). The three channels get the same value; Haze colour (`aerosolTint`) colours it.
2. **The look stores it in the library's units,** like every other key. Looks saved before this change (without the
   key) still load, with the library's default for it. Pasted text the same.
3. **The weather tables may set it.** Add the key to `defaults` in `enhanced_weather.lua` at the library's default,
   in the form the send path takes, so every weather sends it and a weather without it puts the default back. Do not
   change any weather's other values: Claude tunes them.
4. **A test that every weather's look and every built-in look passes the editor's own check,** so a tuned value
   outside a control's range is caught before it ships.
5. The new texts in the six languages.

**Deliver.** Commits on `sky-enhanced-c` and a new section "E3" in `docs/handover/sky-enhanced-E-report.md`.

## Task M: the library's Remix menu, translated

Added on 2026-11-26, after the round's report. The user's answers to round 1's open questions, before the merge:

- The menu: "For option 4, I cleared the confusion, yes please add and translate the NUMOS sky's remix men[u]."
- The credits: "Yes, please update the credit lines."
- Enhanced becomes the default sky, Standard unchanged. Claude changes the companion for that; it is not this task.

Codex thread R, in `sky2r` (fast-forwarded to `sky-enhanced`), on the fork branch `claude/sky-enhanced` in
`<repo>/out/worktrees/r17/out/runtime-src`. "Rules for both tasks" above hold. One new patch, 0114, or more if that is
clearer; say which.

**What round 1 left out.** From the integration commit `Kim2091/dxvk-remix` `1532c782` (its files and per-file
patches are in `<repo>/out/sky2/scratch/numos-upstream`):

- `src/dxvk/rtx_render/rtx_numos_ui.cpp` and `.h`;
- the `dxvk_imgui.cpp` hunks: the sky mode combo, the library's notes and tab bar under Sky Tuning, and the weather
  preset window in the developer menu;
- the `rtx_user_menu.cpp` hunk: Night, Haze and Cloud settings in the graphics settings window while the library
  draws the sky;
- the `dxvk_imgui_about.cpp` hunk: a name added to the About panel.

Round 1's reason: a release build refuses a menu text without its six translations, and the pages have about 790.

**What to build.**

1. **Port the menu** onto our port of the library (patches 0108-0113).
   - Use our option names: the library's settings under `rtx.atmosphere.numos.`, its weather options under
     `rtx.atmosphere.numos.weather.`, the world-change counter `rtx.atmosphere.numos.worldChangeCount`. Our own
     options (`rays.*`, `volumetrics`, `rainbow.*`) get controls in the tab where they fit.
   - The sky mode: keep the fork's existing control for `rtx.skyMode` with its three modes (0 the game's sky,
     1 Standard, 2 Enhanced), named as the menus already name them. Do not add the integration's two-choice combo
     beside it. Show the library's pages where the integration shows them (Sky Tuning in the developer menu; Night,
     Haze and Cloud settings in the graphics settings window) while mode 2 is in effect.
   - Nothing is written into the game folder (ADR 0267, decision 4). Leave out every control that saves, loads,
     lists or opens preset files, folders, seeds or markers, and say which. Built-in presets applied in memory stay.
   - A short note at the top of the library's pages, translated: the RTX Remix tab's "Sky and weather" and
     "Enhanced sky editor" pages set these values, and a change of weather or look, or a map's start, sets them again.
   - The About panel: the integration's addition, and the credit line the library's README asks for, "Sky and clouds:
     NUMOS by Kim2091 (Sparkles)", in the panel's own style. Names are not translated; a label is.
   - The library stays unmodified. The menu code is the integration's (MIT, dxvk-remix): keep its headers.
2. **Translate every new menu text** into zh-CN, zh-TW, ja, ko, fr and ru, as runtime patch 0100 did
   ([remix-menu-i18n-report.md](remix-menu-i18n-report.md)).
   - `i18n/tools/update_strings.py` regenerates `remix.pot`. Translate in each catalog, keeping to
     `i18n/glossary/<language>.md`, and add the sky's new terms to each glossary.
   - `embed.py` (with the fork README's arguments) must report every language complete, and its font and printf
     checks must pass. If a character is missing from the fonts, say which and how you handled it; do not swap fonts
     without saying so.
   - Write the catalogs with Python and explicit UTF-8. A Codex run on this machine once turned non-ASCII text into
     `?`: check that no translation has a `?` its English lacks, and that each language's non-ASCII share is plausible.
   - Option keys, units and numbers in tooltips stay as they are. The English must be right too: short labels, and
     tooltips that say what the setting does.
3. **Checks:** `update_strings.py --check` exits 0; `embed.py` reports every language complete; `test_embed.py`
   passes; the unit suite as in task R2; `runtime\build_runtime.ps1 -NoImport -Install` passes.

**Deliver.** The fork commit(s); in `sky2r` the exported patch(es), `runtime/base.json` (`pending_patches`), the
section in `runtime/README.md`, one CHANGELOG line for players (the Remix menu, Alt+X, shows the Enhanced sky's own
settings, in the seven languages), and your report, `docs/handover/sky-enhanced-M-report.md`:

- where each page shows and what it holds;
- the controls left out, and why;
- `embed.py`'s output and the glyph check;
- what Claude should look at first in the game: which window, which tabs, which languages;
- the commands you ran, with their output, and when your last build ended.

Meanwhile Claude makes Enhanced the default in the companion, adds the credit line to the README (Workshop pages are
never edited: the user, 2026-11-26), and merges this task when it passes in the PoC.
