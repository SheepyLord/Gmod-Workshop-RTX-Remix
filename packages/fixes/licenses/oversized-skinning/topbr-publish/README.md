# ToPBR publishes past mods it cannot read (GitHub issue 6)

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[topbr-publish.patch](topbr-publish.patch) is the eleventh native patch, after the public base and the ten patches
before it in [pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`); with the twelfth
([player-categories](../player-categories/README.md)) it gives the patched native tree `pins.json` records
(`fixes.patched_tree.source` `7464a58d...`; `public` and `premake5.lua` unchanged). The complete changed files are
[fallback_guard.h](source/material_pipeline/to_pbr/fallback_guard.h), [to_pbr.cpp](source/material_pipeline/to_pbr/to_pbr.cpp),
[to_pbr.h](source/material_pipeline/to_pbr/to_pbr.h) and the SDK-free regression
[fallback_guard_test.cpp](tests/fallback_guard_test.cpp), as the work tree has them (CRLF). The build applies only the
patch's `source/` part (`fixes.patch_paths`). The same change is commit `48cd3df` on a local scratch branch
(`claude/issue6-topbr`, in a clone under the loader worktree's `out`) after a commit that applies the ten patches
before it to the base `f28bd5a`; nothing was pushed.

## The fault

ToPBR (world conversion, `rtx_topbr_enabled`, and Imported game PBR, `rtx_topbr_game_maps`) writes its materials into
`rtx-remix\mods\~gmod_topbr\materials.usda`. Before each publication its worker scanned every other mod's USD text for
`mat_<hash>` names, to leave out the textures an authored mod covers (R11, the loader's ADR 0091). When the scan could
not read every file, `FallbackGuard::Select` published **nothing**: one binary USD (the Remix Toolkit writes meshes as
`.usd` crates), one USD over 16 MiB, more than 64 MiB of USD text in all, more than 32,768 entries, a link or a
folder deeper than 16 was enough. Conversion went on writing DDS files into `~gmod_topbr\textures`, so the folder
grew while `materials.usda` stayed an empty `Looks` (`Published 0 fallback materials (... scan=uncertain/suppressed)`
in the console). That is the issue's report. The owner's own field install has 26 such files in three content packs
(binary models in `country_estate_rtx`, `funkis_rtx` and `safehouse_rtx`, a 29 MB `.usd`), and its `materials.usda`
is an empty snapshot (last written 2026-11-11); with those packs, installed on 2026-11-12/13, every later
publication is empty too, imported characters' game maps included.

The rule was a precedence guard from before the runtime had one. Runtime patch 0020 (the loader's ADR 0092,
`rtx.gmod.fallbackMods`) ranks `~gmod_topbr` after every authored mod for materials, meshes and lights, whatever the
folder names and whenever a mod (re)loads, so an authored material the scan cannot read still wins in game.

## The change

- **`FallbackGuard::Select` publishes every generated material whose hash no readable mod names**, whether or not
  the scan read every file. Each switch still governs its own kind (world materials, imported game materials).
- **The scan is cheaper and bounded per scan, not per folder.** `WriteModUSDA` scans at most every 30 s (not at every
  3 s publication) and not at all with both switches off; a per-file cache keyed by size and write time means a file
  is read again only when it changed; a binary crate costs 8 bytes (its `PXR-USDC` magic); a scan reads at most 64 MiB
  of new text and the next scan reads what it left (`Limits`); the entry bound is 65,536.
- **The log says what it could not read, once**: on the owner's field mods it would print `Mod scan partial (26 of
  ... USD files not read; first: binary USD country_estate_rtx\models\garden_gnome_2k.usd): generated materials still
  publish, and every authored mod still wins (rtx.gmod.fallbackMods)`; the publication line ends in `scan=complete`
  or `scan=partial`.
- `ExtractHashes(text, Result&)` stays for the older regressions (`to_pbr_test.cpp`).

## Tests

[fallback_guard_test.cpp](tests/fallback_guard_test.cpp) compiles alone with MSVC
(`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX`) and runs on a scratch folder: a partial
scan publishes everything but the named hashes; a Remix Toolkit crate, a USD with a NUL byte, a file over the bound,
the read limit (a later scan reads the rest), the entry bound and a missing folder are named and counted; a
same-size edit with the old write time keeps the cached hashes and a changed size is read again; a removed mod
leaves the cache. The loader's Release gate compiles and runs it and checks the folder's files against the patch
([test_topbr_publish.py](../../../../../tools/tests/test_topbr_publish.py.md)). autopbr's `game_registry_test.cpp`
keeps the old suppression assertion: it is compiled with autopbr's own headers, the R11 layer it describes.

Validated build (2026-11-14, this machine): **5,597,696 bytes**, SHA-256
`45f489903d4a1bb4f6fe1f9a55f1d1cf6db3968385122f4a3981ccc6c778d7c7` (the eleven patches before the twelfth and the
twelfth included), imported once with `tools/inputs.py`. Built with
[build_modules.ps1](../../../../../tools/ci/build_modules.ps1.md) `-Only fixes` through a temporary drive alias of the
worktree's `out` (premake writes wrong paths under a folder with `!`), with the pinned garrysmod_common and premake
5.0.0-beta2; the build checked the recorded tree. See the loader's
[ADR 0212](../../../../../docs/decisions/0212-topbr-kept-and-publishes-past-unreadable-mods.md).
