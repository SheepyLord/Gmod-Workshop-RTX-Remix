---
name: remix-map-pbr
description: Remaster a Garry's Mod map for RTX Remix (GMod RTX) the way the user's gm_poolrooms, Backrooms, modern_house, lestnicha3 and gm_brmovie_complete remasters were made - extract the Workshop map, classify its materials, generate AI PBR maps (PBRify upscale, normal, roughness, height), add CC0 photoscans where textures or plants are too low-res, build a Remix mod of mat_HASH layers keyed by live-checked texture hashes, and add a map-only Lua add-on with Remix API lights, the physical sky, night lights, mirrors, glass, water, scoped settings and visibility; then tour, compare with stock, measure frame and load times. Use it when a map should look PBR or RTX-remastered, map textures need PBR maps or upscaling, or the task is a map's Remix mod, lights, sky, plants, mirrors, water or caustics, map artifacts, slow loading or low frame rates under GMod RTX, culling for path tracing, or a map before/after. Not for characters (mmd-remix-pbr); a remaster's Workshop upload follows workshop-content-pack.
---

# Map remaster for RTX Remix (Garry's Mod RTX)

A remaster never touches the map file. It layers two halves on it at runtime:

| Half | Folder in the game | What it holds |
| --- | --- | --- |
| Remix mod | `rtx-remix/mods/<map>_rtx/` | `mod.usda` (root layer, sublayers), `materials.usda` (one `over "mat_<HASH>"` replacement per texture hash), `textures/*.rtex.dds` |
| Lua addon | `garrysmod/addons/<map>_rtx/` | boots only on its map: Remix API lights on the map's own fixtures, scoped Remix options (sky, haze, grade, game lights off), scoped engine settings, map fixes (mirrors, water, sprites, missing textures), visibility |

Both halves are needed. Without the addon the mod still loads, but gmRTX's stock light updater runs: on
modern_house that was 1069 helper models a frame, the GPU at 35-40 % and 22 engine fps (2026-10-27).

The working pipelines are Python scripts in the user's fork `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`
(GPL-2.0; branches and paths in `README.md`). This skill describes their behaviour, inputs, outputs and
commands; it holds no code from them. The most complete for interiors is Modern House
(`source/modern_house_rtx/tools`, branch `claude/modern-house-rtx`), copied from Backrooms, which grew out
of the gm_poolrooms work. The newest, lestnicha3 (`source/lestnicha3_rtx/tools`, branch
`claude/lestnicha3-rtx`), is Modern House's copied for an island in the open air: the physical sky as the
main light, CC0 photoscans for grain, ground and plants, night lights driven by the sun. gm_brmovie_complete
(`source/gm_brmovie_complete_rtx/tools`, branch `claude/brmovie-rtx`) is lestnicha3's with Backrooms'
fixture lights, for a big interior map with an outdoor lot: lights that follow the map's switches, PAS
visibility, live hashes for gmRTX's per-material solid-colour textures, and the 3D skybox drawn at its true
scale.

Read the references when you reach their stage:

- `references/pipeline.md`: every stage and script of the three implementations, the folders, recipe and
  light numbers, how the maps differ, what to change for a new map.
- `references/remix-hashes-and-layers.md`: texture hashes (predicted, live, drift), the mod's USD, what this
  runtime accepts, mod priority and folder names, reloads, tag textures.
- `references/testing.md`: cameras, tours, stock-vs-remaster, A/B with noise floors, frame times, visibility
  checks, load timelines, what evidence to present.
- `references/lessons.md`: pitfalls with symptom, cause, fix, map and date (R3-016 among them).

## Ground rules from this user

- **Measure; don't eyeball.** The user wants numbers: frame times per camera with the run-to-run noise
  next to them, before/after pairs with a noise floor, how many predicted hashes matched the live game.
  Say "within the noise" when it is.
- **Ask which permissions this task has, before you start.** The three map sessions were each granted
  "commit, but don't push", "you may close or reopen any game session" and "decide on your own". Those
  grants were per task and do not carry over. Without them:
  - never restart, quit or kill the user's game; start your own test sessions with `-multirun` and end
    only those; never stop a `gmod.exe` you did not start;
  - commit only when asked; never push the fork's map branches (Modern House's must never be pushed).
