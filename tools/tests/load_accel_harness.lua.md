# load_accel_harness.lua

Runs the load accelerator's Lua (R26) under LuaJIT with a mocked GMod (convars, `file`, `timer`, `hook`, `cvars`,
`util.IsBinaryModuleInstalled`, `engine.GetAddons`/`GetGames`, `game.IsDedicated`, `SysTime`, `IsInLoading`,
`require`) and a mocked `nlfsaccel` module whose index gives GMod's answers unless a scenario says otherwise.
Arguments: the add-on's autorun ([`!!!!!nlloadaccel.lua`](../../fs_accel/addon/lua/autorun/!!!!!nlloadaccel.lua.md)),
the companion's menu script ([`load_accel.lua`](../../companion/nativeloader/lua/nativeloader/menu/load_accel.lua.md)),
a scenario.

| Scenario | Checks |
|---|---|
| `serve` | installed, no file written, the checks' switch left alone while it is off; `file.Find` replaced; the self-test asks GMod first, later searches are the index's (GMod not asked, `CountFind(true)`); `GAME`, a mounted game's folder and a date sorting go to GMod; `namedesc` from the index |
| `not-title` | a path that is no add-on's title: GMod's answer, `CountFind(false)` |
| `selftest-mismatch` | the index differs in the self-test: GMod answers this and every later search, one line says why |
| `selftest-skip` | an add-on listed as mounted that GMod's table does not hold (GMod finds nothing under it either) is skipped; the others are tested and the index is trusted |
| `selftest-none` | no mounted add-on to compare with: the index is not trusted, one line says why |
| `selftest-changing` | GMod's table changing during the self-test: no verdict, GMod answers; the next search tests again and trusts |
| `verify` | the checks on (`SetVerify(true)`); an index answer GMod does not give: GMod's returned, the difference printed |
| `left-out` | the module leaves the hooks out once (its start-up marker): one line with its reason; add-on searches still go through the index |
| `off`, `no-module` | `nativeloader_load_accel 0` in the server realm, or no module: nothing loaded, `file.Find` untouched, no file kept |
| `off-client` | `nativeloader_load_accel 0` in the client realm: nothing loaded, `data/nativeloader/load_accel_off.txt` written for the menu realm; turned on again, removed |
| `on-client` | on: a file left from an earlier off is removed |
| `invalidate` | `GameContentChanged` invalidates the index |
| `tally` | the client's line 5 s after `InitPostEntity`, and `Settled()` |
| `server-dedicated`, `server-listen` | 5 s after the server's `InitPostEntity` a dedicated server settles, a listen server does not (its client and the menu do); no tally on a server |
| `menu-install` | the menu script installs at menu start, has no convar of its own, writes no file, sets `NativeLoaderLoadAccel`, prints the folders cached; its `Think` hook settles 10 s after the first load ends (not before a load, not during one, not at 9 s) and removes itself |
| `menu-left-out` | the module leaves the hooks out: one line with its reason, `NativeLoaderLoadAccel` stays false, no `Think` hook |
| `menu-off` | the client's off file present: nothing loaded, one line |
| `menu-not-menu` | outside the menu realm: nothing loaded |

Every scenario but two runs as an RTX start of loader 0.16.0 (a mocked `status.json` and the held
`rtx-session.txt`); `not-rtx` (no report) and `not-rtx-marker` (the report, but no marker) check that the add-on
then makes no convar, loads no module and leaves `file.Find` alone (ADR 0206).

Prints `PASS <scenario>`; any difference is a Lua error (nonzero exit). Writes no files and launches no game. Run by
[`test_load_accel.py`](test_load_accel.py.md).
