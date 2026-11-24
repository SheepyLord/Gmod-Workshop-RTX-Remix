# game_rescan_session.py

A locked PoC RTX session for the RTX fixes' imported game PBR when a model is imported again in the same game session
([ADR 0263](../../docs/decisions/0263-a-re-import-looks-at-the-models-folder-again.md), the user's report of
2026-11-24: "When I forgot to put PBR into the folder of a pmx, and I reimported it in the same session, PBR are not
applied."). A game-rip character (a PMX whose folder holds the game's own maps, `<stem>_N`, `_MRA`, `_P` ...) is copied
into the evidence without its maps and imported through the Model Hotloader's own library flow, spawned in view, and
ToPBR's view of each of its materials (`MaterialPipeline.ToPBR.GetGameMaterial`) is read until it settles. Then the maps
are copied into the copy's folder, as the player does, the same PMX is imported again (the same asset id: the id comes
from the model's own content, not from the maps beside it) and the views are read again.

```powershell
# from a worktree with a Release build (tools\build.ps1 -Config Release); the package from build_package.py
py -3 -I tools\qa\game_rescan_session.py --evidence <main checkout>\out\game-rescan\fix1 --package out\dist\<package>.gma --model <models>\<character folder>
py -3 -I tools\qa\game_rescan_session.py --evidence <main checkout>\out\game-rescan\old1 --package <the package before the fix>.gma --model <models>\<character folder> --expect-none
py -3 -I tools\qa\game_rescan_session.py --evidence <same folder> --rollback   # after an interrupted run
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's or the main checkout's `out` |
| `--package` | The RTX package to install (`.gma`) |
| `--model` | A game-rip character's folder; it is copied into the evidence and never changed |
| `--pmx` | The PMX inside it (default: the largest one) |
| `--hold` | Files the first import must not see, relative to `--model`, an `fnmatch` pattern (repeatable). Default: every image (`.png`, `.bmp`, `.tga`, `.jpg`) whose stem ends in `_n`, `_hn`, `_mra`, `_p`, `_e`, `_id` or `_hm`, the endings ToPBR reads as a game's maps |
| `--settle` | Seconds each reading may take to settle (default 240) |
| `--expect-none` | Judge the old behaviour, for a package before the fix: no game maps after the second import either |
| `--lock-timeout` | How long to wait for `out\r10\poc.lock` (6 hours) |
| `--keep-copies` | Keep the PoC's moved originals and the snapshot's copies after a verified restore |
| `--rollback` | Restore the PoC from an interrupted run's evidence |

## What it does

1. Takes the main checkout's `out\r10\poc.lock` (as [mmd_player_session.py](mmd_player_session.py.md) does), copies
   the model into `<evidence>\model\<folder>` and the held-back maps into `<evidence>\held` (the same relative
   paths), records the hashes of every `user.conf` (they must not change) and writes `plan.json`.
2. Snapshots the PoC ([`field_snapshot.py`](../field_snapshot.py.md)), moves its state into `originals\`
   ([vr_session.py](../vr_session.py.md)'s `preserve`: a fresh data folder and Remix mods, so ToPBR's registry and
   choices start empty), installs the package ([`poc_session.py`](../poc_session.py.md) `install --allow-local
   --remix on --replace-config`) and ends a running field game ([mmd_reimport_session.py](mmd_reimport_session.py.md)'s
   `end_field_games`).
3. Starts `poc_session.py run --addons --map gm_construct --width 1600 --height 900 --lua-shots 2400` and drives the
   game through its console as
   `mmd_reimport_session.py` does (Lua sent in console lines, markers read from this session's own `console.log`,
   found anywhere in a line and their JSON read up to its end: the module's worker thread can print into the middle of
   a console line, as its rescan line did right after `NLRS_IMPORTED`): sends
   [game_rescan_probe.lua](game_rescan_probe.lua.md), `sv_cheats 1`, `ai_disabled 1`, `engine_no_focus_sleep 0`, and
   holds the RTX sky at 14:00 (`nativeloader_sky_time_passes 0`, `nativeloader_sky_time 14`; the probe records both
   first and sets them back before the game quits, `NLRS.Restore()`); imports the PMX (`NLRS_IMPORTED`), spawns the character as a frozen citizen (`NLRS_READY`)
   with a camera in front of it,
   and reads the views every three seconds until their counts and the converting count (`RTXGamePBRProgress`) have not
   changed for 20 seconds with nothing converting (`before`); screenshot `01-no-maps.png`.
4. Copies the held-back maps into the model's folder, imports the PMX again and reads the views the same way (`after`);
   screenshot `02-after-reimport.png`; counts, in the console after the second import, the module's
   `[MaterialPipeline::ToPBR] Game maps looked at again` and `Imported game maps:` lines.
5. Ends the game (`NL_SHOT_DONE`), keeps `console.log` and the probe's reports (`results\states_NNN.json`), restores
   the PoC (vr_session's `restore`) and the video settings, checks the `user.conf` hashes.

Verdict in `summary.json` (`verdict`, `reasons`, `summary`) and on the last line. By default (the fix) it passes when
the second import gave the same asset id, no material had game maps before the maps were copied, the first reading
settled, at least one material shows `automatic` afterwards, and both console lines appear after the second import.
With `--expect-none` (the old behaviour) it passes when no material got game maps after the second import.

Exit code 0 on a pass, 1 on a failure, other codes on an error. Side effects: the PoC is used, its state put back
afterwards; the field game is ended if one runs; the model folder named by `--model` is only read.
