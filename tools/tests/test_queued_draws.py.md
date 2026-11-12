# test_queued_draws.py

Checks the RTX fixes' tenth native patch, [queued-draws](../../packages/fixes/licenses/oversized-skinning/queued-draws/README.md)
([ADR 0192](../../docs/decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md)): the studio render hooks
never read a queued draw's renderable, which on the material system's render thread can be an entity the main
thread has already deleted.

```powershell
cd tools; python -m unittest discover -s tests -p test_queued_draws.py -v
```

- `test_complete_files_are_the_patch_applied`: `queued-draws.patch` touches exactly `source/HardwareSkinningHooks.cpp`,
  `source/prop_fixes.cpp`, `source/studio_draw_policy.h` and `tests/studio_draw_policy_test.cpp`. The folder's
  `HardwareSkinningHooks.cpp` is the patch applied to backrooms' copy (no patch between changes it); its
  `prop_fixes.cpp` (no earlier copy here: the public base's) has the patch's new side at every hunk; the two new files
  are the patch's added lines. `tools/ci/pins.json` builds the module with the patch, last.
- `test_the_lighting_hook_never_reads_the_renderable`: in the shipped `prop_fixes.cpp` the renderable lookup
  (`GetBoneCountForRenderable`, the `vtbl[9]` `GetModel` call, its pointer checks) is gone; the
  `R_StudioSetupSkinAndLighting` hook passes the renderable only to its two trampoline calls, a debug print and
  `StudioDrawPolicy::BoneCount(_this, pClientRenderable)`, and chooses with `StudioDrawPolicy::ChooseLighting`;
  `BoneCount` mentions the renderable once (the null check) and reads `CStudioRender+0x108` and `numbones` at `+0x9C`.
- `test_the_model_to_world_read_is_only_for_the_transform_chains`: `ResolveModelToWorld` checks
  `TransformChainNeedsModelToWorld` before its `ReadProcessMemory` of the entity's coordinate frame, and outside it the
  skinning hooks only pass the renderable on (the `R_StudioRenderFinal` signature, its debug print, the trampoline, the
  pending pointer).
- `test_the_policy_regression_passes` (Windows with the VS 2022 Build Tools): compiles the folder's
  `tests/studio_draw_policy_test.cpp` with `cl /EHsc /std:c++17 /W4 /WX /UNDEBUG` under `out\tmp` and runs it, which
  prints `PASS studio draw policy:`. That regression fails on a policy that reads or calls the renderable (a deleted
  entity with code in slot 9, a renderable in a guard page).

Reads only this repository; the C++ check writes and removes a scratch folder under `out\tmp`. Exit codes: unittest's.
