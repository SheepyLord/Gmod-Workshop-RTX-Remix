# world.lua

Client helper included by `debris.lua`. `Begin(budget, gravity)` requires `nlglass` and opens
`maps/<map>.bsp` in binary mode through the `GAME` search path. `BeginLoadMapFile` receives the size
and a synchronous range reader. Lua seeks, checks the position, reads and closes the handle on success
or failure. The native module owns the selected bytes before the call returns. Its worker parses the
collision data and cooks the static world. With a DLL from before the update, Lua uses its existing
`BeginLoadMap(bytes)` entry point up to that DLL's 256 MiB limit. On larger maps the notice explains
that restarting will load the updated module.

`Tick` polls without waiting,
then extracts two unique prop collision models or adds 64 instances per frame through a coroutine.
The final broadphase optimization also uses `BeginFinishWorld`/`PollFinishWorld` on a worker.
Temporary `ClientsideModel` objects use `PhysicsInit`/`GetMeshConvexes` and are always removed.
Missing, over-complex or refused models/convexes/instances are skipped and counted. A structural
BSP error or a finished map without usable collision selects simpler physics. `MsgN` prints the
first line of the reason once per map, including across pane arrivals, cleanup and Lua refresh.
`Must`, `Fail`, `Shutdown` are internal helpers; shutdown joins workers before releasing their
world, and resets for the next client realm. No disk writes, network or server code; no exit code.
