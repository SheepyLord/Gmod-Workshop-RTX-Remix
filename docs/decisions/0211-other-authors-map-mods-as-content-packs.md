# 0211: Other authors' map mods as content packs: re-keyed to the package's hash, fitted to one item

- Status: Accepted 2026-11-13
- Decided by: the user ("there are a few more maps, I had obtained permission from the author to release in the
  workshop. Please also pack them into gma ... Each map should have 1 gma"), for four ModDB mods by
  skurtyyskirts and HamzaPOPO's Map Pack RTX; the user chose to download the two that were not on this PC.
  Claude choosing the re-key, the fit and the names.
- Builds on: [0191](0191-classic-map-mods-ported-as-content-packs.md) (classic map mods as content packs).

## Context

- The mods: Valley View Mall RTX, FunkisRTX, Country Estate V1 RTX and BigCityRTX "Gmod Hashes Update"
  (skurtyyskirts, ModDB), and Map Pack RTX (HamzaPOPO, ModDB, July 2024), whose eight maps are New Pool Day 2
  (already Pool Day RTX), gm_abandoned_mall, The Backrooms (gm_backrooms and gm_backrooms_classic), Alley
  Triste, Old russian sauna (gm_banya), Dark forest, de_gold_dust & de_gold_dust2, Jupiter Underground.
- **Two texture hashes.** The RTX package's classic defaults key replacements by XXH64 of a texture's top mip
  (`rtx.useObsoleteHashOnTextureUpload = True`). Valley View Mall, Funkis and Country Estate were made with
  Remix's default XXH3: by XXH64, none of their 420, 448 and 413 materials matches its map's textures, by XXH3
  303-402 do. BigCity and the map pack are XXH64.
- **Size.** Valley View Mall (8.38 GB), Funkis (8.69 GB), Country Estate (7.95 GB) and BigCity (3.99 GB) are
  over one item; every texture is a BC DDS with a full mip chain.
- **Gaps.** The map pack names roughness and metallic maps for nearly every material and ships none of them
  (the runtime draws the constants; `@@` gives the same, [RESEARCH.md](../RESEARCH.md)).
- **Map items.** Valley View Mall's page links 3417387329, now not public; the map is 3624445216.

## Decision

1. **One package per map item, a Remix mod only**, named after the map with no version tag: Valley View Mall
   RTX, Funkis RTX, Country Estate RTX, BigCity RTX, Abandoned Mall RTX, Alley Triste RTX, Backrooms RTX,
   Old Russian Sauna RTX, Dark Forest RTX, Jupiter Underground RTX, Gold Dust RTX (`<map>_rtx` folders,
   `<map>-rtx` ids). An item with two maps (The Backrooms, de_gold_dust) gets one package, as its mod is one.
2. **Re-key XXH3 mods** (`rekey_mod_hashes.py`): each `mat_<XXH3>` becomes `mat_<XXH64>` of the same texture,
   from the map item and the stock VPKs of GMod, Half-Life 2 and Counter-Strike: Source; materials no source
   explains keep their names (2, 8 and 11).
3. **Fit to one item** (`fit_mod.py`, 3.85 GB): top mips left out, no re-encoding; roughness, metallic and
   height maps at half their albedo first, then textures above 4096, then above 2048 and normal maps, the
   biggest upscales of small game textures first.
4. **Blank what a mod never had** (`port_classic_mods.py --blank-missing`) and leave out files no layer reaches.
   **Tone down parallax the author set everywhere** (`tune_displacement.py`): after the user pointed at Abandoned
   Mall's ground, HamzaPOPO's eight packs keep no displacement on model and decal textures and at most 0.008 on
   world ones (it was 0.05-0.145 on nearly every material); the other authors' packs keep theirs.
5. **Credit and permission in the description**: the map's author, the mod's author and ModDB page, that the
   author gave permission, and whether the textures were fitted or re-keyed.
6. **Checked in the field** like ADR 0191's packs; **not uploaded** until the user asks.

## Consequences

- The three XXH3 mods now apply under the RTX package at all; before the re-key they never did.
- The fitted packs carry lower top mips than the originals: a cut texture is the original's own lower mip.
- Stock textures these mods replace change on every map; between two packs that replace the same one, the
  first by folder name wins.
- The workshop-content-pack skill gained "Another author's map mod (ModDB)", `rekey_mod_hashes.py`,
  `vtf_hash.py`, `fit_mod.py` and their tests.
