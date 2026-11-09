# Runtime notes: Garry's Mod RTX with the native loader, Remix and Model Hotloader

State of 2026-11-08 (RTX package on Workshop item 3829070317, loader 0.16.0 released). Facts dated
earlier were measured then; the source is named where it is not this skill.

## Paths

| What | Where |
| --- | --- |
| Game | `H:\SteamLibrary\steamapps\common\GarrysMod`, the user's field install (Steam-managed, the native loader's `bin\win64\winmm.dll` in it); rpai stores it in `%USERPROFILE%\.rpai\config.json` (`game_root`). `GarrysMod_PoC` beside it is the development copy. `GarrysMod_RTX_c` is no longer a classic install (the user replaced it on 2026-10-30): never write there; its `rtx-remix\mods\ai_pbr` no longer exists (checked 2026-11-08) |
| Remix runtime | deployed by the loader from the RTX package: `native-loader\packages\gmod-rtx-remix\<version>_<generation>\runtime\d3d9.dll`; RTX sessions load it, and `bin\win64\d3d9.dll` (the user's own DXVK or ReShade) is never written (the repository's ADR 0028). `nlctl status <game root>` or `native-loader\logs\loader.log` names the deployed package version |
| Remix log | `rtx-remix\logs\remix-dxvk.log`. It is buffered: the file stays empty while the game runs and is written at exit (the repository's RESEARCH.md, after R21). Never wait on it during a session; judge in game |
| Mods | `rtx-remix\mods\`. rpai writes only the mod it is given (`ai_pbr`, or `--mod ai_pbr_2048`). Workshop packs deploy `pbr_<name>`; the RTX fixes write `~gmod_topbr` |
| Remix config | the RTX package's layers (`config\dxvk\*.conf` in its payload), copied to `native-loader\remix\dxvk-<n>.conf` at each RTX start and listed in `DXVK_CONFIG_FILE` before the user's own `dxvk.conf`; for an `rtx.*` option the first listed file that holds it wins, so they beat the root `dxvk.conf`. The user's `rtx.conf`, then `user.conf`, in the game root outrank every DXVK file. `garrysmod\data\native-loader\status.json` (`activation.layers`) lists what the latest RTX start read. Read them freely; never edit `user.conf`; ask before editing the others |
| Screenshots | `garrysmod\screenshots\<map>NNNN.jpg` (console `jpeg`) |
| Console log | `garrysmod\console.log` (only with `-condebug`). Read only your own session's part, from the byte offset where it ended before you started; never search the user's log |
| rpai runtime | `%USERPROFILE%\.rpai`: `venv` (Python 3.12, torch 2.8 cu129), `models\pbrify`, `work\<model key>`, `sources\` (rebuilt PMX copies), `ue_maps\` (converted game maps), `compiled_models.json`, `config.json` |
| Model Hotloader | the RTX package's copy: the add-on `garrysmod\addons\mmd_hotloader` (hidden in starts without RTX) and its natives in `garrysmod\lua\bin` (release 2.3.1; the repository's record `packages\model-hotloader\bin\mmdhl-native-release.json`). Its data: `garrysmod\data\mmd_hotloader\` (`assets`, `textures`, `library`, `terms`, `sources.local.json` with each import's source PMX path) |

## Remix mod loading

- **Runtime build.** The RTX package's runtime is the fork sambow23/dxvk-remix-gmod at `c6b48ed1` (its
  remix-1.6.1 merge, in the game since 2026-10-25) with this repository's patches (`runtime/base.json`,
  `runtime/patches`). Its log line `DXVK_Remix: remix-main+<hash>` names the commit of the patched tree
  that build was made from (R19: `248fa6ee` for the stored build, `b2129b8e` for GitHub's), so it
  changes with every runtime build. Before 2026-10-25 the game ran `384581b1`; the notes below say
  which build a fact was measured on.
- **Hot reload.** The runtime watches only `mod.usda`'s timestamp; rpai rewrites it atomically on
  every publish, and the reload takes about a second. `384581b1` logged "Async reloaded USD data
  swapped in successfully" (with many preloaded textures the swap lagged about 9 s); `c6b48ed1` and
  later log no reload line, and the log reaches the disk only at exit anyway. So `abtest.py` and
  `rpai compare` wait 30 s for that line and then rely on their settle time; reloads still apply
  (verified in game on Guinaifen's stockings).
- **Auto-exposure** re-adapts for several seconds after a swap: with an 8 s settle the first shot of a
  variant was 8/255 darker than its repeat. `abtest.py` defaults to `--settle 20 --camera-settle 6`
  (repeat noise 0.9-1.9/255).
- **A new mod folder** is discovered only at startup, or with Alt+X → Enhancements → Loaded USD Files
  → "Rescan Mods & Reload USD Stage".
- **Which mod wins a hash.** Among authored mods, the first in path order:
  `!advanced_material_editor` < `ai_pbr` < `pbr_<name>` (a Workshop pack). The user's Advanced
  Material Editor profiles override rpai; never write into `!advanced_material_editor` (its bridge owns
  and resets it). Generated fallback mods rank after every authored mod whatever their names: runtime
  patch 0020 gives the mods in `rtx.gmod.fallbackMods` (default `~gmod_topbr`) the last priority
  (ADR 0092), and the RTX fixes skip any hash another mod's USD already replaces. So an rpai or pack
  material for a hash always beats ToPBR's for it, also when it is published later.
- **Preloads.** rpai writes `preload_textures = 1` on every material (kept by ADR 0102). Since runtime
  patch 0030 (ADR 0103, `rtx.texturemanager.preloadOnFirstDraw`, default True) a preloaded material
  loads whole and synchronously in the first frame that draws it, not when its mod loads: a character's
  first appearance in a session is one long frame (0.11-0.32 s measured for 0.3-0.5 GB of maps, up to
  0.58 s on a busier machine), and characters nobody spawns cost nothing. Under real VRAM pressure
  replacement textures stop growing and undrawn preloads drop to their smallest mips (patches 0025 and
  0026, ADR 0100). Mod reloads during a capture still restage what is drawn: keep them few.
- Remix's legacy material defaults (the package's classic layer): roughness 0.7, metallic 0.01.

## Texture hashes

- A Remix override is keyed by the texture hash: XXH64 of the top mip as uploaded, because the
  package's classic layer sets `rtx.useObsoleteHashOnTextureUpload = True` (Remix's own default is
  False: XXH3).
- **Where that option comes from** (rpai decides it as the runtime does since 2026-11-09,
  `remixhash.resolve_obsolete_hash_option`; the order is in `tool/rpai/remixhash.py.md`): the loader
  lists the package's layers first in `DXVK_CONFIG_FILE` (`native-loader\remix\dxvk-1.conf` is the
  classic defaults, line 139 sets it), and for an `rtx.*` option the first listed file that holds it
  wins; the game root's `rtx.conf` and then `user.conf` outrank every DXVK file. The game root's
  `rtx.conf` has not set it since 2026-10-29, and rpai used to read only that file: its predictions
  were XXH3 from then on, and none of the 191 live hashes recorded until 2026-11-08 matched one.
  `rpai hashes` prints the function and the file and line that decided it.
- **Live hashes are authoritative.** The game reports them through `RemixMaterial` in client Lua, and
  only for textures it has drawn.
- **Offline prediction** from the VTF is the fallback for parts the game has not drawn yet, one
  candidate per texture:
  - VTFs with an alpha flag (Model Hotloader sets 0x2000) upload as BGRA;
  - opaque VTFs upload as X8R8G8B8 and hash as BGR0: the packaged runtime hashes the pad byte as zero
    (`GetDefinedTexelBits` in `d3d9_texture_hash.h`). Before that change (verified 2026-10-26 on
    `c6b48ed1`), Source wrote only the B, G, R bytes, the pad byte kept whatever the upload memory held,
    and Remix hashed it too: an opaque sheet hashed to BGR0, BGRF or leftover bytes (the Robin import's
    `衣.png` hash `0xA669FF339EF9704B` is exactly its BGR plus the alpha of `inmon2.png`, the sheet
    uploaded before it). The map sessions record runtime builds from 2026-10-26 20:20 on with the pad
    bits zeroed (remix-map-pbr's `references/remix-hashes-and-layers.md`);
  - **measured on characters 2026-11-09:** XXH64 with these layouts reproduces 251 of the 264 live
    hashes rpai recorded whose VTF the field still has (Fu Xuan, HuoHuo and Firefly 51 of 51), and 3 of
    3 ToPBR recorded. The 13 misses are opaque sheets recorded by 2026-10-26 under the old pad byte:
    one single-colour sheet (`c2013648c2e9b597`) hashed three ways in those records and as its BGR0 in
    every record since. No other layout or hash function matched any of them;
  - on Guinevere 8 of 13 predictions agreed overall; the first Firefly layer's predictions for its
    hidden bunny suit, ears, beads and heels were all wrong (found 2026-11-06);
  - compiled addons' DXT5 VTFs upload their blocks unchanged: XXH64 of the top mip's raw blocks
    matched all 3 of the compiled Robin's live hashes (`robin_zzz.mdl`, 2026-10-25).
  Show hidden parts in game and re-run `rpai hashes`: `scripts/reveal_hashes.py` does both and puts
  the visibility back.
- **Parts that are never drawn** keep predicted hashes whatever you show: a part a material morph hides
  (Guinevere's `[Fullbody]`), and painted shadows (目影, 发影, `Moyin`, ...) that the companion leaves
  out of the draw in RTX sessions (below). Those shadows need no PBR; say so in the report.
- `RemixMaterial.GetAllTextureHashes` reports a compiled model's texture hash on only one of the
  materials that share it (Robin: `Body`, `Brows`, `Bangs`); the others return none. rpai merges them
  per texture, so this costs nothing.
- The same texture can upload with a different hash in a new game session. After a restart,
  Guinevere's `灰.jpg` and `sita.png` changed. rpai therefore keeps the union of every hash the game
  ever reported per content-addressed texture key; re-run `rpai hashes` after a restart and before
  packaging.
  - Only opaque sheets drifted (the pad byte above). It also happened within one map instance: on
    2026-10-26 Source re-uploaded every texture about 13 times on gm_poolrooms, and the Robin import's
    `衣.png`, `颜.png` and `发.png` got new hashes from the second upload on, so their PBR vanished
    until `rpai hashes` + `publish` added them. When an opaque sheet loses its PBR, re-run both.
- A busy or loading game does not abort `hashes`: earlier verified hashes are kept.
- `--no-live` is safe, but only because of that union. Before the fix, it silently replaced verified
  hashes with predictions, and 3 overrides stopped applying.
- **Texture size.** Model Hotloader 2.3.1 keeps a source over 4096 at full size and names its VTF
  `mmd/tf/<sha16>` instead of `mmd/t/<sha16>` (Ruan Mei's 8192 body sheet and 15770x6308 stockings,
  2026-11-03); rpai reads both. A re-import with changed textures changes the hashes: run `rpai run`
  again.

## The RTX package's character features (they change what you see and measure)

All in RTX sessions only, for Model Hotloader characters on the map; settings under the RTX Remix
tab, Rendering > Model outlines.

- **Painted shadows left out of the draw** (`nativeloader_hide_painted_shadows`, default 1;
  ADR 0104): overlays such as 目影 over the eyes, 发影 under the fringe, Laevatain's `Moyin` and `Hair+`
  are not drawn, because path tracing casts the real shadow there. Bodygroups, saves and files do not
  change. Such parts get no live hash and need no PBR.
- **Solid hair** (`nativeloader_solid_hair`, default 1; ADR 0104): a hair part whose texture is mostly
  opaque but cut by the 0.5 alpha test loses `$alphatest` (and its soft copy `$translucent`) in memory.
  Texture hashes stay, so rpai layers still apply.
- **MMD alpha** (runtime patch 0017, ADR 0081): categorized draws treat opacity at or above 0.5 as
  opaque.
- **Steady eye whites** for every imported character, a manual chooser and a brightness slider that
  also scales rpai's adaptive eye emission: `standards.md`, "The companion's eye whites".
- **Imported game PBR** (below).
- **Characters load on first use** (ADR 0099): only the most recently used characters stay ready
  (0, 5 or 10 by the loader's memory profile, ADR 0101: minimum 8 GB VRAM / 16 GB RAM, recommended 16 /
  32, high 24 / 64). A first spawn from the NPC tab took 0.5-6 s in R13's runs; spawn and wait before
  `rpai hashes` or a capture.

## Imported game PBR (the RTX fixes' ToPBR)

Characters ripped from games ship the game's own maps beside the PMX, unreferenced by it. The RTX
fixes convert them on their own (R11-R13, R23; ADRs 0091, 0093, 0095, 0098):

- **What it reads**, by family stem beside the base texture `T_*_D`: Wuthering Waves `_N`, the game's
  Normal_Roughness_Metallic map (RG normal, alpha roughness, blue metalness from 0.55 with all metal by
  0.8; R23); Arknights: Endfield `_N`, `_P` (metallic, smoothness to roughness), `_E` (emission);
  Silver Palace `_N` (XYZ), `_MRA` (R metallic, G roughness), `_E`. Classes the game does not ship
  follow `aggressive.json`. Skin, face and eye texels stay protected, and faces get no generated
  material (so the companion's eye-white aliases keep working).
- **Pairing**: exact game names first (a Wuthering Waves family is also known by its character
  prefix `t_<...>md<5 digits>` when another family of that character has an `_ID` or `_HM` map, R23);
  a renamed base (衣服.png) pairs by its UV layout only with clear evidence (correlation 0.28, score
  0.36, margin 0.12) and otherwise abstains (R12-B: 146 agree, 0 wrong, 113 abstain on 259 pairs).
- **Source folder**: the import's source path comes from `garrysmod\data\mmd_hotloader\sources.local.json`.
  After one successful conversion `~gmod_topbr\textures\game_materials.registry` keeps the result
  for the live texture identity (`mmd/t/<16 hex>`), so the look survives a deleted source folder; a
  character never converted that way (its source was already gone, as for five of the field library's
  game characters in R11) needs its source folder once.
- **Manual choices**: the spawn menu's Utilities > RTX Remix > **Imported game PBR** panel (or
  `rtx_topbr_game_editor`): look at the character, "List looked-at character", pick a material, then
  a discovered map family, individual maps with their game layout (Wuthering Waves, Endfield, Silver
  Palace), no game maps, or automatic. A choice is stored per live texture identity
  (`game_overrides.registry`), applies to every character showing that texture and outlives the source
  folder.
- **Switches and storage**: `rtx_topbr_game_maps` (default 1) turns it on or off; world conversion
  (`rtx_topbr_enabled`) stays off by default. Maps are BC5 normals and BC4 roughness and metallic (a
  2048 family is about 11 MB), with no session budget; a release that changes no conversion reuses
  them (ADR 0098).
- **Progress** (R23): while a spawned character's maps convert, a notice at the top right says
  "Preparing PBR materials for imported characters: n of m" with a bar, then that they are ready.
- **Precedence**: authored replacements always win (patch 0020 above). An rpai layer on a sheet
  replaces ToPBR's whole material for that hash, its game maps included. rpai's own `normal_map` reads
  only RG of a Wuthering Waves `_N`; its roughness and metalness need grey copies as `rough_map` /
  `metal_map`, or are better left to ToPBR.

## This Remix build's quirks (verified in source and in game)

Measured first on `384581b1` (2026-08-09, the fork's build before 2026-10-25, based on upstream
68ee7965, between remix-1.5.2 and 1.6.0); where `c6b48ed1` differs, it says so.

- **Colour inputs.** `384581b1`'s "fix crashes" commit 061b8be0 added an `IsHolding<Vector3>` check in
  `rtx_material_data.h` and `rtx_lights_data.cpp` that rejected every `color3f`, `float3`, `double3`,
  `half3`, `color3d` and `color3h` input ("has unexpected type, using default value"), for materials
  and lights; `uint8` inputs loaded only as `uchar`, and `alpha_test_type` and `blend_type` never
  loaded; a rejected value still hid weaker layers' values. On `c6b48ed1` colour inputs load
  (`rtx.usd.legacyIgnoreColors`, default False, restores the old behaviour). rpai writes bools, floats
  and textures, so its layers work on both, except the opt-in `sss_radius` colour (`color3f`), which
  loads only on `c6b48ed1` and later.
- **Emission:** `emissive_mask_texture` (an sRGB colour, used as-is) times `emissive_intensity` (MDL
  default 40), gated by `enable_emission`. With a texture, `emissive_color_constant` is ignored.
- **C-16 scene-adaptive eye emission** (runtime patch 0016, tuned 2026-10-31, ADR 0069):
  `float inputs:emissive_adaptive_intensity` (0..65504; 0 off). With `rtx.adaptiveEmission.enable`
  the runtime uses `emissiveColor * adaptiveIntensity * scale * clamp(L_adapt, minLuminance,
  maxLuminance)`; disabled auto exposure uses `rtx.adaptiveEmission.fallbackLuminance`. Runtimes
  without it ignore the input and keep `emissive_intensity`. rpai writes it for maps carrying eye
  classes beside the unchanged fallback; the publish option is a ratio to that fallback per scene
  luminance (default `25`). Derivation and measurements: [standards](standards.md#scene-adaptive-eye-emission-c-16-tuned-2026-10-31).
  The player's eye-white brightness slider scales it live.
- **Subsurface scattering works only under two conditions.** Measured on Guinevere's forearm:
  - diffusion profile on → the diffuse is replaced by a scattering term from one probe ray per pixel;
  - **the material must be forced opaque** (`bool inputs:use_legacy_alpha_state = 0`,
    `bool inputs:blend_enabled = 0`). Model Hotloader's draws are non-opaque, so the opaque-only
    probe never lands. Remix then drops the diffuse and adds nothing, which renders near-black.
    Force opaque only on body sheets: decal sheets need their alpha;
  - **the skin colour must come from `subsurface_transmittance_texture`.** In this mode the colour
    is the transmittance (default grey);
  - `subsurface_radius_scale` below about 0.5 makes the probe too short on `384581b1` (upstream fixed
    it in remix-1.6.0, 5941c63c, REMIX-5909; whether `c6b48ed1` has it is unverified);
  - the mean free path is radius × radius_scale × `rtx.subsurface.diffusionProfileScale` × 0.01
    world units. `subsurface_max_sample_radius` 16 means R = 1.0;
  - the indirect path (ReSTIR GI or NRC) has no scattering case;
  - thin-opaque transmission (`subsurface_measurement_distance`) only adds light from behind;
  - SSS is not part of the standard: it would need its own full-body AABB and the user's decision.
  - **On `c6b48ed1` (Guinaifen, 2026-10-25):** with `use_legacy_alpha_state = 0`, `blend_enabled =
    0`, the albedo as transmittance, `subsurface_radius_scale` 5 and `color3f subsurface_radius`
    (1, 0.35, 0.2), scattering renders, warms the skin and lets red bleed between fingers and toes. It
    also darkened the skin 3-8/255, softened normal-map relief, drew streaks along both forearms that
    the same layer without SSS did not have, and showed a band where the body meets a skin piece that
    cannot scatter (her upper neck is skin on the cloth atlas, and SSS is per material). On the face
    sheet it dulled the eye whites. rpai turns it on through the `sss` class field, only for sheets
    whose every class asks for it.
- **Eyes:** the runtime's `rtx.eye.*` shading applies only to Source eyeball draw calls, not to MMD
  eye meshes.
- **Anisotropy works** (`anisotropy_constant` and `anisotropy_texture`, -1..1, the texture stored as
  0..1). The tangent follows the texture's +U axis: on legs unwrapped with V down the leg, a negative
  value stretches highlights along the leg and a positive one widens them around it (probe at
  ±0.7 on Guinaifen's stockings, 2026-10-25). rpai writes it from the `aniso` class field.
- **Huge textures:** over 96 MB, Remix logs "doesn't fit into STAGING memory" and uploads them
  synchronously. Harmless (R19's field log listed two 11059x8847 sheets of the user's `ai_pbr`). A
  replacement texture larger than the GPU can create still fails when its big mips stream in (R19's
  open issue): cap such a sheet with a per-texture `max_size`.

## Commit memory while the game runs (WDDM)

Measured 2026-10-27 with the RTX game up: the game held about 22 GB private, and only 3-12 GB of the
system commit limit (about 90-106 GB, a system-managed pagefile that grows on demand) were free. Under
WDDM the VRAM torch reserves is charged to system commit, so the AI stage alone can exhaust it:

- uncapped, the DAT x4 upscaler took the process to ~9 GB within 12 s (one 512 px tile with cuDNN
  reserved 4.3 GB of VRAM). Free commit fell from 9.1 to 0.62 GB;
- with cuDNN off, the CUDA pool capped at 1 GB and `--tile 128`, it stays near 4.5 GB.

The capping wrappers used then (`rpai_capped.py`, `run_rpai_guarded.ps1` in
`H:\BACKUP_20260815\Modding\ipg\zzz_33_c\pbr\tools`) are gone (checked 2026-11-08). Without them:
pass `--tile 128` (or `--upscaler span`, about 40x faster), run one AI stage at a time, and before a
`generate` check free commit and other sessions' `-m rpai` processes (an uncapped run elsewhere held
17 GB). The venv's `python.exe` is a launcher stub; the interpreter is its child. Since R13 the game
itself holds far less (working set about 11 GB idle in the field, against 18 GB before).

## Model Hotloader facts used by rpai

- Imports live in the game's Model Hotloader cache. rpai finds an import by PMX path, or by the
  manifest `sourceHash` (the SHA-256 of the PMX), so a moved or renamed folder still works;
  `--asset <id8>` binds a PMX to a given import. `assets\<id>\model.bin` is the source PMX byte for
  byte, so a lost PMX can be rebuilt from it (March 7th, tool README).
- The model key is `<english name slug>_<asset id[:8]>` (`config.model_key`), for example
  `new_mmd_model_9cdc990f`; a compiled model's is `<name>_<sha1 of the model path>[:8]`. Work files go
  to `%USERPROFILE%\.rpai\work\<key>`, and the per-model preset is `tool/presets/models/<key>.json`.
  The key is an identifier, not a name: it can carry the PMX's tags (`robin_r18_f9c3e4b4`), which the
  naming rule keeps out of names (SKILL.md, "Names").
- The same PMX imported twice is two assets, two keys and one set of hashes: the key that sorts first
  wins every shared hash (tool README, "Remaking a layer").
- Part visibility, the camera and morphs: see `testing-protocol.md`.
