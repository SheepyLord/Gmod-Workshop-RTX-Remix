# 0226: GMod's poster command rendered in tiles by the runtime

- Status: Accepted 2026-11-15 (the user, on GitHub issue 3 "Command poster is disabled for Remix compatibility":
  "Address https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/3. The command poster allow user to render a
  screenshot at a resolution higher than their current resolution."); runtime patch 0095 and the engine guard, no
  loader change.
- Context: the owner's comment on the issue (2026-11-13): "Not easily fixable due to the limitation of DLSS, upscaler
  can not change resolution without a flush in render queue".

## What was found

- **GMod's `poster` is engine code.** `client.dll` registers the ConCommand (`poster [multiplier] [bSaveEach]`, help
  "Renders a poster X times size of your game's resolution and saves it in your screenshots/ folder"). Its callback
  (rva `0x68900` in the PoC's build) only stores `(int)atof(argv[1])` and `argv[2][0] == '1'` in two globals, or prints
  the usage line without a multiplier; the view renderer then renders the poster's tiles through sheared (off-centre)
  projections, reads back the raster image and writes `screenshots/poster-%y-%m-%d %H-%M-%S.png`.
- **RTX Remix rejects such a camera.** `CameraManager::processCameraData` drops a projection whose decomposed shear is
  above 0.01 ("[RTX] CameraManager: rejected an invalid camera"), so none of the tiles is path traced, and the read
  back is the raster image the path traced picture replaces later in the frame. Nothing in the package blocked the
  command: it had nothing to render.
- **Rendering at the poster's size is the wrong way round.** A frame at twice a 4K window (7680 x 4320) needs every
  render target, the denoisers' and the upscaler's included, at that size: several times the VRAM of the 4K frame,
  and a DLSS feature made anew (the flush the owner names) on the way in and out. Four times is out of reach for any
  GPU.
- **The runtime already renders a view other than the game's.** VR (ADR 0145) path traces off-centre eye frustums
  with the game drawing its ordinary view; VR's true stereo needed the physical sky's screen-aligned passes (the cloud
  layer and the aerial perspective, built from the camera's field of view and aspect) fitted to the eye's frustum
  (`RtxAtmosphere::fitAerialPerspective`). The froxel volumetrics follow the projection matrix, and the culling and
  anti-culling frustum is built from the field of view and aspect, not the matrix.

## Decision

1. **The runtime renders the poster (patch 0095).** `d3d9.dll` exports `rtxposter_Start`, `rtxposter_Cancel` and
   `rtxposter_GetStatus` (`rtx_poster_api.h`, version 1). The poster is the multiplier (1 to 16) times the window,
   at most 16384 x 16384, cut into tiles of the window's own size that overlap their neighbours by a sixteenth of the
   window's short side (16 to 256 pixels): no render target, denoiser or upscaler ever changes size. For each tile
   the main, view model and sky cameras' projections are narrowed to the tile's window of the game's view (only the
   clip x and y rows change; the camera keeps the game's field of view and aspect, so the culling frustum and the view
   model's detection see the whole view, and the view model's perspective correction is unchanged). A tile's first
   frame resets the temporal history; its last frame (64 by default), the picture before its UI, is read back. The
   tiles are blended over their overlaps in reading order (each row joined across, then down: every overlap pixel a
   bilinear mix) into 8-bit BGR and written by a thread of their own with Windows' PNG encoder, as `<path>.part`,
   then renamed.
2. **Every tile is lit and finished alike.** While a poster renders, the runtime's clock stands still (the sky,
   clouds, animated materials and particles stay put), exposure keeps the value it had, and motion blur and the lens
   effects (vignette, chromatic aberration: they belong to a whole picture, not to each tile) are left out. The
   physical sky's cloud layer and aerial perspective are fitted to the tile's window; the rasterized sky matte (a
   map's own skybox) gets a viewport stretched until the tile's window covers it, with its jitter shrunk to a pixel;
   textures and the sky are sampled for the poster's pixel size, not the window's.
3. **It stops rather than mix two views:** when the view moves (more than a Source unit or a fifth of a degree), the
   window changes size, VR starts, or it is cancelled.
4. **The engine guard takes the command (client realm, RTX starts).** Where the process's `d3d9.dll` has the poster
   API, the `gmcl_` copy swaps the `poster` ConCommand's callback (found in `client.dll` by its help text, its name,
   its callback in `client.dll`'s code and its kind; SDK 2013's x64 layout, confirmed from `ConCommand::ConCommand` in
   the game's `client.dll`) for one that reads the arguments as the engine does and asks the runtime for the poster
   under the engine's own file name. The module is pinned; the takeover lasts the process. A `Think` hook of the client
   realm prints in the console how it goes, from the main thread (which draws the console). Without a multiplier the engine's callback prints its usage; below 1 the engine's "silly
   size" line is printed; above 16 the module's.
5. **Lua starts nothing.** Only the command starts a poster, as without RTX (any Lua could run the command then as
   now). The client realm gets `nlengineguard.poster` and the read-only `nlengineguard.PosterStatus()`; the
   companion's sky holds its clock and weather while it says `starting` or `rendering`, and goes on from where it
   stood.

## Consequences

- `poster 2` in an RTX start writes a path traced picture of twice the window, `poster 4` four times (15360 x 8640 at
  4K, the most there), in the same `screenshots` folder and under the same name as the game's own poster.
- It takes time: 64 frames for each of (N + 1)² tiles (9 for `poster 2`): 5.0 s for `poster 2` and 9.1 s for
  `poster 3` at 1280 x 720 on an RTX 5090. The screen shows each tile magnified while it is traced.
- The game is not paused by it, nor by the console (game time ran on with the console open in single-player):
  anything that moves during the poster (other players, physics, an NPC, a weapon's idle sway) can differ between
  tiles. The view must hold still.
- No lens effects in a poster. Bloom is computed per tile; the overlap carries it across the seams.
- The engine's `bSaveEach` keeps each tile beside the poster (`<name>_tile_<column>_<row>.png`).
- A start without RTX, or an older runtime, keeps the engine's poster unchanged.

## Alternatives not taken

- **Accepting sheared projections and keeping the engine's poster.** The engine renders all tiles in one frame and
  reads each back before Remix has traced anything; a path traced tile needs dozens of frames to converge.
- **Rendering the poster as one frame at its size.** The VRAM and the upscaler's re-creation above.
- **A Lua command with `render.RenderView` and an off-centre view.** The same rejected camera and raster read-back.
