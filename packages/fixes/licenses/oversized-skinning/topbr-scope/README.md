# ToPBR takes the map's own surfaces unless the player widens it

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[topbr-scope.patch](topbr-scope.patch) is the fourteenth native patch, after [eye-texgen](../eye-texgen/README.md);
[pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`) builds the module with it last and records the patched
native tree the fourteen give (`fixes.patched_tree.source` `b07547bc...`; `public` and `premake5.lua` unchanged). The
complete changed files are [to_pbr.cpp](source/material_pipeline/to_pbr/to_pbr.cpp),
[to_pbr.h](source/material_pipeline/to_pbr/to_pbr.h), the new [topbr_scope.h](source/material_pipeline/to_pbr/topbr_scope.h)
and the SDK-free regression [topbr_scope_test.cpp](tests/topbr_scope_test.cpp), as the work tree has them (CRLF). The
build applies only the patch's `source/` part. Made in a scratch checkout of the public base with the thirteen earlier
patches applied (`out/topbr-scope/fixes` of the loader's main checkout); nothing was committed to the fork or pushed.

## Why

The user's request of 2026-11-16: "allow user to limit its application range, by default it should only work on map
mesh and nothing else". World conversion (ToPBR, `rtx_topbr_enabled`) took every scene material the texture tracker
saw drawn: the map, but also props, weapons, view models, NPCs and effects. Its queue is filled natively (the material
pipeline's worker calls `QueueMaterialsForProcessing` for every newly drawn material, `material_pipeline.cpp`), so the
range has to be held there; Lua cannot filter what it never sees.

## The change

- **`Scope::Filter` ([topbr_scope.h](source/material_pipeline/to_pbr/topbr_scope.h), standard C++)**: restricted or
  not, and the set of material names the game's Lua has named, compared by a key: lower case, forward slashes, no
  `materials/` prefix or `.vmt`, a second base texture's tracker name (`..._stage1`) as its material, and a map's own
  patched material (`maps/<map>/...`, a cubemap patch or a blended displacement's `..._wvt_patch`) without that prefix
  and suffix, so the BSP's names (`game.GetWorld():GetMaterials()`, NikNaks' texture list) meet the names the tracker
  records. At most 65,536 names of at most 512 characters (any server's client Lua reaches the bindings). A new filter
  is restricted and empty: nothing is taken until Lua names the map's materials.
- **The player's setting decides the restriction**: `rtx_topbr_scope` (0 the map's own surfaces, the default; 1 also
  props; 2 everything, as before), read from the engine's convar list on the game thread (`SyncScope`, every 250 ms in
  `PumpSnapshots` and at each Lua binding), like R19's `rtx_topbr_enabled`. Lua only adds names.
- **Every queue asks the range**: `QueueMaterialsForProcessing` skips a material outside it without marking it
  processed (a wider range takes it later), `ProcessSingleMaterial` refuses one, and the worker drops a queued one the
  range no longer takes.
- **Bindings** (`MaterialPipeline.ToPBR`): `AllowScopeMaterials(names)` (returns how many were new), `ClearScope()`,
  `GetScope()` (restricted, names held, the player's setting) and `InScope(name)`.

What a narrower range leaves out of the published layer is the client driver's part: it clears the cache when the
range narrows, so the next publication carries only what the new range converts
([cl_rtx_topbr_conversion.lua](../../../garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_topbr_conversion.lua)).

## Tests

[topbr_scope_test.cpp](tests/topbr_scope_test.cpp) compiles alone with MSVC
(`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX`): the keys (case, slashes, prefix and
extension, cubemap and WVT patches, second stages), the setting's values, a new filter taking nothing, the BSP's names
admitting the tracker's, props outside until named, everything and back, a cleared filter, and the bound. 32 checks.
The loader's Release gate compiles and runs it and checks the folder's files against the patch
([test_topbr_scope.py](../../../../../tools/tests/test_topbr_scope.py.md)).

Validated build: 5,607,424 bytes, SHA-256 `e885543dad209ac52114a7f436d4ee43011094a848991d64c75aed460d781c42`
(`build_modules.ps1 -Only fixes` under a `subst` alias of the worktree, garrysmod_common `a854f23`, premake
5.0.0-beta2; the patched tree matched). See the loader's
[ADR 0229](../../../../../docs/decisions/0229-topbr-takes-the-maps-own-surfaces-unless-the-player-widens-it.md).
