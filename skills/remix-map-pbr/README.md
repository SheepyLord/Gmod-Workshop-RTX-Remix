# remix-map-pbr: records

Read [SKILL.md](SKILL.md) for the procedure. This page records where the real tools live, the state of
the five remasters, the limits of this skill's knowledge and its sources.

| File | What |
| --- | --- |
| `SKILL.md` | when to use it, the user's rules, setup check, the workflow, accepted standards, commands, troubleshooting, done criteria |
| `references/pipeline.md` | every stage and script of the five implementations, folders, recipe and light numbers, how the maps differ, a new-map checklist |
| `references/remix-hashes-and-layers.md` | texture hashes (predicted, live, drift), the mod's USD, what the runtime accepts, mod priority and names, reloads, tag textures, how a mod reaches players |
| `references/testing.md` | cameras, tours, before/after, A/B with noise floors, frame times, visibility checks, load time, evidence |
| `references/lessons.md` | pitfalls with symptom, cause, fix, map and date, R3-016 first |

## Where the real tools live

All in the user's fork `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed` (GPL-2.0). The skill describes
them and holds none of their code, because it lives in this MIT repository.

| Map | Branch, tip | Worktree | Pipeline, doc |
| --- | --- | --- | --- |
| gm_poolrooms (Workshop 2849511871) | `sheepylord/rtx-water-poolrooms`; on `origin` up to `f28bd5a`, local tip `fc478c0` | the main checkout | `source/gm_poolrooms_rtx/tools`, `docs/GM_POOLROOMS_RTX.md`; water by `rtx_water` (`docs/RTX_WATER.md`) |
| gm_br_complex, gm_br_pitfalls (Workshop 2821179466) | `claude/rtx-remix-map-enhancement-bda9ac`, `e4d548d`, local only | `.claude\worktrees\rtx-remix-map-enhancement-bda9ac` | `source/gm_br_rtx/tools`, `docs/GM_BR_RTX.md`; loading and visibility fixes in RTXFixesBinary (`source/culling_patches.cpp`, `HardwareSkinningHooks.cpp`, `modelload_fixes.cpp`) and gmRTX Lua |
| modern_house (Workshop 3495468649) | `claude/modern-house-rtx`, `e96ad7f`, local only, never to be pushed | `.claude\worktrees\modern-house-rtx` | `source/modern_house_rtx/tools`, `docs/MODERN_HOUSE_RTX.md` |
| lestnicha3 (Workshop 3756151906) | `claude/lestnicha3-rtx`, `f47063e`, local only | `.claude\worktrees\lestnicha3-rtx` | `source/lestnicha3_rtx/tools`, `docs/LESTNICHA3_RTX.md`; its CC0 downloads in this repository's `out\l3rtx\cc0` (main checkout) |
| gm_brmovie_complete (Workshop 3761466972) | `claude/brmovie-rtx`, `5afbe3f`, local only | `.claude\worktrees\brmovie-rtx` | `source/gm_brmovie_complete_rtx/tools`, `docs/GM_BRMOVIE_COMPLETE_RTX.md` with its gallery and before/after pairs; its CC0 downloads in this repository's `out\bmrtx\cc0` (main checkout) |

Each map has its add-on in `garrysmod/garrysmod/addons/<addon>` and its mod in
`garrysmod/rtx-remix/mods/<mod>`; the extracted map (`map_extract/`) and intermediates (`work/`) sit beside
each pipeline, git-ignored. The AI stage uses the rpai venv, the PBRify weights and rpai's `ModelRunner`
from the `mmd-remix-pbr` skill; DDS encoding uses the Remix Toolkit's `nvtt_export.exe`. This
repository's `tools\package_content.py` and `tools\poc_session.py` package and test a remaster with the
native loader; the workshop-content-pack skill checks and uploads it.

## The maps (the first three as of 2026-10-31; not re-checked since)

