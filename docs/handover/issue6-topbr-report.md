# GitHub issue 6: "Gmod ToPBR stopped loading?" (report, 2026-11-14)

The reporter: after enabling ToPBR "the GmodtoPBR file in the rtx-remix folder does get bigger, and if I open it I can
see materials being made, but in game I do not see them"; reinstalling, disabling every add-on, re-downloading the game
and rolling the loader back three times changed nothing. The owner's brief: decide whether to fix, migrate or remove the
inherited ToPBR, answer the player, and make the automatic categorization sturdier. Done by Claude on the branch
`qol-topbr` (worktree `out\worktrees\q-pbr`). Package only: the RTX fixes' module with two new GPL patches, three of the
fixes' Lua files and the add-on catalogs; no loader (`winmm.dll`) and no runtime change. Nothing was pushed, merged,
published or posted, and no game was started.
[ADR 0212](../decisions/0212-topbr-kept-and-publishes-past-unreadable-mods.md),
[ADR 0213](../decisions/0213-automatic-categorization-hardened.md); facts in [RESEARCH.md](../RESEARCH.md) ("GitHub issue
6").

## Root cause

ToPBR publishes its materials as `rtx-remix\mods\~gmod_topbr\materials.usda`. Before each publication (every 3 s) its
worker scanned the other mods' USD text for `mat_<hash>` names to leave out what they cover, and since R11
(2026-11-02, ADR 0091) **published nothing at all when the scan could not read every file**
(`fallback_guard.h:15`, `if (guard.complete)`): one binary USD, one USD over 16 MiB, more than 64 MiB of USD text, more
than 32,768 entries or a link was enough. Conversion was never stopped, only publication. So the textures folder filled
with DDS files named after the materials, `materials.usda` stayed `over "Looks" {}`, and the console said
`Published 0 fallback materials (N authored hashes, scan=uncertain/suppressed)`: the report exactly, and nothing the
player tried touches the cause, a file in their `rtx-remix\mods`. The same snapshot carries Imported game PBR, so
imported characters lose their game maps too.

Evidence:

- The owner's own field install (read only): 26 files the scan cannot read in three content packs installed 2026-11-12/13
  (25 binary Remix Toolkit crates in `country_estate_rtx`, `funkis_rtx`, `safehouse_rtx`, and a 29 MB `.usd`), 65.5 MB
  of USD text in 33 mods, and a `materials.usda` that is an empty snapshot (last written 2026-11-11 00:29); since
  the packs came, every publication there is empty.
  Two scratch scripts (`out\issue6\guard_scan.py`, `guard_permod.py` in the worktree, not committed) reproduce the scan offline (`complete False ... reasons 26`).
- [fallback_guard_test.cpp](../../packages/fixes/licenses/oversized-skinning/topbr-publish/tests/fallback_guard_test.cpp)
  builds such a mods folder: a crate makes the scan partial and the selection still publishes everything but the
  named hashes. The old selector returned nothing for a partial scan, which autopbr's `game_registry_test.cpp`
  still asserts against its own (R11) headers.
- Not the suspects in the brief: the runtime's mod-load cache (patch 0086) is used only for a mod's first load and keys
  on size, write and change time and file id; hot reloads read as before; the generated mod is deployed (create-only)
  from the first start and reloads through the directory watch on its root layer; the VR patches touch none of this;
  texture hashes come from the runtime itself (`dxvk_GetTextureHash`), so the colour cap, render guard and idle
  release do not change them; the fixes' own scan was the suppression.
- Why "after an update": the reporter's trigger is a file in their mods folder, which the issue does not show; any map
  pack with a Remix Toolkit mesh does it, and many have one. The reply asks for the console line.
- The two uncommitted edits in `out\worktrees\r23\out\r23\fixes-work` (`game_matching.inl`, `game_pbr.h`) are the
  Wuthering Waves maps change already shipped as the seventh patch (`wuwa-maps`; the Endfield patch came after). They
  do not matter here (imported game matching, not publication). That clone's alternates point at the removed H: clone,
  so git cannot read it any more; the files were compared directly.

## Decision on ToPBR: keep and fix

ToPBR is the only part of the package that gives map, prop, weapon and view-model materials Remix PBR from what their
VMTs already have (bump/normal/SSBump, Phong and envmap masks, ExoPBR/GPBR/MWB/BlueFlyTrap). The "alternative system"
the owner remembered is Imported game PBR (R11-R13): imported characters only, from a game's own maps beside the
model. Both run in the same native `TextureProcessor` and publish into the same mod, so removal would only remove the
switch, and there is nowhere to migrate. World conversion stays off by default.

Menu wording (Utilities > RTX Remix):

- **Map and prop PBR (ToPBR)** (was "ToPBR"): "Enable ToPBR for maps and props"; "Builds PBR materials for map, prop
  and weapon materials from what their Source materials already have: bump and normal maps, Phong and envmap masks,
  and community PBR shaders."; "Off by default. A real PBR mod for a texture always wins over it. Imported characters
  use Imported game PBR instead."; the experimental line; where the textures go and that materials appear a few
  seconds after they are first drawn. The "Experimental Metallic Detection" switch is gone (a no-op since R11), and so
  is "Requires a map reload to enable": turning ToPBR on now queues the materials already drawn.
- **Imported game PBR** gains: "For characters imported with the Model Hotloader: uses the PBR maps their game shipped
  beside the model. For maps and props, see Map and prop PBR (ToPBR)."

## Changes

- **Fixes patch 11, `topbr-publish`** ([README](../../packages/fixes/licenses/oversized-skinning/topbr-publish/README.md)):
  publication keeps out only the hashes a readable mod names (runtime patch 0020 ranks `~gmod_topbr` after every
  authored mod); the scan runs at most every 30 s and not with both switches off, re-reads a file only when its size or
  write time changed, reads a crate's 8-byte magic only, reads at most 64 MiB of new text a scan (the next continues);
  `Mod scan partial (N of M USD files not read; first: ...)` once. Before, the scan read every mod's text every 3 s in
  every RTX session (Imported game PBR is on by default): about 65 MB each time on the owner's field install.
- **Fixes patch 12, `player-categories`** ([README](../../packages/fixes/licenses/oversized-skinning/player-categories/README.md)):
  no automatic path adds a texture to a list the player's `rtx.conf` takes it out of (`ApplyToHash`,
  `ApplyCategoryToHash`, and `RemixMaterial.SetHashCategory` with a new `automatic` argument); `rtx.conf` is read again
  when it changes. Removals and `user.conf` unchanged (ADR 0213 says why).
