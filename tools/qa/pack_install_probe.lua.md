# pack_install_probe.lua

Client half of [pack_install_session.py](pack_install_session.py.md): the driver writes it, with the settings line
`NLPACK_SETTINGS = {...}` in front, as the add-on `garrysmod/addons/zz_nlpack_probe` for one PoC session
(`lua/autorun/client/zz_nlpack_probe.lua`), so it runs from the map's first frame. Never install it as an add-on of your
own.

It times the Model Hotloader installing a freshly deployed model package (`mmdhl.workshop`):

- **Every frame** (a `Think` hook): its length, whether a model is installing (`mmdhl.workshop.Busy()`) and how many
  are installed.
- **Each model** as it finishes, through `mmdhl.workshop.OnInstalled`: when, its name, asset and package.
- **What took the time**, with each call's own time apart from what it calls, for the run and for each frame: the
  Model Hotloader's native module (`mmdhl.native`), library, prop library, terms and workshop functions, and the
  library window's list rebuild (`ui.Library.Refresh`); GMod's `file`, `util` (JSON, compression, SHA-256),
  `notification` and `vgui.Create` calls; every hook listener with a name (wrapped again every two seconds, for
  listeners added later); timers, named by their source line. A frame over `long` milliseconds keeps its six costliest
  functions.
- **The install's steps** (`trace`): each call of `BeginSharedFile`, `CommitSharedFile`, `SharedFileMatches` and
  `StartAssetCheck`, and each `PollSharedCommit` and `PollAssetCheck` that did not answer `false` (still busy): when,
  its milliseconds, its first two arguments and its first result. A transfer's handle joins its begin, commit and end;
  a check's handle its start and end.

Settings: `quiet` (seconds without an install before it ends, 10), `start` (seconds to wait for an install to begin,
120), `limit` (seconds for the whole probe, 900), `long` (a long frame in milliseconds, 50), `spawnmenu` (open the spawn
menu two seconds after the spawn, on the Model Hotloader's tab), `override` (file names under `lua/nlpack_override/`
of the probe's add-on, included as the probe loads, over the package's Model Hotloader files: the driver's
`--hotloader-lua`).

It ends when no model has installed for `quiet` seconds after one did, when none began within `start` seconds, at
`limit`, or when the game shuts down: it writes `data\nlpack_probe\result.json` (the summary the driver prints; see its
`.md`) and `frames.csv`, and prints `NLPACK_DONE <reason>` and `NL_SHOT_DONE`.

Caveat: while a map loads, the load accelerator wraps every hook listener added (`load_callbacks.lua`), the probe's
own wrappers too, and the probe then wraps that wrapper again two seconds later: a listener added during the load
ends up a few wrappers deep, so its `calls` count several times per frame and `incl` overlaps. Self times hold, and the
extra cost per frame is small and the same in every run of one map.

Console output: `NLPACK_PROBE_READY`, one `NLPACK_EVENT <seconds> <kind> <json>` line per event (`init_post_entity`,
`busy`, `idle`, `installed`, `spawnmenu_open`, `spawnmenu_tab`, `no_workshop_api`, `finish`), `NLPACK_DONE`,
`NL_SHOT_DONE`. Side effects:
the wrappers stay in place until the game quits; the `data\nlpack_probe` files.
