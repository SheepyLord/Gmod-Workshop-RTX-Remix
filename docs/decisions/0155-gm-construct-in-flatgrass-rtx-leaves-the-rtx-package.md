# 0155: The gm_construct_in_flatgrass_rtx map leaves the RTX package too

- Status: Accepted 2026-11-10 (the user's request); amends [ADR 0154](0154-gm-construct-rtx-leaves-the-rtx-package.md),
  whose decision 3 kept this map.
- Context: after gm_construct_rtx left the package (ADR 0154), the fixes' other map was still in it,
  **gm_construct_in_flatgrass_rtx**: `garrysmod/addons/remixbinary/maps/gm_construct_in_flatgrass_rtx.bsp` (23.9 MB)
  with its portal file, Hammer source and backup (`.prt`, `.vmf`, `.vmx`), and no thumbnail or Remix layer. Its name
  mixes the two maps the new remasters cover, gm_construct RTX and gm_flatgrass RTX. Asked whether it should go
  too, the user answered "Remove it too".

## Decision

1. **Its four files leave `packages/fixes`**: their entries in `files.json` and their stored files. The
   `remixbinary` add-on no longer has a `maps` folder; nothing else in the part changes.
2. **It stays out** the way gm_construct_rtx does: [`test_removed_content.py`](../../tools/tests/test_removed_content.py.md)
   fails while the index holds it or its stored files are there.
3. ADR 0154 stands otherwise: the fixes' `sv_skybox_fix.lua` keeps its list of maps.

## Consequences

- The next package version has no map of its own; at the next deployment the loader removes the deployed files,
  when unchanged ([ADR 0007](0007-transactional-deployment.md)). Saves and dupes made on this map no longer have it.
- The package shrinks by about 36 MB uncompressed; the stored objects stay in the Git LFS history.
