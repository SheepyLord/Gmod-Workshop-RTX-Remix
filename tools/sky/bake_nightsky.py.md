# bake_nightsky.py

Makes the runtime's night sky textures from the Skyrim mod Night Sky HD LE (PraedythXVI,
https://www.nexusmods.com/skyrim/mods/107102; its FullNebula textures edit Era-7's free nebula
images, used with permission): `stars.dds`, `galaxy.dds`, `nebula.dds` and `nebula_constellations.dds`,
which the runtime draws through the mappings of the mod's own sky meshes
([ADR 0032](../../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md),
[RESEARCH.md](../../docs/RESEARCH.md) section 29) and, since the night sky editor, each with a brightness and a colour
of its own ([ADR 0227](../../docs/decisions/0227-the-night-sky-editor.md)). They ship in
`packages\runtime\files\atmosphere` with `CREDITS.txt`.

```powershell
python -I tools\sky\nif_read.py <mod>\00Data\Meshes\Sky\stars.nif out\sky\stars_nif.json
python -I tools\sky\bake_nightsky.py <mod folder> out\sky\stars_nif.json <out folder> 1 StarsThornShape7
```

| Argument | Meaning |
|---|---|
| mod folder | The extracted 8K archive (its FOMOD tree: `00Data\tex\...`, `00Data\Meshes\...`) |
| stars_nif.json | `stars.nif` as [`nif_read.py`](nif_read.py.md) writes it (block 5 is the constellations) |
| out folder | Where the four DDS files go (and `src\nebula<N>.png`, `src\nebula<N>_constellations.png`) |
| nebula option | 1-4: which `FullNebula<N>` (the RTX package uses 1) |
| stars option | The star folder under `00Data\tex` (the RTX package uses `StarsThornShape7`) |

- **stars.dds, galaxy.dds:** the mod's own `skystars.dds` and `skyrimgalaxy.dds`, copied as they are
  (BC3, 14 mips), so nothing resamples their stars.
- **nebula.dds:** `FullNebula.dds` colour times alpha in its longitude/latitude map, BC7 UNORM with box mips without
  gamma correction (the shader decodes after adding the layers).
- **nebula_constellations.dds:** the 58 constellation triangles rasterised into a map of the nebula's mapping and size:
  each texel's ray through the planar triangle, barycentric UV into the atlas (pre-filtered 2x2, premultiplied). The
  runtime finds it beside the nebula's file by its name (`<name>_constellations.dds`). It is mostly black (0.1 % of the
  texels lit: point-like blue, cyan and violet stars), so BC1 holds it at half BC7's size (44.7 MB with mips; 81 KB
  compressed with xz), with the same box mips. Until the editor the constellations were added into `nebula.dds` in
  gamma space, as Skyrim adds sky layers; the runtime now adds the two layers itself, held at 1 as before, so the
  default look is the same (mean difference 1e-5 in gamma; [RESEARCH.md](../../docs/RESEARCH.md), "The night sky
  editor").

The low tier's `nebula_4096.dds` and `nebula_4096_constellations.dds` are these with mip 0 removed by
[`drop_top_mip.py`](drop_top_mip.py.md).

The mod's files are untrusted downloads: keep them in their own folder and run with `python -I`.
**Needs:** numpy, Pillow, `nvtt_export.exe` (the RTX Remix app's, or `NVTT_EXPORT`). **Exit:** 0; a
missing file or a failed compression raises. The nebula's BC7 at `-q production` takes about ten minutes.
