# GitHub issue 3: the poster command under RTX: report (2026-11-15)

The user's request of 2026-11-15: "Address https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/3. The command
poster allow user to render a screenshot at a resolution higher than their current resolution." The issue (the
owner's, 2026-11-11) is "Command poster is disabled for Remix compatibility", with the owner's comment of 2026-11-13:
"Not easily fixable due to the limitation of DLSS, upscaler can not change resolution without a flush in render
queue". Done by Claude on the branch `issue3-poster`: runtime patch 0095 (fork branch `claude/poster`), the engine
guard and the companion's sky; no loader (`winmm.dll`) change
([ADR 0226](../decisions/0226-the-poster-command-rendered-in-tiles-by-the-runtime.md)).

## Why it did not work

GMod's `poster` is `client.dll` code: the command only sets a multiplier, and the view renderer draws the poster's
tiles through sheared (off-centre) projections in one frame and reads each back. RTX Remix's camera manager rejects a
camera with a shear above 0.01, so no tile was path traced, and the read-back is the raster picture. Nothing in the
package blocked the command. Rendering one frame at the poster's size instead would need every render target, the
denoisers' and DLSS's, at that size (the flush the owner names, and VRAM no GPU has at four times 4K).

## What changed

- **The runtime renders the poster in tiles of the window's size** (patch 0095, `rtx_poster.*`). While a poster
  renders, the main, view model and sky cameras' projections are narrowed to one tile's window of the game's view;
  the cameras keep the game's field of view and aspect, so culling and the view model's detection still see the whole
  view. Tiles overlap by a sixteenth of the window's short side and are blended. A tile's first frame resets the
  temporal history; its 64th, before the UI, is read back. The tiles are composed into one picture and written as a
  PNG by Windows' encoder on a thread of their own. The runtime's clock stands still meanwhile, exposure keeps its
  value, motion blur and the lens effects are left out, the physical sky's cloud layer and aerial perspective follow
  the tile, and a map's own skybox (the sky matte) is stretched to it. Exports `rtxposter_Start`, `rtxposter_Cancel`,
  `rtxposter_GetStatus`.
- **The engine guard takes the command** in the client realm of an RTX start (`engine_guard/poster.*`): the
  `poster` ConCommand's callback in `client.dll` is swapped for one that reads the arguments as the engine does and asks
  the runtime for the poster under the engine's own file name, `screenshots/poster-yy-mm-dd HH-MM-SS.png`; the
  module's `Think` hook prints the size, "Saving poster to ..." and "Saved poster to ..." in the console. Lua gets only the
  read-only `nlengineguard.PosterStatus()`.
- **The companion's sky waits** while a poster renders (`nativeloader_sky.lua`): its clock and weather go on from
  where they stood.

## Checked

In the PoC (RTX 5090, a 1280 x 720 window, gm_construct, the package built from the branch;
`out\qa-poc\issue3-poster`), a client Lua probe typed `poster 1`, `poster 2` and `poster 3` through
`LocalPlayer():ConCommand` and followed them through `nlengineguard.PosterStatus()`:

| Poster | Size | Tiles | Seconds | Scaled down against `poster 1` |
|---|---|---|---|---|
| `poster 1` | 1280 x 720 | 1 | 0.6 | (the reference) |
| `poster 2` | 2560 x 1440 | 3 x 3 | 5.0 | 35.2 dB (a wall), 40.6 dB (sky, buildings, the physics gun) |
| `poster 3` | 3840 x 2160 | 4 x 4 | 9.1 | 34.8 dB, 39.1 dB |

- **The tiles are where they belong.** Every ninth of a poster scaled down to the window matches `poster 1`'s within
  31-54 dB (a misplaced or swapped tile would leave one ninth far below the rest); the view model (the physics gun),
  the buildings, the high cirrus and the sky's gradient continue across every tile. The small clouds sit a little
  further along in a later poster: the clock runs between posters and stands still only within one.
- **No seams.** The mean step across the middle of every overlap is no larger than the steps beside it (0.35-2.1
  against 0.41-2.4 grey levels); the one larger step, `poster 2` of the wall at y = 540, is the wall's trim line.
  Full-size crops across the overlaps show none, and the poster has the detail of its own size (the wall's cracks and
  the gun's panels, where `poster 1` enlarged is soft).
- **The console.** The probe's console lines appear in order: "Poster 2x with RTX: hold still until it is saved.",
  "Rendering the poster at 2560 x 1440: 9 tiles ...", "Saving poster to '...'", "Saved poster to '...' (2560 x
  1440)". With the console open (`showconsole`) the same poster was made in 5.0 s, its lines printed while the console
  stayed open, and no console is in the picture. Game time did not stop with the console open in single-player
  (`CurTime` ran 1.006 s in a second).
- **Writing.** The 3840 x 2160 PNG (9.1 MB) was written 0.38 s after its last tile.
- **Two runs found two things first.** The first run's `rtxposter_Start` answered "no device": GMod never registers
  its device with the Remix API, so the exports now reach the poster through its own instance. The second run
  launched with `poc_session.py`'s default `-noaddons`, which loads none of the package's add-ons, so nothing was path
  traced and the request stayed `starting`; the runs above use `--addons`.
- **The gate.** `tools\test.ps1 -Config Release`: the Python suites (29, 26 and 2002 tests) and the C++ tests pass
  (`nl_client_catalog_tests`' leftovers case failed once while the machine also ran another session's 4K game,
  `remove_leftovers` refused the just-closed lock; alone and in a full CTest rerun all 35 pass).

## What is left

- The poster does not pause the game, and neither does the console: what moves while it renders (an NPC, physics, a
  weapon's idle sway, other players) can differ between tiles. It takes seconds at a window's size (9 s for 16
  tiles at 1280 x 720 on an RTX 5090; longer at 4K).
- Lens effects (vignette, chromatic aberration) are not in posters; bloom is computed per tile and carried across the
  seams by the overlap.
