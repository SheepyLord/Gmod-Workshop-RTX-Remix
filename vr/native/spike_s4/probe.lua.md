# probe.lua

Runs the disposable [module.cpp](module.cpp) from `poc_session.py --lua`. Requires that the test
DLL has been staged as `garrysmod/lua/bin/gmcl_nlvrs4_win64.dll` after a PoC snapshot, and an RTX
map session under the shared PoC and VR locks. Creates one 333 by 197 render target and, for 120
frames, queues markers before, during and after a raster draw into it. At frame 145 removes its
hook and prints `NL_S4_RECORDS` JSON plus `NL_SHOT_DONE`. Records include caller/execution thread
IDs, observed render-target dimensions, invocation and release counts. Prints the actual
`mat_queue_mode` and layout first. No cvar, disk file or setting is changed by this driver. Roll
back the session with the normal PoC snapshot workflow. There is no process exit status; failures
are Lua errors or missing marker records in the session console evidence.
