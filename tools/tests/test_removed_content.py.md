# test_removed_content.py

Checks that content the user took out of the RTX package stays out of its inputs in `packages/`. A
part imported again from its source repository (the fixes from `garrys-mod-rtx-remixed`, which still
has the files) would otherwise bring it back without anyone noticing.

- **`REMOVED`**, per part: the paths in the part (a trailing `*` matches a prefix, without case) and
  why they were removed. None of them may be in the part's `files.json`, nor stored in its folder
  (as itself or as `<name>.xz`).
- **`LAYERS`**, per part: a Remix mod layer and a sublayer it must no longer list.

Today: the `gm_construct_rtx` map (its `.bsp`, `.png`, `.prt`, `.vmf`, `.vmx` in the `remixbinary`
add-on's `maps` folder) and its Remix layer `base_mod/maps/gm_construct_rtx.usda`, which
`base_mod/mod.usda` no longer lists ([ADR 0154](../../docs/decisions/0154-gm-construct-rtx-leaves-the-rtx-package.md)).

`python -m unittest discover -s tools/tests -p test_removed_content.py -v`. Reads `packages/` only;
no game, network or Git LFS content. Exit 0 when all pass, 1 otherwise.
