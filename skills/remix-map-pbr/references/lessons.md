# Lessons from the seven remasters

Each entry: what you would see, why, what fixed it, and where and when it was found (local dates). PR =
gm_poolrooms (2026-10-26), BR = the Backrooms maps (2026-10-27/28), MH = modern_house (2026-10-27/29),
L3 = lestnicha3, an open-air island under the physical sky (2026-11-08/09), BM = gm_brmovie_complete, the
A24 Backrooms Movie map: a store with its parking lot, office halls, a pit, 1677 light entities
(2026-11-09), AG = gm_csgoagency, CS:GO's Agency: offices on a high floor of a tower in a city, every
albedo re-rendered by OpenAI's image model (2026-11-18/19), OF = cmdr_office_summer, CS:GO's cs_office in
summer: offices, a courtyard and streets, the OpenAI stage planned per texture and run as a batch
(2026-11-20), ST = gm_stelliferous, a space station in orbit with 2189 light entities and its own orbit
skybox (2026-11-20).

## Getting the map

**The gma tools refuse an old Workshop item: "LZMA output exceeds its declared size"** (AG, 2026-11-18)
- An item uploaded years ago (1280291772, 2017) is a legacy `.bin`: one LZMA stream in the "alone" format
  (13-byte header) whose decoder runs past the declared size. Decode it with Python's `lzma`
  (`FORMAT_ALONE`), cut the output at the declared size, check the gma's CRC, then read it as a gma.

**Region anchors from the map's soundscapes** (ST, 2026-11-20)
- The `env_soundscape` origins name a map's regions (on gm_stelliferous: hall, labs, servers, offices,
  bridges, pool, core, outside, hydroponics, maintenance, warehouse; 98 of them) and the teleport
  destinations its arrival points. Dropped to the floor in game, turned to the longest open sightline and
  centred between near walls they gave 29 usable cameras across 12 regions (`anchor_cams.py`). Backing a
  camera up to the wall behind it put half the views against a wall or a wall lamp: back up at most 120
  units and centre it in a corridor.

## Skinned models and engine settings

**R3-016: limbs, clothes and hair in bind pose around the pelvis** (MH, found by the user, fixed 2026-10-29)
- Symptom: on modern_house, new HSR characters, their ragdolls, the player model and the hands were drawn
  with every limb at the pelvis; Model Hotloader's models and models with a `.sw.vtx` looked right.
- Cause: the remaster scoped `r_forcehwlight 1`. The RTX fixes then light every model on the GPU, and with
  `r_forcehwskin 0` Source skins a model without a `.sw.vtx` through its fixed-function hardware path,
  which never sets `D3DRS_VERTEXBLEND`, indexed blending or `WORLDMATRIX(1+)`. Remix reads that as "not
  skinned" and draws the mesh rigid on its first bone. The classic install never had it on: its launch
  option `+r_forcehwlight 1` runs before the variable exists.
- Fix: Modern House no longer sets it (fork `claude/modern-house-rtx` `e96ad7f`; item 3829275998 updated to
  `0.0.0-dev.202610300425+d7efd636`); the user confirmed the models in game. `mat_softwareskin 1` would
  cover it, but it is a cheat variable that Source resets when `sv_cheats` goes back to 0. Rule: no add-on
  forces `r_forcehwlight 1` (this repository's QoL handover, R3 triage, RESEARCH.md section 32).
- Still open: the Backrooms addon (`gm_br_rtx/lua/autorun/br_rtx.lua`, on both its branch and the Modern
  House branch) still scopes `r_forcehwlight 1`, and `docs/GM_BR_RTX.md` and `docs/MODERN_HOUSE_RTX.md` still
  say "models use hardware lighting". Backrooms measured a real cost of turning it off: 34.7 → 62 ms a frame
  in a whole-map state on gm_br_complex (2026-10-27, before the `r_novis` fix). Re-measure in the PAS state
  and let the user decide; until then do not copy that line into a new map.

**`r_forcehwskin 1` draws player and NPC models as flexed faces without bodies** (BR, 2026-10-27)
- gmRTX persists `r_forcehwskin` in GMod's `cl.db` cookie table and applies it at startup; a test left it at
  1 and the row had to be removed. Don't set it.

**Calling gmRTX's model reload mid-game crashes** (BR, 2026-10-27)
- `RTX_ReloadModelsAfterHardwareSkinningSettings()` crashed GMod twice in the MDLCache flush; gmRTX calls it
  only during a load. Don't call it from a test.

**`sv_cheats 0` changes the session** (BR, 2026-10-27)
- It resets every cheat variable gmRTX's `autoexec.cfg` set (`r_novis`, `mat_softwareskin 1`,
  `mat_frame_sync_enable 0`, `mat_fastnobump 1`, `r_unloadlightmaps 1`, ...). A session where it happened is
  not normal GMod RTX; Backrooms' first stock figure (128 ms) and its fast "first session" came from one.

**Archived convars keep their saved value** (MH and BR, 2026-10-27/28)
- An archived client convar is written to `cfg/client.vdf` even at its default, so changing the default never
  reaches an install where it was saved (`mhrtx_pvs` and `brrtx_pvs` defaulted to 1). Rename the convar
  (`mhrtx_cull_pvs`, `brrtx_vis`).

## Visibility and frame time

**Rooms next door vanished from the ray-traced scene** (MH 2026-10-27, BR 2026-10-28; the user's report)
- Symptom: the user, playing with DLSS and frame generation at about 200 fps, found "the culling is too
  aggressive and when entered a room, the room next to it are hidden". Reflections, shadows and bounce from
  neighbouring rooms were missing.
- Cause: the client drew only the engine's PVS (the remaster had turned it back on), lights were switched by
  distance, and the server sent only entities in the player's PVS (a fifth of modern_house; on Backrooms the
  PVS is about 1 % of the map).
- Fix: MH draws everything, keeps all 341 lights on, and adds 31 PVS-cover points to every player's PVS on
  the server (16.6 ms against 17.1 ms, within the noise). BR widens every PVS lookup to the PAS
  (`rtx_patch_vis_pas`, 2-5 % of the map; 13.2 against 13.6 ms) and switches its lights by PAS with no
  distance limit. The user confirmed both, with no performance change.

**Every camera 30-40 % slower, the views without the change too** (L3, 2026-11-09)
- A game was running on the same GPU (`nvidia-smi` listed `League of Legends.exe`). A uniform slowdown
  across unrelated views is outside load, not the change. Check the GPU's process list before timing and,
  when something else runs, compare stock and remaster back to back in one session and report ratios. Other
  programs never block or delay a test (the user, 2026-11-09: they may be streaming or other sessions'
  shared compute): launch anyway and note the skewed timings.

**Nothing to cull on an open map** (L3, 2026-11-08)
- lestnicha3's visibility data lets 93 of its 94 clusters see each other: PVS culling would win nothing,
  and the path tracer needs the whole island anyway. Measure the PVS before writing culling.

**Fresh sessions ran Backrooms at 41-48 ms instead of 13 ms** (BR, 2026-10-27)
- Cause: gmRTX turns the PVS off twice, `autoexec.cfg`'s `r_novis 1` and the `rtx_patch_forcenovis` patch;
  the addon turned off only the patch. The first session was fast only because `sv_cheats 0` had reset
  `r_novis`.
