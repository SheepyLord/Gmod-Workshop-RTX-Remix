# workshop-content-pack: records

Read [SKILL.md](SKILL.md) for the procedure. This page is the skill's record: the items made with it,
what was verified, what is open, and where its parts come from. The scripts it runs are in `scripts/`,
each with a `.md`; depth is in `references/`.

## Items (all hidden; dates UTC)

| Item | Package, last upload | Content | History |
|---|---|---|---|
| [3829348717](https://steamcommunity.com/sharedfiles/filedetails/?id=3829348717) | `guinaifen-rtx` `0.0.0-dev.202611010517+7ccac1bb` (2026-11-02) | Guinaifen (桂乃芬.pmx), 18 PBR materials, 44 DDS; about 696 MB | 2026-10-29: the user published the agent's build as this item; the agent added two texture hashes. 2026-11-02: the C-16 adaptive eye emission on her two face materials; her display name `Guinaifen (桂乃芬)` kept at the user's word (`check_pack.py --keep-name 1c2ed2fc`) |
| [3829347093](https://steamcommunity.com/sharedfiles/filedetails/?id=3829347093) | `guinaifen-rtx` (first build) | the same pack, before the hash fix | the agent's first upload; a hidden duplicate that stays (nothing is deleted until the project is done) |
| [3829892354](https://steamcommunity.com/sharedfiles/filedetails/?id=3829892354) | `robin-rtx` `0.0.0-dev.202611010515+3a6d9e61` (2026-11-01) | Robin (知更鸟.pmx), preset `Default`, 17 materials, 30 DDS; about 453 MB | 2026-10-30: created as `robin-r18-rtx`, renamed (`mmdhl_robin`, `pbr_robin`), display name `Robin`. 2026-11-01: C-16, description brought to the rules. The Workshop title set at creation (with "R18") cannot be changed by `update`: the owner renames it on the page |
| [3830769477](https://steamcommunity.com/sharedfiles/filedetails/?id=3830769477) | `evernight-march7th-rtx` `0.0.0-dev.202611010518+103fde9b` (2026-11-01) | Evernight and March 7th, two layers; about 1.22 GB | 2026-10-31: the first pack made with `hotloader_export.py` and `stage_pbr_mod.py` (display names 長夜月 and 三月七, no terms for March 7th); download identical to the build. 2026-10-31 22:13: rebuilt for R5 with `Evernight`, `March 7th` and both terms records, checked on the PoC, updated. 2026-11-01: C-16 (only `native/manifest.json` and the layers changed) |

Builds: the main checkout's `out\packages\guinaifen`, `out\packages\robin` (the first Robin build in
`out\packages\robin-r18`) and `out\packages\evernight-march7th`, each with a `pre-c16` copy. In R13
(2026-11-03) the field install had all three deployed (`pbr_guinaifen`, `pbr_robin`,
`pbr_evernight_march7th`); its `ai_pbr` no longer holds those characters' layers (checked
2026-11-08).

## Verified

- 2026-10-31, offline: `mmdhl_pack.py` rebuilt Robin's published Hotloader package (46 packets
  byte-identical) and made the same 47 packets and manifest content as Model Hotloader's own exporter
  for Evernight and March 7th; `pbr_mod.py` rebuilt Robin's published mod byte for byte (its doc
  string has left out the rpai keys since 2026-11-08); `add_hashes.py` rebuilt Guinaifen's fixed layer
  byte for byte; `gma_diff.py` reproduced the 77-of-77 comparison of Guinaifen's two imports.
- 2026-10-31: `nlctl plan` on the field listed the three packs `ACTIVE ... (subscribed, content only)`;
  the downloaded Guinaifen and Robin archives were byte-identical to their builds.
- 2026-11-02 (C-16): `check_pack.py --deep` on the three rebuilt packs; Guinaifen's update 0 errors
  with `--keep-name 1c2ed2fc`.
- 2026-11-08: `test_names.py` (20 tests) covers the naming rule and every script's refusal.

## Open

- **Not exercised:** setting Required items on an item page; whether `gmpublish create` sets the
  page's description (its logs show no such step); a public release; a map remaster through
  `check_pack.py`.
- **Inferred from code, not observed:** a requires-Remix character pack lets a standalone Model
  Hotloader delete and reinstall the model around starts without RTX; `ai_pbr` hides the packaged
  layer on the author's machine; English readers see Guinaifen as "New MMD Model" (her PMX's English
  name); Model Hotloader shows no Workshop page button for loader-deployed packages; the takeover of
  the author's own import (`references/pitfalls.md` 25).
- **The user's decisions:** whether character packs use `--requires-remix` (Guinaifen and Robin did,
  Evernight did not); making anything public (R18 content; the models' terms, Evernight's forbids
  redistribution); renaming Robin's page title.
- **Under the naming rule (2026-11-08)** the three last builds' descriptions name the game
  ("Honkai: Star Rail"): `check_pack.py` now reports that as an error, so the next update of each
  takes the game out of `description.txt` (the user pastes the page description). An agent cannot sign in to Steam's website: titles after creation, descriptions, Required
  items and visibility stay with the user.
- Windows only for packing (`cabinet.dll`'s XPRESS Huffman codec). The offline packer does not carry
  VRM licence records (none of these PMX models has one).
- The published page descriptions predate the Required-items rule and the naming rule; the archives'
  descriptions of Robin and the later builds were brought to the rules where noted.

## Provenance

Written by Claude for this user on 2026-10-31 from the sessions' transcripts, their scripts and
outputs, the repository's docs and tools, Model Hotloader's code and the mmd-remix-pbr skill; brought
up to date on 2026-11-08 (subscriptions, the naming rule and `model_names.py`, the Hotloader takeover,
`package_content.py` under `python -I`). The packers were written for the user by Claude in those
sessions; `check_pack.py`, `model_names.py` and `test_names.py` are this skill's. All are this
repository's code (MIT).
