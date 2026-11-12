# test_port_classic_mods.py

Unit tests (standard-library `unittest`) of [usd_refs.py](usd_refs.py.md) and
[port_classic_mods.py](port_classic_mods.py.md) on synthetic mods: the test writes text layers in the
Remix Toolkit's form (with `customData = { asset default = @@ }`), small files, and minimal binary crate
layers (header, a `TOKENS` section framed as `TfFastCompression` around a literal-only LZ4 block, a table
of contents).

```powershell
Set-Location <skills>\workshop-content-pack\scripts
$env:TEMP = $env:TMP = '<repo>\out\tmp'      # in the repository: scratch stays under out\
python -I -m unittest discover -v -p "test_port_classic_mods.py"
```

## What it checks

| Test | Case |
|---|---|
| `test_text_references` | `@...@` and `@@@...@@@` found; `@@`, an `@` inside a string and a commented reference skipped |
| `test_blank_missing_only_files` | only the missing file reference becomes `@@`; a present file, a missing sub-layer and a shader name stay |
| `test_lz4_literals_and_overlapping_match` | literal-only blocks (short and with length bytes), an overlapping match, two-chunk `TfFastCompression`, a match offset past the output refused |
| `test_crate_tokens_and_references` | a crate's tokens; its references are the path-like tokens |
| `test_walk_nested_crate_missing_outside_and_shader_beside` | nested sub-layers, a referenced crate and its texture, a missing file, a path leaving the mod, a bare path, a shader file beside its layer counted as used, an unreferenced file |
| `test_merge_keeps_runtime_order_and_files` | three sources given in any order come out ranked `Main`, `Main_fix`, `water_fix`; an overlap where the later source sets only what the owner sets passes; files copied byte for byte; `--drop-unreferenced` leaves out the dead texture |
| `test_later_source_adding_attributes_is_refused` | a later source setting a value the owner does not: exit 1, nothing written |
| `test_empty_prim_does_not_own_a_mesh` | an empty `mesh_` prim in the first source: the second owns the hash |
| `test_missing_files_need_blank_missing` | refused without the option; with it the reference is `@@` in the copy |
| `test_single_source_is_a_byte_identical_rename` | one source with a crate layer: every file identical; a second run without `--force` refused |

## Side effects and exit codes

Writes only temporary folders (removed after each test). Exit 0 when every test passes, 1 otherwise.
