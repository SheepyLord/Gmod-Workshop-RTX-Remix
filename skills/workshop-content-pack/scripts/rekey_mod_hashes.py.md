# rekey_mod_hashes.py

Re-keys a Remix mod made with Remix's default texture hash (XXH3) to the hash the RTX package uses (XXH64),
so its materials apply under the package. Edits the mod's text layers in place (each atomically).

```powershell
$K = '<repo>\skills\workshop-content-pack\scripts'; $C = 'H:\SteamLibrary\steamapps\workshop\content\4000'
python -I "$K\rekey_mod_hashes.py" --mod <ported mod folder> --source "$C\<map item>\<file>.gma" `
  --source H:\SteamLibrary\steamapps\common\GarrysMod\sourceengine\hl2_textures_dir.vpk --source <more *_dir.vpk> `
  --cache <out>\vtf-cache.json --json <out>\rekey-report.json [--dry-run]
```

## Why

The RTX package's classic defaults set `rtx.useObsoleteHashOnTextureUpload = True`: the runtime keys every
replacement material by XXH64 of the texture's top mip. A mod authored in a Remix setup left at the default
keys them by XXH3 of the same bytes, and none of its materials ever applies under the package. Seen on
2026-11-12: skurtyyskirts' Valley View Mall, Funkis and Country Estate mods (2025) matched 0 of their maps'
textures by XXH64 and 303-402 by XXH3; his BigCity "Gmod Hashes Update" and HamzaPOPO's map pack were XXH64.
Run a `--dry-run` on any mod from outside this project: it says which hash it uses.

## What it does

1. Hashes every VTF of the sources both ways ([vtf_hash.py](vtf_hash.py.md)): the map's Workshop item (its
   loose textures and BSP pakfiles) and the `*_dir.vpk` of GMod and the games it mounts (stock textures a map
   reuses). `--cache` keeps each source's table for the next mod.
2. Sorts the mod's `mat_<hash>` prims: **re-keyed** (an XXH3 some source explains), **already XXH64**, or
   **not explained** (a texture of a source not given, a format the game converts in a way not tried, a
   material for another map). Only the first are changed.
3. Renames them everywhere in the text layers (`mat_<XXH3>` as a prim name and in every path that names it,
   such as `material:binding`). Refuses (exit 1, nothing written) when a new name would clash with a material
   already there or with another renamed one, and when a binary layer names a material it would have to
   rename.

## Options

`--mod` (required), `--source` (repeatable, required), `--cache`, `--json` (the lists and the renames),
`--dry-run` (report only).

## Exit codes

0 done (or a dry run, or nothing to rename); 1 refused (no `mod.usda`, a missing source, a clash, a binary
layer to rewrite); 2 bad command line.

## The 2026-11-12 runs

| Mod | Materials | Re-keyed | Already XXH64 | Not explained |
|---|---|---|---|---|
| Valley View Mall RTX | 420 | 418 | 0 | 2 |
| Funkis RTX | 448 | 440 | 0 | 8 |
| Country Estate RTX | 413 | 402 | 0 | 11 |
| BigCity RTX | 356 | 0 | 353 | 3 |
| Map Pack RTX's seven maps | 23-297 each | 0 | 15-295 | 0-8 |

Sources each time: the map item, GMod's `garrysmod_dir.vpk` and `sourceengine\*_dir.vpk`, Half-Life 2's and
Counter-Strike: Source's VPKs (F:\SteamLibrary). Tests: [test_rekey_fit.py](test_rekey_fit.py.md).

## Provenance

Written by Claude for this user on 2026-11-12. Standard library plus `xxhash`; not third-party code.
