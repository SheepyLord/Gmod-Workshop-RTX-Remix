# loading_status.lua

R24 ([ADR 0134](../../../../../docs/decisions/0134-what-a-map-load-is-doing.md)): what the game is doing while a map
loads. Garry's Mod's loading screen says only "Loading resources" or "Starting Lua", and during a blocking phase such
as the Lua start the engine does not repaint it at all. Since [ADR 0214](../../../../../docs/decisions/0214-after-ready-to-play-the-overlay-stays-until-the-game-runs.md)
the overlay stays after "Ready to play!" until the game runs, and since
[ADR 0215](../../../../../docs/decisions/0215-the-loads-estimate-learned-from-the-loads-before.md) it shows how long the
wait should take, learned from the loads before.

- **Where it runs.** In the menu realm of an RTX start, run once by the RTX client module like the companion's other
  menu scripts ([multiplayer_notice.lua](multiplayer_notice.lua.md)). It requires the engine guard module there
  (`gmsv_nlengineguard_win64.dll`, [engine_guard](../../../../../engine_guard/README.md)): its guard against material
  fallback loops is then in place before any map loads, and its load overlay is available (`LoadStart`,
  `LoadHeading`, `LoadStatus`, `LoadExpect`, `LoadSettling`, `LoadEnd`, `LoadTimes`, `LoadTimesSave`, menu realm only).
  Without the module the console says why and nothing else changes; with R24's module (no `LoadSettling`) the
  overlay ends with the engine's load as it did then, untimed.
- **Following a load.** A `Think` hook of the menu realm sees the stock `IsInLoading()` become true (the overlay
  starts, "Loading…"), passes the stock status line `GetLoadStatus()` on when it changes (trimmed), and sees the
  engine's load end. The engine draws frames between its blocking phases, so the hook runs then; the overlay's own
  thread carries it through them. `GameDetails` (wrapped; the stock function always gets every argument) names the
  map ("Loading gm_construct") or the server and the map when joining one ("Joining <server> · <map>"); a name that
  came at most 10 s before the load is seen is the overlay's first line. A game started here (single-player, or a
  listen server) stays "Loading <map>" for the whole load: the engine names its own server too ("My Garry's Mod
  Server") later in the load, when `IsHostingGame()` can already read false, so a call while hosting, or for one
  player, marks the load as hosted until it ends. The loading panel itself is never touched (made early, it would sit
  over the menu; the engine keeps its own reference to it).
- **After the engine's load (ADR 0214).** "Ready to play!" is the engine's last status, and the menu's
  `IsInLoading()` ends with the loading panel, while the main thread still runs the client's `InitPostEntity`, add-ons'
  timers and Remix's first frames. When the load ends with a game (`IsInGame()`, within a second; else the load was
  cancelled or refused and the overlay ends), the script calls `LoadSettling()` and the status reads "The map has
  loaded; the game is starting". Each `Think` measures the gap since the last one: a gap longer than three times the
  median of the last sixteen (at least 0.25 s, at most 1 s) is a freeze. Two seconds without one end the wait (`LoadEnd`),
  as does `SETTLE_LIMIT` (120 s). The game ending or the next load beginning ends it untimed.
- **The overlay** (drawn by the module's own thread): the heading and the time so far; the estimate's row; the stock
  status; what the main thread is doing ("RTX Remix is preparing the scene", "Running add-on scripts", "Building the
  spawn menu", "Loading game files"; classed by the module); "Lua: <file running>" and "File: <game file being
  read>", sampled from the main thread four times a second. It appears after 1.5 s of a load.
- **The Workshop's work (ADR 0214).** GMod's menu hooks `WorkshopSubscriptionsProgress`, `WorkshopDownloadTotals`,
  `WorkshopExtractProgress` and `WorkshopStart`/`WorkshopEnd` (added under the name `NativeLoaderLoadStatus`, returning
  nothing) put "Workshop: fetching subscriptions (120 of 774)", "Workshop: downloading add-ons (3 of 10)", "Workshop:
  extracting <title>" or "Workshop: updating add-ons" after the status while the overlay is up; a word older than ten
  seconds is dropped. The overlay does not wait for the Workshop.
- **The estimate (ADR 0215).** At menu start the script reads the history through `LoadTimes()`
  (`garrysmod/data/nativeloader/load_times.txt`). `Eta.estimate` gives the engine's load and the wait after it, from
  this map's newest five loads (their median, each scaled to today's add-on count and first-load state) or, for a map
  not loaded before, from the machine's other maps (one point per map, fitted to the map's size), with a confidence
  ("good" or "rough"); nothing without a load of the same kind (a server joined, or a game started here).
  `LoadExpect(seconds, confidence)` passes the whole wait's expected length at the start, again when `GameDetails`
  names the map, and again when the engine's load ends (its actual length plus the wait expected after it). The window
  counts down by itself. A load timed to its end is added to the history, which `LoadTimesSave(text)` writes back
  (at most ten loads per map and 200 in all); a load that ended without a game, untimed, or a demo is not.
- **The summary.** At the end the console gets one English line: `[nativeloader] map loaded in 24.1 s, then 7.1 s until
  the game ran steadily (31.2 s in all; expected about 30 s); the main thread: Lua 12.0 s, game files 4.0 s, RTX Remix
  3.2 s; Lua files that ran longest: lua/arc9/shared/sh_atts.lua (5.5 s), ...` (activities and files seen for at least
  half a second, at most three files). A cancelled load says "the map load ended without a game after N s", a
  game that ended or a load that followed say so. `NativeLoaderLoadStatus` keeps `loads`, `last` (the module's summary),
  `history`, `estimate` and the estimator `Eta` in the menu realm.
- **The load accelerator (R26, [ADR 0140](../../../../../docs/decisions/0140-the-load-accelerator.md)).** When
  [`load_accel.lua`](load_accel.lua.md) has loaded the `nlfsaccel` module (`NativeLoaderLoadAccel`), the status line
  goes on with "  ·  N file lookups answered from memory" (translated), counted from the load's start, and the
  summary ends with "; the load accelerator answered N file lookups from memory".
- **Off switch.** `nativeloader_load_overlay 0` (archived): no overlay, no summary and nothing timed or written. The
  words are translated from the companion's catalog (`nativeloader_language`, read from the copy the companion keeps
  for the menu in `data/nativeloader_companion/language.txt` since the menu realm cannot see that client convar, else
  `gmod_language`) through the module's read API, and passed to the module as `LoadStart`'s labels.

Tested by [`tools/tests/test_loading_status.py`](../../../../../tools/tests/test_loading_status.py.md), which also checks
that no companion menu script uses a name GMod's Lua reserves (`continue`).
