# Seamless Portals off the GetRenderMesh crash path (2026-11-10)

The follow-up named in the [Model Hotloader report](hotloader-import-report.md): after its static props, the fixes
part's Seamless Portals were the last package code drawing a Lua mesh through GMod's `ENT:GetRenderMesh` and
`DrawModel`, the path that crashes the material system's render thread under queued rendering (`mat_queue_mode 2`,
the user's; `studiorender.dll+0x6603b`). Done by Claude on branch `portals`, no Codex, at the user's word ("Do this
task here"). Decision: [ADR 0153](../decisions/0153-no-entity-hands-gmod-a-lua-mesh-to-draw.md).

## The change

`packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/cl_init.lua`
(GPL-2.0, the part's licence; recorded in [packages/fixes/README.md](../../packages/fixes/README.md)):

- A portal drew its frame (backface) with `self:DrawModel()` from `ENT:DrawStenciled`, through `ENT:GetRenderMesh`
  (the portal's cylinder mesh, `Matrix` = its size as a scale, `Material` = `models/dav0r/hoverball`), re-entering
  `ENT:Draw` through a `draw_model` flag to reach the engine's draw. Now the entity has no `GetRenderMesh`; the frame is
  the same mesh drawn by the existing `ENT:DrawModelMesh` (the portal's world matrix with its size as the scale) with
  that material bound, before the flat face and the stencilled inside, which keep it. `ENT:Draw` no longer re-enters.
- Only portals the Remix runtime does not render itself reach this code: an unlinked portal, a pair past the
  runtime's portal slots, or any with `seamless_portals_remix 0`. The meshes are built once per number of sides and
  kept, so no mesh is released while a queued frame might draw it.

## Tests

- [`tools/tests/test_render_mesh_entities.py`](../../tools/tests/test_render_mesh_entities.py.md): the shipped file,
  turned into plain Lua, drawn by [a LuaJIT harness](../../tools/tests/seamless_portal_draw_harness.lua.md) in every
  branch (unlinked, linked outside and inside a portal view, no backface, claimed by the runtime, a halo pass): no
  `GetRenderMesh`, no `DrawModel`, the frame as the whole mesh with the portal's material under its transform scaled by
  its size. It fails at once against the old file. A scan of the package's Lua fails on any `GetRenderMesh` that
  returns a mesh.

## Checked in the PoC

`out/hlfix/poc_hl.py` with `out/hlfix/portal_probe.lua` (main checkout; the Hotloader report's driver, the PoC's loader, package and data moved aside and rolled back after each run): RTX on, `mat_queue_mode 2`, `-noworkshop`, gm_construct, 2560x1440. The probe sets `seamless_portals_remix 0` (the add-on's own stencil path), spawns a linked pair as the spawn menu does (`gm_spawnsent seamless_portal`) and circles the camera round it 160 units out for 30 s, spawns a second pair and circles for 20 s, then gives the pairs to the runtime (`seamless_portals_remix 1`) for 20 s.

| Run | Package | Result |
|---|---|---|
| `repro-portal_probe-160945` | the published `0.0.0-dev.20261110225814+5855bc92` (the Hotloader fix; the old portal code, `render_mesh: true`) | **crashed** about 2 s after the first pair was spawned, before the probe's next line: access violation at `studiorender.dll+0x6603b`, `r14` 0, `r15` 0x388, a garbage `rbx`, the Hotloader's fault |
| `verify-portal_probe-161140` | built here (`0.0.0-dev.20261110230722+3860d976`) | **no crash**, a normal quit, the three screenshots: one pair 30 s (2,264 frames) and two pairs 20 s (1,259 frames) on the stencil path, 20 s (1,904 frames) with the runtime's portals; the frames drawn with the portal's material |

Evidence: `out/hlfix/qa/<run>/` in the main checkout (the crash's dump in `repro-portal_probe-160945/hl-repro-crash/`).

## Built and tested

- `cl_init.lua` re-imported with `tools\inputs.py import fixes --file` (`inputs.py verify`: 14 parts, 0 problems).
- `tools\test.ps1 -Config Release` in `out\worktrees\portals`: all checks passed (CTest 30 of 30, 794 Python tests, one skipped).
