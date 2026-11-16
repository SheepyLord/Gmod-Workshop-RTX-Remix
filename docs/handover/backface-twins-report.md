# Imported characters' back-face copies: report (2026-11-16)

The user's report of 2026-11-16: "In the active gmod session, the ragdoll from the imported models, with this as an
example, has a black region on her back skirt, hypothesis is due to clipping, investigate the cause and decide whether a
general fix can be applied to the imported characters." Done by Claude on the branch `backface-twins` (worktree
`out\worktrees\twins`, from `main` at `b77e3191`): a change to the Model Hotloader's natives
([ADR 0228](../decisions/0228-back-face-copies-deform-with-the-layer-facing-outside.md)); no loader (`winmm.dll`),
runtime or Lua change. Facts in [RESEARCH.md](../RESEARCH.md) ("Back-face copies of imported characters").

## What the session showed

The field game (modern_house, single-player) had a Fu Xua ragdoll (Model Hotloader asset `19c0edc5...`) lying on the
floor with a sharp-edged black patch on the purple and gold hem of her skirt. Everything was read from the running game
without changing its settings: server Lua through the console, client Lua through a net message (`sv_allowcslua` stayed
0), the camera moved by a temporary `CalcView` hook, parts hidden in the native renderer only, Remix debug views set
through `RemixConfig`; each was put back, the user's view restored, and the probe's files removed from `data/`.

- The skirt does pass through the floor (to 16 units below it), as the hypothesis said, but that is not what turns it
  black.
- Remix's debug views: the patch has the hem's albedo and roughness, no direct light and almost no bounce light, on a
  fan of four triangles. Hiding the hem's copy `裙下擺+` alone (nothing else) removed the patch.

## Cause

MMD clothing is often two layers on the same triangles: the cloth, and a back-face copy with the opposite winding for
the view from inside. The hem and its copy coincide at rest, but **one vertex of the copy (v177473) is skinned to the
skirt's physics chains** `裙_5_8`/`裙_5_9` while its twin on the hem (v177194) is skinned to the lower body and the left
leg. When those chains swing away from the leg, that vertex lifts five of the copy's triangles up to 1.5 units outside
the hem. The camera culls their back faces, so they stay invisible; but their front faces look at the hem, so every
shadow and bounce ray from the hem stops on them, in the dark gap between the layers. In raster rendering, and in MMD,
the copy is always culled from outside, so the model's mistake never showed. A ragdoll pressed into the floor bends the
chains hardest; swinging skirts in dances open it too.

## Is it general

Yes. Over the user's library (206 imported characters, read only): 68 have back-face copies (262 pairs of parts), and
24 files (20 distinct characters) have copy vertices that deform otherwise than their twins: 752 vertices with other
skinning and 4,973 differing vertex morph offsets. The Herta (210 vertices, 1,430 morph offsets), Robin (70, 243),
hyacine (38, 686), Rin (18 vertices, and the copy of her skirt alone carries the `妊娠↓` morph: 966 offsets), Lycia
(55), Silver Wolf (44), Sandrone (24), Furina (11), Topaz (7, 11), Firefly, Jingliu and Citlali (morphs only), Fu Xua
(1), and others. Each can shade its cloth black under RTX when a pose or a morph opens it.

## What changed

The Model Hotloader's native model loader (`source/backface-twins.patch` on the source copy, see
[Source.md](../../packages/model-hotloader/source/Source.md)):

- `native/backface_twins.hpp` (new). At load, `weldBackfaceTwins` finds pairs of parts whose triangles lie on the same
  points (1e-4) with the opposite winding. It decides each pair's outside layer by a vote: up to 64 twin triangles cast
  a ray along each layer's normals through a 1/64 occupancy grid of the rest mesh, and the layer crossing fewer surfaces
  faces outside; an open pair is decided by names (`+`, `裏`, `内側`, lining). Each copy vertex then takes its outside
  twin's skinning (type, bones, weights, SDEF parameters). `buildTwinMorphFixes` adds, per vertex morph, the offsets
  that keep each copy vertex with its twin.
- `native/model.cpp`: `parse` runs both after `validateNumbers`, reading only the twin vertices' morph offsets;
  `Instance::publish` applies the corrections with each morph; `buildGpuSkin` counts them in the bone boxes' reach.
  `native/runtime.hpp`: the model's `twinLeads`, `twinMorphFixes` and `twins` report.
