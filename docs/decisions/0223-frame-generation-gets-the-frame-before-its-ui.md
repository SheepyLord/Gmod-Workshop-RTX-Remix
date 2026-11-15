# 0223: DLSS frame generation gets the frame before its UI

- Status: Accepted 2026-11-14 (the user: "Draw the crosshair as the UI texture is not so already, so it won't be
  affected by frame generation."); runtime patch 0094, no loader change.
- Context: with DLSS Frame Generation on, the crosshair smeared or doubled while the view turned.

## What was found

- **The crosshair is UI to Remix already.** GMod draws the default crosshair (`CHudCrosshair`, a glyph of the HUD's
  font through vgui) with an orthographic projection and no depth writes, which `D3D9Rtx::isRenderingUI()` takes for
  UI (`rtx.orthographicIsUI`, on by default; the package does not change it). It is rasterized over the path traced
  image after RTX injection, like the rest of the HUD, a custom crosshair drawn in `HUDPaint` and the menus. Tagging
  its texture in `rtx.uiTextures` would change nothing.
- **Frame generation moved it.** Remix's DLSS-G (`DxvkDLFGPresenter`, `NGXDLFGContext::evaluate`) was given only the
  finished back buffer, motion vectors and depth (`pBackbuffer`, `pMVecs`, `pDepth`), so it moved every pixel with
  the scene's motion, the UI's too. NGX takes an optional HUD-less colour, "the scene color before any UI or HUD
  elements are drawn" (`pHudless`, `nvsdk_ngx_defs_dlssg.h`), and keeps the pixels where the back buffer differs from
  it, the UI, in place. FSR frame generation already got the final output as its HUD-less colour.
- **When it shows.** In the PoC at 1280x720 (about 560 rendered frames a second, one generated frame each) a test bar
  and the crosshair stayed intact in every sampled frame with either runtime: the scene moves a few pixels a frame.
  At 3840x2160 with three generated frames per rendered one and the view turning 180 degrees a second, the published
  runtime showed faint copies of the crosshair dot along the turn in 16 of 290 sampled frames and a damaged test bar
  in 22, as the user saw.

## Decision

Runtime patch 0094 gives DLSS-G the frame before its UI:

1. While the frame generation presenter runs, the D3D9 swapchain keeps a copy of its back buffer (its create info,
   and its sampled view for reading it) and hands it to `DxvkDLFG`'s `DlfgHudlessHandoff` (`rtx_dlfg_hudless.h`).
2. `RtxContext::injectRTX` blits the final output into that copy right after the game's target, with the same blit,
   when frame generation is on and the copy has the target's size, format and one sample, and marks the frame.
3. The presenter has a HUD-less image beside each back buffer; the swapchain's present blits the copy into it with
   the back buffer's own `presentImage` call (the same rectangles, gamma ramp and view), so a pixel no UI was drawn
   over comes out identical, and the HUD and Remix's own menu, drawn after it, are UI.
4. The present thread passes the slot's image as `pHudless` only for a frame the render thread marked; a new copy
   (another back buffer size or format) forgets every mark. Its barriers mirror the back buffer's. The runtime logs
   `[DLFG] frame generation gets each frame before its UI (HUD-less input), from frame N` once.

No option: with DLSS-G on it is always used, and with frame generation off nothing changes. It costs one copy of the
back buffer and a full-screen blit a frame, and one HUD-less image per frame generation back buffer (about 33 MB each
at 3840x2160), only while DLSS-G runs.

## Consequences

- The crosshair, the HUD, menus, the console and Remix's menu stay in place in the generated frames. Measured in the
  PoC's 4K test above with the branch's runtime: no copy of the crosshair dot in any of 305 sampled frames, the test
  bar intact in all of them, and a one-pixel test cross a little whiter (its darkest pixel's median 207 against 173).
- Anything rasterized after injection that is not UI (a raster draw after the frame's first 2D draw, as in R25's ARC9
  cases) differs from the HUD-less image as well, so DLSS-G keeps it in place too: it steps at the rendered rate
  instead of smearing.
- A frame whose injection target is not the back buffer's size or format gets no HUD-less image, as before.
- Changing `rtx.dlfg.maxInterpolatedFrames` while frame generation runs stopped the published runtime's presenter in
  the PoC (`DxvkDLFGCommandListArray::nextCmdList: vkWaitForFences failed`; the game kept answering but drew nothing
  more). Not this patch's: the tests changed the multiplier only with frame generation off. It is open.
