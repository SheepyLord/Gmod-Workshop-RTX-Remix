# The night sky editor: report (2026-11-15)

The user's request: "make skybox enhancement, add a sky editor in the tab to allow user to customize how each element
in the night sky looks (allow changing brightness of stellar elements). Note if the night sky is a whole picture, don't
proceed and report honestly". Done by Claude on the branch `night-sky-editor` (worktree `out\worktrees\nsky`, from
`main` at `9780980e`): runtime patch 0099 (fork branch `claude/night-sky-editor`), the night sky's re-baked textures and
the companion's Night sky editor page; no loader (`winmm.dll`) change.
[ADR 0227](../decisions/0227-the-night-sky-editor.md); facts in [RESEARCH.md](../RESEARCH.md) ("The night sky editor").

## Is the night sky one picture?

No, so the work went ahead, with one part that was: the runtime draws the night from separate parts, the night sky
image's three textures (a star layer, the galaxy band, a nebula sphere, each sampled on its own through the Skyrim mod's
sky-mesh mappings), the real Moon, the airglow and the shooting stars, or the procedural stars instead of the image.
But the shader summed the three image layers and scaled the sum with one brightness, and the mod's **constellations were
baked into the nebula picture**, so their bright stars could only change with the nebulae. Within the star layer the
stars are one picture: a single star, or the faint ones apart from the bright ones, cannot be changed. The
constellations could be split out: the mod's files are still here.

## What changed

