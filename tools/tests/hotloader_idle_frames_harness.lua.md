# hotloader_idle_frames_harness.lua

A LuaJIT harness for the Model Hotloader's per-frame work with no character model, and with a few
([ADR 0273](../../docs/decisions/0273-the-hotloaders-frames-cost-nothing-without-a-character.md)), run by
[test_hotloader_idle_frames.py](test_hotloader_idle_frames.py.md).

```powershell
luajit tools\tests\hotloader_idle_frames_harness.lua <scenario> packages\model-hotloader\mmd_hotloader\lua\mmdhl
```

It stubs the parts of Garry's Mod's API the client's `client.lua`, `carrier.lua` and `native_render.lua` use while
they load and while frames run (`hook` with `hook.Run`, `ents.GetAll`, `ents.FindByClass` and `ents.CreateClientside`
counted, `FrameNumber`, `RealTime` and the other clocks on a fake time, convars, `Vector`, `IsValid`, `LocalPlayer`,
`math.Clamp`) and `mmdhl` (the natives' `PrepareFrame` and `PruneRenderCache` counted; `UpdateClientInstances` as
`instances.lua` begins it, a fresh entity list; `HasClientInstances` set by a scenario). Entities are tables whose
`GetNW2String('MMDHLAsset')` is counted: each is one check of whether an entity carries a model. Spawning one runs
`OnEntityCreated`, removing it `EntityRemoved`; a scenario gives one a model with or without the
`EntityNetworkedVarChanged` hook, which runs before the value changes as in the game.

The three files are loaded whole, with GMod's `continue` turned into LuaJIT's `goto` to a label put before the end of
its innermost loop (strings and comments copied as they are). A frame runs `Think` (`MMDHL.NativeVisuals`,
`MMDHL.RenderMode`), `PreRender` (`MMDHL.Shadows`) and the opaque and translucent draw hooks (`MMDHL.PendingVisuals`,
`MMDHL.Models`), at sixty frames a second.

Scenarios: `idle`, `measure` (prints the counts of a frame on a map of 661 candidates with no character model and
with three; it also runs against the files before ADR 0273, which have neither idle helper: give it a folder holding
those three files), `spawn`, `change`, `missed` (prints the frames the turn took), `transmit`, `removed`, `order`,
`preview`, `full_update`, `legacy`, `native_idle`; and in the server realm (`SERVER` true, only `carrier.lua` loaded,
`CreateConVar` and `util.AddNetworkString` stubbed, the natives' `SetMorphs` recorded) `server_pose` and
`server_pose_unannounced`, which run the `MMDHL.NativePose` tick at 66 ticks a second (the table in the test's notes
says what each checks). Prints `PASS <scenario>`; a failed check raises `FAIL <scenario>: <why>` (exit code 1). Writes
no file.
