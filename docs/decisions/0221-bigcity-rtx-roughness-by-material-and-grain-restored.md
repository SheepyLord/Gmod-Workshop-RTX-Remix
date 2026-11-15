# 0221: BigCity RTX's roughness set by material, and the grain its upscale lost put back

- Status: Accepted 2026-11-14
- Decided by: the user ("Revise the big city PBR and update to
  https://steamcommunity.com/sharedfiles/filedetails/?id=3839835474, the old enhancement is rejected as it makes
  everything looks plastic"), on the item the user had uploaded with the build of
  [0211](0211-other-authors-map-mods-as-content-packs.md). Claude chose how to revise it.
- Builds on: [0211](0211-other-authors-map-mods-as-content-packs.md) (other authors' map mods as content packs).

## Context

- BigCityRTX "Gmod Hashes Update" (skurtyyskirts) was made with PBRFusion. Its roughness maps are PBRify
  RoughnessV2's raw output: they correlate 0.995 with that model run on the mod's albedo, and 0.84-0.98 with the
  albedo's brightness. Every material sat near 0.5 (means 0.45-0.63; brick 0.42-0.57). This project's
  remasters use 0.66-0.95 for brick, concrete and plaster. Under the sky the path tracer drew facades, pavement
  and cobbles with a pale, sky-blue sheen.
- The normals are PBRify NormalV3's too. They are indistinguishable from a fresh run, and fine.
- The albedo's colour matches the game textures (median brightness ratio 0.99). But the upscale smoothed the grain
  of the ground textures. Box-downsampled to the source's size, the albedos kept a median 0.53 of the source's
  fine detail on cobbles, 0.69 on concrete and 0.47 on pavement. In the field, the cobbles' local contrast was
  0.018 against stock's 0.029. Smooth stone reads as plastic too.

## Decision

1. **Roughness by material class.** Each material's game texture is found by its hash; its path picks a class
   (facade, skyline, brick, concrete, plaster, stone, metal, wood, decal kinds, ground, ...). The roughness map,
   made again with PBRify from the mod's albedo, is normalised to its 2nd-98th percentile and mapped into the
   class's range: brick 0.74-0.95, concrete 0.68-0.94, plaster 0.78-0.94, cobbles 0.60-0.90, painted metal
   0.45-0.85. The values follow the remix-map-pbr skill's standards. Normal slopes are scaled by class: brick 1.3,
   cobbles 1.4, distant skyline facades 0.7.
2. **Glass in painted windows.** 35 facades have an albedo alpha that is HL2's window mask (`$basealphaenvmapmask`,
   0 on the panes). On those, the panes get roughness 0.12 and a flat normal. The panes are the near-black,
   solid regions of the alpha. The first upload took everything below one half, which made the grey, grungy
   panels of `building_template006b` glossy in blotches; the final build does not.
3. **Grain put back** on the 92 albedos that kept less than 0.8 of the source's fine detail (and still correlate at
   least 0.7 with it), by back-projection: the albedo plus the bicubic upscale of the source minus the albedo's
   downsample. The upscale's sharp edges stay.
4. **Left as the mod had them:** the sky, weapons, the Combine soldier, glass, a lamp, a black effect and a plastic
   sheet (18 materials), and 3 materials no game texture names. Displacement too: the mod has none.
5. **The same package**: id `bigcity-rtx`, folder `bigcity_rtx`, sizes unchanged (3.85 GB). The method is the
   workshop-content-pack skill's `retune_roughness.py --restore-grain`; pitfall 34 and step 5 of "Another
   author's map mod" make the check part of every such port.

## Consequences

- In the field (2026-11-14, five views, old build, new build and Remix's replacements off in one session each),
  the facades keep their colour, the windows reflect the sky, the sidewalk glare is gone, and the cobbles' local
  contrast is 0.030 against stock's 0.029 (old build: 0.018).
- The textures are still the mod's work with changes. The description says what changed, and the page credits the
  author as before.
- The mod's materials apply to HL2 textures wherever they are drawn (0211). Other maps that use those textures
  get the same revised roughness.

## Alternatives considered

- **Remap the mod's own roughness without PBRify:** the mod's maps correlate 0.995 with a fresh run, so the
  result is nearly the same, and the skill script does that by default. The build used a fresh run
  (`--ai-dir`), which also gives normals without the old files' BC5 compression to scale.
- **Re-upscale the albedo from the game textures:** would replace the author's work wholesale. The
  back-projection keeps the author's upscale and adds back only what it lost.
- **Leave the albedo alone:** the cobbles still looked smooth and pale next to stock after the roughness fix
  (local contrast unchanged at 0.018).
