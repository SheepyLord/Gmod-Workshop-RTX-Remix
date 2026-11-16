# The Model Hotloader's native source, for the GitHub build

The add-on's four native files in this part's `bin/` (`gmcl_mmdhl_win64.dll`, `gmsv_mmdhl_win64.dll`,
`mmdhl_runtime_win64.dll`, `mmdhl_worker.exe`) are built from `mmdhl/` on GitHub by the RTX package's
workflow (R16, ADR 0107), with the add-on's hash records for them (`native_policy.lua`,
`mmdhl-native-release.json`) regenerated in the same run, so the package carries no native file made on
a local machine. `lib_coacd.dll` is CoACD's own wheel build, which the workflow downloads (ADR 0106).

## Source identity

- Origin: https://github.com/SheepyLord/Gmod-Model-Hotloader-with-Vulkan (MIT), commit
  `ecd7c426c0b50fa3b92cb882059ac46842912f3a` ("Version 2.3.1"), **with the staged, uncommitted changes**
  of its author's worktree `wt-full-textures-props` (branch `feat/gravity-buoyancy-settings`): the
  buoyancy and secondary-water work (`SetSecondaryWater`, `SetSecondaryBuoyancy`, `secondaryGravity`)
  that the shipped 2.3.1 natives export and the packaged add-on uses. No commit holds those changes.
- The worktree had every change staged and none unstaged, and no source file there was newer than the
  shipped `gmcl_mmdhl_win64.dll` (2026-10-26 16:21:10 -0700): the files here are that index's blobs, the
  source of the shipped build (whose five native files were byte-identical to that worktree's
  `build\bin\Release`).
