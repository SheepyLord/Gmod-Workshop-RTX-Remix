# test_topbr_publish.py

Checks the RTX fixes' eleventh native patch, [topbr-publish](../../packages/fixes/licenses/oversized-skinning/topbr-publish/README.md),
and the RTX Remix pages around it ([ADR 0212](../../docs/decisions/0212-topbr-kept-and-publishes-past-unreadable-mods.md),
GitHub issue 6): ToPBR publishes what it converts although its scan of the other mods could not read every file.

```powershell
cd tools; python -m unittest discover -s tests -p test_topbr_publish.py -v
```

- `test_complete_files_are_the_patch_applied`: `topbr-publish.patch` touches exactly `fallback_guard.h`, `to_pbr.cpp`,
  `to_pbr.h` (under `source/material_pipeline/to_pbr`) and `tests/fallback_guard_test.cpp`. The folder's three sources
  are the patch applied to autopbr's copies (no patch between changes them); the regression is the patch's added
  lines. `tools/ci/pins.json` builds the module with the patch right after queued-draws.
- `test_a_partial_scan_no_longer_suppresses`: the shipped `FallbackGuard::Select` does not look at `complete`, only
  at the hashes the scan read; `WriteModUSDA` rescans at most every 30 s with the per-file cache and logs
  `Mod scan partial`; the old `uncertain/suppressed` state is gone.
- `test_the_guard_regression_passes` (Windows with the VS 2022 Build Tools): compiles the folder's
  `tests/fallback_guard_test.cpp` with `cl /EHsc /std:c++17 /W4 /WX /UNDEBUG` under `out\tmp` and runs it on a scratch
  folder there, which prints `PASS fallback guard:`.
- `test_the_settings_pages` (LuaJIT): runs [rtx_settings_harness.lua](rtx_settings_harness.lua.md) on the packaged
  `cl_rtx_settings.lua`.

Reads only this repository; the C++ check writes and removes a scratch folder under `out\tmp`. Exit codes: unittest's.
