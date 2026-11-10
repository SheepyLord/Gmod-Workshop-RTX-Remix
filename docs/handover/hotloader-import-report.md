# The Model Hotloader's imports: slow physics, no percentage, a crash once the importer shows a prop (2026-11-10)

The user's report (through the session that started this one): importing `E:\G\Upload\Ganyu_alt\1_PMX\花.pmx`, a static
flower (1,584 triangles, 2 materials), with the RTX package's Model Hotloader (its `model-hotloader` part):

1. at the default settings, building the physics took a long time;
2. the importer showed no percentage for that;
3. for any new import, the game crashed when the imported item was loaded from the importer ("Garry's Mod closed
   unexpectedly", 0xC0000005), evidence in the field install's `native-loader/logs/sessions/2026-11-10T212505.066Z-36508-crash`.

Done by Claude on branch `hlfix` (worktree `out\worktrees\hlfix`), no Codex. Decision:
[ADR 0152](../decisions/0152-hotloader-imports-fast-by-default-and-props-drawn-without-render-meshes.md); facts and
offsets: RESEARCH, "Model Hotloader imports".

## 1. The physics: what the default was, what it is now

| | The flower's import (offline, the shipped worker) |
|---|---|
| Single hull (`mmdhl_prop_import_collision hull`) | **0.08 s** (every stage under 20 ms) |
| Detailed collision (`balanced`, CoACD) | **26.1 s, 36.2 s, 37.6 s** in three runs; 41.1 s in the PoC game |
| As a character (its physics is the fit) | 0.16 s (the fit 11 ms) |

- **What the default was.** The convar's default has been the single hull since the option exists (2.1.0); but it is
  a remembered (archived) choice, and the user's game had `balanced` saved (`cfg/client.vdf`, read only). So every
  static import of theirs ran CoACD, which remeshes the non-manifold flower into 31,568 triangles, decomposes it in
  16-20 passes into 138-246 pieces and merges them into 16 hulls. Their import registry holds the flower imported
  both ways (the same asset ids as offline). Character imports spend no comparable time on physics.
- **What it is now.** Detailed collision serves **one import**: an import that starts with it sets the choice back to
  the single hull, so an ordinary import, and a static prop above all, never runs CoACD unless the player picks it for
  that import. A `balanced` remembered from before goes back to `hull` once (`mmdhl_prop_import_collision_version`).
  A reimport keeps detailed collision for a prop that has it. The option reads "next import only" in all seven
  languages, and the combo shows the single hull again after the import.
- **Why.** A per-prop quality choice stored as a global default made every later import slow without saying so; that
  is how the user's game got here. A faster CoACD would change what the option builds (see "Not done").

## 2. The percentage

| Stage | Before | Now |
|---|---|---|
| Detailed collision (static) | 65 % from start to end (26-54 s), "this stage has no percentage estimate" | its passes from CoACD's own log (pipe on the worker's standard output), its silent merge estimated; the stage spans 10-95 % of such an import |
| Character: textures | 10-90 % per material | 10-62 % per material |
| Character: Source materials, their package | 91 % for 0.5-0.9 s, then 94 % for the package's 0.75 s | 62-94 %, per material, then per byte written |

Offline with the final natives (the flower, detailed; time against shown percentage): 30 % at 30 %, 41 % at 39 %,
57 % at 48 % (the merge starts), 72 % at 59 %, 80 % at 68 %, 89 % at 94 %, then 96-100 % (37.6 s). Ganyu as a
character: the shown percentage within 1-6 points of the elapsed share throughout (4.4 s). The CoACD merge logs
nothing, so that part is an estimate from the number of pieces it merges; it slows towards its end and may jump from
about 80-90 % to the end. The worker's output is unchanged (the same asset ids before and after).

## 3. The crash

- **The user's dump:** access violation at `studiorender.dll+0x6603b` (the 3x4 matrix concatenation) from `+0x141b9`, on
  the material system's queued render thread, in studiorender's loop over a model's render meshes: GMod's
  `ENT:GetRenderMesh`. The first mesh (`r14` 0, `r15` 0x388) with a garbage index register (`rbx` `0x18000000000`).
  The same fault as R4's procedural glass and three of issue 2's crashes.
- **The Hotloader's static props** drew through hidden client entities whose `GetRenderMesh` returned the prop's Lua
  mesh, drawn with `DrawModel`: in the importer's preview (which selects every new import at once), the placed
  `mmdhl_prop`, the tool's ghost and the parts editor.
