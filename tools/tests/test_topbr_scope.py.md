# test_topbr_scope.py

Checks ToPBR's range (the user's request of 2026-11-16,
[ADR 0229](../../docs/decisions/0229-topbr-takes-the-maps-own-surfaces-unless-the-player-widens-it.md)): the RTX fixes'
fourteenth native patch, [topbr-scope](../../packages/fixes/licenses/oversized-skinning/topbr-scope/README.md), and the
client driver's default.

```powershell
cd tools; python -m unittest discover -s tests -p test_topbr_scope.py -v
```

- `test_complete_files_are_the_patch_applied`: `topbr-scope.patch` touches exactly `to_pbr.cpp`, `to_pbr.h`, the new
  `topbr_scope.h` and `tests/topbr_scope_test.cpp`. The first two are the patch applied to topbr-publish's copies (no
  later patch changes them); the new files are its added lines. `tools/ci/pins.json` builds the module with the patch
  last, right after eye-texgen.
- `test_every_queue_takes_only_the_players_range`: `QueueMaterialsForProcessing` skips a material outside the range
  before it is queued, `ProcessSingleMaterial` refuses one, and the worker drops a queued one a narrower range left out
  without marking it processed (so a wider range takes it later); `PumpSnapshots` reads the player's setting
  (`rtx_topbr_scope`, through the engine's convar list); the four Lua bindings exist and the one that adds names never
  widens the range itself; the header starts restricted and includes no SDK.
- `test_the_driver_starts_at_the_maps_own_surfaces`: the packaged driver creates `rtx_topbr_scope` with 0 and clears
  the cache when the range narrows.
- `test_the_regression_passes` (Windows with the VS 2022 Build Tools): compiles the folder's
  `tests/topbr_scope_test.cpp` with `cl /EHsc /std:c++17 /W4 /WX /UNDEBUG` under `out\tmp` and runs it, which prints
  `PASS topbr scope:`.

Reads only this repository; the C++ check writes and removes a scratch folder under `out\tmp`. Exit codes: unittest's.
