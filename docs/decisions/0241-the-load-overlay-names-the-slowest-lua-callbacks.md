# 0241: The load overlay names the slowest Lua callbacks of a load

- Status: Accepted 2026-11-17 (the user: "Let's also do the remaining 6 points in the plan"; item D2 of the second load
  speed-up plan)
- Decided by: the agents; package only: the `load-accelerator` part's add-on
  (`fs_accel/addon/lua/nlloadaccel/load_callbacks.lua`) and the companion's load overlay (`menu/loading_status.lua`).
- Report: [load-speedup-3-report.md](../handover/load-speedup-3-report.md).

## Context

The load overlay (ADR 0134) names "the Lua files that ran longest" from the file names GMod keeps on the stack while a
file runs. A hook, a timer or a net receiver runs later, from a file that has finished, and leaves no name there. The
second round's largest cost, a frame of 54 s after `InitPostEntity`, was one net receiver (the Model Hotloader's
`mmdhl_catalog`, called 94 times) that the overlay could not name; finding it took a Lua probe and a sampler. The lag
report (ADR 0143) times hooks and receivers, but only for a window a player starts by command, in a running game.

## Decision

1. **While a realm's Lua starts and its map loads** (from the load accelerator add-on's autorun, the first of every
   realm, until 10 s after `InitPostEntity`; 900 s at the latest) every function registered through `hook.Add`,
   `timer.Simple`, `timer.Create` and `net.Receive` is wrapped in a timer (`SysTime()` around the call; arguments and
   results pass through; the render guard's record of timed functions gets each wrapper, as for the lag report).
2. **Then the originals go back** where the wrappers still are (the registration functions, each hook through the lag
   report's `swap`, ULib's table included, each net receiver); a wrapper left in a timer only passes the call on.
3. **The slowest are named**: a console line per realm (five at most, 0.1 s or more, with the source line and the
   add-on), and `data/nativeloader/load_callbacks_<realm>.txt` (written as soon as a call takes 0.25 s, then at the end),
   from which the load overlay's end-of-load line adds "Lua callbacks that ran longest: ..." (the three longest of at
   least 0.5 s across both realms, from files of this load only).
4. **Switch:** `nativeloader_load_accel_callbacks` (archived, 1).

## Consequences

- The next add-on that holds a load in a callback is named in the player's own console and in the overlay's line, which
  bug reports carry. Its first field run named the Model Hotloader's `MMDHL.RestorePublishedActors` (server,
  1.4-1.9 s), its `mmdhl_actor_registration` receiver (0.8-0.9 s, 151 calls) and Bullet Break Simulator's Think
  `BBS.ProcessRagdollMeshPrewarm` (2.3-2.4 s over the load's frames).
- During the load each wrapped call costs two `SysTime()` calls and a few table updates; after it, nothing (the
  originals are back).
- Callbacks registered before the add-on's autorun (GMod's own includes and gamemode) and entity, weapon and panel
  methods are not timed; a time includes what the callback calls.

## Alternatives considered

- **Replacing `hook.Call`:** one wrapper for every event, but it would have to repeat GMod's (and ULib's) dispatch.
- **Native sampling of the Lua stack:** the engine guard's sampler sees only files being run.
- **Keeping the wrappers for the session:** an extra frame in every hook's traceback and its source for every
  inspection, for numbers nobody reads after the load.