- Fix: scope `r_novis 0` as well. After changing it, the camera must move to another vis cluster before the
  engine recomputes the visible set (46.8 ms with the camera still, 12.8 ms after moving). Ruled out on the
  way: Lua, focus, frame generation, CPU-die affinity, the light updater, opacity micromaps, replacement
  materials, junction against real folders.

**The whole map is CPU-bound on big maps** (BR, 2026-10-27)
- About 46 ms a frame with 5000-9000 model renders: about 40 % Source model rendering, 30 % Remix per-draw
  preparation (12 % one global lock in every `RtxOption` read), 11 % one `ReadProcessMemory` per model render
  in RTXFixesBinary's `R_StudioRenderFinal` hook. Fixed in the hook (`62f4af0`, 46.4 → 44.6 ms) and in the
  runtime (lock-free option reads, build `A8E39D93`, 44.0 → 35.5 ms). Still too slow to draw these maps whole.

**Low GPU use, three game threads pegged, 22 fps on modern_house** (MH, 2026-10-27)
- Cause: the user had moved add-ons out to load faster, `modern_house_rtx` among them; the Remix mod still
  loaded, but gmRTX's light updater drew a helper model at each of 1069 map lights every frame.
- Measured: 45 ms and GPU 35-40 % with the updater, 19.6 ms and GPU 87 % with its three hooks paused.
- Fix: the addon back. Ship and install both halves; check for the addon's `created` line. Low GPU use with
  pegged game threads: suspect the light updater first.

**gmRTX's own map lights doubled the remaster's** (BR, 2026-10-27)
- Light2RTX made 1255 and 2278 always-on API lights on top of the remaster's. Flipping `rtx_lightupdater`
  instead ran Light2RTX over the whole map (seconds of hull traces) and set `rtx.skyBrightness` 0.0424.
- Fix: scope `rtx_api_map_lights_autospawn 0`, clear what Light2RTX made, suspend the updater's three hooks
  while the map runs, and never change the user's archived `rtx_lightupdater`.

**Distance-switched lights saved nothing and darkened far rooms** (MH, 2026-10-27)
- 341 lights on against the 30-300 a distance manager kept: no measurable difference at 4K (an earlier
  3-5 ms estimate did not reproduce); at night the far rooms looked dark from the lawn.
- OF (2026-11-20), a distance limit on top of the PAS (`ofrtx_light_range`): at 1200 units the break room
  went from 117 lights to 24 and gained 0.5 ms, the other slow views 0.0-0.4 ms. The cost is in having API
  lights at all: all of them off saved 2.7-3.2 ms with about 100 on, and a scene with a single API light
  already pays about 1.3 ms at 4K; each further light costs little. The limit stays in the add-on at 0 (off).

**Overlay FPS is four times the engine rate** (MH, 2026-10-27)
- The user's overlay includes DLSS 4x frame generation; divide by 4, or measure engine frames
  (`rtx_agent_frames`).

**Measurements spoiled by other work** (MH, 2026-10-27)
- A concurrent NVTT encode put stock modern_house at 90+ ms (37.2 ms idle) and the first load at 389 s
  (150 s clean). A mod hot reload is followed by seconds of texture streaming (18 fps against 12.7 ms on BR).
  GMod clamps `FrameTime()` at 100 ms (BR's stock runs): count frames by wall clock.

**gmRTX's light updater on a map full of light entities** (ST, 2026-11-20)
- The RTX guard line named it: `RTXReady_RenderLightUpdaters` 38-42 ms of every frame (worst 360 ms) with
  2189 light entities, and most of the station still dark. Stock ran at about 150 ms a frame by wall clock
  (GMod clamps `FrameTime()` at 100 ms, so `rtx_agent` read 100.0 everywhere); the remaster, with the updater
  suspended, its own 2253 API lights and the PAS drawn, at 25 ms (19.6 ms median of 32 cameras by engine
  frames).
- The number of API lights cost little here too: at the core, 645 lights against 129 or 47 timed 32.0, 31.1
  and 31.6 ms (`strtx_light_range`), so no distance limit by default.

**Skybox brushes hide what the PAS leaves out** (ST)
- From an outer catwalk camera a whole wall of the station vanished with `strtx_vis pas`; no face ahead was in
  the camera cluster's PVS. 41 % of the map's brush area is `toolsskybox`: vvis treats those brushes as solid,
  the game draws sky there, but Remix's sky does not occlude, so the whole map drawn shows what the mapper
  hid. The PAS matches the original game and costs a third (the whole map: about 47 ms).

## Loading

**Hang at "Collecting materials for Lua fixers"** (BR, 2026-10-27)
- gmRTX's material collector built every mesh of every static-prop instance (`NikNaks.ModelMaterials` →
  `util.GetModelMeshes`). Fixed in gmRTX Lua (`672ada9`): each model's materials read once from its `.mdl`
  header.

**Fatal "Too many verts for a dynamic vertex buffer (57466>32768)"** (BR, 2026-10-27)
- gm_br_pitfalls' `cden_containerset.mdl` group took Source's software path, which rebuilds it in a
  32768-vertex buffer. Wrong guesses first: PVS on, `r_drawbatchdecals 0`, `r_forcehwlight 1`. Found from a
  crash dump and disassembly; fixed in RTXFixesBinary (groups of 32768 vertices or more drawn on the hardware
  path).

**First-frame freeze from the `.sw.vtx` probe** (BR, 2026-10-27)
- RTXFixesBinary looked for a matching `.sw.vtx` on every GAME search path (about 800) per model. Fixed: a
  miss on the GAME-wide lookup ends the search, and misses are cached per map (442 models on pitfalls,
  `6b4794f`). The "30 s" theory was wrong: 1.4 s per load.

**A debug view built its meshes on every load** (MH, 2026-10-27)
- gmRTX's skybox boundary renderer, off by default, walked every BSP leaf in a coroutine for 60-90 s at 3 ms a
  frame. Fixed in gmRTX (`de3bfbd`): built only when switched on.

**Where the rest of the load goes** (MH, 2026-10-27)
- About 35 s of client Lua start-up for the user's ~250 add-ons, the 136 MB BSP (126 MB lightmaps), and
  gmRTX's two model reloads. Not the map's addon. The remaster cannot change the map file.

**`map` sent while the Workshop was still mounting** (PR, 2026-10-26)
- A first partial line ("Mounted 19 of 765") matched too early; the map then failed or the window stopped
  answering. Wait for the full mount (90 % or the second mount line) and a quiet log.

## Materials and USD

**Opaque materials named like glass made glass** (AG, found by the user, 2026-11-19)
- Symptom: the glass railings' handrails, posts and clamps were clear glass (the user named the hash,
  `62509E09427E88CC`); so were the tower's exterior mullions, an office window's frame and an HL2 door's
  frame, and closed blinds became plain frosted glass.
- Cause: the class rules matched `glass` and `window` in the names (`railingglass`, `unique/window`,
  `doorglassmain`, `glass/blinds_illuminated`). The VMTs say otherwise: opaque `VertexLitGeneric` phong
  metal or a self-illuminated `LightmappedGeneric`, no `$translucent` or `$alphatest`, DXT1 without alpha.
  The models carry no pane at all (`mdlgeo.py`: railing_glass's largest triangle is 49 units^2, a strip of
  the handrail tube; the panes are separate `glass01` brushes).
