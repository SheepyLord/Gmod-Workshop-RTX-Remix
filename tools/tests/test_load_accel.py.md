# test_load_accel.py

Unit test (R26) for the load accelerator's Lua: the add-on's autorun
(`fs_accel/addon/lua/autorun/!!!!!nlloadaccel.lua`) and the companion's menu script
(`companion/nativeloader/lua/nativeloader/menu/load_accel.lua`). Runs
[`load_accel_harness.lua`](load_accel_harness.lua.md) with LuaJIT once per scenario (`serve`, `not-title`,
`selftest-mismatch`, `verify`, `left-out`, `off`, `no-module`, `invalidate`, `tally`, `menu-install`,
`menu-left-out`, `menu-not-menu`, `menu-off`) as subtests and requires `PASS <scenario>`. The module itself is tested
by CTest (`nl_fs_accel_tests`, [fs_accel](../../fs_accel/README.md)).

Usage: `python -m unittest discover -s tools/tests -p test_load_accel.py` (also part of `tools\test.ps1`). Skipped
when LuaJIT is not installed (`luajit` on PATH or `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`). No files
written; exit code as unittest's.
