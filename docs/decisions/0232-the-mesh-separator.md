# 0232: The mesh separator: a piece of a model becomes a Hotloader static prop

- Status: Accepted 2026-11-16 (the user's request and answers; the checks in the report). **Superseded in part by
  [0233](0233-the-mesh-separator-selects-in-its-editor.md)**: the selection is made in the editor only; nothing is drawn on the model in the world.
- Decided by: the user, through the design questions of 2026-11-16 ("Plan and implement a mesh seperator in gmod, ask me
  question to build the idea. It should allow user pick a or a part of a mesh on vanilla and imported mmdhl model to
  allow spawning that part of the mesh as prop with physics model generated. (For example: detach a hairpin from
  character)"); how it is built was the agent's choice.
- Builds on: [0107](0107-the-model-hotloaders-natives-built-from-a-source-copy.md) (the Hotloader's natives built from
  the source copy here), [0152](0152-hotloader-imports-fast-by-default-and-props-drawn-without-render-meshes.md) (props
  draw their own meshes; collision choices), [0153](0153-no-entity-hands-gmod-a-lua-mesh-to-draw.md) (no render mesh
  handed to the engine), [0228](0228-back-face-copies-deform-with-the-layer-facing-outside.md) (a character's parts).
- Plan: [mesh-separator-plan.md](../handover/mesh-separator-plan.md); report: [mesh-separator-report.md](../handover/mesh-separator-report.md).

## Context

A player wants to take a piece off a model, such as a hairpin off a character, and play with it as a prop of its own.
The pieces are the triangles of a model: an imported Model Hotloader character (drawn by the Hotloader's native module)
or a vanilla Source model (a prop, a ragdoll, an NPC). The Hotloader already turns model files into static props with
generated collision, keeps them in its props library, spawns, saves, duplicates and shares them; nothing turned a part
of a model in the game into one.

## Decision (the user's answers)

1. **A toolgun tool, Mesh Separator**, in the tool menu's Construction category beside the Static Prop tool.
2. **Four ways to pick**: click a connected piece under the crosshair (add or remove it), a whole material part, a paint
   brush, and a box or lasso in the editor's 3D view.
3. **The shape**: the player chooses the current pose (as it looks now) or the model's rest pose.
4. **One solid prop**: a piece with bones of its own (a ponytail) becomes rigid in its detached shape.
5. **Physics, automatic**: one convex hull for compact pieces, a convex decomposition (CoACD) for concave closed ones;
   the player can choose either instead. A piece under 12 units across keeps the single hull: in the game, CoACD cut
   Character A's 3-unit hair ornament into 16 slivers, and the piece was not placed.
6. **A reusable prop in the Model Hotloader's props library**: spawned again from Static Props and the Static Prop tool,
   kept by saves and dupes, shared like the Hotloader's props.
7. **The source stays as it is**: the user cancelled "remove from source" (Source cannot hide single triangles of a
   vanilla model).
8. **Vanilla models**: props, ragdolls and NPCs (not the player's own model).
9. **Servers**: a player takes pieces off models they own (prop protection's owner, or who spawned it), administrators
   off any; `mmdhl_separator_enabled 0` switches the tool off.

## Decision (how it is built)

- **One new worker job, `mesh`**, beside `derive` (`worker.cpp`, `props/mesh_prop.cpp`): the request carries the piece's
  triangles (positions around its centre, normals, UVs, a material per triangle), and the worker builds a static prop
  bundle with the props pipeline's own steps (tangents, material analysis, collision, `saveAsset`). A bundle in the cache
  is all the library needs, so listing, preview, spawning, dupes, sharing and the Workshop work as for an imported prop.
  Every field of the request is checked; a texture is taken only from the character cache by its content hash.
- **A character's piece** is read in the game module from the instance itself (`PropFromMesh`): the drawn vertices for
  the current pose, the rest vertices at the instance's scale for the rest pose, and each part's texture by its content
  hash, embedded unchanged. The library records `separated_from` (the character's asset) and gives the piece a copy of
  the character's terms of use.
- **A vanilla piece** is read in Lua from `util.GetModelMeshes` (with the entity's bodygroups as the packed m_nBody
  number, and its skin), skinned to its bones now for the current pose, at the model's scale for the rest pose, and
  refers to the Source materials it is drawn with: a mesh's slot is the model material with the same path, else one
  ending like it, else the only one, and that slot's override wins unless it is a procedural `!` material of this
  session. A model whose bones do not exist yet is refused rather than read in its rest pose. Under RTX Remix the
  previous model's mesh result is let go over two garbage-collector cycles before another is read (the destruction
  tool's `client.dll` crash window). These follow the code survey of 2026-11-16
  ([plan](../handover/mesh-separator-plan.md)); the bodygroup and skin conventions are checked in the game.
- **`source_material`** (an optional material field the bundle format passes through): the prop renderer draws such a
  slot with that material when it exists (the character's own `mmd/...` material from its mounted archive, or the
  vanilla model's), so the piece looks like its source and keeps its RTX Remix replacements (the same textures, the same
  hashes); without it, the embedded texture. Tinted draws (the colour tool, the placement ghost) keep the prop's own
  materials, with the source's base texture where the piece has none.
- **The selection** (`separator/mesh.lua`, plain Lua) works on a snapshot of the model in the pose it had when it was
  clicked (`SeparatorMesh` for a character, the skinned `GetModelMeshes` for a vanilla model): pieces are triangles
  joined by shared corners, corners joined where they lie at the same place (texture seams, back-face copies), rays go
  through a uniform grid, the brush takes triangles within its radius, and a box or lasso takes what it covers, through
  the model or, by a small depth buffer over the region, only what the camera sees.
- **The server checks every click** (the tool sends the target to its owner only when `S.MayUse` allows it) and every
  placement, and answers a placement with its own message (placed, or refused and why, also in the console): the
  Hotloader's notices all show as errors. The selection lives on the client.
- **A prop whose hulls the physics engine refuses** is placed with one convex around all their points (in the props'
  server code, so for every Hotloader prop) instead of not at all.
- **The current pose appears where it was**: unrotated at the centre of its vertices, frozen by default, colliding with
  the world only (the Static Prop tool's settings); a rest-pose piece is placed where the player aims, like the Static
  Prop tool.
- **The highlight**: outside RTX, translucent triangles after the translucent pass (as the Advanced Bodygroup Tool's);
  under RTX Remix, where the path tracer draws such meshes as a white coating (vertex colours are not its albedo), the
  selection, the piece under the aim and the brush are drawn on the screen in the interface pass, through the model.
- **The editor** draws with UnlitGeneric `vgui/white` materials, which Remix draws as interface in a panel, as the
  Hotloader's previews are; the editor projects and casts rays from `util.AimVector`'s
  pixel rays in its own coordinates (`Vector:ToScreen` is inaccurate inside a panel's `cam.Start3D` viewport, as the
  bodygroup tool's cut editor found), so rays and regions match the picture.
- **Behaviour, not code, from the user's other add-ons**: the bodygroup tool, the destruction tool and the material
  editor carry no licence file, so the separator reimplements what it learned from them; the GPL fixes are read only.

## Consequences

- The Model Hotloader's natives are rebuilt (two client bindings, a worker job), with a C++ test.
- A vanilla piece needs its source's content where it is drawn (as the model itself does); a character's piece falls back
  to its embedded textures when the character's materials are not on that computer, and then loses its RTX PBR.
- Large concave pieces take CoACD's time (seconds to a minute) with the import's progress shown.
- On a server, other players see a piece once an administrator shares it, as for any Hotloader prop; a player who is
  not an administrator keeps it in their library.

## Alternatives considered

- **Write the piece to a model file and import it**: GMod's `file.Write` refuses those extensions, servers refuse
  imports of files the player did not pick, and the importers rescale and re-encode.
- **A Lua entity with its own mesh and physics**: no library, no sharing, a second drawing and dupe path; the Hotloader
  already has all of them.
- **Remove the piece from its source**: cancelled by the user.
- **A separate top-level add-on** (as `glass/addon` is), which the code survey suggested: the separator needs the
  Hotloader's worker, native instances and props library, so it ships and is versioned with them.
- **A "recipe" entity** (model, bodygroups, skin, triangle set) that the server rebuilds from `util.GetModelMeshes`, also
  from the survey: it works only for vanilla models (the server cannot read a character's triangles), and needs its own
  drawing, physics, dupes and network path, where a Hotloader prop bundle already has all of them for both kinds.
- **Mark the piece as a derived prop (`derived_from`)**: the library would treat it as a part preset of a static prop.
