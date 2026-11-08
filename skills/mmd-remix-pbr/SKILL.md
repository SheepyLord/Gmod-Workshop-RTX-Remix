---
name: mmd-remix-pbr
description: Make, tune, A/B-test and package RTX Remix PBR materials for an MMD/PMX character in Garry's Mod RTX with the bundled rpai tool (AI upscale, normal, roughness, metallic and emissive maps, material classes rasterised into UV space, anime-safe face and eye rules, live Remix texture hashes, a hot-reloaded ai_pbr mod, scripted AABB captures). Use it when a Model Hotloader import or a compiled character add-on should get or change PBR, when the task mentions rpai, ai_pbr, PBRify, Remix texture hashes, a per-model preset, a character's cloth, metal, hair, skin, face or eye look under path tracing, an in-game before/after or A/B of a character, an 8 GB variant, or packaging a character's maps. First decide whether the RTX package already covers the need (imported game PBR from a game rip's own maps, steady eye whites, painted shadows, solid hair). Not for maps (remix-map-pbr) or Workshop uploads (workshop-content-pack, which uses this skill's export and staging scripts).
---

# MMD character PBR for RTX Remix (Garry's Mod RTX)

rpai turns an MMD character's diffuse-only sheets into Remix PBR materials and hot-loads them into the
running game. It upscales each albedo with PBRify (DAT) up to 4096, generates normal and roughness
maps, classifies every PMX material (cloth, metal, skin, face, iris, ...) and rasterises the classes
into texture space, because MMD sheets are shared atlases. It writes `over "mat_<HASH>"` layers into
`rtx-remix/mods/ai_pbr`, keyed by the texture hashes the game reports.

- Code, presets and the full method: `tool/` (read `tool/README.md` for any option not below).
- Runtime (venv, weights, work files): `%USERPROFILE%\.rpai`.
- References: `references/runtime-notes.md` (paths, runtime, hashes, the RTX package's character
  features, imported game PBR), `references/standards.md` (class values and their evidence),
  `references/testing-protocol.md` (AABB), `references/texture-review.md` (reviewing a new character).
- The canonical copy of this skill is `skills/mmd-remix-pbr` in the native loader repository
  (`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix`). The user's sessions may run an installed copy,
  `%USERPROFILE%\.claude\skills\mmd-remix-pbr`; what changes there is copied back to the repository
  (`skills/README.md`, "Keeping them current").

## Rules (the user's)

- **Measure; do not eyeball.** Report before/after differences with a noise floor, patch values and
  detail retention.
- **A standard changes only with full-body evidence and the user's decision.** Run a full-body AABB
  (`references/testing-protocol.md`) and present options. If none is accepted, revert to the original
  RTX Remix look.
- **Body skin changes are made and applied only when the user asks**: skin-class overrides
  (`original: 0`, roughness, relief), the model's own body normal map on skin, subsurface scattering,
  de-lighting, skin texels on shared sheets, skin recolouring. Never propose them as part of other work
  and never leave one applied after a test the user did not accept. A tested look that is not kept goes
  to `tool/presets/on_request/` (never auto-loaded) and the per-model preset returns to the standard.
- **Names: the character's own name only** (the user, 2026-11-08). See "Names" below.
- **Do not get stuck on side issues.** Note them, keep the evidence, move on.
- **Leave the setup alone.** Never write `rtx-remix/mods/!advanced_material_editor`; never touch Remix
  `user.conf`; ask before editing `rtx.conf` or `dxvk.conf` and before downloading anything. Do not
  close or restart the game the user is working in (their scene is lost); start your own test game
  only on the PoC install with `-multirun`, unless the user gave a standing permission for this task.
  Restore every scene change you make (camera hooks, hidden parts, player position) and only those:
  the user may change the scene at the same time.
- **R18 models:** aim test views at the surface under test (neck and collarbones, abdomen, arms, legs).
  In local debug and AABB sessions keep screenshots whole: never crop them, and never change morphs or
  part visibility to hide the model's base body. Images sent to the user and Workshop icons stay
  free of adult content.
- **Privacy:** read only your own session's part of the game's `console.log`; write no user account
  name into files (use `%USERPROFILE%`).

## Names

A model's recorded name is the character's own name as the user uses it (`Chisa`, `Guinaifen`, `Alf`,
`March 7th`), never a source folder or PMX name with its tags. It applies to:

- the Model Hotloader display name of anything you package or export, and package `NAME`s;
- folder names and slugs derived from it (`pbr_<name>`, `mmdhl_<name>`, `<name>-rtx`, an export's
  file name), titles, bodygroup preset names you choose (`Default`);
- names written into records: a per-model preset's `doc` (start it with the clean name; a path may
  keep its folder's name), `mod.usda` doc strings, reports to the user, package READMEs.

Refused tags: a game or franchise (鸣潮, 星穹铁道, 原神, 崩坏, 明日方舟, 终末地, 白银之城, HSR, WuWa,
Genshin, ZZZ, `[Arknights]`), a version, build or edition (`2.0`, `v1.2`, `Ver.3`, `合体7`, a number
after the name), an author or uploader (`by_mobius`, `Tda式`), a rating or format (`R18`, `NSFW`,
`MMD`, `PMX`), a bracketed tag, and in display names pack words (`RTX`, `PBR`). Examples: source
folder `鸣潮-千咲` → `Chisa`; `星穹铁道-桂乃芬` → `Guinaifen`; `阿芙2.0` → `Alf`. When unsure of the
name the user uses, ask.

`scripts/model_names.py` implements the rule; `hotloader_export.py`, `stage_pbr_mod.py` and
`package_characters.py` refuse a tagged name before writing anything (exit 1). rpai's model key
(`robin_r18_f9c3e4b4`) is derived from the PMX's English name and may carry tags: it is an internal
identifier (work folder, preset file, layer file name). Never present a key as a name, never derive a
name or slug from it.

## Before you start: is rpai the right tool?

The RTX package (Workshop 3829070317) already does some character work in every RTX session
(`references/runtime-notes.md`):

| The need | Already handled by | Use rpai when |
|---|---|---|
| PBR for a game rip whose folder holds the game's maps (Wuthering Waves `_N`, Endfield `_N`/`_P`/`_E`, Silver Palace `_N`/`_MRA`) | the RTX fixes' **imported game PBR** (`rtx_topbr_game_maps 1`): converts the game's maps on its own, keeps them when the source folder goes, per-texture choices in the spawn menu's Utilities > RTX Remix > Imported game PBR panel | the user asks for more than the game maps give, or the panel shows sheets with no maps |
| Steady eye whites | the companion's eye whites (automatic, plus **Choose eye-white materials**, brightness slider) | the user wants rpai's face standard (iris, catchlight, sclera classes) |
| Dark bands from painted shadow overlays (目影, 发影) | the companion leaves them out of the draw | never: they need no PBR |
| Hair with see-through notches from the alpha test | the companion's solid hair | never for that alone |

An authored layer (rpai's or a pack's) wins over ToPBR for every hash it covers (runtime patch 0020):
an rpai material for a sheet replaces the game-map material for that sheet. Check the panel before
publishing over a game character, and tell the user which sheets change hands.

## Setup check

```powershell
& "$env:USERPROFILE\.claude\skills\mmd-remix-pbr\tool\rpai.cmd" doctor     # or <repo>\skills\mmd-remix-pbr\tool\rpai.cmd
```

`rpai.cmd` puts `tool/` on `PYTHONPATH` and runs the venv's Python. From Git Bash:
`PYTHONPATH="<skill>/tool" "$HOME/.rpai/venv/Scripts/python.exe" -m rpai doctor`. The doctor checks
torch with CUDA, the PBRify weights, the Remix Toolkit's NVTT exporter and whether the game answers.

- **No venv?** `tool/setup.ps1` creates it and downloads the PBRify_Remix v1.7.2 weights (CC0, 72 MB).
  Ask first: it downloads.
- **Keep `RPAI_HOME` on a short path.** PyTorch's DLLs fail with WinError 206 from long paths.
- Run the scripts in `scripts/` with the venv's Python (`$py = "$env:USERPROFILE\.rpai\venv\Scripts\python.exe"`);
  they put `tool/` on the path themselves.

## Workflow for a character

1. **Scope.** Get the PMX path and the character's name as the user uses it. Confirm which textures are
   in scope and the style: the defaults, or `presets/aggressive.json` (most characters since
   2026-10-30 use the aggressive style with the values accepted on Evernight: cloth 0.65 / rough_ai
   0.35 / normal 2.0, leather 0.25 / 0.4, stockings 0.42, satin metal 0.32, hair 0.38).
2. **The game.** The character must be spawned (Model Hotloader, Q → MMD) in the running game, so
   Remix has drawn its textures; wait for its first spawn to finish (characters load on first use).
   With several games running pass `--game-root <GarrysMod>` to every command.
   - **Compiled add-on** (sheepylord's ports, `models/sheepylord/<game>/<name>.mdl`, spawned as a
     ragdoll or prop): find its model path in game (`GetModel()`), pass `--mdl <model path>` once
     (remembered per PMX). Its VMTs must be named like the PMX materials (tool README, "Compiled
     models"); `abtest.py --asset <model path>` frames it.
3. **Hashes.** `rpai hashes "<pmx>"`. Live hashes are authoritative; predicted ones can be wrong. If
   parts are hidden, `& $py scripts\reveal_hashes.py --game-root <GarrysMod> <asset id8> <material
   count> "<pmx>"` shows them, runs `rpai hashes` and hides them again (restored exactly, checked).
   List what stays predicted (morph-hidden parts, painted shadows).
4. **Texture review** for a new character (`references/texture-review.md`): game maps first, the class
   of every material, what every sheet holds. Write the per-model preset
   `tool/presets/models/<model key>.json`: style include, class pins (`_materials`, 0-based PMX
   material indices), region rules (`regions`: painted gold → metal; `"islands"` for one material
   holding many surfaces), per-texture overrides (`max_size`, `presets`, `normal_map`, `rough_map`,
   `metal_map`, `albedo_source`), and a `doc` that starts with the clean name and says why:

   ```json
   {
     "doc": "Chisa (<pmx>, <source folder>), Model Hotloader asset 0123abcd, reviewed <date>: what each part is and why.",
     "include": ["../aggressive.json"],
     "presets": {"_materials": {"38": "metal", "45": "gem"}},
     "regions": [{"texture": "衣.png", "within": ["cloth"], "class": "metal",
                  "hue": [28, 58], "sat": [0.30, 1.0], "val": [0.50, 1.0], "doc": "gold trim"}],
     "textures": {"丝袜.png": {"max_size": "source"},
                  "衣.png": {"normal_map": "衣 normal.png", "presets": {"cloth": {"rough": 0.6}}}}
   }
   ```

   Body skin settings never go into this file on your own initiative. Per-texture file paths are
   relative to the sheet's folder or absolute; write paths under the user's profile as
   `%USERPROFILE%\...` (rpai expands variables and a leading `~`).
5. **Generate.** `rpai generate "<pmx>"`. The first run per texture costs minutes of GPU time (DAT);
   the AI outputs are cached in `work/<key>/raw`, so re-tuning recomposes in seconds. Inspect
   `work/<key>/preview.jpg`, the class masks and `classes.json`. Check free commit memory and other
   `-m rpai` processes first; beside the game use `--tile 128` (`runtime-notes.md`, "Commit memory").
6. **Publish.** `rpai publish "<pmx>"`: NVTT DDS (BC7/BC5/BC4), the layer, an atomic `mod.usda`
   rewrite; the runtime hot-reloads in about a second (no log line on current runtimes: check in game).
   A brand-new mod folder needs Alt+X → Enhancements → Loaded USD Files → "Rescan Mods & Reload USD
   Stage" once (the user's click, or a restart of your own test game). `rpai run "<pmx>"` = hashes +
   generate + publish.
7. **Show the result.** `rpai compare "<pmx>"` toggles the layer from the user's camera and saves a
   before/after; for tuning or a standard use the AABB rig (`scripts/abtest.py`). Quote every change
   against the floor-corner or repeat noise.
8. **Iterate** on the per-model preset. `--settings extra.json` merges before the per-model preset, so
   the model preset wins.
9. **After a game restart and before packaging,** re-run `rpai hashes` with the model spawned: the
   same opaque sheet can upload with a new hash, and rpai keeps every hash it has seen.
10. **Remaking a layer** (the same PMX imported again under a new asset): the key that sorts first wins
    every shared hash, so remove the old layer (`rpai remove "<pmx>" --asset <old id>`), mark the old
    preset superseded in its `doc`, carry over the per-sheet decisions the user accepted (tool README,
    "Remaking a layer").

## Standards (defaults in `tool/rpai/classify.py`; evidence in `references/standards.md`)

- **Materials:** cloth 0.78 / normal 1.44, leather 0.42 / 1.12, stockings 0.55, rubber 0.22, hair
  0.40; metal 0.28 with metallic 1; gem 0.05. `aggressive.json` pushes them (cloth 0.55 / 2.6, leather
  0.20 / 2.0, metal 0.12, ...) and never touches skin or the face classes.
- **Gold type per character** (2026-10-26): painted gold has F0 0.17-0.55, so polished it mirrors a dim
  room as dark bronze; painted golds get a satin metal (0.30-0.36), bright silver and tiny jewellery
  stay polished. `"f0": 0.74` lifts a satin gold to real gold's reflectance (measured on Robin,
  `robin_r18_f9c3e4b4`). Measure a new character's metal F0 on the mesh and choose the same way.
- **Face and eyes (anime-safe):** face and mouth 0.60 flat; lashes, brows, eyeliner 0.85; eye white
  0.25 with emission 0.025; iris 0.06 with emission 0.04; catchlight mesh emission 0.6. Eye emission
  maps also get `emissive_adaptive_intensity` (C-16, ratio `--emissive-adaptive-intensity`, default 25;
  `0` opts out); the player's eye-white brightness slider scales it.
- **Body skin: left as Remix renders it** (`original: 1`): a skin-only sheet gets no override; skin on
  a shared sheet gets roughness 0.7, flat, original colours. De-lighting, SSS and relief from the
  model's normal map are on request only.
- AI relief and AI roughness variation are off on skin and the face classes.
- **Emissive parts** (a glowing tail, a lamp): a class with an `emissive` weight of its own on that
  sheet (tool README, "A part that glows").

## Commands

| Command | What it does |
| --- | --- |
| `rpai run "<pmx>"` | hashes → generate → publish |
| `rpai hashes` / `generate` / `publish` / `compare` / `remove` | single steps (each takes the PMX path) |
| `rpai status`, `rpai doctor` | published models / installation check |
| `--mdl models/.../x.mdl` | a compiled add-on, not a Model Hotloader import (remembered) |
| `--asset 1c2ed2fc` | use this Model Hotloader import for the PMX (a re-import whose source folder is gone) |
| `--only "衣.png,髪.png"`, `--force` | some textures; redo the AI stage too |
| `--settings f.json` (repeatable), `--no-prune` | extra settings; keep old DDS (variants, A/B) |
| `--emissive-intensity 0.7`, `--emissive-adaptive-intensity 25` | eye emission level; adaptive ratio (publish only; `0` disables) |
| `--no-live` | skip the in-game query (earlier verified hashes are kept) |
| `--max-size 2048`, `--upscaler span`, `--tile 128` | size cap; faster, softer upscale; smaller inference tiles |
| `--height --displacement 0.03`, `--mod <name>`, `--game-root <dir>` | height maps for POM (off by default); another mod folder; pick the game |
| `& $py scripts\reveal_hashes.py [--game-root <dir>] <asset id8> <material count> "<pmx>"` | show hidden parts, `rpai hashes`, restore visibility exactly |
| `& $py scripts\ue_toon_maps.py --d T_x_d.png --m T_x_m.png --id T_x_id.png --out-dir <dir> --name <sheet>` | roughness and metallic maps from an Unreal toon set, for `rough_map` / `metal_map` |
| `& $py scripts\abtest.py bones --asset <id8>` / `capture ...` / `metrics <run> --baseline A` | AABB rig: bones, captures of variant layers (restores everything), noise/change/detail tables |
| `& $py scripts\package_characters.py --dest <dir> --character <Name>=<key>[=<pmx>] ...` | package characters for reuse (not a Workshop pack) |
| `& $py scripts\set_adaptive_emission.py --mod <copy> --multiplier 25 --dry-run` | adaptive eye emission in an existing pack; omit `--dry-run` to apply |
| `& $py scripts\recolour_skin.py --src <sheet> --ref <images> --out <png> --pmx <pmx> --materials 0,1` | skin tone matched to a reference (on request only), used through `albedo_source` |
| `& $py scripts\hotloader_export.py ...`, `scripts\stage_pbr_mod.py ...` | Workshop pack inputs: see workshop-content-pack |

The model key is `<english name slug>_<asset id[:8]>` (`rpai status` lists them; a compiled model's is
`<name>_<sha1 of its path>[:8]`).

## Testing in game

Use `references/testing-protocol.md` for anything beyond a quick compare:

- **Variants are complete model layers**: `generate --settings variant.json`, `publish --no-prune`,
  copy the layer after each. `abtest.py capture` swaps them in, waits, and shoots each view twice back
  to back (AABB), so every effect comes with its own noise floor; bracket with `A2` when an effect is
  small.
- **Views come from bone names** (`views.json`); the camera is a client `CalcView` hook.
- **Hide parts only via `mmdhl.SetMaterialVisible`** (`--hide 7,8,44`); a part that stays invisible
  while its flags say visible is a material morph (`[Fullbody]`): leave it.
- **Hold the RTX package's character settings still** (painted shadows, solid hair, eye whites and
  their brightness) through an A/B and record them.
