# test_rtxdebug.py

Checks the RTX debug module's source copy in [packages/fixes/licenses/rtxdebug](../../packages/fixes/licenses/rtxdebug/Source.md)
and runs its own regressions in the Release gate. Its patch 0004
([ADR 0237](../../docs/decisions/0237-developers-set-remix-options-through-the-debug-modules-developer-gate.md)) writes
Remix options through the Remix API behind the module's developer gate, and leaves every other write to
`RemixConfig.SetConfigVariable`, whose list ([ADR 0234](../../docs/decisions/0234-what-a-server-a-workshop-item-and-lua-may-reach.md))
refuses debug views to every other Lua.

```powershell
cd tools; python -m unittest discover -s tests -p test_rtxdebug.py -v
```

- `test_the_record_lists_every_checkout_file`: `provenance.json`'s `complete_checkout` names exactly the files in
  `checkout/`, each with its size and SHA-256.
- `test_the_patches_are_one_chain_from_the_base_to_the_pinned_commit`: the folder's patches are the record's, numbered
  in order, each with its size and SHA-256, each applying to the commit the one before made (the first to
  `base_commit`) and naming its result in its `From` line; the last result is `source_commit` and
  `tools/ci/pins.json`'s `rtxdebug.commit`, which builds `checkout/`.
- `test_each_file_the_patches_touch_is_their_last_post_image`: each patch's `index` line for a file starts where the
  patch before left it, and every touched file in `checkout/` has the git object id of the last patch's result (an edit
  of a patched file that no patch carries fails here; the module's `.gitattributes` is `gitattributes.upstream`).
- `test_the_stored_module_is_the_recorded_build`: `packages/fixes/files.json`'s `modules/gmcl_rtxdebug_win64.dll` has
  the size and SHA-256 of the record's `built_artifact`, whose version is the module's `kVersion` and `Source.md`'s
  title.
- `test_writes_follow_the_route_and_restores_the_ledger`: `remix_debug.cpp` asks `Policy::RouteConfig` with the
  native developer gate (`CanMutate()`) and the client rendering gate, records the route of each override
  (`Policy::RestoreThroughApi`), restores through it in `RestoreConfig`, `RestoreAll` and `Shutdown`, and calls
  `RemixConfig.SetConfigVariable` in one place.
- `test_the_api_is_only_asked_for_an_interface_and_set_config_variable`: the module takes `remixapi_InitializeLibrary`
  from `d3d9.dll`, initializes with the headers' own version (pinned to 0.1000.1, the version `RTXFixesBinary` and
  RTX Water ask for: the runtime keeps the latest initialize's version for the process) and calls nothing on the
  interface but `SetConfigVariable`.
- `test_the_gate_reads_nothing_from_lua`: the developer gate needs the game thread, an open module, `-insecure` from
  the command line, single-player from the engine client and `sv_cheats`.
- `PolicyRegressions` (Windows with the VS 2022 Build Tools; skipped otherwise): compiles
  `checkout/tests/render_policy_test.cpp` and `session_policy_test.cpp` with `cl /EHsc /std:c++17 /W4 /WX` and runs
  them. The first is the regression for debug views: it fails on a copy of the route that sends every write to
  `RemixConfig` (the module before patch 0004) and on one that sends every write to the API.

Writes only a temporary folder under `out\tmp` (compiler output), removed afterwards. Exit: unittest's.
