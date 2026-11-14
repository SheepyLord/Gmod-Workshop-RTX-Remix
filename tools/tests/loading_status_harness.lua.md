# loading_status_harness.lua

Runs the companion's real `nativeloader/menu/loading_status.lua` (R24; ADR 0214 and 0215) under LuaJIT in a mocked
menu realm: the engine guard module's overlay functions (recorded; `LoadTimes` serves a history text the scenario sets
and `LoadTimesSave` keeps what the script writes), the stock `IsInLoading`, `IsInGame`, `GetLoadStatus`, `GameDetails`
and `IsHostingGame`, the menu's hooks per event (`Think` called by the harness on a mocked clock; the Workshop's hooks
called with GMod's arguments; a hook that returns a value fails the run, since it would end GMod's own),
`engine.GetAddons` (774 mounted), `engine.IsPlayingDemo`, `file.Size` (gm_construct is 10 MiB), convars,
`CreateConVar`, `SysTime` and the RTX client module's `__NATIVELOADER_MENU_API.read`. Frames are `Think` calls every
1/64 s; a freeze is one call after a jump of the clock.

Usage: `luajit loading_status_harness.lua <repo root> <scenario>`; prints `PASS <scenario>` or fails with a Lua error
(exit 1). Scenarios:

- R24: `load` (nothing while not loading; the start, the trimmed status sent once per change, the map's name; after
  the engine's load the overlay stays, "The map has loaded; the game is starting", through a 6 s freeze until two
  steady seconds; the console summary with the main thread's activities; the load saved to the history; the next
  load's rough estimate from it), `details-first` (a map named just before the load is seen is the first line; an old
  one is not), `joining` (a server's name and map), `local` (a single-player game and a listen server stay "Loading
  <map>" when the engine later names its own server and `IsHostingGame()` reads false, as in the PoC; the stock
  function gets every argument; the next load, a server joined, is named as one), `translated` (the catalog's words,
  the new labels included, the English where the catalog has none), `menu-compile` (the catalog through `RunString`
  without `CompileString`, as in GMod's menu realm), `saved-language` (the companion's language from the copy it keeps
  in `data/nativeloader_companion/language.txt`, its client convar not being visible in the menu realm), `off`
  (`nativeloader_load_overlay 0`: nothing shown, timed or written), `no-module` (no hook, and the console says why) and
  `not-menu`.
- ADR 0214: `cancelled` (the load ends without a game: waited out for a second, then ended untimed), `late-game` (the
  game is there half a second after the load: the wait goes on and is timed from the load's end),
  `left-while-settling` and `next-while-settling` (untimed, and the console says which), `capped` (freezes for ever:
  the wait ends at 120 s and is recorded as capped), `slow-frames` (two steady frames a second are a running game),
  `workshop` (the Workshop's fetching, downloading and extracting on the status line in both phases, not waited for,
  an old word dropped), `demo` (not timed), `old-module` (R24's module: the overlay ends with the engine's load, no
  estimate).
- ADR 0215: `estimate` (a history file of three maps and unreadable lines: the machine's rough estimate before the
  map is known, this map's good one after `GameDetails` with later loads scaled by the learned first-load factor, the
  engine's actual load plus the expected wait when it ends, "expected about 29 s" in the summary, unreadable lines not
  written back), `joined-history` (loads of a game started here give no estimate for a server joined; the joined load
  is recorded with its server), `eta` (the estimator alone: medians, clipping, map and server names, the file's round
  trip and the lines it leaves out, numbers out of any real range in a hand-edited file, the bounds per map and in all, one load or two, an outlier, the newest five, the
  add-on scaling, the first-load factor, the size fit over four maps and the clamps).

No files are read or written besides the script. Run by [`test_loading_status.py`](test_loading_status.py.md).
