# Material rules for repbr_map_mod.py

One JSON file per map: the material classes of the map's style and which textures belong to each.
[repbr_map_mod.py](../scripts/repbr_map_mod.py.md) reads it with `--rules`.

| File | Map | Style |
|---|---|---|
| [vvmall.json](vvmall.json) | gm_vvmall (Valley View Mall) | a kept-up mall: polished stone and terrazzo floors, satin paint, matte ceilings, glazed tiles, black painted railings, brushed metal |
| [funkis.json](funkis.json) | gm_funkis | a mid-century house among pines: oiled and lacquered wood, white plaster, board-formed concrete, glazed tiles; a green forest floor and grey rock rebuilt from the map's own textures; painted and bare metal in the lab |
| [estate.json](estate.json) | rp_countryestatev1 | a country manor: lime plaster, stone, cobbles, brick, roof tiles; polished wood, panelling, marble and carpets inside |

## Format

```json
{
  "note": "what the map should look like",
  "skip_flags": ["translucent", "additive", "selfillum"],
  "classes": {"brick": {"rough": [0.72, 0.95], "normal": 0.15, "cavity": 0.35, "height": 0.003}},
  "scan_rules": [["^nature/milground002$", "ground_grass"]],
  "rules": [["^tools/|^glass/", "skip"], ["brick", "brick"], ["^models/", "prop"], [".", "generic"]],
  "overrides": {"0123456789ABCDEF": "metal_bare"}
}
```

- `classes`: a recipe per class (the keys and their defaults are in repbr_map_mod.py.md). `keep`, `scan`
  and `skip` always exist and keep the author's maps, only sized.
- `rules`: ordered `[regular expression, class]` pairs, matched case-insensitively against the texture path in
  lower case, without `materials/` and `.vtf` (`concrete/concretefloor016a`,
  `models/props_c17/furniturecouch001a`). The first match wins; end with a catch-all.
- `scan_rules`: the same, for materials whose albedo is the author's own asset outside `SubUSDs` (CC0 scans).
  Those keep their maps unless a scan rule names them: use it where the author gave a surface the wrong scan
  (Funkis' main grass and cliffs were dark mud; a white popcorn ceiling in Country Estate was dark rock).
- `skip_flags`: VMT flags (from [map_usage.py](../scripts/map_usage.py.md)) that keep a material as the
  author made it: glass, signs and lights are usually translucent, additive or self-illuminated.
- `overrides`: a class per material hash (the re-keyed `mat_<HASH>`), for single textures the rules get wrong.

## Writing one

1. `repbr_map_mod.py --plan-only --json plan.json`, then read the classes of the materials with the most
   importance; `sheet` and `--preview` show the albedo next to the game texture and the new maps lit.
2. Ranges follow the remix-map-pbr skill's "Roughness by finish": matt plaster 0.80-0.95, concrete 0.66-0.93,
   polished stone and glazed tile 0.06-0.30, satin wood 0.28-0.58, fabric 0.85-1.0. The normal target is the
   mean |xy| of the unit normals: 0.01-0.02 for polished or printed surfaces, 0.03-0.06 for paint and
   plaster, 0.12-0.18 for brick, cobbles and rock.
3. Give foliage and distant props a low `weight` (their model boxes are large) and `max_side` 2048.
4. Check in the field: the floors at a grazing angle, a sunlit wall, and every class against the build before
   and Remix's replacements off.
