# arc9_scope_harness.lua

Runs the scope and screen-draw parts (R25) of the RTX fixes' ARC9 patch (`packages/fixes/.../patcher/addons/cl_arc9.lua`)
under LuaJIT, with a mocked patcher, `RemixConfig`, render targets, materials, `render`/`cam`/`mesh`/`surface`,
`util.GetModelMeshes`, vectors, angles and bone matrices (Source's axes), and an ARC9 weapon holding an RT scope part
(an ELCAN-like model: its lens at sub-material 3, one lens triangle bound to one bone, two bodygroups) next to an
ordinary part. Arguments: the patch file, a scenario.

| Scenario | Checks |
|---|---|
| `lens` | `RenderRT` keeps the scope's view (ARC9's field of view: `ScaleFOVByWidthRatio(90, 0.75) / 2` for 2x) and never runs ARC9's own picture; the targets are made once (the scope target 1016 x 508 with its own depth, flags 780, format 16: Source's BGRX8888, which GMod names no global for, so the harness defines none; a 16 x 16 black target, cleared) and the scope target's hash given to `rtx.raytracedRenderTargetTextures`; in `DrawCustomModel` ARC9 draws the receiver, the scope follows with its lens black, then the lens meshes (bodygroup mask 5), the camera triangle into the target (a 508-pixel square viewport, 8 units ahead: the parts reach 14 units, a quarter of it plus 2 is less than ARC9's 8) and the lens copy: lifted 0.1 towards the eye, texture coordinates its screen position in ARC9's square (hand-computed: the centre at 0.5, 0.5; a corner vertex at (880 - 350) / 900, 410 / 900 on a 1600 x 900 screen); every override reset; ARC9's `DrawRTReticle` call draws the reticle in 2D with each vertex's place on ARC9's reticle square (hand-computed: 0.7375, 0.38125) |
| `not-looking` | not looked through, or a view from an earlier frame: only the black lens |
| `off` / `no-runtime` | `rtx_patcher_arc9_scopes 0`, or no `RemixConfig.SetConfigVariable`: ARC9's own `RenderRT`, `DrawRTReticle` and loop drawing, no target made |
| `own-picture` | ARC9's own scope picture (scopes off): the screen is read just before ARC9's `DrawRTReticle` while the sight is up or `arc9_fx_rt_alwaysdraw` is on; not at the hip, not with the patch off |
| `cheap` | a cheap sight (ARC9's own answer): the view's own vertical field of view, so the lens shows ARC9's view 1:1 |
| `blur` | `RenderDoFMask`/`RenderDoF` skipped, ARC9's with the patch off |
| `screen-draws` | ARC9's 2D draws in `PreDrawViewModel` (customization background, blur) skipped and the functions put back, also after an error; ARC9's own with the patch off |
| `screen-reads` | ARC9's screen copies in `PreDrawViewModel` (`render.UpdateScreenEffectTexture`, `CopyTexture`, `UpdateFullScreenDepthTexture`, `CopyRenderTargetToTexture`) skipped and put back; ARC9's own with the patch off |
| `translucent-pass` | the view model's `DrawTranslucentPass` runs without `render.UpdatePowerOfTwoTexture`, a world model's with it; the function is put back after an error |
| `after-view-model` | the patch's `PreDrawEffects` hook reads the screen once in a frame whose ARC9 `PreDrawViewModel` ran (twice: the opaque and the translucent pass), nothing before it; not twice, not in a frame without ARC9's view model, not in ARC9's own scope view (`ARC9.RTScopeRender`) or a preset's camera, not with the patch off |
| `deferred` | ARC9's holosights (from its `PostDrawViewModel`) and the view model's flares (`DrawLightFlare` with its view model flag) are kept from the last of two passes, their vectors copied, and drawn after the read with the view model's camera; a world model's flare at once; the weapon's own `DoHolosight` put back, also after an error |
| `vm-attachments` | a view model whose render bounds reach 171 units ahead and whose muzzle attachment is 40 units ahead: the camera 12 units ahead (40 x 0.25 + 2); an attachment 5000 units away is left out |
| `far-part` | a part 5000 units away (not placed this frame) and one ARC9 marks `NoDraw` leave the camera at ARC9's 8 units |
| `own-lens` | a scope in the weapon's own view model: its lens black while the engine draws it, the override cleared in `ViewModelDrawn` and the copy drawn; nothing overridden when `PreDrawViewModel` hides the view model |
| `always-draw` | `arc9_fx_rt_alwaysdraw`, made by ARC9 after the patch loads, is read when needed |
| `additive` | an additive reticle (`$additive` in `$flags`) gets the additive material |
| `camera-error` | a failing camera draw still ends the camera and pops the target; the error is kept for the status command |
| `hash-override` | `rtx_patcher_arc9_scope_hash` replaces the built-in hash |
| `apply` | every function is intercepted on the base table (the translucent pass among them); a base without `RenderDoF` is no failure |

Prints `PASS <scenario>`; any difference is a Lua error (nonzero exit). Writes no files and launches no game. Run by
[`test_arc9_scope.py`](test_arc9_scope.py.md).
