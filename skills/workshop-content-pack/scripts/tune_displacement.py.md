# tune_displacement.py

Tones down a mod's parallax displacement in place: none on model and decal textures, a cap on world
textures. Only the `displace_in` values of its text layers change; textures and every other input stay.

```powershell
python -I "$K\tune_displacement.py" --mod <B>\<map>_rtx --source "$C\<map item>\<file>.gma" `
  --source <*_dir.vpk> ... [--world-max 0.008] [--json <B>\displacement-report.json] [--dry-run]
```

## Why

Remix draws a material that has a height map and `displace_in` above 0 with parallax occlusion mapping, as if
the surface were `displace_in` times one texture repeat deep. HamzaPOPO's Map Pack RTX sets 0.05 on nearly every
material (up to 0.145), props and decals included. In the field (2026-11-13) Abandoned Mall's floor tiles drew as
stacked, smeared blocks, its debris props tore along their UV seams, and Jupiter Underground's walls smeared and
its floor grew spikes; the user pointed at the ground. This project's remasters keep 0.0006-0.008 on world floors
and walls and no displacement on models (remix-map-pbr, "Height maps").

## What it does

1. Names each material's game texture by its hash in the sources ([vtf_hash.py](vtf_hash.py.md), both hash
   functions): a texture under `materials/models/` is a model texture, one under `materials/decals/` a decal,
   anything else, or a material no source names, counts as world.
2. Rewrites each `float inputs:displace_in = <v>` inside a `mat_<hash>` prim: 0 for model and decal materials,
   `min(v, --world-max)` for world ones. Each layer is rewritten atomically; `--dry-run` only counts.

Prints how many materials of each kind changed and how many already were within the limits; `--json` lists every
change (kind, texture, old and new value).

## Exit codes

0 done (or a dry run); 1 refused (no `mod.usda`, a missing source); 2 bad command line.

## The 2026-11-13 runs (`--world-max 0.008`)

| Pack | Models to 0 | Decals to 0 | World capped | Within limits |
|---|---|---|---|---|
| Abandoned Mall RTX | 58 | 32 | 116 | 5 |
| Jupiter Underground RTX | 65 | 0 | 231 | 1 |
| Alley Triste RTX | 73 | 0 | 38 | 6 |
| Old Russian Sauna RTX | 48 | 0 | 25 | 0 |
| Gold Dust RTX | 0 | 0 | 31 | 0 |
| Backrooms RTX | 1 | 5 | 17 | 0 |
| Dark Forest RTX | 7 | 2 | 6 | 0 |
| Pool Day RTX | 0 | 0 | 20 | 1 |

The skurtyyskirts packs and Safehouse RTX were left alone: they bind height maps on few materials, and their
views showed no parallax faults. Tests: [test_rekey_fit.py](test_rekey_fit.py.md).

## Provenance

Written by Claude for this user on 2026-11-13. Standard library plus `xxhash` (through vtf_hash); not
third-party code.
