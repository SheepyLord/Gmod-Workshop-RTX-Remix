# test_arc9_scope.py

Unit test (R25) for the path-traced scopes and the skipped screen-space draws in the RTX fixes' ARC9 patch
(`packages/fixes/.../patcher/addons/cl_arc9.lua`): runs [`arc9_scope_harness.lua`](arc9_scope_harness.lua.md) with
LuaJIT once per scenario (`lens`, `not-looking`, `off`, `no-runtime`, `own-picture`, `cheap`, `blur`,
`screen-draws`, `screen-reads`, `translucent-pass`, `after-view-model`, `deferred`, `vm-attachments`, `far-part`,
`own-lens`, `always-draw`, `additive`, `camera-error`, `hash-override`, `apply`) and requires `PASS <scenario>`. The R24 parts of
the patch keep their own test, [`test_arc9_patch.py`](test_arc9_patch.py.md).

Usage: `python -m unittest discover -s tools/tests -p test_arc9_scope.py` (also part of `tools\test.ps1`). Skipped when
LuaJIT is not installed (`luajit` on PATH or `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`). No files written; exit
code as unittest's.