| Map | Done | Where it is |
| --- | --- | --- |
| gm_poolrooms | 2026-10-26; calm water by RTX Water | Committed and pushed on the fork branch (the remaster's commit `b5c194e` is on `origin`, textures included: 18 mod files, 149.6 MB). It ships in the RTX package's `packages/fixes` part (imported from `fc478c0`), so in the distribution item 3829070317; the field install has a `gm_poolrooms_rtx` mod folder (2026-11-08) |
| gm_br_complex, gm_br_pitfalls | 2026-10-27; PAS visibility 2026-10-28 | Local branch only; no Workshop item. The field install has a `gm_br_rtx` mod folder (seen 2026-11-08; how it got there is not recorded). Its Lua forced `r_forcehwlight 1` (R3-016): check before shipping |
| modern_house | 2026-10-27; culling fix 2026-10-27; R3-016 fix 2026-10-29 | Hidden Workshop test item 3829275998 (`modern-house-rtx`, `0.0.0-dev.202610300425+d7efd636`, 500 files, 3.32 GB), built with `package_content.py`. Its textures derive from another author's map: the branch stays local and the item hidden (the user, 2026-10-29). Players get it only by subscribing (loader 0.14.0, ADR 0111) |
| lestnicha3 | 2026-11-09 (the user's request of 2026-11-08, with the follow-ups: better plants, replace low-resolution textures, the planter gap, the dandelions) | Local branch `claude/lestnicha3-rtx` (`f47063e`). Installed as real files in the field install (`garrysmod/addons/lestnicha3_rtx`, `rtx-remix/mods/lestnicha3_rtx`, textures hard-linked from the worktree; 619 MB). No Workshop item: its textures derive from the map author's work |
| gm_brmovie_complete | 2026-11-09 (the user's request of 2026-11-09: every region, Backrooms mood, culling for performance) | Local branch `claude/brmovie-rtx` (`5afbe3f`). Installed as real files in the field and PoC installs (`garrysmod/addons/gm_brmovie_complete_rtx`, `rtx-remix/mods/gm_brmovie_complete_rtx`, 2349 textures hard-linked from the worktree; 8.7 GB). 13.4 ms against stock's 79.2 ms (median of 32 cameras, 4K). No Workshop item: the map's authors ask to be contacted before anyone ports, redistributes or modifies it. The map is installed but not subscribed in Steam's record (2026-11-09). A native-loader package under 4 GB is built and not uploaded: this repository's `out\packages\gm-brmovie-complete-rtx\gm-brmovie-complete-rtx.gma` (main checkout; 3,923,815,823 bytes, mod `gm_brmovie_complete_rtx_pack`) |

## Limits

- **Numbers from one machine:** RTX 5090, Ryzen 9 9950X3D, 4K with DLSS, a game with about 250 add-ons,
  sessions of 2026-10-26 to 2026-10-29 and 2026-11-08/09.
- **Not measured:** the material recipes, kelvins and grades were tuned by eye from tours (the user approved
  the results), not with the A/B noise-floor method used for characters.
- **The fork scripts target the classic install:** their `*_GAME` defaults point at `GarrysMod_RTX_c` (no
  longer a classic install; never write there) and `restart.py` uses that install's `_debug_tools`
  launcher. Always set the `*_GAME` variable. lestnicha3's and gm_brmovie_complete's copies default to the
  PoC and were used there with the native loader throughout (2026-11-08/09; `references/testing.md`).
- **Overlapping mods:** Remix takes a texture's first replacement in mod-name order, so remasters of maps
  that share content overlap. The Backrooms remasters (`gm_br_rtx`, `gm_br_rtx_complex`,
  `gm_br_rtx_pitfalls`) sort before `gm_brmovie_complete_rtx` and win 82, 53 and 29 shared prop textures
  in the field (2026-11-09).
- **Changed since the sessions** (from this repository's later rounds): runtime patch 0020 ranks the RTX
  fixes' `~gmod_topbr` after every authored mod; patch 0030 loads a material's preload at its first draw;
  content packages deploy only from subscribed items (ADR 0111); `remix-dxvk.log` is written at exit.
  The references say where each matters.
- **Open questions for the user:** the Backrooms add-on forcing `r_forcehwlight 1` (R3-016); poolrooms'
  derived textures (the upscaled plaster, the ladder atlas) are pushed to the fork's remote and ship in
  the RTX package, while Modern House's stay local; hash replacements of base-game textures change those
  textures on every map.
- **Sources:** the fork's `docs/GM_POOLROOMS_RTX.md`, `docs/GM_BR_RTX.md`, `docs/MODERN_HOUSE_RTX.md`,
  `docs/PBR_GMA_LOADER.md` and the three `tools/` folders; this repository's ADRs 0023, 0027, 0031, 0035,
  0092, 0103, 0111, `tools/package_content.py.md`, `tools/poc_session.py.md`, `tools/compare_frames.py.md`,
  `docs/handover/R3-triage.md`, `docs/RESEARCH.md` sections 12, 20, 21 and 32; the `mmd-remix-pbr` skill; the
  session transcripts `3d2eda0e` (Backrooms), `74c5d7d0` (Modern House), `3f948dbb` (gm_poolrooms),
  `ff87a857` (Modern House follow-up: GPU use, save loading), `94200df9` (Blood Overhaul, general Remix
  lessons only), `46de923c` (lestnicha3, 2026-11-08/09, with the fork's `docs/LESTNICHA3_RTX.md`) and
  `ad616835` (gm_brmovie_complete, 2026-11-09, with the fork's `docs/GM_BRMOVIE_COMPLETE_RTX.md`).
  Drafted 2026-10-31; brought up to date 2026-11-09.
