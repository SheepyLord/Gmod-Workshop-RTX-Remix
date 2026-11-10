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
