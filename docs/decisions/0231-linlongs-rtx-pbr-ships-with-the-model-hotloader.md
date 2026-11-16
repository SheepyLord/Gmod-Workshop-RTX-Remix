# 0231: Linlong's RTX PBR ships with the Model Hotloader

- Status: Accepted 2026-11-16
- Decided by: the user ("here is the RTX package for the included model in the model hotloader, please also merge and
  ship it with the main"; then, told that Linlong's terms forbid redistribution and that the pack's own description
  asks not to upload it publicly, "Ship it in main anyway"). The folder name was the agent's choice.
- Builds on: [0033](0033-one-repository-package-inputs-in-git-lfs.md) (the package's inputs in this repository),
  [0006](0006-package-precedence-and-planning.md) (a package whose files overlap an active one's is skipped).
- Report: [linlong-pbr-report.md](../handover/linlong-pbr-report.md).

## Context

The Model Hotloader part comes with one character, Linlong (asset `801f3bcf...`), which the add-on installs into the
player's library from `mmd_hotloader/data_static/mmdhl` (package record `84c3039b...`). On 2026-11-16 the user made
RTX Remix PBR materials for her with rpai (the `mmd-remix-pbr` skill) and packed them with the
`workshop-content-pack` skill as `linlong-rtx.gma`: an add-on, `mmdhl_linlong`, with her model files, and a Remix
mod, `pbr_linlong` (`mod.usda`, a material layer, 22 DDS maps at 2048: normal, roughness and two emissive).

Her PMX's embedded terms forbid redistribution (二次配布) and taking parts to modify other models, 18+ works and
commercial use; the pack's description calls it a private package. This repository is public, and rule 7 of
AGENTS.md keeps in `packages/` only what may be redistributed. Her model itself has been in the public part since
the part was imported.

## Decision

1. **The pack's Remix mod ships in the Model Hotloader part**, unchanged (its 24 files):
   `packages/model-hotloader/mods/mmdhl_pbr_linlong/`, deployed by the part's packager (`--mod` in
   `tools/workshop.json`) to `rtx-remix/mods/mmdhl_pbr_linlong`. In RTX sessions Linlong is drawn with these maps.
2. **Not the pack's add-on**: its model files are the part's own, byte for byte (the same 20 files by SHA-256), and
   its package record differs only in metadata and in the terms it carries.
3. **A folder name of its own**, not the pack's `pbr_linlong`: the combined package is one package
   (`gmod-rtx-remix`), and the loader skips a package whose files overlap an active package's (ADR 0006, rule 6). A
   local copy of the private pack, which takes precedence over the Workshop item, would have switched the whole RTX
   package off. With two names both mods load, with the same replacements.
4. **The user's decision is this mod's exception to rule 7**, recorded here and in the part's README.

## Consequences

- Git LFS keeps 35.7 MB more for good (92 MB unpacked); the package grows by about 95 MB.
- Every RTX player gets Linlong's PBR materials with the package, nothing to download or switch on.
- The model's terms are unchanged by this decision: whether Linlong stays in the public package is the user's call.

## Alternatives considered

- **A hidden Workshop item of the pack** (as the map packs are) or **the pack kept local**: offered with the terms;
  the user chose the main package.
- **The pack's folder name**: the overlap above.
