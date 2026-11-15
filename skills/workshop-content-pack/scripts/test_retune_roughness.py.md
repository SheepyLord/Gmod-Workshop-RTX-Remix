# test_retune_roughness.py

Unit tests (standard-library `unittest`, numpy, Pillow, `xxhash`) of [retune_roughness.py](retune_roughness.py.md)
on synthetic data: a GMAD archive holding two DXT1 VTFs ([test_rekey_fit.py](test_rekey_fit.py.md)'s `make_vtf`
and `gma`), and a small mod with a sub-layer and uncompressed DDS maps written by Pillow.

```powershell
Set-Location <skills>\workshop-content-pack\scripts
$env:TEMP = $env:TMP = '<repo>\out\tmp'
python -I -m unittest discover -v -p "test_retune_roughness.py"
```

| Test | Case |
|---|---|
| `test_classify` | brick, pavement in a pakfile, a facade, graffiti; sky and a weapon sheet skipped; an unknown path unclassified |
| `test_remap` | the 2nd-98th percentile mapped onto the range with the texels' order kept; a flat map to the middle |
| `test_window_mask` | a two-level alpha with 5 % panes gives a mask; a graded alpha (grey, grungy panels with a few near-black texels and one solid pane, as `building_template006b`) gives the pane and nothing on the panels; an opaque, a speckled and a mostly-zero alpha give none |
| `test_octahedral_and_gain` | octahedral encoding round trip within 0.02; a gain above 1 steepens; a full flat mask gives (0, 0, 1) |
| `test_decode_vtf` | a DXT1 block decoded through the DDS header (blue), an RGBA8888 VTF as RGB, an I8 VTF refused |
| `test_restore_grain` | a blurred upscale keeps under half the source's grain; one back-projection pass more than doubles it (above 0.65 on pixel-level noise, the hardest case) and keeps the alpha; a nearest-neighbour upscale has nothing to restore |
| `test_dry_run_and_refusals` | one material retuned, one skipped by rule, one unnamed, nothing written; an existing `--out` without `--force` or without a `mod.usda`, a missing source and a folder without `mod.usda` refused |
| `test_run_writes_new_files_only` | with the NVTT exporter installed (skipped otherwise), with `--restore-grain`: the brick's roughness lands in 0.74-0.95, its normal is re-encoded, the sky and the unnamed material keep their bytes, and `--mod` is unchanged |

Writes only temporary folders. Exit 0 when every test passes, 1 otherwise.
