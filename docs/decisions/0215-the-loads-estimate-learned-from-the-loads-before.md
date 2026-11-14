# 0215: The load's estimate, learned from the loads before

- Status: Accepted 2026-11-14 on the branch `qol-load` (the user's QoL request; not merged; the in-game checks are the
  user's, see the [report](../handover/load-eta-report.md)).
- Context: the user: "The map loading should also get an ETA estimate, it can be trained from previous map loads,
  please design this part to make user able to expect the wait time." The wait the user sees is the engine's load and
  then the wait until the game runs ([ADR 0214](0214-after-ready-to-play-the-overlay-stays-until-the-game-runs.md)).
  With hundreds of add-ons most of it is their Lua and file lookups, the same for every map (R24, R26).

## Decision

1. **What is recorded.** Each load the overlay followed to its end (the game ran steadily, or the 120 s limit) is
   recorded with:
   - when it happened;
   - the map (lower case, letters, digits and `_-.+`, at most 64 characters), and for a server joined, the server's
     name (one line, at most 64 bytes);
   - flags: the first load of this game start, a server joined, and whether the wait hit the limit;
   - the add-ons mounted (`engine.GetAddons()`) and the map's size (`file.Size("maps/<map>.bsp", "GAME")`);
   - the engine's load in seconds, and the wait after it.
   Not recorded: a load that ended without a game, a game that ended or a load that followed before it settled, a demo,
   and anything while `nativeloader_load_overlay` is 0. The overlay only exists in RTX starts, so every record is one.
2. **Where.** `garrysmod/data/nativeloader/load_times.txt`: tab-separated, a version in each line, newest last, at
   most ten loads per map (and server) and 200 in all, about 20 KB. The menu realm cannot write files (RESEARCH, R26),
   so the engine guard's menu copy reads it (`LoadTimes()`) and replaces it (`LoadTimesSave(text)`: at most 64 KiB, no
   NUL, written to a temporary file and moved over the old one). The path is the module's own; only the menu realm has
   these functions. Lines the script cannot read are left out and not written back; deleting the file starts afresh.
3. **The estimate** (pure Lua in the menu script, `NativeLoaderLoadStatus.Eta`, tested by the harness):
   - Only loads of the same kind count: a server joined, or a game started here.
   - **This map's own loads first** (and this server's, for a server joined): its newest five. The estimate is the
     median of each phase, so one load that went wrong does not move it. Each load is first scaled to today:
     - the add-on count, by (150 + now) / (150 + then), held within [0.5, 2]: a load's fixed part is worth about 150
       add-ons (772 add-ons took 17-28 s, a bare game a few seconds; RESEARCH);
     - the first load of a game start, against later ones, by this machine's own ratio. It is learned from maps
       loaded both ways (else from all first and later loads), held within [0.75, 3].
     The estimate is **good** when at least two loads agree within 60 % and none needed a far scaling (an add-on
     count more than 15 % off, or a first-load state not learned yet). Otherwise it is **rough**.
   - **A map not loaded before** takes the machine's newest twelve maps, one point per map (its median), so a map
     loaded often does not decide alone. With three or more sizes known, a line through them fits the map's size
     (Theil-Sen: the median of the pairs' slopes, never negative, at most 0.5 s per megabyte). **Rough.**
   - **No load of the same kind**: no estimate.
   - Held to 1-900 s for the engine's load and 0-600 s for the wait after it.
4. **Shown** ([`load_eta.h`](../../engine_guard/load_eta.h)). The main thread is blocked for most of a load, so the
   module counts down by itself: `LoadExpect(seconds, confidence)` gives it the whole wait's expected length from the
   load's start. The script passes it:
   - at the start, with the machine's estimate while the map is unknown;
   - when `GameDetails` names the map: the map's own estimate;
   - when the engine's load ends: its actual length plus the wait expected after it.
   The window's second row:
   - a bar, from where it stands toward 97 % at the expected end. It never goes back. Past the end it creeps toward
     99.5 % and turns amber.
   - "about N s left", in steps of five seconds from 20 s, or "about N min left" from 90 s;
   - "(rough estimate)" after a rough one;
   - "Taking longer than usual" past the end;
   - without an estimate, "No estimate yet: this load is timed for the next one".
   A translation fills its one `%s` in the module (anything else falls back to the English). The words come from the
   companion's catalogs in seven languages.
5. **Learning from overruns.** Every timed load is recorded, overruns included, and the median of the newest five
   follows them. A wait cut at the limit is recorded with its flag (a lower bound). Older loads drop out at ten per map.

## Consequences

- The first load after the update shows no estimate. A map's first load shows a rough one from the machine's other
  maps.
- The history is the install's: two games of one install running at once may overwrite each other's last load (the
  last writer wins).
- The add-on scaling and the first-load factor are priors where the history is thin; with five loads of a map they only
  matter when the add-on count or the first-load state changes.
- The console line ends with the estimate the player saw ("expected about 30 s"), so a bad estimate can be reported.

## Alternatives considered

- **An exponentially weighted average:** one bad load (a Windows update scan, a shader cache rebuild) moves it for
  several loads; the median of five does not, and the window of five still follows a lasting change within three
  loads.
- **A regression over every feature** (map, add-ons, size, first load): a player has a few dozen loads, too few to fit
  many parameters robustly. The map's own median does the work, and the features only scale it.
- **A fixed first guess** ("about 30 s") with no history: a made-up number. The window says the load is being timed
  instead.
- **Keeping the history in the client realm or the loader:** the client realm does not see the engine's load (it starts
  during it), and the loader's state is the loader's (a loader change, which needs the user's approval).
