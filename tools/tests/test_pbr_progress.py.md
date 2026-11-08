# test_pbr_progress.py

Unit tests (R23, the user's item 3) that run the companion's real
`lua/autorun/client/nativeloader_pbr_progress.lua` under LuaJIT through
[pbr_progress_harness.lua](pbr_progress_harness.lua.md), one scenario per run.

```powershell
cd tools; python -m unittest tests.test_pbr_progress
```

- `quick`: a batch done within 1.5 s (saved maps restored) shows no notice.
- `progress`: a longer batch shows a lasting notice with "0 of 5" and its bar, updates it ("3 of 5",
  0.6), says the maps are ready and lets it go four seconds later; a later batch shows a new one.
- `closed`: a notice the player closes is not shown again for its batch, but is for the next.
- `absent`: without the RTX fixes, or with a failing count, nothing shows; a failure of the notice
  itself stops the poll with one console line.

Skipped without LuaJIT. Exit code 0 when every test passes. No side effects.
