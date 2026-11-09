# test_game_emission.py

Checks the fixes' ninth native patch, imported game emission
([ADR 0138](../../docs/decisions/0138-imported-game-emission-glows.md),
[the patch's README](../../packages/fixes/licenses/oversized-skinning/game-emission/README.md)). Run from
`tools`:

```powershell
python -I -m unittest discover -s tests -p test_game_emission.py
```

- `test_complete_files_are_the_patch_applied`: `game-emission.patch` touches exactly
  `source/material_pipeline/to_pbr/usda.cpp` and `tests/to_pbr_test.cpp`; its hunks, applied to autopbr's complete
  files (no patch in between changes them) with every context and removed line checked, give the folder's complete
  files (line endings aside); `tools/ci/pins.json` builds the module with the patch.
- `test_only_game_materials_with_emission_maps_enable_it`: in the shipped `WriteOpaqueMaterial`, the one
  `enable_emission` line sits inside the emission-map block behind `info.importedGame`; the folder's
  `to_pbr_test.cpp` asserts the flag for a game material with an emission map and its absence otherwise.

The native regression itself (`to_pbr_test.cpp`, which writes the materials with the production `usda.cpp`) needs
the fixes' `public/include` and garrysmod_common's headers, which this repository does not hold; it was built and
run as the R11 notes describe (passes with the patch, fails without it). This test reuses `apply` and `text` from
[`test_endfield_maps.py`](test_endfield_maps.py.md). Reads only committed files; no compiler, game or network.
Exit 0 on success, 1 on a failure. Included in `tools/test.ps1`.
