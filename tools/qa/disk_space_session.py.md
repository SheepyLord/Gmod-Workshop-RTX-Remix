# disk_space_session.py

The companion's disk space notice ([ADR 0260](../../docs/decisions/0260-the-package-says-when-the-disk-is-too-full-for-updates.md),
[`disk_space.lua`](../../companion/nativeloader/lua/nativeloader/menu/disk_space.lua.md)) in a locked PoC RTX session:
the RTX client module's measure of the game's drive and of the deployed packages, read at the main menu of a real RTX
start, and a screenshot of each card's preview there.

```powershell
python tools\build_package.py --out out\diskfull-poc\pkg
python tools\qa\disk_space_session.py --evidence out\diskfull-poc\run1 --package out\diskfull-poc\pkg\<name>.gma
python tools\qa\disk_space_session.py --evidence out\diskfull-poc\run2 --package <same> --language ja --command "nativeloader_disk_space_preview low"
python tools\qa\disk_space_session.py --evidence out\diskfull-poc\run1 --rollback   # after an interrupted run
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's (or the main checkout's) `out` |
| `--package` | The RTX package (`.gma`) the loader deploys |
| `--label` | The run's name (`menu`) |
| `--language` | The companion's language for the cards, written to the PoC's `data/nativeloader_companion/language.txt` (the menu realm's fallback; never `gmod_language`, which Steam Cloud carries to the field) |
| `--command` | A menu console command instead of the four defaults (repeatable): `nativeloader_disk_space_status`, then `nativeloader_disk_space_preview need`, `full` and `low` |
| `--map`, `--width`, `--height`, `--timeout`, `--hang-grace` | As [poc_session.py](../poc_session.py.md) `run` |
| `--lock-timeout` | Seconds to wait for the shared PoC lock (6 hours) |
| `--keep-copies` | Keep the PoC's preserved originals in the evidence |
| `--rollback` | Restore the PoC after an interrupted run |

## What it does

1. Takes the main checkout's `out\r10\poc.lock` (as [mmd_player_session.py](mmd_player_session.py.md)) and refuses to
   start while a PoC game runs; records the PoC's `user.conf` hashes and the game's video registry values; snapshots
   the depot files ([field_snapshot.py](../field_snapshot.py.md)); moves the PoC's own loader state, add-ons, data and
   settings into `<evidence>\originals` (vr_session's `preserve`).
2. Installs this checkout's Release loader with the package allowed and RTX on, ends a running field game (the user's
   standing rule; `field-games.json` names it), and runs the game with `poc_session.py run --addons --workshop
   --menu-shot`, sending each command at the main menu with `--menu-console` (a screenshot `menu-<n>.png` three
   seconds after each), then loads the map and quits.
3. Writes `<evidence>\summary.json`: the run's result, the menu commands and their screenshots, the console lines about
   disk space and the client module (`[nativeloader] disk space: ...`, `[NativeLoader RTX menu] ...`), the module's free
   and total MiB from the first line, and Python's free space of the PoC's drive before the run. Restores the PoC and
   the video settings, checks `user.conf`, removes the bulky copies unless `--keep-copies`.
4. Prints the lines, both measures and each command with its screenshot.

**Exit:** 0 when the run finished (its game may still have failed: see `summary.json`); 1 on an error, with the PoC
restored when no game still runs (otherwise `--rollback` after the game ends). **Side effects:** the PoC's state is
moved away and back; the field game is ended; nothing in the field install is written.
