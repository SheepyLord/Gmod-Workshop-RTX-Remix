# 0153: No entity in the package hands GMod a Lua mesh to draw; Seamless Portals draw their frame themselves

- Status: Accepted 2026-11-10
- Context: [ADR 0152](0152-hotloader-imports-fast-by-default-and-props-drawn-without-render-meshes.md) traced the
  user's crash on new Model Hotloader imports to GMod's `ENT:GetRenderMesh` path: an entity whose `GetRenderMesh`
  returns a Lua `IMesh`, drawn with `DrawModel`, makes studiorender draw that mesh in its loop over a model's render
  meshes, and under queued rendering (`mat_queue_mode 2`, the user's setting) the material system's render thread
  faults there (`studiorender.dll+0x6603b` from `+0x141b9`, the first mesh with a garbage index register). It was
  reproduced in the PoC with the published package. R4 had found the same fault with the glass shards
  ([RESEARCH](../RESEARCH.md), R4 field facts), and three of issue 2's crashes are at the same offset. After ADR 0152
  the last package code on that path was the Seamless Portals entity in the fixes part
  (`GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/cl_init.lua`), which drew a portal's frame (its backface)
  with `self:DrawModel()` from `ENT:DrawStenciled`, through a `GetRenderMesh` that returned the portal's cylinder mesh
  scaled by the portal's size, re-entering `ENT:Draw` through a `draw_model` flag to reach the engine's draw.

## Decision

1. **No entity in the package hands GMod a Lua mesh to draw.** Code that draws a Lua mesh for an entity pushes the
   entity's model matrix and draws the mesh itself (`cam.PushModelMatrix`, `render.SetMaterial`, `IMesh:Draw`), as the
   glass shards (R4), the Hotloader's static props (ADR 0152) and now the portals do. An empty `ENT:GetRenderMesh`
   that switches the engine's path off is fine. `tools/tests/test_render_mesh_entities.py` scans the package's Lua
   (`packages/`, `glass/addon`, `companion`, `fs_accel/addon`) and fails on a `GetRenderMesh` that returns something.
2. **Seamless Portals:** the entity has no `GetRenderMesh`; its frame is the same mesh drawn by the existing
   `ENT:DrawModelMesh` (the portal's world matrix with its size as the scale, what `GetRenderMesh`'s matrix gave on top
   of the entity's transform) with the portal's material (`models/dav0r/hoverball`) bound, before the flat face and
   the stencilled inside, which keep that material. `ENT:Draw` no longer re-enters itself. The meshes are built once
   per number of sides and never released, so nothing is retired. This is a local change of a GPL-2.0 part, recorded
   in `packages/fixes/README.md`.

## Consequences

- A portal not rendered by the Remix runtime (an unlinked one, a pair beyond the runtime's portal slots, or with
  `seamless_portals_remix 0`) no longer goes through studiorender's render-mesh loop. Its frame is the same
  geometry and material; under RTX Remix it is path traced as before.
- An add-on outside the package that still uses `GetRenderMesh` with `DrawModel` is exposed to the same fault under
  queued rendering; the package does not change other add-ons.
