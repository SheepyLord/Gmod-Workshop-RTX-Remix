# retune_roughness.py

Gives another author's map mod physical roughness. Each material's roughness map is remapped into the range of its
material class; on facades the painted window panes become glossy glass. With `--restore-grain` it also puts back
the game textures' fine grain where the mod's upscale smoothed it away; otherwise the albedo is not touched. The
result is a new mod folder, a hard-linked copy of the old one in which only the rewritten maps are new files.

```powershell
python -I "$K\retune_roughness.py" --mod <B>\<map>_rtx --out <B>\v2\<map>_rtx --source "$C\<map item>\<file>" `
  --source <*_dir.vpk> ... [--rules rules.json] [--ai-dir <PBRify maps>] `
  [--restore-grain [--grain-ratio 0.8] [--grain-corr 0.7]] [--work <folder>] `
  [--json <B>\retune-report.json] [--dry-run] [--force]
```

## Why

Mods made with PBRFusion (BigCity RTX's "Gmod Hashes Update", skurtyyskirts) ship PBRify's raw maps. Their
roughness correlates 0.995 with PBRify RoughnessV2 run on the mod's albedo (48 BigCity materials, 2026-11-14) and
0.84-0.98 with the albedo's brightness. It was never mapped to physical values, so it sat near 0.5 on everything
(0.45-0.63 per material; brick 0.42-0.57). Under the sky the path tracer drew brick, concrete, plaster and cobbles
with a pale, sky-blue sheen. The user rejected that: "it makes everything looks plastic". The normals are PBRify's
too; their look was fine. This project's remasters set roughness per finish (remix-map-pbr, "Roughness by
finish").

## What it does

1. Names each material's game texture by its hash in the sources ([vtf_hash.py](vtf_hash.py.md), both hash
   functions). Reads every text layer reached from `mod.usda` ([usd_refs.py](usd_refs.py.md)) for each `mat_<hash>`
   prim's `diffuse_texture`, `normalmap_texture` and `reflectionroughness_texture`, taken from inside the
   prim's own braces (`usd_refs.prim_spans`; since 2026-11-15: a mesh replacement's material that follows a
   material's block had been read as that material's).
2. Picks a class by the texture's path: ordered regular expressions, the first match wins. The defaults were written
   for HL2's city textures:

| Class | Roughness | Normal gain | Textures (path contains) |
|---|---|---|---|
| skip | the mod's | the mod's | `skybox/`, `models/weapons/`, `models/combine_soldier/`, `models/player`, `effects/`, `glass/`, glass windows, lights, `sprites/`, `particle/` |
| facade | 0.64-0.92, panes 0.12 | 1.0, panes flat | `building_template/` |
| skyline | 0.55-0.88 | 0.7 | `Composite/`, `buildings/gen*`, skybox buildings |
| brick | 0.74-0.95 | 1.3 | `brick/` |
| concrete | 0.68-0.94 | 1.0 | `concrete/`, pavement, curbs, cement |
| plaster, wallpaper | 0.78-0.94, 0.62-0.86 | 0.8 | `plaster/` |
| stone (cobbles) | 0.60-0.90 | 1.4 | `stone/` |
| slate, roof tile | 0.35-0.70, 0.58-0.88 | 1.0, 1.2 | `tilefloor`, `tileroof` |
| wood | painted 0.46-0.80, floor 0.42-0.75, rough 0.65-0.90 | 1.0-1.1 | `wooddoor`, `woodfloor`, `woodwall`, `wood/` |
| metal | 0.45-0.85 | 1.0 | `metal/`, `dev/`, doors, fences |
| decals | graffiti 0.55-0.85, paper 0.74-0.93, signs 0.45-0.78, stains 0.62-0.92 | 0.6-0.8 | `decals/` by name |
| ground, carpet, tar paper, slime | 0.80-1.00, 0.86-1.00, 0.74-0.95, 0.30-0.75 | 0.8-1.2 | by name |

   `--rules FILE` (JSON: `{"classes": {"name": [lo, hi, gain]}, "rules": [["regex", "class"], ...]}`) adds classes
   and replaces the rule list. A material no source names, or no rule matches, keeps its maps; the report lists
   it.
3. Per material: the roughness (the mod's map, or `--ai-dir\<HASH>_rough.png`) is normalised to its 2nd-98th
   percentile and mapped into the class's range. On a facade whose albedo alpha marks window panes, the panes get
   roughness 0.12 and a flat normal. The alpha is HL2's `$basealphaenvmapmask`: 0 on the panes, either two-level
   or graded with grey, grungy panels (`building_template006b`). The panes are the near-black texels (below
   0.1, 2-60 % of the texture) that survive an opening (5 px minimum, then maximum) at 80 % or more. Scattered
   dark grunge is no pane, and grey panels stay matte. An earlier rule, below one half, gave
   `building_template006b`'s panels glossy blotches. The normal map is rewritten only when the gain is not 1, there are panes, or
   `--ai-dir` gives PBRify normals (`<HASH>_normal.png`, DirectX): its slopes are scaled and it is written in
   Remix's octahedral encoding.
4. With `--restore-grain`: decodes each retuned material's source VTF (top mip of the first frame; DXT1/3/5
   through Pillow's DDS reader, 8-bit RGB(A) layouts directly). It box-downsamples the mod's albedo to the
   source's size and compares their fine detail (luminance minus a 2 px Gaussian blur). If the albedo kept
   less than `--grain-ratio` (0.8) of the source's detail and still correlates at least `--grain-corr` (0.7)
   with it, the source's grain goes back by back-projection: the albedo plus the bicubic upscale of (source
   minus that downsample). The upscale's edges stay and the alpha is kept. A texture the author replaced (a
   scan) correlates less and is left alone. Smooth, grainless pavement and cobbles read as plastic even with
   the right roughness.
5. Writes the PNGs to `--work` (default `<out>.work`) and encodes them with the RTX Remix Toolkit's NVTT exporter
   through rpai's `dds` module ([skills/mmd-remix-pbr/tool](../../mmd-remix-pbr/tool/README.md)): BC4 roughness,
   BC5 normals and BC7 albedo, each at the size the old file had. They replace the hard links in `--out` as new files, so `--mod`
   is never written.

`--dry-run` only classifies and counts (`--json` then lists each material's texture and class). `--json` after a
run lists per material the class, range, gain, old and new mean roughness and the panes' share.

## Exit codes

0 done (or a dry run); 1 refused (no `mod.usda`, a missing source, `--out` exists without `--force` or is not a
mod folder, a rule class without a range, no NVTT exporter); 2 bad command line.

## Side effects

Creates `--out` (with `--force`, first removes an earlier output that has a `mod.usda`) and `--work`. Never writes
`--mod`. Runs `nvtt_export.exe` in up to six processes.

## The BigCity run (2026-11-14)

356 materials. 335 were retuned, 18 skipped by rule (sky, weapons, the Combine soldier, glass, a light, a black
effect, a plastic sheet), and 3 had no source. The 35 `building_template` and courtyard facades with window masks
got glossy panes (8-59 % of the texture). Mean roughness went from 0.554 to 0.743. Grain was restored on 92
albedos: 762 files in all, 125 s. The archive stayed 3.85 GB, and the files keep their sizes.

The build on item 3839835474 is this script's output with `--ai-dir` and `--restore-grain`. The `--ai-dir` maps
are PBRify run on the mod's albedo by `out\pbr-maps\bigcity_repbr.py` in the worktree
`gmod-pbr-maps-packaging-b6de9c`. Before the opening rule, the same run had matched that worktree's scratch build in
1068 of 1070 files. Tests: [test_retune_roughness.py](test_retune_roughness.py.md).

## Provenance

Written by Claude for this user on 2026-11-14. numpy and Pillow, rpai's `dds` module (this repository, MIT) and the
Toolkit's NVTT exporter; the octahedral encoding is the Toolkit's published maths, as in rpai. Not third-party code.