- **Present** the sheets and metrics, then ask with options that each carry their measured trade-off.

## Publishing for 8 GB GPUs

The loader's minimum memory profile is 8 GB of VRAM and 16 GB of RAM (ADR 0101); larger packs fit
larger cards. Characters meant for players with 8 GB GPUs are published with `--max-size 2048` into a
separate `--mod`, such as `ai_pbr_2048`. Apply the cap while generating, then publish that output:

```powershell
rpai run "<pmx>" --max-size 2048 --mod ai_pbr_2048
# or, with hashes already checked:
rpai generate "<pmx>" --max-size 2048 --mod ai_pbr_2048
rpai publish "<pmx>" --max-size 2048 --mod ai_pbr_2048
```

- `publish` encodes the existing generated maps: the flag at publish time alone does **not** resize an
  earlier 4096 generation.
- Per-texture `max_size` overrides (including `"source"`) lift the global cap: check them first.
- Publishing replaces the model's layer and prunes unused DDS in that mod, so keep each size variant
  in its own mod; stage and package from `rtx-remix/mods/ai_pbr_2048` (`--mod ai_pbr_2048` /
  `--src ...\ai_pbr_2048`). Verify the packaged layer's DDS are at most 2048 px. Install one variant at
  a time when they override the same hashes.
