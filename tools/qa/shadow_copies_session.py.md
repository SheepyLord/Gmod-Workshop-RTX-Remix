# shadow_copies_session.py

Switches Local player shadow (the RTX fixes' body and weapon copies, `rtx_pseudoplayer` and `rtx_pseudoweapon`) on
and off in a locked PoC RTX session, and records each state: a screenshot, the frame times (a path-traced frame costs
far more than a raster one) and the switches' values. On the server it names every entity that has a model and no
model scale, the answer the Model Hotloader's scene capture could not compare. Written for the follow-up of
2026-11-21 ([shadow-copies-report.md](../../docs/handover/shadow-copies-report.md)).

```powershell
python -I tools\qa\shadow_copies_session.py --evidence out\lshadow\run1 --package out\packages\gmod-rtx-remix-<version>.gma
python -I tools\qa\shadow_copies_session.py --evidence out\lshadow\run2 --package <gma> --order weapon-first
python -I tools\qa\shadow_copies_session.py --evidence out\lshadow\run3 --package <gma> --character --player-model
python -I tools\qa\shadow_copies_session.py --evidence out\lshadow\run4 --package <gma> --weapon gmod_tool --hour 13
python -I tools\qa\shadow_copies_session.py --evidence out\lshadow\run1 --rollback   # after an interrupted run
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's `out` (refused otherwise, or when it is not empty) |
| `--package` | The RTX package (`.gma`) to deploy in the PoC |
| `--label` | The run's name in the evidence (default `run`) |
| `--order` | `body-first` (default) or `weapon-first`: which copy is switched on first; `third-person`: the third-person sequence; `diagnose`: the weapon copy's diagnostic sequence; `verify`: the check of ADR 0251 and 0252 (below) |
| `--character` | Before the first shot, the PoC library's first imported character as an NPC in front of you (the Model Hotloader's scene capture then classifies what is near it) |
| `--player-model` | With both copies on, that character as your own model (a step of its own) |
| `--weapon` | A weapon class to hold from the start, given if missing (`gmod_tool`: the tool gun draws a screen of its own) |
| `--hour` | Hold the time of day at this hour for the run (`nativeloader_sky_time_passes 0`, `nativeloader_sky_time <hour>`), so every shot has the same light |
| `--console` | A console command after the map, before the probe (repeatable) |
| `--settle`, `--wait` | Seconds before the first shot (15) and after each switch before its shot (12) |
| `--map`, `--width`, `--height` | `gm_construct`, 1600x900 |
| `--timeout`, `--hang-grace` | The map start deadline (1200 s: a fresh deployment unpacks) and the hang grace (600 s) |
| `--lock-timeout` | How long to wait for `out\r10\poc.lock` (6 h) |
| `--keep-copies` | Keep the evidence's bulk copies after a verified rollback |
| `--rollback` | Restore the PoC after an interrupted run |

The steps, each a wait, a state line and a screenshot, after `01_before`:

- `body-first` and `weapon-first`: the first copy on (`02_body_on` or `02_weapon_on`), `03_both_on`.
- `third-person`: a view 120 units behind you that draws you (`drawviewer`, as the motion importer's camera): copies
  off (`02_third_off`), the weapon copy (`03_third_weapon`), both (`04_third_both`), then first person with both
  (`05_first_both`).
- `diagnose` (first person; hold the tool gun with `--weapon gmod_tool`): the body copy (`02_body_on`), the weapon copy
  (`03_weapon_on`), the weapon copy entity's own draw left out (`04_entity_hidden`), its client-side model's too
  (`05_model_hidden`), both drawn again with the tool gun screen add-on off (`06_drawn_screen_off`, `dts_enabled 0`), the
  camera SWEP in hand (`07_camera_swep`), the tool gun again with the weapon copy's private textures
  (`08_private_textures`, `rtx_pseudoweapon_unique_hashes 1`).
- `verify` (hold the tool gun with `--weapon gmod_tool`): the body copy (`02_body_on`), both copies (`03_both_on`), both
  in third person (`04_third_both`), the gravity gun in first person (`05_gravity_gun`), the tool gun again
  (`06_tool_gun_again`: the weapon copy makes its textures anew).
- With `--player-model`, `06_player_model`; at the end the copies off (`07_both_off`, or `09_both_off` after `diagnose`).

At the end the switches, `rtx_pseudoweapon_unique_hashes`, `dts_enabled` and the sky's clock
(`nativeloader_sky_time_passes`, `nativeloader_sky_hour`) go back to the values the session found.

What it does, holding `out\r10\poc.lock` (the shared PoC lock, polled four times a second as
[mmd_player_session.py](mmd_player_session.py.md) does):

1. Snapshots the PoC (`tools\field_snapshot.py`), sets its folders aside (`vr_session.preserve`), puts the PoC
   library's imported characters back into the fresh data folder and deploys the package with Remix on
   (`poc_session.py install --replace-config`). It does not end the field game: the PoC starts with `-multirun`
   beside it.
2. Writes [shadow_copies_probe.lua](shadow_copies_probe.lua.md) with its settings in front (`NLSH = {...}`) and
   [shadow_copies_server.lua](shadow_copies_server.lua.md) as `data\nlshadow\server.txt`, then runs
   `poc_session.py run --addons --lua <probe> --lua-shots` on the map, the server half started with
   `lua_run RunString(file.Read("nlshadow/server.txt","DATA"),"nlshadow_server")`.
3. Copies `data\nlshadow` (`client.json`, `server.json`) into `<evidence>\<label>\results`, writes `summary.json`
   and `session.json`, restores the PoC (`vr_session.restore`, a verified rollback) and the game's video settings,
   checks that no `user.conf` changed, and removes the bulk copies unless `--keep-copies`.

**Writes:** the evidence folder: `plan.json`, the snapshot and rollback receipts, `poc\` (the session's record, logs
and `poc\<label>\shot-<nn>-<step>.png`), `<label>\results\`, `<label>\summary.json`; the PoC only for the run, put
back after it. **Prints** one line per step (the switches, the copies counted, the median and 90th-percentile frame
time), each entity without a model scale and the screenshots' folder.

**Exit:** 0 when the run and the rollback finished (the game's own exit 0 or 1 is accepted, its record says which);
1 with a message when the lock, the deployment, the run or the restoration failed.
