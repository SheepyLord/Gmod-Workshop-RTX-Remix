# packages/model-hotloader

The Model Hotloader's part of the RTX package: the importer that turns PMX, PMD, VRM, FBX, glTF and DAE characters
and OBJ, FBX, glTF, PMX and Blender static props into ragdolls, NPCs, player models and placeable props at run time.
Its origin is [SheepyLord/Gmod-Model-Hotloader-with-Vulkan](https://github.com/SheepyLord/Gmod-Model-Hotloader-with-Vulkan)
(MIT, `LICENSE`; the natives' libraries' licences in `licenses/`), release 2.3.1, with this repository's own changes.

| Path | What |
|---|---|
| `mmd_hotloader/` | The add-on, deployed as `garrysmod/addons/mmd_hotloader` |
| `overrides/installation.lua` | Replaces the add-on's install check (`tools/workshop.json` `--addon-file`): game-build findings only in diagnostics ([ADR 0125](../../docs/decisions/0125-hotloader-game-build-findings-are-diagnostics.md)) |
| `bin/` | The natives, deployed to `garrysmod/lua/bin`: `gmcl_`/`gmsv_mmdhl_win64.dll`, `mmdhl_runtime_win64.dll`, the import worker `mmdhl_worker.exe`, CoACD's `lib_coacd.dll` (its wheel's DLL), and `mmdhl-native-release.json` |
| `mods/mmdhl_pbr_linlong/` | RTX Remix PBR materials for Linlong, the character the add-on comes with (`mmd_hotloader/data_static/mmdhl`), deployed to `rtx-remix/mods/mmdhl_pbr_linlong` (`--mod`): the user's pack of 2026-11-16, made with rpai ([ADR 0231](../../docs/decisions/0231-linlongs-rtx-pbr-ships-with-the-model-hotloader.md)) |
| `source/` | The natives' source ([Source.md](source/Source.md)): the origin's commit with its author's staged changes, and this repository's changes as patches |

## The natives

The four natives are built from `source/mmdhl` by [`tools/ci/build_hotloader.ps1`](../../tools/ci/build_hotloader.ps1.md),
which also regenerates the add-on's hash records for them, `mmd_hotloader/lua/mmdhl/native_policy.lua` (the add-on
loads only natives whose SHA-256 it lists) and `bin/mmdhl-native-release.json`
([ADR 0107](../../docs/decisions/0107-the-model-hotloaders-natives-built-from-a-source-copy.md)). GitHub's package
workflow builds them for a release; during development they are built here and imported with `tools\inputs.py import`
with the two records ([ADR 0108](../../docs/decisions/0108-releases-built-on-github-by-hand-development-built-here.md)).
`tools/ci/pins.json` `hotloader` names the origin, its base commit, the release and the source copy.

```powershell
python tools\inputs.py extract model-hotloader --prefix source/mmdhl/ --dest out\<task>\stage\mmdhl   # then edit there
tools\ci\build_hotloader.ps1 -Source <abs>\out\<task>\stage\mmdhl -Vendor <the add-on's bootstrapped vendor folder> -Work <abs short folder> -Out <abs>\out\<task>\built
python tools\inputs.py import model-hotloader --file <built>\model-hotloader\bin\mmdhl_worker.exe=bin/mmdhl_worker.exe ...
```

Extract the stage (a copy of this folder holds `native/shape_atlas.hpp` as `.xz`), give the script absolute paths,
and import the changed sources, a patch of them and `Source.md` with the four natives and both records.

## This repository's changes

- **R19** (the pre-release review): models read their files only inside their own folders, file-access grants keyed on
  the script that asked, a memory budget for loads, loads stopped when the module closes, remote collision shapes
  dropped when unused (`source/r19-changes.patch`).
