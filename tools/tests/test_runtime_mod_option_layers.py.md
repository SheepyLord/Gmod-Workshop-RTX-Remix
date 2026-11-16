# test_runtime_mod_option_layers.py

Checks runtime patch `0101-A-mod-s-Remix-Logic-option-layer-only-its-own-config.patch`
([runtime/README.md](../../runtime/README.md)), the fix of finding 1 of the repository review of 2026-11-16: a Remix
Logic graph in a mod, which the loader deploys from any subscribed Workshop item as content, acquires an option layer
only from a config file in its own folder, the layer applies only rendering options, and a value that fails to parse
is refused instead of thrown out of the graph (or the Remix API).

```powershell
cd tools; python -m unittest discover -s tests -p test_runtime_mod_option_layers.py
```

| Test | Checks |
|---|---|
| the policy's unit test from the patch | writes `rtx_mod_layer_policy.h` and `tests/rtx/unit/test_mod_layer_policy.cpp` as the committed patch creates them into `out\tmp`, compiles them with MSVC (`/std:c++17 /W4 /WX`) and runs them: `PASS mod layer policy: N checks` (authored paths, paths inside the mod's folder, config paths below `rtx-remix/mods`, the options a mod may set, the review's reproduction file, values that fail to parse). Skipped without the VS 2022 Build Tools |
| the policy is self-contained and names the reviewed options | the header includes the standard library only; the allowed namespaces; the integer range; the player's settings, runtime state and debugging options refused; the unit test names the review's minimum (ADR 0112's path options, the water rings' texture, the splash, captures, keys, the interface language, the replacement switches, the sky probe, the hash list of the crash) |
| the parser refuses a path before resolving it and keeps it in the mod | `resolveAssetPath` checks the authored path before USD's resolver looks for it (a share would open a network session) and the resolved path against the mod's folder (its stage's root layer's); a string-typed asset path resolves as a token does |
| the graph acquires a mod's layer and throws nothing | `RtxOptionLayerAction` calls `acquireModLayer`, inside a `catch (const std::exception&)` |
| the option manager checks the path and marks the layer | `acquireModLayer` checks the path against `RtxFileSys`'s mods folder before acquiring; the layer is marked before it first applies; a mod's layer and code never share one; refused keys are logged; a mod's layer creates no dynamic options |
| a mod's layer applies only allowed options and no value throws | `readOptionLayer` refuses what the policy does not allow on a mod's layer; `readOptionLayer` and `readOption` read through `readValueWithoutThrow`; `SetConfigVariable` returns `INVALID_ARGUMENTS` for a value that fails to parse |
| meson lists the header and both unit tests | `src/dxvk/meson.build` and `tests/rtx/unit/meson.build` (the second unit test, `test_mod_option_layer.cpp`, drives the real option manager and is built by the runtime's meson only) |
| no shipped Remix mod uses logic graphs | no `.usda`, `.usd` or `.usdc` in `packages/` holds an `OmniGraph` or `RtxOptionLayer`, so the policy restricts nothing the package ships |

Writes only a scratch folder under `out\tmp`, removed afterwards. Exit 0 when every test passes.
