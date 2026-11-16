# The mesh separator: report (2026-11-16)

The user's request of 2026-11-16: "Plan and implement a mesh seperator in gmod, ask me question to build the idea. It
should allow user pick a or a part of a mesh on vanilla and imported mmdhl model to allow spawning that part of the mesh
as prop with physics model generated. (For example: detach a hairpin from character)". The design came from three rounds
of questions ([ADR 0232](../decisions/0232-the-mesh-separator.md), [plan](mesh-separator-plan.md)). Branch
`mesh-separator`, by Claude; everything is in the Model Hotloader's part (`packages/model-hotloader`, MIT).

## What the player gets

- **Mesh Separator** in the tool menu (Construction, beside Static Prop). Left click selects the piece under the
  crosshair (triangles joined to it, across texture seams and with a layer's back-face copy), right click takes it away;
  the panel switches a click to a whole material part, or to a brush painted while the button is held. Reload opens the
  editor. A click past the model's physics body (a hairpin outside a ragdoll's hull) still reaches the model being
  worked on. The selection and the piece under the crosshair are drawn on the model while the tool is out.
- **The editor**: the model alone in a 3D view (right drag turns, middle drag moves, wheel zooms), parts in their own
  colours, the selection drawn over them; a piece, a part, the brush, a box or a lasso (through the model, or only what
  is seen), Ctrl or the right button to take away; the parts with a tick each; the name, the shape (current or rest
  pose), the physics (automatic, one hull, detailed), freeze and place; Detach with the import's progress.
- **Detach**: the piece becomes a prop of the Static Props library, named after its model and part unless named, with
  physics made for its shape, and appears where it was (current pose: frozen by default, colliding with the world only,
  as the Static Prop tool places) or where the player aims (rest pose). The model itself does not change.

## How it works

| Piece | Where |
|---|---|
| The worker job `mesh`: the request's triangles become a static prop bundle (materials checked, a character texture embedded by its content hash, `source_material` kept, parts by material, tangents, analysis, collision `auto`/`hull`/`balanced`) | `source/mmdhl/native/props/mesh_prop.cpp`, `worker.cpp` |
| `SeparatorMesh(instance, posed)`: a character's visible parts for selecting (JSON) with its positions and corners as Lua tables; `PropFromMesh(request[, instance])`: a character's piece read from the instance, or a vanilla piece as given, as a `mesh` job | `source/mmdhl/native/module.cpp` |
| The selection engine: pieces, the grid, rays, brush, box and lasso, the selection | `mmd_hotloader/lua/mmdhl/separator/mesh.lua` |
| Snapshots, the highlight, the brush, Detach, placing | `separator/client.lua` |
| The server's checks and placement | `separator/server.lua`, `separator/shared.lua` |
| The tool and the editor | `lua/weapons/gmod_tool/stools/mmdhl_separator.lua`, `separator/editor.lua` |
| A piece drawn with its source's material | `props/render.lua` |
| A piece's origin and a character's terms | `props/library.lua` |
| The worker call in the install check's guard | `mmdhl/installation.lua`, `overrides/installation.lua` |
| 64 texts in the seven catalogs | `resource/localization/*/mmdhl.properties` |

## Checks

Offline:

- The selection engine's LuaJIT harness ([`test_separator_mesh.py`](../../tools/tests/test_separator_mesh.py.md)): pieces
  across seams and back-face copies, rays through the grid, the brush, box and lasso through the model and only what is
  seen, the selection set: 5 scenarios pass.
- `tools/check_addon_i18n.py`: the 64 new texts in the seven catalogs (2,096 keys each), 0 problems.
- The C++ test `mesh_prop` (the Hotloader's build): materials, an embedded texture and source materials through save and
  load, a missing texture's warning, the automatic collision (a concave ring 20 units across gets CoACD; the same ring
  2 units across, an open sheet and a sheet with its back-face copy the fast hull), refusals.
- The worker end to end (`mmdhl_worker.exe --request`): a concave ring got CoACD (5 hulls, 2.7 s), a block and a flat
  ribbon the fast hull, at once.

In the PoC (gm_construct, RTX on, 1920x1080; `out/qa-poc/mesh-separator`):

- **Run 1** (`01-branch`): the character snapshot came back cut to 15,000 numbers per array (GMod's JSON reader's
  default limit) and the piece search failed; `SeparatorMesh` now returns tables.
