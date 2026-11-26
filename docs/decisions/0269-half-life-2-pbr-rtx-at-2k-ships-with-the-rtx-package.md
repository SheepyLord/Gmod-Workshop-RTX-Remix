# 0269: Half-Life 2 PBR RTX at 2K ships with the RTX package

- Status: Accepted 2026-11-26
- Decided by: the user. First: "I plan to bundle this to the main rtx remix package, but space is a consideration,
  could you make a separate version where the maximum resolution of the texture is 2048x2048?" Then, told that
  bundling puts about 1 GB of textures derived from Valve's into the public repository's Git LFS: "Yes, bundle it".
  The folder name was the agent's choice.
- Builds on: [0033](0033-one-repository-package-inputs-in-git-lfs.md) (the package's inputs in this repository),
  [0006](0006-package-precedence-and-planning.md) (a package whose files overlap an active one's is skipped),
  [0231](0231-linlongs-rtx-pbr-ships-with-the-model-hotloader.md) (a bundled mod takes a folder name of its own).
- Report: the part's [README](../../packages/hl2-pbr-rtx/README.md). The full account is the fork's
  `docs/HL2_PBR_RTX.md` (local branch `claude/hl2-pbr-rtx`).

## Context

Half-Life 2 PBR RTX was made on 2026-11-26 with the `remix-map-pbr` skill's pipeline for the game's own assets. It
remasters the weapons and spawnable items Half-Life 2 and GMod ship: 67 textures, 69 replacements. Its full version
draws the view models at 4096 and weighs 2.33 GB.

The user asked for a version capped at 2048 to bundle with the RTX package, which was 2.36 GB at its last upload, where
space counts. The fork's `pack_mod.py --max-side 2048` makes it from the full mod by leaving out each DDS file's top mip
levels: 1.03 GB. On the PoC at 3840x2160 it looked the same as the full version: 0.7-1.6 of 255 apart under the same
sky, and 1:1 crops look alike.

The textures derive from Valve's (Half-Life 2 and its episodes) and Facepunch's (GMod). This repository is public, and
AGENTS.md rule 7 keeps in `packages/` only what may be redistributed.

## Decision

1. **A part of its own**, `packages/hl2-pbr-rtx`. It holds the 2K mod folder: 283 files, the 281 DDS maps in Git LFS
   (644 MB stored) and the two layers as text. `package_content.py` (`--mod`) builds it, and the loader deploys it to
   `rtx-remix/mods/!hl2_pbr_rtx_shipped_2k`.
2. **A folder name of its own**, `!hl2_pbr_rtx_shipped_2k`. It is not the name of a standalone package's folder
   (`!hl2_pbr_rtx_pack`, `!hl2_pbr_rtx_pack_2k`) or of the development build's (`!hl2_pbr_rtx`). With shared file
   paths the loader would skip one of two packages (ADR 0006), possibly the whole RTX package, as ADR 0231 found.
   - The name sorts after every other copy's, and the runtime takes a replaced texture from the folder that sorts
     first. A game that also has the full version shows its 4096 textures.
   - With its `!` it sorts before the map packs and the RTX fixes' `base_mod`. It shares no texture hash with the
     package's other mods.
3. **The user's decision is this part's exception to rule 7**, recorded here and in the part's README. The rights in
   the textures stay with Valve and Facepunch, and the repository's MIT licence does not cover them.

## Consequences

- The RTX package grows by about 1.03 GB, to about 3.39 GB, and every RTX player gets the weapons' and items' PBR with
  it.
- Git LFS keeps 644 MB more for good, of its 10 GiB, and every full fetch of the inputs downloads it.
- The full version and the standalone 2K package remain separate packages, neither uploaded.
- The part is rebuilt with the fork's `pack_mod.py --max-side 2048 --folder !hl2_pbr_rtx_shipped_2k --mod-label
  "(RTX package, 2K)"`, then `inputs.py import` (see the part's README).

## Alternatives considered

- **The full version, at 4096**: 1.29 GB more than the 2K one, with no visible gain at 4K.
- **Roughness, metallic and emission at 1024 as well**: 0.73 GB in all. Not what the user asked for.
- **A hidden Workshop item of its own**, as the map packs have: the user chose the RTX package.
