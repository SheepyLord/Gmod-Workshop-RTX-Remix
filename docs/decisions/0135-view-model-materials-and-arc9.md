# 0135: View model materials through the material pipeline; an ARC9 patch

- Status: Accepted 2026-11-08 (R24, the user's item 2)
- Context: the user: "Make fixes related to the first person view models, especially custom ones. In ARC9, custom view
  models has incorrect shading and material processing. Also, suppress the ARC9 compatibility warning about the game
  setting." Their screenshot: an ARC9 M249 with a white plate z-fighting on the receiver and a black square in a green
  frame. Reproduced in the PoC with [ARC9] Gunsmith Arms: Source's M249, its sticker slots holding the Firearms:
  Source sticker and the Kill Counter charm (RESEARCH.md, R24).

## Decision

1. **The material pass for view models** (`remixlua/cl/cl_viewmodel_materials.lua`, fixes part). The material pipeline
   saw the map at load and an entity's materials when it was created; a weapon's view model is one entity whose model
   changes with every weapon switch, and weapon bases draw attachments as client-side models. Twice a second the pass
   checks the local view models, the hands and the active weapon's attachment models (ARC9, TFA and the SWEP
   Construction Kit, CW 2.0, ArcCW) and sends each material it has not seen through the Lua fixers, the BlueFlyTrap fix
   and the auto-categorisation (decal, emissive, particle): once per material, at most 4096 a session.
2. **The ARC9 patch** (`patcher/addons/cl_arc9.lua`, in the fixes' RTXPatcher):
   - ARC9's DirectX check answers "fine" in RTX sessions (RTX runs Source at level 80; ARC9's advice, `-dxlevel 95`,
     does not apply to a path-traced renderer). ARC9's own `arc9_ignore_dx` and its other checks are untouched;
     `rtx_patcher_arc9_dx_warning 1` shows the warning again.
   - Under RTX a client-side model's `SetMaterial`/`SetSubMaterial` does not change what draws (R7), and ARC9 dresses
     stickers (whose models carry only a missing material: the white plate) and gun screens that way. While ARC9 draws
     its custom models, those parts (known from ARC9's own tables: a sticker's `StickerMaterial`; a gun screen charm's
     index 2) are skipped by ARC9 and drawn at the pose it gave them through `render.MaterialOverrideByIndex`, which
     does reach the image. The sticker materials also go through the material pass (a decal).
     `rtx_patcher_arc9_parts 0` turns this off. Only the parts ARC9 itself draws in that call are drawn so (the R24
     review): none when it returns early (a world model while an RT scope renders or at LOD 2, where only the base
     model draws and the parts keep a stale pose; an NPC's or a distant player's view model), the preset's own models
     for a preset icon, and never a charm (its parent draws it), an animation proxy or a translucent part (ARC9's
     translucent pass draws it).
   - Gun screens show a render target, black in the path-traced image: the companion's toolgun screen redraw takes
     them from a provider (`NativeLoaderScreens.Register`, or the providers table the companion keeps when the patch
     applies first) and draws them as 2D after upscaling; a provider that fails leaves only its screen out.
3. **Not done.** The flat look of every view model (fixed-function DX7 shading drops normal maps and phong) is RTX's
   shading model: PBR maps for weapons would be authored replacements or ToPBR, which stays the player's choice
   (`rtx_topbr_enabled`, R19). Changing the DirectX level servers see was declined
   ([ADR 0133](0133-the-multiplayer-notice-in-the-companion.md)).

## Consequences

- The patch is GPL-2.0 like the rest of the fixes part.
- A weapon base whose parts are dressed some other way still draws them as before; its attachment models get the
  material pass.