**Runtime patch 0099** (`Atmosphere: the night sky editor: each layer on its own, the constellations apart`, fork
branch `claude/night-sky-editor` at `1dd38dbf` on 0098's `173bdc84`):

- Each image layer (stars, constellations, galaxy band, nebulae) has a brightness, `starMap*Brightness` (1, 0-8), and a
  colour, `starMap*Saturation` (1, 0-2). The layers are still added in gamma space as Skyrim adds them: a brightness b
  is the weight b^(1/2.2), so a layer alone scales by b in linear light; the sum is held at 1, or at the largest weight
  above it. At the defaults the image is as it was (`rtx_night_sky_layers.h`, `test_night_sky_layers.cpp`, 860 checks).
- The constellations are a layer of their own, the file beside the nebula's named `<name>_constellations.dds`
  (binding 222). No new path option, so the RTX fixes' Lua path policy needs no change. They come out with the stars in
  the twilight; the galaxy and the nebulae still wait for deep night.
- A layer at 0 is neither drawn nor kept: its texture is freed and loaded again when turned up. With every layer at 0
  the night has no stars at all (the image's night has its own flag), not the procedural field.
- The shooting stars: `shootingStarsPerMinute` (1.2, the former fixed 8 % of slots; 0-15) and `shootingStarBrightness`.
- Three 16-byte rows at the end of `AtmosphereArgs`, zeroed in the LUT cache key; `RtxOptions.md`. Not in the Remix
  menu, where the star map's options never were.
- Built by `build_runtime.ps1` (0001-0099): `d3d9.dll` 479,795,712 bytes, SHA-256 `52a8a3d2...2537` (70.8 MB with xz).

**The textures** ([`bake_nightsky.py`](../../tools/sky/bake_nightsky.py.md), now writing the two maps apart):
`nebula.dds` without the constellations (BC7) and `nebula_constellations.dds` (BC1, 0.1 % of its texels lit), with
their low-tier `_4096` copies ([`drop_top_mip.py`](../../tools/sky/drop_top_mip.py.md)); `CREDITS.txt` names the new
file. The default look matches the old combined map to a mean of 1e-5. 44 MB more video memory at 8192 with every layer
on (11 MB in the low tier); a hidden layer frees its own.

**The companion** ([`nativeloader_sky.lua`](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md)): the
**Night sky editor** page beside "Sky and weather" in the RTX Remix tab:

- Go to night, Time passes (to hold the night while editing) and the Night sky choice;
- the night sky image: all layers, then the stars, the constellations, the Milky Way and the nebulae, each a brightness
  (0-8) and a colour (0-2);
- the simulated stars: brightness, density, twinkle;
- the moon: brightness (its disc and its light on the map), size (0.5-5 degrees; the moonlight on the ground is kept,
  the eclipse geometry follows the radius), glow, earthshine;
- the shooting stars: a minute, brightness; the night glow (the weather's airglow); Reset the night sky.

Each is a saved client setting (`nativeloader_sky_*`). Like No horizon they are how the player sees the sky: a change
goes out at once and takes no map's sky over; on a map whose add-on owns the sky only the settings off their defaults
go out. The status line has the editor's values; `nativeloader_sky_night_reset` is the page's reset. 31 new texts in the
six catalogs (agent-written).

## Tests

- [`test_runtime_night_sky_editor.py`](../../tools/tests/test_runtime_night_sky_editor.py.md): the layers' unit test
  compiled from patch 0099 with MSVC and run; the options, arguments, binding, loading, shader and `RtxOptions.md` in
  the patch; the package's split layers in both tiers.
- [`test_companion_sky.py`](../../tools/tests/test_companion_sky.py.md): two new cases, the editor's settings reaching
  Remix, and a map whose add-on owns the sky.

- [`test_companion_sky.py`](../../tools/tests/test_companion_sky.py.md) also builds both pages against a recording panel:
  a slider for every editor setting over its own range, Go to night, Time passes, the Night sky choice and the reset.

## In the PoC

RTX 5090, 1280x720, gm_construct, the branch's package `0.0.0-dev.20261115180810+17fab958` (memory profile auto), a clear
midnight with a full moon held by [`night_sky_editor_probe.lua`](../../tools/qa/night_sky_editor_probe.lua.md); evidence
in `out\qa-poc\night-sky` (`01-editor`, `02-baseline`, `03-editor-stars`, `diffs`, `night-sky-editor-sheet.png`). Each run
exited 0 and quit normally.

- **Each element changes on its own** (`01-editor`, three views after each step, compared with the defaults): the
  constellations at 0 and at 6 in white change only their own star clusters (the difference images show the
  constellation shapes and nothing else); the Milky Way alone at 4, the nebulae alone at 4 (colour 1.5), every layer at
  0 and all layers at 3 change 27-45 % of the frame; with every layer at 0 the sky is the airglow alone, no simulated
  stars. The moon at 4 degrees, brightness 2 and glow 3 is larger, brighter and haloed, and stands about 7 degrees
  higher: a larger moon passes further from Earth's shadow, which scales with it (the help line says so). Reset the
  night sky gives the default frames back to within the frame-to-frame noise (mean difference 0.0015).
- **Textures freed and loaded again**: the Remix log loads the four layers at the start (the constellations' 8192
  texture beside the nebula's), and again each layer turned up from 0 (the constellations at 11:10:14, the nebulae at
  11:10:45, all four at 11:11:06), about 20 ms each.
- **The default look is unchanged** (`02-baseline`, the published package `0.0.0-dev.20261115130101+9f7a7c85` with
  the same probe): its default frames against the branch's differ by 0.0014-0.0017 on average per view (0.10-0.66 % of
  pixels by more than 4/255), as much as two frames of one run (0.0015-0.0017, 0.19-0.76 %); the frames' means agree to
  four decimals. The published package loads three night sky textures, the branch four.
- **The stars**: at 1280x720 and 90-110 degrees of view a pixel spans 14-17 texels across of the star layer, so its
  small stars average into a faint haze and the stars' steps barely change those views. Through 35 degrees
  (`03-editor-stars`, `stars-narrow.png`) single stars show: point sources counted in the frame, 830 by default, 2,118
  with the stars at 4, 97 at 0 (the constellations' stars and the nebulae's knots left) and 1,399 at 2 in grey.
- **The constellations in the twilight** (`04-twilight-page`, a scratch probe, the sun 10 degrees down): the Milky Way
  is a faint smudge (its deep-night fade about 0.1) while the constellations' clusters show, plainly at 6; the
  difference against 0 holds those clusters and nothing else.
- **The page** (`04-twilight-page`): the spawn menu's RTX Remix tab lists "Night sky editor" under Sky and weather;
  the page builds with every control, its long labels and help lines fit at 1280x720, no Lua error. Its sliders write
  back what they show, as GMod's sliders do; a value the console sets in the same tick as the page is built is
  overwritten by that write-back (the probe's own timing, seen once).
- The runs used the package built before the moon size's help line was reworded (it now says a larger moon moves a
  little in the sky); the text is the only difference.

## What is left

- Not seen in a game: earthshine on a crescent, the shooting stars' rate and brightness (a streak is thinner than a
  pixel at 720p; the shader's change is checked in the patch and the unit test), a 4K screen, a Radeon card.
- Within the star layer the stars are one picture: no control for a single star or a range of magnitudes.
- The fork's string catalogs were already behind its sources before this patch (98 menu texts untranslated after a
  regeneration, most likely since the upstream merge of patch 0093); left as they were.

## Gate

`tools\test.ps1 -Config Release` on the branch: "All checks passed" (C++ 35 of 35; Python 2,018 tests in `tools`, 1
skipped, 29 in `gmapack`, 26 in `steam`).
