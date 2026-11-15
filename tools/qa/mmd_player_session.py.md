# mmd_player_session.py

Times the Advanced MMD Animation Player (the character motion importer's tool, `mmd_vmd_npc`) in a locked
PoC RTX session, the way a player uses it: the spawn menu and the tool's panel, motions picked in its list,
yourself selected with R, motions assigned to two imported characters spawned as NPCs by clicking them with
the tool gun, a click that takes one off again, the selection cleared. Written for the user's report of
2026-11-14 ("selection, assignment ... always result in a few seconds of hangs"); the client half is
[mmd_player_probe.lua](mmd_player_probe.lua.md), the server half [mmd_player_server.lua](mmd_player_server.lua.md).

```powershell
# Once: a copy of the field's motion library (read only there) in this worktree's out.
robocopy H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\mmd_vmd_npc out\mmd-player\field-data\mmd_vmd_npc /E /COPY:DAT /DCOPY:T /MT:16
python tools\build_package.py --out out\mmd-player\pkg-before
python tools\qa\mmd_player_session.py --evidence out\mmd-player\before --package out\mmd-player\pkg-before\<name>.gma `
    --label before --data out\mmd-player\field-data --workshop
python tools\qa\mmd_player_session.py --evidence out\mmd-player\before --rollback   # after an interrupted run
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's (or the main checkout's) `out` |
| `--package` | The RTX package (`.gma`) the loader deploys: build one from `packages\` with `build_package.py` |
| `--label` | The run's name; its files go to `<evidence>\<label>\` |
| `--data` | A folder holding a copy of the field's `data\mmd_vmd_npc` (motions, built caches, settings) as `mmd_vmd_npc` |
| `--workshop` | Mount the Workshop subscriptions, as the field game does (the PoC shares the Steam library's) |
| `--manager` | Also open the Motion Manager window before the steps |
| `--tab` | Also open the RTX package's Motion importer creation tab (its embedded Motion Manager) |
| `--features` | After the steps, check the new options in the game (below) |
| `--no-steps` | Skip the timed click-through (with `--features`: the checks alone, a shorter run) |
| `--motions A B` | The two motion ids to pick (default: a third and two thirds down the sorted list) |
| `--window` | Seconds measured after each action (4) |
| `--settle` | Seconds after the NPCs spawn before the first step (8) |
| `--map`, `--width`, `--height`, `--timeout`, `--hang-grace`, `--extra` | As [poc_session.py](../poc_session.py.md) `run` |
| `--lock-timeout` | Seconds to wait for the shared PoC lock (6 hours) |
| `--keep-copies` | Keep the PoC's preserved originals and generated files in the evidence |
| `--rollback` | Put the motion copy back and restore the PoC after an interrupted run |

## What it does

1. Takes the shared `out\r10\poc.lock` of the main checkout (polled four times a second: other tasks'
   queued holds retake it within a second of a release) and refuses to start while a PoC game runs.
2. Records the PoC's `user.conf` hashes and the game's video registry values, snapshots the depot files
   ([field_snapshot.py](../field_snapshot.py.md)) and moves the PoC's own loader state, add-ons, data,
   settings, Lua binaries and Remix mods and logs into `<evidence>\originals` (vr_session's `preserve`).
3. Copies the PoC's own character library (`data\mmd_hotloader`, the imported character the NPCs are made
   of) back into the empty data folder, and moves the `--data` copy in as `data\mmd_vmd_npc` (a rename on
   the same volume; `data-moved.json` is its receipt).
4. Installs this checkout's Release loader with the package allowed and RTX on
   (`poc_session.py install --allow-local ... --remix on`), ends a running field game (the user's standing
   rule; `field-games.json` names it), and runs the game with `poc_session.py run --addons --lua-manual`:
   the server half waits in the session's fresh data folder as `nlmp_probe/server.txt` and one console line
   runs it (`lua_run RunString(file.Read(...))`: as hex console lines it outgrew Windows' 32,767-character
   command line), the client half travels as the `--lua` file with the settings line `NLMP_SETTINGS = {...}`
   in front. `engine_no_focus_sleep 0` keeps an unfocused window at full speed.
5. Copies the probe's results (`data\nlmp_probe`) to `<evidence>\<label>\results`, writes
   `<label>\summary.json` and `<label>\session.json`, moves the motion copy back (`data-back.json` lists any
   file the game changed in it), restores the PoC and the video settings, checks `user.conf`, and removes
   the bulky copies unless `--keep-copies`.
6. Prints one line per step: the longest frame, the frames over 100 ms, the median frame, and the add-on
   functions that took the most time on the client and the server.

## Results

`<label>\results\step_NN_<step>.json`: `frames` (`max_ms`, `median_ms`, `over_50`, `over_100`,
`over_250`, `longest_ms`, `all_ms`), `sent` (the add-on's net messages the step sent, by name), `client` and
`server.stats` (each timed call's `calls`, `incl_ms`, `self_ms`, `max_ms`, sorted by self time),
`server.longest_ticks_ms`. `summary.json` in `results` lists the steps and the setup (the NPCs' model, bones,
sequences, flexes, whether they are imported characters).

With `--features`, `results\features.json`: `build` (a four-second test dance, both arms held out from frame 20
to 100 and the eyes closed from 30 to 90, built for the imported character), `followers` (what the engine's
`CreateBoneFollowers` makes for that NPC), `collision_on` and `collision_off` (the dance with
`mmd_vmd_npc_ragdoll_collision` 1 and 0: the colliders, the box's group and hull collisions, traces through the
held-out hands, a player hull into the box's empty corner and into the head, the Model Hotloader's captured scene,
and the state after the stop), `flexes_kept` and `flexes_reset` (`mmd_vmd_npc_keep_flexes` 1 and 0: the weights of
笑い, set to 0.6 and not driven, and まばたき, driven, after a selection, at the start, mid-dance and after the
stop) and `timeline` (the debug window's timeline: its range and widths, one set position, a held sweep of 51
positions with the requests it sent, and the lists after the knob is let go).

**Exit:** 0 when the run finished (its steps may still have failed: see the printed lines and
`action_error`); 1 on an error, with the PoC restored when no game still runs (otherwise `--rollback`
after the game ends). **Side effects:** the PoC's state is moved away and back; the field game is ended;
nothing in the field install is written.
