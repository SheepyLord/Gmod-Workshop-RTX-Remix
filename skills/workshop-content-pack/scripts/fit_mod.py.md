# fit_mod.py

Fits any Remix mod folder under one Workshop item's budget by leaving out top mips, without re-encoding.
For mods from outside this project's remaster pipeline, which [fit_map_mod.py](fit_map_mod.py.md) cannot
read (it needs the pipeline's `materials.usda` layout and its per-map inventory).

```powershell
python -I "$K\fit_mod.py" --mod <ported mod folder> --out <B>\<map>_rtx --source <map item> `
  --source <*_dir.vpk> ... --cache <out>\vtf-cache.json --report <B>\fit-report.json [--dry-run] [--force]
```

## What it does

1. Walks the mod with [usd_refs.py](usd_refs.py.md) (text and binary layers) and gives each referenced DDS
   its role from the material inputs that name it: albedo (`diffuse_texture`), normal, emissive, aux
   (roughness, metallic, height); a texture only a binary layer names is a model texture. With `--source`
   it also knows each material's game texture size ([vtf_hash.py](vtf_hash.py.md)), so it can tell an 8x
   upscale of a 256 px texture from a 2x upscale of a 2048 px one.
2. Lossless: a BC4 or BC5 map whose top mip holds one value keeps only its tail from 16 px.
3. Tiers, each only until the mod fits:

   | Tier | Cut | Order |
   |---|---|---|
   | `aux` | roughness, metallic and height maps at half their material's albedo side | largest file first |
   | `4096` | every texture above 4096 at 4096 | largest first |
   | `2048` | every texture above 2048 at 2048 | biggest upscale of its game texture first, then largest |
   | `normal` | normal maps at half their material's albedo side | as `2048` |
   | `halve` | everything halved again, round by round, down to `--min-side` | as `2048` |

   A cut is fit_map_mod's: the DDS header rewritten (size, top-level size, mip count) and the remaining mips
   copied byte for byte, so a cut texture is the original's own lower mip. Every layer and every other file
   is copied unchanged, at the same relative path.
4. Writes `--out` through `<out>.partial-<pid>`, checks the byte total equals the plan and every reference
   resolves, then renames it into place.

## Options

| Option | Meaning |
|---|---|
| `--mod`, `--out` | the mod to fit and the folder to write (its name is the deployed mod name) |
| `--budget` | bytes of every file of the result (default 3,850,000,000, fit_map_mod's) |
| `--min-side` | no texture is cut below this side (default 128) |
| `--source`, `--cache` | where the game textures' sizes come from (as rekey_mod_hashes.py) |
| `--report` | JSON: sizes before and after, each tier's count and bytes saved, every cut file (side, new side, roles, game side, constant) |
| `--dry-run`, `--force` | plan only; replace an existing `--out` |

## Exit codes

0 written or planned; 1 refused (a reference that does not resolve, `--out` exists without `--force`, the
budget out of reach at `--min-side`); 2 bad command line.

## The 2026-11-12 fits (budget 3.85 GB)

| Mod | Source | Fitted | Tiers |
|---|---|---|---|
| Valley View Mall RTX | 8.38 GB | 3.85 GB | aux 409 textures (1.26 GB), 4096 33 (1.36 GB), 2048 118 (1.91 GB) |
| Funkis RTX | 8.69 GB (8.54 lossless) | 3.85 GB | aux 407, 4096 22, 2048 206, normal 210 |
| Country Estate RTX | 7.95 GB (7.85 lossless) | 3.85 GB | aux 402, 4096 24, 2048 221, normal 91 |
| BigCity RTX | 3.99 GB | 3.85 GB | aux 51 |

(The table holds the dry runs before the game sizes were used; the final reports are in each build folder.)
Tests: [test_rekey_fit.py](test_rekey_fit.py.md).

## Provenance

Written by Claude for this user on 2026-11-12; reuses fit_map_mod.py's `Dds` and constant check. Standard
library; not third-party code.
