# 0238: The Model Hotloader's map-start work: done once, and its warm characters after the map runs

- Status: Accepted 2026-11-16 (the user chose items H1, H2 and H3 of the second load speed-up plan: "H1, A2, H2, H3")
- Decided by: the agents, from the field measurements of the plan
  (`out/load-speedup-2/PLAN.md` in the main checkout); package only: the Model Hotloader's Lua in
  `packages/model-hotloader`. No native module, loader or runtime change.
- Supersedes in part: [0099](0099-saved-characters-load-on-first-use.md), only *when* the characters kept ready are
  made ready in a game a player hosts (at the map's start, before; now once the map runs). Which characters, how many,
  and that the others load at their first use, stand.
- Report: [load-speedup-2-report.md](../handover/load-speedup-2-report.md).

## Context

In the user's field game (787 Workshop add-ons, 206 imported characters, 93 of them approved) every map load took
88-95 s warm, whatever the map and whether it was a game start's first load or a later one. Over half of it was the
Model Hotloader's map-start work, all of it on the main thread:

- **The library built 94 times.** The client asks the server for its catalog from `InitPostEntity`; the server sends one
  `mmdhl_catalog` message per approved character (`sharing.lua`, `catalog`), and the client's receiver called
  `library.Refresh()` for each. A build reads and decodes every character's `manifest.json` (206 files, 32.5 MB of
  JSON). 94 builds: 19,364 reads, 3.05 GB of JSON, 51 s in `util.JSONToTable`, in one frame of 54 s. In single-player
  the build does not even use the catalog (`library.Refresh` reads `mmdhl.sharedAssets` only outside single-player).
  An A/B in the user's game with only the builds coalesced (in game memory): modern_house 92.4 -> 39.7 s, a second
  load 88.2 -> 33.3 s.
- **Every saved rig decoded twice by the server.** `MMDHL.RestorePublishedActors` (server `InitPostEntity`) first runs
  `PruneRigs`, which decodes each approved rig's `rig.json` for its group, then decodes them all again for the
  restoration: 298 rigs of about 230 KB, about 1 s a pass.
- **The warm characters in the load.** The memory profile "high" keeps the ten most recently used characters ready at a
  map's start (ADR 0099): mounted and precached, which loads their textures (3.9 GiB of material archives here) while
  the player waits, about 4 s on the server's side of the load and part of the client's precache after it.

## Decision

1. **One library build for a burst of catalog messages, none for a single-player catalog.** `library.RequestRefresh()`
   builds the library on the next tick, once however often it is asked before then. The two catalog receivers
   (`mmdhl_catalog`, `mmdhl_catalog_forget`) ask through it, and in single-player not at all. The catalog's network
   messages are unchanged, so a server and a client of different versions still understand each other.
2. **Manifests decoded once.** `library.Refresh()` keeps each character's decoded manifest with its file's size and time
   and decodes only a manifest it has not seen or that changed (an asset's folder is named by its content's hash, so a
   manifest is written once). The decoded tables are shared between builds: nothing writes into an entry's `info`.
   Settings files are read at every build as before (small, and a rename can keep the size within a second).
3. **Each saved rig decoded once at a map start.** `PruneRigs` and the restoration share one table of decoded rigs
   (`readRig`).
4. **Warm characters once the map runs, in a game a player hosts.** `mmdhl.RestoreActors` publishes every saved entry
   from metadata at the map's start. On a dedicated server the chosen ones are made ready at once, as before (nobody is
   waiting). In single-player and on a listen server they are queued, newest use first, and made ready one character
   (all its entries) at a time: the first 5 s after the host's client asks for the catalog (its `InitPostEntity`), then
   one every 3 s; 90 s after the map's start at the latest. A character used before its turn is made ready at that
   use, as any other entry; its turn then does nothing. The console says when the queue is done ("Saved characters
   ready while the map runs: N entries (M characters) in T s").

## Consequences

- A modern_house load in the user's game (measured, the map command to the load overlay's end line): 25.5-29.8 s
  instead of 96.3 s (a control the same hour; 91.6-92.4 s in the plan's runs), gm_construct after it 28.7-30.8 s
  instead of 88.8 s. Decision 1 alone had given 39.7 s in the plan's A/B; decisions 2-4 took the server's and the
  client's phases of the load from about 16 s each to 9-12 s each.
- In the first seconds of a map (5 s plus 3 s a character, about 35 s for ten), a character kept ready may not be ready
  yet: spawning it then loads it first, as for every other saved character (a second or a few). The guide's sentence
  "When a map starts, your most recently used characters are loaded in advance" still holds and is unchanged.
- The characters made ready while the map runs are hitches: the server's part took 3.7 s for ten characters (0.37 s
  each on average); with the client's loading of their materials, the largest showed as one stretch of 1.4 s of the
  main thread, the others under 0.25 s or below 85 % of a core. They are spaced 3 s apart so that the load overlay's
  two steady seconds can pass between them; the player can move between them.
- `mmdhl.readiness.Describe()` also reports the deferred entries and the characters still waiting.
- Multiplayer: a remote client still receives every registration as before; a listen server's host's catalog request
  starts the queue, a joining player's does not.

## Alternatives considered

- **Fewer warm characters at a map's start** (three for "high"): keeps part of the cost in the load and loses the rest
  of the warm set; deferring keeps them all.
- **One catalog message for the whole catalog** (as the props catalog sends 32 per message): fewer messages, but a
  protocol change between servers and clients of different versions, and the client would still build per message
  without decision 1.
- **Decoding rigs lazily** (published entries from a small summary, the full rig at first use): would also save the
  client's 0.8 s of rig decoding, but every reader of `entry.rig` would have to change; left for later.
