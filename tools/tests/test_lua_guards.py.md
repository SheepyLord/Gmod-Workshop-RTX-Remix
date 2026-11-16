# test_lua_guards.py

Checks the RTX fixes' fifteenth native patch, [lua-guards](../../packages/fixes/licenses/oversized-skinning/lua-guards/README.md):
the repository review of 2026-11-16, findings 2, 7 and 24. What any server's client Lua may ask of
`gmcl_RTXFixesBinary_win64.dll`: `RemixConfig.SetConfigVariable` takes only the Remix options the RTX package's own Lua
sets, ToPBR's game-map actions read only the character's own model, and the model reload runs only while the material
system is single-threaded, at most twice a map.

```powershell
cd tools; python -m unittest discover -s tests -p test_lua_guards.py -v
```

- `test_complete_files_are_the_patch_applied`: `lua-guards.patch` touches exactly its eleven files. Each changed file
  is the last earlier copy with the patch applied (`lua_path_policy.h` and `tests/lua_path_policy_test.cpp` from
  autopbr, `to_pbr.cpp` from topbr-scope, `module.cpp` from backrooms, `config_lua_bindings.cpp` from upscaling-state;
  no folder between holds the file), each new file the patch's added lines. `tools/ci/pins.json` builds the module with
  the patch last, right after topbr-scope.
- `test_set_config_variable_takes_only_the_packages_options`: the generic setter asks
  `RemixOptionPolicy::LuaMaySet` before the Remix API; every other setter of the binding names its option; the review's
  list (captures, replacement switches, the sky probe's size, crash and debugger hotkeys, the profiler, automation, free
  camera keys, the splash, the path options with `rtx.waterSim.rings.texture`) is refused by name; the policy header
  includes no Windows header.
- `test_every_runtime_text_key_and_hash_option_is_reviewed`: every option of type `std::string`, `VirtualKeys`,
  `fast_unordered_set` or `std::vector<XXH64_hash_t>` declared on a line a runtime patch (`runtime/patches`) adds has a
  verdict in `kRuntimeOptions` of `tests/remix_option_policy_test.cpp`, which checks the policy gives it. A runtime
  update that adds such an option fails here until it is reviewed. Options the fork's base commit declares and no
  patch touches are in the table from a scan of the packaged runtime tree (25c85588b). Declarations in the runtime's
  own unit tests (a patch's files under `tests/`, such as patch 0101's `rtx.modLayerTestHashes`) are not options of
  the shipped `d3d9.dll` and are left out.
- `test_the_shipped_options_are_found`: the option names the package's Lua and data set are collected (no compiler
  needed): the quoted names in every Lua file under `packages/`, `companion/nativeloader/`, `vr/addon/`,
  `glass/addon/` and `fs_accel/addon/` that calls `SetConfigVariable` (with a `sh_config.lua` beside it), the weather
  presets the sky sets, the eye whites' `rtx.gmod.` names, the default map config's `rtx:` lines and the content
  packs' profiles under `skills/workshop-content-pack/scripts/astra_companion/`. Names those files only read
  (`READ_ONLY`) are left out; the test fails when an exemption no longer appears anywhere.
- `test_game_material_actions_read_only_the_characters_model`: "options" lists through `GamePBR::ListOptions`, "maps"
  scans through `GamePBR::SourceFolder` before reading families and takes only images the folder lists, an automatic
  resolution counts only a usable model as its source, and no worker path calls `discovery.Get` directly;
  `game_source.h` answers every refusal with `SourceRefusal`.
- `test_the_model_reload_runs_single_threaded_twice_a_map`: the binding asks `materials->GetThreadMode()` and the
  allowance before it flushes, the allowance restarts in `GMOD_MODULE_OPEN`, and `cl_rtx.lua`'s last call still
  switches `mat_queue_mode` to 0 (the native check needs it).
- `LuaGuardRegressions` (Windows with the VS 2022 Build Tools): the module's sources as the fifteen patches leave them
  (every patch folder's `source/` and `tests/` in `pins.json`'s order, later over earlier) are copied to a scratch
  tree under `out\tmp`; `lua_path_policy_test`, `remix_option_policy_test`, `model_reload_policy_test` and
  `game_source_test` are compiled with `cl /EHsc /std:c++17 /W4 /WX /UNDEBUG` and must print their `PASS` lines; then
  `remix_option_policy_test --verdicts` judges every collected option name and none may be refused.

Reads only this repository; the C++ checks write and remove a scratch folder under `out\tmp`. Exit codes: unittest's.