- **R21-B**: game-build findings only in the installation's diagnostics (`overrides/installation.lua`).
- **2026-11-10, the user's import report** ([handover](../../docs/handover/hotloader-import-report.md),
  [ADR 0152](../../docs/decisions/0152-hotloader-imports-fast-by-default-and-props-drawn-without-render-meshes.md)):
  - static props draw their meshes themselves (`mmd_hotloader/lua/mmdhl/props/render.lua`): their `GetRenderMesh`
    proxy entities crashed the material system's render thread in queued rendering, and the importer previews every
    new import at once;
  - detailed collision (CoACD) serves one import and is no longer a remembered default; a remembered one went back to
    the single hull once (`props/library.lua`, `library.lua`, `ui.lua`, the seven catalogs);
  - the import shows a percentage through every slow stage: CoACD's passes read from its log and its merge estimated,
    a character's Source materials and their package (`source/import-progress.patch`).
- **2026-11-15, the Animation Player's ragdoll collision**
  ([ADR 0224](../../docs/decisions/0224-the-animation-player-answers-a-click-with-its-built-flags.md)): the hair and
  clothing physics' scene capture puts the bodies of an entity flagged `MMDHLSceneExcluded` in its excluded list
  (`mmd_hotloader/lua/mmdhl/secondary_collision.lua`). The character motion importer's colliders, which follow a
  dancing NPC's ragdoll bodies, carry the flag, so hair and clothing collide as before.
- **2026-11-16, the user's report of a black patch on a skirt under RTX**
  ([handover](../../docs/handover/backface-twins-report.md),
  [ADR 0228](../../docs/decisions/0228-back-face-copies-deform-with-the-layer-facing-outside.md)): a character's back-face
  copies (`X+` layers: another part's triangles with the opposite winding) take, at load, the skinning and the vertex
  morph offsets of their twins on the layer facing outside, so a copy can no longer stand outside its cloth and shade
  it black (`source/backface-twins.patch`: `native/backface_twins.hpp`, `model.cpp`, `runtime.hpp`, the C++ test).
- **2026-11-16, Linlong's RTX PBR** ([report](../../docs/handover/linlong-pbr-report.md),
  [ADR 0231](../../docs/decisions/0231-linlongs-rtx-pbr-ships-with-the-model-hotloader.md)): the Remix mod of the user's
  `linlong-rtx` pack (normal, roughness and emissive maps at 2048 for her outfit, hair and flowers), unchanged, as
  `mods/mmdhl_pbr_linlong`. Her PMX's terms forbid redistribution; the user chose to ship it in the public package
  anyway, as the model itself has been. The pack's copy of her model files is the add-on's own and is not stored again.
- **2026-11-16, the mesh separator** ([report](../../docs/handover/mesh-separator-report.md),
  [ADR 0232](../../docs/decisions/0232-the-mesh-separator.md)): the Mesh Separator tool
  (`mmd_hotloader/lua/weapons/gmod_tool/stools/mmdhl_separator.lua`) and `mmd_hotloader/lua/mmdhl/separator/` (the
  selection engine `mesh.lua`, the client, the editor, the server's checks and placement, what both realms share); a
  piece's `source_material` in the prop renderer (`props/render.lua`); its origin and a character's terms in the props
  library (`props/library.lua`); one convex around all of a prop's hulls when the physics engine refuses them
  (`props/server.lua`); the new worker call in the install check's guard (`mmdhl/installation.lua`,
  `overrides/installation.lua`); 63 texts in the seven catalogs; the natives' `mesh` job and the bindings
  `SeparatorMesh` and `PropFromMesh` (`source/separator.patch`).
- **2026-11-16, the separator's selection in its editor only**
  ([ADR 0233](../../docs/decisions/0233-the-mesh-separator-selects-in-its-editor.md)): a left click opens the editor and nothing is drawn on the model in the
  world (`mmd_hotloader/lua/mmdhl/separator/client.lua`, the tool, `separator/editor.lua`); seven texts fewer in the
  seven catalogs.
