# 0195: The mod loader keeps its texture reads between starts

- Status: Accepted 2026-11-12
- Decided by: Claude, on the user's report of 2026-11-12 ("The field game takes a long time to load enhancements
  each start"), a task from the coordinating session; the user decides whether to check it in the field game.
- Builds on: [0103](0103-material-preloads-load-at-their-first-draw.md) (runtime patch 0030: a material's preload waits
  for its first draw, so a mod's load reads only each texture's smallest mips), [0033](0033-one-repository-package-inputs-in-git-lfs.md)
  and [0034](0034-the-runtimes-build-inputs-recorded.md) (the runtime built from `runtime/`). Runtime patch 0086, in the
  RTX package; no loader (`winmm.dll`) change.

## Context

The box "Loading enhancements / Processing Materials (N processed)" is the Remix runtime's own HUD message
(`dxvk_imgui.cpp`), shown while its asset thread loads the USD mods in `rtx-remix\mods` one after another, from the main
menu on, and only once the load has lasted 1.5 s (`rtx.gui.enhancementLoadingMessageDelayMilliseconds`, patch 0001).
Nothing at the menu needs the mods; a map loaded before they finish draws without its replacements until they do.

What a mod's load does per material (`rtx_mod_usd.cpp` `processMaterial` → `getTexture`), for every texture input:
USD resolves the asset path (a file existence check), `AssetDataManager::findAsset` opens the DDS file and parses its
headers (`DdsTextureData::load`: `fopen`, reads, `last_write_time`), and `preloadTextureAsset` makes the texture and
stages its five smallest mips synchronously (`requestMips(1)`, `scheduleTextureLoad(..., false)`), which opens and maps
the file a second time. A file named by several materials is parsed again for each. Nothing is kept between starts.

- **The field's mods** (28 folders, read 2026-11-12): about 7,300 material prims naming 25,487 textures in 16,700 files
  (70 GB). Two pairs load the same content twice (`gm_brmovie_complete_rtx` and `gm_brmovie_complete_rtx_pack`,
  `blood_overhaul_rtx` and `nl_blood_overhaul_rtx`).
- **Measured in the PoC** ([report](../handover/mod-load-cache-report.md)) with the user's 12 subscribed content packages
  deployed (19 mods, 16,300 texture references): opening and parsing the DDS files (`find`) is 90-95 % of every mod's
  load. The whole load took 27.3 s at the first start after the content was unpacked, 1.8 s at the next (every file
  in Windows' file cache) and 11.5 s once the file cache had been emptied of the mods, as after a reboot or a long
  session that pushed them out. The field has twice the PoC's files, plus the game's own start reading the user's
  Workshop add-ons at the same time.

## Decision

1. **The runtime keeps what it read** (runtime patch 0086, `rtx_mod_texture_store.h`, `rtx_mod_texture_cache.cpp`): per
   mod, `rtx-remix\cache\mod-textures\<mod folder>-<hash of its path>.bin` (beside the mods folder) holds, for each texture file the mod's first
   load named, the DDS headers as the partial loader parsed them and the bytes of the five smallest mips a new texture
   uploads first (tails over 64 KB, a texture without its mip chain, are not kept; such a texture's header still is).
2. **An entry is used only for an unchanged file**: the same size, last write time, change time and NTFS file id, all
   four from one folder listing per texture folder (`GetFileInformationByHandleEx(FileIdBothDirectoryInfo)`); the file
   itself is not opened. The change time moves with any write, even one that puts the old write time back; a replaced
   file has another id. A file read afresh is kept only when the file itself, opened for its attributes alone, has the
   listing's size, id and write time and one name: a hard-linked file's folder entry can be stale, so such a file is
   read at every start. Links, folders and file systems without change times are never stamped.
3. **The result is the partial loader's own**: a cached texture is `DdsTextureData` restored from the record (the same
   file name, hash, format, extent, mips and write time as `load()` gives) whose kept mips serve its first upload; its
   larger mips are read from the file when drawn, as before. A miss reads the file once (the tail read for the cache also
   feeds the first upload), and repeated names in one load share one asset.
4. **The file is written only when the load used anything else than it read** (new or changed entries, or entries no
   texture asked for, which are dropped), to a temporary file then moved over the old one; a damaged, shortened or
   other-version file is ignored and rewritten. Hot reloads (the material editor) read files as before.
5. **`rtx.initializer.modTextureCache`** (default True) turns it off; deleting the folder is always safe.
6. **`[RTX Mod Load]` and `[RTX Mod Texture Cache]` lines** in `remix-dxvk.log` give each mod's first load by phase and
   its cache counts, and the whole load's time.

## Consequences

- **Later starts open no texture file.** In the PoC (the same 19 mods, 9,042 files): 1.36 s instead of 11.5 s with the
  file cache emptied, 1.09 s instead of 1.83 s warm; every file a hit. Both are under the notice's 1.5 s delay, so
  the box no longer appears there. The first start with the patch reads every file as before and writes the cache
  (10.8 s cold, 35 ms of it writing 7.2 MB). All 9,042 entries were checked against their files with
  [check_mod_texture_cache.py](../../tools/qa/check_mod_texture_cache.py.md): the headers and, byte for byte, the
  8,989 kept tails match; the pinned views before and after differ as little as two starts of one build.
- The first start after an update of a content package (the loader writes new files) reads that package's files once
  more; other mods keep their entries.
- The folder holds about 0.8 KB per texture file (the PoC's 9,042: 7.2 MB; the field's 16,700: about 14 MB). It is the runtime's, like `rtx-remix\logs`: the
  loader's uninstall leaves it, and PoC labs' rollbacks move the whole `rtx-remix` folder away.
- USD still resolves each asset path (a file existence check per reference), and the stage parse and material walk
  remain: under 2 s for the PoC's mods when warm.
- A texture written while the game starts (a tool still holding the file) can show its old smallest mips for that
  session; the next start sees the change.
- The runtime's patch series now has 0086 after 0071 on `main`; the VR branches' runtime patches 0072-0085 do not touch
  these files, and a VR merge rebuilds the runtime with all of them.

## Alternatives considered

- **Load the mods on several threads:** shortens the wall time on a fast disk but reads every file at every start;
  the asset manager's search paths and the texture manager's locks are shared.
- **Defer each texture's file read to its first draw:** nothing to read at the menu, but every first appearance of a
  replacement would wait for its file (the hitch ADR 0103 measured for preloads) and the material data model expects a
  texture with its info at load.
- **Stamp each file with its own attribute query** instead of a folder listing: exact even for hard links, but one query
  per file; the listing costs one call per folder and hard-linked files are excluded instead.
- **Fix it in the loader or the add-ons:** the work is the runtime's; nothing outside it can skip a file the runtime
  opens.
