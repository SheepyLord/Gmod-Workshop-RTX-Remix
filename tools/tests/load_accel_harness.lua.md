# load_accel_harness.lua

Runs the load accelerator's Lua (R26) under LuaJIT with a mocked GMod (convars, `file`, `timer`, `hook`, `cvars`,
`util.IsBinaryModuleInstalled`, `engine.GetAddons`/`GetGames`, `require`) and a mocked `nlfsaccel` module whose index
gives GMod's answers unless a scenario says otherwise. Arguments: the add-on's autorun
([`!!!!!nlloadaccel.lua`](../../fs_accel/addon/lua/autorun/!!!!!nlloadaccel.lua.md)), the companion's menu script
([`load_accel.lua`](../../companion/nativeloader/lua/nativeloader/menu/load_accel.lua.md)), a scenario.

| Scenario | Checks |
|---|---|
| `serve` | installed, no file written; `file.Find` replaced; the self-test asks GMod first, later searches are the index's (GMod not asked, `CountFind(true)`); `GAME`, a mounted game's folder and a date sorting go to GMod; `namedesc` from the index |
| `not-title` | a path that is no add-on's title: GMod's answer, `CountFind(false)` |
| `selftest-mismatch` | the index differs in the self-test: GMod answers this and every later search, one line says why |
| `verify` | the checks on (`SetVerify(true)`); an index answer GMod does not give: GMod's returned, the difference printed |
| `left-out` | the module leaves the hooks out once (its start-up marker): one line with its reason; add-on searches still go through the index |
| `off`, `no-module` | `nativeloader_load_accel 0`, or no module: nothing loaded, `file.Find` untouched |
| `invalidate` | `GameContentChanged` invalidates the index |
| `tally` | the client's line 5 s after `InitPostEntity` |
| `menu-install` | the menu script installs at menu start, writes no file, sets `NativeLoaderLoadAccel`, prints the folders cached |
| `menu-left-out` | the module leaves the hooks out: one line with its reason, `NativeLoaderLoadAccel` stays false |
| `menu-not-menu`, `menu-off` | outside the menu realm, or switched off: nothing is loaded |

Prints `PASS <scenario>`; any difference is a Lua error (nonzero exit). Writes no files and launches no game. Run by
[`test_load_accel.py`](test_load_accel.py.md).