- Costs (full mip chain, size calculations, not measurements): BC7 albedo or BC5 normals 21.3 MiB at
  4096 against 5.3 MiB at 2048; BC4 roughness 10.7 against 2.7 MiB. A sheet carries several maps.
- Since runtime patch 0030 a character's maps load at its first draw in a session, so a big pack costs
  nothing until the character is spawned, then one long frame (0.11-0.32 s measured for 0.3-0.5 GB) and
  its VRAM while drawn. Under real VRAM pressure undrawn maps give way (patches 0025 and 0026). None of
  this makes a 4096 pack cheap for an 8 GB card; the loader's low tier changes memory only, nothing
  visible.

## Packaging

- **For reuse** (a folder the user names; they chose `H:\BACKUP_20260815\Modding\ipg\!GMRTX_PBR_Test`
  before): `scripts/package_characters.py` writes a drop-in mod with only the referenced DDS and a
  `mod.usda` listing those layers, each character's maps, AI cache, masks, settings, hashes and
  previews, a copy of the tool, a README, and checks every DDS against the live mod. Shader inputs
  (adaptive emission and its fallback included) are copied byte for byte. Add character-specific
  notes to its README.
- **For the Workshop** (a hidden content pack the loader deploys to subscribers): follow the
  workshop-content-pack skill (`skills/workshop-content-pack/SKILL.md`). This skill provides its
  preferred inputs: `scripts/hotloader_export.py` (Model Hotloader's own export through the game) and
  `scripts/stage_pbr_mod.py` (only the referenced DDS, SHA-checked).
- **Update an existing pack's eye emission** without regenerating:
  `scripts/set_adaptive_emission.py` on a staged copy (dry run first).

## Runtime caveats (details: `references/runtime-notes.md`)

- The runtime is the RTX package's: the fork's `c6b48ed1` with this repository's patches, loaded by the
  native loader from `native-loader\packages\rtx-remix-runtime\...`. rpai writes bools, floats and
  textures (a rule from the older `384581b1`, which rejected colour inputs; `c6b48ed1` loads them), plus
  the opt-in `sss_radius` colour.
- `remix-dxvk.log` is written at exit, and current runtimes log no reload line: judge reloads in game.
- Mod precedence: `!advanced_material_editor` < `ai_pbr` < `pbr_<name>` packs < (fallback, always last)
  `~gmod_topbr`. Remix hot-reloads only on a `mod.usda` timestamp change.
- SSS works only with the material forced opaque and the skin colour as
  `subsurface_transmittance_texture`; not part of the standard.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| A texture shows no change in game | Its hash is predicted or stale: show the part (`reveal_hashes.py`), `rpai hashes`, `rpai publish`. Or another layer wins a byte-identical sheet (publish prints a note), or the user's Advanced Material Editor profile covers it |
| A game character's sheet lost its game-map look after a publish | The rpai layer now owns that hash and wins over ToPBR. If the user prefers the game maps, give every class on that sheet `"original": 1` in its per-texture `presets`, then `generate` and `publish`: the sheet leaves the layer and ToPBR's material shows again |
| "the game window did not accept the console message" | The game is loading or hung. Wait once; `hashes` falls back to earlier verified hashes. Do not loop or restart it |
| WinError 206 loading torch | The venv is on a long path: keep `RPAI_HOME` short (`%USERPROFILE%\.rpai`) |
| New mod folder not loaded | Rescan Mods once (Alt+X menu) or a restart |
| Eyes or skin look grey in the sockets | Path tracing. Eye emission (rpai's or the companion's eye whites) handles the eyes; skin stays original by decision. Check `nativeloader_eye_white_brightness` |
| Part invisible though its flags say visible | A material morph hides it (`[Fullbody]`): the user's setting, leave it |
| A dark band over the eyes is gone, or a shadow part has no live hash | The companion leaves painted shadows out of the draw in RTX sessions (`nativeloader_hide_painted_shadows`): expected |
| "doesn't fit into STAGING memory" in the Remix log | Harmless for sheets over 96 MB (Firefly's 11059×8847 stockings) |
| Colour constant ignored ("has unexpected type") | The old `384581b1` runtime; on the current one check `rtx.usd.legacyIgnoreColors` |
| Thin crease along UV seams (stockings, sleeves) | Maps generated before the gutter fix (2026-10-25): run `generate` again (the upscale cache is kept) |
| Same slit down the sides of the body with a model's own `normal_map` | Bake padding that does not match the islands; `relief_normals` handles it (RELIEF_VERSION 3): regenerate |
| A compiled model turns (almost) invisible after publish | Its VMTs alpha-test at 0.5 and the PMX images carry a mask in alpha (Wuthering Waves `_D` toon masks): point the PMX at RGB copies and republish (tool README, "Compiled models") |
| A sheet over 4096 has no hash | Model Hotloader 2.3.1 keeps it full size in `mmd/tf/`; this rpai reads both folders (an installed copy older than 2026-11-03 does not) |

## Done criteria for a character

- `rpai status` lists the model; the change was checked in game (no reload log line exists).
- A compare or AABB result with numbers was shown to the user.
- Predicted-only textures are named, with why (hidden, morph, painted shadow).
- For a game character: which sheets the rpai layer took over from imported game PBR.
- Every new decision is in the per-model preset's `doc` (clean name first) and, for a standard, in
  `references/standards.md` and the `classify.py` comments.
