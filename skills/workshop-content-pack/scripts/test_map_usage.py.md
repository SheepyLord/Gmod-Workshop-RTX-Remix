# test_map_usage.py

Unit tests (standard-library `unittest`) of [map_usage.py](map_usage.py.md) on a synthetic map item: a GMAD
archive ([test_rekey_fit.py](test_rekey_fit.py.md)'s `gma`) holding a VBSP v20 written by the test's `bsp()`
(planes, texdata, texinfo, faces, the string table, a static-prop game lump and an entity), VMTs and a studio
model header written by `mdl()`.

```powershell
Set-Location <skills>\workshop-content-pack\scripts
$env:TEMP = $env:TMP = '<repo>\out\tmp'
python -I -m unittest discover -v -p "test_map_usage.py"
```

| Test | Case |
|---|---|
| `test_usage` | a floor material, its VBSP cubemap and `_wvt_patch` copies and a root material written `/name` summed; sky and `tools/` faces left out; a blend's two base textures share its wall area; the VMT's flags and surface type kept; 2 static props and 1 entity times the model's box surface, half seen; `importance()`; an overlay's UV square and an `infodecal` counted as wall without changing the total |
| `test_cli_and_refusal` | `--json` written; an archive without a BSP and a missing source refused (exit 1) |
| `test_norm_and_vmt` | texture names normalised (`pak:`, `materials/`, back slashes, `.vtf`); a VMT's shader and keys, quoted or not |
| `test_mdl` | texture names, `$cdmaterials` and the view box's surface; a file that is no model gives None |

`test_repbr_map_mod.py` reuses `bsp()` and `VMT`. Writes only temporary folders. Exit 0 when every test passes,
1 otherwise.
