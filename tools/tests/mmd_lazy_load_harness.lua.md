# mmd_lazy_load_harness.lua

LuaJIT harness for R13-A's load-on-first-use regression, invoked by
[test_mmd_lazy_load.py](test_mmd_lazy_load.py.md). Arguments: the generated production snippet, the
packaged `lua/mmdhl` folder, and one scenario: `server_none`, `server_budget`, `server_convar`,
`server_first_use`, `server_fallback`, `server_map_change`, `server_forget`, `server_dedicated`,
`server_host_ready`, `client_host`, `client_remote`, `server_workshop_update` or `client_workshop_choice`.

`server_workshop_update` reads the host's Workshop state and refits its saved Citizen, player and
hands. It checks the registered NPC spawn, the previous player selector, exact recent timestamps
and an unrelated rig. The duplicator loads the old model and materials in single player. After a
server withdraws the old approval, a paste uses the approved revision. With both approvals gone
it fails. `client_workshop_choice` waits for the new player model to register and respects a later
manual selection.

The fixture library has four characters (archives of 500, 700, 4000 and 300 MiB), one with a player
model and its arms, saved approvals and a use record. Disk reads and writes, `game.MountGMA`,
`util.PrecacheModel` (which refuses a model that is not mounted), list and player-model entries,
network messages, ConVars, timers and entities are instrumented; binding (native attachment and
appearance) is reduced to its boundary, as in the R12-A harness. `server_map_change` reloads the four
files with the engine's own `SetModel`/`PrecacheModel`/`IsValidModel`, as a new map's Lua state has
them.

[ADR 0238](../../docs/decisions/0238-the-hotloaders-map-start-work-once-and-after-the-map-runs.md): in a game a
player hosts (the harness's default, `game.IsDedicated()` false) the characters kept ready are queued at the map's
start and made ready once the map runs; `warm()` starts the queue as the host's catalog request does
(`mmdhl.readiness.HostReady()`), runs its first turn and drains the rest. `server_dedicated` checks that a dedicated
server still makes them ready at the map's start; `server_host_ready` that the queue makes one character (all its
entries) ready per turn, newest use first; that a second `HostReady` starts no second queue; that a character used
before its turn is made ready at that use and its turn prepares nothing again; that the queue's timer goes and its end
line is printed when it is done; and that without the host's ask the fallback starts the queue. Writes stdout only. Exit 0 with `PASS <scenario>`, otherwise nonzero with the failed assertion.
