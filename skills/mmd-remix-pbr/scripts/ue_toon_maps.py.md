# ue_toon_maps.py

Converts an Unreal toon-shader texture set (Neverness to Everness style: `T_..._d`, `T_..._m`,
`T_..._id`) into grey **roughness and metallic maps** for rpai's per-texture `rough_map` /
`metal_map` settings. The game has no roughness or metallic map; its toon material reads a LightMap
(`_m`: R specular intensity, B specular size) and an ID map (`_id`: red 0 marks skin). The rules are an
interpretation measured on Elyms' four outfits (2026-11-03), not the shader's own maths; they are in
the script's header:

- gloss = clip(B / 0.62); roughness = 0.78 - 0.60 gloss - 0.20 clip(R / 0.40), clipped to 0.10-0.85;
- skin (ID red below 24/255): roughness 0.70, metallic 0 (the standard for skin on a shared sheet);
- metallic = smoothstep(R, 0.22, 0.36), only on bright silver or gold paint; metal texels get
  roughness at most 0.30.

```powershell
& $py ue_toon_maps.py --d T_x_d.png --m T_x_m.png --id T_x_id.png --out-dir <dir> --name Clothes_1
```

Then, in the per-model preset:
`"textures": {"Clothes_1.png": {"normal_map": "<T_x_n.png>", "rough_map": "<dir>/Clothes_1_rough.png", "metal_map": "<dir>/Clothes_1_metal.png"}}`
with the sheet's classes at `normal` 1.0 (tool README, "The game's own maps"). A set whose LightMap is
the default grey (`T_Linear_Gray`) has nothing to convert: give only its normal map.

## Inputs and outputs

| Argument | Meaning |
|---|---|
| `--d` | the base colour (`T_..._d`) |
| `--m` | the LightMap (`T_..._m`); the outputs take its size |
| `--id` | the ID map (`T_..._id`) |
| `--out-dir` | where to write (created) |
| `--name` | the output name stem, usually the sheet's name |

Writes `<out-dir>/<name>_rough.png` and `<out-dir>/<name>_metal.png` (8-bit grey) and prints the
roughness percentiles and the metal and skin shares. Nothing else.

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`): it needs numpy,
Pillow and scipy. Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)).

## Exit codes

0 on success; 1 on an unreadable image (Python's error); 2 for a bad command line (argparse).

## Provenance

Written for this user by Claude in the Elyms session (2026-11-03) in the installed copy of this skill;
copied into the repository on 2026-11-08 unchanged.
