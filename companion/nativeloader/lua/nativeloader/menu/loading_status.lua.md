# loading_status.lua

R24 ([ADR 0134](../../../../../docs/decisions/0134-what-a-map-load-is-doing.md)): what the game is doing while a map
loads. Garry's Mod's loading screen says only "Loading resources" or "Starting Lua", and during a blocking phase such
as the Lua start the engine does not repaint it at all.

- **Where it runs.** In the menu realm of an RTX start, run once by the RTX client module like the companion's other
  menu scripts ([multiplayer_notice.lua](multiplayer_notice.lua.md)). It requires the engine guard module there
  (`gmsv_nlengineguard_win64.dll`, [engine_guard](../../../../../engine_guard/README.md)): its guard against material
  fallback loops is then in place before any map loads, and its load overlay is available (`LoadStart`,
  `LoadHeading`, `LoadStatus`, `LoadEnd`, menu realm only). Without the module the console says why and nothing else
  changes.
- **Following a load.** A `Think` hook of the menu realm sees the stock `IsInLoading()` become true (the overlay
  starts, "Loading…"), passes the stock status line `GetLoadStatus()` on when it changes (trimmed), and sees the load
  end (the overlay hides). The engine draws frames between its blocking phases, so the hook runs then; the overlay's
  own thread carries it through them. `GameDetails` (wrapped; the stock function always gets every argument) names the
  map ("Loading gm_construct") or the server and the map when joining one ("Joining <server> · <map>"); a name that
  came at most 10 s before the load is seen is the overlay's first line. A game started here (single-player, or a
  listen server) stays "Loading <map>" for the whole load: the engine names its own server too ("My Garry's Mod
  Server") later in the load, when `IsHostingGame()` can already read false, so a call while hosting, or for one
  player, marks the load as hosted until it ends. The loading panel itself is never touched (made early, it would sit over the menu; the
  engine keeps its own reference to it).
- **The overlay** (drawn by the module's own thread): the heading and the time so far, the stock status,
  "Lua: <file running>" and "File: <game file being read>", sampled from the main thread four times a second; it
  appears after 1.5 s of a load and hides at its end.
- **The summary.** At the end the console gets one English line: `[nativeloader] map loaded in 47.3 s; Lua files that
  ran longest: lua/arc9/shared/sh_atts.lua (5.5 s), ...` (files seen for at least half a second, at most three).
  `NativeLoaderLoadStatus.last` keeps it in the menu realm.
- **The load accelerator (R26, [ADR 0140](../../../../../docs/decisions/0140-the-load-accelerator.md)).** When
  [`load_accel.lua`](load_accel.lua.md) has loaded the `nlfsaccel` module (`NativeLoaderLoadAccel`), the status line
  goes on with "  ·  N file lookups answered from memory" (translated), counted from the load's start, and the
  summary ends with "; the load accelerator answered N file lookups from memory".
- **Off switch.** `nativeloader_load_overlay 0` (archived): no overlay and no summary. The words are translated from the
  companion's catalog (`nativeloader_language`, read from the copy the companion keeps for the menu in
  `data/nativeloader_companion/language.txt` since the menu realm cannot see that client convar, else
  `gmod_language`) through the module's read API.

Tested by [`tools/tests/test_loading_status.py`](../../../../../tools/tests/test_loading_status.py.md), which also checks
that no companion menu script uses a name GMod's Lua reserves (`continue`).