- **`gmcl_RTXFixesBinary_win64.dll`** rebuilt with `tools\ci\build_modules.ps1 -Only fixes` (subst `Q:` for the
  worktree's `out`, the pinned garrysmod_common copied from `out\worktrees\r23\out\ci\work`, premake 5.0.0-beta2 from
  `out\debug-multiplayer-tools\premake-beta2`, the fixes clone `E:\Modding_Backup\garrys-mod-rtx-remixed` only read):
  5,597,696 bytes, SHA-256 `45f489903d4a1bb4f6fe1f9a55f1d1cf6db3968385122f4a3981ccc6c778d7c7`; the build checked the
  recorded tree. `tools/ci/pins.json`: both patches, `patched_tree.source` `7464a58d...`. Imported with `inputs.py`.
  The patches were made on a scratch branch `claude/issue6-topbr` in a shared clone under `out\fx`; no branch of the
  fork was touched.
- **Category manager** (`cl_remix_category_0_manager.lua`, ADR 0213): the map scan is a job of 2 ms a frame (it ran in
  one frame, quadratic, a VMT read per brush, a console line per hash); World Geometry is honoured (it was never read),
  and Overlay Decals and Legacy Emissive govern the scan's own branches; blended displacements are named as the tracker
  names them; one VMT read per material per scan; an unreadable material is counted and skipped; one queue entry per
  material, at most 16,384, 64 checked a frame; switching a category off or the master switch drops automatic work and
  rescans; a map change stops the old scan and its delayed start. Automatic writes pass `automatic = true`.
- **Pages and texts**: `cl_rtx_settings.lua`, `cl_rtx_topbr_conversion.lua` (queue on enable, panel line, help text);
  seven new texts in the six add-on catalogs and one in the panel's own table, agent-written by Claude, not yet
  reviewed by a person; nine obsolete texts left the catalogs. The companion guide's Rendering list names the renamed
  page and no longer says it needs a map reload (one message in the six companion catalogs).