- **Config files.** Never edit Remix `user.conf`. Ask before editing `rtx.conf`, `dxvk.conf` or the game's
  `cfg` files. A remaster sets its Remix options live from Lua (`RemixConfig.SetConfigVariable`) while its
  map is loaded and puts them back when the map unloads; it writes no config file. Leave the user's own
  choices alone (their archived `rtx_lightupdater 1`, their PsychoV17 purity 1.33).
- **Ask before downloads or the network:** subscribing to the map (a Steam download), rpai's `setup.ps1`
  (72 MB of weights), the Remix Toolkit, reading the Workshop page or the Remix documentation online. When
  the user allows free resources (lestnicha3, 2026-11-08), take CC0 ones (Poly Haven, ambientCG), keep the
  downloads under this repository's `out\`, and credit them in the doc page.
- **Installs.** Develop and test on the PoC, `H:\SteamLibrary\steamapps\common\GarrysMod_PoC`. Touch the
  field install `...\common\GarrysMod` only when the user asks, after backing up what you will change.
  Never write into `GarrysMod_RTX_c` or its backups (the user replaced it on 2026-10-30). The fork's
  scripts default `MHRTX_GAME`, `BRRTX_GAME` and `POOLRTX_GAME` to that install: always set the variable.
- **The map stays untouched.** Steam's files and the map author's files are never modified.
- **Derived assets.** Textures upscaled or derived from another author's map are still that author's work.
  Keep them local, or in a hidden Workshop item, unless the original author's terms allow redistribution.
  Modern House is the model: a local branch that is never pushed and the hidden item 3829275998 (the user
  chose "Keep it local", 2026-10-29). Never commit extracted map files (`map_extract/` and `work/` are
  git-ignored). Textures generated from scratch (the poolrooms tile) are yours. Anything public is the
  user's decision.
- **Licence of the tools.** The fork is GPL-2.0. A new map's pipeline is a copy of the fork's scripts on a
  branch of the fork; never copy fork code into this MIT repository.
- **Names.** A remaster, its folders (`<map>_rtx`), package id (`<map>-rtx`) and titles carry the map's
  own name only: no author, version or uploader tag (the user's naming rule of 2026-11-08, written for
  characters; `check_pack.py` refuses such tags in ids and titles).
- **Never force `r_forcehwlight 1` or `r_forcehwskin 1`.** The first put skinned models in bind pose on
  modern_house (R3-016), the second drew player and NPC models as faces without bodies (`lessons.md`).
- **Privacy.** Never search the user's `console.log`; read only what your own session wrote, from the byte
  offset where it ended before your launch.
- **Shared game.** Other sessions may drive the same game. Tell them before a capture, keep camera
  overrides to the capture, and put back every option you toggled and every entity you spawned.
- **Don't get stuck on side issues.** Note them, keep the evidence, move on.
- Report plainly what changed and how it looks, with the numbers and what was not checked.

## Prerequisites and setup check

