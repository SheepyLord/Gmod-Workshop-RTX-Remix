# pbr_progress_harness.lua

LuaJIT harness for the companion's `lua/autorun/client/nativeloader_pbr_progress.lua` (R23, the
user's item 3). Invoked by [test_pbr_progress.py](test_pbr_progress.py.md):
`luajit pbr_progress_harness.lua REPO SCENARIO`.

Mocks the RTX fixes' `RTXGamePBRProgress` (materials still converting, and the batch's total),
`RealTime`, ordered repeating timers, `include` of the i18n module (marking translated text with `T:`)
and of the shared notice (a recording panel with `SetNoticeText`, `SetNoticeProgress` and
`FinishNotice`), and the console. Scenarios: `quick`, `progress`, `closed`, `absent` (see the test's
`.md`). Prints `PASS <scenario>` and exits 0, or raises an assertion error. No side effects.