- Fix: before a texture gets a translucent material, check its VMT (`$translucent`, `$alphatest`, the
  texture's alpha) and, for a model, where its UVs and big flat triangles fall. Pin the false ones before
  the glass rule (metal, painted metal, fabric with its self-illumination as emission).

**Mirror-smooth opaque glass: ripples, then specks** (AG, 2026-11-19)
- Symptom: the tower's opaque exterior windows (the offices drawn in, `facade_glass`) reflected the city
  rippled, and at roughness 0.02-0.03 the far city in them had amber and white specks: the clouds broken up.
- Cause: PBRify's normal of the painted desks behind the glass tilted it up to 4 degrees (99th percentile,
  16 at most); a mirror doubles any tilt. Below about 0.03 the runtime treats a surface as a perfect mirror
  (primary surface replacement), and that path shaded the far, true-scale city in it with specks. Ruled
  out, with measurements: holes (the specks did not match the scene behind the hidden pane), gmRTX's
  DECAL_STATIC flag on world textures (cleared every frame: no change), the alpha (255 everywhere).
- Fix: no normal map where a recipe adds no relief (`compose.py` writes none when all slopes are zero) and
  an even roughness of 0.035; 0.045 and up blur the reflection like frosted glass.

**Frosted bands and wired glass on clear glass** (AG, 2026-11-19)
- A plain thin-walled translucent material loses what the original's alpha drew on its glass: the office
  partitions' two frosted safety bands (alpha 0.70 over 0.32), the wire mesh of wired safety glass.
- Fix: the translucent material's diffuse layer. `use_diffuse_layer = 1` turns `transmittance_texture`
  into a diffuse coat (RGB its colour, alpha its coverage), and `enable_transmission_mask = 1` lets it
  shadow the light through the pane. Redraw the original's alpha as a crisp mask (`glass_layers.py`).

**Texture names with backslashes** (AG, 2026-11-18)
- CS:GO's model materials reach the inventory as `models\agency\...`; the class rules written with slashes
  missed them. Normalise to forward slashes before matching.

**Five textures predicted wrong** (MH, 2026-10-27)
- 106 of 110 predictions matched; HL2's `lights/white*` and two de_elysion metals are uploaded from other
  mounted copies. Fixed with `live_hashes.py` merged by `tex_jobs.py`.

**The mirrors grey, 42 textures unchanged though composed: gmRTX's solid-colour fix** (BM, 2026-11-09)
- Symptom: the store's mirrors (a 16 px grey texture) kept their grey; the blue hotel wall, car paint and
  chrome, the frosted glass and a few signs kept the game's look. `RemixMaterial.GetAllTextureHashes`
  returned hashes no prediction had, and `Material(...):GetTexture("$basetexture")` named
  `rtx_solidcolor_<material>_rt`.
- Cause: gmRTX's `cl_fix_solid_color_materials.lua` (`rtx_fixsolidcolor_enabled 1`) gives every material
  whose base texture is a solid colour its own render target (the colour, two pixels toggled by a hash of
  the material name) so that Remix can tell such materials apart. The hash Remix sees is that target's, one
  per material: every cubemap-patched copy (`maps/<map>/..._x_y_z`) has its own.
- Fix: the live hashes. Draw the whole map (`bmrtx_vis all`), move the *player* through every region (the
  server sends entities by the player's PVS, not the held camera's), run `live_hashes.py`, then `tex_jobs.py`
  (merges them) and `compose.py` (it refreshes the hashes in `composed.json`) and `build_mod.py`.

**Old mods never applied** (the blood mods, 2026-10-27)
- Keyed to the other texture-hash scheme; and where they would have matched, the normal and roughness maps
  were swapped and blood was 97 % metallic. Read the hashes back from the game, and check what each map in a
  mod is, before trusting an existing mod.

**Every texel transparent** (rainbow blood, 2026-10-27)
- `int inputs:alpha_test_type = 0` is "never". Leave it out.

**A colour constant did nothing** (MH, 2026-10-27)
- Mirrors and LED strips kept the game texture: an unauthored `diffuse_texture` inherits it. Author it
  empty (`@@`).

**Glow colours warmer than intended, the whole map's balance off** (PR, 2026-10-26)
- Colour constants are decoded as sRGB, and the linear kelvin colours were passed as if sRGB. Large emitters
  light the room through GI, so their colour sets the white balance as much as the lights. Pass sRGB values;
  a bound emissive texture overrides the colour constant.

**Material tints are applied live: baking them tints twice** (L3, verified 2026-11-08; MH bakes them)
- gmRTX's fixed-function shaders pass a material's `$color`/`$color2` as `D3DRS_TEXTUREFACTOR`. Remix
  applies that factor only to textures in the decal, particle or allowBakedLighting categories, and gmRTX's
  smart-mark puts every world texture and every BSP static-prop material in DECAL_STATIC (0x1000). So the
  tint reaches the replacement albedo live (the albedo debug view, index 23, shows it; index 32 is the raw
  albedo). lestnicha3's pavers (`$color2` 0.51) came out right only with the tint left out of the bake.
- Modern House multiplies tints into its composed albedo (the near-black slatted wood, the 51 % grey gloss
  panels), so on its DECAL_STATIC textures they apply twice. A new map: don't bake tints; compare views 23
  and 32 on a tinted surface first.

**An edging near black** (L3, 2026-11-08)
- `$color2` 1.59 on the arches' and rims' edging overflowed through the texture factor to near black.
- Fix: the addon takes that one texture out of DECAL_STATIC (`RemixMaterial` category remove, then set,
  after gmRTX's smart-mark has run: it marks 5 s after load and again for pending textures, so recheck on a
  timer for a minute), and `compose.py` bakes the brightening (`bake_tint`). Don't edit the material's
  `$color2` live instead: a `Material:SetVector` right after a camera cut lost the device
  (`VK_ERROR_DEVICE_LOST`, 2026-11-08).

**The concrete's grain was gone** (L3, 2026-11-08)
- Source draws `$detail` as a second fixed-function pass, and gmRTX marks the detail texture decal plus
  ignore (0x1008), so Remix shows the bare base. Bake it into the base before the AI stage: mod2x,
  `base * lerp(1, 2 * detail, $detailblendfactor)` in gamma space, the gain normalised to a mean of 1, a
  whole number of repeats on tiling textures (`detail_bake.py`).

**Halftone blobs after the upscale** (L3, 2026-11-08)
- The walkways' pavers had a strong detail grain (`$detailblendfactor` 0.76) over a speckled base; the
  DAT upscaler turned the baked grain into black-and-white blobs. Weaker grains (0.56) came out fine.
- Fix: upscale the plain base (`tex_jobs.py` override `detail_bake: false`) and add the grain after the AI
  stage from a CC0 photoscan at full resolution (`compose.py` `micro` with an albedo share). Crop the same
  spot from source, bake, AI output and final before trusting an upscale.