- **Tests**: `fallback_guard_test.cpp` and `player_categories_test.cpp` (MSVC `/W4 /WX`, run by
  `test_topbr_publish.py` and `test_player_categories.py`, which also check each folder against its patch);
  `category_manager_harness.lua` and `rtx_settings_harness.lua` (LuaJIT); `topbr_harness.lua` checks queue-on-enable;
  `test_queued_draws.py` now checks its patch is tenth instead of last.

## Tests

`powershell -NoProfile -File tools\test.ps1 -Config Release` from the worktree, with `NL_FIXES_CLONE` set so the
patched-tree replay runs, at `2e2df965`: **All checks passed** (repo conventions; 35 of 35 CTests; Python 1906 tests in
`tools`, 29 in `tools\gmapack`, 26 in `tools\steam`, one skip each). The first run failed one check,
`test_vr_review_docs.py`: a branch may add only table rows to `docs/decisions/README.md`, and this one had also added
two list entries, now gone. Before the gate: both native regressions, the four Lua harnesses, `test_topbr_publish.py`,
`test_player_categories.py`, `test_queued_draws.py`, `test_topbr.py`, `test_ci_tools.py` (replay included),
`companion_i18n.py check`, `check_addon_i18n.py` and `inputs.py verify` passed.

## In-game checks still needed (the user's call)

1. On an install with a binary-USD mod (the field has three), enable Map and prop PBR on gm_construct: the console
   prints `Mod scan partial (...)` once and `Published N fallback materials (..., scan=partial)` with N > 0; materials
   change within seconds without a map reload; `materials.usda` lists them.
2. Imported game PBR on the field: an imported Wuthering Waves or Endfield character gets its game maps again (they
   are suppressed there since the packs came on 2026-11-12/13).
3. A map pack's authored material still wins over ToPBR's for the same texture (patch 0020).
4. Auto-Categorization on a large map (gm_bigcity or a field pack): no stall about three seconds into the map; the
   summary line appears a little later; decals and water look as before. With World Geometry off and a restart, the
   map's walls are not decals (switching it off mid-session affects only textures not yet categorized).
5. Remix developer menu: take a wall texture out of Decal, save `rtx.conf`, restart: it stays out.
6. The spawn-menu pages in English and one other language at 4K (GUI Scaler): labels and help lines fit.

## Open questions for the user

- Automatic categories still go to the runtime's user layer and into `user.conf` when a player saves settings. A
  runtime patch could give API category writes their own unsaved layer below `rtx.conf`; it would also stop the water
  correction of leftovers already saved in `user.conf`. Not done (runtime build owned elsewhere today).
- The reply below is a draft: it says the fix comes with the next package update, which a merge of this branch into
  `main` publishes, and asks for the console line only to confirm which mod triggered it.

## Reply draft for the issue (not posted)

> Thanks for the detailed report, and sorry: my earlier reply was wrong. ToPBR has not been replaced; it is still the
> only part of the package that converts map and prop materials, and it is being fixed rather than removed. (The
> newer "Imported game PBR" only covers characters imported with the Model Hotloader.)
>
> What you saw is a bug in how ToPBR publishes its materials. Before writing `rtx-remix\mods\~gmod_topbr\materials.usda`
> it scans your other Remix mods so it doesn't duplicate textures they already replace. If it couldn't read every file
> in `rtx-remix\mods`, for example a mesh saved by the RTX Remix Toolkit as a binary `.usd` (most map packs have some),
> it published **no** materials at all, while it kept converting textures. That's why the folder grew and nothing
> showed, and why reinstalling or rolling the loader back changed nothing: the trigger is a file in your mods folder.
>
> The fix is ready on our side and ships with the next update of the RTX package (the Workshop item updates itself; no
> new loader needed). Remix already makes real PBR mods win over ToPBR's materials, so ToPBR now publishes everything
> except what it can see another mod covers. The page is renamed "Map and prop PBR (ToPBR)", and turning it on no
> longer needs a map reload.
>
> If you'd like to confirm it's the same cause before the update: with ToPBR on, the console shows a line like
> `[MaterialPipeline::ToPBR] Published 0 fallback materials (... scan=uncertain/suppressed)`. After the update it will
> say `scan=partial` with a number above 0, plus one line naming the first file it couldn't read. Please tell us if it
> still doesn't work after the update.
