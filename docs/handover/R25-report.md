# R25: the user's report after R24 (report)

The user's message after R24 (2026-11-09), three items with a screenshot of an RTX session (an ARC9 M249 with a
magnified scope whose lens showed the error material, and an "M249 SAW" card in the middle of the left half of the
screen) and the render guard's lines for ARC9's `cl_vm.lua:479/483` and `cl_pipscope_new.lua:387/388, 689/690`.
Standing instructions: no Codex (Claude, with Claude subagents); no loader (`winmm.dll`) change without the user's
approval; edits tested and reviewed; other programs on the machine never hold back a test. Done on branch `r25` in
`out/worktrees/r25`, by Claude, with Claude subagents for two independent reviews. No loader change and no runtime
change: everything ships in the package (the Workshop item).

| Item | Result |
|---|---|
| 1: a left-over UI drawn on the screen | A spawn-menu drag that GMod never ends: fixed in the companion (`nativeloader_dragdrop.lua`) |
| 2: mod weapons not path traced, the weapon, its accessories and scopes shaded wrongly | ARC9 read the screen just before drawing its gun in every frame, which ends path tracing for the frame: the gun, the hands and the attachments were rasterized. ARC9's screen reads and 2D draws before its view model are skipped under RTX and the screen is read after the view models instead; ARC9's sight blur, which drew a black copy of the scope into the image, is skipped ([ADR 0136](../decisions/0136-arc9-scopes-path-traced.md)) |
| 3: magnified scopes do not work (rendering, zoom) | ARC9's scope picture is path traced through the RTX runtime's raytraced render targets, at ARC9's magnification, with its reticle ([ADR 0136](../decisions/0136-arc9-scopes-path-traced.md)) |

## Item 1: the card left on the screen

The card is a spawn-menu content icon (128 pixels at the GUI scaler's size, with the NPC-weapon badge a weapon's icon
has at its top right). GMod's drag and drop (`lua/includes/extensions/client/panel/dragdrop.lua`) ends a drag only when
the dragged panel receives the mouse release; its own "no button is held, so drop" check is commented out. When the
spawn menu closes while an icon is held (Q released before the mouse button, or a click that moved the mouse 20 pixels
first), the release goes to the game, and GMod's `DrawOverlay` hook `DragNDropPaint` paints the icon at the cursor for
the rest of the session. Clicking any spawn-menu icon once ends it in a running game.

The companion's `nativeloader_dragdrop.lua` ends such a drag as GMod would (`dragndrop.StopDragging`, the panel lets
the mouse go) once no cursor is visible, or once the dragged panel has been hidden for two frames with its button up
(a drop onto a spawn list hides the source panel for a moment); a right-drag's drop menu is left alone, and an error in
another add-on's drag callbacks still clears the drag. Tested by `test_stuck_drag.py` (ten scenarios) and in the PoC: a
held icon whose panel is hidden was still painted 1.5 s later without the fix (`vm` runs) and was gone a frame after
with it (every run, the packaged build included).

## Items 2 and 3: ARC9's view model and scopes

Reproduced in the PoC with [ARC9] Gunsmith Arms: Source's M249 (the user's weapon) and its ELCAN, RTX on, the companion
and the RTX fixes' ARC9 patch from this branch, through `out/r25/poc_r25.py` (snapshot, move-aside, rollback). What the
user saw, and why:

- **The gun not path traced.** The RTX runtime path traces a frame up to its first 2D draw or its first read of the back
  buffer (the fork finishes the image there for the game to read), puts the image into the target bound then, and
  rasterizes everything after it. ARC9's `PreDrawViewModel` reads the screen every frame for its sight blur
  (`arc9_fx_adsblur_bleeding`, on by default), just before the engine draws the gun: the gun, the hands and the
  attachments were rasterized in every frame, unlit by the scene. Remix's albedo debug view showed it: the ARC9 M249
  shaded, the stock SMG flat. ARC9's customization background, its blur options and its translucent pass draw or read
  there too.
- **A black copy of the scope.** ARC9's sight blur draws the scope again every frame, black with a white lens, into a
  mask target whose format the render guard answers with its inert target; the draws went into the image.