**The walkway floor blurry, joints soft** (L3, 2026-11-08; the user's screenshot)
- Sampler-feedback streaming left the pavers at a tiny mip at a distance. `preload_textures = 1` for this
  0.6 GB mod fixed it; stream only mods of several GB.

**Overlays, detail sprites and the sky missing from the inventory** (L3, 2026-11-08)
- Overlays are not faces: they are BSP lump 45 (`doverlay_t`, 352 bytes, up to 64 faces each). The
  worldspawn's `detailmaterial`, the `skyname` faces and particle materials are not faces either. Add them
  (`inventory.py` reads lump 45 and an `EXTRA_MATERIALS` list).

**"Lump 0 is LZMA compressed"** (L3, 2026-11-08)
- A map repacked with `bspzip -repack` LZMA-compresses each lump (`LZMA`, actual size, packed size, five
  property bytes) and each game lump on its own (flags bit 0, the packed size in its own header). Python's
  `lzma` reads it as FORMAT_ALONE: properties, a 64-bit size, the stream (`bsp.py` `lzma_lump`).

**A dark band on ribbed ledges** (L3, 2026-11-08)
- The concrete class's high-pass on the normal (2 % of the side) flattened board-formed ribs 120-240 px wide
  at 4096; the ledges read smooth and dark. A per-texture override keeps the broad relief.

**Painted grass and a 512 px meadow** (L3, 2026-11-08/09; the user asked for better plants)
- An upscale gives a painted atlas pixels, not blades. Replace the plants with CC0 photoscanned cards at
  the places the model's UVs expect them (`plant_atlas.py`: measure the cards' UV boxes, cut each scan card
  by its alpha component, trim the scan's stretched padding, re-encode its normal, recompute
  transmission). Replace a low-resolution ground with a CC0 ground scan, divided by the material's live
  tint so the result matches (`compose.py` `scan` with `tint_compensate`).

**A dark navy line along every planter and rim** (L3, 2026-11-09; the user's "Gap" screenshot)
- The edging model laid its 17-unit lips 1-1.6 units above the paver floor and left their inner edges
  open. Source's lightmap lit the floor in that slot like the rest; the path tracer shadows it, and seen at
  an angle the slot reads as a uniform navy line. Traces pass through the model (no collision) and hit the
  floor, which is the clue; a cross-section of model and brush faces (`mdlgeo.py`, `bsp.py`) shows it.
- Fix (`gen_skirts.py`): every open boundary edge of the model's upward-facing triangles (welded by
  position) that floats 0.05-4 units over a world floor face, split into the stretches that do; the addon
  draws one mesh of fillets from those edges down into the floor with the model's own material, in
  `PreDrawTranslucentRenderables`. A vertical wall there, in the shade beside a sunlit floor, still read as
  a dark line: 45-degree fillets catch the sky, their foot extended past both ends so corners meet, UVs
  run down the slope (outward plus down cancel on a 45-degree face).

**Backlit grass a lavender carpet** (L3, 2026-11-09)
- A grey `subsurface_single_scattering_albedo` (0.8) made thin-opaque blades scatter white, so backlit
  grass glowed with the sky's colour; on the darker photoscanned blades it read as lavender. Debug views
  23, 32 and 89 were all fine; `rtx.subsurface.enableThinOpaque False` gave green again. Fix: a green
  scattering albedo (0.45, 0.70, 0.12). Test it live by editing `materials.usda` and touching `mod.usda`.

