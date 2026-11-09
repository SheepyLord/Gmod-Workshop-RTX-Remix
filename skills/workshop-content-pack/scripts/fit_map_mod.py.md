# fit_map_mod.py

Splits a map remaster's Remix mod into Workshop-sized parts and fits each part under a byte budget,
without re-encoding a texture. Written for the Backrooms remaster (2026-11-09): its `gm_br_rtx` mod is
14.25 GB (3,712 DDS for 1,127 materials over two maps), and one Workshop item may hold about 4 GB.

A remix-map-pbr remaster's mod is `mod.usda`, `materials.usda` (one `over "mat_<HASH>"` block per
texture hash, written by the pipeline's `build_mod.py`) and `textures/*.dds`. The script:

1. **Splits by map.** Each block's texture is looked up by its hash (else by its `# <name> (<class>)`
   comment) in the pipeline's `work/textures.json`; its `materials` and `work/inventory.json` say which
   maps draw it. A block goes to the first `--part` whose maps use it, so the first part of a two-map
   remaster takes everything its map uses (shared textures included) and the second only what the
   other map alone uses. Blocks no part's maps use are left out; blocks with no map information go to
   the first part (both counted in the output).
2. **Shrinks without re-encoding.** Every DDS of these mods holds its full mip chain, and the encoder
   made each mip from the full-size image, so a texture at half size is the same file without its top
   mip: the header (width, height, top-level size, mip count) is rewritten and the rest copied byte for
   byte. A BC4/BC5 map whose top mip is one block repeated, holding one value per channel (a flat
   metallic, roughness, height or normal map), keeps only its tail from 16 px down: it samples the same
   value everywhere, exactly as before. Byte-identical files are written once (checked by SHA-256) and
   the blocks point at the kept copy; constant maps of one value and size merge too.
3. **Fits each part under its budget**, tier by tier. A tier is applied to the least important
   textures first and stops as soon as the part fits; a later tier runs only when the earlier ones were
   not enough:

   | Tier | Cut | Least important first |
   |---|---|---|
   | `aux` | roughness, metallic and height maps at half the size of their albedo | models by instance count, then world textures by area share |
   | `props` | model (prop) textures at most twice their source VTF's size (albedo, normal, emissive; their aux maps follow) | instance count |
   | `world` | world textures above 2048 at 2048 | share of the world's brush area |
   | `prop-nrm` | model normal maps at half the size of their albedo | instance count |
   | `world-nrm` | world normal maps at half the size of their albedo | area share |
   | `halve` | every texture halved again, round by round, down to `--min-side` | as above |

   The order is a judgement of what shows least: roughness and height detail first, then the second
   doubling of a 4x model upscale, then the largest world textures that cover least of the map. A
   shared file takes the largest size any of its users still wants.
4. **Writes** each part as a mod folder named like the folder given (its name is the deployed name
   under `rtx-remix\mods`): `mod.usda` (the source's, with the part's `lightspeed_mod_name` and a `doc`
   saying where it came from), `materials.usda` (the part's blocks in source order, references
   rewritten to the kept copies) and `textures\`. Nothing else, so the folder is what
   `tools\package_content.py --mod` takes. Each part is written to `<folder>.partial-<pid>`, checked
   (re-parsed; every reference present, no unreferenced file, every DDS of the planned size and mip
   count) and only then moved into place.

```powershell
$W = 'H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed\.claude\worktrees\rtx-remix-map-enhancement-bda9ac'
$O = '<repo>\out\packages\gm-br-rtx'
python -I scripts\fit_map_mod.py --mod "$W\garrysmod\rtx-remix\mods\gm_br_rtx" `
  --textures-json "$W\source\gm_br_rtx\work\textures.json" --inventory-json "$W\source\gm_br_rtx\work\inventory.json" `
  --part "$O\complex\gm_br_rtx=gm_br_complex" --part "$O\pitfalls\gm_br_rtx_pitfalls=gm_br_pitfalls" `
  --mod-name "gm_br_rtx_pitfalls=The Backrooms - Complex RTX: gm_br_pitfalls" --report "$O\fit-report.json" [--dry-run] [--force]
```

