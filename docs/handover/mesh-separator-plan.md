# The mesh separator: plan (2026-11-16)

The user's request of 2026-11-16: "Plan and implement a mesh seperator in gmod, ask me question to build the idea. It
should allow user pick a or a part of a mesh on vanilla and imported mmdhl model to allow spawning that part of the mesh
as prop with physics model generated. (For example: detach a hairpin from character)". The design questions and their
answers are in [ADR 0232](../decisions/0232-the-mesh-separator.md). Branch `mesh-separator`, worktree
`out\worktrees\msep`; everything lives in the Model Hotloader's part (`packages/model-hotloader`, MIT).

## What the player gets

- **Mesh Separator** in the tool menu (Construction, beside Static Prop).
  - Left click on a model: add the connected piece under the crosshair. Right click: remove it. Hold either with the
    brush on: paint triangles in or out. Reload: open the editor.
  - The tool's panel: what a click selects (a piece or a whole part), the brush and its size, the pose (current or
    rest), the physics, freeze and place, the piece's name, Detach, Clear, Open the editor.
- **The editor**: the model alone in a 3D view (turn, move, zoom), the selection drawn over it; a piece, a part, the
  brush, a box or a lasso (through the model or only what is seen), the parts with a tick each; the name; Detach with
  the import's progress.
- **Detach**: the piece becomes a static prop in the Model Hotloader's props library (named after its model and part),
  and appears where it was (current pose) or where the player aims (rest pose), with its physics generated.

## What the code survey found (2026-11-16)

An Explore agent surveyed the repository's vanilla mesh reading, picking and tool code before the design was fixed
(`util.GetModelMeshes` callers, skinning, connectivity, highlights, 3D panels, the props pipeline, tool conventions,
licences). What it found, and what the separator does with it:

| Finding | Where it was found | The separator |
|---|---|---|
| Skinning a bind-pose vertex: `GetBoneMatrix(b) * bind[b].matrix * pos`, weighted; the bind matrix is Source's pose-to-bone matrix, never inverted; one bone or none: `LocalToWorld` | Advanced Material Editor `cl_58_meshuv.lua` 619-733 | `S.Skinning` does the same; a model whose bones do not exist yet is refused ("still loading") instead of being read in its rest pose, as the editor's retry does |
| A matrix from `GetBoneMatrix` may change at the next `SetupBones`: copy it | destruction tool `cl_30_overlay.lua` 1366-1368 | the product `live * bind` is a new matrix, taken at once |
| Two bodygroup conventions in use: a packed m_nBody number (material editor, ARC9 patch) and a base-36 digit string (bodygroup tool, destruction tool) | AME 587-609; ABT `cl_uv_hide.lua` 161-176, 196-215 | the packed number (`S.BodyMask`); **checked in the PoC** against the digit string on a model with a bodygroup |
| A claim that `GetModelMeshes` returns skin 0's materials whatever the skin argument | `remixbinary ... cl_static_prop_renderer.lua:603` (GPL, read only) | the skin is passed; **checked in the PoC** on a model with several skins |
| Meshes name their material, not their slot; `GetMaterials` drops missing ones; overrides by slot; procedural `!` overrides | ABT `FindSubmaterialIndexes` 841-859, `ResolveSourceMaterial` 1246-1261 | the slot by exact path, else a path ending like it, else the only one; a `!` override (this session's `CreateMaterial`) is not kept, the model's own material is |
| Under RTX Remix, heavy work right after a large `GetModelMeshes` result became garbage crashed `client.dll`; two garbage-collector cycles first | destruction tool `cl_29_mesh_preparation.lua` 15-38, `cl_32_mesh_persistence.lua` 477-482 | the previous snapshot's result is dropped and two cycles stepped (at most 0.5 s, never a full collection) before another model is read |
| Connectivity: by shared vertex tables (UV islands, one material) or by positions to 1/1000 within one mesh; nothing across materials | AME 170-281, ABT `DiscoverMeshRegions` 314-414 | positions to 1/1000 across the whole model, so a piece crosses seams and materials and keeps its back-face copy |
| `Vector:ToScreen` is inaccurate inside a panel's `cam.Start3D` viewport; invert `util.AimVector` | ABT `cl_vertex_keep_editor.lua` 525-552 | the editor projects and casts rays from `util.AimVector`'s pixel rays, in the view's own coordinates |
| Box, lasso and brush on 3D triangles exist nowhere; the material editor's UV canvas has the interaction pattern | AME `cl_74_texeditor.lua` 93-125 | new, in `separator/mesh.lua` (a depth buffer for "only what is seen") |
| No entity may hand GMod a Lua mesh to draw (`GetRenderMesh`); draw under the model matrix, retire meshes 8 frames later | ADR 0152, ADR 0153 | the pieces are Hotloader props (drawn by `props/render.lua`); the highlight and the editor draw their own meshes and retire them |
| Flat point sets fail Source's convex constructors | the GPL glass shards (behaviour only) | the props pipeline's fast hull already gives flat geometry a thickness (a box when degenerate); a flat ribbon was checked through the worker |
| Hotloader characters: the natives cap a material at 90,000 indices and exist only in the client module | Hotloader `module.cpp` | `SeparatorMesh` has no per-material cap; selection is client-side, the server only checks and places |
| The bodygroup, destruction and material editor add-ons carry no licence file (the user's own) | `packages/README.md` | their code is read for behaviour; nothing is copied |

The survey recommended a new top-level add-on and a compact "recipe" entity (model, bodygroups, skin, triangle set) that
the server rebuilds. The separator stays in the Model Hotloader instead: a piece needs its import worker and native
instance, and as a Hotloader prop it gets the library, dupes, saves, sharing and the Workshop without a second entity
(ADR 0232, alternatives).

## Components

| Piece | Where | What |
|---|---|---|
| Worker job `mesh` | `source/mmdhl/native/worker.cpp`, `props/mesh_prop.cpp` (new) | validates the request; vertices, tangents, parts of 60,000 indices, materials, embedded character textures; `analyzeMaterials`; collision `auto` (fast hull, or CoACD when the piece is closed and concave); `saveAsset` |
| Client bindings | `source/mmdhl/native/module.cpp` | `PropFromMesh(json, instance)`: a character's piece from the instance (posed or rest vertices, normals, UVs, texture hashes, the parts' public materials), a vanilla piece as given by Lua; launches the job. `SeparatorMesh(instance, posed)`: the instance's visible parts (JSON) with positions and corners as Lua tables (GMod's JSON reader stops arrays at 15,000 entries) |
| `source_material` | `mmd_hotloader/lua/mmdhl/props/render.lua` | a slot with an existing Source material draws with it |
| Selection engine | `mmd_hotloader/lua/mmdhl/separator/mesh.lua` | pieces, the picking grid, ray picking, brush, box and lasso (through the model or by a small depth buffer), parts, the selection (plain Lua, tested under LuaJIT) |
| Snapshots, requests and spawning | `separator/client.lua`, `separator/server.lua`, `separator/shared.lua` | snapshots (character through `SeparatorMesh`; vanilla through `util.GetModelMeshes`, skinned, with the RTX settle), the request, the job through `library.StartImport`, the name, the placement in place or at aim, the world highlight, the brush; the server's checks (`mmdhl_separator_enabled`, ownership, a short cooldown) |
| Tool and editor | `lua/weapons/gmod_tool/stools/mmdhl_separator.lua`, `separator/editor.lua` | the tool and its panel, the editor window |
| The library | `props/library.lua` | a piece's `separated_from` and a character's terms copied to it |
| Catalogs | `resource/localization/<language>/mmdhl.properties` | English and the six languages |