**Dandelion clocks drawn as paper fans** (L3, 2026-11-09; the user's screenshot)
- A white disc with a seed head on the model's crossed cards looked like folded paper with a dark heart.
  Draw the clock as it is built (`plant_atlas.py`): 130 seeds on a Fibonacci sphere, each a beak from a
  small seed head to a parachute of 18 hairs in a shallow cone, the back half darker, lines supersampled
  3x; about 80 % coverage inside after the alpha test, so it stays see-through, and a wispy rim. Draw the
  stem first and the clock over it, a dome normal for the sphere, near-white transmission.

**Grass sheen bluish; dandelions white discs** (L3, 2026-11-08)
- Foliage at roughness 0.4 mirrored the sky: 0.60-0.88. A white blob in the atlas read as a flat disc:
  fibrous seed hairs, a seed head, a dome normal and near-white transmission (`puffs`). Snap alpha-tested
  foliage to 0 and 255 so opacity micromaps classify it.

**White leaf cards on the mall trees, in stock too** (OF, 2026-11-20)
- Symptom: on `mall_tree_medium01` (L4D2's mall tree, in the courtyard), a few leaf cards near the top
  blown out to pure white (255) when seen from below at a slant, beside green ones of the same material;
  from above and looking up into the sun they are green.
- Not the material: rougher leaves (0.88-0.98), no transmission, the API lights near the tree off and a red
  albedo (they turned pink: the texture is ours, the light about ten times a sunlit wall's) all left them
  white. Not the mesh data: one leaf material (`mall_trees_branches02`, alpha-tested, `$nocull`), unit vertex
  normals that face their triangles. Not baked lighting: the runtime ignores vertex colour unless a texture
  is in `rtx.allowBakedLightingTextures`. Stock GMod RTX shows the same cards white.
- So it is how the runtime draws these two-sided cards; the remaster records it as a known issue. Test a
  suspect artifact in stock before spending on it, and keep the diagnostics short: the red albedo and one
  switch per cause settle it in minutes.

**Snow left by the winter map** (OF, 2026-11-20)
- The summer version of cs_office kept three winter textures: `ground/snow01` on a wall's coping and a
  street edge, and de_vostok's snowed-in electrical boxes on a roof seen from the courtyard. List every
  texture named for snow, ice or frost and look where it is drawn (the faces' positions from the BSP, the
  props from `static_props.json`), from the places players stand.
- A world texture that is only snow takes a CC0 scan of what belongs there (`overrides.json`: the class
  and `"scan": {"name": "Concrete025", "repeats": 2}`). On an atlas, `desnow` in `compose.py` finds the
  snow (bright, nearly grey texels, grown a little over their soft edge) and fills it from the bare surface
  around it, in the colour, the normal and the roughness (a push-pull pyramid fill: seamless over holes of
  any size). A smooth fill is enough for a rooftop prop seen from the street; no OpenAI request.

**A mod that sorts early owns shared props on every map** (OF, 2026-11-20)
- 131 of cmdr_office_summer's 295 hashes are also replaced by the user's other remasters (cs_office's
  props, the landscape paintings, the mall trees, carpets and concrete). `cmdr_...` sorts before `gm_...`,
  `funkis_...` and `valley_...`, so its versions show on those maps too (56 hashes on the Backrooms movie
  map, 37 Funkis, 31 Country Estate, 27 Agency, 26 Valley View Mall), and `bigcity_rtx` wins 10 on the
  office map.
- Before installing next to other remasters, compare not only the hashes but what each replaces them
  with: the 27 shared with gm_csgoagency have the same class, maps and inputs (21 share the very OpenAI
  colour), so Agency's map keeps its look. A shared world texture with a map-specific look (Level 0's damp
  carpet, say) needs a tag texture on its own map instead (`remix-hashes-and-layers.md`).
- Asked whether to keep the office's versions or keep them to the office's map with tag textures, the user
  kept them and set the rule for every package: "keep them, the gma must be standalone". Each package
  carries its own map's textures in full; none is left out because another remaster's item has it.

**One texture under two material names** (OF, 2026-11-20)
- `models/props/cs_office/poster_backing` and `models/props_interiors/poster_backing` are the same image,
  one Remix hash. `build_mod.py` wrote both names' maps though the layer keeps only the first material's
  block, so three DDS files (1.7 MB) went into the package and nothing read them. The build now skips a
  material whose hashes an earlier one took, and `pack_mod.py` stops unless every packed texture is named by
  a layer and every name a layer gives is inside the package (Remix's `AperturePBR_*.mdl` shaders aside).
  Agency's package had no such file.

**Clear glass turned emerald** (MH, 2026-10-27)
- Brush panes with nodraw faces leave a refracting volume open, which keeps absorbing over metres. Fix:
  `thin_walled`.

**Black water and a navy canal** (PR, 2026-10-26)
- Source draws geometry strictly under opaque water only into its refraction target (gmRTX also has
  `r_waterdrawrefraction 0`), so Remix had no pool floor. Theories about decals and nodraw were disproved.
  Fix: set the translucent flag (2097152) in the water materials' `$flags` at runtime. The Water shader binds
  `$normalmap`, so the tag goes there. A translucent caustic layer inside the water volume then turned the
  water navy; the overlay became an unordered emissive particle (`blend_type 6`).

**Giant tiles on arches and columns** (PR, 2026-10-26)
- `$seamless_scale` triplanar mapping is ignored by Remix; the faces show tiles 16x too large. Unfold the
  faces offline at the real tile size, redraw them from Lua, hide the originals (NO_DRAW flag).

**Lens emission included the trim ring; rails glowed** (MH, BR, 2026-10-27)
- Self-illuminated lamps: the alpha mask times a brightness threshold. Atlases: `emit_rects` limits emission to
  the lamp's part (slum fixtures).

**Aluminium frames turned silver; marble and paving looked wrong under parallax** (MH, 2026-10-27)
- No F0 lift for anodised aluminium (only chrome); marble without height; the paving's AI height read albedo
  blotches as bumps (noise at grazing angles): height 0, gentle normal.

**Parallax on props showed UV seams** (all)
- Height only on world textures; forced to 0 on model textures.

**Interiors too orange; Level 0 radioactive yellow; a cyan cast** (MH, BR, PR)
- MH: kelvins moved (downlights 3400 K, LEDs 3200 K) and purity 1.12. BR: yellow multiplies itself through
  every bounce in a closed yellow room: wallpaper saturation 0.7 and exposure 0.88, purity 1.15, haze 55 m.
  PR: a neutral tile albedo and 5500 K lights (6000 K too cyan, 4800 K too beige).

**PBRify's normal of a pale texture is flat** (PR plaster, 2026-10-26)
- Use the artist's normal map plus high-pass relief from the upscaled albedo.

**Production DDS took hours** (MH, 2026-10-27)
- Production BC7 for 490 files ran about 3 hours (about 25x the default) for no visible gain. Use `normal`.
  gm_poolrooms' few textures took 5 minutes at production.

**Duplicate DDS per material** (PR, 2026-10-26)
- Name textures by source and content digest so materials share them.

**Classification errors** (BR, MH, 2026-10-27)
- `maps/` (cubemap copies) matched a paper rule; stainless matched a decal rule; doors came out as wood; a
  mirror rule anchored at the name's end never matched because the key includes the texture name. Strip
  cubemap names first, order rules from specific to general, check every class on contact sheets.

**Carpet loops read as cobblestones** (BM, 2026-11-09)
- The movie's loop-pile carpets (2-3 cm loops in the source) at normal 1.3 and parallax 0.0016 became a
  pebbled surface up close and on the intro rooms' carpeted walls. Normal 0.75, height 0.0008, the CC0
  carpet scan's normal at 0.45.

**A chandelier's brass glowed** (BM, 2026-11-09)
- The light class's emission threshold (luminance) caught the brass's highlights in the atlas; only the
  candles should glow. `emit_rects` limits the emission to the candles' part (find it from the
  low-saturation white pixels), and the class is metal for the rest.

**`compose.py` failed with "image has wrong mode"** (BR, 2026-10-27)
- Pillow's Gaussian blur does not take 16-bit images: use scipy's `gaussian_filter` on floats.

**Glow masks and screens** (ST)
- With `$selfillum` the base texture's alpha is the glow mask, not opacity: show such textures' colour with the
  mask beside it on contact sheets, or half the sci-fi set reads as magenta. A wall of light strips
  (`stellif_framelights_02`, a tenth of the station) is the light class (the mask's bright texels emit at 16);
  a hull panel with a lamp strip down its seam takes `emissive` 16 from `overrides.json`; consoles' and panels'
  LEDs emit at 6-8 through `emit_selfillum`; screens with pictures glow as a whole (`backdrop` 2.0) behind a
  glossy face.
- Refract-shader windows (`glass/glasswindow_refract01`, `$normalmap` only) come out of stock GMod RTX as an
  opaque blue sheet; they have one live hash for every window (0x0A101376A899C892), which the clear glass
  material takes as an extra hash.
- `WindowImposter` fake skies (cubemap ceilings over the gardens) are not drawn by Remix; the map's skybox
  shows in their place, which on a station in orbit reads as the view out.

## AI albedo with OpenAI's image model

**Re-rendering each albedo before PBRify** (AG, the user's request, 2026-11-18)
- What worked: the image edit endpoint (`POST /v1/images/edits`, JSON body with the texture as a data URL,
  `gpt-image-2.6-sunburst`, `quality high`) asked for the same image with real surface detail and nothing
  moved, one prompt detail per class (`oai_tex.py`). Every result is scored against its source before it
  is kept: blurred-luminance cross-correlation, edge correlation, the 90th percentile of local shift by
  phase correlation (tiles without a clear peak left out), brightness and contrast; a random surface
  (concrete, plaster, carpet, fabric) is judged on brightness and contrast only, since its detail is drawn
  anew. 182 textures sent, 144 kept; 38 refused (parts moved 20, layout changed 17, brightness 1) keep the
  DAT upscale. Tiling textures are generated with a margin of their own wrapped edges, and the step across
  each wrapped edge is spread over a band; check them as 2x2 sheets. About 24 US dollars in all at the
  published per-token prices (input 8, output 30 per million tokens).
- The endpoint's limits: both sides multiples of 16, the longest at most 3840 (4096x4096 is refused even
  where a model is said to make 4K), at most 8,294,400 pixels, an aspect within 3:1 (a 2048x672 strip was
  refused after rounding: round the short side up, pad a thin strip with its own edge to 3:1 and crop it
  back). The square maximum is 2880; larger targets are scaled up after.
- The key: read from the environment only, never written into a tracked file, a log or a memory; delete
  its copy when the work ends.
- Calibrate the normal strength per class against the artist's own bump maps (the xy spread of the
  composed normal next to the bump's): CS:GO's plaster and cast concrete are nearly flat, and the first
  recipes read as stucco.

**Spending the usage where it shows** (OF = cmdr_office_summer, CS:GO's cs_office in summer; the user's
request "avoid wasting usage", 2026-11-20)
- The cost is nearly all output tokens, and they grow with the output's size, not linearly: quality high,
  2.6 Sunburst, about 3570 tokens for a 2048 px result and 4930 for a 2560 px tiling canvas, 1540-1760 for
  816-1024 px. Price per million: 8 in, 30 out; in a batch 4 and 15.
- `oai_tex.py --plan` decides per texture before anything is sent: reuse what another remaster already
  kept (same Remix hash: 21 of cs_office's textures came free from gm_csgoagency's), skip what the model
  cannot improve or what nobody sees (lights, decals, sky, signs, artwork and lettering, the 3D skybox's far
  facades, flat or animated textures, surfaces under 0.02 % of the map, small props), skip patterned world
  textures that are not heroes, send the rest: heroes at full size, the rest at half size, which DAT then
  doubles. Agency sent 182 and paid for a second tiling pass; cs_office's plan sent 146 in one pass (the
  wrapped margin from the start), about $5.60 estimated in a batch.
- The Batch API takes `/v1/images/edits` (the request body as in a synchronous call, the source as a PNG
  data URL in a JSONL line) at half the price. The guide names only the 2.5 models; a one-request test batch
  showed 2.6 Sunburst works too (validated, completed). Keep a batch's input file under the 200 MB limit
  (`BATCH_FILE_BYTES`, 150 MB; 142 requests were 108 MB). A batch takes its time: the single-request test
  finished in 14 minutes, the 142-request batch in 55 (138 done after about 37, the last four held it
  to the end); build, tour and measure with the local upscales meanwhile and swap the colour in after.
- The result on cs_office: 146 answers, 134 kept (92 %; Agency kept 79 %), 21 more reused free, $7.88 in all
  with the pilots (176,640 tokens in, 428,883 out), against about $24 for Agency's 144: about 65 % less per
  kept texture. The 12 refused: two of the nine brick walls (layout changed), a steel beam texture and nine
  prop atlases (parts moved); they keep the local upscale. A plan that skips non-tiling textures OpenAI will re-render also halves the
  local DAT stage (their colour comes from OpenAI and the maps are made from it).
- A small synchronous pilot settles model and quality before the batch (about $1.50 on cs_office): 2.5
  Sunburst exaggerates contrast (asphalt aggregate turned into bright pebbles; contrast 1.8 against 1.0);
  2.5 at medium costs a quarter of high's tokens and looks the same as 2.5 high; 2.6 at medium saves only
  17 % and is visibly softer. 2.5 refuses the `complexity` parameter (no charge). Chosen: 2.6 Sunburst, high,
  in a batch. Move the pilot answers you keep into the run's folder so the batch skips them.
- Patterned walls can pass: both of cs_office's cinder block and brick heroes kept their layout in the pilot,
  where Agency's tile grids failed. Pilot the heroes of a pattern class rather than skip the class.
- A kill pattern for one script can match another: `ai_tex.py` is a substring of `oai_tex.py`, and stopping
  the AI stage stopped the batch poller too (restarted; the batch at OpenAI was unaffected).

**A larger map for less** (ST, 2026-11-20)
- The plan over 384 textures with jobs: reuse 20 (18 from cmdr_office_summer, 2 from gm_csgoagency; `--reuse`
  now takes several work folders, the first that kept a texture wins), skip 222, send 136 (57 full, 79 half).
  A five-hero synchronous pilot ($0.82) checked that sci-fi hull panels keep their layout, then 131 requests in
  one submission (two input files, 150 and 11 MB: the first finished in about 25 minutes, the second waited
  about 30 before it started). 136 answers, 114 accepted by the scorer and 4 by eye, 18 refused; $6.11 in all
  (157,988 tokens in, 337,780 out), about $0.05 per kept texture.
- The scorer refuses a near-flat dark panel whose rivets stayed in place (luminance correlation 0.75-0.81:
  too little structure); look at such refusals before re-sending. Foliage atlases did badly here (5 of 7
  refused), while the office's mall trees were reused.
- `oai_tex.py --prepare` blends a tiling answer's edges with the local DAT upscale read from `work/ai_dat`:
  copy those there before the `jobs_oai.json` run rewrites `work/ai`.

## Lights and sky

**Fixture colours from the mapper's light entities** (AG, 2026-11-19)
- Symptom: offices and toilets peach; the walls white in the map are salmon under the remaster.
- Cause: the inherited downlights at 3000 K. Agency's 321 light entities are all a cool white
  (`_light` 227 238 238).
- Fix: read the light entities' colours before choosing kelvins: troffers, panels and strips 4500 K,
  downlights 4000 K, warm only for sconces (3000 K) and lamps (2900 K).

**Light calibration 10x too dim; entity brightness up to 75000** (BR, 2026-10-27)
- Calibrate from flux, compress above a knee (1000), cap radiance (2000, growing the radius instead).

**Switched-off strip lights still glowing** (BM, 2026-11-09)
- The store's hanging strip lights swap to "off" models when its breaker or the flicker switches them,
  and both use one texture: `light_shop2_off` is `light_shop2` without `$selfillum`. A glowing replacement
  for the texture made the off models glow. Fix: the server sets an add-on material on the off models
  (`Entity:SetMaterial`, networked); its tag texture (the same pixels as BGRA8888) has its own hash and a
  dark replacement (`overrides.json` "from" the lit material, emission off).

**Following the map's light switches** (BM, 2026-11-09)
- Named light entities stay on the server, and `CLight::TurnOff` sets the "start off" spawn flag, `TurnOn`
  clears it: the server reads `HasSpawnFlags(1)` per name (an `AcceptInput` hook for TurnOn/TurnOff/Toggle,
  and a 1 s poll), networks one `SetGlobal2Bool` per group and bumps a version int; the client switches the
  group's API lights when the version changes (the flicker shows). Generated lights record their group
  from the targetname of the fixture's prop or brush or of the light entity they took their colour from.

**Pole lights lit nothing** (BM, 2026-11-09)
- A sphere light inside a closed lamp head is shadowed by the housing: hang it just under the head, spot
  shaped downwards. The emitting area must come from the radius actually used (a lamp post's bounding
  radius of 180 units, clamped to 8 for the light, still set its radiance: 0.3 instead of about 400). A
  parking-lot pole 10 m up needs street-light flux (15 troffers), not 3.

**Batched troffer models gave no panels** (BR, 2026-10-27)
- Prop-combined lamp models cannot be split by vertex proximity; split them by VTX triangle connectivity.

**Spots pointed the wrong way; uplights missing** (MH, PR)
- A light entity's `pitch` is an elevation (-90 points down), the opposite of a camera pitch. The garden
  uplights were `light_inset` props set into the ground pointing up: a separate "uplight" kind.

**The sun blew the scene out** (MH, 2026-10-27)
- Radiance 2200 on a distant light; a distant light's radiance is what a white surface facing it shows (about
  4-5).

**The physical sky gave no sun shadows** (MH, 2026-10-27)
- Its default clouds (coverage 0.85 with voxel shadows) hid the sun. Coverage 0.27, `cloudShadowStrength 0`,
  `cloudVoxelShadowsEnable False`. Don't add a second sun: the atmosphere makes its own.

**A region box boosted the wrong room** (BR, 2026-10-27)
- The cistern's box also covered the grey rooms' point lights. Check region boxes in game with traces.

**Hall panels read grey** (PR, 2026-10-26)
- Smaller and brighter: 64 x 160 units, radiance and emission 18.

**A white ellipse and a dark ring on the horizon** (L3, 2026-11-08)
- The 3D skybox room (`sky_camera`) is drawn at its real position, and under the physical sky Remix shows
  its props as geometry. Scope `r_3dsky 0`, and on the server hide the room's props (`SetNoDraw`) at
  `InitPostEntity` and `PostCleanupMap`: gmRTX's `r_novis 1` still draws them.

**Flat cards of fake light shafts** (L3, 2026-11-08)
- A `vol_lightmask` model painted shafts into the air. Hide its texture hash; the volumetrics make real ones.

**No sunlit haze** (L3, 2026-11-08)
- The physical sky's sun does not light the froxel volumetrics. A dim distant light along the sun's direction
  does (radiance 0.2, `volumetricRadianceScale` 10). Raise `rtx.volumetrics.froxelMaxDistanceMeters` from 20
  to what the space needs (45 m on the island), with `froxelGridResolutionScale` 4.

**Night lights too costly as rects** (L3, 2026-11-08)
- 17 rect lights under a gallery ceiling cost 7-11 ms at night; 8 shaped spheres (a cone of 72 degrees, hung
  under the ceiling) gave the look for about 4 ms. Fade night lights by the sun's elevation (on below 3
  degrees, full at -6) and recreate them only when the level changes by more than 2 %.

