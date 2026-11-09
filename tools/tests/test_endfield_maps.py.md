# test_endfield_maps.py

Regressions for the fixes' eighth native patch, Endfield NPC, weapon and item maps in imported game PBR
([ADR 0137](../../docs/decisions/0137-endfield-npc-weapon-and-item-maps.md),
[the patch's README](../../packages/fixes/licenses/oversized-skinning/endfield-maps/README.md)). Run from the
repository root:

```powershell
python -I -m unittest discover -s tools/tests -p test_endfield_maps.py
```

- `test_complete_files_are_the_patch_applied` (every platform): `endfield-maps.patch` touches exactly
  `source/material_pipeline/to_pbr/game_matching.inl` and `tests/game_matching_test.cpp`; its hunks, applied
  to the preceding complete files (wuwa-maps' `game_matching.inl`, autopbr's test) with every context and
  removed line checked, give the folder's complete files (line endings aside); `tools/ci/pins.json` builds the
  module with the patch, applying only `source/*` of it.
- `test_matching_regression_on_the_shipped_headers` (Windows with the VS 2022 Build Tools, otherwise
  skipped): assembles the ToPBR headers the module is built from out of the patches' complete files, in patch
  order (autopbr, then wuwa-maps, then endfield-maps; checked on 2026-11-09 to equal all 20 files of the
  patched tree's `source/material_pipeline/to_pbr`), with autopbr's SDK-free `game_pbr_types.h`, and compiles
  the folder's `game_matching_test.cpp` with MSVC C++17, `/W4 /WX` and assertions. It must print
  `PASS Endfield maps:` (NPC, weapon and item families pair by exact stem with the Endfield layout, known by
  their own or a sibling's `_P`; never UV candidates, names shown or hidden; a `t_actor_` family still is one;
  an `_MRA` under the prefix keeps Silver's rule; a `T_*_D`/`T_*_N` pair with no `_P` stays no family) and
  R12's `PASS R12 matching:`. The Release gate's older `test_topbr_registry.py` compiles autopbr's copy of the
  test on autopbr's headers.

Inputs: the committed patch, complete files and `pins.json`. Writes compiler inputs, outputs and generated
fixture images only in a temporary folder under `out/tmp`, removed afterwards. No game, GPU, network or fixes
checkout. Exit 0 on success or skip, 1 on a failure. Included in `tools/test.ps1`.
