# repbr_map_mod.py

New PBR maps for another author's Remix map mod, by material class in the map's own style, every texture
sized by where it shows on the map so the whole mod fits one Workshop item. The author's albedo stays (or,
where a class says so, the game's own texture upscaled 4x replaces it); normals, roughness and height are made
new. The result is a new mod folder; `--mod` is never written.

```powershell
& "$env:USERPROFILE\.rpai\venv\Scripts\python.exe" -I "$K\repbr_map_mod.py" --mod <B>\full\<map>_rtx `
  --out <B>\<map>_rtx --source "$C\<map item>\<file>" --source <*_dir.vpk> ... --rules "$K\..\rules\<map>.json" `
  [--budget 3850000000] [--max-side 4096] [--work <B>\repbr-work] [--json <B>\repbr-report.json] `
  [--plan-only] [--preview <folder> --only <name or hash>,...] [--force] [--workers 6]
```

`--mod` is the full-size port of the original, re-keyed (`port_classic_mods.py`, `rekey_mod_hashes.py`), not
a fitted one: the planner needs the author's top mips. Run it with rpai's Python (torch, spandrel, the PBRify
models: [skills/mmd-remix-pbr/tool](../../mmd-remix-pbr/tool/README.md)); `--plan-only` runs with any Python
that has numpy, Pillow and xxhash.

## Why

skurtyyskirts' mods (Valley View Mall, Funkis, Country Estate, BigCity; ModDB) were made with PBRFusion:
PBRify's 1x NormalV3 and RoughnessV2 run on the 4x-upscaled albedo. A 1x model sees the upscale's features at
four times the size it was trained on, so the relief came out nearly flat. Measured at full resolution on a
512 px centre crop (mean |xy| of the unit normals), Valley View Mall's drywall was 0.009, its main floor tile
0.027 and its grey plaster 0.025. Its terrazzo was 0.13-0.14, bumpy where polished terrazzo is flush. The
roughness sat near 0.5 on everything (mean 0.49, 0.45 and 0.42 for the three mods). Fitting each mod to one
item (`fit_mod.py`) then cut the top mip of 160-250 textures, the most visible floors and walls among them.
The user asked on 2026-11-15 for the three to look better and have more detail, in each map's structure and
style, without trusting the original.

## What it does

1. **Names and usage.** Each material's game texture by its hash in the sources (both hash functions,
   `vtf_hash.py`), and where it shows ([map_usage.py](map_usage.py.md)): floor, wall and ceiling area and
   props. Both cached in `--work` per set of sources.
2. **Class** from the rules file ([rules/README.md](../rules/README.md)), in this order:
   - a per-hash override;
   - `keep` for a texture no source names;
   - `skip` for a VMT flag in `skip_flags` (translucent, additive, self-illuminated: glass, signs, lights);
   - for the author's own assets (an albedo outside `SubUSDs`, mostly CC0 scans), the `scan_rules`, else
     `scan`;
   - else the first rule whose regular expression matches the texture path, else `keep`.

   `keep`, `scan` and `skip` keep the author's maps, only sized.
3. **Size plan** under `--budget` (default 3.85 GB) less 1 MiB for the layers' edits. Every texture starts at
   256 px, or smaller if it is smaller. The doubling with the most weight per added byte goes first: weight =
   `importance` x the class's `weight` x the role's (albedo 1, normal 0.8, roughness 0.3, height 0.25,
   metallic 0.15), divided by the doublings it already had. A material without known usage (unnamed, or drawn
   by something the BSP does not list) gets half the median importance of the placed ones: given almost none,
   about 150-190 materials per pack had shrunk to 256 px, posters, decals and a terrace floor among them. Each texture stops at the author's size and at
   `--max-side` (4096) or the class's `max_side`. Costs are exact: a block-compressed mip chain with its
   header. An author's DDS is cut by leaving out top mips (no re-encoding, as `fit_mod.py`); a one-value BC4
   or BC5 map keeps only its 16 px tail, which loses nothing.
4. **AI maps.** PBRify's NormalV3, RoughnessV2 and Height (rpai's `ModelRunner`, tiled, fp16) run on the albedo
   at the game texture's scale: twice the source's side, 512-2048 px. World textures get wrap-around padding,
   so the maps tile. A class with `from_source` first upscales the game texture 4x with PBRify UpscalerV4 (the
   alpha bicubic), and that becomes the albedo. All of it is cached in `--work/ai`.
5. **Compose** at the planned sizes, from the class's recipe:

| Key | Default | Effect |
|---|---|---|
| `rough` | 0.55-0.85 | AI roughness normalised to its 2nd-98th percentile and mapped into the range |
| `rough_from` | `ai` | or `albedo` (inverted luminance), `flat` (the middle of the range) |
| `normal` | 0.06 | target mean \|xy\| of the unit normals; the AI normal's slopes are scaled to it (0 = flat) |
| `detail` | 0 | relief from the albedo's fine detail (its 1.5 px high-pass as height, brighter is higher) added before scaling |
| `height` | 0 | on world textures: a height map from the AI height and `displace_in` |
| `cavity` | 0 | roughness raised toward 1 in the height's hollows (grout, mortar, cracks) |
| `smudge` | 0 | large, soft, tileable roughness variation (polished floors) |
| `envmask` | 0 | how far the VMT's base-alpha envmap mask lowers roughness |
| `metal` | 0 | `metallic_constant` (the author's metallic map is blanked) |
| `grain` | true | the game texture's grain put back by back-projection where the upscale smoothed it (`retune_roughness.restore_grain`: less than 0.8 of the source's high-pass kept, correlation at least 0.7) |
| `from_source` | false | the albedo is the game texture upscaled 4x, not the author's |
| `albedo` | none | `{"saturation", "exposure", "max"}` colour changes |
| `weight`, `max_side` | 1, none | the size plan's multiplier and cap |

6. **Encode and write.** The NVTT exporter through rpai's `dds` module encodes BC7 albedo, BC5 normals and BC4
   roughness and height, as `SubUSDs/<HASH>_repbr_<role>.<x>.rtex.dds`. The material inputs are rewritten in
   a copy of the author's layers (`set_inputs`: a value replaced with its metadata kept, or a line added). Every
   other file the layers reach is copied, sized as planned, and nothing else. The walk must then resolve every
   reference and the folder must fit the budget, or nothing is written.

`--plan-only` prints the classes and their bytes (`--json` lists each material's class, why, importance and
sizes). `--preview` with `--only` writes, per material, the whole albedo and 1:1 crops of the top size: the
author's albedo (when replaced), the new albedo, the author's normal lit by a grazing light, the new one lit,
the author's roughness, the new roughness and the height.

## Exit codes

0 done (or planned, or previewed); 1 refused (no `mod.usda`, a missing source, `--out` exists without
`--force`, the budget out of reach at the smallest sizes, a reference that does not resolve, the result over
the budget, no NVTT exporter); 2 bad command line.

## Side effects

Writes `--out` (through `<out>.partial`, renamed at the end) and `--work` (`names-*.json`, `usage-*.json`,
`ai/`; the PNGs it encodes are removed). Runs `nvtt_export.exe` in `--workers` processes and the PBRify models
on the GPU.

## Runs (2026-11-15)

The three skurtyyskirts packs in the worktree `gmod-pbr-maps-packaging-b6de9c` (`out\pbr-maps\build_round4.py`).
Valley View Mall: 420 materials, 345 with new maps, AI for 330 in 443 s on the RTX 5090, composed in 153 s,
742 maps encoded in 55 s. Tests: [test_repbr_map_mod.py](test_repbr_map_mod.py.md).

## Provenance

Written by Claude for this user on 2026-11-15. numpy, Pillow, rpai (this repository, MIT), the PBRify models
(Kim2091, CC0) and the Toolkit's NVTT exporter. The octahedral encoding is the Toolkit's published maths, as in
rpai. Not third-party code.
