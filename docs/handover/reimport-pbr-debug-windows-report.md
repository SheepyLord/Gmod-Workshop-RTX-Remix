# A re-import picks up the PBR maps added to its folder; the MMD player's debug windows hide (2026-11-24)

The user wrote, 2026-11-24, after pasting another session's notes on ToPBR's session caches:

> When I forgot to put PBR into the folder of a pmx, and I reimported it in the same session, PBR are not applied.
>
> 2. Also address a QoL for mmd motion player debug, allow user to hide all the debug menu (motion and camera) but keep
> in debug mode, so user can take screenshot or move.

Claude (the main session) traced both, reproduced the first in the PoC, wrote the debug-window change and both game
tests, and validated; an Opus 5.5 subagent wrote and built the fixes' native patch. On the branch `reimport-rescan`
(worktree `out\worktrees\rescan`, from `main` at `4173c298`). Package only, no loader (`winmm.dll`) change. Decisions:
[ADR 0263](../decisions/0263-a-re-import-looks-at-the-models-folder-again.md),
[ADR 0264](../decisions/0264-hide-the-debug-windows-and-stay-in-debug-mode.md); facts: [RESEARCH.md](../RESEARCH.md),
"A model imported again in the same session: ToPBR's session caches" and "The MMD animation player's debug windows".

## 1. A re-import picks up the PBR maps added to its folder

### Why the maps were not applied

- A Model Hotloader character's asset id is a hash of the model's own content (the PMX and the textures it names), so
  an unchanged PMX imported again has the same id and the same material names `mmd/<the id's first 16 digits>/...`.
  The maps beside the PMX are not part of it.
- The RTX fixes' imported game PBR kept the first answer for the whole session in four places: its Lua submitted each
  material name once (`gameSubmitted`), the module refused a name it had (`m_gameSubmitted`), the worker scanned a
  model's folder once (`DiscoveryCache`) and resolved each texture once (`GameRegistry::Session`), "no maps" included.
  The answer was not saved, so a restart helped.

### What was built

| Part | What it does | Where |
|---|---|---|
| `MMDHL.Imported` hook (`RTXToPBR_GameRescan`) | After every finished character import or Reload: for that asset (64 hex digits; its names start with `mmd/` and the first 16) asks the module to rescan; when the module takes it, forgets the Lua's own submissions and progress entries and starts the next pass at once. A refused call changes nothing; a module without the function: only the Lua part | `packages/fixes/.../cl_rtx_topbr_conversion.lua` |
| `ToPBR.RescanGameSource(source, prefix)` | Game thread, under the queue lock: refuses unless initialized, game maps on, a character's prefix, a `.pmx` on a local drive (no control character, at most 2048 bytes), room in the queue and a second since the last call it took; forgets the prefix's submitted names, sets their views to "waiting", queues an internal `rescan` job (`GameMaterialAction` cannot name it) | the fixes' seventeenth native patch, `packages/fixes/licenses/oversized-skinning/game-rescan/` (`to_pbr.cpp`, `to_pbr.h`, `game_rescan.h`) |
| The worker's `rescan` job | Drops every folder scan; erases the session resolution and view of the textures of the live materials under the prefix or from the same PMX file; prints `Game maps looked at again: <PMX file name> (<n> textures)`. Their registered maps stay until their next resolution: a record replaces them, none or a failure takes them back | the same |
| `game_rescan_session.py`, `game_rescan_probe.lua` | The PoC test: import without the maps, settle, copy the maps in, import again, settle; PASS/FAIL | `tools/qa/` |

The module: 5,682,176 bytes, SHA-256 `fc850271b02dd0d739c6ee293bb1baf6e3972d5aec55dc65c7ced51ddacc75d9`, built with
`tools/ci/build_modules.ps1 -Only fixes` from the user's fork clone (garrysmod_common `a854f23`, premake 5.0.0-beta2,
under a `subst` alias); the seventeen patches give the native tree `41dc27fc...` (`fixes.patched_tree.source`).

The subagent changed two points of the first design, both kept: the maps registered for a texture are not taken back at
the rescan (a re-import would have shown the character without maps for a moment, and another character drawing the
same texture, whose names are not submitted again, would have lost them for the session); and the views are set to
"waiting" on the game thread, not in the worker, so the progress notice does not race the worker.

### Checked

- Before the fix (the published package `0.0.0-dev.20261123212444+ec7d0621`, `game_rescan_session.py --expect-none`,
  evidence `out/game-rescan/old1` of the main checkout): "Character A" (a game-rip character whose `_N` and `_MRA` maps
  sit in a subfolder) without its maps: 9 of 28 materials `none` (face, skin, body, hair, its weapon, a pupil), 19
  `waiting` (never drawn, so never asked). Maps copied in, imported again: the same asset id, the same 9 `none`, no
  "Imported game maps" line. The report, reproduced.