**The addon's sky ignored** (L3, 2026-11-08)
- With the native loader's `nativeloader_sky_follow_map 0` (time passing, its own weather: the user's field
  setting) the companion owns sun, clouds and fog. Answer `NativeLoaderSkyOwner` only when it follows the
  map; otherwise read its sun (wrap `RemixConfig.SetConfigVariable` for `rtx.atmosphere.sunElevation` and
  `sunRotation` while the map is loaded) and fade the night lights and haze by it. Tests that need the
  addon's own sky set `follow_map 1` before the map loads and put it back.

**A slab of terrain floating over the parking lot; the horizon empty** (BM, 2026-11-09)
- gmRTX's whole-map drawing (`r_novis 1`) draws the 3D skybox room as world geometry at its real place,
  2000 units over the lot. Visibility by the PAS removes it (the room is in no PAS of the playable map).
- The map turns its 3D skybox on at spawn, but Remix cannot draw Source's second camera pass (`r_3dsky 0`),
  so the lot lost its hills, mountains and town. `gen_skybox.py` puts the room's contents where they
  appear: world = 16 x (skybox point - sky camera); props at their `modelscale` x 16 (skybox props carry
  0.0625, so they become life size); displacements decoded from the dispinfo (176-byte records) and
  dispvert (5 floats) lumps, the base quad starting at the corner nearest the start position. The room also
  models the playable area in low detail (its pavement 1 unit over the real lot): leave out everything
  over the real outdoor footprint, and draw the rest only while the camera is outdoors, where the levels
  that share those coordinates are not drawn. Props baked into one static mesh per material
  (`util.GetModelMeshes`) keep it to a few dozen draws.