- `mmdhl/` holds what the native build reads: `CMakeLists.txt`, `dependencies.lock.json`, `native/`,
  `shaders/`, the C++ tests and fixtures in `tests/` (CMake declares those targets), the scripts the
  build runs (`scripts/bootstrap.py`, `patch-bullet-threading.py`, `native_manifest.py` with
  `compatibility_profiles.py`, `shaders.py`, `fixtures.py`, and the origin's `build.ps1` for its recipe),
  the licences of the dependencies (`licenses/`, `THIRD_PARTY.md`), `LICENSE` and `README.md`. Left out:
  the Lua add-on (this part ships it in `mmd_hotloader/`), the add-on's Python and Lua tests, the DXVK
  renderer and its patches (the package's runtime is Remix), documentation.
- `staged-changes.patch` is `git diff --cached` of the ten vendored files that differ from the commit;
  `provenance.json` lists every file's size, SHA-256 and git blob as they were copied (R16), those ten
  paths, and the shipped release record.

## Changes made here (R19)

`r19-changes.patch` holds this repository's own changes to the copy, made for the pre-release review
(docs/handover/R19-review.md, R19-H-report.md); applied to the copy `provenance.json` describes, it gives
`mmdhl/` as it is now. They are not in the origin repository:

- **MH-01:** a model reads its textures and other dependencies only inside its import root (its folder, the
  tex and textures folders near it, or the Steam Workshop item it lies in); `..` inside it still works
  (`native/dependency_scope.*`, `assets.cpp`, `props/import.cpp`, `props/material_overrides.cpp`,
  `props/texture_resolver.hpp`).
- **MH-02:** remembered file-access folders are keyed on the requesting script the module finds on the Lua
  stack, not only on the label a script reports (`file_access.*`, `module.cpp`).
- **MH-04 and MH-06:** a model loaded in the game checks its size against the memory free for loading before
  it reads anything (`runtime.hpp` `LoadBudget`, `assets.cpp`), and loads and checks still running stop at
  their next step when the module closes (`module.cpp`).
- **MH-05:** remote collision shapes go when no frame has named them for a minute, within a byte and count
  budget, and the client is told to ask for them again (`scene_share.*`, `module.cpp`).
- **F-03:** `scripts/bootstrap.py` fetches the locked commits with git instead of GitHub's archives.
- The C++ tests for these, and `THIRD_PARTY.md`'s sentence on the bootstrap.

## Changes made here (2026-11-10: import progress)

`import-progress.patch` holds this repository's changes for the user's report of 2026-11-10 (a static prop's physics
took long with no percentage; [handover](../../../docs/handover/hotloader-import-report.md),
[ADR 0152](../../../docs/decisions/0152-hotloader-imports-fast-by-default-and-props-drawn-without-render-meshes.md));
applied after `r19-changes.patch`, it gives `mmdhl/` as it is now. Not in the origin repository:

- `native/props/collision.cpp`: detailed collision's percentage. CoACD 1.0.14 has no progress callback, but at log
  level `info` its logger (spdlog's Windows console sink, `GetStdHandle` and `WriteFile`; the wheel's DLL links its
  C runtime statically) writes each decomposition pass to standard output. Before the DLL loads, standard output
  becomes a pipe (`CoacdProgress`), a thread reads the passes, and the stage's percentage follows them: a piece
  finished in pass N is 2^-N of the mesh, so the finished shares add up to 1 at the end; the merge down to 16 hulls
  logs nothing and is estimated from the number of pieces it merges. Afterwards the log is turned off and standard
  output put back. Without the pipe the stage reports as before (no percentage). Windows only; the Linux build is
  unchanged.
- `native/worker.cpp`: an import with detailed collision (and a part preset with it) shows that stage over 10-95 %
  of its bar instead of 65-86 % (`detailedShare`), since it is nearly all of the import's time.
- `native/assets.cpp`, `native/rig.hpp`: `prepareSourceMaterials` takes an optional progress callback; a character
  import reports "Preparing Source materials" per material (71-93 %), and its textures over 10-70 % (was 10-90 %,
  with the materials at a fixed 91 %), as measured on a 24-material character (2.2 s and 0.9 s of 3.3 s).

The Lua side of the same report is in the add-on in `../mmd_hotloader`: static props draw their meshes themselves
(no `GetRenderMesh` entity: the importer's preview crashed queued rendering), and detailed collision serves one
import instead of being a remembered default.

## Changes made here (2026-11-16: back-face copies)

`backface-twins.patch` holds this repository's changes for the user's report of 2026-11-16 (a black patch on an imported
character's skirt under RTX; [handover](../../../docs/handover/backface-twins-report.md),
[ADR 0228](../../../docs/decisions/0228-back-face-copies-deform-with-the-layer-facing-outside.md)); applied after
`import-progress.patch`, it gives `mmdhl/` as it is now. Not in the origin repository:

- `native/backface_twins.hpp` (new): a model's back-face copies, parts whose triangles lie on another part's points with
  the opposite winding (MMD's `X+` layers), found at load; for each pair of parts, which layer faces outside, voted by rays
  along each layer's normals through a coarse occupancy grid of the rest mesh, else by the parts' names; each copy vertex
  then takes the skinning (type, bones, weights, SDEF parameters) of its twin on that layer (`weldBackfaceTwins`), and
  per vertex morph the offsets that keep it with its twin (`buildTwinMorphFixes`).
- `native/runtime.hpp`: `Model::twinLeads`, `twinMorphFixes` and the `twins` report.
- `native/model.cpp`: `parse` welds the copies after `validateNumbers` and gathers only the twin vertices' morph
  offsets; `Instance::publish` applies the morph corrections with each vertex morph; `buildGpuSkin` counts them in the
  bone boxes' reach.
- `tests/backface_twin_tests.cpp` (CTest `backface_twins`) and its target in `CMakeLists.txt`: the outside vote, a vote
  that overrules a misleading name, the names deciding an open pair, a pair left alone, the morph corrections, the same
  result at every load, a same-wound overlay that is not a copy; with a real PMX it checks named welds and that every
  weld holds under a random pose.

## Changes made here (2026-11-16: the mesh separator)

`separator.patch` holds this repository's changes for the user's request of 2026-11-16 (a mesh separator: a piece of a
character or a vanilla model becomes a prop with generated physics; [handover](../../../docs/handover/mesh-separator-report.md),
[ADR 0232](../../../docs/decisions/0232-the-mesh-separator.md)); applied after `backface-twins.patch`, it gives `mmdhl/`
as it is now. Not in the origin repository:

- `native/props/mesh_prop.hpp`, `native/props/mesh_prop.cpp` (new): the worker's job kind `mesh`. `meshAsset` builds a
  static prop from the triangles a request carries (positions around the piece's origin, normals, UVs, a material per
  triangle), every field checked: materials keep only the fields the bundle format knows, a texture named by its content
  hash is embedded unchanged from the character cache (a missing one is a warning), `source_material` (the Source
  material the part was drawn with) is kept when it is a plain relative path, the parts are grouped by material in
  chunks of 60,000 indices, zero normals take their faces', tangents come from the UVs.
  `automaticCollision` picks CoACD for a closed piece, 12 units across or more, that fills between 2 and 55 percent of
  its fast hull (a ring, a bow) and the fast hull otherwise (small pieces, compact pieces, open shells, a sheet with its
  back-face copy); `measurePiece`
  measures the open edges, the enclosed volume and the hull's.
- `native/worker.cpp`: `meshProp` (a name of 1 to 60 characters, collision `auto`, `hull` or `balanced`, the prop
  saved like a derived one, `separated_from` in its info) and the dispatch of `mesh` jobs; a `mesh` job's status names no
  source.
- `native/module.cpp` (client): `SeparatorMesh(instance, posed)`, the instance's visible parts as one mesh for selecting:
  a JSON string with each part's slot, name, public material, texture hash and triangle ranges, then the positions (the
  drawn world positions or the rest positions at its scale) and the outward counter-clockwise corners as Lua tables
  (GMod's JSON reader stops arrays at 15,000 entries); `PropFromMesh(request[, instance])`,
  which fills a character's piece from the instance (current or rest pose, around the bounds' centre, each part's
  material with its texture hash and its public material as `source_material`) and starts the `mesh` job; it returns the
  job and the centre.
- `tests/mesh_prop_tests.cpp` (CTest `mesh_prop`) and its target in `CMakeLists.txt`, with `mesh_prop.cpp` in
  `mmdhl_props_import`: two boxes keep their materials, embedded texture and source materials through save and load; a
  missing texture warns; a concave closed ring gets CoACD, the same ring a tenth of the size, an open sheet and a sheet
  with its back-face copy the fast hull; indices, materials, paths, numbers and texture references out of range are refused.

## Lua installation override (R21-B)

`../overrides/installation.lua` replaces the add-on's `mmdhl/installation.lua` through
`tools/workshop.json`'s `--addon-file`; it originated in the Vulkan repository and carries this
repository's local policy. R21-B (ADR 0125) keeps game-build findings only in
`status.compatibility`, outside installation warnings and problem counts. Neither the banner nor
the notice asks players to dismiss an unverified build, a failed or unavailable check, or native
interface/slot/class findings. The installation window omits these findings too; Copy diagnostics
still includes the report. One plain console line in each realm's Lua session names unverified
libraries and findings, after pending libraries settle or reach the retry limit; Recheck does not
repeat it. The native source, binaries, guards and feature gating are unchanged. Missing libraries
still wait, and every other warning remains. The user accepts current and future game updates and
will fix actual failures as they occur; R20's separate new-build validation/evidence-refresh task
is dropped. The origin repository is untouched.

## Build

```powershell
python scripts/bootstrap.py               # the locked dependencies (each commit fetched with git; CoACD's wheel)
python scripts/patch-bullet-threading.py  # the add-on's documented Bullet patches
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target mmdhl_client mmdhl_server mmdhl_worker
python scripts/native_manifest.py --bin build/bin/Release --output <a copy of native_policy.lua>
```

`tools/ci/build_hotloader.ps1` runs exactly this. The build identity is `<12 digits of git HEAD>-<UTC
configure time>`: in this repository, HEAD is the commit of this repository being built.
