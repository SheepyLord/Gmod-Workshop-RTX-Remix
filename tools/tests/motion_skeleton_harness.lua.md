# motion_skeleton_harness.lua

The LuaJIT side of [test_motion_skeletons.py](test_motion_skeletons.py.md): loads the Character Motion Importer's
`sh_core.lua`, `sv_cache.lua` and `sv_skeletons.lua` with the parts of Garry's Mod they use stubbed, then runs one
scenario ([ADR 0259](../../docs/decisions/0259-imported-characters-share-their-builds-across-carriers.md): a Model
Hotloader character's carriers share their built animations under a build model).

```powershell
luajit tools\tests\motion_skeleton_harness.lua <scenario> packages\character-motion-importer\mmd_vmd_npc\lua\mmd_vmd_npc
```

Scenarios: `resize`, `reimport`, `persist`, `migrate`, `migrate_on_demand`, `mappings` (what each checks: the table
in [test_motion_skeletons.py.md](test_motion_skeletons.py.md)).

The stubs: an in-memory `data/` (`file.Read`, `Write`, `Exists`, `Delete`, `Rename`, `Time` and `Find` with a glob in
its last part, listing files and folders), `util.CRC` as the game's CRC-32 in decimal, a `util.SHA256` that gives
distinct texts distinct strings, a small JSON encoder and decoder, hooks, timers run by `tick`, and `SysTime` taking
2 ms a call, so the migration's 3 ms steps read two rigs each. A new session is a fresh load of the three files with
the same `data/`.

Rig manifests are made as the Hotloader writes them (`rig.cpp` identify, `rig_animation.cpp`): a seven-bone humanoid
with world rotations and positions composed from local offsets times the carrier's size, an actor's height
(`actorOrigin`) under the root, morphs with PMX and native indices, a Reference whose first four bones keep the
profile skeleton's offsets and the others the fitted ones, and the fields a carrier changes without changing its
skeleton (asset, name, materials, attachments, donor hash, generator). Built files are written as `sv_commands.lua`'s
`finalize_build` writes them, and the files of before the change under each carrier's own name.

**Output:** `PASS <scenario>`, exit 0; a failed check raises `FAIL <scenario>: <why>` (exit 1).
**Writes:** nothing on disk.