**A station in orbit under the map's own skybox** (ST, 2026-11-20)
- The companion's physical atmosphere put the station under a blue daytime sky. `rtx.skyMode 0` draws the map's
  skybox (black space, the planet's limb and clouds below); the add-on adds the sun as an API distant light
  from the mapper's `light_environment` (8 degrees over the limb: long, hard light through the halls).
- The game draws the HDR skybox at `mat_hdr_level 2` (BGRA8888 with the alpha a scale); Remix shows its raw
  RGB, far bluer than the map looks (blue 204 against 132 on average). The mod gives the six faces the LDR
  faces upscaled four times, under both hashes.
- The add-on owns the sky only if "Follow the map's sun" (`nativeloader_sky_follow_map 1`) was set when the
  map started: set during the session the companion keeps the sky until the next map start (ADR 0105), so a
  test sets it and runs `changelevel`. Unticked (the user's own setting) the companion's sky and sun stay, and
  the add-on drops its API sun.
- `rtx.atmosphere.altitude` is refused by `RemixConfig` since the review of 2026-11-16.

## Mirrors, sprites and map clean-up

**Mirrors missing** (MH, 2026-10-27)
- gmRTX deletes `func_reflective_glass` at map start. Redraw the quads from Lua with a tag texture. The
  mirrors' texture was also the cooktop's, so the tag keeps the cooktop black glass.

**Loading a save broke the frame** (MH, 2026-10-27)
- A same-map `gm_load` (and the spawn menu's clean-up) runs `game.CleanUpMap()`, which recreated the eight
  `func_reflective_glass`; their planar reflection pass took the walls and floors out of the Remix frame and
  cost about 30 % fps. A camera cut in that state hung the GPU (display driver reset, `VK_ERROR_DEVICE_LOST`).
- Fix in gmRTX (`d958da6` on the fork's `main`): remove the class whenever it is created. Any entity your
  addon removes or hides must be handled at `PostCleanupMap` and on creation too.

**Lua meshes invisible to Remix** (PR, 2026-10-26)
- Drawn in `PostDrawOpaqueRenderables`, whatever the settings; `PreDrawTranslucentRenderables` draws reach
  Remix.

**Crash on every map change** (PR, 2026-10-26)
- The addon changed a world material in the `ShutDown` hook; GMod ran the queued change after the material
  was freed. Leave map materials alone at unload.

**Remix API mesh and material calls crashed** (RTX Water, 2026-10-26)
- `CreateMesh`, `DestroyMesh`, `CreateMaterial`, `DestroyMaterial` from Lua race GMod's render thread; use
  `CreateMeshBatched` and persistent instances, or ordinary GMod meshes with tag textures.

**Sprites a map's logic drives** (ST)
- Of 378 glow sprites, only the secret sequence's (`secret_*`, shown by a `logic_relay`) are switched; the
  laser coils' 160 red glows, the solar array's and the doors' are static. The add-on removes all but
  `secret_*`, the ten `point_spotlight` beams and the three `env_projectedtexture` lamps (Remix cannot draw
  them; spot lights in their place from their FOV and colour).

## Driving the game

**Tours and frame times without the props the server never sent** (OF, 2026-11-20)
- Symptom: a room's computers, chairs and bins in one tour and gone in the next; the remaster's frame times
  a little better than they should be.
- Cause: `tour.py` and `perf.py` held the camera (`RTXAgent.View`) while the player stayed in the spawn room.
  The server sends entities (physics props) by the player's vis area, here its PAS, so rooms far from the
  player had no props; stock mode transmits the whole map (its novis), so a stock-against-remaster pair
  compared different scenes.
- Fix: `game.place_player(pos)` moves the noclipping player to each camera (server Lua) before the view is
  held; tours and frame-time runs made before it (gm_csgoagency's, whose props are mostly static) are worth
  checking against a placed run.

**Stock shots that kept the remaster's materials** (AG, 2026-11-19)
- Symptom: none in the pictures; the console said `SetConfigVariable: 'rtx.enableReplacementMaterials'
  refused (Lua may not set this option)`.
- Cause: since 2026-11-16 the RTX package's `RemixConfig` allowlist refuses that option from Lua, so
  `stock.py` switched the lights and settings to stock and left every material replacement on. The first
  stock tour and stock frame times measured a half-stock map.
- Fix: stock mode rewrites the mod's `mod.usda` without its sublayers (the runtime reloads it when its
  timestamp changes) and puts it back after. After any `RemixConfig` call, read the console for "refused".

**A script could have killed another session's game** (PR, 2026-10-26)
- `game.py` and `restart.py` matched any `gmod.exe`; a peer ran a vanilla GMod beside it. They now check the
  executable path of the configured install. Never stop a game you did not start.

**Settings not readable** (PR, 2026-10-26)
- `RemixConfig.GetConfigVariable` returns the `rtx.conf` value, not the live one; the addons re-apply their
  options three times in the first minute and restore from `rtx.conf` or their defaults. For an option
  `rtx.conf` does not set it returns an empty string: a test that switches such an option off must put
  back the known default itself (L3 left `rtx.subsurface.enableThinOpaque` off once, 2026-11-09).

**Lua autorefresh** (PR, 2026-10-26)
- Editing an installed addon's file re-runs it (repeated `created` lines); hook closures can keep the old
  code. Reload with `include` and restart the addon. New Lua files are not on the cached Lua path until a
  restart (blood, 2026-10-27).

**`IsValid(game.GetWorld())` is false on the client** (PR, 2026-10-26)
- Test the world entity directly.

**HUD in the shots** (MH, 2026-10-27)
- The toolgun's panel ignores `cl_drawhud`: switch to `weapon_physgun` for tours.

**`VK_ERROR_DEVICE_LOST` with the AI stage running** (BM, 2026-11-09)
- The game lost its device at a sky change while `ai_tex.py` ran on the same GPU (as on Backrooms). Keep
  the game closed during the AI stage and the DDS encodes (NVTT also uses the GPU, and starves the AI
  stage); the user also wants idle games closed. Pause the AI stage by stopping its process (a finished job
  keeps its `done.json`; the rest resume) when a game session is needed.

**One map over 4 GB: keep what shows** (BM, 2026-11-09)
- The user asked for one package under 4 GB; the mod was 8.7 GB (2,349 DDS). Every DDS holds its own mips,
  so leaving out top levels costs nothing but resolution: packed files decode to the source's own mip
  (mean difference 0-3 of 255 against a box downscale).
- `fit_map_mod.py` (workshop-content-pack) reached 3.92 GB by cutting all 29 world textures above 2048 to
  2048, the halls' wallpaper, carpet and ceilings included; with those kept it had to halve all 566 prop
  normal maps. It ranks props by placements, so a door knob placed 28 times outranks a bed placed once.
- The fork's `pack_mod.py` instead keeps the 22 surfaces covering at least 0.2 % of the map (and pictures
  whose own source is 2048 or more) at 4096, other world textures at 2048 or 1024 by share, and sizes props
  by texel density over their model's bounding box from the `.mdl` header (6.25 texels per unit fitted),
  never below the game's own texture; roughness, metallic, height, emission and subsurface one size below
  their albedo. Flat maps kept as tails would have freed only 23 MB at those sizes.
- Name the packed mod apart from the full build (`gm_brmovie_complete_rtx_pack`): a package takes over the
  files at its paths, so under the full build's name it would replace the user's hand-placed 8.7 GB build
  with the cut one. `nlctl apply` into a scratch game holding both: the mod added, the identical add-on
  adopted, the full build untouched; `uninstall` left the full build and the add-on. An add-on file a later
  version of the package replaced is the package's from then on and leaves with it (`deploy.py` puts it back).
- In the game (PoC, 4K, the package deployed by the loader, the full build moved out of `rtx-remix\mods`):
  against the full build's views of an earlier session, a median difference of 1.77 of 255 and 97.6 % of
  the fine detail; two package sessions against each other 1.25 and 100.5 %, but up to 7 % apart on one
  view. Texture streaming in a freshly loaded map moves single views that much: compare sessions of the
  same age, or shoot each view after the map has been up a while.

**A map that switches `r_3dsky` on** (BM, 2026-11-10)
- Symptom: at the map's load the RTX fixes showed "You have enabled r_3dsky which may cause rendering
  issues..." (`cl_rtx_settings.lua`, a change callback on `r_3dsky`, unless `rtx_show_3dsky_warning 0`); the
  add-on's scoped settings logged `r_3dsky 1 -> 0` and put the 1 back when the map unloaded.
- Cause: a `lua_run` named `lua_skyboxon` (`RunConsoleCommand('r_3dsky', '1')`) with spawn flag 1, which
  GMod's `lua_run` runs in `Initialize`, as it spawns, before any input; a `logic_auto` and a button fire
  it again. An `AcceptInput` hook cannot stop the spawn-time run.
- Fix: the add-on's server replaces the entity's code before it spawns, in `EntityKeyValue` (it runs before
  the entity's own `KeyValue`): `r_3dsky` stays 0, no dialog. Look for `r_3dsky`, `mat_` and `r_` commands in
  a map's `lua_run`, `point_clientcommand` and `point_servercommand` entities when extracting it.

**The console stops answering** (BR, MH)
- During a map load, gmRTX's model reloads, Light2RTX processing or a lost device. Wait once; if the device is
  lost, the game must be closed (with permission). Running the AI batch beside the game caused one
  `VK_ERROR_DEVICE_LOST`.

**Another session needs the PoC** (L3, 2026-11-08)
- Sessions share the PoC through a lock file (`out\r10\poc.lock` in this repository's main checkout, owner
  and start time inside). When a peer asks, hand it over at a natural pause, quit your game with the
  field's config put back, and wait for the lock to come back; AI and DDS work can go on meanwhile.

**Script text corrupted by the shell** (all)
- Heredocs turned `\b` in a regex into a backspace and `\n` in a Lua string into a newline (an autorun syntax
  error, a NUL byte). Write scripts and patches with the file-writing tool, not inline shell text.

**The engine's screenshot ends the session** (ST, 2026-11-20)
- Symptom: in five stock sessions launched in the foreground, the first `jpeg` ended the game within seconds:
  "CMatRenderContext::PopRenderTargetAndViewport: about to underflow!", the screenshot written, then an access
  violation in `vphysics.dll` (+0xab7a0, under server.dll's physics frame) or the Engine Error "CUtlStack::
  EnsureCapacity ran out of memory!". The console had "PushMatrix underflow?" and "CMatRenderContextBase::
  PopMatrix: Underflow!" about 15 times a second from the map's first frames (the office and Agency sessions:
  none in hundreds of shots).
- Not gmRTX's light updater (removed: the crash stayed), not physics (`phys_timescale 0`: stayed), not the
  water's reflection (already off). A stock session whose runner was started hidden (PowerShell
  `Start-Process -WindowStyle Hidden`) had no underflow at all, and with the remaster's add-on a foreground
  session had none and took two engine screenshots: which of its start-up changes avoids it was not narrowed.
- The tools capture the window (`PrintWindow` with `PW_RENDERFULLCONTENT`; make the process DPI-aware first, or
  the capture is the window's top-left quarter at 200 % scaling). `STRTX_CAPTURE=jpeg` brings the command back.

## Packaging and licensing

**A mod that fits ships whole** (AG, 2026-11-19)
- `pack_mod.py` applied its size caps (1024 for the long tail of world surfaces, props by density) even when
  the whole mod fit. It now keeps every texture whole when the full mod is under the budget (gm_csgoagency:
  about 2.1 GB of 3.96).

**`nlctl` refuses a hard-linked package folder** (MH package, 2026-10-29)
- `package_content.py --link` stages hard links to avoid copying 3.3 GB; the linked build is checked as the
  packed archive instead. The build took 9 s: 500 files, 3,322,961,921 bytes; `gmpublish create` uploaded it
  in 50 s as a hidden item; Steam installed it byte-identical.

**Derived textures and where they went** (2026-10-29)
- Modern House's textures derive from another author's map: its branch stays local and its item hidden (the
  user chose "Keep it local"). Check the same before shipping any remaster; poolrooms' upscaled plaster and
  ladder textures are committed on the pushed fork branch and in the RTX package, which this rule would
  question (ask the user).

**A remaster leaks into other maps** (MH, BR, 2026-10-27)
- Hash replacements are global. Backrooms replaced 209 base-game textures, so they look Backrooms-tuned on
  every map; on modern_house five textures kept other mods' versions because those folders sort first.
  Decide per texture (tag, leave to Remix, or accept) and tell the user.
