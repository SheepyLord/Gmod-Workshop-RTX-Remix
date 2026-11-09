# test_arc9_patch.py

R24 ([ADR 0135](../../docs/decisions/0135-view-model-materials-and-arc9.md)): unit tests of the RTX fixes' ARC9 patch as
the package ships it (`packages/fixes/.../remixbinary/lua/patcher/addons/cl_arc9.lua`). `ARC9PatchTests` runs
[`arc9_patch_harness.lua`](arc9_patch_harness.lua.md) under LuaJIT, one scenario per test (skipped without LuaJIT): the
parts drawn with their materials, only in the calls where ARC9 draws them (not for a world model in an RT scope or at
LOD 2, not for an NPC's or a distant player's view model, the preset's models for a preset icon, never a charm,
animation proxy or translucent part), ARC9's errors and results passed on, the off switch, and the gun screen provider
in place whichever of the patch and the companion loads first.

Usage: `python -I -m unittest discover -s tools\tests -p test_arc9_patch.py` (or the whole suite through
`tools\test.ps1`). No side effects; exit status is unittest's.
