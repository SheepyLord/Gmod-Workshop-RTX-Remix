# test_player_categories.py

Checks the RTX fixes' twelfth native patch, [player-categories](../../packages/fixes/licenses/oversized-skinning/player-categories/README.md),
and the packaged category manager ([ADR 0213](../../docs/decisions/0213-automatic-categorization-hardened.md)):
automatic categorization never adds a texture to a list the player's `rtx.conf` takes it out of, and its map scan is
bounded, follows its switches and survives map changes.

```powershell
cd tools; python -m unittest discover -s tests -p test_player_categories.py -v
```

- `test_complete_files_are_the_patch_applied`: `player-categories.patch` touches exactly `source/d3d9_texture_tracker.cpp`,
  `auto_categorisation.cpp`, the new `player_categories.h` (under `source/material_pipeline/auto_categorisation`),
  `source/remixapi/material_lua_bindings.cpp` and `tests/player_categories_test.cpp`. `auto_categorisation.cpp` and
  `material_lua_bindings.cpp` are the patch applied to autopbr's copies (lua-paths changed them last); the tracker
  (no earlier copy here: the public base's) has the patch's new side at every hunk; the new files are its added lines.
  `tools/ci/pins.json` builds the module with the patch, last.
- `test_every_automatic_add_asks_the_players_rtx_conf`: `ApplyToHash` and `ApplyCategoryToHash` filter their bits
  through `PlayerCategories::File::Allowed` before any `AddTextureHash`; `RemixMaterial.SetHashCategory` does when its
  third argument is `true`; the policy reads `rtx.conf` in the game folder and not `user.conf`.
- `test_the_lua_marks_its_automatic_writes`: the category manager passes `automatic == true` through
  `SetHashCategory`, its queue passes each entry's flag, its automatic paths pass `true`, and the manual
  `rtx_set_material_category` command does not.
- `test_the_policy_regression_passes` (Windows with the VS 2022 Build Tools): compiles the folder's
  `tests/player_categories_test.cpp` with `cl /EHsc /std:c++17 /W4 /WX /UNDEBUG` under `out\tmp` and runs it, which
  prints `PASS player categories:`.
- `test_the_category_manager` (LuaJIT): runs [category_manager_harness.lua](category_manager_harness.lua.md) on the
  packaged `cl_remix_category_0_manager.lua`.

Reads only this repository; the C++ check writes and removes a scratch folder under `out\tmp`. Exit codes: unittest's.