- **The magnified scope.** ARC9 renders a second view of the world into a render target and puts it on the lens through
  screen-space shaders RTX cannot run (the user's guard lines): the error material, nothing magnified.

What changed (ADR 0136, `patcher/addons/cl_arc9.lua` in the fixes part):

- **The scope's picture is path traced.** The patch draws the lens with a render target of its own
  (`nativeloader_arc9_scope_v1`, 1016 x 508) whose descriptor hash it adds to `rtx.raytracedRenderTargetTextures`: rays
  that hit the lens go on from the scope's camera, which one empty triangle a frame gives the runtime, with ARC9's field
  of view, so no second view of the world is drawn. The lens copy's texture coordinates are its place in ARC9's
  picture, so the magnification is ARC9's; the reticle is drawn over it in 2D where ARC9 would have drawn it; a lens
  nobody looks through is black. `rtx_patcher_arc9_scopes 0` gives ARC9's own scopes back;
  `rtx_patcher_arc9_scope_status` prints the state.
- **The gun is path traced.** ARC9's 2D draws and screen reads before its view model, and the reads in its translucent
  pass, do nothing under RTX; the patch reads the screen in GMod's `PreDrawEffects` instead, once the view models are
  drawn, so ARC9's HUD and its own scope picture stay rasterized over the image as before. The sight blur is skipped.

The PoC runs found five things the reading of the sources had not:

1. **GMod names no `IMAGE_FORMAT_BGRX8888`.** The patch passed nil as the target's format, and the render guard answered
   with its 1 x 1 inert target (the first two runs reported "the scope target is 1 x 1"). The unit harness had defined
   the global; it now mirrors GMod. The patch passes Source's value, 16, which the guard reviews.
2. **A screen-sized target counts as the screen.** With ARC9's read before the gun skipped, the frame's first 2D draw
   ended path tracing; while aiming with ARC9's own scope picture that draw went into ARC9's full-frame scope target,
   so the frame's image did too, and the screen stayed black (HUD only). ARC9's HUD also draws its hints and an ammo
   card in perspective, which the runtime then traced as a lit white card in front of the gun. Both are answered by the
   read after the view models (and one just before ARC9's own scope picture, for a frame whose view model was not drawn).
3. **The engine draws ARC9's view model twice a frame**, in its opaque and its translucent pass, each with ARC9's hooks
   (the lens count ran at twice the reticle count). A read in the first `PostDrawViewModel` rasterized the second draw:
   a black lens and a shaded scope in the packaged build's first check. The read moved to `PreDrawEffects`, which runs
   once after all view models.
4. **The view model's render bounds are not the gun.** The FA:S M249's reach 171 units ahead (its whole animation), so
   the scope's camera sat at its cap (it starts past the gun's front, because rays going on from the lens can meet the
   view model, which the runtime draws at a quarter of its size). The gun's front is now taken from the view model's
   attachment points (its muzzle among them) and the parts ARC9 draws; the camera's cap is 24 units, its floor ARC9's
   own near plane of 8.
5. **The hash formula is right, and literal sizes are kept.** Targets of 1024 x 512, 1016 x 508, 1000 x 1000 and
   2048 x 128 were each flagged by Remix's debug view with the hash computed for them, and wrong descriptions were not.
   The target is 1016 x 508 so that no other target shares its description.

The packaged build, nothing injected (`verify -f`, the final one: `out/r25/qa-verify-f` in the `r25` worktree; RTX at
1280 x 720, the window unfocused, other work on the machine; `verify -e` before it gave the same without the
holosight step):

| Check | Result |
|---|---|
| A held icon whose panel is hidden | Dragging false a second later (the companion's hook loaded) |
| ARC9's own scope picture first (`rtx_patcher_arc9_scopes 0`, the patch's target never made) | The scene on the screen, the lens ARC9's error material as before R25, the gun path traced; 18.1 ms a frame |
| The patch's scope (`rtx_patcher_arc9_scopes 1`) | The view through the ELCAN path traced at 2.8x with its reticle; the lens flagged as a raytraced render target in Remix's debug view 821; the scope and the gun path traced in the albedo view (23); the picture follows a 60-degree turn; 10.6 ms a frame |
| The scope's camera | 14.2 units ahead: the M249's `muzzle_suppressor` attachment 48.6 units ahead (its muzzle 41.3) x 0.25 + 2 |
| From the hip | The gun and hands path traced and lit by the sky, ARC9's HUD rasterized as before (no card in the world); 10.1 ms a frame |
| ARC9's customization view | The gun path traced (albedo view) |
| An EoTech 553 holosight, aimed | Its reticle in its window; the sight and the gun path traced (albedo view); 10.1 ms a frame |
| The lens count | Twice the reticle count: two view model draws a frame, both path traced |

The first run of the branch (`vm`, before the screen reads were skipped) is the "before": in its albedo view the
customization view's gun is shaded, rasterized. `out/r25/r25-before-after.png` puts before and after side by side.

## Review

Two independent Claude reviews. The first, of the branch before the PoC runs, found 19 problems; all but the
2D reticle's occlusion were fixed or recorded:

| # | Finding | Answer |
|---|---|---|
| 1 | 1x, collimator and forced-cheap RT sights got the expensive scope's field of view: 0.75x at 16:9 | Cheap sights keep ARC9's own answer and show the view 1:1 (`ScaleFOVByWidthRatio(F, ScrH()/ScrW())`) |
| 2 | The hash goes into the runtime's user layer; a save from the RTX menu writes it to `user.conf` | Recorded in ADR 0136 (the package never writes `user.conf`; the line is harmless); a session-only option would need a runtime change, not made |
| 3 | Additive reticles were never detected (`$additive` is a bit of `$flags`) | Read from `$flags`; harness scenario `additive` |
| 4 | `arc9_fx_rt_alwaysdraw` was read when the file loaded, before ARC9 makes it | Read when needed; harness scenario `always-draw` |
| 5 | The runtime has one render-to-texture camera a frame | Recorded in ADR 0136 |
| 6 | The 2D reticle ignored roll, the fix angle and the eye-offset placement, and clamped coordinates warped it | Placed as ARC9 places it, triangles cut to its square; not hidden by hands passing in front (recorded) |
| 7 | An error after the camera's push left the scope target bound | The camera is always ended and the target popped; scenario `camera-error` |
| 8 | Lua garbage per lens vertex every frame | Buffers reused, a vertex cap |
| 9 | The integrated-scope path was not tested | Scenario `own-lens` |
| 10 | GPU cost while aiming (lighter G-buffer variants dropped) | Measured: frame times through the scope at the hip's (below) |
| 11 | The gun can appear in the scope picture | The camera starts past the gun's front (PoC finding 4) |
| 12 | No way out if a runtime describes the target differently | `rtx_patcher_arc9_scope_hash` |
| 13 | Attachments scaled with `RenderMultiply` | The lens copy takes the part's scale |
| 14 | Bodygroups ignored for the lens mesh | The bodygroup mask is part of the mesh and its cache key |
| 15 | Rays through the lens copy also hit the black lens behind it | The copy sits 0.1 unit in front; motion-vector smearing under DLSS recorded |
| 16 | The camera and black-lens textures shared hashes with every identical texture | A 16-pixel target of the patch's own |
| 17 | The customization view's 2D background rasterized the gun; `cam.IgnoreZ` there made the camera triangle sky | 2D skipped before the view model; `IgnoreZ` lifted for the triangle |
| 18 | The drag fix could cancel a drop onto a spawn list (the source panel hidden for a frame) | Two frames hidden with the button up |
| 19 | An error in another add-on's drag callback turned the drag fix off | `StopDragging` protected, the drag always cleared |

The second review read the code added after the PoC runs began (the screen reads, the translucent pass, the read in
`PreDrawEffects`, the target's size). It confirmed the restore logic, the arguments of the translucent pass, the
hash of 1016 x 508, the square projection and the runtime's use of `frac(uv)` over the whole frustum, and found:

| # | Finding | Answer |
|---|---|---|
| 1 | ARC9's holosights read the screen inside each view model pass: in the first pass that rasterizes the second (every attachment and the hands drawn again over the path-traced gun while a red dot is aimed; a black lens on a scope with a piggyback dot) | Holosights kept from the last pass and drawn after the read; scenario `deferred`; PoC with the EoTech 553 (below) |
| 2 | ARC9's lens flares are 2D draws from `ViewModelDrawn` (a light or laser facing the eye, always for `Flashlight360`) | The view model's flares kept and drawn after the read, like the holosights; flares of other players' lights and lasers, drawn before the view models, left as they are (recorded) |
| 3 | The engine may copy the screen before a view model whose own materials refract (a scope built into the view model) | Not checked; recorded in ADR 0136 |
| 4 | The runtime keeps a frame's first render-to-texture camera, not its last | ADR 0136 corrected; nothing took the scope's camera in the PoC |
| 5 | Translucent parts that sample `_rt_PowerOfTwoFB` see a stale copy | Under RTX such parts are path traced, not drawn by their refract shader; left |
| 6 | Nits: the target's name after two size changes, a lost traceback, a duplicate read, the section header | The name is new in R25 (no player has an older target of it); the header comment rewritten |

## Tests

`tools	est.ps1 -Config Release` passed on the final tree, rebased on `main`: repository conventions, 29 of 29 C++
tests and 752 Python tests, among them [`test_arc9_scope.py`](../../tools/tests/test_arc9_scope.py.md) (20 scenarios),
[`test_stuck_drag.py`](../../tools/tests/test_stuck_drag.py.md) (10) and R24's
[`test_arc9_patch.py`](../../tools/tests/test_arc9_patch.py.md). The packaged build was checked in the PoC after the
last change that reached the game (`verify -f`, above); each earlier PoC run is in the list of findings.

## Published (2026-11-09 UTC)

`main` was pushed at `eba469e`, rebased on the skills commits that had landed meanwhile. The merge's hook built the
package here and uploaded it to item 3829070317 as **0.0.0-dev.20261109063824+42d02ecc** (2,182,395,122 bytes, SHA-256
`e78660144190ebec8e5b605e760c1e995b13045dfba3a4eb512b97abac290639`); Steam's public record shows that size, updated
06:38:57 UTC. The push's hook found the same inputs and uploaded nothing. No GitHub Action was started. The drag fix
and the ARC9 patch reach players with the Workshop item; the loader is unchanged (0.16.0).

## Not changed

- The loader and the RTX runtime: no change.
- With `rtx_patcher_arc9_scopes 0` ARC9's own scope picture is drawn as before R25 (the error material on the lens
  under RTX), now without a black screen and with the gun path traced.
- The 2D reticle is not hidden by what passes in front of the lens; ARC9's night vision, thermal and eye-relief shadow
  inside its picture are not shown; the customization view loses ARC9's darkened background.