- **Reproduced in the PoC** with the published package (`out/hlfix/qa/repro-153720` in the main checkout): RTX on,
  `mat_queue_mode 2` (the user's), gm_construct. The flower imported (0.6 s), placed and drawn for 1,078 frames, the
  detailed import (65 % for 41 s), then about 3 s after a character import the game died (exit 0xC0000409, GMod's
  handler after the first fault): GMod's report has the client in `DrawModel` <- the RTX fixes' `cl_rtx_misc.lua:145`
  <- `props/render.lua:15` (the proxy's `Draw`) <- `:272` `drawPieces` <- `DrawAsset` <- `mmdhl_prop`'s `ENT:Draw`, and
  its dump the same access violation at `studiorender.dll+0x6603b` from `+0x141b9`, index 0, a garbage `rbx`.
- **The fix** (`props/render.lua`): no proxy entity. `P.DrawAsset` pushes the prop's model matrix (rotation, uniform
  scale, the native render origin: the proxy's placement, checked in the test) and draws each piece's mesh with
  `render.SetMaterial` and `IMesh:Draw`, in the colour pass and in `render.RenderFlashlights`, as R4's glass shards do.
  A coloured prop (colour tool, the tool's translucent ghost) draws with materials of its colour, eight colours a
  prop; released meshes are destroyed eight frames late.
- **Verified in the PoC** with the package built here (see "Checked in the PoC"): the same sequence at 2560x1440, where the importer's preview also paints, with no crash.

## Checked in the PoC

`out/hlfix/poc_hl.py` and `out/hlfix/hl_probe.lua` (main checkout; R27's driver adapted: the PoC's loader, deployed
package and data moved aside, a clean install of the loader with one package, everything moved back and rolled back
after each run). RTX on, `mat_queue_mode 2`, `-noworkshop`, gm_construct, the importer opened on Static Props; the
flower imported with the defaults and shown by the importer for 20 s, placed and looked at for 20 s, imported again
with detailed collision, then Ganyu (`甘雨.pmx`, a character) imported, shown and spawned as a ragdoll.

| Run | Package | Result |
|---|---|---|
| `repro-151943` (1280x720) | published (item 3829070317, `0.0.0-dev.20261110142116+be270f89`) | no crash; the preview never painted at 720p (the window leaves it no room), the placement failed (aimed only client-side) |
| `repro-153720` (1280x720) | the same | **crashed** as above, after 1,078 frames of the placed flower and the character's import |
| `verify-154149` (2560x1440) | built here (`gmod-rtx-remix-0.0.0-dev.20261110223921_3d75f479`, SHA-256 `c06f1a47...`) | **no crash**, a normal quit, all seven screenshots: the flower imported in 0.27 s (single hull), shown by the importer's preview for 557 frames and placed and looked at for 681; the detailed import ran (the choice back to the single hull after it starts, the registry recording `balanced` for that asset only); Ganyu imported (6.3 s), shown by the importer, spawned as a ragdoll beside the flower |

The percentage the importer showed in the game (`HLQA_PROGRESS`, every change of `library.progress`):

| Import | Published package (`repro-153720`) | Built here (`verify-154149`) |
|---|---|---|
| The flower, single hull | 0 %, 99 %, 100 % in 0.2 s | the same |
| The flower, detailed | 0 %, then **65 % for 41 s**, then 100 % (3 updates) | 59 updates: 18 % at 3 s, 37 % at 25 s, 53 % at 34 s, 75 % at 40 s, 90 % at 55 s, 100 % at 58 s |
| Ganyu, character | 12 updates; 91 % from 2.6 to 3.8 s | 24 updates; 51 % at 3.3 s, 72 % at 4.1 s, 94 % at 5.2 s |

The verify run's detailed import took 58 s against 41 s because the C++ test gate was compiling on the same machine; the screenshots `shot-04-flower-detailed-progress.png` show "Decomposing collision 64%" (published, 12 s in, as for its whole 41 s) and "Decomposing collision 24%" (built here, 12 s in). Evidence: `out/hlfix/qa/<run>/` in the main checkout (each run's `qa-summary.json`, `restoration.json`, `poc/<session>/` with the console and screenshots; the crash's GMod report and dump in `repro-153720/hl-repro-crash/`).

## Tests

- `tools/tests/test_hotloader_props_render.py` with its LuaJIT harness: the real `props/render.lua` prepares and draws a
  prop with the engine instrumented; no entity, no `DrawModel`, the model matrix against the proxy's placement, the
  flashlight pass, colour materials, late destruction. It fails at once against the old file.
- `tools/tests/test_hotloader_prop_options.py` with its harness: the reset of a remembered choice, one import per
  choice, a `.blend` listing not using it, reimport keeping a detailed prop's collision, the combo following its
  setting. It fails at once against the old files.
- The add-on's catalogs: `tools\check_addon_i18n.py`, 0 problems; the existing Hotloader tests pass.
- Offline imports with `mmdhl_worker.exe --request` (`out/hlfix/time_import.py`): the timings above, the same asset ids.
- `tools\test.ps1 -Config Release` in `out\worktrees\hlfix`: all checks passed (CTest 30 of 30, 791 Python tests, one
  skipped).

## Built and recorded

- Natives: `tools\ci\build_hotloader.ps1 -Source <out\hlfix\stage\mmdhl> -Vendor <ipg\!GMHLVK\wt-full-textures-props\vendor>`
  (absolute paths), build `c0c55fb9209d-20261110T222450Z`; the four natives, `native_policy.lua` (its 2.3.1 entry) and
  `bin/mmdhl-native-release.json` imported with `tools\inputs.py import --file`, with the five changed sources,
  `source/import-progress.patch` (checked: applied to the previous copy it gives the new one) and `Source.md`.
  `tools/ci/pins.json` `hotloader` names this round's patch beside R19's. The stage must come from
  `inputs.py extract` (a copy of the part holds `native/shape_atlas.hpp` as `.xz`; the first build failed on it).
- New SHA-256: `gmcl_mmdhl_win64.dll` `8cb7a7a2...`, `gmsv_mmdhl_win64.dll` `2a209177...`,
  `mmdhl_runtime_win64.dll` `1a357381...`, `mmdhl_worker.exe` `88fd2d60...`.

## Not done, follow-ups

- The fixes part's Seamless Portals (`seamless_portal/cl_init.lua`) still draw through `GetRenderMesh` and `DrawModel`,
  the same path; a portal under queued rendering is exposed to the same fault.
- Detailed collision itself is still slow: CoACD decomposes to a concavity of 0.05 and then merges to 16 hulls, which
  leaves a concavity of about 0.17 anyway; decomposing to a threshold near what 16 hulls reach would be much faster,
  but changes what the option builds, so it was not done here.
- The Linux worker has no pipe: its detailed-collision stage keeps the old message.