| Need | Where | Check |
| --- | --- | --- |
| Python 3.12 with numpy, scipy, Pillow, xxhash | system Python, for every script except the AI stage | `python -c "import numpy, scipy, PIL, xxhash"` |
| rpai venv (torch with CUDA) | `%USERPROFILE%\.rpai\venv` | `"%USERPROFILE%\.claude\skills\mmd-remix-pbr\tool\rpai.cmd" doctor` |
| PBRify_Remix v1.7.2 weights (CC0) | `%USERPROFILE%\.rpai\models\pbrify`: `4x-PBRify-UpscalerV4.safetensors` (DAT), `4x-PBRify_UpscalerSPANV4.pth`, `1x-PBRify_NormalV3.pth`, `1x-PBRify_RoughnessV2.pth`, `1x-PBRify_Height.pth` | the five files exist |
| rpai's `ModelRunner` | `%USERPROFILE%\.claude\skills\mmd-remix-pbr\tool` | set `MHRTX_RPAI` (or `BRRTX_RPAI`, `POOLRTX_RPAI`) to it; the scripts' default `H:\BACKUP_20260815\Modding\ipg\!GMRTX_PBR_Test\tool` holds an identical `rpai/ai.py` (compared 2026-10-31) |
| NVTT exporter | `C:\Program Files\NVIDIA Corporation\RTX Remix\exts\lightspeed.trex.app.resources\deps\tools\nvtt\nvtt_export.exe`, hard-coded in `texlib.py` | the file exists |
| An RTX session | the PoC with the native loader and the RTX package (Workshop 3829070317) | gmRTX's Lua API (`RemixLight`, `RemixConfig`, `RemixMaterial`), the `rtx_agent` and `niknaks` add-ons, the fixes module with `rtx_patch_vis_pas`, the package's runtime (the fork's `c6b48ed1`, its 1.6.1 merge, with the repository's patches; the log's `remix-main+<hash>` names the patched build, not `c6b48ed1`) |
| The map | subscribed (ask first) | `H:\SteamLibrary\steamapps\workshop\content\4000\<id>\*.gma` |

What the map pipelines reuse from rpai: the venv, the PBRify weights, its tiled `ModelRunner` (overlapping
feathered tiles, fp16 with an fp32 fallback, halves the tile on CUDA out-of-memory) and the Toolkit's NVTT
settings. They do not use rpai's CLI, its UV-space class rasteriser or its Model Hotloader bridge.

The offline hash prediction assumes `rtx.useObsoleteHashOnTextureUpload = True`, which the RTX package's
`classic_remix_defaults.conf` layer sets. Run the AI stage on a quiet machine, not beside a game that is
being measured: the Backrooms AI batch beside the game ended in `VK_ERROR_DEVICE_LOST`, and rpai's notes
show torch's VRAM charged to Windows commit memory while the game holds about 22 GB.

## Workflow

Run the scripts from `source/<map>_rtx/tools` of your branch. `python` is the system 3.12;
`<rpai python>` is `%USERPROFILE%\.rpai\venv\Scripts\python.exe`. Script names are Modern House's; the
other two maps' equivalents are in `references/pipeline.md`.

1. **Scope with the user.** Map id and internal map names; the look (each brief asked for a "stunning"
   result in the map's own vibe, checked visually on multiple areas); the test install; whether you may
   restart the game, commit, use the network; where the result goes (local, hidden item, public) given the
   map author's terms; the performance target (the user plays at 4K with DLSS and 4x frame generation on
   an RTX 5090).
2. **Branch and copy the pipeline** inside the fork: a worktree under `.claude\worktrees\<name>`, a copy of
   `source/modern_house_rtx/tools` as `source/<map>_rtx/tools`, and a renamed paths module (`mh_paths.py`:
   `MAP`/`MAPS`, `WORKSHOP_ID`, addon and mod folder names), environment-variable prefix, Lua table names,
   mod name and light hash base. Add `.gitignore` lines for `map_extract/`, `work/` and the mod's
   `textures/`. The checklist is in `references/pipeline.md`, "Starting a new map".
3. **Extract.** `python extract_map.py [path to .gma]` unpacks the Workshop addon to `map_extract/gma`,
   each BSP's pakfile to `map_extract/<map>/pak`, its entities and static props to JSON, and the parsed
   faces to `work/<map>/faces.pkl`. Without a path it reads Steam's copy under the game's library.
4. **Survey the map and take the stock shots.** With the map loaded in a test session (no remaster yet, or
   `python stock.py on`), find one camera per region: `python survey.py <label>` (spread over the AI nodes)
   or Backrooms' `find_cameras.py <map>` (teleport destinations, scored by light). Write
   `tools/cameras_<map>.json` and shoot `python tour.py <map> before`. Look at every region for artifacts:
   black water, giant tiles, glow sprites, fake light cones, missing textures, missing mirrors.
5. **Inventory and classify.** `python inventory.py` writes `work/inventory.json`: every material by world
   area and prop instances, with its shader, textures and VTF formats. `classify.py` maps each material to
   a class by regexes on the material and texture names (VBSP's cubemap copies `maps/<map>/..._x_y_z`
   stripped first), then `$surfaceprop`, then the shader. `python contact_sheet.py` shows the base
   textures; pin mistakes in `tools/overrides.json`. Glass, mirrors, water, emitters, decals and unlit
   materials get no AI: they are hand-made. Faces are not all the map draws: add overlays (BSP lump 45),
   detail sprites, sky faces and particle materials (lestnicha3's `inventory.py`), and note each material's
   `$detail` and tint.
6. **Hashes, predicted and live.** `python tex_jobs.py` writes `work/textures.json` (per texture: its
   predicted Remix hash per animation frame, size, format, materials, class, world-area share, tint),
   decodes the sources to `work/src/` and writes the AI job list `work/jobs_ai.json`, most visible first.
   Then load the map, look around so its textures are uploaded (on a big map: draw it whole and move the
   player, not only the camera, through every region), and run `python live_hashes.py`
   (gmRTX's `RemixMaterial.GetAllTextureHashes` for every inventoried material); run `tex_jobs.py` again to
   merge the live hashes. Report the match count: on modern_house 106 of 110 predictions matched, and the 5
   textures that other mounted content overrides (HL2's `lights/white*`, two de_elysion metals) got their
   live hashes added. gmRTX's solid-colour fix gives every material whose texture is one colour its own
   texture (`rtx_solidcolor_<material>_rt`), so those hashes exist only live (gm_brmovie_complete's mirrors
   and 42 textures). Details: `references/remix-hashes-and-layers.md`.
7. **AI maps.** `<rpai python> ai_tex.py ..\work\jobs_ai.json [--only name,...]` writes `work/ai/<name>/`:
   the upscaled `albedo.png` (and `alpha.png`), `normal_raw.npy`, `rough.png`, `height.png`. Tiling world
   textures are processed with wrap-around padding so they stay seamless. A finished job is skipped on the
   next run. Measured on the RTX 5090: 139 jobs in 2722 s (modern_house), 1132 jobs in 5548 s (Backrooms),
   14 in 316 s (lestnicha3). A material's `$detail` is invisible under gmRTX: bake it into the AI input,
   except a strong grain, which the upscaler turns into blobs (upscale the plain base, add the grain from a
   scan in step 8). Crop one spot from source, input, AI output and final to check.
8. **Compose.** `python compose.py [--only ...] [--force]` turns the AI outputs and the originals into
   `work/tex/<name>/{albedo,normal,roughness,metallic,height,emissive}.png` and `work/composed.json`, from
   the class recipe (`RECIPES` in `compose.py`) and per-texture changes in `overrides.json` "textures".
   Inspect the maps before building. Recipes and what each key does: `references/pipeline.md`. Don't bake
   a world or BSP-prop material's tint: gmRTX's DECAL_STATIC marking makes Remix apply it live (compare
   debug views 23 and 32). Where the source has no detail to upscale, use CC0 photoscans: `micro` (a
   high-passed scan's relief and grain), `scan` (a whole ground), `plant_atlas.py` (photoscanned plants in a
   foliage atlas at the places the model's UVs expect them); give foliage thin-opaque transmission and
   alpha snapped to 0 and 255.
9. **Hand-made materials and tag textures.** In `overrides.json` "materials": clear glass (translucent,
   thin-walled), frosted glass, mirrors, LED emitters, water sheets, sky faces, each listing the textures
   (or hashes) it replaces. Where a replacement must apply only on this map, or to a texture that is shared
   with another surface, the addon binds a small "tag" VTF of your own (`vtfwrite.py`) and the mod targets
   the tag's hash (poolrooms water and openings, Modern House mirrors).
10. **Build the mod.** `python build_mod.py [--no-prune]` encodes the DDS (BC7 colour, BC5 normals, BC4
    roughness/metallic/height) with NVTT, writes `materials.usda` and rewrites `mod.usda` atomically, and
    prunes unused DDS. Preload (`preload_textures = 1`) a mod under about 1 GB: streaming left lestnicha3's
    walkway floor at a tiny mip. A running game hot-reloads on the `mod.usda` timestamp; a brand-new mod folder is
    found only at startup or with Alt+X → Enhancements → Loaded USD Files → "Rescan Mods & Reload USD
    Stage" (the user's click, or your own test session's restart). Keep `MHRTX_DDS_QUALITY` at its default
    (`normal`): production BC7 took about 3 hours on modern_house for no visible gain.
11. **Lights.** Edit `tools/lights_style.json`, run `python gen_lights.py`; it writes the addon's light list
    (`lua/<addon>/lights.lua`). Light sources come from what the map really has: fixture models (lens size
    from the model geometry), emissive brush faces (LED strips, light openings), the light entities no
    fixture accounts for, and extras the place lacks (Modern House's pool lights). A fixture or entity in a
    switch group (a named light the map turns on and off: a breaker box, a flicker) records the group; the
    add-on's server follows the named lights (`HasSpawnFlags(1)` is "off") and the client switches the group
    (gm_brmovie_complete). Each light records its BSP vis cluster. The addon creates them with `RemixLight.Create*`, hides the game's own lights from
    Remix (`rtx.ignoreGamePointLights/SpotLights/DirectionalLights True`, only once its lights exist),
    suspends gmRTX's light-updater hooks for the map and turns Light2RTX's autospawn off. Colours are
    kelvin per kind and per region box.
12. **Sky, mirrors, water, caustics, fixes.** Physical sky (`rtx.skyMode 1`, its own sun; set
    `rtx.atmosphere.sunRotation` to 90 minus the azimuth) scoped to the map, with `gen_sky.py` as a painted
    fallback skybox; answer the native loader's `NativeLoaderSkyOwner` hook so its companion leaves your sky
    alone (ADR 0031). Mirrors: gmRTX deletes `func_reflective_glass`, so `gen_mirrors.py` writes the quads
    and a tag texture and the addon draws them in `PreDrawTranslucentRenderables`. Water: RTX Water's
    `RTXWater_MapProfile` hook (calm), or the translucent-flag fix. Hide glow sprites and fake beam cones on
    the server at `InitPostEntity` and `PostCleanupMap`. Caustics and curved-tile unfolding are the
    poolrooms tools. Outdoors (lestnicha3): the mapper's `light_environment` as the sun; a dim "haze sun"
    distant light along it, since the atmosphere's sun does not light the froxels; the froxel range raised
    to the space (45 m); `r_3dsky 0` scoped and the 3D skybox room's props hidden; night lights faded by
    the sun's elevation. A map whose 3D skybox holds its surroundings (gm_brmovie_complete's lot: hills, a
    town, a railway) gets them back at true scale (`gen_skybox.py`: 16 x the offset from the sky camera,
    props at `modelscale` x 16, the skybox's copy of the playable area left out, drawn only outdoors). When
    the companion drives the sky (`nativeloader_sky_follow_map 0`, the user's
    field setting) leave it its sky and follow its sun instead of answering `NativeLoaderSkyOwner`. Fix a
    texture's category from the addon (`RemixMaterial`): IGNORE hides fake shafts, removing DECAL_STATIC
    stops an overflowing tint.
13. **Visibility.** Never cull what the path tracer needs. Small maps: keep gmRTX's whole-map drawing and add
    PVS-cover points on the server (`python gen_vis.py` → `vis_points.lua`, 31 points cover modern_house) so
    every networked prop is sent. Huge maps where the whole map is CPU-bound (Backrooms, about 46 ms): the
    engine's PVS widened to the PAS (`rtx_patch_vis_pas 1`, 2-5 % of the map) with `r_novis 0` and
    `rtx_patch_forcenovis 0` scoped. Check with `cullcheck.py`/`vischeck.py` (`references/testing.md`).
    Measure the PVS first: on an open map (lestnicha3, 93 of 94 clusters see each other) culling wins nothing.
14. **Deploy to a test install.** With that game closed: `python deploy.py` with `MHRTX_GAME` set to the test
    install (it copies the addon and hard-links the textures on the same volume, removes a development
    junction first, and removes files the build no longer has); or junctions into the worktree for live
    iteration; or, on the PoC, a native-loader content package (step 17) through `tools\poc_session.py`.
15. **Tour, compare, decide.** `python tour.py <map> <label>` shoots every camera (HUD hidden, the light
    manager following the held camera) to `work/shots/<map>/<label>/` with a contact sheet. Fix what looks
    wrong, rebuild, shoot again. `python compare.py <after> [before]` builds the gallery and stacked
    "Stock GMod RTX" / remaster pairs for the docs. A change to a standard needs an A/B with a noise floor
    and the user's decision (`references/testing.md`).
16. **Performance and loading.** `python perf.py <map> <label>` holds each camera and prints median and
    99th-percentile frame times (rtx_agent) with the lights on; measure stock (`stock.py on`) in the same
    session; frame generation off for the measurement; a quiet machine. `python abtest.py <camera>
    [variant ...]` switches one cost off at a time. A launch with the load timeline (`restart.py`, only
    where you may restart) prints where the load time goes.
17. **Docs and package.** Write `docs/<MAP>_RTX.md` in the fork (what changes, performance table, loading,
    before/after, install, console commands, layout, rebuild table) with `docs/<map>_rtx/{gallery,compare}`.
    Package only when the user asks, as a native-loader content package from this repository, named after
    the map only (no author or version tag):
    `python -I tools\package_content.py --id <map>-rtx --name "<Map> RTX" --requires-remix --addon <addon
    folder> --mod <mod folder> --title ... --type effects --tag scenic --gma out\packages\<map>-rtx.gma --link`,
    checked with `nlctl manifest` and the workshop-content-pack skill's `check_pack.py`. A hidden Workshop
    test item only on the user's request, never public, by that skill's procedure; players get it only by
    subscribing (loader 0.14.0, ADR 0111). A mod over about 4 GB (one item's limit) is split by map into
    parts that each fit with that skill's `fit_map_mod.py` (top mips left out, no re-encoding; the
    Backrooms' 14 GB went out as two hidden items of 3.85 GB, 3836505482 and 3836505733, "A remaster
    larger than one item").

## Standards and decisions (with the numbers)

Decided or confirmed by the user:

- **Nothing the path tracer needs is culled** (2026-10-27, Backrooms fixed 2026-10-28: "the culling is too
  aggressive and when entered a room, the room next to it are hidden"). Modern House: all 381 networked
  props sent from every room, the whole map drawn, all 341 lights on: median 16.6 ms against 17.1 ms with
  the old culling, within the ±2 ms run-to-run noise. Backrooms: PAS instead of PVS, 13.2 ms against 13.6 ms. The user confirmed both
  fixed with no performance change. Culling stays opt-in for slow machines (`mhrtx_cull_pvs`,
  `mhrtx_cull_lights`, `brrtx_vis pvs|all`).
- **Water is calm and uniform** (2026-10-26, gm_poolrooms: "Remove the current animated ripples, make the
  water looks uniform"); waves and interaction come from the RTX Water addon, and caustics show only while
  it has waves on.
- **One package per map, not in the RTX package** (ADR 0023): players of other maps should not download
  3.3 GB. Modern House is the hidden item 3829275998; its source stays local.
- **No add-on forces `r_forcehwlight 1`** (R3-016, 2026-10-29; the user confirmed the fix in game).
- No size limit on a remaster's resources (said in all four requests); performance still counts.
- **Low-resolution textures may be replaced, not only upscaled** (lestnicha3, 2026-11-08: "You don't have to
  stick on the textures on the original map ... you could upscale or replace them", free resources
  allowed): CC0 photoscans for the grass, the meadow ground and the concrete's grain. The map's layout
  (joints, stains, per-paver tones) stays.

Set by the sessions and not contested (chosen by eye on tour sheets, not A/B-measured; re-measure before
calling them standards for a new map):

- **Texture sizes:** world textures 4096 when they cover at least 0.15 % of the world area (Modern House;
  0.4 % on Backrooms) or the source is already 2048, otherwise 2048; prop textures 4x, between 512 and 2048.
  Every texture through the DAT upscaler (Modern House); Backrooms used SPAN, about 40x faster, for props with
  fewer than 12 instances.
- **Height maps** only on world textures of floor and wall classes, never on model UV islands (parallax shows
  their seams); `displace_in` 0.0006-0.008 per class (the depth as a fraction of one texture repeat).
- **Roughness by finish:** matt plaster 0.80-0.95, concrete 0.66-0.93, polished concrete 0.20-0.46, marble
  0.04-0.17, glazed tile 0.12-0.40, satin oak 0.28-0.58, gloss lacquer 0.05-0.22, chrome 0.02-0.10 metal with
  F0 lifted to 0.62, aluminium 0.28-0.52 metallic 0.85 without lift, fabric 0.85-1.0. Full tables:
  `references/pipeline.md`.
- **Lights:** radiance in linear Remix units. Backrooms caps it at 2000 (a stronger source grows its
  radius instead) and compresses light-entity brightness above a knee of 1000 (entities reached 75000).
  Modern House downlights 3400 K, LED lines 3200 K, kitchen 3500 K, baths 3300-3600 K, garage and laundry
  4000 K. Poolrooms openings 5500 K rect lights over a 5000 K emitter (6000 K read cyan, 4800 K beige). A
  distant sun is about 4-5, never 2200.
- **Look:** haze and grade scoped per map: Modern House haze 420 m and purity 1.12, Backrooms 55 m and 1.15,
  poolrooms 10 m. The user's own purity (1.33) comes back on unload.
- **Glass:** thin-walled for brush panes (IOR 1.52, thickness 0.25), or an open volume turns emerald;
  mirrors metallic 1, roughness 0, on a tag texture.
- **DDS:** NVTT `normal` quality; content-named files; `preload_textures 0` (streaming) for GB-size mods,
  1 for the 150 MB poolrooms mod. Since runtime patch 0030 a preload loads whole in the first frame that
  draws it (not at mod load), so a preloaded map mod's cost lands in the map's first frames.
- **Precedence:** an authored map mod always beats the RTX fixes' generated `~gmod_topbr` (runtime patch
  0020); ToPBR's world conversion stays opt-in (`rtx_topbr_enabled 0`).
- **Tints** are left to Remix on DECAL_STATIC textures (verified on lestnicha3, 2026-11-08); a tint above 1
  is baked after the addon removes that texture's DECAL_STATIC category. Modern House's baked tints predate
  this finding.
- **Outdoor light** (lestnicha3): the sun at the mapper's angle, radiance 4.5 at 5200 K; clouds 0.30 with
  voxel shadows at 0.55; haze sun 0.2 with volumetric scale 10; froxels to 45 m; night lights as shaped
  spheres (gallery 4300 K/85, uplights 2900-3000 K/1200-1400) faded in below 3 degrees of sun elevation.
  The remaster cost 1.7 ms over stock by day at 4K (12.4 against 10.7 ms).

## Commands

| Command (from `source/<map>_rtx/tools`) | What it does |
| --- | --- |
| `python extract_map.py [gma]` | unpack the Workshop map into `map_extract/` |
| `python inventory.py [--top N]` | `work/inventory.json` |
| `python contact_sheet.py [--all]` | base-texture sheets for review |
| `python tex_jobs.py` | predicted hashes, sources, AI job list (merges `live_hashes.json`) |
| `python live_hashes.py` | live hashes from the running game |
| `<rpai python> ai_tex.py ..\work\jobs_ai.json [--only ...]` | upscale, normal, roughness, height |
| `python compose.py [--only ...] [--force]` | PBR maps per recipe |
| `python plant_atlas.py [--cc0 DIR] [--preview]` | lestnicha3: CC0 photoscanned plants and a drawn dandelion clock into the grass atlas (after `compose.py`) |
| `python gen_skirts.py [--min A] [--max B] [--debug x y r]` | lestnicha3: fillets for the open lip edges of a model floating over the floor, into the addon |
| `python build_mod.py [--no-prune]` | DDS, `materials.usda`, atomic `mod.usda` |
| `python gen_lights.py` / `gen_mirrors.py` / `gen_sky.py [--size N]` / `gen_vis.py` | lights, mirror quads and tag, fallback sky, PVS-cover points |
| `python survey.py <label> [count]` / `find_cameras.py <map>` | candidate cameras |
| `python tour.py <map> <label> [camera ...]` | screenshots and contact sheet |
| `python stock.py on\|off` | the running map as stock GMod RTX, and back |
| `python compare.py <after> [before]` | docs gallery and before/after pairs |
| `python perf.py <map> [label] [camera ...]` | frame times per camera |
| `python abtest.py <camera> [variant ...]` | frame time with one cost switched off |
| `python cullcheck.py <label> [room ...] [--views] [--lights] [--ab]` / `vischeck.py <map> <label> [--shots] [--frames]` | what reaches the ray tracer per room |
| `python restart.py [--no-quit] [--map <map>]` | quit, relaunch, load, timeline (only with restart permission) |
| `python deploy.py` | install addon and mod as real files (game closed; set the `*_GAME` variable) |
| `python game.py con <text>` / `lua <code>` / `luafile <file>` / `shot <name>` | drive the running game (console, client Lua, a screenshot) |

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| A surface shows no change | Its hash is not the one the game uploads: another mounted copy of the texture, a different hash mode, an animated frame. Run `live_hashes.py`, then `tex_jobs.py` and `build_mod.py`. Or another mod folder that sorts earlier replaces the same hash (`remix-hashes-and-layers.md`) |
| The whole mod does nothing | A new mod folder: Rescan Mods (Alt+X) or a restart. Or `rtx.enableReplacementMaterials` left False by a stock toggle |
| A colour constant does nothing | The input inherited the game's texture: author `diffuse_texture` empty (`@@`). Or a bound emissive texture overrides the emissive colour |
| Every texel of a material is transparent | `alpha_test_type = 0` means "never"; leave it out |
| Glass turns emerald or deep green | A refracting volume left open by nodraw faces: `thin_walled` |
| Water renders black | Source draws the floor under opaque water only into its refraction target: flag the water materials translucent, or install RTX Water |
| Tiles 16x too large on arches and columns | `$seamless_scale` triplanar mapping, which Remix ignores: unfold the faces offline and redraw them (`unwrap_stretchy.py`) |
| Mirrors missing, or the world vanishes after loading a save | gmRTX deletes `func_reflective_glass`; a save load or clean-up recreated them (fixed in gmRTX `d958da6`) |
| A solid-colour surface (mirror, painted wall, car paint) unchanged though composed | gmRTX's solid-colour fix gave its material its own texture: take the live hashes (`live_hashes.py`, then `tex_jobs.py`, `compose.py`, `build_mod.py`) |
| A store's switched-off lights still glow | the "off" material shares the lit texture: a per-entity tag material from the server (`SetMaterial`) with a dark replacement |
| A slab of terrain floating over an outdoor area; its horizon empty | the 3D skybox room drawn whole at its real place, and Remix cannot draw the skybox pass: PAS visibility, and the skybox at true scale (`gen_skybox.py`) |
| A pole or street light lights nothing | the light sits inside the lamp's closed head: hang it under the head, spot-shaped down |
| Rooms next door missing from reflections, shadows and bounce | PVS culling on the client or the server: `references/pipeline.md`, visibility |
| ~45 ms a frame on a huge map in a fresh session | `r_novis 1` from the RTX `autoexec.cfg` draws the whole map: scope `r_novis 0` too, then move the camera to another room |
| GPU at 35-40 %, three pegged game threads | gmRTX's light updater runs: the addon is missing or not booted (look for its `created` log line) |
| Limbs, clothes and hair in bind pose at the pelvis | `r_forcehwlight 1` (R3-016): never force it |
| Lua mesh invisible to Remix | Drawn in `PostDrawOpaqueRenderables`: draw in `PreDrawTranslucentRenderables` |
| Crash on every map change | A world material changed in the `ShutDown` hook: leave map materials alone at unload |
| A setting never reaches an install | An archived client convar keeps its old saved value: rename the convar |
| Game "hangs" after a crash at "Parsed config file" | The Remix crash-report prompt: let the launch time out; never set `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES` |
| "console message not accepted" | The game is loading, reloading models or has lost its device: wait once, then check it is alive; don't loop |
| A surface near black, its albedo fine in the files | A tint above 1 overflows through the texture factor (debug view 23 shows it): take the texture out of DECAL_STATIC from the addon and bake the tint |
| Tinted surfaces too dark | The tint baked into the albedo and applied again live: don't bake tints on DECAL_STATIC textures |
| The concrete's grain missing | `$detail` is a separate pass gmRTX hides: bake it into the base before the AI stage |
| Black-and-white blobs after the upscale | A strong baked grain: upscale the plain base and add the grain from a scan (`micro` with albedo) |
| A floor blurry at a distance, sharp up close | Texture streaming left it at a low mip: `preload_textures = 1` for a mod under about 1 GB |
| A white ellipse or dark ring at the horizon | The 3D skybox room drawn as geometry under the physical sky: `r_3dsky 0` and hide its props |
| No sunlit haze between buildings | The atmosphere's sun does not light the froxels: a dim haze sun along it, a longer froxel range |
| The addon's sun and times ignored | The companion owns the sky (`nativeloader_sky_follow_map 0`): follow its sun, or set `follow_map 1` for tests |
| `VK_ERROR_DEVICE_LOST` after a material edit | `Material:SetVector` on a world material right after a camera cut: change Remix categories instead |
| A dark navy line along kerbs, copings or planter rims | A model's lip floats over the floor with its inner edge open; the path tracer shadows the slot: close it with fillets from the addon (`gen_skirts.py`) |
| Backlit grass or leaves lavender or white | A grey thin-opaque scattering albedo: give it the foliage's green |
| Every view slower by the same share | Another program on the GPU (`nvidia-smi`), a game or streaming: measure stock and remaster back to back and report ratios; it never blocks the test |

## Done criteria for a map

- Every region of the camera file shot after the last build, with no artifact left unexplained; the user saw
  the gallery and the stock-vs-remaster pairs. An outdoor map also at golden hour, dusk and night, with
  the night lights' cost measured, and under the user's own sky setting (the companion's time passing).
- Hash coverage reported: predictions matched live, textures with live hashes added, textures left to Remix
  and why.
- A frame-time table, stock against remaster in one session, median and slowest region, with the noise.
- Load time from the `map` command, and that the addon's `created` line appears with no Lua errors.
- Unloading the map puts back every Remix option and engine setting it changed; nothing forced that R3-016
  forbids.
- The doc page written in the fork, and the licence status of the derived textures stated.
- A package or Workshop item only if the user asked for one; recorded in this repository's `docs/handover`
  and `CHANGELOG.md` when they ask for that.