- With the fix (the package built from the branch, `game_rescan_session.py`, evidence `out/game-rescan/fix2`, `fix3`
  and `fix4`: three runs, the same numbers each time): the same 9 `none` before; maps copied in, imported again: the same asset id, one `Game maps looked at again: <PMX> (8
  textures)` line, five `Imported game maps` conversions (both body sheets, the weapon, both hair sheets), and 6
  materials `automatic`. The 3 still `none` are the face, the skin and a pupil, which the converter leaves as Remix
  draws them on purpose (`game_pbr.h` classifies face, eye and skin materials as "Original"; the skin and the pupil were
  paired with their maps by name, the face's pairing to the skin's maps was refused as a conflicting family). PASS.
  (A first run, `fix1`, showed the same rescan line, then stopped in the driver: the module's line had landed on the
  same console line as the probe's JSON; the driver now reads the JSON up to its end.) The screenshots keep the
  character at the right edge of the frame; a crop of both (`fix3\compare-character.png`) shows the maps at work after
  the re-import: hair strands with their highlights, the arm piece's metal, the coat's folds.
- Tests: `test_game_rescan.py` (6, with the regression's 62 checks), `test_cleanup_drain.py` (15) and `test_lua_guards.py`
  (8) by the patches' places, `test_ci_tools.py` with the tree replay, `test_topbr.py` (the harness's re-import cases),
  `test_inputs.py`.
- The gate (`tools\test.ps1 -Config Release`, the fixes' tree replay with the fork clone): the conventions, 35 of 35
  native tests, 29, 26 and 2,234 Python tests: "All checks passed".

## 2. The MMD animation player's debug windows hide without leaving debug mode

### What was built

- **Hide windows** in the debug window's button strip (beside Next): the debug window and the camera debug panel are
  hidden (`SetVisible(false)`), not closed, so nothing goes to the server and debug mode, the pose, a playing preview
  and the camera preview stay; the mouse and keyboard go back to the game. A notice (six seconds) and the button's
  tooltip name the key that shows them again.
- **Back**: the context menu's key (`OnContextMenuOpen`, C by default), the player's own key
  `mmd_vmd_npc_debug_panels_key` (the tool's Advanced tab, "Show/hide debug windows key", none by default; it also
  hides them; not while typing), `mmdvmd_debug_panels` (`0` hides, `1` shows, nothing toggles), and opening debug mode
  again from the tool, the motion window or the console (`MMDVMDNPC.ShowDebugMenu`); the window's own steps keep using
  `OpenDebugMenu` and leave them hidden.
- Five texts in the add-on's nine catalogs (en, zh, zh-tw, ja, ko, fr, ru, ar, es).

### Checked

- LuaJIT: `test_motion_tab.py`'s new `debug_windows` scenario (14 of 14 with the others), and the other motion player
  tests (`test_motion_camera`, `test_motion_server`, `test_motion_skeletons`, `test_mmd_morphs`, `test_lights`).
- PoC (`mmd_player_session.py --debug-windows --no-steps` with a package built from the branch, evidence `out/dbgwin`
  of the main checkout): debug mode on the test dance at frame 60 on an imported character, the camera panel ticked.
  Shown: both windows, the cursor on, the keyboard in the window. Hidden: both gone, the cursor off, the keyboard out
  of the window; the server still at debug frame 60 with the right hand where that frame puts it; the same seven seconds
  later. Context menu held and let go: both back, the window keeps the mouse. `mmdvmd_debug_panels 0`/`1` and opening
  debug mode on hidden windows: as expected. Closed: debug mode ends as before (the server's debug frame cleared, the
  character back in its reference pose). Screenshots: the windows with the button, the notice, the posed character
  alone, the windows back.
- Not covered: a real key press for the player's own key (mocked in the harness; the game test uses console commands).

## Files

- The re-import: `packages/fixes/licenses/oversized-skinning/game-rescan/` (new: `game-rescan.patch`, `README.md`,
  `source/material_pipeline/to_pbr/{game_rescan.h, to_pbr.cpp, to_pbr.h}`, `tests/game_rescan_test.cpp`);
  `packages/fixes/modules/gmcl_RTXFixesBinary_win64.dll` (rebuilt), `packages/fixes/files.json`,
  `packages/fixes/README.md`; `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_topbr_conversion.lua`;
  the patch counts in `packages/fixes/licenses/oversized-skinning/{cleanup-drain,lua-guards}/README.md`,
  `tools/ci/README.md`, `tools/ci/build_modules.ps1.md`; `tools/ci/pins.json` (`fixes.patches`, `fixes.patched_tree`).
- The debug windows: `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_menu.lua`, `sh_core.lua`,
  `lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua`, `packages/character-motion-importer/files.json`.
- Tests: [test_game_rescan.py](../../tools/tests/test_game_rescan.py.md) (new), `test_cleanup_drain.py`,
  `test_lua_guards.py`, `topbr_harness.lua` (the re-import cases), `motion_tab_harness.lua` and `test_motion_tab.py`
  (the `debug_windows` scenario), each with its `.md`.
- QA: [game_rescan_session.py](../../tools/qa/game_rescan_session.py.md) and
  [game_rescan_probe.lua](../../tools/qa/game_rescan_probe.lua.md) (new); `mmd_player_session.py` and
  `mmd_player_probe.lua` (`--debug-windows`), each with its `.md`.
- Docs: ADR 0263, ADR 0264 and their rows, CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS, AGENTS.md, this report
  and its line in the handover index.

## Published

Merged to `main` as `5b831611` (a fast-forward) and pushed; Workshop item 3829070317 updated as
`0.0.0-dev.20261124082855+6b799cdf` (2026-11-24 08:29 UTC), its change note the two CHANGELOG entries; the push's own
publish found the inputs unchanged. No run in the field install: checking these there would import a model into the
player's library and write a test motion into their motion folder; the PoC runs above cover both. The field game the
first PoC run found running was ended by its driver (the standing rule that a field game is a test session).

## Notes and open questions

1. The PoC's game-rip character had 19 of its 28 materials never asked about (never drawn in the view, or hidden
   parts); they behave the same before and after.
2. Maps copied into a folder without a re-import are still taken only at the next import or game.