## Phases

1. The worker job and the bindings, with a C++ test (`mesh_prop_tests.cpp`) and the worker end to end (a concave ring,
   a block, a flat ribbon). The natives are rebuilt with `tools\ci\build_hotloader.ps1`.
2. `source_material` in the renderer; the selection engine with a LuaJIT harness test (pieces, rays, brush, box and
   lasso, the selection); the server side.
3. The tool, the highlight and the editor; the catalogs.
4. The PoC: the survey's two conventions (bodygroups, skins); a piece of Character A's hair ornament (an imported test character, named by a placeholder) (current and rest
   pose), a piece of an oil drum, a vanilla ragdoll and an NPC; the prop's physics; the editor's projection against its
   picture; RTX look. Then the documents, the gate, the merge and the publish.

## What the game runs changed

- Run 1: GMod's JSON reader stopped the snapshot at 15,000 entries per array; `SeparatorMesh` returns tables.
- Run 2: the snapshot reads in 14 ms (209,152 triangles); the bodygroup number and the skin argument work (the GPL
  renderer's claim about skins is wrong; `GetMaterials` does not follow the skin, the meshes do). Character A's 3-unit hair
  ornament went to CoACD (16 slivers) and was not placed: pieces under 12 units keep the fast hull, and refused hulls
  fall back to one convex. Under RTX the world highlight drew as a white coating: it is drawn on the screen there. The
  editor's Detach was below the fold at 1080p: a footer keeps it in view.

## Risks

- **Selection on large models in Lua**: Character A's snapshot is about 250,000 triangles; read as tables, then pieces and
  the grid once per model and pose.
- **The world highlight and the editor under RTX**: drawn with UnlitGeneric `vgui/white` materials, as the bodygroup
  tool's highlight and the Hotloader's previews are; checked in the PoC.
- **Vanilla skins and bodygroups**: the two conventions above, checked in the PoC before the merge.
