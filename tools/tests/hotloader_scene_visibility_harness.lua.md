# hotloader_scene_visibility_harness.lua

A LuaJIT harness for the Model Hotloader's hair and clothing scene capture
([ADR 0245](../../docs/decisions/0245-mmd-hair-and-clothing-leave-out-what-nobody-sees.md)), run by
[test_hotloader_scene_visibility.py](test_hotloader_scene_visibility.py.md).

```powershell
luajit tools\tests\hotloader_scene_visibility_harness.lua <scenario> packages\model-hotloader\mmd_hotloader\lua\mmdhl
```

It stubs the parts of Garry's Mod's API the server half of `secondary_collision.lua` uses (`hook`, `net`, `util`,
`game`, `ents`, `player`, `file.Open` over generated studio model bytes, `IsValid`, the render mode enums) and
`mmdhl` (one MMD ragdoll in `mmdhl.Entities()`, a natives table whose `CaptureSecondaryScene` records the owners,
excluded bodies, players and NPCs it is handed, and `SceneInterest` naming one region). It then loads the file whole
(`dofile`), places a scenario's entities (fields say how each is drawn: `nodraw`, `mode`, `color`, `model`, `groups`,
`scale`, `scripted`, `owner`, `children`, `mmd`, `nw2`, the scene flags) and runs the capture's `Tick` hook.

Scenarios: `hidden`, `visible_again`, `models`, `followers`, `characters`, `stand_ins`, `living`, `no_model`, `children` (the
table in the test's notes says what each checks). Prints `PASS <scenario>`; a failed check raises
`FAIL <scenario>: <why>` (exit code 1). Writes no file.
