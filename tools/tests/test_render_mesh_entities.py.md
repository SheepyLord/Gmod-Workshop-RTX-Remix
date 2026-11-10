# test_render_mesh_entities.py

No entity in the RTX package hands GMod a Lua mesh through `ENT:GetRenderMesh`
([ADR 0153](../../docs/decisions/0153-no-entity-hands-gmod-a-lua-mesh-to-draw.md)): drawn with `DrawModel`, that path
crashes the material system's render thread under queued rendering (`studiorender.dll+0x6603b`, the user's
`mat_queue_mode 2`).

- `test_no_lua_in_the_package_provides_a_render_mesh`: every `.lua` under `packages/`, `glass/addon`, `companion` and
  `fs_accel/addon`; a `GetRenderMesh` definition whose body returns something fails it, an empty one (the glass
  shard's, which switches the path off) does not. Comments are ignored.
- `test_the_scan_finds_a_provider`: the scan finds the portal's old definition and the Model Hotloader's old proxy.
- `test_portals_draw_their_mesh_directly`: turns the Seamless Portals entity's `cl_init.lua` (GLua) into plain Lua
  with `glua_to_lua` from [test_glass_map.py](test_glass_map.py.md), in a temporary folder under `out\tmp`, and runs
  [the harness](seamless_portal_draw_harness.lua.md) on it with LuaJIT (skipped without LuaJIT). Against the file
  before the change it fails at once ("the portal must not define ENT:GetRenderMesh").

Run `python -m unittest discover -s tools/tests -p test_render_mesh_entities.py`. No game, network, Workshop upload or
profile change. Exit follows unittest.