- `tests/backface_twin_tests.cpp` (CTest `backface_twins`).
- Rebuilt with `tools\ci\build_hotloader.ps1` (release 2.3.1): the four natives, `native_policy.lua` and
  `mmdhl-native-release.json`, imported with `tools\inputs.py`; `tools/ci/pins.json`'s note names the patch.

The outer layers keep their own skinning and morphs, so every character's outside looks as before; only the copies
change, and only where they differed.

## Checks

- `backface_twins` (synthetic scene): the outside vote, a vote that overrules a misleading name (a `+` part facing
  outside), names deciding an open pair, a pair left alone, four copy vertices re-skinned, the morph corrections (a
  morph of the outer layer moves its copy, one of the copy alone no longer does), the same welds at every load, a
  same-wound overlay not taken for a copy.
- On Fu Xua's `model.bin`: 15 pairs (10 voted, 5 by names, none open), 8,725 copy vertices following a twin, exactly one
  re-skinned: v177473 now on bones 13/174/193/173 as v177194; under a random pose the twins land within 1.1e-6 units.
  Every one of the 15 decisions puts the `+` part behind its twin.
- Over the library (the same test on each `model.bin`): 206 of 206 load and pass; every weld holds within 9.5e-5 units
  under random poses. Six pairs had the vote put a `+`-named part outside; their twins were alike, so nothing changed.
- Cost: a median 28 ms per model on the loading thread (Fu Xua 100 ms, the largest, 941,469 triangles, 455 ms); the
  Hotloader's existing light-overlap pass took 280 ms on Fu Xua.
- The neighbouring native tests: `flashlight_overlaps` and `gpu_skinning` (18 checks) pass.

## In the PoC

RTX 5090, 1920x1080, gm_construct, RTX on; `out\tmp\ragdoll\poc_twins.py` copied Fu Xua's asset, its textures, fits
and library entry from the field library and a scratch add-on into the PoC (all removed afterwards), and
`poc\twin_probe.lua` spawned her as a ragdoll in front of the player, then for 20 s (about 40 samples) measured, for
each of the 15 pairs, the largest distance between an outer layer's drawn vertex and its copy's at the same rest
position (`GetMaterialPositions`, matched through `GetMaterialMesh`), and took three screenshots of the hem. Evidence
in `out\qa-poc\backface-twins`; every run exited 0 and quit normally.

- **The published package** (`0.0.0-dev.20261115223519+c15f69ce`, `03-published`): the hem's copy stood up to
  **7.62 units** from the hem while she fell and settled; every other pair stayed within 0.0008 (their twins were
  alike). The screenshots show the user's symptom: sharp black wedges on the hem's panel, from above and from beside.
- **This branch's package** (`0.0.0-dev.20261116080236+e630b5fe`, `02-branch`): the hem's copy **0.0000** from the
  hem, every pair within 0.0009 (rest positions that coincide within the PMX's rounding); no black patch on the hem.
- The ragdoll falls differently each time, so the poses differ; the measured distance is the comparison.
  `skirt-black-patch-before-after.png` there puts the field session's patch and both runs side by side.
- The first attempt with the published package (`01-published`) could not spawn the character: the asset's textures
  live in `data/mmd_hotloader/textures`, which the copy had missed.

## What is left

- Clipping between different pieces (a skirt through the floor, a leg through a skirt) is the MMD physics' and shows
  in raster too; not changed.
- A copy whose outer layer is itself the mis-weighted one now follows that mistake (raster showed it all along).

## Gate

`tools\test.ps1 -Config Release` on the branch: "All checks passed" (repo conventions OK; C++ 35 of 35; Python 2,019
tests in `tools`, 2 skipped, 29 in `gmapack`, 26 in `steam`). The Hotloader's own C++ tests are not part of it; they
ran as above.

## Published

`main` was fast-forwarded to `bf30f89c` (the branch's one commit) and pushed (`b77e3191..bf30f89c`, four LFS objects,
6.2 MB). The merge's hook built the package from `packages/` and uploaded item 3829070317 as
**0.0.0-dev.20261116082002+3143b18b** (content digest `dbc71b59...`, the same content as the package checked in the
PoC), its change note the changelog's entry; the push's hook found the inputs unchanged. Not yet seen in the field: the
user's running session still has the previous natives until the game restarts.
