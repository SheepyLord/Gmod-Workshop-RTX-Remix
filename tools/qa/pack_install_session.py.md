# pack_install_session.py

Times what a freshly subscribed content package costs in a locked PoC RTX session: the loader's deploy at the start
(from its log), the Remix runtime's mod load, and, in the game, the Model Hotloader installing the package's models
into a fresh library (as a new subscriber has none of them), frame by frame. The client half is
[pack_install_probe.lua](pack_install_probe.lua.md), deployed for the session as the add-on
`garrysmod/addons/zz_nlpack_probe` so it runs from the map's first frame.

```powershell
python tools\qa\pack_install_session.py --evidence out\<purpose>\run1 --package <RTX package>.gma --pack <content pack>.gma --label fresh
python tools\qa\pack_install_session.py --evidence out\<purpose>\run1 --rollback   # after an interrupted run
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's (or the main checkout's) `out` |
| `--package` | The RTX package (`.gma`) the loader deploys, as a local package (the published item's file, or one built from `packages\` with `build_package.py`) |
| `--pack` | The content package (`.gma`) under test, deployed as a second local package |
| `--label` | The run's name; its files go to `<evidence>\<label>\` |
| `--library` | Keep the PoC's own Model Hotloader library (default: a fresh, empty one) |
| `--seed-library` | A Model Hotloader data folder (`garrysmod\data\mmd_hotloader`, read only) whose library the install meets: each character's `manifest.json` and settings and the props (`static\assets`, `static\library`) are copied in; no model data, Workshop records or other state |
| `--spawnmenu` | Open the spawn menu two seconds after the spawn, on the Model Hotloader's tab (whose list follows the library's changes), so the models install with it open; the probe keeps it open until it ends |
| `--hotloader-lua` | A Model Hotloader `lua\mmdhl` folder whose `library.lua`, `workshop.lua` and `ui.lua` run over the package's for this session (a branch's change, before a package is built from it): copied beside the probe, which includes them before the map's first frame (the library window registered again, before the spawn menu makes one) |
| `--quiet` | Seconds without an install before the probe ends (10) |
| `--start` | Seconds after the spawn for an install to begin (180) |
| `--limit` | Seconds for the whole probe (1200) |
| `--long` | A long frame, in milliseconds (50) |
| `--map`, `--width`, `--height`, `--timeout`, `--hang-grace`, `--extra` | As [poc_session.py](../poc_session.py.md) `run` |
| `--lock-timeout` | Seconds to wait for the shared PoC lock (6 hours) |
| `--keep-copies` | Keep the PoC's preserved originals and the deployed files in the evidence |
| `--keep-field-game` | Leave a running field game alone, when another task's test uses it (its pids go to `<evidence>\field-games.json` as `kept`); the timings then share the computer with it |
| `--rollback` | Restore the PoC after an interrupted run |

## What it does

1. Takes the shared `out\r10\poc.lock` of the main checkout. A PoC game another task started without the lock is
   waited out (the PoC must then stay free for 90 s, so that task's next run starts first), up to `--lock-timeout`.
2. Records the PoC's `user.conf` hashes and video registry values, snapshots the depot files
   ([field_snapshot.py](../field_snapshot.py.md)) and moves the PoC's loader state, add-ons, data, settings, Lua
   binaries, Remix mods and logs into `<evidence>\originals` (vr_session's `preserve`): the first start deploys both
   packages afresh and the Model Hotloader's library is empty (with `--library`, the PoC's own is copied back; with
   `--seed-library`, the given library's listing; the counts go to `<evidence>\seeded.json`).
3. Installs this checkout's Release loader with both packages allowed and RTX on (`poc_session.py install
   --allow-local <package> --allow-local <pack>`), ends a running field game (the user's standing rule; not with
   `--keep-field-game`), writes the probe add-on and runs the game with `poc_session.py run --addons --lua-manual`: the
   injected Lua only says the probe is there; the probe ends the run with `NL_SHOT_DONE`.
4. Copies the probe's results (`data\nlpack_probe`) to `<evidence>\<label>\results`, keeps the loader's deploy lines
   and the runtime's `[RTX Mod Load]` lines in `<label>\loader-deploy.json`, writes `<label>\session.json`, restores the
   PoC and the video settings, checks `user.conf`, and removes the bulky copies (the deployed files) unless
   `--keep-copies`.
5. Prints the install's seconds and frames, each model's install time, the longest frames with what took them, the
   functions with the most time of their own, each library revision (how many characters `library.Add` listed) with
   when the library window was shown or hidden and the spawn menu's closes kept off, and each update of the library
   window (a rebuild of its list or rows brought up to date alone, ADR 0258) with its call's time, its frame and the
   next frame.

## Results

`<label>\results\result.json`: `started`, `done` and `seconds` (from the first frame a model installs to the last),
`installed` (each model: when, name, asset, package), `install_frames` (frames, over 50/100/250/1000 ms, the longest
and the sum, while models install), `before_install`, `median_ms`, `long_frames` (each frame over `--long`: when, how
long, whether a model was installing, how many were installed, its six costliest functions), `functions` (the 80
functions with the most time of their own: calls, self, inclusive and longest, in ms), `events`, `trace` (each call
of the install's native steps: when, the function, its milliseconds, its first two arguments and first result; see
the probe's `.md`), `library_updates` (each frame in which the library window built its list again or added rows:
when, `kind` `rebuild` or `rows`, the call's inclusive milliseconds, the frame's and the next frame's, busy, installed,
the frame's costliest functions) and `library` (the entries in the library at the end).
`<label>\results\frames.csv`: every frame (`t`, `ms`, `busy`, `installed`). With `--hotloader-lua`, the three files
that ran are kept in `<label>\`.

**Exit:** 0 when the run finished (see the printed lines); 1 on an error, with the PoC restored when no game still
runs (otherwise `--rollback` after the game ends). **Side effects:** the PoC's state is moved away and back; the field
game is ended (unless `--keep-field-game`); nothing in the field install is written.
