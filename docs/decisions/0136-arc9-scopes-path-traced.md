# 0136: ARC9's magnified scopes path traced through a raytraced render target; ARC9's gun path traced

- Status: Accepted 2026-11-09 (R25, the user's items 2 and 3)
- Context: the user, after R24: "Mod weapons are not rendered ray-traced and does not affected by environment lights,
  the shading looks incorrect for both the weapon and the accessories, the scopes on the weapon." and "Magnified
  scopes does not work, there is bug in rendering and when zooming." Their screenshot: an ARC9 M249 with a magnified
  scope whose lens showed the error material, and the render guard's lines for `cl_vm.lua:479/483` (ARC9's depth of
  field mask) and `cl_pipscope_new.lua:387/388, 689/690` (its scope's FXAA and lens shader).
- Builds on: [ADR 0135](0135-view-model-materials-and-arc9.md) (the ARC9 patch, R24) and the render guard's inert
  targets ([ADR 0086](0086-inert-shader-effects-and-safe-guard-fallbacks.md)).

## What ARC9 does, and what RTX makes of it

- **What ends path tracing for a frame**: the RTX runtime path traces the scene up to the first draw it takes for UI
  (a fixed-function draw with an orthographic projection and no depth writes, or one with a UI texture, into a target
  of the screen's size; `d3d9_rtx.cpp`, `internalPrepareDraw`) or up to the first read of the back buffer
  (`StretchRect` or `GetRenderTargetData` from it, `d3d9_device.cpp`: the fork finishes the image there for the game
  to read), puts the path-traced image into the target bound at that point, and rasterizes everything after it over
  the result. ARC9's `PreDrawViewModel` copies the screen every frame for its sight blur
  (`render.UpdateScreenEffectTexture` and a copy into `arc9_prevm`, with `arc9_fx_adsblur_bleeding`, on by default), so
  the gun and the hands were rasterized in every frame: the weapon the user saw unlit by the scene, its accessories and
  scopes shaded wrongly. Its customization view also draws a full-screen 2D background there, its blur options
  (`arc9_fx_rtblur`, `_reloadblur`, `_animblur`, `_inspectblur`, `arc9_cust_blur`) a full-screen quad, and its
  translucent pass copies the screen (`render.UpdatePowerOfTwoTexture`) before the view model's translucent parts.
- **A magnified scope** (ARC9's "new scopes") is a second view of the world: in `PreRender` ARC9 pushes its target
  `arc9_optic_main` and calls `render.RenderView` with the scope's field of view, a square of the screen's height in the
  middle; after the view models it pushes that target again and draws the reticle, shadows and black bars into it,
  runs a lens shader into `arc9_optic_shaderpass` and gives that to `effects/arc9/rt`, a Refract material on the lens
  that samples it at the lens's place on the screen. Its "cheap" sights (collimators, 1x sights, `arc9_cheapscopes`)
  zoom the whole view and copy the screen instead. RTX cannot run the screen-space shaders (the guard drops them), and
  the path tracer does not show a render target's picture: the lens showed the error material, and nothing was
  magnified.
- **ARC9's sight blur** (`arc9_fx_adsblur_new`, on by default) draws the scope model again every frame an RT scope is
  the active sight, black with a white lens, into its mask target `arc9_optic_dof_mask2`. Its format (I8) makes the
  guard hand ARC9 its inert target, whose push the guard refuses; the draws inside went on, into the image itself: a
  black copy of the scope over the real one.
- **ARC9's HUD** draws its hints and its ammo card in perspective (`cam.Start3D` in `HUDPaint`): a perspective draw is
  not UI to the runtime, so whatever ends path tracing must come before it, or the runtime traces the HUD as lit objects
  in the world (in the PoC a white card in front of the gun, until the read after the view model below).

## Decision

1. **The scope's picture is path traced** (`patcher/addons/cl_arc9.lua`, section 4, in the fixes). The RTX runtime
   (the user's fork) has raytraced render targets: a surface textured with one is a window, and rays that hit it go
   on from the camera that drew into that target (`rayCreateRenderTarget`: from the camera's position, through the
   surface's texture coordinates). Under RTX, from the first time a magnified scope is used:
   - the patch makes its own target, `nativeloader_arc9_scope_v1`: 1016 x 508, Source's BGRX8888 (16: GMod names no
     `IMAGE_FORMAT_BGRX8888`, and nil made the guard hand back its 1 x 1 inert target), its own depth buffer; the
     camera draws a 508-pixel square of it, and nothing samples its pixels. The size is unusual on purpose: every
     target with the same D3D9 description has the same hash, and the runtime would treat it as raytraced too. The
     patch adds the target's descriptor hash (XXH3-64 over its D3D9 description, `0x9F721457A944740A`; confirmed in the
     PoC, where Remix's debug view flagged the lens for targets of four sizes and for no wrong description) to
     `rtx.raytracedRenderTargetTextures` through `RemixConfig.SetConfigVariable`; a hash set reads additively into the
     runtime's user layer, beside the hashes already there. `rtx_patcher_arc9_scope_hash` replaces the hash if a
     runtime ever describes the target differently;
   - ARC9's `RenderRT` keeps the view ARC9 would have rendered instead of rendering it: ARC9's own field of view for a
     magnified scope, and for a cheap sight the view's own (ARC9 shows its zoomed view 1:1 there);
   - in the view model pass one empty triangle (no area) is drawn into the target with that camera: the runtime takes
     the target's camera from whatever is drawn into it, so no second view of the world is drawn. The camera starts
     past the gun's front (the furthest along the view of the view model's attachment points, its muzzle among them,
     and of the corners of the parts ARC9 draws, times the runtime's view model scale 0.25, plus 2 units; at least
     ARC9's own near plane of 8, at most 24; the view model's own render bounds cover its whole animation, 171 units
     ahead for the FA:S M249, and a point more than 128 units from the eye is not where ARC9 draws this frame), because
     the runtime draws the view model within a few units of the eye and rays going on from the lens can meet it. The triangle is depth tested
     (and `cam.IgnoreZ` lifted for it in the customization view): a draw without a depth test into such a target counts
     as sky and is dropped;
   - the scope part is drawn with its lens black (ARC9 blacks a lens nobody looks through) through
     `render.MaterialOverrideByIndex`, and while the scope is looked through, a copy of the lens mesh (at the pose and
     `RenderMultiply` scale ARC9 gave the part, bodygroups included) is drawn 0.1 unit in front of it, textured with
     the target; its texture coordinates are its place on the screen in ARC9's square, so the window shows what ARC9's
     picture would have shown there, at ARC9's magnification. The black lens and the camera triangle use a 16-pixel
     target of the patch's own as their texture: a shared white or black file texture has the hash of every identical
     texture, and a category the fixes gave it would reach them all;
   - the reticle (the scope's `RTScopeReticle`, colour, scale and fix angle) is drawn over the lens as 2D from ARC9's
     own `DrawRTReticle` call (its `RenderScreenspaceEffects` hook, after the view model): each lens vertex's place on
     ARC9's reticle square (the ray from the eye through it with ARC9's 90-degree camera, met with the square's plane),
     the lens triangles cut to the square, faded in with the sight as ARC9 darkens its picture until then.
   A scope built into the weapon's own view model (`SWEP.RTScope`) gets the same through `PreDrawViewModel` and
   `ViewModelDrawn`. `rtx_patcher_arc9_scopes 0` turns this off (ARC9's own scopes, as before);
   `rtx_patcher_arc9_scope_status` prints its state.
2. **ARC9's gun is path traced: path tracing ends right after it** (section 5). While ARC9's `PreDrawViewModel` runs,
   `surface.DrawRect`, `surface.DrawTexturedRect`, `render.DrawScreenQuad`, `render.DrawScreenQuadEx` and the screen
   reads (`render.UpdateScreenEffectTexture`, `UpdateFullScreenDepthTexture`, `UpdateRefractTexture`,
   `UpdatePowerOfTwoTexture`, `CopyRenderTargetToTexture`, `CopyTexture`) do nothing (put back afterwards, also after an
   error), and so do the reads while its `DrawTranslucentPass` draws the view model's translucent parts. What the
   skipped copies fed (the sight blur) is skipped too: `RenderDoFMask` and `RenderDoF` do nothing. In GMod's
   `PreDrawEffects`, which runs once all view models are drawn, the patch reads the screen once in a frame whose copy
   it skipped (not in ARC9's own scope view or a preset's camera), so path tracing ends there, on the screen: the gun,
   the hands, the translucent parts and the muzzle flashes are path traced, also in the customization view and with
   the blur options on, and everything ARC9 draws after its view models (its HUD, partly in perspective, and its own
   scope picture into its screen-sized target) is rasterized over the image, as before. The engine draws ARC9's view
   model twice a frame, in its opaque and its translucent pass, each with ARC9's hooks: in the PoC a read after the
   first `PostDrawViewModel` rasterized the second (a black lens, a shaded scope). ARC9 draws its holosights
   (`DoHolosight`, which reads the screen first) and the view model's lens flares (`DrawLightFlare` for the view
   model: 2D) inside each pass, where either would end path tracing before the next pass: the patch keeps those of the
   frame's last pass and draws them after the read, with the view model's camera, so the holosights' stencilled
   reticles and the flares are rasterized as before. When ARC9 draws its own scope picture (the scopes above off, or a
   runtime that did not take the target), the screen is also read just before ARC9's `DrawRTReticle`, for a frame
   whose view model was not drawn: in the PoC, before the read after the view models, the screen stayed black while
   aiming, the frame's image in ARC9's target. All with `rtx_patcher_arc9` on.

## Not done

- The 2D reticle is not hidden by what passes in front of the lens (hands during a reload in the sight); it fades with
  the sight. Effects ARC9 draws into its picture (night vision, thermal, the eye-relief shadow, range finders' 2D draw
  functions) are not shown, and the customization view loses ARC9's darkened background.
- The scope's camera starts past the gun's front: what is closer to the eye than that (8 to 24 units, a gun's length
  at the runtime's view model scale) is not seen through the scope.
- Screen reads in an attachment's own draw functions (`DrawFunc`, during the view model) are not looked for: one would
  end path tracing before the rest of the gun, as ARC9's own copy did. Lens flares of other players' lights and lasers
  (drawn before the view models) are left as ARC9 draws them: one facing the camera ends path tracing before the gun
  for that frame. The engine may copy the screen before a view model whose own materials need it (a scope built into
  the view model with a refracting lens material); not checked.
- A session-only runtime option for the hash (as ADR 0121's categories have) would need a runtime change; not made.

## Consequences

- **The runtime's user layer holds the scope target's hash** after the first magnified scope of a session: the RTX
  menu then counts a changed setting, and saving the RTX settings from its menu writes that one line into the player's
  `user.conf` (as the fixes' settings set through `RemixConfig` do). The package never writes `user.conf`; the line is
  harmless (no other target has that description), and players who never use a magnified scope never get it.
- **The runtime has one render-to-texture camera a frame, the first drawn** (`RtCamera::update` keeps a frame's first):
  the scope's is drawn in the view model pass, so a raytraced render target drawn into earlier in the frame would give
  the lens its camera. The package's defaults list one other target (`0x6FFDC1AC626F4AA6`, whose description R25 could
  not match); nothing took the scope's camera in the PoC.
- **One screen copy a frame while an ARC9 weapon is drawn** (the read after the view models), where ARC9 itself made
  one every frame before (its sight blur's): no more copying than before.
- While the scope's camera is valid the runtime gives up some of its lighter G-buffer variants for the frame
  (`rtx_pathtracer_gbuffer.cpp`); the PoC measured the frame time (R25 report). Rays through the window carry the
  runtime's known approximation of motion vectors, so the picture can smear under DLSS while panning.
- A runtime without raytraced render targets or without `RemixConfig` leaves ARC9's own scopes in place, as before.
- The patch is GPL-2.0 like the rest of the fixes part.
