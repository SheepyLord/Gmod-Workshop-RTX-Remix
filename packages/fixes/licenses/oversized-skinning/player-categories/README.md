# Automatic categories keep the player's rtx.conf choices

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[player-categories.patch](player-categories.patch) is the twelfth native patch, after
[topbr-publish](../topbr-publish/README.md); [pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`) builds the
module with it last and records the patched native tree the twelve give (`fixes.patched_tree.source` `7464a58d...`).
The complete changed files are [d3d9_texture_tracker.cpp](source/d3d9_texture_tracker.cpp),
[auto_categorisation.cpp](source/material_pipeline/auto_categorisation/auto_categorisation.cpp), the new
[player_categories.h](source/material_pipeline/auto_categorisation/player_categories.h),
[material_lua_bindings.cpp](source/remixapi/material_lua_bindings.cpp) and the SDK-free regression
[player_categories_test.cpp](tests/player_categories_test.cpp), as the work tree has them (CRLF). The build applies
only the patch's `source/` part. The same change is commit `25d2e66` on the local scratch branch that also holds
topbr-publish (`48cd3df`); nothing was pushed.

## The fault

Automatic categorization writes texture categories through `remixapi_AddTextureHash` and `RemoveTextureHash`, which
the runtime applies to its user layer (`rtx_fork_api_entry.cpp`, `mutateTextureHashOption`): the strongest layer,
above `rtx.conf`, and the one Remix's Save Settings writes to `user.conf`. The first layer with an opinion on a hash
decides (`HashSetLayer::mergeFrom`). So a texture the player took out of a category in the Remix developer menu (which
edits the `rtx.conf` layer and saves a `-0x...` entry there) was put back by the next automatic pass in every session:
the player could not un-decal a wall or un-particle a sprite for good.

## The change

- **`PlayerCategories` (player_categories.h, standard C++)** reads the `-0x...` entries of every `rtx.*Textures` list
  in the player's `rtx.conf` in the game folder (bounded: 16 MiB read, a million entries), again when its size or
  write time changes (looked at at most every 2 s, on the game thread each frame through `RetryPendingCategories`).
- **Every automatic add asks it**: `AutoCategorisation::ApplyToHash` and `D3D9TextureTracker::ApplyCategoryToHash`
  drop the category bits (sky, ignore, particle, decal, animated water, legacy emissive) whose list `rtx.conf` takes
  the hash out of, before any `AddTextureHash` and before their own bookkeeping; `RemixMaterial.SetHashCategory` does
  the same when its new third argument is `true`, which the Lua category manager passes for its automatic paths.
  Manual commands, the player body's proxies (ADR 0043) and RTX Water's own textures pass nothing and are not limited.
- **Removals are unchanged.** They correct automatic leftovers, such as water that an older session saved as a decal
  (the `rtx.conf` and `user.conf` of the owner's field install have 4 water hashes in their decal lists, the package's
  classic defaults 33). `user.conf` is not read: Remix writes texture lists there only from automatic categories a
  Save Settings kept, never from the player's own choices.

## Tests

[player_categories_test.cpp](tests/player_categories_test.cpp) compiles alone with MSVC
(`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX`): parsing (case, quotes, comments, invalid
tokens, positive entries ignored, the bound), only an excluded list's bit dropped, and the live file read on the first
refresh, again on a change, not within two seconds, and cleared when it goes. The loader's Release gate compiles and
runs it, checks the folder's files against the patch and checks that every automatic add path asks the policy first
([test_player_categories.py](../../../../../tools/tests/test_player_categories.py.md)).

Validated build: the one in [topbr-publish](../topbr-publish/README.md) (both patches, 5,597,696 bytes, SHA-256
`45f48990...`). See the loader's [ADR 0213](../../../../../docs/decisions/0213-automatic-categorization-hardened.md).