- **Run 2** (`02-branch`):
  - `util.GetModelMeshes`: the packed bodygroup number gives the right meshes (the classic zombie's headcrab: 1 mesh,
    3,360 triangles at 0; 2 meshes, 4,290 with the headcrab; the metrocop's manhack and the jeep's tau cannon alike);
    the skin argument works (the Combine soldier's skin 1: `combinesoldiersheet_shotgun`), though `GetMaterials` stays on
    skin 0's names.
  - Character A (an imported test character; test models other than the game's own are named by placeholders) (67
    visible parts): the snapshot read in 14 ms (209,152 triangles, 125,226 vertices), 145 pieces in 60 ms,
    the grid in 69 ms; the hair ornament (3,268 triangles) gave a 360-triangle piece, and a ray onto it picked the
    same piece.
  - Vanilla: the oil drum whole (252 triangles, one hull, in 0.1 s) placed at the drum's centre (0.045 units off); the
    citizen ragdoll's body (4,427 triangles, 13 CoACD hulls, 6.6 s) placed at the aim in its rest pose; the citizen
    NPC's mouth (230 triangles) placed where it was; all drawn with their models' own materials (5 of 5 for the body).
  - Not placed: both of Character A's pieces. The automatic choice had sent the 3-unit piece to CoACD (16 slivers); small
    pieces now keep the fast hull, and refused hulls fall back to one convex.
  - Under RTX the world highlight drew as a white coating; it is drawn on the screen there now. The editor drew the
    character in its panel, but Detach was below the fold at 1080p; a footer keeps it in view.
- **Run 3** (`03-branch`):
  - Character A's hair-ornament piece (360 triangles) kept the fast hull (0.4 s) and was placed where it was, 0.36 units
    from the mean of its triangles' centres, and again at the aim in the rest pose; both drawn with the character's own
    public material (`mmd/<asset>/...`, found for 1 of 1 slots). Frozen it had one convex, 2 kg and the world-only
    collision group; unfrozen it dropped 2.1 units to the ground. The character kept its own ornament.
  - The drum, the ragdoll's body (13 hulls, 7.0 s) and the NPC's mouth were placed again; every placement answered
    "Placed ...".
  - Under RTX the selection drew on the screen in orange (the drum) and the piece under the aim in blue (the character's hair).
  - The editor showed its footer ("360 of 209,152 triangles selected", Clear, Detach); from its first view the piece is
    behind the character's hair, so run 4 turns the camera to it.
- **Run 4** (`04-branch`): every placement answered "Placed ..." again. In the editor, turned to face the piece from
  outside, 45 of 50 rays cast through the projected centres of selected triangles hit the selection (the other 5 meet
  a triangle in front) and all 50 pass within 0.05 units of the centre they were cast through; a box drawn around the
  selection's projected bounds encloses the orange piece in the screenshot, so a box or a lasso takes what it is drawn
  around.

## Limits

- **The highlight under RTX** is drawn on the screen, through the model (no depth test), at most about 6,000 triangles a
  frame, evenly spread over a larger selection. Outside RTX it is drawn on the model. On the screen it is slow, about
  4 microseconds a triangle: the guard's slow-hook report measured `MMDHL.SeparatorOverlay` at 17.0 ms of every frame in
  run 3 (a 360-triangle piece selected, the character's hair under the aim) and 18.1 ms in run 4 (the citizen ragdoll's
  body selected, 4,427 triangles), worst 46 and 61 ms, so a large selection costs frame rate while the tool is out.
- **A character's piece** draws with the character's own material where the character's materials archive exists on
  that computer; elsewhere with its embedded texture, without its RTX PBR.
- **The selection is made on the pose the model had when it was clicked**; a model that moved is read again at the next
  click, so a dancing NPC is best selected paused or in the editor.
- **A world click** reaches a model through its physics body, or keeps the model already being worked on: the server's
  trace meets physics, not triangles (a hairpin outside a ragdoll's hull is reached after a click on the ragdoll).
- **On a server** a new piece needs an administrator to share it before it is placed, as any imported prop.
- **Not tested in the game**: multiplayer (ownership, sharing), saves and dupes of a piece (ordinary Hotloader props), the
  brush, box and lasso by hand (the harness covers the engine), the 3D highlight outside RTX.

## Gate

`tools\test.ps1 -Config Release` on the branch (`d4d32578`): "All checks passed" (repo conventions OK; C++ 35 of 35;
Python 2,029 tests in `tools`, 1 skipped, 29 in `gmapack`, 26 in `steam`). The run before it (`6eaef0dd`) had two
failures: the render guard's list of bundled files lacked the separator's five modules and its tool, and
`props/render.lua` called GMod's `isstring`, which the renderer's LuaJIT harness does not have; `d4d32578` fixes both.
The guard blocked no separator call in the four PoC runs (no "blocked" line names its files), so the list changes
nothing that was tested. The Hotloader's own C++ test `mesh_prop` is not part of the gate; it ran as above.

## Published

`main` was fast-forwarded to `d4d32578` (the branch's two commits) and pushed (`b96c086f..d4d32578`, four LFS objects,
6.2 MB: the Hotloader's natives). The merge's hook built the package from `packages/` and uploaded item 3829070317 as
**0.0.0-dev.20261116105136+d8d8bbc3** (2,301,138,808 bytes, content digest `9abe4f82...`), its change note the
changelog's new entries; the push's hook found the inputs unchanged. The package differs from the one run 4 used only by
the two gate fixes. Not yet seen in the field: a running game keeps the previous Hotloader until it restarts.
