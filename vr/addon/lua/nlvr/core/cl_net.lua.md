# cl_net.lua: Client sync

New(core,protocol) returns Start, Stop, Sync, On(type,reader), Send(type,writer). Start notifies the local server with the scale and installs one nlvr receiver; Stop sends STOP and removes the client receiver. Sync is called from the core CreateMove, at most once per engine tick after a valid head exists, from raw target poses in world space, never collision-resolved shown hands. A scale change re-sends START without resetting server history. Module writers take the bounded net-shaped buffer described in sh_protocol.lua.md. Module readers use global net.Read* and are owned by the registering module. No separate timer, hooks or file writes.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

Once a head has been sampled, invalid tracking is still sent explicitly; it must not strand the last usable server pose.

Stop removes its receiver even if sending STOP fails during game-channel shutdown, then reports that send error through resource cleanup.

Integration: reuses Debug.net rather than allocating a debug table per sync.
