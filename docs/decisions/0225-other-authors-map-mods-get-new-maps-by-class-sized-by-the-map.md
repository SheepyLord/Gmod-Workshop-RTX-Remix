# 0225: Other authors' AI-made map mods get new maps by material class, every texture sized by where it shows

- Status: Accepted 2026-11-15
- Decided by: the user ("Retune the other three skurtyyskirts packs too, you don't have to trust the original,
  make the materials look better and have more details, which fit the map's structure and style"), for Valley
  View Mall, Funkis and Country Estate RTX (built in [0211](0211-other-authors-map-mods-as-content-packs.md), not
  uploaded). Claude chose the method, the classes and the sizes.
- Builds on: [0211](0211-other-authors-map-mods-as-content-packs.md) (other authors' map mods as content packs),
  [0221](0221-bigcity-rtx-roughness-by-material-and-grain-restored.md) (BigCity's roughness by material).

## Context

- The three mods were made with PBRFusion: PBRify's 1x NormalV3 and RoughnessV2 run on the 4x-upscaled albedo.
  The 1x models see every feature at four times the size they were trained on.
  - **Normals nearly flat.** Measured at the top mip, as the mean |xy| of the unit normals on a 512 px centre
    crop: Valley View Mall's drywall 0.009, its main floor tile 0.027, its grey plaster 0.025. The terrazzo
    floors were 0.13-0.14, bumpy where polished terrazzo is flush. A 256 px mip hides all of it.
  - **Roughness near 0.5 everywhere** (means 0.49, 0.45 and 0.42).
- **The fit cut what shows most.** At 7.9-8.7 GB each, `fit_mod.py` fitted them to one 3.85 GB item by
  size. It cut the top mip of 160-250 textures, the main floors and walls among them.
- **Two of the author's scans do not fit their surfaces.** Funkis' main grass (21 % of the map's ground) and
  its cliffs' rock were given dark mud scans: in the field the forest floor was pale, flat and grey.
  Country Estate's white popcorn ceiling was given a dark rock scan.
- **Funkis' trees glowed bright green.** The author's subsurface scattering on foliage had a measurement
  distance of 1.5-3.7 where this project's remasters use 0.05.

## Decision

1. **New maps by material class, in each map's style**, from a rules file per map
   (`skills/workshop-content-pack/rules/<map>.json`; regular expressions on the game texture's path, the
   author's CC0 scans kept unless a scan rule names them, glass, signs and lights kept by their VMT flags):
   - Valley View Mall: a kept-up mall. Polished stone tile 0.10-0.30 with rough grout and a height map,
     terrazzo 0.18-0.40 and flush, satin paint, matte ceiling tiles, glazed tiles, painted and brushed metal.
   - Funkis: a mid-century house in a pine forest. Oiled and lacquered wood, plaster, board-formed concrete,
     a forest floor and rock.
   - Country Estate: a manor. Lime plaster, stone, cobbles, brick, roof tiles; polished wood, panelling,
     marble and carpets inside.
2. **Made at the game texture's scale.** PBRify NormalV3, RoughnessV2 and Height run on the albedo at twice the
   source's side (512-2048 px, wrap-padded for world textures). Each class then sets:
   - the normal's mean slope as a target, with relief from the albedo's fine detail added;
   - the roughness range, rougher in the height's hollows, with soft smudges on polished floors;
   - height maps with `displace_in` 0.0015-0.004, on world floors and walls of tile, brick, stone, cobbles,
     rock and ground only.

   The author's albedo stays, with the game texture's grain put back where the upscale lost it (0221).
3. **Every texture sized by where it shows**, from the BSP: floor, wall and ceiling area and props (instances
   times the model's box), with overlays and decals counted as wall. A material with no known usage
   (unnamed, or drawn by something the BSP does not list) gets half the median importance, not none. The
   planner gives each doubling by weight per byte, so the main floors and walls keep 4096 within 3.85 GB.
4. **Rebuilt from the map's own textures** where the author's scan is wrong for the surface: Funkis' grass
   and rock, Country Estate's popcorn ceiling. PBRify UpscalerV4 upscales them 4x, then the class's maps are
   made. Foliage scattering is set to 0.05 wherever the author set it.
5. **Tools in the workshop-content-pack skill**, with tests: `repbr_map_mod.py`, `map_usage.py`, the rules
   files and pitfall 35, plus step 6 of "Another author's map mod". `usd_refs.prim_spans` gives a material
   only the inputs inside its own braces. The old reader had given Country Estate's wooden column the
   textures of the garden gnome mesh that follows it.
6. **Not uploaded**: the packs stay local until the user decides, as in 0211. The package ids, folder names,
   map items and credits are unchanged. Each description says what changed.

## Consequences

- Valley View Mall, field check of 2026-11-15 (ten spots, the round-2 build, the new one and Remix's
  replacements off):
  - The center court's tiles, the terrazzo walkways and the dark lower level mirror the store windows,
    railings and lights as a polished floor does; the old build and stock are matte.
  - The stucco walls show more relief.
  - The map drew 337 of the 345 materials with new maps.
- Funkis: the forest floor is green grass with needles and twigs where it was flat grey. The author's wood
  rooms, leaf litter and concrete keep their scans.
- Each pack is 3.85 GB, as before.
- Not the packs' doing, seen during the check: 7 of 18 field starts with the RTX package of 2026-11-15
  02:58 UTC (`0.0.0-dev.20261115025852+1145e794`) ended with `engine.dll`+0x34b9dc (0xC0000409):
  - six at the level change, just after the RTX fixes' module shut down;
  - one 3 s after Remix had loaded its mods.

  The four BigCity sessions of 2026-11-14 on the package before (`...20261114214127+c7ab57a1`) had none,
  and the field install verified vanilla. Reported to the user.

## Alternatives considered

- **Retune roughness only (0221's tool):** leaves the flat normals and the fit's cuts. The user asked for
  more detail.
- **Fit by size, then retune:** the fit cut the main floors to 2048 and kept props nobody sees at 4096.
- **Re-upscale every albedo from the game textures:** replaces the author's work wholesale. The author's
  upscales are good; only two surfaces had the wrong texture.
- **Split each map over two items:** the user asked for one package per map (0211).
