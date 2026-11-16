# What any server's Lua may ask of the module: Remix options, game-map sources, model reloads

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[lua-guards.patch](lua-guards.patch) is the fifteenth native patch, after [topbr-scope](../topbr-scope/README.md);
[pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`) builds the module with it last and records the patched
native tree the fifteen give (`fixes.patched_tree.source` `14a120ec...`; `public` and `premake5.lua` unchanged). The
complete changed files are [lua_path_policy.h](source/lua_path_policy.h), [module.cpp](source/module.cpp),
[config_lua_bindings.cpp](source/remixapi/config_lua_bindings.cpp) and
[to_pbr.cpp](source/material_pipeline/to_pbr/to_pbr.cpp); the new ones
[remix_option_policy.h](source/remix_option_policy.h), [model_reload_policy.h](source/model_reload_policy.h) and
[game_source.h](source/material_pipeline/to_pbr/game_source.h); the regressions
[lua_path_policy_test.cpp](tests/lua_path_policy_test.cpp) (extended),
[remix_option_policy_test.cpp](tests/remix_option_policy_test.cpp),
[game_source_test.cpp](tests/game_source_test.cpp) and
[model_reload_policy_test.cpp](tests/model_reload_policy_test.cpp), as the work tree has them (CRLF). The build applies
only the patch's `source/` part. Made in a scratch `git clone --shared` of the user's fork clone with the fourteen
earlier patches applied (`out/fx/fixes` of the review's worktree); nothing was committed to the fork or pushed.

## Why

The repository review of 2026-11-16 found three things any server's client Lua could do through this module, beyond
GMod's Lua sandbox or into a crash, and the user approved fixing every finding:

- **Finding 2.** `RemixConfig.SetConfigVariable` refused only fourteen path options by name (R19, the loader's
  ADR 0112) and values starting at a root or a drive. Everything else reached the runtime's User layer, which the Remix
  menu's "Save Settings" writes to `user.conf`: `rtx.captureShowMenuOnHotkey False` with `rtx.captureHotKey` set to
  Shift (GMod's sprint) started a capture into `rtx-remix/captures` on every frame Shift was held, each with a sky probe
  of up to 1 GiB (`rtx.skyProbeSide`) once `rtx.enableReplacementAssets` was off; the crash hotkeys, the profiler and
  automation options went through; and the upstream merge of 2026-11-14 added `rtx.waterSim.rings.texture`, which the
  runtime opens, so `..\..\Users\Public\x.dds` or `C:Users\...` loaded any local DDS.
- **Finding 7.** `ToPBR.GameMaterialAction(..., "options")` listed up to 256 image files in the folder of any absolute
  path ending in `.pmx` (the file never had to exist), and "maps" scanned it, whatever the player's
  `rtx_topbr_game_maps`; their errors told a missing folder ("invalid model folder") from an existing one. An automatic
  resolution likewise opened any path, and its error ("not a local PMX") told an existing file from a missing one.
- **Finding 24.** `RTX_ReloadModelsAfterHardwareSkinningSettings()` discarded studiorender's hardware meshes
  (`MDLCACHE_FLUSH_STUDIOHWDATA`) whenever called. Under queued rendering the material system's thread may be drawing
  them: about half of the loader's PoC starts crashed there until `cl_rtx.lua` switched `mat_queue_mode` to 0 for its
  last call (review R4). The Lua guarded its own calls; the global did not.

## The change

### Remix options from Lua (finding 2)

`RemixOptionPolicy::LuaMaySet` ([remix_option_policy.h](source/remix_option_policy.h), standard C++) decides before the
Remix API is called; a refusal prints the option, the reason and "set it in rtx.conf or the Remix menu", and
`SetConfigVariable` returns false. Names compare in lower case without white space (the runtime itself needs the exact
name). In order:

1. **Refused by name**, whatever the allowed list holds: every path option (`LuaPathPolicy::RemixPathOption`, now with
   `rtx.waterSim.rings.texture`), `rtx.capture*`, `rtx.enableReplacement*`, `rtx.profiler.*`, `rtx.automation.*`,
   `rtx.cameraSequence.*`, `rtx.nsight.*`, `rtx.freeCam.*`, `rtx.gui.*` (the menu's language and logging),
   `rtx.gpuOverride.*`, `rtx.skyProbeSide`, `rtx.welcomeMessage`, `rtx.splashMessageDisplayTimeSeconds`,
   `rtx.hideSplashMessage`, `rtx.enableCrashHotkey`, `rtx.crashHotkey`, `rtx.gpuCrashHotkey`,
   `rtx.enableBreakIntoDebuggerOnPressingB`, `rtx.remixMenuKeyBinds`, `rtx.dumpAllInstancesOnFrame`,
   `rtx.gmod.fallbackMods` (the generated mods' rank) and `rtx.gmod.enableInstrumentation` (diagnostic logging).
2. **Allowed**: what the RTX package's own Lua and data set (listed below, from a search of `packages/`, `companion/`,
   `glass/`, `vr/` and `fs_accel/` for `RemixConfig.Set*` and every setter's tables), what the content packs'
   companion profiles in `skills/workshop-content-pack` set, and what the map RTX add-ons on the fork's branches set.
   Everything else is refused.
3. **Values**: at most 1 MiB; none naming a root, a drive, a network path, a drive-relative path (`C:x`) or a climb
   out of a folder (a segment of dots and spaces with two dots or more: `LuaPathPolicy::AbsolutePathValue`, extended);
   the hash-list options take only comma-separated hashes (1-16 hex digits, an optional `0x`, an optional leading `-`),
   because the runtime reads each item with an unguarded `std::stoull` that would throw through the Remix API.

| Allowed options | Set by |
|---|---|
| `rtx.atmosphere.*`, `rtx.weather.*` | the companion's sky, weather and night sky editor (`nativeloader_sky.lua`, `nativeloader/weather_presets.lua`) |
| `rtx.volumetrics.*` | the weather's fog and the RTX Remix tab's fog presets (`nativeloader_menu.lua`), Poolrooms RTX, the content packs |
| `rtx.tonemap.*`, `rtx.autoExposure.*`, `rtx.bloom.*`, `rtx.enableDirectTranslucentShadows` | the tab's colour purity; the content packs' looks (`skills/workshop-content-pack`'s companion profiles) |
| `rtx.postfx.*` | the tab's post effects |
| `rtx.skyBrightness`, `rtx.skyMode`, `rtx.ignoreGamePointLights`, `rtx.ignoreGameSpotLights`, `rtx.ignoreGameDirectionalLights` | the map lights (`cl_remix_api_map_lights.lua`), the fixes' settings (`cl_rtx_settings.lua`), the sky, Poolrooms RTX, the content packs |
| `rtx.fallbackLightMode` | the map RTX add-ons made from the fork's map branches (Modern House RTX and others), beside the options above |
| `rtx.playerModel.enablePrimaryShadows` | the tab, for the body proxy |
| `rtx.graphicsPreset`, `rtx.upscalerType`, `rtx.qualityDLSS`, `rtx.frameGenerationType`, `rtx.integrateIndirectMode`, `rtx.pathMaxBounces` | the tab's Remix settings |
| `rtx.di.*`, `rtx.neeCache.enableAnalyticalLight`, `rtx.risLightSampleCount`, `rtx.denoiseDirectAndIndirectLightingSeparately`, `rtx.suppressLightKeeping`, `rtx.hideInstanceTextures` | the shipped default map config (`data/remix_map_configs/default.txt`, applied by `cl_remix_map_configs.lua`) |
| `rtx.translucentMaterial.*` | RTX Water (`rtx_water/cl_core.lua`) |
| `rtx.gmod.*` (not the two above) | the companion's eye whites, model layers, imported normals, MMD alpha and effect categories |
| `rtx.legacyEmissiveColorsString`, `rtx.legacyEmissiveIntensitiesString` | the physgun's glow (`cl_physgun_color_sync.lua`) |
| `rtx.raytracedRenderTargetTextures` | ARC9's magnified scopes (`patcher/addons/cl_arc9.lua`) |
| `rtx.recomputeTextureHashOnWrite`, `rtx.opacityMicromapIgnoreTextures` | the bullet break simulator (`cl_40_damage.lua`) |
| `rtx.ignoreTextures` | VR's held camera (`vr/addon/lua/nlvr/modules/cl_weapons_model.lua`) |
| `rtx.enableRaytracing`, `rtx.upscaler`, `rtx.denoiser`, `rtx.reflectionUpscaler`, `rtx.renderResolutionScale`, `rtx.maxBounces`, `rtx.volumetricEnabled`, `rtx.defaultToAdvancedUI` | `RemixConfig`'s own shortcut setters, which set them anyway |

The hash lists checked item by item: `rtx.ignoreTextures`, `rtx.hideInstanceTextures`,
`rtx.raytracedRenderTargetTextures`, `rtx.opacityMicromapIgnoreTextures`, `rtx.postfx.motionBlurMaskOutTextures`, the
six `rtx.gmod.*Textures*` lists and `rtx.gmod.meshReplacementHashAliases`. The runtime parses the other text options
Lua may set (`rtx.gmod.eyeWhiteAliases`, the two legacy emissive strings) without throwing.

What this changes for a player: a map config of their own (`data/remix_map_configs/<map>.txt`) or another add-on that
sets an option outside the list through `RemixConfig.SetConfigVariable` now gets `false` and a console line; such an
option belongs in `rtx.conf`. The other `RemixConfig` setters (the shortcuts, `SetUIState`) set fixed options and are
unchanged.

### Game-map actions (finding 7)

[game_source.h](source/material_pipeline/to_pbr/game_source.h) (standard C++ with the Windows headers `game_pbr.h`
takes): `SourceModels::Check` accepts a source only when it is an existing regular `.pmx` file that `GamePBR::ParsePMX`
reads (at most 256 MiB, as the conversion's own read) and one of whose materials draws the base texture, compared as
the conversion's mask compares it (lower case, forward slashes); the parsed texture names are kept per path while the
file's size and write time stay the same (at most 16 models, the worker's own). A server cannot put such a file on the
player's drive.

- **"options"** (`GamePBR::ListOptions`): the families and image files of the model's folder, or, for a refused source
  or a folder the scan cannot read, no list and the one text `SourceRefusal` ("the model's source is unavailable (the
  game console says why)"); the reason goes to the console only. An empty source still lists nothing, without an
  error, as before.
- **"maps"** (`GamePBR::SourceFolder`): the same check before the folder is scanned, the same text for a refusal, and
  the chosen maps must be images that folder lists (the files and families "options" offers), so a choice cannot probe
  other files beside the model.
- **The automatic resolution** (and an "automatic" action) counts the source as readable only when the check passes;
  anything else restores the recorded maps only, the same whether or not a file is there. A file that is there but
  refused is named in the console.

"none" and "automatic" still take no source, so a player can turn game maps off or back to automatic for a character
whose source folder is gone; the Imported game PBR page's calls are unchanged (its harness,
`tools/tests/game_pbr_panel_harness.lua`, passes).

### Model reload (finding 24)

[model_reload_policy.h](source/model_reload_policy.h): `RTX_ReloadModelsAfterHardwareSkinningSettings` flushes only
while `materials->GetThreadMode()` is `MATERIAL_SINGLE_THREADED`, and at most twice for one client Lua state (the
allowance restarts in `GMOD_MODULE_OPEN`, which runs for each map). A refused call is not counted, prints why and
returns `false`; a flush returns `true` (the binding returned nothing before). `cl_rtx.lua` makes at most these two
calls: one once `r_forcehwskin` is restored (skipped now if queued rendering is on at that moment) and one a second
after `InitPostEntity` with `mat_queue_mode` switched to 0 for four frames, which passes the check and flushes what the
first would have.

## Tests

The four regressions compile alone with MSVC (`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX`):

- [lua_path_policy_test.cpp](tests/lua_path_policy_test.cpp): the review's two values for `rtx.waterSim.rings.texture`,
  drive-relative values, `..` segments and their look-alikes refused; option values (hash lists, alias pairs, emissive
  strings, vectors) not; `rtx.waterSim.rings.texture` a path option.
- [remix_option_policy_test.cpp](tests/remix_option_policy_test.cpp): every `std::string`, `VirtualKeys`,
  `fast_unordered_set` and `std::vector<XXH64_hash_t>` option of the shipped runtime (86, from a scan of the runtime
  tree at 25c85588b and of `runtime/patches`) with its verdict; the review's list refused whatever its spelling; a
  sample of what the package's Lua sets allowed, with its real values; path values, hash items and sizes. With
  `--verdicts <file>` it judges a list of names.
- [game_source_test.cpp](tests/game_source_test.cpp): a generated PMX, its base texture in three spellings, refusals
  (another texture, no base, images without a model, a missing folder, a text file and a folder named `.pmx`, a
  `.jpg`, a relative path), the cache following a changed model, "options" listing the model's folder and nothing
  with one text for every refusal, "maps" throwing that text.
- [model_reload_policy_test.cpp](tests/model_reload_policy_test.cpp): refused under queued rendering without counting,
  two reloads, then none, two again after a reset.

The loader's Release gate compiles and runs all four on the headers as the fifteen patches leave them, checks the
folder's files against the patch, checks that every text, key or hash option a runtime patch declares has a verdict,
and has the option regression judge every option the package's Lua and data set
([test_lua_guards.py](../../../../../tools/tests/test_lua_guards.py.md)).

Validated build: 5,655,040 bytes, SHA-256 `bbee8323c604cc657fda281d8244d15a2f99a83a21fd4c825921960bc5d6f214`
(`build_modules.ps1 -Only fixes` with the user's fork clone, under a `subst` alias of the worktree's `out`,
garrysmod_common `a854f23`, premake 5.0.0-beta2; the patched tree matched). Not run in a game.
