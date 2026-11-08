# nativeloader_pbr_progress.lua

R23 (the user's item 3: "If the user import a model with PBR and the game is processing them before
they are applied, let the user know it is loading and show a small progress bar"; [ADR 0132](../../../../../docs/decisions/0132-progress-while-imported-pbr-converts.md)).
Client autorun.

When a spawned imported character's game PBR maps convert (the RTX fixes' imported game PBR, R11/R12),
a notice at the top right ([`nativeloader/notice.lua`](../../nativeloader/notice.lua.md)) says
"Preparing PBR materials for imported characters: 3 of 8." with a progress bar, and then "PBR
materials for imported characters are ready." for four seconds. Translated (`L`).

- **The count** comes from the fixes' ToPBR driver: `RTXGamePBRProgress()` returns how many submitted
  materials the native worker still shows as `waiting`, and how many the batch had; the batch ends
  when none is (`cl_rtx_topbr_conversion.lua` in the fixes part).
- **When:** a timer polls it four times a second (one native view read per pending material). A batch
  shows a notice only once it has lasted 1.5 s, so restoring saved maps shows nothing. A notice the
  player closes stays closed until the next batch.
- Without the RTX fixes (no `RTXGamePBRProgress`) nothing happens; a failing count shows nothing, and a
  failure of the notice itself stops the poll with one console line.

Tested by [`tools/tests/test_pbr_progress.py`](../../../../../tools/tests/test_pbr_progress.py.md) and,
for the count, [`tools/tests/topbr_harness.lua`](../../../../../tools/tests/topbr_harness.lua.md).
