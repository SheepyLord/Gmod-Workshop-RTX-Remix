# "Loading enhancements" at every start: report (2026-11-12)

The user's report: "The field game takes a long time to load enhancements each start", with a screenshot of the main
menu's box "Loading enhancements / Processing Materials (496 processed)". A task from the coordinating session (VR
milestone V4). Done by Claude on the branch `mod-load-cache` (worktree `out\worktrees\mlr`); package only: runtime
patch 0086 in the RTX package, no loader (`winmm.dll`) change. Merged into `main` as `8a654395` after the shipped
DLL's PoC series and published to Workshop item 3829070317 (see the end).
[ADR 0195](../decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md); facts in
[RESEARCH.md](../RESEARCH.md) ("Loading enhancements": what the runtime's mod load spends its time on).

## What shows the box and does the work

The Remix runtime itself, not a Lua add-on, the companion, ToPBR/rpai or the load accelerator:

- `dxvk_imgui.cpp` shows "Loading enhancements" while any USD mod in `rtx-remix\mods` is opening or processing, with
  "Processing Materials (N processed)" per loading mod, once the load has lasted 1.5 s (patch 0001's delay).
- The load runs on the runtime's asset thread from the main menu on (after GMod's browser, `libcef.dll`, is up), one
  mod after another. The menu needs none of it; a map started earlier draws without replacements until it is done.
- Per texture reference of every material it opened the DDS file to parse its headers, then opened and mapped it again
  to stage the five smallest mips, and parsed it again for every further material naming it. Nothing was kept between
  starts. The field's mods: 25,487 references to 16,700 files (70 GB) in 28 folders.

## Measured on the PoC

`tools/qa/mod_load_session.py` (under `out\r10\poc.lock`, the PoC snapshotted and restored, rollbacks clean): the
published package's content and the user's 12 subscribed content packages (`--subscribed-content on`, 19 mods, 17,970
references to 9,042 files), gm_construct at 1600x900, `-noaddons -noworkshop`. "Cold" = the mods' files purged from
Windows' file cache first (`purge_file_cache.py`, no administrator rights), as after a reboot or a long session.

| Start | Before (patch 0086's timing lines, old loading) | After (patch 0086) |
|---|---|---|
| First after the content is unpacked | 27.3 s (`find` 24.0 s) | the cache is made at the first start (below) |
| Cold, no cache yet (first start with the patch) | 11.5 s (`find` 8.2 s, staging 1.5 s) | 10.8 s, cache written in 35 ms (7.2 MB) |
| Warm (second start) | 1.83 s | **1.09 s** |
| Cold, cache present | 11.5 s | **1.36 s** |

- The published package (no timing lines, its log markers): 5.9 s at its first start after an unpack, 1.7 s at the next.
- With the cache every one of the 9,042 files was a hit; no DDS file was opened. `find` fell from 8.2 s (cold) to 81 ms
  (folder listings 11-16 ms, reading the 19 cache files 36-38 ms). What is left (about 1 s) is USD: opening the stages,
  resolving the asset paths, Safehouse's meshes. Both later starts are under the box's 1.5 s delay: it no longer
  appears in the PoC.
- **The result is the same.** All 9,042 entries checked against their DDS files with `check_mod_texture_cache.py`:
  the recorded headers match and the 8,989 kept tails (the others have no full mip chain) equal the files' bytes.
  The pinned gm_construct view (gm_construct_rtx's PBR) before and after differs by `block_diff` 0.47-0.48, inside
  the 0.36-0.98 between two starts of one build (the sky moves with the time of day).
- Evidence: `out\mlc\base1` (published package), `out\mlc\ab1` (instrumented vs patched, with screenshots),
  `out\mlc\final1` and `out\mlc\final2` (the confirmation series below); each has `results.json`.

### Confirmation with the shipped build

The A/B's build wrote its cache under `bin\win64` (the bug below), and the ADR's renumbering (0194 to 0195, after a VR
branch took 0194) changed the patch's comments and so the DLL's build identity. Each final build ran its own PoC
series, a fresh deployment of the same content:

- `c36c1962` (`out\mlc\final1`): 4.3 s at the first start after the unpack (every file a miss; the cache, 19 files,
  7,200,724 bytes, now in `<game>\rtx-remix\cache\mod-textures`), 1.12 s warm and 1.52 s with the file cache emptied
  (every file a hit; that start overlapped the rebuild below). All three quit normally; the rollback was clean; all
  9,042 entries matched their files.
- `cfb2173b`, the shipped DLL (`out\mlc\final2`): 11.8 s at the first start after the unpack (every file a miss;
  that start overlapped the end of a `tools\test.ps1` run), **1.13 s** warm and **1.26 s** with the file cache emptied
  (every file a hit). The cache in `<game>\rtx-remix\cache\mod-textures` (7,200,724 bytes), nothing under `bin\win64`;
  all three quit normally; the rollback was clean; all 9,042 entries matched their files.

### The field, estimated (not run)

The field has about twice the PoC's files and its start reads the user's Workshop add-ons at the same time. From the
PoC's per-file costs (about 0.9 ms a file with an empty file cache, 4 ms for a freshly written file), a cold field
start spent roughly 15-20 s in the box, and the box's "Processing Materials (496 processed)" was one large mod part
way through. With the patch, from its second start: the folder listings, the cache files (about 14 MB) and USD, about
2-3 s. Whether to check it in the field is the user's call.

## The change

Runtime patch `0086-Keep-the-mod-loader-s-texture-reads-between-starts.patch` (built from `c6b48ed1` + 0001-0071 +
0086 as `cfb2173b` in `out\worktrees\mlc\rt`; `d3d9.dll` 418,398,720 bytes, SHA-256
`dfbc26d59a8a7da3d28bb04a282dd7973647316dab97e320abec5693e8ac8030`, imported with `build_runtime.ps1`):

- `rtx_mod_texture_store.h` (self-contained): per mod, `rtx-remix\cache\mod-textures\<mod>-<hash>.bin` with each file's
  DDS record and its five smallest mips (tails up to 64 KB). An entry is used only while the folder listing gives the
  same size, write time, change time and file id; a file read afresh is kept only if the file itself (opened for its
  attributes) matches and has one name. Written atomically when anything differs; damaged or other-version files are
  ignored.
- `rtx_mod_texture_cache.cpp`: the runtime's side. A hit restores the partial loader's `DdsTextureData` from the
  record (same name, hash, info), the kept mips serving its first upload; a miss reads the file once; repeated names
  share one asset. Only a mod's first load uses it; hot reloads read as before.
- `rtx_asset_data_manager.cpp`: `loadDdsAssetForCache` and `restoreDdsAsset`; `DdsTextureData::data()` serves the kept
  mips until `evictCache` of the smallest level frees them.
- `rtx.initializer.modTextureCache` (default True); `[RTX Mod Load]` and `[RTX Mod Texture Cache]` log lines.
- `tests/rtx/unit/test_mod_texture_store.cpp`: 71 checks with real files (below).

A bug found on the PoC and fixed before the build: the runtime's `RtxFileSys::rootPath()` is `bin\win64`, so the first
build wrote the cache to `bin\win64\rtx-remix\cache`; the cache now sits beside the mods folder.

## Tests

- `tools\test.ps1` (Release): `tools/tests/test_mod_texture_cache.py` compiles `rtx_mod_texture_store.h` and its test
  from the committed patch with MSVC `/W4 /WX` and runs it: a first load reads and writes, a second reads nothing
  and returns the same bytes, a same-size edit with the old write time put back, a replaced file and a hard-linked file
  are read again (the last never kept), unused entries are dropped, damaged/short/other-version/other-magic cache
  files are ignored and rewritten, an unwritable folder fails only the save. It also checks the runtime's wiring in the
  patch, the cache checker (right entry, wrong tail, wrong header, changed file, damaged file, moved mods) and the lab's
  log parser.
- The PoC series above, and the confirmation series with the shipped DLL ("Confirmation with the shipped build").

## For the coordinating session and the VR branches

- Patch numbering: `main` gets `0086` after `0071`, so it sorts after the VR branches' `0072`-`0085`; ADR `0195`
  follows VR's `0193` (`vr2`) and `0194` (`v2q`, VR hold witnesses and ladder sectors; this ADR was renumbered from
  0194 before the merge). The VR patches touch none of this patch's files; a VR merge rebuilds the runtime with all of
  them (and must keep 0086 in `base.json`'s `packaged` record).
- Open, the user's call: the field's two duplicated mod pairs (`gm_brmovie_complete_rtx` with its `_pack`,
  `blood_overhaul_rtx` with `nl_blood_overhaul_rtx`) load the same files twice; and the one Lua error every run prints,
  `Couldn't include file 'nativeloader\engine_guard_words.lua'` (the published package too; the include is inside a
  `pcall` in the guard scripts, so nothing fails, but GMod prints it).

## Published

The merge's hook uploaded the package to item 3829070317 as `0.0.0-dev.20261113003337+9cd6be14` (2,085,755,646 bytes,
content digest `0dca07e0`), whose `native/payload/runtime/d3d9.dll` is the confirmed build (`dfbc26d5...`, 418,398,720
bytes); the push's hook found the inputs unchanged. The field gets it at its next start (Steam's update of the item);
the first start after it reads every texture once more and writes the cache, the next ones use it. The field check is
the user's call.
