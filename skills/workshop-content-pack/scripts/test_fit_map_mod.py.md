# test_fit_map_mod.py

Unit tests (standard-library `unittest`) of [fit_map_mod.py](fit_map_mod.py.md) on synthetic mods: the
test writes DX10 DDS files (BC7, BC5, BC4 with full mip chains, random or constant blocks), a
`materials.usda` in the remaster pipeline's form, `mod.usda`, and the `textures.json` and
`inventory.json` that say which maps use what.

```powershell
Set-Location <skills>\workshop-content-pack\scripts
$env:TEMP = $env:TMP = '<repo>\out\tmp'      # in the repository: scratch stays under out\
python -I -m unittest discover -v -p "test_fit_map_mod.py"
```

## What it checks

| Test | Case |
|---|---|
| `test_split_by_map_first_part_wins` | shared and first-map blocks go to the first part, second-map blocks to the second, a block of a third map is left out, a block without map information goes to the first part; each part holds only its own textures |
| `test_lossless_constants_and_duplicates` | two constant metallic maps of different sizes become one 16 px file holding the value; a byte-identical albedo is written once and its block points at the copy; an untouched file stays byte-identical; an unreferenced source file is counted and left out |
| `test_dropped_mips_are_the_source_tail` | a cut file's header (size, top-level size, mip count) and its data, which is exactly the source's from the next mip on; tier 1 leaves the albedo alone |
| `test_tier_order_and_least_important_first` | a budget that tier 1 alone meets cuts the models' roughness first and no world map; a tighter one applies tier 1 everywhere, then cuts the model with fewer instances to twice its source (its roughness to half its albedo) and leaves the other |
| `test_world_tier_cuts_big_world_textures_by_share` | of two 4096 world textures, the one with the smaller area share goes to 2048 |
| `test_unreachable_budget_writes_nothing` | exit 1, no part folder |
| `test_dry_run_and_force_rules` | `--dry-run` writes only the report; an existing part needs `--force`; `--force` refuses a folder holding other files |
| `test_mod_usda_rewritten_and_other_sublayers_refused` | `--mod-name` and the `doc` in the part's `mod.usda`; a mod with another sublayer is refused |
| `test_bad_command_lines` | a part without maps, two parts of one name, a part inside the source, an unknown `--part-budget` name (exit 1); a missing required option (exit 2) |
| `test_constant_check_needs_one_value` | a repeated block holding two values is not constant |

## Side effects and exit codes

Writes only into a temporary folder (`tempfile`, which honours `TEMP`), removed afterwards; no game or
real mod is touched. Exit 0 when every test passes, 1 otherwise (unittest's own codes).
