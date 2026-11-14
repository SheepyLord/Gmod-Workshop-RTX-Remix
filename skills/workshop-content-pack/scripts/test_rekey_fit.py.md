# test_rekey_fit.py

Unit tests (standard-library `unittest`, plus `xxhash`) of [vtf_hash.py](vtf_hash.py.md),
[rekey_mod_hashes.py](rekey_mod_hashes.py.md) and [fit_mod.py](fit_mod.py.md) on synthetic data: VTFs (7.2 and
7.3 layouts, DXT1 with two frames, RGBA8888 with and without an alpha flag, BGR888), a GMAD archive, a VPK v1
dir file holding its data, small mods, and DDS files from [test_fit_map_mod.py](test_fit_map_mod.py.md)'s
`make_dds`.

```powershell
Set-Location <skills>\workshop-content-pack\scripts
$env:TEMP = $env:TMP = '<repo>\out\tmp'
python -I -m unittest discover -v -p "test_rekey_fit.py"
```

| Test | Case |
|---|---|
| `test_dxt_frames_and_versions` | every frame's top mip hashed both ways; the 7.3 resource table found |
| `test_uncompressed_layouts` | RGBA8888 as BGRA with an alpha flag and BGR0 without; BGR888 as BGR0; not a VTF refused |
| `test_containers` | a .gma yields only its VTFs; a VPK yields its `materials/` VTF and not its sound; the source table and its cache |
| `test_rename_known_keep_others_and_refuse_clash` | an XXH3 material renamed with the path that binds it; an XXH64 one and an unknown one kept; a rename onto an existing material refused with nothing written |
| `test_models_and_decals_off_world_capped` | [tune_displacement.py](tune_displacement.py.md): a model and a decal material's depth to 0, a world one capped at 0.008, one already shallower kept |
| `test_aux_first_then_lossless_layers_kept` | a constant metallic map cut to a 16 px tail; the roughness map at half its albedo; the albedo and the layers byte-identical; the cut file's data is the source's lower mips |
| `test_out_of_reach_and_existing_out` | a budget out of reach writes nothing; an existing `--out` needs `--force` |

Writes only temporary folders. Exit 0 when every test passes, 1 otherwise.
