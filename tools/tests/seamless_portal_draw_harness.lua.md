# seamless_portal_draw_harness.lua

Loads the Seamless Portals entity's shipped client file (`seamless_portal/cl_init.lua` of the fixes part, already
turned into plain Lua by [test_render_mesh_entities.py](test_render_mesh_entities.py.md); path in `arg[1]`) under
LuaJIT with the engine instrumented, and draws portals through `ENT:Draw` in every branch: an unlinked portal, a
linked one outside and inside a portal view, one without its backface, one the Remix runtime claims, and a halo pass.

Fails if the file defines `ENT:GetRenderMesh`, if anything calls `DrawModel` on a portal (the path that crashes
queued rendering at `studiorender.dll+0x6603b`, [ADR 0153](../../docs/decisions/0153-no-entity-hands-gmod-a-lua-mesh-to-draw.md)),
or if a mesh is drawn outside a pushed model matrix. Checks that the frame (backface) is the whole mesh drawn with the
portal's material and normal culling under the portal's transform scaled by its size (what `GetRenderMesh`'s matrix
gave), the flat face flattened with reversed culling and the same material, the stencilled inside and the other side's
texture for a linked portal, nothing for a claimed portal or a halo pass, and one kept mesh per number of sides.

Prints `PASS: portals draw their mesh directly`; exit 1 with `FAIL: <reason>` on stderr otherwise. No game or user
files are accessed.
