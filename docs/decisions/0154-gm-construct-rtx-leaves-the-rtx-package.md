# 0154: The gm_construct_rtx map leaves the RTX package

- Status: Accepted 2026-11-10 (the user's request).
- Context: the RTX package (Workshop item 3829070317) carried, from the fixes (`garrys-mod-rtx-remixed`), a
  separate map **gm_construct_rtx**: `garrysmod/addons/remixbinary/maps/gm_construct_rtx.bsp` (51.7 MB) with its
  thumbnail, portal file, Hammer source and backup (`.png`, `.prt`, `.vmf`, `.vmx`), and a Remix layer for it,
  `rtx-remix/mods/base_mod/maps/gm_construct_rtx.usda`, a sublayer of `base_mod/mod.usda`. Beside it there is now a
  remaster of GMod's own gm_construct, **gm_construct RTX** (a content package of its own, 2026-11-10), and the
  user: "The gm_construct_rtx map packaged in the workshop item is causing confusion and user does not know which
  one to use. Remove it from the workshop package."

## Decision

1. **The six files leave `packages/fixes`**: their entries in `files.json` and their stored files, and
   `base_mod/mod.usda` no longer lists `./maps/gm_construct_rtx.usda` (imported with `inputs.py import --file`).
   Nothing else in the part changes.
2. **They stay out.** The fixes repository still has them, so importing the part from it again would bring them
   back: [`test_removed_content.py`](../../tools/tests/test_removed_content.py.md) fails while the index holds them,
   their stored files are there, or `base_mod/mod.usda` lists the layer.
3. **What stays:** `gm_construct_in_flatgrass_rtx`, another map in the same folder (the user named only
   gm_construct_rtx); and the fixes' `sv_skybox_fix.lua`, whose list of maps it leaves alone still names
   gm_construct_rtx, which does nothing without the map.

## Consequences

- The next package version has no gm_construct_rtx. On a player's machine the loader removes the deployed map
  files and the layer at the next deployment, as it removes any file a new version no longer has, when the file
  is unchanged ([ADR 0007](0007-transactional-deployment.md)); a copy the player changed stays theirs.
- Saves and dupes made on gm_construct_rtx no longer have their map; GMod's own gm_construct with the remaster is
  the place to play.
- The stored objects stay in the repository's Git LFS history (a pushed object is never freed); the package
  shrinks by about 64 MB uncompressed.

## Alternatives considered

- **Rename the map** (so its name differs from the remaster's): the user asked for removal, and two gm_construct
  variants in the spawn menu would still leave the choice.
- **Remove it from the fixes repository too:** that is the user's other repository and not what was asked; the
  test keeps the package right whatever that repository holds.
