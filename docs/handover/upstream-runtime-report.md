# The runtime and upstream dxvk-remix main: report (2026-11-14)

The user's request of 2026-11-14: "Make the dxvk-remix up-to-date from upstream. Test in game and post to github and
workshop." Done by Claude on the branch `upstream-1114` ([ADR 0218](../decisions/0218-the-runtime-follows-upstream-dxvk-remix-main.md),
runtime patch 0093, [runtime/README.md](../../runtime/README.md)).

## What changed

The runtime was NVIDIA's RTX Remix 1.6.1 (the user's merge into `sambow23/dxvk-remix-gmod`, patch 0001) plus this
project's patches 0002-0092. Patch 0093 brings it to NVIDIA's `dxvk-remix` `main` of 2026-11-14 (`2b46bed0c`, 57
commits past `remix-1.6.1`), merged with 1.6.1 as the merge base and squashed into one commit on the fork clone's branch
`claude/upstream-main-1114` (`20e3553e`):

- NVIDIA's fixes: eye shading (corrupted over-curved reflections, dark eye whites, iris parallax, a limbal ring), BLAS
  refit after opacity micromaps, incremental bindless updates, first-hit decals and decals through PSR and raytraced
  render targets, skinning (the full bone range, per-vertex stride in the API), particles (collision velocity, frame-rate
  independent drag, emitters kept across compaction), translucent resolve rays, the HL2 RTX start-up, the core fixes
  0091 had already ported (now present twice, identical).
- NVIDIA's features: USDG mesh packages (`usdg.dll`), a water simulation with sludge, an alpha blend dissolve for faded
  objects, particle spawn distribution by surface area, per-emitter screen size and picking, RTXDI compact reservoirs
  and full-resolution reuse for sparse rendering, texture transforms on materials, colour inversion post effect, Hydra
  AOVs.
- RTXDI moves to upstream's `dc8eb03` with the fork's Numos volumetrics as `runtime/submodules/rtxdi.patch`.
- The fork's Remix API becomes 0.1000.2 and stays binary compatible with the package's modules (built against
  0.1000.1): upstream's additions follow the fork's own; a 0.1000.0 or 0.1000.1 client is written only its 328 bytes;
  the new material fields are read only from 0.1000.2 clients.
- Where both sides took the same bits, the fork keeps them and upstream's move (flags0 for the dissolve, opaque flag
  offsets 11-12, a 64-byte particle, padded rows); upstream's outer lock in `remixapi_SetConfigVariable` is left out,
  since it would deadlock with the fork's `readOption`.
- `rtx.eye.irisDepth` gives way to upstream's `rtx.eye.irisDepthScale` and `rtx.eye.limbalRingScale`.

The package ships `usdg.dll` beside `d3d9.dll` (which links it) and its `usd/plugins/usdg/resources/plugInfo.json`;
both Remix schemas and plugin DLLs are rebuilt. `tools/ci/collect_runtime.py` labels `usdg.dll` compiled. The package
grows to 2,147,921,872 bytes, just past 2 GiB; the loader's GMA reader uses 64-bit offsets and `gmpublish.exe` is x64.

## Build and offline checks

- `runtime/build_runtime.ps1` verified the tree against `base.json` and 0001-0093 and built `d3d9.dll` 478,618,112
  bytes, SHA-256 `3237fe73bfc5a243de9fccb86036dccdb350411bafdc30960c5f47c75c59b0e9` (`remix-main+20e3553e`), imported
  with the plugin files. `-Install` stops locally at upstream's `usdg-converter` install step (its batch helper drops the
  `!` of this repository's path); the tool is not shipped and GitHub's runners have no `!` in their paths.
- The runtime's unit suite: 57 of 58 pass. Upstream's API version test, fitted to the fork's line, checks that a
  0.1000.0 and a 0.1000.1 client keep their canary bytes and stock 0.6.x clients are refused; upstream's texture
  transform, camera material and particle picking tests and the fork's MMD alpha test pass with the merged layouts.
  `test_remix_categories` cannot load `d3d9.dll` in its process, as before this update.
- `RtxOptions.md` is regenerated from the build (`test_documentation`).

## In the game (PoC, 2026-11-14)

`poc_session.py` and `release_qa.py` on `GarrysMod_PoC` with the branch's package
(0.0.0-dev.20261114200412+4903e14b), evidence in `out/qa-poc/upstream-1114`:

- **session** (gm_construct, the RTX session probe, the toolgun screen) and **spawnmenu** (External Models, the motion
  importer): pass. Normal quits, no Lua error, `user.conf`, `rtx.conf`, the registry and the loader files unchanged.
- The runtime reports `remix-main+20e3553e`; `usdg.dll` loads beside `d3d9.dll` and Remix logs "USD plugin,
  USDGFileFormat loaded!". The RTX fixes' Remix API is ready and the debug module, built against 0.1000.1, loads
  against 0.1000.2. The Remix log has the same error and warning profile as the published runtime's (29 and 179 lines).
- An extra probe (`out/upstream/npc_eyes_rain_probe.lua`): a citizen's eyes at noon and at golden hour, its face, a
  rainstorm and snow. Rain falls and the storm sky and lit windows render. The eyes show no iris, as with the
  published runtime (GitHub issue 1, `$iris` not shown, known); upstream's limbal ring shows as a faint outline. The
  snow's dark flakes close to the camera and a faint band in the clouds are in the published runtime's shot too.
- **map-glass** and **spawned-glass** fail: the glass add-on's module (`gmcl_nlglass_win64.dll`) never loads in these
  PoC sessions, so no pane breaks into shards and `procedural_shard_4` is not spawned. The published package fails the
  same way in the same sessions (`out/qa-poc/upstream-1114-baseline`), so this predates the update; it is open.
- During the baseline, one PoC start of the published runtime (`remix-main+dd580bc2`) ended with 0xC0000409 while
  another session's field game was starting (`native-loader/logs/sessions/2026-11-14T201324.993Z-34608-crash`). No
  start of the new runtime crashed.

Not covered: VR (the headset), the field install before the publish, Model Hotloader characters, maps with water or
sludge, USDG packages (no mod uses them yet).

## Open

- The glass add-on not loading its module in PoC QA sessions, with the published package too.
- In-game checks on the field after the publish.
- `-Install` with `!` in the path: the fork's `install_file_in_dir.bat` would need to avoid delayed expansion for
  wildcard copies.
