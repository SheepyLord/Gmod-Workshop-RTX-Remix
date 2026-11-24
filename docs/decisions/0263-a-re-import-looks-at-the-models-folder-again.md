# 0263: A re-import looks at the model's folder again

- Status: Accepted 2026-11-24 (the user's report: "When I forgot to put PBR into the folder of a pmx, and I reimported it
  in the same session, PBR are not applied."). Extends the imported game PBR of R11 and R12
  ([ADR 0091](0091-automatic-pbr-fallbacks.md), [ADR 0093](0093-cached-imported-game-materials.md)) and the
  review's source rule of 2026-11-16 (its finding 7, [ADR 0234](0234-what-a-server-a-workshop-item-and-lua-may-reach.md)).
- Package only: the RTX fixes' binary module `gmcl_RTXFixesBinary_win64.dll` (the fixes' seventeenth native patch,
  [game-rescan](../../packages/fixes/licenses/oversized-skinning/game-rescan/README.md)) and the fixes' Lua
  (`cl_rtx_topbr_conversion.lua`). No `winmm.dll` change: the user rejected loader changes (2026-11-17).

## Context

The RTX fixes' imported game PBR (`rtx_topbr_game_maps 1`, on by default) gives a Model Hotloader character the game's
own maps found beside its PMX (`<stem>_N`, `_MRA`, `_P`, `_E` ...). Everything it learns about a character is kept for
the whole game session:

- The character's asset id is a hash of the model's own content (`packages/model-hotloader/source/mmdhl/native/
  assets.cpp`, the manifest: the PMX and the textures it names), not of the maps beside it, so importing an unchanged
  PMX again gives the same asset id and the same material names `mmd/<id>/...`.
- The fixes' Lua submits each loaded character's materials once a session (`gameSubmitted`), and the module refuses a
  name it was given before (`m_gameSubmitted`).
- The module's worker scans a model's folder once (`DiscoveryCache`: the images it lists are never listed again) and
  resolves each texture identity once (`GameRegistry::Session`), a "no maps" answer included.

A player who imported a character before copying its maps into its folder, then imported it again, got the first
answer back: no maps until the game was restarted (a "no maps" answer is not saved). `rtx_topbr_clear` (`ToPBR.
ClearCache()`) starts everything again, the map's own conversions and the published layer included: too broad for a
re-import.

## Decision

1. **A finished import or Reload of a character looks at its model's folder again.** The fixes' Lua hooks the Model
   Hotloader's `MMDHL.Imported` (fired on the client after every completed character import and Reload, with the full
   asset id, 64 hexadecimal digits; its material names start with `mmd/` and the id's first 16). It asks the module,
   through the new `ToPBR.RescanGameSource(source, "mmd/<first 16>/")`, to forget what the session knows about that
   model; when the module takes the call it also forgets the materials it submitted itself, and the next pass of its
   game-map loop (started at once) submits them again, so they are resolved as at a first import. A refused call
   changes nothing; with a module that lacks the function only the Lua's own part runs.
2. **What the module forgets** (the seventeenth native patch, `game-rescan`): on the game thread, under its queue lock,
   the submitted names under the prefix, whose panel views say "waiting" again (the companion's progress notice counts
   them); on the worker, every folder scan and, for the texture identities of the live materials under the prefix or
   drawn from the same PMX file, their session resolution and panel view. The imported maps registered for those
   materials stay until their first resolution since: a record replaces them, no record or a failure takes them back
   (and a publication follows). So a re-import does not leave the character without maps for a moment, and another
   character drawing the same texture, whose names are not submitted again, keeps its maps. The game-map registry
   re-converts from a readable source on every resolution, so maps that were added or changed are taken; a manual
   choice saved in the panel stays (`overrides.Select` comes first).
3. **Bounded for any Lua.** Any server's client Lua reaches ToPBR's functions (ADR 0112): the call is refused unless the
   converter is initialized and the player's game maps are on, the prefix is `mmd/`, 16 hexadecimal digits and `/`, the
   source is a `.pmx` on a local drive (`LuaPathPolicy::LocalDrivePath`, at most 2048 bytes, no control character, a NUL
   refused rather than cut) and the game-map queue has room; one call a second is taken; nothing is opened on the game
   thread. `GameMaterialAction` cannot name the worker's internal `rescan` action. One console line says what happened:
   `[MaterialPipeline::ToPBR] Game maps looked at again: <PMX file name> (<n> textures)`.

## Consequences

- Copying a character's maps into its folder and importing it again (or Reload in the entity editor) applies them in
  the same session; so do maps that were replaced.
- A re-import of a character whose maps were found before converts them again from its folder (the registry always
  did on a resolution; now a re-import is one).
- Two re-imports within the same second: the second is not looked at again (the limit); an import takes longer than
  that.
- Not covered: maps copied into the folder without importing again are taken at the next import or the next game; the
  panel's per-texture lists also refresh at a re-import.
- Tests: the patch's standalone regression and `test_game_rescan.py`, the Lua hook in the ToPBR harness, and
  `tools/qa/game_rescan_session.py` in the PoC (the old package reproduces the report; the new one gives the maps).
