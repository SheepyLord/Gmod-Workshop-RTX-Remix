# map_usage.py

Where each texture of a map shows: its share of the world's area (floor, wall, ceiling) and of the props, read
from the map item's BSP. A module (imported by [repbr_map_mod.py](repbr_map_mod.py.md), which sizes textures by
it) and a command:

```powershell
python -I map_usage.py --source <map item .gma/.bin or .bsp> [--source <*_dir.vpk> ...] --json <out.json>
```

## What it does

1. For every BSP in the first source, sums the faces' area per material from the faces lump's own `area` field.
   Sky, sky2d, nodraw, hint, skip and trigger faces and `tools/` materials are left out. The face's plane says
   floor (normal z above 0.7), ceiling (below -0.7) or wall. VBSP's cubemap copies
   (`maps/<map>/<material>_x_y_z`) and blend copies (`_wvt_patch`) count as their material, and a name Hammer
   stored from the root (`/cleancobblestreet_texture`) is normalised like a VMT path. Faces whose material has
   no VMT in the sources are listed in `unmatched` with their share of the area, and the command prints them:
   before that normalisation Country Estate's custom materials got no weight and their textures were planned
   at 256 px (2026-11-15).
2. Reads every VMT and MDL in all the sources (the map item with its BSPs' pakfiles, then the VPKs; the first
   copy found wins). A material's `$basetexture` takes its area; a blend's `$basetexture2` takes half.
3. Overlays and decals: the BSP's overlays (lump 45: posters, signs and stains placed on brushes, each with the
   area of its four UV points) and its `infodecal` entities (64 x 64 units each) weigh their material as wall
   area. They lie on faces already counted, so the world's total area leaves them out.
4. Props: the game lump's static props and the models the entities name (`"model" "models/..."`). Each counts
   its instances times the surface of the model's view box (the hull when that is empty), shared among its
   textures. The texture is found by trying the MDL texture name under each `$cdmaterials` folder, then the VMT's
   base texture. Half the box counts as seen.

The JSON maps each texture (lower case, no `materials/`, no `.vtf`) to `world`, `floor`, `wall`, `ceiling`
and `props` (per cent of the world's area), `models` (model: instances), `vmts`, `shader`, `surfaceprop` and
`flags` (`translucent`, `alphatest`, `additive`, `selfillum`, `envmap`, `basealphaenvmapmask`, ...). It also
holds `maps`, `world_area` and `unmatched`.

`importance(entry)` weighs a texture for a size budget: 1.5 x floor + wall + 0.6 x ceiling + props. Floors are
seen closest, ceilings least.

## Exit codes

0 written; 1 a missing source or no BSP in the first source; 2 bad command line.

## Side effects

Writes `--json` only.

## Measured (2026-11-15)

| Map | Textures used | Most weight |
|---|---|---|
| gm_vvmall | 455 | whiteplaster1 19.2, valley_view_center_tile001a 17.7, vvmall_greyplaster 17.2 |
| gm_funkis | 600 | arbre01_sway 30.7 and distant_trees 19.1 (big tree boxes: the rules weigh foliage down), milground002 15.7 |
| rp_countryestatev1 | 543 | grassfloor002a 14.1, infskybox02 11.2, ah_foliage_sheet001 8.1 |

Tests: [test_map_usage.py](test_map_usage.py.md).

## Provenance

Written by Claude for this user on 2026-11-15. Standard library only. The BSP, VPK, GMA and MDL layouts are
Valve's published formats (the Valve Developer Community's BSP and MDL pages). Not third-party code.
