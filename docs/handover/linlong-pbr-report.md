# Linlong's RTX PBR in the Model Hotloader part (2026-11-16)

The user's request of 2026-11-16: "here is the RTX package for the included model in the model hotloader, please also
merge and ship it with the main" (`linlong-rtx.gma`, made with the `mmd-remix-pbr` and `workshop-content-pack`
skills). Told that Linlong's PMX terms forbid redistribution and that the pack's description asks not to upload it
publicly, the user chose "Ship it in main anyway" ([ADR 0231](../decisions/0231-linlongs-rtx-pbr-ships-with-the-model-hotloader.md)).
Branch `linlong-pbr`, by Claude, package only.

## What changed

- `packages/model-hotloader/mods/mmdhl_pbr_linlong/`: the pack's Remix mod `pbr_linlong`, unchanged (24 files: `mod.usda`,
  `models/linlong_801f3bcf.usda`, 22 DDS maps at 2048: normal, roughness, two emissive), imported with
  `tools\inputs.py import model-hotloader --root <pack>\native\root\rtx-remix\mods\pbr_linlong=mods/mmdhl_pbr_linlong`:
  92 MB, 35.7 MB stored in Git LFS.
- `tools/workshop.json`: the part's packager deploys it (`--mod`) to `rtx-remix/mods/mmdhl_pbr_linlong`.
- Not shipped: the pack's add-on `mmdhl_linlong`. Its 20 model files are the part's bundled Linlong byte for byte
  (`mmd_hotloader/data_static/mmdhl/files`, the same SHA-256 names and contents); its package record
  (`ecb5c177...`) differs from the bundled one (`84c3039b...`) only in its id, time, title, description, generator and
  the model's terms.
- The folder is `mmdhl_pbr_linlong`, not the pack's `pbr_linlong`: the combined package is one package, and a local
  copy of the private pack would overlap it and, taking precedence, switch the whole RTX package off (ADR 0006, rule 6).

## Checks

- `linlong-rtx.gma`: GMAD v3, 47 files, every CRC and the add-on CRC verified (`tools\gmapack\gmapack.py verify`).
- No install has the private pack deployed (the field allowlists only 3829070317 and no local archive; no
  `*linlong*` add-on or mod folder in the field or the PoC).
- `python tools\inputs.py verify`: 15 parts, 0 problems.
- `python tools\build_package.py --compare out\workshop\published.json`: built, other content than the item's
  `0.0.0-dev.20261116091301+f38cbcc6` (exit 3, as expected); the `.gma` grew from 2,205,859,273 to 2,300,950,895 bytes
  and lists `native/root/rtx-remix/mods/mmdhl_pbr_linlong/` with its 24 files.
- Not checked in the game here: the maps are the user's pack as made and checked with rpai; the folder name does not
  change what Remix replaces.

## Published

`main` was fast-forwarded to `bd250b52` (the branch's one commit) and pushed (`f4abd3e6..bd250b52`, 21 LFS objects,
38 MB: two of the 22 maps are the same file). The merge's hook built the package from `packages/` and uploaded item
3829070317 as **0.0.0-dev.20261116093052+564dd514** (content digest `6e3cd068...`, the same content as the branch's build),
its change note the changelog's entry; the push's hook found the inputs unchanged. Not yet seen in a game: a start of
the field or the PoC with this package deploys `rtx-remix\mods\mmdhl_pbr_linlong`.
