# game_rescan_probe.lua

The client probe of [game_rescan_session.py](game_rescan_session.py.md)
([ADR 0263](../../docs/decisions/0263-a-re-import-looks-at-the-models-folder-again.md)). The driver sends it through the
console into a PoC RTX session; it is never installed. It defines the global table `NLRS`:

- `NLRS.Import(source)`: imports the PMX through the Model Hotloader's own library flow
  (`mmdhl.library.StartImport(mmdhl.native.BeginImport(source, mmdhl.library.CharacterImportOptions()))`), so the
  import ends as the player's does, in the library's `MMDHL.Imported` hook, which the RTX fixes' Lua also hooks. When
  that hook runs for this import it prints `NLRS_IMPORTED {"asset": <id>, "source": <path>}`.
- `NLRS.Spawn(asset)`: spawns the character as a frozen citizen (`mmdhl.RequestSpawn`), printing `NLRS_READY
  {"index": <entity index>}`.
- `NLRS.View(index)`: a `CalcView` camera in front of the character's chest (its `Spine2` bone, else `Spine1`, the
  pelvis or 40 units above its origin; a carrier's bounding box need not be where the model is drawn), the HUD off, the
  first-run dialogs closed. The entity is looked up in each frame: a character spawned a moment before may reach the
  client after the call (a first version looked once and drew no camera at all). In the PoC runs of 2026-11-24 the
  character still sat at the right edge of the frame; the verdict does not depend on the screenshots, and a crop of
  both shows the change.
- `NLRS.States(asset)`: for each material of the asset (`mmdhl.assets[asset].materials`), the RTX fixes' imported game
  PBR view (`MaterialPipeline.ToPBR.GetGameMaterial(path)`: `state`, `family`, `error`), counted by state; the materials
  still converting and the batch's size (`RTXGamePBRProgress()`); whether the module has `RescanGameSource`. Writes the
  whole list to `data\nlrescan\states_NNN.json` and prints `NLRS_STATES` with the counts.

- `NLRS.Restore()`: sets `nativeloader_sky_time_passes` and `nativeloader_sky_time` back to the values recorded when
  the probe was sent (the driver changes them for its screenshots), then prints `NLRS_RESTORED`.

It prints `NLRS_INSTALLED` when sent, and `NLRS_ERROR <reason>` when an import does not start or a spawn fails (the
driver stops on that line). Side effects: a character imported into the session's (fresh) Model Hotloader library and
spawned, two client hooks (`CalcView`, `HUDShouldDraw`), files under `data\nlrescan`.
