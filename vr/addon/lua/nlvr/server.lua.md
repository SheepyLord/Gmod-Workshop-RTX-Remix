# server.lua: Server composition root

Included by the companion stub for the eligible local player only. Returns SV.Start(ply, scale), Stop(ply), Receive(type, bits, ply). The fixed modules are move and interact. Including alone installs nothing; the last Stop unloads all session resources.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

V4 adds fixed weapons/reload/tools descriptors (orders 44/46/48), initially empty. They are included only with the same lazy local-host server activation; remote distribution is unchanged.