## Options

| Option | Meaning |
|---|---|
| `--mod DIR` | the remaster's mod folder (`mod.usda` whose one sublayer is `./materials.usda`, `materials.usda`, `textures\`) |
| `--textures-json`, `--inventory-json` | the pipeline's `work\textures.json` (per texture: `w`, `h`, `world`, `share`, `instances`, `hashes`, `materials`) and `work\inventory.json` (`materials.<name>.maps`) |
| `--part FOLDER=MAP[,MAP]` | an output part and the maps it serves, in order (repeatable, at least one) |
| `--budget BYTES` | bytes of every file a part writes (default 3,850,000,000: room for a Lua add-on and the archive's index under 4 GB) |
| `--part-budget NAME=BYTES` | another budget for one part |
| `--mod-name NAME=TEXT` | the part's `lightspeed_mod_name` (default: the source's) |
| `--min-side N` | no non-constant map is cut below N pixels on its longer side (default 128) |
| `--report FILE` | JSON: per part its budget, the lossless and fitted sizes, each tier's textures cut and bytes saved, and every file with its source and output size, mip levels dropped, constant flag, merged duplicates and the materials using it |
| `--dry-run` | plan, print and report; write no part |
| `--force` | replace a part folder this script wrote before (one holding only `mod.usda`, `materials.usda` and `textures\*.dds`); any other folder is refused |

## Limits

Block-compressed 2D DDS only (BC1-BC7, DX10 or legacy FourCC headers); a file without a mip chain
cannot be cut and stays as it is. Constant detection covers BC4 and BC5 (the single-channel and normal
maps; a BC7 albedo is never flat in practice). A mod with other sublayers than `materials.usda`
(`lights.usda`, `meshes.usda`) or an asset outside `textures\` is refused. Byte sizes are exact: the
budget check counts the files as they are written.

## Side effects and exit codes

Reads the mod and the two JSON files; writes only the part folders (and `--report`), never a game
install. Standard library only; runs with `python -I`. Exit 0 written (or planned with `--dry-run`),
1 refused or a budget out of reach (nothing written for any part), 2 bad command line.

## Verified (2026-11-09)

- `gm_br_rtx` into `gm_br_rtx_complex` (gm_br_complex: 540 materials, shared ones included) and
  `gm_br_rtx_pitfalls` (587 materials only gm_br_pitfalls uses): 7.517 GB and 6.652 GB of source files,
  7.318 and 6.552 GB after the lossless step (118 constant maps, 92 of them metallic, as 22 tails; one
  group of identical files; 28 unreferenced files left out), fitted to 3,844,053,569 and 3,841,452,232
  bytes. Part 1 took `aux` for
  all 539 textures, `props` for all 304 models and `world` for the 17 lowest-share of 41 world
  textures above 2048; part 2 `aux` for all 587 and `props` for the 282 least-placed of 416 models.
  13 s with the files in the cache.
- 30 cut files, every format and size class, decoded by Pillow equal the source's own mip of the same
  size pixel for pixel; constant files decode to the source's single value.
- In the game (PoC, 1920x1080, the remaster's own add-on and 16 of its cameras, each view wide and
  zoomed 3x, shot twice): the packages against the full mod differ by a median 0.94 of 255 (wide) and
  0.81 (zoomed), two sessions of the full mod by 0.78 and 0.68; median fine detail kept 99.3%, lowest
  92.6% (gm_br_pitfalls' cistern). Both packages deployed with `nlctl apply` and loaded with no Lua error.
- [test_fit_map_mod.py](test_fit_map_mod.py.md): 10 tests on generated mods.

## Provenance

Written for this user by Claude (2026-11-09) for the Backrooms Workshop upload. Not third-party code;
it reads the GPL fork's pipeline outputs (JSON) but holds none of its code.
