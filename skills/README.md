# Agent skills

Skills are folders an agent loads when a task matches: a `SKILL.md` (YAML front matter with `name`
and a `description` that says when to use it, then the procedure), with `references/` for depth and
`scripts/` or `tool/` for the code the procedure runs. They are written for agents: an agent that never
saw the earlier sessions follows them to repeat the work.

| Skill | Use it to | Made from |
|---|---|---|
| [`mmd-remix-pbr`](mmd-remix-pbr/SKILL.md) | Give an MMD character (a Model Hotloader import or a compiled add-on) AI-generated PBR materials with the `rpai` tool: upscaled albedo, normal, roughness, metal and emissive maps keyed by live Remix texture hashes, hot-loaded into the game, checked with measured A/B (AABB) tests; per-character presets. Starts by checking what the RTX package already does (imported game PBR from a game rip's own maps, eye whites, painted shadows, solid hair) | Guinevere/Guinaifen, Firefly, Hyacine, Robin, Cyrene, Castorice, Kafka, Eldreda, Hiyuki, Evernight, March 7th (2026-10-24 to 10-31); Elyms, Jingliu, Ruan Mei, Topaz, The Herta, Saber, Fu Xuan, HuoHuo and the Firefly remake (2026-11-03 to 11-08) |
| [`remix-map-pbr`](remix-map-pbr/SKILL.md) | Remaster a map for RTX Remix: extract its materials, classify them, generate PBR maps with AI, build the Remix mod (material overrides, lights, sky, mirrors, caustics), tour and compare it in game | gm_poolrooms RTX, Modern House RTX, Backrooms RTX (2026-10-26 to 10-29) |
| [`workshop-content-pack`](workshop-content-pack/SKILL.md) | Pack a character (its Model Hotloader package and PBR mod) or a map remaster into a hidden Workshop item that the native loader deploys for players who subscribe to it; split a remaster too big for one item by map and fit each part under the limit (`fit_map_mod.py`) | Guinaifen (3829348717), Robin (3829892354), Evernight and March 7th (3830769477); the Backrooms remaster in two items (3836505482, 3836505733; 2026-11-09) |

A character goes `mmd-remix-pbr` (make and verify the materials), then `workshop-content-pack` (ship
them). A map goes `remix-map-pbr`, then `workshop-content-pack`.

## Installing a skill

Claude Code reads personal skills from `%USERPROFILE%\.claude\skills\<name>\`. Link the folder there so
this repository stays the one copy (a junction needs no administrator rights):

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\mmd-remix-pbr" -Target "<repo>\skills\mmd-remix-pbr"
```

Other agents read the `SKILL.md` directly: each skill names the files to read next. `mmd-remix-pbr` also
needs its runtime, which is not in the repository: a Python 3.12 venv with PyTorch (CUDA), the PBRify
weights (CC0) and the RTX Remix Toolkit's NVTT exporter, all under `%USERPROFILE%\.rpai` (`tool/setup.ps1`
creates it; it downloads, so ask first). Install the two character skills side by side:
`workshop-content-pack` runs `mmd-remix-pbr`'s export and staging scripts, and its `test_names.py` checks
that both skills' copies of `model_names.py` match.

## Rules every skill keeps

- **Measure, do not eyeball.** Before/after numbers with a noise floor (AABB), not impressions.
- **Names are the character's own** (the user, 2026-11-08): no game or franchise, version, author or
  rating tag in a display name, folder, package id, title or record (`Chisa`, not `鸣潮-千咲`; `Alf`, not
  `阿芙2.0`). `model_names.py` (in both character skills) enforces it in their scripts.
- **Leave the user's setup alone:** never edit Remix `user.conf`, ask before `rtx.conf` or `dxvk.conf`,
  never write into `rtx-remix\mods\!advanced_material_editor`, never close or restart a game the user is
  working in without their permission, and restore every scene change you make.
- **Downloads and uploads are asked for**, except what the project's standing permissions allow
  (AGENTS.md rule 5): Workshop test items are uploaded hidden and never deleted; making one public
  needs the user's go-ahead, and so does anything with unclear redistribution rights or adult content.
- **Derived assets keep their source's terms.** A map or model by another author stays local or in a
  hidden item unless its terms allow redistribution (Modern House's derived textures stay local).
- **No account names in files:** write paths under the user's profile as `%USERPROFILE%\...` (rpai
  expands it in per-texture settings).
- **Licences:** the skills and their scripts are this repository's (MIT). The map pipelines they
  describe live in the user's GPL-2.0 fork `garrys-mod-rtx-remixed`; the skills point to those scripts
  and never copy them.

## Keeping them current

A skill changes when a method or a standard does: update its `SKILL.md` (and the reference it points to)
in the same change, with the evidence, and say so in [CHANGELOG.md](../CHANGELOG.md). Every script keeps
a `<script>.md` beside it, as everywhere in this repository.

`mmd-remix-pbr` was first copied on 2026-10-31 from the user's installed copy
(`%USERPROFILE%\.claude\skills\mmd-remix-pbr`, a plain folder that character sessions edit). The two then
drifted: the repository gained C-16's adaptive eye emission (`set_adaptive_emission.py`, rpai's
`--emissive-adaptive-intensity`), the installed copy gained `rough_map`/`metal_map`, full-size
`mmd/tf/` textures, `reveal_hashes.py`, `ue_toon_maps.py` and twelve per-model presets
(2026-11-03 to 11-08). On 2026-11-08 the installed copy's changes were merged into this folder (a
three-way merge against the 2026-10-31 copy; the presets' paths under the user's profile rewritten as
`%USERPROFILE%`, their leading names cleaned by the naming rule). The installed copy itself was not
changed: it still lacks C-16, so layers published from it carry no adaptive eye emission. Replace it
with a junction to this folder (above) once no character session is using it, and from then on edit
only here.
