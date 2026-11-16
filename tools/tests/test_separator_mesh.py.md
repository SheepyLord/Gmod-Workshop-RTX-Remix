# test_separator_mesh.py

Python unit tests for the Mesh Separator's selection engine, `mmd_hotloader/lua/mmdhl/separator/mesh.lua` in the
Model Hotloader part ([ADR 0232](../../docs/decisions/0232-the-mesh-separator.md)). Each test runs one scenario of
[`separator_mesh_harness.lua`](separator_mesh_harness.lua.md) under LuaJIT (on `PATH`, or
`%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`) and expects `PASS <scenario>`; without LuaJIT they are skipped.

What they hold: pieces join across texture seams and with their back-face copies, and pieces apart stay apart; a ray
finds the nearest triangle through the grid from outside or inside it, slanted or straight, and stops at its limit; the
piece under a ray is the whole piece; the brush takes the triangles within its radius and nothing beside the model; a
box or a lasso on the screen takes, through the model, every triangle inside, and otherwise only what the camera sees
there with a coincident inside layer; the selection adds, removes, counts per part, lists, carries to a new snapshot of
the same parts and clears.

```powershell
python tools\tests\test_separator_mesh.py
```

Run by `tools\test.ps1` with the other Python tests. Writes nothing. Exit code 0 when every test passes or is skipped.
