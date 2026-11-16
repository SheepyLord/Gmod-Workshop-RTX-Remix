# separator_mesh_harness.lua

Runs the Mesh Separator's selection engine, the Model Hotloader part's
`mmd_hotloader/lua/mmdhl/separator/mesh.lua` ([ADR 0232](../../docs/decisions/0232-the-mesh-separator.md)), under
LuaJIT. The engine is plain Lua over numbers, so no game is mocked: each scenario builds a small model of boxes and
sheets (outward counter-clockwise, in parts), and looks at it from above with an orthographic projection where boxes
and lassos are needed.

```text
luajit tools\tests\separator_mesh_harness.lua <repo> <scenario>
```

Scenarios: `islands` (seams and back-face copies join a piece, boxes apart stay apart), `raycast` (the nearest
triangle through the grid, from inside it, slanted, with a limit; the piece under a ray), `brush` (triangles within a
radius), `region` (a box and a lasso, through the model and only what is seen, with a coincident inside layer) and
`selection` (add, remove, counts per part, the list, a new snapshot, clear). Each prints `PASS <scenario>` and exits
0, or prints the failed check and exits 1. It reads the engine and writes nothing. Run by
[`test_separator_mesh.py`](test_separator_mesh.py.md).
