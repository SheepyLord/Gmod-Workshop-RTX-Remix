# client.lua: Client composition root

Included by the companion after native readiness. Returns Session.Start(native, onError, units), Stop(), Recenter(). Starts the fixed core, hud, hands, move, ui, weapons (44), reload (46), tools (48), interact list; stops in reverse. Partial startup is cleaned by the page. The local package deploys the nlvr add-on for both SP and listen hosts; these files need no AddCSLuaFile or remote distribution. No autorun, native start/stop, engine convar writes or file writes.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

V6 adds `perf` ([cl_perf.lua](modules/cl_perf.lua.md)) at the end of the fixed list; it starts last (order 60).
