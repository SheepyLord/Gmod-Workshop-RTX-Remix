# 0138: Imported game materials glow where their game's emission map does

- Status: Accepted 2026-11-09 (the user, asked after [ADR 0137](0137-endfield-npc-weapon-and-item-maps.md):
  "Yes, make them glow"); within the imported game maps of
  [ADR 0091](0091-automatic-pbr-fallbacks.md) and [ADR 0098](0098-compact-imported-game-maps-and-recipe-keys.md).
- Context: ToPBR converts a game family's emission map (Arknights: Endfield and Silver Palace `_E`; WuWa ships
  none it uses) and its materials wrote `emissive_mask_texture` and `emissive_intensity`, but never
  `enable_emission`. The runtime's default for that input is off (`rtx_material_data.h:65`), and with it off a
  material's emissive intensity is 0 (`rtx_materials.h:970`); no runtime patch changes that for these materials
  (0019 enables emission for eye whites only). So no imported game emission map ever glowed.

## Decision

1. **An imported game material with an emission map is written with `bool inputs:enable_emission = 1`**
   (`WriteOpaqueMaterial`, the fixes' ninth native patch `game-emission.patch`). World conversion (vanilla
   ToPBR, off by default) keeps its emission off; a game material without an emission map gets no flag.
2. **The intensity stays the game record's fixed 1.** An `_E` map is non-zero only on the parts the game lights:
   in the AKEF pack's 40 converted emission maps, a median of 0.6 % of texels (at most 16 %, Laevatain's sword),
   lit texels at 0.3-0.9. At intensity 1 those parts are clearly bright in daylight (the PoC's daytime
   `adapted_yf` about 0.115 at exposure 1.5: a lit texel at about 0.6 to 7 times middle grey before tonemapping) and
   glow at night (exposure at its cap of 16). A fixed emitter is what a lit part is, so the scene-adaptive input
   of [ADR 0067](0067-scene-adaptive-emission.md), made for anime eye whites that must look the same in every
   light, is not used.
3. **Nothing converts again.** The flag lives in the USD layer ToPBR publishes, which it writes again whenever
   the content changes; the converted maps, the recipe tag and the game registry are unchanged.
4. `tools/ci/pins.json` records the patch and the patched tree, so GitHub's package workflow builds the same
   module; the patch's folder keeps the complete files, the native regression and a README.

## Consequences

Endfield's glowing parts (weapon runes, tech lines, lights) and Silver Palace's emissive details glow under
path tracing, in every imported character that ships the map, from the next session. They also light the
scene a little, as emissive surfaces do in Remix. The fixed intensity is not tuned per material: a part may
look stronger or weaker than in the game; a per-family intensity, or an adaptive one, can follow if the user
finds one too bright or too dim. Saved manual choices with an emission map glow too.

## Alternatives considered

- **Scene-adaptive emission** (ADR 0067's `emissive_adaptive_intensity`): the same glow in noon and at night,
  which suits eye whites, not lit equipment; it would also need a tuned ratio per game.
- **The runtime's default intensity of 40**: far brighter than the game; kept at the record's 1.
- **Enabling it for world conversion too**: not what the user chose, and Source `$selfillum` materials have
  their own look.
