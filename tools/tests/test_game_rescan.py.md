# test_game_rescan.py

Checks the RTX fixes' seventeenth native patch,
[game-rescan](../../packages/fixes/licenses/oversized-skinning/game-rescan/README.md) (ADR 0263): a Model Hotloader
character imported again in the same game has its game maps looked for again. An unchanged PMX keeps its asset id and
its material names, which ToPBR's game maps submitted once a session while the worker kept each model folder's scan and
each texture's resolution; `ToPBR.RescanGameSource(source, prefix)` forgets the character's submissions and has the
worker let those go, and the driver's `MMDHL.Imported` hook asks for it after each import or Reload.

```powershell
cd tools; python -m unittest discover -s tests -p test_game_rescan.py -v
```

- `GameRescanPatchTests`:
  - `test_complete_files_are_the_patch_applied`: `game-rescan.patch` touches exactly `game_rescan.h`, `to_pbr.cpp`,
    `to_pbr.h` (under `source/material_pipeline/to_pbr`) and `tests/game_rescan_test.cpp`; `to_pbr.cpp` is lua-guards'
    copy and `to_pbr.h` topbr-scope's with the patch applied (no folder between holds them), the two new files the
    patch's added lines (no earlier folder holds them); `tools/ci/pins.json` builds the module with the patch right
    after cleanup-drain (each patch once); the folder's README names it the seventeenth native patch and the tree the
    seventeen give (`41dc27fc...`), which `fixes.patched_tree.source` must be while the patch is the last one.
  - `test_the_header_needs_no_sdk`: `game_rescan.h` includes only standard headers and holds the one-a-second interval
    and the 2048-byte bound; `to_pbr.h` includes it, declares `RescanGameSource` and holds the `GameRescan::Limit`.
  - `test_the_binding_is_registered_and_refuses_what_it_does_not_take`: `ToPBR.RescanGameSource` is registered right
    after `ClearCache` and takes both strings whole (`GetString` with their lengths); `RescanGameSource` checks the
    converter, the player's game maps, the prefix, the source and the local drive before it locks, then the queue's
    room, then the limit, and only then forgets the prefix's submissions, sets their views waiting and queues the
    `rescan` job; it opens no file. `QueueGameMaterial`'s actions are unchanged and never `rescan`; one place in the
    module makes that action.
  - `test_the_worker_handles_the_rescan_before_the_identity_logic`: the worker's `rescan` branch comes before any
    live-job work, clears `gotGame`, drops the folder scans, lets go of the identities `GameRescan::Identities` names
    (session resolution, identity view, noted as let go), prints `Game maps looked at again: %s (%zu textures)` and
    catches what it throws, and leaves registered maps alone; no worker path calls `discovery.Get` directly; the first
    resolution since then (`resolving`, after `ResolveOnce`, before the maps are registered) takes the maps back when
    it finds none, and so does a failed one (the `catch`); `retract` removes only `importedGame` entries and asks for
    a publication; `overrides.Select` still decides first.
  - `test_the_driver_rescans_after_an_import`: `cl_rtx_topbr_conversion.lua` adds `RTXToPBR_GameRescan` to
    `MMDHL.Imported`, outside the R12 panel's section, naming ADR 0263: an id of 64 lower-case hex digits, the prefix
    from its first 16, the source from `mmdhl.library.entries` (not `mmdhl.assets`), `RescanGameSource` asked before
    the submissions are forgotten, a refusal or error leaving them, and the pass started at once. The Model Hotloader's
    `library.lua` fires the event after `library.Refresh()` with ids its `validId` takes (64 hex digits), and
    `naming.cpp` builds material names from the id's first 16 digits. The hook's behaviour runs in
    [topbr_harness.lua](topbr_harness.lua.md) ([test_topbr.py](test_topbr.py.md)).
- `GameRescanRegression` (Windows with the VS 2022 Build Tools): every patch folder's `source/` and `tests/` in
  `pins.json`'s order, later over earlier, copied to a scratch folder under `out\tmp`; `game_rescan_test.cpp` compiled
  with `/W4 /WX /UNDEBUG` and run; it must print `PASS game rescan:`.

Reads only this repository; the C++ check writes and removes a scratch folder under `out\tmp`. Exit codes: unittest's.
