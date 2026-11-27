# cache_key.py

Prints the cache key of one of the package workflow's binary builds (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)): a SHA-256 of exactly the sources
that build reads, so a run reuses a cached build only for the same sources.

```powershell
python tools\ci\cache_key.py runtime
python tools\ci\cache_key.py modules
python tools\ci\cache_key.py hotloader
```

| Build | What the key covers |
|---|---|
| `runtime` | the build files under `runtime/` (patches, `base.json`, `submodules/`, `build_runtime.ps1`), `pins.json`'s NUMOS repository and commit, `collect_runtime.py`, `tools/lib/VsDevEnv.psm1`, and the paths collected from the tagged install |
| `modules` | `build_modules.ps1`, `tools/lib/VsDevEnv.psm1`, the fixes' patches (`fixes.patches`) and RTX Water's (`fixes.rtxwater_patches`, R19), the debug module's and the bridge's source copies, and `pins.json`'s `garrysmod_common`, `premake`, `fixes`, `rtxdebug` and `advmat_bridge` |
| `hotloader` | `build_hotloader.ps1`, `tools/lib/VsDevEnv.psm1`, `tools/inputs.py`, the Model Hotloader's source copy (`packages/model-hotloader/source`), the policy the build rewrites, and `pins.json`'s `hotloader` |

Each file counts with its path and its bytes with CRLF read as LF, so a checkout's line-ending conversion
does not change a key. The workflow prefixes the key with the build's name and `BUILD_SALT`. Exit 0
prints the key. Exit 1 reports a difference between the CI NUMOS pin and the clone the runtime wrapper
fetches. Exit 2 means the build name is unknown. [Cache key tests](../tests/test_ci_tools.py.md)
