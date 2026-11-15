# test_repbr_map_mod.py

Unit tests (standard-library `unittest`, numpy, Pillow, `xxhash`) of [repbr_map_mod.py](repbr_map_mod.py.md)
on synthetic data: a map item with a VBSP ([test_map_usage.py](test_map_usage.py.md)'s `bsp`), VMTs and VTFs
([test_rekey_fit.py](test_rekey_fit.py.md)'s `make_vtf` and `gma`), and a mod with brick, metal, a CC0-style
material to rebuild from its game texture and an unnamed material. The AI maps are written into the work
folder beforehand, so no model runs and no GPU is needed.

```powershell
Set-Location <skills>\workshop-content-pack\scripts
$env:TEMP = $env:TMP = '<repo>\out\tmp'
python -I -m unittest discover -v -p "test_repbr_map_mod.py"
```

| Test | Case |
|---|---|
| `test_ladder` | a texture starts at 256 px on its mip ladder; a one-value map keeps its 16 px tail; a small texture keeps its size; the mips left out for a side |
| `test_greedy_budget` | under a budget the heavy texture reaches 4096 before the light one passes 512; an unreachable budget is refused |
| `test_order` | override, unnamed, a skip flag, scans before rules, a scan rule, a rule, no rule; a recipe key or a rule class that does not exist refused |
| `test_set_inputs` | an existing asset input replaced with its metadata kept, a constant added, the prim found in any case; a missing prim raises |
| `test_mesh_material_after_a_block` | a mesh replacement's own material after a material's block: its inputs are not read as the material's, and an edit adds the input to the material without touching the mesh's |
| `test_maps` | the normal's mean slope reaches the class's target; roughness within the class's range and rougher in the height's hollows; a height map; a flat class; the envmap mask lowers roughness |
| `test_noise_and_blur_tile` | the smudge noise stays in [-1, 1] and wraps; the Gaussian blur keeps the sum and wraps |
| `test_plan_only_and_refusals` | classes and the floor's greater importance; a height map only for the world floor's class; an unreachable budget, a folder without `mod.usda`, a missing source and an existing `--out` refused |
| `test_build` | with the NVTT exporter installed (skipped otherwise): new normal, roughness and height files referenced, the rebuilt material's albedo replaced, `displace_in` and `metallic_constant` set, the unnamed material's maps kept byte for byte, the replaced author's maps left out, the brick's roughness in its range, `--mod` unchanged, within the budget |

Writes only temporary folders. Exit 0 when every test passes, 1 otherwise.
